# TokenBar Design System

本文档定义 TokenBar 后续界面迭代的长期视觉、交互和文案边界。它借鉴 macOS 菜单栏工具的扫视型信息架构，但所有规则都以 TokenBar 自身的策略闸门定位为准。

## 设计立场

TokenBar 是面向 AI 编程 Agent 的本地策略控制台。它应该像一个可信的 macOS 工具，而不是营销页、账单仪表盘或聊天应用。

- 守卫优先：首屏先回答“这次运行能不能继续”。
- 本地优先：用户能明确知道数据来自本机、供应商 API、Keychain 还是估算。
- 扫视优先：菜单栏 popover 和 dashboard 都服务快速判断，不展示长日志。
- 策略诚实：`ALLOW`、`WARN`、`BLOCK` 的原因要清楚，不能只靠颜色表达。
- 原生克制：优先使用 SwiftUI、系统色、SF Symbols、系统字体和系统控件。
- 隐私默认：不展示 prompt 正文、回复正文、raw logs、完整 secrets 或不必要的完整路径。

## 信息架构

### 第一层：是否可运行

守卫决策是 TokenBar 的主信息，不应被供应商用量、路由推荐或设置入口压过。

- 决策状态：`ALLOW`、`WARN`、`BLOCK`。
- 决策对象：Agent、workspace、provider、model。
- 决策原因：最多展示关键原因，长解释进入详情或文档。
- 下一步建议：明确说明继续、换模型、换供应商、调整预算或补充 Key。

### 第二层：为什么这样判断

解释信息必须按用户能理解的口径组织：

- 工作区策略：允许的 provider、blocked model、company key 要求。
- 成本策略：estimated run、projected daily spend、session budget、per-run cap。
- 数据来源：live、local、CC Switch、needs key、error、unsupported。
- Smart Routing：只作为推荐和证据，不覆盖 guard policy。

### 第三层：如何修复或配置

配置入口应靠近问题，但不抢首屏：

- 缺 Key 时给出 Settings 或 Keychain 入口。
- 超预算时展示当前 cap 和调整控件。
- provider unsupported 时说明是未实现适配器，不暗示用户配置错误。
- local API stopped/failed 时展示端口、状态和最小恢复动作。

## 布局原则

TokenBar 适合高密度但安静的工具型布局。

- Dashboard 使用 `NavigationSplitView` 保持左侧 section 和右侧内容稳定。
- Menu bar popover 保持单列、紧凑、可滚动，最重要的决策卡片始终靠前。
- 卡片只用于真正需要边界的重复对象：决策、provider、workspace、audit、summary tile。
- 不把卡片嵌套在卡片里；内部列表用分割线、间距或轻量行背景。
- 并列 summary tile 需要共享高度、顶部基线和数字对齐策略。
- 文本、路径、模型名和 provider 名必须能截断或缩放，刷新时不造成明显跳动。
- 关键数字使用 monospaced digit，金额和 token 刷新不应左右抖动。

## 视觉语言

### 材质和表面

- App window 使用系统 window/background/control colors，尊重浅色、深色和高对比环境。
- Menu bar header/footer 可使用 `.thinMaterial` 建立原生层级。
- 内容卡片优先使用 `Color(nsColor: .controlBackgroundColor)` 和 8px radius。
- 不使用大面积渐变、装饰性光斑、背景 orb、强玻璃拟态或网页式 hero。
- 阴影只在需要表达窗口层级或浮层时使用，常规卡片不要靠阴影制造装饰感。

### 色彩职责

颜色只承担语义，不承担装饰。

| 类别 | 用途 |
| --- | --- |
| Status | `ALLOW`、`WARN`、`BLOCK`、healthy、warning、critical |
| Source | live、local、CC Switch、needs key、error、unsupported |
| Data | usage ratio、budget progress、trend line、relative bar |
| Brand | app icon 呼应和少量主强调 |
| Surface | window、card、separator、track、hover |

规则：

- 绿色只表示可继续、健康、成功。
- 橙色或黄色只表示注意、接近上限、需要确认。
- 红色只表示阻断、失败、危险或不可继续。
- 蓝色/紫色只用于品牌或 Smart Routing 强调，不作为默认状态色。
- 灰色表示中性、不可用、未知或次级信息。
- 不用颜色作为唯一状态通道，必须配合文字、图标或位置。

### 字体和图标

- 使用系统字体，不引入网页字体。
- 标题、正文、caption、数字和标签使用系统文本层级，不用 viewport 相关字号。
- 金额、token、百分比、时间窗口使用 `.monospacedDigit()`。
- 图标优先使用 SF Symbols，并与文案语义一致。
- 不使用 emoji 作为产品图标、状态图标或按钮图标。
- Icon button 必须有 tooltip/help，尤其是刷新、设置、复制、打开详情。

## 组件规范

### Decision Hero

