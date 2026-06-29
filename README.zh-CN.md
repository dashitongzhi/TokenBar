<p align="center">
  <img src="TokenBar/Assets.xcassets/AppIconMidnight.imageset/AppIconMidnight.png" alt="TokenBar app icon" width="96" height="96" />
</p>

<h1 align="center">TokenBar</h1>

<p align="center">
  <strong>macOS 上面向 AI 编程代理的本地策略闸门。</strong>
</p>

<p align="center">
  在昂贵、不安全或不符合策略的 Agent 运行真正触碰仓库、供应商额度和公司 Key 之前，先把它拦下来。
</p>

<p align="center">
  <a href="#快速开始"><img alt="快速开始" src="https://img.shields.io/badge/Quick%20Start-CLI%20%2B%20macOS-111827?style=for-the-badge&labelColor=0f172a"></a>
  <a href="#本地-api"><img alt="本地 API" src="https://img.shields.io/badge/API-127.0.0.1%3A3847-2563eb?style=for-the-badge&labelColor=0f172a"></a>
  <a href="#实时供应商用量"><img alt="供应商用量" src="https://img.shields.io/badge/Usage-OpenAI%20%7C%20Anthropic%20%7C%20OpenRouter%20%7C%20MiniMax-16a34a?style=for-the-badge&labelColor=0f172a"></a>
  <a href="#发布打包"><img alt="发布打包" src="https://img.shields.io/badge/Packaging-DMG%20ready-7c3aed?style=for-the-badge&labelColor=0f172a"></a>
</p>

<p align="center">
  <a href="#为什么是-tokenbar">为什么是 TokenBar</a>
  <span> | </span>
  <a href="#工作方式">工作方式</a>
  <span> | </span>
  <a href="#快速开始">快速开始</a>
  <span> | </span>
  <a href="#本地-api">本地 API</a>
  <span> | </span>
  <a href="#agent-hooks">Agent Hooks</a>
  <span> | </span>
  <a href="#开发">开发</a>
</p>

<p align="center">
  <a href="README.md">English</a>
  <span> | </span>
  <strong>简体中文</strong>
</p>

---

## 为什么是 TokenBar

AI 编程工具跑得太快，围绕它们的防护却没有同步跟上。

TokenBar 是一个菜单栏控制面板，用来决定一次 Agent 运行是否应该继续。它读取工作区策略、本地用量、实时供应商额度和本次运行的元数据，然后在昂贵任务开始前给出清晰的 `ALLOW`、`WARN` 或 `BLOCK` 决策。

它不是另一个 API Key 切换器。像 `cc-switch` 这样的工具很适合做供应商路由。TokenBar 关注的是更关键的问题：

> 这个 Agent 是否应该在这个工作区、使用这个模型、以这个成本继续运行？

## 它解决的问题

| 没有 TokenBar | 使用 TokenBar |
| --- | --- |
| Agent 可能从错误的仓库或客户工作区启动。 | 工作区策略通过 `tokenbar.yml` 跟随仓库。 |
| 成本上限停留在人的记忆里，或者事后才打开账单后台。 | CLI 和本地 API 会在运行前检查预算。 |
| OpenAI、Anthropic、OpenRouter、MiniMax、Codex 和本地代理的用量分散在不同地方。 | TokenBar 把实时用量和本地用量集中到一个菜单栏界面。 |
| Claude Code 和 Codex hook 通常需要每个项目手写。 | `tokenbar policy init --hooks all` 会生成可工作的 hook 示例。 |
| 缺失的实时数据很容易被误读成零花费。 | TokenBar 会明确标记未知花费、缺失 Key 和未支持的适配器。 |

## 产品表面

| 层级 | 作用 |
| --- | --- |
| 菜单栏守卫 | 一眼看到当前策略决策和活跃工作区。 |
| Dashboard | 跟踪供应商用量、工作区预算、来源标记、审计事件和策略状态。 |
| CLI preflight | 让 hooks 和脚本在启动 Agent 之前调用 `tokenbar check`。 |
| 本地 API | 在 `127.0.0.1:3847` 暴露仅限 loopback 的策略、额度、pace 和用量端点。 |
| Hook bridge | 把 Codex 和 Claude Code 的运行前检查与用量摄取接入同一套策略引擎。 |
| 发布路径 | 构建、验证、为本地校验做 ad-hoc 签名，并打包 DMG。 |

