# FlowMoney · AI 智能个人财务管理 App 设计文档

> 暂定名 FlowMoney（代码名 `flowmoney`，产品名可随时更换，代码不强耦合：界面显示名为「智账」，2026-09-03 前为「智能记账」）。
> Flutter 一套代码，iOS + Android。数据全部本地存储，不上传。

---

## A. 站点地图（Sitemap）

```
App 启动
└── 主框架 AppShell（底部 4 Tab + 中央【+】）
    ├── 1. 首页 Dashboard
    │     ├── 问候区（时段问候 + 用户名）
    │     ├── 本月结余卡（收入 / 支出 / 环比徽章）
    │     ├── 本月预算卡（进度条，80% 变黄、100% 变红）
    │     ├── 今日支出（当日账单列表 → 点击进详情）
    │     └── AI 财务提示（洞察卡 →「查看分析」切到分析 Tab）
    │
    ├── 2. 流水
    │     ├── 月份切换 + 本月收支汇总
    │     ├── 搜索（商户 / 描述）+ 类型筛选 + 分类多选筛选
    │     └── 按日分组列表（日小计）→ 点击进详情
    │
    ├── 3. 分析
    │     ├── 月份切换
    │     ├── 消费结构环形图（可点选扇区 → 分类明细 + Top 商户）
    │     ├── 月度趋势（近 6 个月收支双折线）
    │     ├── 消费排名（分类条形）
    │     └── AI 财务洞察列表
    │
    ├── 4. 我的
    │     ├── 用户卡（昵称编辑）
    │     ├── 财务档案（月收入 / 固定支出 / 月预算 / 储蓄目标，弹层编辑）
    │     ├── 分类管理（隐藏 / 显示、新增自定义分类）
    │     ├── 周期记账 / AI 服务设置（Phase 7 / 9 占位）
    │     ├── 外观（自动 / 浅色 / 深色）
    │     └── 隐私与数据（生物锁 Phase 10 占位、重新生成演示数据、清空账单）
    │
    └── 中央【+】→ 记账入口选择
          ├── 语音记账（演示模式：规则引擎解析 → 确认卡 → Pipeline）
          ├── 截图记账（演示模式：支付宝 / 微信示例账单 → 确认卡 → Pipeline）
          └── 手动记账（完整表单）

详情链路：任意账单 → 账单详情（字段 / 原始识别记录 / 编辑 / 删除）
保存链路：所有入口统一走 TransactionPipeline（校验 → 归一化 → 分类兜底 → 去重 → 入库）
去重链路：score ≥ 0.85 自动合并（可撤销提示）；0.55 ~ 0.85 弹窗「合并为一笔 / 这是两笔」；< 0.55 直接入库
```

## B. 目录结构

```
lib/
├── main.dart                    # 平台分支（sqflite / 内存仓库）+ Provider overrides
├── app.dart                     # MaterialApp、主题、深浅色
├── core/
│   ├── constants/app_constants.dart   # 去重权重 / 阈值、置信度策略、预算提醒、默认档案
│   ├── icons/app_icons.dart           # iconCode → IconData 集中映射（数据层不依赖具体图标）
│   ├── theme/                         # app_colors（token 体系）、app_typography、app_theme
│   ├── utils/                         # money（分↔展示）、日期、IdGen
│   └── widgets/                       # FMCard/FMEmptyState、FMAmountText、弹层、Toast、
│                                      # 分类图标、月份切换、进度条、账单 Tile
├── domain/                       # —— 纯 Dart，无 Flutter 依赖（除 Category 的 Color）——
│   ├── models/                   # TransactionEntity、TransactionCandidate、Category、
│   │                             # DuplicateMatch、AiInsight、enums（db 值稳定）
│   ├── pipeline/transaction_pipeline.dart   # 统一入库流水线（sealed result）
│   ├── repositories/             # 仓库抽象（transaction / category / settings）
│   └── services/ai_services.dart # AITransactionParser / SpeechRecognitionService / OCRService 抽象
├── data/
│   ├── database/                 # db_schema（11 表 DDL）、app_database（连接管理 + supportsSqlite）
│   ├── dao/mappers.dart          # Row ↔ Entity
│   ├── repositories/             # Sqflite* 实现 + Memory* 实现（Web 预览 / 测试）+ PrefsSettings
│   └── services/                 # RuleBasedTransactionParser（Mock AI）、MockAiServices
├── services/                     # 跨层应用服务：DuplicateDetectionService（去重引擎）、
│                                 # InsightsService（真实计算洞察）、SeedDataService（演示数据）
├── state/app_providers.dart      # 全部 Riverpod provider（读模型 + 可替换实现注入点）
└── presentation/
    ├── navigation/app_shell.dart
    ├── home/  transactions/  analysis/  detail/
    ├── entry/                    # 入口选择、语音页、截图页、手动记账、确认卡、
    │                             # 分类选择、重复确认弹窗、统一保存流程 entry_flow
    └── profile/                  # 我的页、分类管理页
```

