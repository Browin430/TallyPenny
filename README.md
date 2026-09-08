# FlowMoney（智账）

AI 智能个人财务管理 App。Flutter 一套代码覆盖 iOS / Android / Web 预览，配套 FastAPI 后端提供通义千问 AI 能力：文本 / 语音 / 截图账单解析、账单文件导入与财务顾问。

## 功能特性

- **多方式记一笔**：手动输入、语音描述、支付截图 OCR、账单文件导入（支付宝 CSV / 微信 XLSX）、周期账单。
- **统一入账管线**：所有输入经 归一化 → AI 分类 → 去重检测 → 置信度评估 → 保存 / 请求确认（`domain/pipeline/`）。
- **智能去重**：可配置的阈值与权重（`core/constants/app_constants.dart`），避免重复入账。
- **财务顾问**：基于当前账目快照的 AI 问答（预算、消费建议）。
- **本地持久化**：移动端 sqflite；Web 预览使用内存仓库 + 演示数据。
- **数据安全**：原始数据永不丢失（`transaction_sources` 保留 raw_text / ocr_result / ai_parse_result），删除为软删除。

## 项目结构

```
├── lib/                  # Flutter 前端（Clean Architecture）
│   ├── core/             # 设计系统（theme/）、通用组件（widgets/）、工具
│   ├── domain/           # models/ 实体与枚举、repositories/ 与 services/ 抽象接口、pipeline/
│   ├── data/             # database/ sqflite schema、dao/、repositories/ 实现、services/ Mock AI
│   ├── services/         # 纯 Dart 应用服务：去重引擎、洞察计算、演示数据
│   └── presentation/     # navigation/ + 各页面（home/ transactions/ analysis/ profile/ entry/ detail/）
├── server/               # Python 后端（FastAPI + 通义千问/DashScope）
├── android/  ios/  web/  # 平台宿主
├── test/                 # Flutter 单元测试
├── docs/design.md        # 设计文档
└── design/               # 启动图标等设计源文件
```

依赖方向：presentation → (domain ← data)。所有 AI / OCR / 语音能力走 `domain/services` 接口，
当前实现为 `data/services` 下的 Mock，`server/` 为真实 AI 服务实现，可在 App 内配置服务器地址接入。

## 快速开始

### 前端（Flutter）

```bash
flutter pub get
flutter run -d edge      # Web 预览：内存仓库 + 演示数据，无需移动端工具链
flutter run              # Android / iOS：sqflite 持久化
```

App 内「服务器地址」填后端地址（如 `http://192.168.x.x:8765`）即可启用真实 AI 能力；
不配置时使用本地 Mock 服务。

### 后端（FastAPI）

```bash
cd server
pip install -r requirements.txt -i https://mirrors.aliyun.com/pypi/simple/
copy .env.example .env   # 编辑 .env 填入 DASHSCOPE_API_KEY
python main.py           # 默认 0.0.0.0:8765（或双击 start_server.bat）
```

真机访问：手机与电脑同一 Wi-Fi，App 内填电脑局域网 IP。详见 [server/README.md](server/README.md)。

## 测试

```bash
flutter test                 # 前端
cd server && python -m pytest tests/   # 后端
```

## 关键设计约定

- 金额一律以 **分（int cents）** 存储，展示层才格式化；货币默认 CNY。
- 状态刷新采用 dataVersionProvider：写操作 bump 版本号，读模型 provider watch 它自动重算。
- 金额排版使用 tabular figures；支出用墨色 + 分类色标签（不用满屏红），收入用柔和绿。
- AI 模型可经环境变量切换：文本 qwen-plus / 截图 qwen-vl-plus / 语音 qwen3-asr-flash。

## 相关文档

- [docs/design.md](docs/design.md) — 产品与架构设计
- [server/README.md](server/README.md) — 后端 API 契约与模型配置
- [IOS_INSTALL.md](IOS_INSTALL.md) — iOS 安装指南

## 联系作者 / Contact

扫码加微信交流 —— 功能建议、Bug 反馈、自部署问题都欢迎：

<p align="center">
  <img src="docs/wechat-qr.jpg" width="240" alt="WeChat QR code" />
</p>

Non-Chinese speakers are welcome to open an issue instead.

## 许可证 / License

[MIT](LICENSE) — 供学习与自用部署；欢迎 Fork 和 PR。
