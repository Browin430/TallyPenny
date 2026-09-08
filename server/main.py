"""TallyPenny（智能记账）后端服务 —— FastAPI + 通义千问。

端点：
- GET  /health               健康检查
- POST /api/parse/text       文本 → TransactionCandidate JSON
- POST /api/parse/audio      语音文件（multipart）→ {transcript, candidate}
- POST /api/parse/screenshot 截图文件（multipart）→ {ocrText, candidate}
- POST /api/advisor          {question, snapshot} → {answer, disclaimer}

启动：python main.py  或  uvicorn main:app --host 0.0.0.0 --port 8765
配置：同目录 .env（参考 .env.example），必填 DASHSCOPE_API_KEY。
"""

from __future__ import annotations

import difflib
import json
import re
import secrets
import shutil
import sqlite3
import threading
import uuid
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timedelta
from pathlib import Path
from tempfile import NamedTemporaryFile
from typing import Any

from fastapi import FastAPI, File, Form, HTTPException, Request, UploadFile
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from pydantic import BaseModel, Field
from starlette.concurrency import run_in_threadpool

import qwen_client
from config import (
    FM_API_TOKEN,
    FM_SERVER_PORT,
    QWEN_ASR_MODEL,
    QWEN_TEXT_MODEL,
    QWEN_VL_MODEL,
    has_api_key,
    has_client_token,
)
from prompts import (
    EXPENSE_CATEGORIES,
    INCOME_CATEGORIES,
    SCREENSHOT_OCR_PROMPT,
    build_advisor_messages,
    build_multi_parse_messages,
    build_parse_messages,
    build_voice_command_messages,
)
from statement_parser import StatementParseError, parse_statement_file, platform_label

app = FastAPI(title="TallyPenny AI Server", version="0.1.0")

# Flutter Web 预览跨域访问（移动端不受 CORS 约束）。
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)


@app.middleware("http")
async def require_api_token(request: Request, call_next):
    """公网业务接口必须携带 App 的访问令牌；健康检查保持公开。"""
    if request.method != "OPTIONS" and request.url.path.startswith("/api/"):
        supplied = request.headers.get("X-API-Key", "")
        if not FM_API_TOKEN or not secrets.compare_digest(supplied, FM_API_TOKEN):
            return JSONResponse(status_code=401, content={"detail": "无效的访问令牌"})
    return await call_next(request)

MAX_UPLOAD_BYTES = 15 * 1024 * 1024  # 15MB
MAX_SCREENSHOTS_PER_JOB = 10
AUDIO_SUFFIXES = {".wav", ".mp3", ".aac", ".m4a", ".ogg", ".opus", ".flac"}
IMAGE_SUFFIXES = {".png", ".jpg", ".jpeg", ".webp", ".heic", ".bmp"}
STATEMENT_SUFFIXES = {".csv", ".xlsx"}

SERVER_DIR = Path(__file__).resolve().parent
JOB_DATA_DIR = SERVER_DIR / "job_data"
JOB_DB_PATH = SERVER_DIR / "recognition_jobs.sqlite3"
JOB_EXECUTOR = ThreadPoolExecutor(max_workers=2, thread_name_prefix="tallypenny-job")
VISION_SEMAPHORE = threading.BoundedSemaphore(3)
UPLOAD_CHUNK_BYTES = 1024 * 1024
_SCHEDULED_JOB_IDS: set[str] = set()
_SCHEDULED_LOCK = threading.Lock()

DISCLAIMER = "以上为一般性参考，不构成投资建议。"


# ---- 请求 / 响应模型 ----

class ParseTextRequest(BaseModel):
    text: str = Field(min_length=1, max_length=2000)
    referenceTime: str | None = None  # ISO 时间；缺省用服务器当前时间
    merchantRules: list[dict[str, Any]] | None = None  # 用户商户偏好


class AdvisorRequest(BaseModel):
    question: str = Field(min_length=1, max_length=500)
    snapshot: dict[str, Any] | None = None


# ---- 工具 ----

def _now_iso() -> str:
    return datetime.now().strftime("%Y-%m-%dT%H:%M:%S")


def _normalize_reference_time(value: str | None) -> str:
    """把前端传入的 ISO 时间（可能带 Z / 时区）规整为本地无时区格式。"""
    if not value:
        return _now_iso()
    try:
        cleaned = value.strip().replace("Z", "+00:00")
        dt = datetime.fromisoformat(cleaned)
        if dt.tzinfo is not None:
            dt = dt.astimezone()  # 转服务器本地时区
        return dt.strftime("%Y-%m-%dT%H:%M:%S")
    except ValueError:
        return _now_iso()


def _understand_image_limited(path: Path, prompt: str) -> str:
    """限制全局视觉模型并发，避免多份长截图同时切片造成内存/连接尖峰。"""
    with VISION_SEMAPHORE:
        return qwen_client.understand_image(path, prompt)


