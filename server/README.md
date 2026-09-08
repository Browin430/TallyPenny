# 智能记账 · AI 后端服务

FastAPI + 通义千问（DashScope），为 Flutter App 提供 AI 能力：账单解析（文本 / 语音 / 截图）与财务顾问。

## 快速开始

```bash
# 1. 安装依赖
pip install -r requirements.txt -i https://mirrors.aliyun.com/pypi/simple/

# 2. 配置 API Key
copy .env.example .env    # 然后编辑 .env 填入 DASHSCOPE_API_KEY

# 3. 启动（或直接双击 start_server.bat）
python main.py            # 默认 0.0.0.0:8765
```

## 端点

| 方法 | 路径 | 入参 | 出参 |
|------|------|------|------|
| GET | `/health` | — | `{status, hasApiKey, models}` |
| POST | `/api/parse/text` | JSON `{text, referenceTime?}` | `{referenceTime, candidate}` |
| POST | `/api/parse/audio` | multipart `file`（wav/mp3/m4a…）+ `referenceTime?` | `{transcript, referenceTime, candidate}` |
| POST | `/api/parse/screenshot` | multipart `file`（png/jpg/webp…）+ `referenceTime?` | `{ocrText, referenceTime, candidate}` |
| POST | `/api/jobs/screenshots` | multipart `files`（最多 10 张） | 持久化后台截图任务 |
| POST | `/api/jobs/audio` | multipart `file` + `durationSeconds` | 持久化后台语音任务 |
| POST | `/api/jobs/statements` | multipart `files`（支付宝 CSV / 微信 XLSX，最多 5 个） | 持久化账单文件导入任务 |
| GET | `/api/jobs/{jobId}` | — | 查询任务状态与结果 |
| DELETE | `/api/jobs/{jobId}` | — | 消费后清理任务结果 |
| POST | `/api/advisor` | JSON `{question, snapshot?}` | `{answer, disclaimer}` |

## candidate 契约（与 Flutter `TransactionCandidate` 对齐）

```json
{
  "sourceType": "text",
  "confidence": 0.9,
  "type": "expense",
  "amountCents": 2850,
  "currency": "CNY",
  "categoryId": "food",
  "subcategory": null,
  "merchant": "美团",
  "description": "外卖",
  "transactionTime": "2026-08-28T12:30:00",
  "timeConfident": true,
  "paymentMethod": "alipay",
  "note": null,
  "parseWarnings": []
}
```

- `amountCents`：整数分（¥28.5 → 2850），识别不出为 `null` 并在 `parseWarnings` 说明。
- `categoryId` 必须在白名单内（18 支出 + 7 收入，见 `prompts.py`），越界自动落 `other`/`other_income`。
- `transactionTime` 为无时区本地时间；`timeConfident=false` 时 App 端展示"时间待确认"。

## 模型

| 用途 | 默认模型 | 环境变量 |
|------|----------|----------|
| 文本解析 / 顾问 | qwen-plus | `QWEN_TEXT_MODEL` |
| 截图 OCR | qwen-vl-plus（部分账号 qwen-vl-max-latest 未开通） | `QWEN_VL_MODEL` |
| 语音转写 | qwen3-asr-flash（失败兜底 paraformer-realtime-v2） | `QWEN_ASR_MODEL` |

## 手动验证

```bash
curl http://127.0.0.1:8765/health

curl -X POST http://127.0.0.1:8765/api/parse/text ^
  -H "Content-Type: application/json" ^
  -d "{\"text\": \"今天中午在美团花了28块5吃外卖\", \"referenceTime\": \"2026-08-28T18:00:00\"}"

curl -X POST http://127.0.0.1:8765/api/parse/audio -F "file=@test.wav"
curl -X POST http://127.0.0.1:8765/api/parse/screenshot -F "file=@pay.png"

curl -X POST http://127.0.0.1:8765/api/advisor ^
  -H "Content-Type: application/json" ^
  -d "{\"question\": \"我这个月还能花多少钱？\", \"snapshot\": {\"monthlyBudgetCents\": 800000, \"spentCents\": 520000}}"
```

> 真机访问：手机与电脑同一 Wi-Fi，App 内服务器地址填电脑局域网 IP（`ipconfig` 查看），如 `http://192.168.x.x:8765`。