## 工作方式

```text
Agent request
  -> tokenbar check
  -> workspace policy
  -> provider and model rules
  -> budget projection
  -> local and live usage context
  -> ALLOW, WARN, or BLOCK
```

决策引擎会评估：

- 工作区、客户和项目身份
- 允许的供应商和首选供应商
- 被阻断的模型关键词，例如 `opus` 或 `gpt-5-pro`
- 单次运行的预计成本和 token 上限
- 每日和每月预算投影
- 公司 Key 要求
- Claude Code 和 Codex 的本地用量增量
- 管理员 Key 或供应商 Key 可用时的实时供应商状态

## 快速开始

在本地运行 macOS app：

```bash
./script/build_and_run.sh
```

验证构建和本地 API ready 路径：

```bash
./script/build_and_run.sh --verify
```

从 CLI 检查当前项目：

```bash
./bin/tokenbar status
```

创建仓库本地策略：

```bash
./bin/tokenbar policy init
```

评估一次拟启动的 Agent 运行：

```bash
./bin/tokenbar check \
  --agent codex \
  --provider openai \
  --model gpt-5 \
  --estimated-cost 0 \
  --estimated-tokens 0 \
  --intent implement
```

`tokenbar check` 使用产品计划状态码退出：

| Exit code | 含义 |
| --- | --- |
| `0` | Allow |
| `1` | Warn |
| `2` | Block |
| `3` | CLI、配置或 API 错误 |

## CLI Command Center

TokenBar 在 `bin/tokenbar` 提供一个无额外依赖的本地 CLI。

```bash
./bin/tokenbar status

./bin/tokenbar policy init

./bin/tokenbar usage ingest \
  --agent claudeCode \
  --provider anthropic \
  --model claude-sonnet \
  --session-id local-demo \
  --cost-usd 0.12 \
  --total-tokens 24000

./bin/tokenbar usage codex-session \
  --transcript ~/.codex/sessions/2026/06/17/rollout-example.jsonl

./bin/tokenbar routing record \
  --agent codex \
  --intent implementation \
  --provider openai \
  --model gpt-5 \
  --estimated-cost 0.40 \
  --actual-cost 0.33 \
  --estimated-tokens 42000 \
  --actual-tokens 38000 \
  --success

./bin/tokenbar routing stats

printf '{"model":"gpt-5","prompt":"Fix the failing tests and update docs."}' | \
  ./bin/tokenbar check --agent codex --provider openai --codex-hook-json --json

./bin/tokenbar usage claude-statusline
```

CLI 会优先调用运行中 app 的认证 `POST /policy/evaluate` 端点。如果 app 没有运行，它会从当前目录向上查找 `tokenbar.yml` 或 `tokenbar.yaml`，并在本地评估同一份工作区策略。Codex 预检可以用 `tokenbar check --codex-hook-json` 从 stdin 读取 `UserPromptSubmit` payload，并在评估策略前根据 prompt、model 和 Codex 价格表补齐缺失的成本和 token 估算。

这个离线路径刻意保持窄而稳定：供应商 allowlist、被阻断的模型关键词、单次运行成本上限、每日预算投影和公司 Key 要求都会与当前 `PolicyEngine` 保持一致。

## 项目策略

在仓库根目录执行 `tokenbar policy init`，即可生成项目级本地策略：

```bash
tokenbar policy init
```

它会写入 `./tokenbar.yml`，其中包含从当前目录推断出的 workspace id 和名称、绝对路径、保守的初始预算，以及从本机 agent 配置推断出的供应商/模型策略。TokenBar 会在存在时读取 Codex、Claude Code 和 CC Switch 的模型配置，选择首选平台和 `models.default`，app 首次启动的本地工作区也使用同一套推断。

示例：

```yaml
version: 1

workspace:
  id: local-workspace
  name: Local Workspace
  path: ~/project/current
  client: local

budgets:
  daily: 8.00
  monthly: 160.00
  max_run: 1.50
  spend_today: 0.00
  spend_month: 0.00

providers:
  allowed:
    - openai
    - anthropic
    - openrouter
  preferred: openai
  require_company_key: false

models:
  default: gpt-5
  blocked: []

setup:
  source: local_agent_config
  configured_models: 2
  inferred_from:
    - ~/.codex/config.toml
```