def _sanitize_candidate(raw: dict[str, Any]) -> dict[str, Any]:
    """对模型输出做契约校验与清洗：白名单外的 categoryId 落到 other，金额强制 int/None。"""
    candidate = dict(raw)
    warnings = list(candidate.get("parseWarnings") or [])

    amount = candidate.get("amountCents")
    if amount is not None:
        try:
            # 收支方向由 type 表达，金额恒为正；模型偶发输出的负号会
            # 破坏 App 端展示，也会让长图分割的相似账单合并漏配。
            candidate["amountCents"] = abs(int(round(float(amount))))
        except (TypeError, ValueError):
            candidate["amountCents"] = None
            warnings.append("模型返回的金额格式异常，已置空")

    category = candidate.get("categoryId")
    valid_ids = {cid for cid, _ in EXPENSE_CATEGORIES + INCOME_CATEGORIES}
    if category not in valid_ids:
        if category is not None:
            warnings.append(f"模型返回了白名单外的分类 {category!r}，已改为 other")
        candidate["categoryId"] = "other"
        if candidate.get("type") == "income":
            candidate["categoryId"] = "other_income"

    candidate["type"] = "income" if candidate.get("type") == "income" else "expense"
    if candidate["type"] == "expense":
        merchant = str(candidate.get("merchant") or "")
        description = str(candidate.get("description") or "")
        subcategory = str(candidate.get("subcategory") or "")
        probe = f"{merchant} {description} {subcategory}"
        # 对确定性很高的平台/商品规则做最终兜底，避免模型把明显账单放入“其他”。
        hardware_words = (
            "螺丝钉", "螺丝刀", "螺丝", "螺母", "垫片", "紧固件",
            "五金", "扳手", "钳子", "钻头",
        )
        if "小遛" in probe:
            candidate["categoryId"] = "transport"
            candidate["subcategory"] = "共享电动车"
        elif any(word in probe for word in hardware_words):
            candidate["categoryId"] = "shopping"
            candidate["subcategory"] = "五金工具"
        elif "滴滴" in merchant or "滴滴出行" in probe:
            candidate["categoryId"] = "transport"
        elif (
            "美团" in merchant
            and description.strip()
            and candidate.get("categoryId") in (None, "other")
        ):
            candidate["categoryId"] = "food"
        elif candidate.get("categoryId") in (None, "other") and any(
            word in probe
            for word in (
                "餐饮", "餐厅", "餐馆", "饭店", "酒楼", "食府", "菜馆", "私房菜",
                "小吃", "快餐", "便当", "食堂", "早餐", "夜宵", "重庆小面", "小面",
                "面馆", "拉面", "牛肉面", "刀削面", "米线", "米粉", "螺蛳粉",
                "酸辣粉", "麻辣烫", "冒菜", "火锅", "串串", "烧烤", "烤肉", "烤鱼",
                "酸菜鱼", "馄饨", "云吞", "饺子", "包子", "粥铺", "盖饭", "炒饭",
                "汉堡", "炸鸡", "披萨", "寿司", "料理", "咖啡", "奶茶", "茶饮",
                "果汁", "鲜榨", "饮品", "烘焙", "蛋糕", "甜品", "面包店", "外卖",
            )
        ):
            candidate["categoryId"] = "food"
    candidate["currency"] = str(candidate.get("currency") or "CNY")
    candidate["timeConfident"] = bool(candidate.get("timeConfident", False))
    candidate["parseWarnings"] = warnings
    return candidate


UPDATE_FIELD_KEYS = {
    "type", "amountCents", "currency", "categoryId", "subcategory",
    "merchant", "description", "transactionTime", "timeConfident",
    "paymentMethod", "note",
}


def _parse_merchant_rules_field(raw: str | None) -> list[dict[str, Any]]:
    """Form 字段里的 merchantRules JSON → 列表；坏输入容错为空表。"""
    if not raw:
        return []
    try:
        data = json.loads(raw)
    except json.JSONDecodeError:
        return []
    if not isinstance(data, list):
        return []
    return [item for item in data if isinstance(item, dict)][:50]


def _merchant_match(pattern: str, merchant: str) -> bool:
    """与 App 端 MerchantRuleMatcher 同语义：归一化精确 > 互包含（短边≥2字）。"""
    def norm(value: str) -> str:
        return "".join(value.split()).lower()

    a, b = norm(pattern), norm(merchant)
    if not a or not b:
        return False
    if a == b:
        return True
    shorter, longer = (a, b) if len(a) < len(b) else (b, a)
    return len(shorter) >= 2 and shorter in longer


def _apply_merchant_rules(
    candidate: dict[str, Any],
    merchant_rules: list[dict[str, Any]] | None,
) -> dict[str, Any]:
    """用户商户偏好的确定性兜底：即使模型忽略 prompt 也保证分类正确。"""
    if not merchant_rules:
        return candidate
    merchant = str(candidate.get("merchant") or "").strip()
    if not merchant:
        return candidate
    valid_ids = {cid for cid, _ in EXPENSE_CATEGORIES + INCOME_CATEGORIES}
    best: tuple[int, str] | None = None  # (pattern 长度, categoryId)
    for rule in merchant_rules:
        pattern = str(rule.get("merchant") or "").strip()
        category = str(rule.get("categoryId") or "").strip()
        if not pattern or category not in valid_ids:
            continue
        if _merchant_match(pattern, merchant) and (
            best is None or len(pattern) > best[0]
        ):
            best = (len(pattern), category)
    if best is not None and candidate.get("categoryId") != best[1]:
        candidate = dict(candidate)
        candidate["categoryId"] = best[1]
    return candidate


def _sanitize_update_fields(raw: dict[str, Any]) -> tuple[dict[str, Any], list[str]]:
    """修改指令只保留白名单内且模型明确给出的字段——绝不补默认值覆盖原账单。"""
    fields: dict[str, Any] = {}
    warnings: list[str] = []
    valid_ids = {cid for cid, _ in EXPENSE_CATEGORIES + INCOME_CATEGORIES}
    for key, value in raw.items():
        if key not in UPDATE_FIELD_KEYS or value is None:
            continue
        if key == "amountCents":
            try:
                value = int(round(float(value)))
            except (TypeError, ValueError):
                warnings.append("修改金额格式异常，已忽略")
                continue
        elif key == "categoryId" and value not in valid_ids:
            warnings.append(f"修改分类 {value!r} 不在白名单，已忽略")
            continue
        elif key == "type" and value not in ("expense", "income"):
            continue
        elif key == "timeConfident":
            value = bool(value)
        fields[key] = value
    if not fields:
        warnings.append("没有可应用的修改字段")
    return fields, warnings


