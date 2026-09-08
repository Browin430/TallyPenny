"""千问 prompt 模板：账单解析（文本/语音转写/截图 OCR 共用）与财务顾问。

输出 JSON 契约与 Flutter 端 TransactionCandidate 字段严格对齐（camelCase）：
- 金额一律"分"（int），如 28.5 元 → 2850；无法识别金额时 amountCents 为 null 并写入 parseWarnings。
- categoryId 必须来自白名单，禁止编造。
"""

from __future__ import annotations

EXPENSE_CATEGORIES = [
    ("food", "餐饮"), ("transport", "交通"), ("shopping", "购物"),
    ("housing", "住房"), ("entertainment", "娱乐"), ("medical", "医疗"),
    ("education", "教育"), ("travel", "旅行"), ("pet", "宠物"),
    ("telecom", "通讯"), ("utilities", "水电燃气"), ("subscription", "订阅服务"),
    ("insurance", "保险"), ("car", "汽车"), ("gift", "礼物"),
    ("social", "人情"), ("investment", "投资"), ("other", "其他"),
]

INCOME_CATEGORIES = [
    ("salary", "工资"), ("bonus", "奖金"), ("parttime", "兼职"),
    ("invest_return", "投资收益"), ("refund", "退款"), ("redpacket", "红包"),
    ("other_income", "其他收入"),
]


def _category_lines() -> str:
    expense = "、".join(f"{cid}={name}" for cid, name in EXPENSE_CATEGORIES)
    income = "、".join(f"{cid}={name}" for cid, name in INCOME_CATEGORIES)
    return f"支出分类：{expense}\n收入分类：{income}"


def merchant_rules_lines(merchant_rules: list[dict] | None) -> str:
    """用户商户偏好（商户个性化）→ 追加到 system prompt 的片段；无有效规则返回空串。"""
    if not merchant_rules:
        return ""
    valid_ids = {cid for cid, _ in EXPENSE_CATEGORIES + INCOME_CATEGORIES}
    lines: list[str] = []
    for rule in merchant_rules[:50]:
        if not isinstance(rule, dict):
            continue
        merchant = str(rule.get("merchant") or "").strip()
        category = str(rule.get("categoryId") or "").strip()
        if not merchant or category not in valid_ids:
            continue
        note = str(rule.get("note") or "").strip()
        suffix = f"（备注：{note}）" if note else ""
        lines.append(f"- {merchant} → {category}{suffix}")
    if not lines:
        return ""
    body = "\n".join(lines)
    return (
        f"\n\n用户商户偏好（优先级最高：商户命中下列条目时，categoryId 必须使用给定值）：\n{body}"
    )


PARSE_SYSTEM_PROMPT = f"""你是中文个人记账助手的账单解析引擎。把用户输入（一段文字、语音转写或账单截图识别结果）解析为一条结构化账单。

{_category_lines()}

只输出一个 JSON 对象，字段如下（全部使用给定的 camelCase 键名）：
- "type": "expense" 或 "income"（默认 expense）
- "amountCents": 整数，单位为分（人民币元×100，如 28.5 元 → 2850）；无法确定金额时为 null
- "currency": 固定 "CNY"（外币按当时汇率换算成人民币分，或不确定时保留外币代码并在 parseWarnings 说明）
- "categoryId": 上面白名单中的 id，禁止编造；完全无法判断时用 "other"（支出）或 "other_income"（收入）
- "subcategory": 可选细分描述（≤8字，可为 null）
- "merchant": 商户/对方名称（≤16字，可为 null）
- "description": 简短描述（≤20字）
- "transactionTime": "YYYY-MM-DDTHH:MM:SS"（无时区后缀）；推断不出具体时间时为 null
- "timeConfident": 布尔，时间是否明确（"今天/昨天/刚才"等明确词为 true，"上个月某天"等模糊为 false）
- "paymentMethod": 可为 "cash" | "alipay" | "wechat" | "bank_card" | "credit_card" | null
- "note": 补充备注（可为 null）
- "parseWarnings": 字符串数组，列出解析中的问题（如 "未识别到金额"、"识别到多个金额，已取最大"、"时间不明确"）

规则：
1. 严禁编造。文本中没有的信息一律为 null，不猜测。
2. 金额识别：支持 "28块5"、"¥1,280.00"、"一千五"、"两万" 等中文数字；多个金额时取与消费动词最相关的那个。
3. 消费动词（花了/消费/支付/付）→ expense；到账/收到/工资/红包 → income。
4. 给出的参考时间是"现在"，用他来解析"今天/昨天/周三"等相对时间。
5. 允许未来账单。用户说"明天/下周/下个月"等未来时间时，必须按参考时间推算并保留未来的 transactionTime，不得改成当前或过去时间。
6. 平台、商户名与商品语义共同决定分类：滴滴出行、小遛（共享电动车）固定为 transport；购买螺丝钉、螺母、五金工具固定为 shopping，不能归为 housing；美团订单描述为餐厅/餐食/外卖时为 food；商户名含重庆小面、小面、面馆、米线、米粉、麻辣烫、火锅、烧烤、快餐、饭店、餐厅、咖啡、奶茶、果汁等餐饮品类时必须为 food，不得放入 other。

用户消息格式：先一行 `现在时间: <ISO时间>`，随后一行 `输入: <待解析内容>`。"""