## 本地 API

本地 API 只绑定 loopback。`GET /health` 有意保持无需认证，用于 readiness 检查。所有 policy、quota、pace 或 usage 端点都需要 `Authorization: Bearer <local-token>`。

app 会在这里创建 token：

```text
~/Library/Application Support/TokenBar/local-api-token
```

token 文件使用仅当前用户可读写的权限，CLI 会自动读取它。浏览器 CORS 响应被限制为 localhost 来源。TokenBar 不会输出 `Access-Control-Allow-Origin: *`。

```bash
curl http://127.0.0.1:3847/health

TOKENBAR_API_TOKEN="$(cat "$HOME/Library/Application Support/TokenBar/local-api-token")"

curl http://127.0.0.1:3847/policy \
  -H "Authorization: Bearer $TOKENBAR_API_TOKEN"

curl http://127.0.0.1:3847/quotas/anthropic \
  -H "Authorization: Bearer $TOKENBAR_API_TOKEN"
```

通过 API 评估一次拟启动的运行：

```bash
curl -X POST http://127.0.0.1:3847/policy/evaluate \
  -H "Authorization: Bearer $TOKENBAR_API_TOKEN" \
  -H 'Content-Type: application/json' \
  -d '{
    "agent": "codex",
    "workspaceID": "local-workspace",
    "providerID": "openai",
    "model": "gpt-5",
    "estimatedCost": 0,
    "estimatedTokens": 0,
    "intent": "implement"
  }'
```

示例响应：

```json
{
  "decision": {
    "status": "allow",
    "agent": "Codex",
    "provider": "openai",
    "model": "gpt-5",
    "reasons": [
      "Workspace, provider, model, and budget are inside policy."
    ],
    "recommendation": "Continue with gpt-5. Keep the agent on this workspace policy."
  },
  "localOnly": true
}
```

## Agent Hooks

可工作的 hook 示例位于 `examples/hooks/`。

最快接入：

```bash
tokenbar policy init --hooks all
tokenbar policy init --codex-hooks
tokenbar policy init --claude-hooks
```

hook init 会使用 `examples/hooks/` 里的 shell 脚本写入 `.codex/hooks.json` 和/或 `.claude/settings.local.json`。已有文件默认不会被覆盖，除非传入 `--force`，所以有自定义 hooks 的项目可以手动合并。

| Agent | 运行前检查 | 用量摄取 |
| --- | --- | --- |
| Codex | `UserPromptSubmit` 在运行前调用 `tokenbar check`。 | `Stop` 读取 Codex transcript JSONL，并发送累计 session 用量。 |
| Claude Code | `UserPromptSubmit` 在运行前调用 `tokenbar check`。 | `statusLine` 发送可识别的 cost、token、context-window 和 rate-limit 字段。 |

Codex 的预检 hook 默认会根据提交的 prompt 和 model 估算一次运行，而不是发送 0 成本和 0 token。这个启发式估算会使用 prompt 长度、任务关键词、保守的 Codex 输入/输出预算，以及 `tokenbar usage codex-session` 同一套价格覆盖逻辑。两个 shell hook 都接受这些环境变量覆盖：

```bash
TOKENBAR_BIN=/absolute/path/to/tokenbar
TOKENBAR_PROVIDER=anthropic
TOKENBAR_MODEL=claude-sonnet
TOKENBAR_KEY_SOURCE=company_managed
TOKENBAR_ESTIMATED_COST=0.25
TOKENBAR_ESTIMATED_TOKENS=20000
TOKENBAR_INTENT=refactor
```

Codex `UserPromptSubmit` 里，`TOKENBAR_PROVIDER`、`TOKENBAR_MODEL`、`TOKENBAR_ESTIMATED_COST`、`TOKENBAR_ESTIMATED_TOKENS` 都是可选的。Codex 只提供 prompt 而没有估算值时，hook 会把 JSON payload 管道传给 `tokenbar check --codex-hook-json`；CLI 会根据 prompt、model 和 Codex pricing 做一个保守估算，把 key source 标记为 `codex_managed`，再执行正常 workspace policy。若你明确希望 company-key workspace 拒绝个人/env OpenAI key，请设置 `TOKENBAR_KEY_SOURCE=personal` 或传 `--key-source personal`。