def _run_parse(
    content: str,
    reference_time: str | None,
    source_type: str,
    merchant_rules: list[dict[str, Any]] | None = None,
) -> dict[str, Any]:
    ref = _normalize_reference_time(reference_time)
    try:
        payload = qwen_client.chat_json(
            build_parse_messages(content, ref, merchant_rules),
            model=QWEN_TEXT_MODEL,
        )
    except qwen_client.QwenError as exc:
        raise HTTPException(status_code=502, detail=str(exc)) from exc
    except ValueError as exc:
        raise HTTPException(status_code=502, detail=f"模型输出无法解析: {exc}") from exc
    candidate = _apply_merchant_rules(_sanitize_candidate(payload), merchant_rules)
    # Flutter TransactionCandidate 必需字段：来源与置信度由端点决定（模型不输出）。
    candidate["sourceType"] = source_type
    candidate["confidence"] = 0.85
    return {
        "referenceTime": ref,
        "candidate": candidate,
    }


def _run_parse_many(
    content: str,
    reference_time: str | None,
    source_type: str,
    merchant_rules: list[dict[str, Any]] | None = None,
) -> list[dict[str, Any]]:
    """多笔解析（账单列表截图）：输出 candidates 数组。"""
    ref = _normalize_reference_time(reference_time)
    try:
        payload = qwen_client.chat_json(
            build_multi_parse_messages(content, ref, merchant_rules),
            model=QWEN_TEXT_MODEL,
        )
    except qwen_client.QwenError as exc:
        raise HTTPException(status_code=502, detail=str(exc)) from exc
    except ValueError as exc:
        raise HTTPException(status_code=502, detail=f"模型输出无法解析: {exc}") from exc

    records = payload.get("records") if isinstance(payload, dict) else None
    if isinstance(payload, list):
        records = payload
    if not isinstance(records, list) or not records:
        raise HTTPException(status_code=422, detail="未能从截图中解析出账单记录")
    # 兼容模型输出单对象
    if isinstance(records, dict):
        records = [records]

    candidates: list[dict[str, Any]] = []
    for item in records:
        if not isinstance(item, dict):
            continue
        candidate = _apply_merchant_rules(_sanitize_candidate(item), merchant_rules)
        candidate["sourceType"] = source_type
        candidate["confidence"] = 0.85
        candidates.append(candidate)
    if not candidates:
        raise HTTPException(status_code=422, detail="未能从截图中解析出有效账单记录")
    return candidates


async def _save_upload(file: UploadFile, allowed: set[str], kind: str) -> Path:
    suffix = Path(file.filename or "").suffix.lower()
    if suffix not in allowed:
        raise HTTPException(status_code=415, detail=f"不支持的{kind}格式: {suffix or '(无后缀)'}")
    tmp = NamedTemporaryFile(suffix=suffix, delete=False)
    path = Path(tmp.name)
    total = 0
    try:
        while chunk := await file.read(UPLOAD_CHUNK_BYTES):
            total += len(chunk)
            if total > MAX_UPLOAD_BYTES:
                raise HTTPException(status_code=413, detail=f"{kind}文件超过 15MB 限制")
            tmp.write(chunk)
        if total == 0:
            raise HTTPException(status_code=400, detail=f"{kind}文件为空")
        return path
    except Exception:
        tmp.close()
        path.unlink(missing_ok=True)
        raise
    finally:
        if not tmp.closed:
            tmp.close()


# ---- 端点 ----

@app.get("/health")
def health() -> dict[str, Any]:
    return {
        "status": "ok",
        "hasApiKey": has_api_key(),
        "clientAuthEnabled": has_client_token(),
        "models": {
            "text": QWEN_TEXT_MODEL,
            "vision": QWEN_VL_MODEL,
            "asr": QWEN_ASR_MODEL,
        },
    }


@app.post("/api/parse/text")
def parse_text(req: ParseTextRequest) -> dict[str, Any]:
    return _run_parse(req.text.strip(), req.referenceTime, "text", req.merchantRules)


@app.post("/api/parse/audio")
async def parse_audio(
    file: UploadFile = File(...),
    referenceTime: str | None = Form(default=None),
    merchantRules: str | None = Form(default=None),
) -> dict[str, Any]:
    audio_path = await _save_upload(file, AUDIO_SUFFIXES, "音频")
    try:
        try:
            transcript = qwen_client.transcribe_audio(audio_path)
        except qwen_client.QwenError:
            if QWEN_ASR_MODEL == "qwen3-asr-flash":
                # 主模型失败 → paraformer 兜底（与参考项目一致）。
                transcript = qwen_client.transcribe_audio(audio_path, model="paraformer-realtime-v2")
            else:
                raise
    except qwen_client.QwenError as exc:
        raise HTTPException(status_code=502, detail=str(exc)) from exc
    finally:
        audio_path.unlink(missing_ok=True)

    transcript = transcript.strip()
    if not transcript:
        raise HTTPException(status_code=422, detail="语音识别结果为空")
    result = _run_parse(
        transcript,
        referenceTime,
        "voice",
        _parse_merchant_rules_field(merchantRules),
    )
    return {"transcript": transcript, **result}