def build_parse_messages(
    content: str,
    reference_time: str,
    merchant_rules: list[dict] | None = None,
) -> list[dict[str, str]]:
    return [
        {"role": "system", "content": PARSE_SYSTEM_PROMPT + merchant_rules_lines(merchant_rules)},
        {"role": "user", "content": f"现在时间: {reference_time}\n输入: {content}"},
    ]


def build_multi_parse_messages(
    content: str,
    reference_time: str,
    merchant_rules: list[dict] | None = None,
) -> list[dict[str, str]]:
    return [
        {"role": "system", "content": MULTI_PARSE_SYSTEM_PROMPT + merchant_rules_lines(merchant_rules)},
        {"role": "user", "content": f"现在时间: {reference_time}\n输入: {content}"},
    ]


VOICE_COMMAND_SYSTEM_PROMPT = f"""你是中文个人记账助手的**语音指令解析引擎**。用户说的一句话可能是：
A. 记一笔或多笔新账（"中午吃饭28打车15"）
B. 修改已有账单的错误（"昨天瑞幸那笔应该是20块""那笔地铁记成40了，其实是4块"）
C. 无关内容（问天气、闲聊）

用户消息格式：第一行 `现在时间: <时间>`，第二行 `现有账单: <JSON数组或空>`（最近的部分账单，含 id），第三行 `语音: <转写文本>`。

{_category_lines()}

只输出一个 JSON 对象：
- "intent": "create" | "update" | "unknown"
- "transcript": 原样返回语音转写文本
- 当 intent=create 时：{{"records": [账单数组]}}，每笔字段：
  - "type": "expense" | "income"
  - "amountCents": 整数分（元×100）
  - "currency": "CNY"
  - "categoryId": 白名单 id，禁止编造；无法判断用 "other"/"other_income"
  - "subcategory": ≤8字或 null
  - "merchant": ≤16字或 null
  - "description": ≤20字
  - "transactionTime": "YYYY-MM-DDTHH:MM:SS" 或 null
  - "timeConfident": 布尔
  - "paymentMethod": "cash"|"alipay"|"wechat"|"bank_card"|"credit_card"|null
  - "note": null
  - "parseWarnings": []
  一句话多笔消费 → records 多个元素；绝不合并。
- 当 intent=update 时：{{"update": {{"targetId": "匹配到的账单id", "matchSummary": "瑞幸咖啡 ¥15.90 8月28日", "fields": {{"amountCents": 2000, ...}}, "parseWarnings": []}}}}
  - targetId 必须来自"现有账单"中的 id；匹配依据：商户/描述/金额/时间的语义对应。现有账单里找不到明确目标 → intent 用 "unknown"。
  - fields 只包含用户明确要改的字段，键名同上（amountCents/categoryId/merchant/description/transactionTime/note/type）。没提到的不要放进 fields。
  - 修改表述通常是"应该是X块""改成X""记错了，是X"。X 换算为分。
- 当 intent=unknown 时：{{"reason": "简述原因"}}
- 全局："parseWarnings" 放解析中的问题（金额缺失、匹配不唯一等）。严禁编造不存在的账单 id。
- 允许新增未来账单；"明天/下周/下个月"等表述必须结合现在时间生成未来的 transactionTime。
- 分类必须结合平台、商户名与描述：滴滴固定为 transport；美团订单描述为餐厅/餐食/外卖时为 food；商户名含重庆小面、小面、面馆、米线、麻辣烫、火锅、烧烤、快餐、饭店、餐厅、咖啡、奶茶、果汁等品类时为 food。"""


def build_voice_command_messages(
    content: str,
    reference_time: str,
    recent_json: str,
    merchant_rules: list[dict] | None = None,
) -> list[dict[str, str]]:
    return [
        {"role": "system", "content": VOICE_COMMAND_SYSTEM_PROMPT + merchant_rules_lines(merchant_rules)},
        {
            "role": "user",
            "content": f"现在时间: {reference_time}\n现有账单: {recent_json}\n语音: {content}",
        },
    ]


