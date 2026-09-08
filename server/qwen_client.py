"""通义千问客户端：文本生成（JSON）/ 语音识别（qwen3-asr-flash）/ 图片理解（qwen-vl）。

调用模式与 Javis 语音备忘录项目保持一致：
- 文本：dashscope.Generation.call(messages=..., result_format="message")
- ASR：dashscope.MultiModalConversation.call(model=qwen3-asr-flash, content=[{"type":"audio",...}])
- 图片：dashscope.MultiModalConversation.call(model=qwen-vl-*, content=[{"type":"image",...}])
"""

from __future__ import annotations

import base64
import json
import re
from http import HTTPStatus
from pathlib import Path
from typing import Any

from config import QWEN_ASR_MODEL, QWEN_TEXT_MODEL, QWEN_VL_MODEL, configure_dashscope

MIME_BY_SUFFIX = {
    "wav": "audio/wav",
    "mp3": "audio/mpeg",
    "aac": "audio/aac",
    "m4a": "audio/mp4",
    "ogg": "audio/ogg",
    "opus": "audio/opus",
    "flac": "audio/flac",
}


class QwenError(RuntimeError):
    """千问调用失败（网络 / key / 内容审查等）。"""


def chat(
    messages: list[dict[str, str]],
    *,
    model: str = QWEN_TEXT_MODEL,
    temperature: float = 0.3,
    json_mode: bool = False,
) -> str:
    """文本生成，返回 assistant 文本。"""
    dashscope = configure_dashscope()
    kwargs: dict[str, Any] = {
        "api_key": dashscope.api_key,
        "model": model,
        "messages": messages,
        "result_format": "message",
        "temperature": temperature,
    }
    if json_mode:
        kwargs["response_format"] = {"type": "json_object"}
    try:
        response = dashscope.Generation.call(**kwargs)
    except Exception as exc:  # 网络等
        raise QwenError(f"千问调用异常: {exc}") from exc

    if response.status_code != HTTPStatus.OK:
        raise QwenError(f"千问返回错误: {response.code} {response.message}")

    output = response.output
    choices = output.get("choices", []) if isinstance(output, dict) else getattr(output, "choices", [])
    if not choices:
        raise QwenError("千问返回空结果")
    message = choices[0].get("message", {}) if isinstance(choices[0], dict) else choices[0].message
    content = message.get("content", "") if isinstance(message, dict) else message.content
    return (content or "").strip()


def chat_json(messages: list[dict[str, str]], *, model: str = QWEN_TEXT_MODEL, temperature: float = 0.2) -> dict[str, Any]:
    """文本生成并解析为 JSON 对象（容忍 ```json 围栏与前后杂质）。"""
    raw = chat(messages, model=model, temperature=temperature, json_mode=True)
    return parse_json_object(raw)


def parse_json_object(raw: str) -> dict[str, Any]:
    text = raw.strip()
    # 剥掉 ```json ... ``` 围栏。
    fence = re.search(r"```(?:json)?\s*(.+?)\s*```", text, re.DOTALL)
    if fence:
        text = fence.group(1).strip()
    try:
        payload = json.loads(text)
    except json.JSONDecodeError:
        # 兜底：截取第一个 { 到最后一个 }。
        start, end = text.find("{"), text.rfind("}")
        if start < 0 or end <= start:
            raise ValueError(f"无法解析 JSON: {raw[:200]}")
        payload = json.loads(text[start : end + 1])
    if not isinstance(payload, dict):
        raise ValueError(f"JSON 顶层不是对象: {raw[:200]}")
    return payload


def _b64_data_url(path: Path, kind: str) -> str:
    mime_map = {
        "png": "image/png", "jpg": "image/jpeg", "jpeg": "image/jpeg",
        "webp": "image/webp", "heic": "image/heic", "bmp": "image/bmp",
    }
    suffix = path.suffix.lower().lstrip(".")
    if kind == "audio":
        mime = MIME_BY_SUFFIX.get(suffix, "audio/wav")
    else:
        mime = mime_map.get(suffix, "image/jpeg")
    b64 = base64.b64encode(path.read_bytes()).decode()
    return f"data:{mime};base64,{b64}"


def transcribe_audio(audio_path: Path, *, model: str = QWEN_ASR_MODEL) -> str:
    """语音转文字（qwen3-asr-flash，base64 data-url，与参考项目一致）。"""
    dashscope = configure_dashscope()
    messages = [
        {
            "role": "user",
            "content": [{"type": "audio", "audio": _b64_data_url(audio_path, "audio")}],
        }
    ]
    try:
        response = dashscope.MultiModalConversation.call(
            model=model, messages=messages, result_format="message"
        )
    except Exception as exc:
        raise QwenError(f"语音识别调用异常: {exc}") from exc

    if response.status_code != HTTPStatus.OK:
        raise QwenError(f"语音识别失败: {response.message}")

    return _extract_text(response) or ""


def understand_image(image_path: Path, prompt: str, *, model: str = QWEN_VL_MODEL) -> str:
    """图片理解（qwen-vl），返回 assistant 文本（可要求 JSON）。"""
    dashscope = configure_dashscope()
    messages = [
        {
            "role": "user",
            "content": [
                {"type": "image", "image": _b64_data_url(image_path, "image")},
                {"type": "text", "text": prompt},
            ],
        }
    ]
    try:
        response = dashscope.MultiModalConversation.call(
            model=model, messages=messages, result_format="message"
        )
    except Exception as exc:
        raise QwenError(f"图片理解调用异常: {exc}") from exc

    if response.status_code != HTTPStatus.OK:
        raise QwenError(f"图片理解失败: {response.message}")

    return _extract_text(response) or ""


def vision_json(image_path: Path, prompt: str, *, model: str = QWEN_VL_MODEL) -> dict[str, Any]:
    return parse_json_object(understand_image(image_path, prompt, model=model))


def _extract_text(response: Any) -> str:
    """从 MultiModalConversation 响应中拼接全部文本片段。"""
    output = response.output
    choices = output.get("choices", []) if isinstance(output, dict) else getattr(output, "choices", [])
    if not choices:
        return ""
    message = choices[0].get("message", {}) if isinstance(choices[0], dict) else choices[0].message
    content = message.get("content", []) if isinstance(message, dict) else message.content
    parts: list[str] = []
    for item in content or []:
        if isinstance(item, dict):
            text = item.get("text", "")
            if text:
                parts.append(text)
        elif isinstance(item, str):
            parts.append(item)
    return "".join(parts).strip()