@app.post("/api/parse/screenshot")
async def parse_screenshot(
    file: UploadFile = File(...),
    referenceTime: str | None = Form(default=None),
    merchantRules: str | None = Form(default=None),
) -> dict[str, Any]:
    image_path = await _save_upload(file, IMAGE_SUFFIXES, "图片")
    try:
        ref = _normalize_reference_time(referenceTime)
        # 视觉模型 SDK 是同步阻塞调用。放入工作线程，避免长图处理期间占住
        # FastAPI 事件循环，导致健康检查和其他用户请求也一起超时。
        ocr_text, candidates = await run_in_threadpool(
            _process_screenshot_path,
            image_path,
            ref,
            _parse_merchant_rules_field(merchantRules),
        )
        candidates, cancelled_refund_pairs = _cancel_balanced_pairs(candidates)
    finally:
        image_path.unlink(missing_ok=True)

    return {
        "ocrText": ocr_text,
        "referenceTime": ref,
        "candidates": candidates,
        "cancelledRefundPairs": cancelled_refund_pairs,
        # 兼容旧客户端：单数 candidate 为第一笔。
        "candidate": candidates[0] if candidates else None,
    }


def _process_screenshot_path(
    image_path: Path,
    reference_time: str,
    merchant_rules: list[dict[str, Any]] | None = None,
) -> tuple[str, list[dict[str, Any]]]:
    """同步处理单张截图；供同步端点和持久化后台任务共同调用。"""
    parts: list[Path] | None = None
    try:
        parts = _split_long_image(image_path)
        if parts is None:
            try:
                ocr_text = _understand_image_limited(
                    image_path,
                    SCREENSHOT_OCR_PROMPT,
                ).strip()
            except qwen_client.QwenError as exc:
                raise HTTPException(status_code=502, detail=str(exc)) from exc
            if not ocr_text or "未识别到账单信息" in ocr_text:
                raise HTTPException(status_code=422, detail="图中未识别到账单信息")
            candidates = _run_parse_many(
                ocr_text, reference_time, "screenshot", merchant_rules
            )
            return ocr_text, candidates

        return _recognize_slices(parts, reference_time, merchant_rules)
    finally:
        for part in parts or []:
            part.unlink(missing_ok=True)


# ---- 长截图分割识别 ----
# qwen-vl 对输入图有总像素上限，超限会整图等比压缩 → 长截屏文字糊成噪点。
# 实测（754px 宽账单截图）：单片 ≤ ~2.7MP 时 OCR 全部可读，整图 10.2MP 直接失败。

SLICE_TARGET_PIXELS = 2_200_000  # 单片像素预算（留出压缩余量）
SLICE_MIN_HEIGHT = 1600
SLICE_MAX_HEIGHT = 3000
SLICE_OVERLAP_RATIO = 0.25       # 相邻片重叠 1/4，重叠区重复账单靠合并去重
SLICE_MAX_WORKERS = 4
SLICE_EDGE_TRIM_PX = 140         # 重试时向内修边的像素（≈ 一个账单行高）


def _plan_slice_boxes(width: int, height: int) -> list[tuple[int, int]]:
    """规划垂直切割窗口 [(top, bottom), ...]；短图返回整图一片。

    切割带重叠（上一片尾部 ≅ 下一片头部），配合相似账单合并可保证
    任何一条账单至少完整出现在一个切片里、且不会重复入库。
    """
    if width <= 0 or height <= 0:
        return [(0, max(height, 1))]
    slice_h = SLICE_TARGET_PIXELS // width
    slice_h = max(SLICE_MIN_HEIGHT, min(SLICE_MAX_HEIGHT, slice_h))
    if height <= slice_h * 3 // 2:
        return [(0, height)]

    overlap = int(slice_h * SLICE_OVERLAP_RATIO)
    step = slice_h - overlap
    boxes: list[tuple[int, int]] = []
    top = 0
    while True:
        bottom = min(top + slice_h, height)
        boxes.append((top, bottom))
        if bottom >= height:
            break
        nxt = top + step
        if height - nxt <= overlap:
            # 剩余高度已完全落入下一个重叠区 → 当前片直接延伸到图片底部，避免碎片。
            boxes[-1] = (top, height)
            break
        top = nxt
    return boxes


def _split_long_image(path: Path) -> list[Path] | None:
    """长图按窗口切割为若干临时 JPEG；无需切割返回 None。失败抛 HTTPException。"""
    try:
        from PIL import Image, ImageOps

        with Image.open(path) as im:
            im = ImageOps.exif_transpose(im)
            boxes = _plan_slice_boxes(im.width, im.height)
            if len(boxes) <= 1:
                return None
            parts: list[Path] = []
            try:
                for top, bottom in boxes:
                    crop = im.crop((0, top, im.width, bottom)).convert("RGB")
                    tmp = NamedTemporaryFile(suffix=".jpg", delete=False)
                    tmp.close()
                    crop.save(tmp.name, format="JPEG", quality=92)
                    parts.append(Path(tmp.name))
                return parts
            except Exception:
                for part in parts:
                    part.unlink(missing_ok=True)
                raise
    except HTTPException:
        raise
    except Exception as exc:
        raise HTTPException(status_code=422, detail=f"图片无法解码: {exc}") from exc