- 是 guard dashboard 的首要组件。
- 左侧显示状态图标和决策标题，右侧显示 `StatusPill`。
- 决策上下文必须包含 workspace 和 model。
- 原因列表使用简短句子，不暴露内部字段名。
- Smart Routing 推荐只能放在 guard 决策之后，并明确“guard policy 仍优先”。

### StatusPill

- Pill 表示状态，不表示普通分类。
- 文案必须可本地化，不能只显示 raw enum。
- 背景使用状态色低透明度，文字使用同一语义色。
- 不在 pill 内塞长解释，解释进入相邻正文或 tooltip。

### SourcePill

- Source pill 表示数据口径，不表示供应商品牌。
- `Live`、`Local`、`CC Switch`、`Needs key`、`Error`、`Unsupported` 必须语义稳定。
- `Needs key` 和 `Unsupported` 不能被样式做成错误状态。
- Tooltip 或详情应解释来源限制，但不能泄露 secrets 或 raw response。

### Provider Card

- 卡片应优先展示 provider 名称、状态、用量/额度和来源。
- 缺失字段显示 unknown 或 unavailable，不显示 0。
- 支持 live adapter 但无 key 时，引导去 Settings。
- provider 错误应展示用户可处理的信息，避免原样输出冗长 API response。

### Workspace Policy Card

- 展示 workspace 名称、预算、allowed providers、preferred provider/model 和 blocked models。
- Per-run cap 是高频控制，使用清晰的金额输入和 +/- 操作。
- 修改策略后应立即刷新 guard decision，避免界面与实际策略不一致。
- 项目路径只在有帮助时展示，长路径默认截断中间。

### Smart Routing

- Smart Routing 是建议，不是授权。
- 推荐必须展示 provider/model、confidence、evidence count 和简短原因。
- 当 guard decision block 时，Smart Routing 仍不得把动作文案写成继续运行。
- synthetic、test、smoke evidence 不应进入生产推荐叙事。

### Audit 和日志

- Audit panel 展示事件摘要，不展示 prompt、回复正文、tool arguments 或 raw logs。
- 事件按最新优先，单行尽量可扫视。
- 详情中可以展示 action、provider、workspace、source、时间和结果。
- 错误详情应脱敏，避免包含 key、auth header、完整本地敏感路径。

## 文案规范

- 使用用户语言，不使用孤立内部字段名。
- “估算”必须明确写出来，不能把 estimated cost 当作 bill。
- “未知”表示供应商或本地记录没有数据，不等于 0。
- “Unsupported”表示 TokenBar 尚无适配器，不表示 provider 不可用。
- “Needs key”表示可以配置 key 后获取 live data，不表示策略失败。
- 中英文文案表达同一语义，不做机械逐字翻译。
- 按钮文案使用动作动词：Check、Refresh、Open Settings、Copy Token。
- 不使用夸张营销词，不把节省成本包装成确定收益。

## 数据口径

TokenBar 必须持续区分四类数据：

| 口径 | 示例 | UI 表达 |
| --- | --- | --- |
| Project policy | `tokenbar.yml`、workspace budgets、blocked models | Policy / Workspace |
| Local runtime | local API status、local token、preferences | Local |
| Local record | Codex transcript、Claude Code statusline、CC Switch rollups | Local / CC Switch |
| Live provider | OpenAI Admin、Anthropic Admin、OpenRouter credits、MiniMax quota | Live |
| Estimate | prompt cost estimate、route confidence、fallback token count | Estimated |

规则：

- 缺失 live data 时显示 unknown、needs key、unsupported 或 error。
- 不把缺失的 spend、quota、request count 或 token count 填成 0。
- 估算值必须标注 estimated 或“估算”。
- provider 额度、官方账单、本地用量和策略投影不得混成一个未解释的总数。

## 隐私边界

默认不展示：

- prompt 正文、assistant 回复正文、tool arguments。
- provider keys、local API bearer token、auth header。
- raw logs、raw transcripts、raw provider response。
- 完整本地路径，除非用户主动查看详情。
- 可识别客户或项目敏感信息的长字符串。

允许展示：

- workspace display name。
- provider/model 名称。
- 脱敏后的路径尾名。
- 聚合 token、cost、request count、状态和时间。
- 明确脱敏后的错误摘要。

## 可访问性

- 状态必须同时通过文字和图标表达，不只靠颜色。
- 小字号不能承载唯一关键含义。
- 控件必须支持键盘和 VoiceOver 的基本理解。
- 颜色对比应在浅色、深色和高对比环境下可读。
- 动态刷新不能导致焦点丢失或控件位置明显跳动。
- 所有 icon-only controls 都需要 `.help` 或 accessibility label。

## 维护规则

- 新增 UI 前先检查现有 `StatusPill`、`SourcePill`、provider card、workspace card 和 menu popover 模式。
- 新增颜色、radius、spacing 或图标语义前，先判断是否能复用系统 token 或现有组件。
- 改动 guard decision、provider status、source badge 或 Smart Routing 时，同步检查本文档。
- 文档记录长期规则，不记录一次性实现细节、临时 bug 或发布 checklist。
