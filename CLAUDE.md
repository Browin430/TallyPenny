# FlowMoney（工程代号 flowmoney）

AI 智能个人财务管理 App。Flutter 一套代码，目标平台 iOS / Android。
产品名称未定稿 —— 代码中不出现 "FlowMoney" 字样于业务逻辑（仅 pubspec 包名与 README 允许）。

## 历史上下文

CLAUDE.md 写于 Mock 阶段，AI 能力现已接入真实后端（自部署 `server/`，App 内「我的 → AI 服务设置」配置地址），以代码为准。

## 常用命令

```bash
flutter pub get
flutter analyze          # 必须零错误
flutter run -d edge      # Web 预览（使用内存仓库 + 演示数据，无需移动端工具链）
flutter run              # Android / iOS（sqflite 持久化）
flutter test
```

Web 预览运行于内存实现（`kIsWeb` 分支），与移动端共用全部业务与 UI 代码。

## 架构（Clean Architecture）

```
lib/
  core/        设计系统（theme/）、通用组件（widgets/）、工具
  domain/      models/ 实体与枚举、repositories/ 抽象接口、services/ 抽象接口、pipeline/
  data/        database/ sqflite schema、dao/、repositories/ 实现、services/ Mock AI 实现
  services/    纯 Dart 应用服务：去重引擎、洞察计算、演示数据
  presentation/  navigation/ + 各页面（home/ transactions/ analysis/ profile/ entry/ detail/）
```

依赖方向：presentation → (domain ← data)。所有 AI / OCR / 语音能力走 domain/services 接口，
当前实现为 data/services 下的 Mock（代码内 `TODO(phase)` 标注），后续可替换为真实服务。

## 关键设计

- 金额一律以 **分（int cents）** 存储，展示层才格式化。货币默认 CNY。
- 所有输入（手动/语音/截图/导入/周期）经 `domain/pipeline/transaction_pipeline.dart` 统一处理：
  归一化 → 分类 → **去重检测** → 置信度评估 → 保存/请求确认。
- 去重阈值与权重在 `core/constants/app_constants.dart` 的 `DuplicateWeights` / `DuplicateThresholds`，不写死在 UI。
- 原始数据永不丢失：`transaction_sources` 保留 raw_text / ocr_result / ai_parse_result；
  删除为软删除（is_deleted）。
- 状态刷新采用 dataVersionProvider（写操作 bump 版本号，读模型 provider watch 它自动重算）。
- 金额排版必须 tabular figures；支出不用满屏红色，用墨色 + 分类色标签；收入柔和绿。