def _candidates_similar(a: dict[str, Any], b: dict[str, Any]) -> bool:
    """相邻切片重叠区的同一笔账单：金额一致 + 时间不冲突 + 商户相同/相近。"""
    amount = a.get("amountCents")
    if amount is None or amount != b.get("amountCents"):
        return False
    if a.get("type") != b.get("type"):
        return False

    time_a, time_b = a.get("transactionTime"), b.get("transactionTime")
    if time_a and time_b and time_a != time_b:
        # 时间冲突：仅认定为切片边缘残缺行的"幻影"（时间抄自相邻行）才合并。
        # 约束极严：同日 + 金额相同 + 商户一方为另一方的边缘截断形态。
        if time_a[:10] != time_b[:10]:
            return False
        return _is_edge_truncation(
            (a.get("merchant") or "").strip(), (b.get("merchant") or "").strip()
        )

    merchant_a = (a.get("merchant") or "").strip()
    merchant_b = (b.get("merchant") or "").strip()
    if merchant_a and merchant_b:
        if merchant_a == merchant_b or merchant_a in merchant_b or merchant_b in merchant_a:
            return True
        return difflib.SequenceMatcher(None, merchant_a, merchant_b).ratio() >= 0.6
    # 商户缺失时要求时间双方都在且一致，避免把正常重复消费误合并。
    return bool(time_a and time_b and time_a == time_b)


def _is_edge_truncation(merchant_a: str, merchant_b: str) -> bool:
    """商户一方是另一方的"边缘截断"形态（被切片边界切掉的残缺行）。

    等长（如同日两笔"宁波地铁"）或短侧自带列表省略号的都是真实两行；
    只有严格包含且短侧无省略号、长度足以排除通用短名时才算残缺幻影。
    """
    if not merchant_a or not merchant_b:
        return False
    short, long_ = (
        (merchant_a, merchant_b)
        if len(merchant_a) <= len(merchant_b)
        else (merchant_b, merchant_a)
    )
    if short == long_ or len(short) < 6:
        return False
    if short.endswith(("...", "…")):
        return False
    return short in long_


def _merge_duplicate_candidates(candidates: list[dict[str, Any]]) -> list[dict[str, Any]]:
    """按图片顺序合并相邻切片重叠区产生的重复账单。

    候选账单需带 `_slice`（来源切片序号，由 _recognize_slices 打标）；只有
    相邻切片的相似账单才合并，避免把不同切片里恰好雷同的真实两笔误伤。
    """
    merged: list[dict[str, Any]] = []
    for cand in candidates:
        dup = next(
            (
                m
                for m in merged
                if abs(m["_slice"] - cand["_slice"]) == 1 and _candidates_similar(m, cand)
            ),
            None,
        )
        if dup is None:
            merged.append(cand)
            continue
        ignored_refund = _is_refund_candidate(dup) or _is_refund_candidate(cand)
        # 同一笔被两片都识别到：补齐缺失字段；文本字段优先保留更完整的一份，
        # 避免先遇到切片边缘的残缺商户名后丢掉下一片中的完整名称。
        for key, value in cand.items():
            if key in ("_slice", "parseWarnings"):
                continue
            if dup.get(key) in (None, "") and value not in (None, ""):
                dup[key] = value
            elif (
                key in {"merchant", "description", "subcategory", "note"}
                and isinstance(value, str)
                and isinstance(dup.get(key), str)
                and _text_completeness(value) > _text_completeness(dup[key])
            ):
                dup[key] = value
        if cand.get("timeConfident") and not dup.get("timeConfident"):
            dup["transactionTime"] = cand.get("transactionTime") or dup.get("transactionTime")
            dup["timeConfident"] = True
        warnings = set(dup.get("parseWarnings") or []) | set(cand.get("parseWarnings") or [])
        dup["parseWarnings"] = sorted(warnings)
        if ignored_refund and not _is_refund_candidate(dup):
            # 较长的普通备注不能覆盖另一切片读到的退款状态。
            dup["note"] = f"{dup.get('note') or ''} 已全额退款".strip()

    for cand in merged:
        cand.pop("_slice", None)
    return merged


def _text_completeness(value: str) -> tuple[int, int]:
    """文本完整度：无省略号优先，其次取信息量更大的较长文本。"""
    cleaned = value.strip()
    truncated = cleaned.endswith(("...", "…"))
    return (0 if truncated else 1, len(cleaned))


def _cancel_balanced_pairs(
    candidates: list[dict[str, Any]],
) -> tuple[list[dict[str, Any]], int]:
    """忽略退款记录，避免只有退款没有原订单时虚增收入。"""
    refunds = {
        index for index, candidate in enumerate(candidates)
        if _is_refund_candidate(candidate)
    }
    return (
        [candidate for index, candidate in enumerate(candidates) if index not in refunds],
        len(refunds),
    )


def _is_refund_candidate(candidate: dict[str, Any]) -> bool:
    probe = " ".join(
        str(candidate.get(key) or "")
        for key in ("categoryId", "merchant", "description", "note", "subcategory")
    )
    compact = re.sub(r"\s+", "", probe)
    if any(status in compact for status in ("已全额退款", "已全退款", "全额退款成功", "全额已退款")):
        return True
    return candidate.get("type") == "income" and (
        candidate.get("categoryId") == "refund" or "退款" in probe
    )


def _ocr_slice_with_retry(path: Path) -> str:
    """切片 OCR，带"向内修边"重试。

    视觉模型遇到图片边缘被裁断一半的残缺行时，偶发对整片输出
    "未识别到账单信息"。修掉的边缘必然落在相邻切片的重叠区内
    （首片顶边是状态栏、末片底边是源图自身的残缺行），不会丢账单。
    """
    attempts = [(0, 0), (0, SLICE_EDGE_TRIM_PX), (SLICE_EDGE_TRIM_PX, 0),
                (SLICE_EDGE_TRIM_PX, SLICE_EDGE_TRIM_PX)]
    last = ""
    for trim_top, trim_bottom in attempts:
        if trim_top <= 0 and trim_bottom <= 0:
            text = _understand_image_limited(path, SCREENSHOT_OCR_PROMPT).strip()
        else:
            text = _ocr_trimmed(path, trim_top, trim_bottom)
        last = text
        if text and "未识别到账单信息" not in text:
            return text
    return last