依赖方向：`presentation → state → services/domain ← data`。domain 不 import data / presentation。

## C. 数据库 Schema（11 表，v1）

| 表 | 关键字段 | 说明 |
|---|---|---|
| `users` | id, nickname, created_at | 本地单用户（`local`），预留多用户 |
| `categories` | id(text 主键), name, icon_code, color_value, type, sort_order, is_system, is_hidden | 18 支出 + 7 收入内置，支持自定义 |
| `transactions` | id, user_id, type, amount_cents(**int 分**), currency, category_id, subcategory, merchant, description, note, transaction_time, created_at, updated_at, source_type, confidence, status, is_recurring, payment_method, dedup_group_id, deleted_at | 软删除（deleted_at）；金额一律 int 分 |
| `transaction_sources` | id, transaction_id(FK), source_type, raw_text, image_reference, ocr_result_json, ai_parse_result_json, created_at | **原始识别记录永不丢失**（语音转写 / OCR 文本 / AI 解析 JSON） |
| `recurring_transactions` | id, template_tx_id, frequency(daily/weekly/monthly/yearly), interval, next_run_at, end_date, is_active | 周期记账模板（Phase 7） |
| `budgets` | id, user_id, scope(overall/category), category_id, amount_cents, period(monthly), start_date | 月预算 / 分类预算 |
| `financial_profiles` | user_id PK, monthly_income_cents, fixed_expense_cents, monthly_budget_cents, savings_goal_cents | 财务档案（当前存 SharedPreferences，表已备好） |
| `financial_goals` | id, name, target_cents, current_cents, deadline | 储蓄目标（Phase 8） |
| `ai_insights` | id, user_id, type, severity, content, data_json, created_at, is_read | AI 洞察持久化（Phase 9） |
| `duplicate_candidates` | id, existing_tx_id, incoming_tx_id, score, reasons_json, action(auto_merged/user_merged/kept_both/rejected), created_at | 去重判定完整审计 |
| `user_merchant_rules` | id, user_id, merchant_pattern, category_id, payment_method, priority | 用户反馈学习（Phase 9） |

索引：`transactions(user_id, transaction_time)`、`(category_id)`、`(status)`；`transaction_sources(transaction_id)`；`duplicate_candidates(existing_tx_id)`、`(incoming_tx_id)`。

设计要点：
- 金额、预算、目标全部 **int 分**，杜绝浮点误差。
- 枚举 db 值 snake_case 稳定（`expense` / `income`…），永不改动。
- `transaction_sources` 与 `duplicate_candidates` 保证「原始数据不丢、判定可审计」。

## D. Transaction 模型

```
TransactionEntity
├── id / userId / currency
├── type: TransactionType(expense|income)      ← db: 'expense'/'income'
├── amountCents: int                           ← 恒正；方向由 type 决定
├── categoryId / subcategory                   ← category_id 为 null 时 UI 兜底「其他」
├── merchant / description / note
├── transactionTime / createdAt / updatedAt
├── sourceType: manual|voice|screenshot|import|recurring
├── confidence: double                          ← AI 置信度，手动 = 1.0
├── status: confirmed|pendingReview|merged      ← merged = 去重合并的正身
├── isRecurring / paymentMethod / dedupGroupId
├── deletedAt（软删除）
├── displayTitle    ← merchant ?? description ?? 分类名
└── signedAmountCents / isIncome    ← 派生
```

