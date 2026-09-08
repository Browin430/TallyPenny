"""配置加载：.env + 千问模型名。参考 Javis 语音备忘录项目的 configure_dashscope 模式。"""

from __future__ import annotations

import os
from pathlib import Path
from typing import Any


def load_env_file(path: Path) -> None:
    """轻量 .env 加载（不覆盖已有环境变量）。"""
    if not path.exists():
        return
    for raw in path.read_text(encoding="utf-8").splitlines():
        line = raw.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, _, value = line.partition("=")
        key = key.strip()
        value = value.strip().strip('"').strip("'")
        if key and key not in os.environ:
            os.environ[key] = value


SERVER_DIR = Path(__file__).resolve().parent
load_env_file(SERVER_DIR / ".env")

# ---- 模型 ----
QWEN_TEXT_MODEL = os.getenv("QWEN_TEXT_MODEL", "qwen-plus")
QWEN_VL_MODEL = os.getenv("QWEN_VL_MODEL", "qwen-vl-max-latest")
QWEN_ASR_MODEL = os.getenv("QWEN_ASR_MODEL", "qwen3-asr-flash")

FM_SERVER_PORT = int(os.getenv("FM_SERVER_PORT", "8765"))
FM_API_TOKEN = os.getenv("FM_API_TOKEN", "").strip()


def configure_dashscope() -> Any:
    """配置并返回 dashscope 模块；key 缺失时抛 RuntimeError。"""
    api_key = os.getenv("DASHSCOPE_API_KEY", "").strip()
    if not api_key or api_key.startswith("your_"):
        raise RuntimeError("缺少 DASHSCOPE_API_KEY，请在 server/.env 中配置通义千问 API Key")
    try:
        import dashscope
    except ImportError as exc:  # pragma: no cover
        raise RuntimeError("缺少 dashscope 依赖：pip install -r requirements.txt") from exc

    base_url = os.getenv("DASHSCOPE_BASE_URL")
    if base_url:
        dashscope.base_http_api_url = base_url.rstrip("/")
    dashscope.api_key = api_key
    return dashscope


def has_api_key() -> bool:
    key = os.getenv("DASHSCOPE_API_KEY", "").strip()
    return bool(key) and not key.startswith("your_")


def has_client_token() -> bool:
    """公网 API 是否已启用客户端访问令牌。"""
    return len(FM_API_TOKEN) >= 24