def _ocr_trimmed(path: Path, trim_top: int, trim_bottom: int) -> str:
    """裁掉切片上下边缘后 OCR（临时文件，用完即删）。"""
    from PIL import Image

    with Image.open(path) as im:
        bottom = max(im.height - trim_bottom, trim_top + 1)
        crop = im.crop((0, trim_top, im.width, bottom)).convert("RGB")
        tmp = NamedTemporaryFile(suffix=".jpg", delete=False)
        tmp.close()
        crop.save(tmp.name, format="JPEG", quality=92)
    trimmed = Path(tmp.name)
    try:
        return _understand_image_limited(trimmed, SCREENSHOT_OCR_PROMPT).strip()
    finally:
        trimmed.unlink(missing_ok=True)


def _recognize_slices(
    parts: list[Path],
    ref: str,
    merchant_rules: list[dict[str, Any]] | None = None,
) -> tuple[str, list[dict[str, Any]]]:
    """并行识别各切片 → 合并账单。单片失败不影响其余切片，全部失败才报错。"""

    def run(slice_index: int, part: Path) -> tuple[int, str, list[dict[str, Any]]]:
        text = _ocr_slice_with_retry(part)
        if not text or "未识别到账单信息" in text:
            return slice_index, text, []
        try:
            return slice_index, text, _run_parse_many(text, ref, "screenshot", merchant_rules)
        except HTTPException as exc:
            if exc.status_code >= 500:
                raise
            return slice_index, text, []  # 该片可读但无账单（如页眉/空白区）

    results: list[tuple[int, str, list[dict[str, Any]]]] = []
    errors: list[str] = []
    with ThreadPoolExecutor(max_workers=min(SLICE_MAX_WORKERS, len(parts))) as pool:
        futures = [pool.submit(run, index, part) for index, part in enumerate(parts)]
        for future in futures:
            try:
                results.append(future.result())
            except (qwen_client.QwenError, HTTPException) as exc:
                errors.append(str(getattr(exc, "detail", None) or exc))

    results.sort(key=lambda result: result[0])
    texts = [text for _, text, _ in results if text]
    if errors and not texts:
        raise HTTPException(status_code=502, detail=f"图片识别失败: {errors[0]}")
    if not texts:
        raise HTTPException(status_code=422, detail="图中未识别到账单信息")

    candidates: list[dict[str, Any]] = []
    for slice_index, _, items in results:
        for item in items:
            item["_slice"] = slice_index
            candidates.append(item)
    candidates = _merge_duplicate_candidates(candidates)
    if not candidates:
        raise HTTPException(status_code=422, detail="未能从截图中解析出账单记录")
    return "\n".join(texts).strip(), candidates


# ---- 可退出 App 的持久化后台识别任务 ----

def _job_connection() -> sqlite3.Connection:
    connection = sqlite3.connect(JOB_DB_PATH, timeout=30)
    connection.row_factory = sqlite3.Row
    return connection


def _init_job_store() -> None:
    JOB_DATA_DIR.mkdir(parents=True, exist_ok=True)
    with _job_connection() as connection:
        connection.execute("PRAGMA journal_mode=WAL")
        connection.execute(
            """
            CREATE TABLE IF NOT EXISTS recognition_jobs (
                id TEXT PRIMARY KEY,
                kind TEXT NOT NULL,
                status TEXT NOT NULL,
                estimate_seconds INTEGER NOT NULL,
                input_json TEXT NOT NULL,
                result_json TEXT,
                error TEXT,
                created_at TEXT NOT NULL,
                updated_at TEXT NOT NULL
            )
            """
        )


def _insert_job(
    job_id: str,
    kind: str,
    estimate_seconds: int,
    payload: dict[str, Any],
) -> None:
    now = _now_iso()
    with _job_connection() as connection:
        connection.execute(
            """
            INSERT INTO recognition_jobs
                (id, kind, status, estimate_seconds, input_json, created_at, updated_at)
            VALUES (?, ?, 'queued', ?, ?, ?, ?)
            """,
            (
                job_id,
                kind,
                estimate_seconds,
                json.dumps(payload, ensure_ascii=False),
                now,
                now,
            ),
        )


def _set_job_state(
    job_id: str,
    status: str,
    *,
    result: dict[str, Any] | None = None,
    error: str | None = None,
) -> None:
    with _job_connection() as connection:
        connection.execute(
            """
            UPDATE recognition_jobs
            SET status = ?, result_json = ?, error = ?, updated_at = ?
            WHERE id = ?
            """,
            (
                status,
                json.dumps(result, ensure_ascii=False) if result is not None else None,
                error,
                _now_iso(),
                job_id,
            ),
        )


def _schedule_job(job_id: str) -> None:
    with _SCHEDULED_LOCK:
        if job_id in _SCHEDULED_JOB_IDS:
            return
        _SCHEDULED_JOB_IDS.add(job_id)
    future = JOB_EXECUTOR.submit(_run_recognition_job, job_id)

    def release(_: object) -> None:
        with _SCHEDULED_LOCK:
            _SCHEDULED_JOB_IDS.discard(job_id)

    future.add_done_callback(release)