写入路径唯一：`TransactionCandidate`（各入口产出，含 sourceRecords 与 parseWarnings）
→ `TransactionPipeline.process()` → `PipelineSaved | PipelineNeedsReview | PipelineDuplicateSuspected`。

## E. 多来源去重算法（核心）

**第一步 · 硬性候选筛选**（SQL：`duplicateWindow`，任意条件不满足直接排除）
- 时间：与已有账单相差 ≤ `candidateWindowHours`（24h）
- 方向：同收支方向
- 金额：`ABS(amount - incoming) ≤ incoming × candidateAmountTolerance`（15%）

**第二步 · 加权评分**（权重存于 `DuplicateWeights`，可配置，不写死在逻辑里）

| 维度 | 权重 | 规则 |
|---|---|---|
| 金额 | 0.40 | 差 0% → 满分；差 1 分钱以内 → 满分；否则按容差线性衰减 |
| 时间 | 0.25 | ≤5min 满分 → ≤2h 线性 → ≤24h 线性衰减 |
| 内容语义 | 0.20 | 描述/商户/备注合并文本：字符二元组 Dice + 消费场景词组亲缘（「瑞幸↔咖啡」） |
| 商户 | 0.10 | 完全相同满分；场景亲缘给部分分 |
| 分类 | 0.10 | categoryId 相同满分 |

score clamp 到 0~1。每一条加分都生成中文理由（弹窗里展示「判断依据」）。

**第三步 · 按阈值处置**（`DuplicateThresholds`，可配置）
- `score ≥ 0.85` → **自动合并**：保留已有账单为正身（status=merged 组），`fill()` 补全缺失字段，incoming 的 source records 附加到正身，写 `duplicate_candidates(action=auto_merged)` 审计
- `0.55 ≤ score < 0.85` → **弹窗确认**：左右对比卡 + 判断依据 →「合并为一笔 / 这是两笔消费 / 查看已有账单」
- `score < 0.55` → 正常入库

可替换性：评分中「内容语义」与「商户」相似度已抽象为私有方法，TODO(phase-5) 接入 embedding 后替换为余弦相似度；阈值与权重集中在 `core/constants/app_constants.dart`。

## F. Design System（Apple 风格极简）

- 背景 `#F5F5F7`（深色 `#050506`）；卡片 surface 圆角 20（sheet 28 / 输入 14 / chip 12 / 按钮 16），浅色柔和阴影、深色 0.5px 描边
- 主色 `#3478F6`（accent）；**收入柔和绿 `#30A46C`；支出用墨色**，只有超预算 / 删除等破坏性场景用红 —— 拒绝满屏红色
- 全部金额 `FontFeature.tabularFigures` 等宽对齐；金额字号阶梯 XL 34 / L 26 / M 20 / S 16
- 间距阶梯 4 / 8 / 12 / 16 / 24 / 32；列表分组卡内 0.5px 分隔线
- 动画克制：金额数字 Tween 滚动、环形图展开、Toast 浮入，全部 ≤ 750ms、easeOutCubic
- 深浅色完整双 token（`FMScheme`），组件只从 `context.colors` 取色，不写死 Color

## G. 页面规划

| 页面 | 文件 | 状态 |
|---|---|---|
| 首页 Dashboard | `presentation/home/home_page.dart` | ✅ |
| 流水 | `presentation/transactions/transactions_page.dart` | ✅ |
| 分析 | `presentation/analysis/analysis_page.dart`（DonutChart / TrendChart 自绘，零第三方图表库） | ✅ |
| 我的 | `presentation/profile/profile_page.dart` + `category_manage_page.dart` | ✅ |
| 语音记账 | `presentation/entry/voice_entry_page.dart`（波形动画 + 演示模式徽章） | ✅ Mock ASR |
| 截图记账 | `presentation/entry/screenshot_entry_page.dart` | ✅ Mock OCR |
| 手动记账 / 编辑 | `presentation/entry/manual_entry_page.dart` | ✅ |
| 账单详情 | `presentation/detail/transaction_detail_page.dart` | ✅ |
| 重复确认 | `presentation/entry/duplicate_confirm_sheet.dart` | ✅ |
| 周期记账 / AI 顾问 / 生物锁 / 导出 | — | Phase 7~10 |