也就是说，昂贵的 Codex prompt 可以在真正运行前被拦截：如果估算出的 prompt/run token 会换算成超过 `budgets.max_run` 的成本，或者让 projected daily spend 超过工作区预算，`UserPromptSubmit` 会返回 Codex block decision。TokenBar 默认闸门是基于成本策略，而不是独立的原始 token 数量上限；如果某个工作区需要“超过固定 token 数就一律拦截”，应再增加显式的 token cap policy。

用户不需要编辑 `tokenbar.yml` 来调整运行中的阈值。在 TokenBar 的 Workspaces 界面里，可以用金额输入框和 +/- 按钮调整每个工作区的 Per-run cap；这个值会本地保存，并由运行中的 localhost policy API 使用。`tokenbar.yml` 只保留为 app API 不可用时的离线 fallback。

手动检查 Codex 任务时，也可以直接传入 prompt：

```bash
./bin/tokenbar check \
  --agent codex \
  --provider openai \
  --model gpt-5 \
  --key-source codex_managed \
  --prompt "Implement the parser, update docs, and run tests." \
  --intent implement \
  --json
```

## 本地用量摄取

把真实的本地 Agent 用量发送进运行中的 app：

```bash
curl -X POST http://127.0.0.1:3847/usage/ingest \
  -H "Authorization: Bearer $TOKENBAR_API_TOKEN" \
  -H 'Content-Type: application/json' \
  -d '{
    "agent": "claudeCode",
    "providerID": "anthropic",
    "model": "claude-sonnet",
    "workspaceID": "local-workspace",
    "sessionID": "statusline-session",
    "source": "Claude Code statusline",
    "costUSD": 0.12,
    "totalTokens": 24000,
    "contextWindowSize": 200000,
    "cumulative": true
  }'
```

默认情况下，用量值会被视为累计 session 总量。TokenBar 会根据 `--session-id` 或 transcript 路径进行增量去重，所以重复触发 hook 不会重复计费。

Codex 价格可以通过环境变量覆盖：

```bash
TOKENBAR_CODEX_INPUT_USD_PER_1M=1.25
TOKENBAR_CODEX_CACHED_INPUT_USD_PER_1M=0.125
TOKENBAR_CODEX_OUTPUT_USD_PER_1M=10.00
```

也可以通过项目配置覆盖：

```yaml
codex:
  pricing:
    gpt-5.5:
      input_per_million: 1.25
      cached_input_per_million: 0.125
      output_per_million: 10.00
```

## 实时供应商用量

TokenBar 支持来自以下供应商或本地来源的实时/本地用量信号：

| 供应商或来源 | TokenBar 读取内容 | Key 或本地状态 |
| --- | --- | --- |
| OpenAI | Organization usage and cost APIs | `OPENAI_ADMIN_KEY` 或 `TOKENBAR_OPENAI_ADMIN_KEY` |
| Anthropic | Usage and Cost Admin API | `ANTHROPIC_ADMIN_KEY` 或 `TOKENBAR_ANTHROPIC_ADMIN_KEY` |
| OpenRouter | Credits API | `OPENROUTER_API_KEY`、`TOKENBAR_OPENROUTER_API_KEY` 或 management-key aliases |
| Codex | 本地登录额度窗口 | `~/.codex/auth.json` |
| MiniMax | Token Plan 当前窗口和周窗口额度 | `MINIMAX_API_KEY` 或 `TOKENBAR_MINIMAX_API_KEY` |
| CC Switch | 本地代理配置、健康状态和滚动用量汇总 | `~/.cc-switch/cc-switch.db` |

Key 可以从 Settings 保存到 macOS Keychain，也可以通过 app 环境变量提供。

TokenBar 会非常明确地区分数据来源质量：

| Badge | 含义 |
| --- | --- |
| `Live` | 已成功获取供应商数据。 |
| `Local` | 已从 Claude Code 或 Codex 摄取本地 Agent 用量。 |
| `CC Switch` | 已从 CC Switch sqlite 数据库读取本地代理配置或汇总。 |
| `Needs key` | 已有实时适配器，但没有可用 Key。 |
| `Error` | 适配器已运行，但供应商返回错误或不可读响应。 |
| `Unsupported` | 已有供应商元数据，但尚未实现实时适配器。 |