def _run_recognition_job(job_id: str) -> None:
    with _job_connection() as connection:
        row = connection.execute(
            "SELECT * FROM recognition_jobs WHERE id = ?",
            (job_id,),
        ).fetchone()
    if row is None or row["status"] not in {"queued", "processing"}:
        return

    payload = json.loads(row["input_json"])
    _set_job_state(job_id, "processing")
    try:
        if row["kind"] == "screenshot":
            texts: list[str] = []
            candidates: list[dict[str, Any]] = []
            image_errors: list[str] = []
            reference_time = str(payload.get("referenceTime") or _now_iso())
            screenshot_rules = payload.get("merchantRules")
            for raw_path in payload.get("paths") or []:
                try:
                    text, items = _process_screenshot_path(
                        Path(raw_path), reference_time, screenshot_rules
                    )
                    texts.append(text)
                    candidates.extend(items)
                except HTTPException as exc:
                    image_errors.append(str(exc.detail))
            if not candidates:
                detail = image_errors[0] if image_errors else "未识别到账单记录"
                raise HTTPException(status_code=422, detail=detail)
            candidates, cancelled_refund_pairs = _cancel_balanced_pairs(candidates)
            result = {
                "ocrText": "\n\n".join(texts),
                "candidates": candidates,
                "candidate": candidates[0] if candidates else None,
                "imageErrors": image_errors,
                "cancelledRefundPairs": cancelled_refund_pairs,
            }
        elif row["kind"] == "audio":
            result = _process_voice_command_path(
                Path(payload["path"]),
                payload.get("recentTransactions"),
                payload.get("merchantRules"),
            )
        elif row["kind"] == "statement":
            candidates = []
            platforms: list[str] = []
            file_errors: list[str] = []
            skipped = 0
            for raw_path in payload.get("paths") or []:
                try:
                    parsed = parse_statement_file(Path(raw_path))
                    candidates.extend(parsed["candidates"])
                    skipped += int(parsed["skipped"])
                    label = platform_label(parsed["platform"])
                    if label not in platforms:
                        platforms.append(label)
                except StatementParseError as exc:
                    file_errors.append(str(exc))
            if not candidates:
                detail = file_errors[0] if file_errors else "账单文件中没有可导入记录"
                raise HTTPException(status_code=422, detail=detail)
            candidates, cancelled_refund_pairs = _cancel_balanced_pairs(candidates)
            result = {
                "sourceSummary": "、".join(platforms),
                "platforms": platforms,
                "candidates": candidates,
                "fileErrors": file_errors,
                "skipped": skipped,
                "cancelledRefundPairs": cancelled_refund_pairs,
            }
        else:
            raise RuntimeError(f"不支持的任务类型: {row['kind']}")
        _set_job_state(job_id, "completed", result=result)
    except Exception as exc:
        detail = getattr(exc, "detail", None) or str(exc) or exc.__class__.__name__
        _set_job_state(job_id, "failed", error=str(detail)[:1000])
    finally:
        shutil.rmtree(JOB_DATA_DIR / job_id, ignore_errors=True)


def _estimate_screenshot_seconds(paths: list[Path]) -> int:
    from PIL import Image, ImageOps

    estimate = 0.0
    for path in paths:
        try:
            with Image.open(path) as image:
                image = ImageOps.exif_transpose(image)
                pixels = image.width * image.height
        except Exception:
            pixels = max(path.stat().st_size * 4, 1_000_000)
        # 视觉 OCR + 结构化解析；像素越高，切片和模型调用越多。
        estimate += 12 + pixels / 260_000
    return max(15, min(600, int(round(estimate))))


def _estimate_audio_seconds(duration_seconds: int) -> int:
    # ASR 时长大致随音频长度增长，之后还需一次意图/账单结构化解析。
    return max(12, min(300, int(round(12 + duration_seconds * 0.8))))


def _estimate_statement_seconds(paths: list[Path]) -> int:
    total_bytes = sum(path.stat().st_size for path in paths)
    return max(5, min(60, int(round(5 + total_bytes / 500_000))))


async def _save_job_upload(
    upload: UploadFile,
    allowed: set[str],
    kind: str,
    destination: Path,
) -> Path:
    suffix = Path(upload.filename or "").suffix.lower()
    if suffix not in allowed:
        raise HTTPException(status_code=415, detail=f"不支持的{kind}格式: {suffix or '(无后缀)'}")
    destination.parent.mkdir(parents=True, exist_ok=True)
    destination = destination.with_suffix(suffix)
    total = 0
    try:
        with destination.open("wb") as output:
            while chunk := await upload.read(UPLOAD_CHUNK_BYTES):
                total += len(chunk)
                if total > MAX_UPLOAD_BYTES:
                    raise HTTPException(
                        status_code=413,
                        detail=f"{kind}文件超过 15MB 限制",
                    )
                output.write(chunk)
        if total == 0:
            raise HTTPException(status_code=400, detail=f"{kind}文件为空")
        return destination
    except Exception:
        destination.unlink(missing_ok=True)
        raise


@app.on_event("startup")
def recover_recognition_jobs() -> None:
    """服务重启后重新排队未完成任务，保证 App 退出或服务器重启都不丢。"""
    _init_job_store()
    with _job_connection() as connection:
        # 客户端异常退出后可能来不及 DELETE；自动清理七天前的终态结果，
        # 避免识别结果 JSON 长期占用服务器磁盘。
        cutoff = (datetime.now() - timedelta(days=7)).strftime("%Y-%m-%dT%H:%M:%S")
        connection.execute(
            "DELETE FROM recognition_jobs "
            "WHERE status IN ('completed', 'failed') AND updated_at < ?",
            (cutoff,),
        )
        connection.execute(
            "UPDATE recognition_jobs SET status = 'queued', updated_at = ? "
            "WHERE status = 'processing'",
            (_now_iso(),),
        )
        rows = connection.execute(
            "SELECT id FROM recognition_jobs WHERE status = 'queued' ORDER BY created_at",
        ).fetchall()
    for row in rows:
        _schedule_job(row["id"])