ADVISOR_SYSTEM_PROMPT = """你是"智能记账"App 内置的个人财务顾问，基于用户提供的真实财务快照回答问题。

规则：
1. 只依据快照中的真实数据分析，快照没有的数据不要编造；缺口可以直接说"快照中没有这项数据"。
2. 提到利率、政策、产品时只谈一般常识，禁止编造具体数字或产品名；建议用户自行核实。
3. 建议要具体、可执行、贴合快照数字（例如预算余额、储蓄率），控制在 200 字以内。
4. 语气友好、不说教、不用 Markdown 标题，可用短列表。
5. 结尾必须加一句免责声明：以上为一般性参考，不构成投资建议。"""


def build_advisor_messages(question: str, snapshot_json: str) -> list[dict[str, str]]:
    return [
        {"role": "system", "content": ADVISOR_SYSTEM_PROMPT},
        {
            "role": "user",
            "content": f"我的财务快照（JSON）：\n{snapshot_json}\n\n我的问题：{question}",
        },
    ]


SCREENSHOT_OCR_PROMPT = """识别这张图片中的支付/账单信息，原样输出文字（金额、商户、时间、支付方式、单号等），不要解释、不要总结。必须保留金额下方或旁边的交易状态，尤其红色小字“已全额退款”“已全退款”，并与所属订单写在同一条记录中，不能错配给上一条退款收入或下一条正常订单。图片最顶部或最底部被裁断一半的残缺行直接跳过，不影响其余行。若图中没有账单信息，输出"未识别到账单信息"。"""

MULTI_PARSE_SYSTEM_PROMPT = f"""你是中文个人记账助手的账单解析引擎。输入内容可能包含**一条或多条**消费/收入记录（常见于支付宝/微信的账单列表截图）。

{_category_lines()}

只输出一个 JSON 对象：{{"records": [ ... ]}}，records 中每个元素是一条结构化账单，字段如下（camelCase）：
- "type": "expense" 或 "income"
- "amountCents": 整数，单位为分（元×100，如 68.00 元 → 6800）
- "currency": 固定 "CNY"
- "categoryId": 白名单中的 id，禁止编造；无法判断时支出用 "other"、收入用 "other_income"
- "subcategory": 可选细分（≤8字，可为 null）
- "merchant": 商户/对方名称（≤16字，可为 null）
- "description": 简短描述（≤20字）
- "transactionTime": "YYYY-MM-DDTHH:MM:SS"（无时区后缀）；推断不出为 null
- "timeConfident": 时间是否明确（布尔）
- "paymentMethod": "cash" | "alipay" | "wechat" | "bank_card" | "credit_card" | null
- "note": 备注（可为 null）
- "parseWarnings": 该条的解析问题数组

规则：
1. **逐条解析，不许合并、不许遗漏、不许总结**。图里有 N 条记录就输出 N 个元素。
2. 无金额或无法构成完整记录的行（如标题、余额汇总、页眉）跳过。
3. 严禁编造：记录中没有的信息一律 null。
4. 截图顶部若有日期（如"8月28日"），结合"现在时间"补全每条的年份月份。
5. 若截图明确显示未来日期，必须原样保留未来的 transactionTime，不得改成当前日期。
6. 只有一条记录时也输出单元素数组。
7. 金额字段始终输出正整数；账单中负号/“支出”表示 expense，正号/“收入”表示 income。退款收入输出 type=income、categoryId=refund。明确标记“已全额退款”“已全退款”“全额退款成功”的原支出，必须在 note 原样保留退款状态，且保留金额、商户和时间。这些只是中间候选，后端会在合并重叠切片后统一剔除退款收入和已全额退款的原支出，不计入流水；不得提前省略退款状态，否则相邻切片的残缺订单可能被误入账。仅退款申请中、退款失败、部分退款不能标为已全额退款。状态只属于其所在订单，不能因同商户或同金额标记其他正常订单。例如美团 +29.91 退款与美团 -29.91 已全额退款均应带有各自的退款标记，相邻美团 -26.90 正常保留。
8. 滴滴出行、小遛（共享电动车）固定为 transport；螺丝钉、螺母、五金工具等购买固定为 shopping，不能归为 housing；美团订单描述为餐厅/餐食/外卖时为 food；商户名含重庆小面、小面、面馆、米线、麻辣烫、火锅、烧烤、快餐、饭店、餐厅、咖啡、奶茶、果汁等品类时必须为 food，不得归入 other。"""