OpenRouter 的 credits endpoint 不暴露 token buckets、request counts 或周期花费。TokenBar 会把这些字段标记为 unknown，而不是填充假的零值。Anthropic 组织用量需要以 `sk-ant-admin` 开头的 Admin API key；普通 Claude API key 不能授权组织 usage 和 cost report endpoints。

## 安全模型

TokenBar 是 local-first 设计：

- API 绑定 `127.0.0.1`，不暴露到公网。
- 非 health 端点需要 bearer token。
- 本地 token 存在 Application Support，并使用仅当前用户可读写的权限。
- Browser CORS 被限制为 localhost origins。
- 供应商 Key 从环境变量或 Keychain 读取。
- CC Switch keys 只在内存中读取，不会导入 TokenBar Keychain。
- 未知供应商字段保持 unknown，不会变成误导性的零值。

## 开发

本地运行 app：

```bash
./script/build_and_run.sh
```

验证构建和本地 API：

```bash
./script/build_and_run.sh --verify
```

verify 模式会使用 Xcode 构建 `TokenBar.xcodeproj`，停止任何旧的 `TokenBar` 进程，临时启用本地 API 偏好设置，然后为刚构建出的 executable 准备一个 ad-hoc signed verifier copy。

verifier 会运行 TokenBar 内置的 `--tokenbar-verify-local-api` 路径，不依赖 LaunchServices 或窗口会话。它会等待一个真正拥有 `127.0.0.1:3847` listening socket 的进程，并返回：

```json
{"status":"ok","service":"TokenBar"}
```

`--verify` 是本地 API acceptance check，不是可视化 UI smoke test。需要通过 LaunchServices 启动已签名 macOS app 时，请使用默认的 `./script/build_and_run.sh` 路径。

运行 CLI smoke checks：

```bash
./bin/tokenbar status
./bin/tokenbar usage ingest --agent claudeCode --provider anthropic --model claude-sonnet --session-id smoke --cost-usd 0.12 --total-tokens 24000 --json
./bin/tokenbar routing record --agent codex --intent smoke --provider openai --model gpt-5 --estimated-cost 0.10 --actual-cost 0.08 --estimated-tokens 12000 --actual-tokens 9500 --success --json
./bin/tokenbar routing stats --json
./bin/tokenbar usage codex-session --transcript /path/to/codex-rollout.jsonl --json
printf '{"model":"gpt-5","prompt":"Implement the CLI preflight estimate and verify the hook."}' | ./bin/tokenbar check --agent codex --provider openai --codex-hook-json --intent implement --json
./bin/tokenbar check --agent codex --provider anthropic --model claude-sonnet --estimated-cost 0.20 --estimated-tokens 12000 --intent debug
./bin/tokenbar check --agent codex --provider openai --model gpt-5 --estimated-cost 0 --estimated-tokens 0 --intent implement
```

## 发布打包

创建本地 release DMG：

```bash
./script/package_release.sh
```

release 脚本会 archive macOS app，生成拖拽到 Applications 的 DMG，并诚实报告 artifact 是 ad-hoc、Developer ID signed，还是已经 notarized。缺少 Apple credentials 时，它不会假装签名或 notarization 已完成。

运行 `./script/package_release.sh --help` 查看 Developer ID 和 notarization 输入项。

## 当前状态

TokenBar 是一个已经具备发布形态的早期产品 shell，包含：

- Guard-first macOS dashboard
- 菜单栏决策 popover
- 工作区策略 cards 和 durable policy storage
- 用于 Agent preflight checks 的 loopback local API
- 带 bearer auth 的 policy、quota、pace 和 usage endpoints
- 带离线 `tokenbar.yml` fallback 的 CLI preflight
- 可工作的 Codex 和 Claude Code hook 示例
- Claude Code statusline usage ingestion
- 带 session 去重的 Codex transcript usage ingestion
- OpenAI organization usage and cost adapter
- Anthropic Usage and Cost Admin API adapter
- OpenRouter Credits API adapter
- MiniMax Token Plan quota adapter
- Codex login quota adapter
- CC Switch local proxy rollups
- Keychain-backed provider key storage
- 能区分 live data、missing credentials、adapter errors、local usage 和 unsupported providers 的 provider source badges
- 本地 release DMG packaging

下一步生产化方向是加入更多真实适配器、供应商专属 rate-limit headers，以及更多 admin usage APIs。