## H. 包推荐（当前依赖）

| 包 | 用途 | 备注 |
|---|---|---|
| flutter_riverpod | 状态管理（Notifier/AsyncNotifier，无 codegen） | dataVersion 版本号驱动读模型刷新 |
| sqflite + path | iOS/Android/macOS 本地库 | Web 走内存仓库双实现 |
| shared_preferences | 轻量 KV（主题 / 档案 / 种子标记） | |
| intl | 金额 / 日期格式化 | |
| cupertino_icons | SF 风格图标 | |

后续按 Phase 引入（均已在抽象后预留替换点）：`google_mlkit_text_recognition`（OCR，Phase 4）、`speech_to_text`（ASR，Phase 3）、`flutter_local_notifications`（预算提醒，Phase 8）、`file_picker` + `csv`（导出，Phase 10）。**刻意不引入**：图表库（自绘）、状态管理以外的重运行时。

## I. Service 接口（全部抽象，可替换）

```
AITransactionParser        parseFromText(text) / parseFromOcr(OcrResult)
                           → TransactionCandidate（含 confidence / parseWarnings / sourceRecords）
SpeechRecognitionService   start(locale) / stop() / results Stream / available
OCRService                 recognizeFromGallery() / recognizeFromFile(path) → OcrResult
FinancialAdvisorService    ask(question, snapshot) → 顾问回复（强制免责声明；利率不编造）
TransactionRepository      insert/update/softDelete/getById/getByRange/getAll/
                           duplicateWindow/attachSource/sourcesOf/logDuplicateEvent/clearAll
CategoryRepository         getAll/byId/upsert/setHidden/upsertAll
SettingsRepository         getString/setString/getInt/setInt/getBool/setBool
TransactionPipeline        process(candidate) → sealed PipelineResult；merge(match)；keepBoth(match)
DuplicateDetectionService  findMatch(candidate) → DuplicateMatch?（score + 中文 reasons）
InsightsService            insightsForMonth(...) → List<AiInsight>（真实计算，非 mock 文案）
```

Mock → 真实实现的替换只发生在 `app_providers.dart` 的 provider 处（或 main 的 override），业务代码零改动。

## J. 阶段任务列表

| Phase | 内容 | 状态 |
|---|---|---|
| 1 | 架构 / 主题 / 导航 / 数据库 / 首页 / 流水 / 手动记账 / 详情 / 分析 / 我的 / 统一 Pipeline + 去重 | ✅ 本次交付 |
| 2 | 真机验证、集成测试、边缘用例（跨月 / 时区 / 大额） | 待开始 |
| 3 | 真实语音：speech_to_text 接入 + ASR 结果进 Pipeline | 抽象已备 |
| 4 | 真实 OCR：mlkit 截图识别（支付宝 / 微信账单模板解析） | 抽象已备 |
| 5 | 周期记账引擎 + 通知提醒；去重升级 embedding 相似度 | 抽象已备 |
| 6 | 预算体系完善（分类预算）+ 目标储蓄 | 表已备 |
| 7 | AI 财务顾问（LLM 接入，免责声明 + 利率防编造约束） | 接口已定义 |
| 8 | 用户反馈学习（user_merchant_rules 生效） | 表已备 |
| 9 | 数据导出 / 备份 | exportAll 已备 |
| 10 | 生物识别锁、图标、上架材料 | — |

## 运行

```bash
# Web 预览（无需移动端工具链，内存仓库 + 演示数据）
flutter run -d edge        # 或 -d chrome

# 移动端（sqflite 持久化）
flutter run                # 连接的 iOS/Android 设备

# 质量检查
dart analyze               # 0 issues
flutter test               # 7 tests passing
```

> Windows 桌面 / Web 使用内存仓库（sqflite 不支持），数据会话级；移动端为真实持久化。