@app.post("/api/jobs/screenshots", status_code=202)
async def create_screenshot_job(
    files: list[UploadFile] = File(...),
    referenceTime: str | None = Form(default=None),
    merchantRules: str | None = Form(default=None),
) -> dict[str, Any]:
    if not files or len(files) > MAX_SCREENSHOTS_PER_JOB:
        raise HTTPException(
            status_code=400,
            detail=f"每次请选择 1–{MAX_SCREENSHOTS_PER_JOB} 张截图",
        )
    job_id = uuid.uuid4().hex
    job_dir = JOB_DATA_DIR / job_id
    paths: list[Path] = []
    try:
        for index, upload in enumerate(files):
            paths.append(
                await _save_job_upload(
                    upload,
                    IMAGE_SUFFIXES,
                    "图片",
                    job_dir / f"screenshot-{index}",
                )
            )
        estimate = _estimate_screenshot_seconds(paths)
        _insert_job(
            job_id,
            "screenshot",
            estimate,
            {
                "paths": [str(path) for path in paths],
                "referenceTime": _normalize_reference_time(referenceTime),
                "merchantRules": _parse_merchant_rules_field(merchantRules),
            },
        )
        _schedule_job(job_id)
        return {
            "jobId": job_id,
            "kind": "screenshot",
            "status": "queued",
            "estimateSeconds": estimate,
            "fileCount": len(paths),
        }
    except Exception:
        shutil.rmtree(job_dir, ignore_errors=True)
        raise


@app.post("/api/jobs/audio", status_code=202)
async def create_audio_job(
    file: UploadFile = File(...),
    durationSeconds: int = Form(default=1),
    recentTransactions: str | None = Form(default=None),
    merchantRules: str | None = Form(default=None),
) -> dict[str, Any]:
    job_id = uuid.uuid4().hex
    job_dir = JOB_DATA_DIR / job_id
    try:
        path = await _save_job_upload(
            file,
            AUDIO_SUFFIXES,
            "音频",
            job_dir / "audio",
        )
        duration = max(1, min(durationSeconds, 3600))
        estimate = _estimate_audio_seconds(duration)
        _insert_job(
            job_id,
            "audio",
            estimate,
            {
                "path": str(path),
                "durationSeconds": duration,
                "recentTransactions": recentTransactions,
                "merchantRules": _parse_merchant_rules_field(merchantRules),
            },
        )
        _schedule_job(job_id)
        return {
            "jobId": job_id,
            "kind": "audio",
            "status": "queued",
            "estimateSeconds": estimate,
            "fileCount": 1,
        }
    except Exception:
        shutil.rmtree(job_dir, ignore_errors=True)
        raise


@app.post("/api/jobs/statements", status_code=202)
async def create_statement_job(
    files: list[UploadFile] = File(...),
) -> dict[str, Any]:
    if not files or len(files) > 5:
        raise HTTPException(status_code=400, detail="每次请选择 1–5 个账单文件")
    job_id = uuid.uuid4().hex
    job_dir = JOB_DATA_DIR / job_id
    paths: list[Path] = []
    try:
        for index, upload in enumerate(files):
            paths.append(
                await _save_job_upload(
                    upload,
                    STATEMENT_SUFFIXES,
                    "账单",
                    job_dir / f"statement-{index}",
                )
            )
        estimate = _estimate_statement_seconds(paths)
        _insert_job(
            job_id,
            "statement",
            estimate,
            {"paths": [str(path) for path in paths]},
        )
        _schedule_job(job_id)
        return {
            "jobId": job_id,
            "kind": "statement",
            "status": "queued",
            "estimateSeconds": estimate,
            "fileCount": len(paths),
        }
    except Exception:
        shutil.rmtree(job_dir, ignore_errors=True)
        raise


@app.get("/api/jobs/{job_id}")
def get_recognition_job(job_id: str) -> dict[str, Any]:
    with _job_connection() as connection:
        row = connection.execute(
            "SELECT * FROM recognition_jobs WHERE id = ?",
            (job_id,),
        ).fetchone()
    if row is None:
        raise HTTPException(status_code=404, detail="任务不存在或已清理")
    status = row["status"]
    return {
        "jobId": row["id"],
        "kind": row["kind"],
        "status": status,
        "estimateSeconds": row["estimate_seconds"],
        "progress": {"queued": 0, "processing": 35, "completed": 100, "failed": 100}.get(status, 0),
        "result": json.loads(row["result_json"]) if row["result_json"] else None,
        "error": row["error"],
        "createdAt": row["created_at"],
        "updatedAt": row["updated_at"],
    }


@app.delete("/api/jobs/{job_id}")
def delete_recognition_job(job_id: str) -> dict[str, bool]:
    with _job_connection() as connection:
        connection.execute("DELETE FROM recognition_jobs WHERE id = ?", (job_id,))
    shutil.rmtree(JOB_DATA_DIR / job_id, ignore_errors=True)
    return {"deleted": True}


@app.post("/api/advisor")
def advisor(req: AdvisorRequest) -> dict[str, Any]:
    snapshot_json = json.dumps(req.snapshot or {}, ensure_ascii=False)
    messages = build_advisor_messages(req.question.strip(), snapshot_json)
    try:
        answer = qwen_client.chat(messages, model=QWEN_TEXT_MODEL, temperature=0.5)
    except qwen_client.QwenError as exc:
        raise HTTPException(status_code=502, detail=str(exc)) from exc
    return {"answer": answer, "disclaimer": DISCLAIMER}
