<p align="center">
  <img src="TokenBar/Assets.xcassets/AppIconMidnight.imageset/AppIconMidnight.png" alt="TokenBar app icon" width="96" height="96" />
</p>

<h1 align="center">TokenBar</h1>

<p align="center">
  <strong>The local policy gate for AI coding agents on macOS.</strong>
</p>

<p align="center">
  Stop expensive, unsafe, or off-policy agent runs before they touch your repo, your provider quota, or your company key.
</p>

<p align="center">
  <a href="#quick-start"><img alt="Quick start" src="https://img.shields.io/badge/Quick%20Start-CLI%20%2B%20macOS-111827?style=for-the-badge&labelColor=0f172a"></a>
  <a href="#local-api"><img alt="Local API" src="https://img.shields.io/badge/API-127.0.0.1%3A3847-2563eb?style=for-the-badge&labelColor=0f172a"></a>
  <a href="#live-provider-usage"><img alt="Provider usage" src="https://img.shields.io/badge/Usage-OpenAI%20%7C%20Anthropic%20%7C%20OpenRouter%20%7C%20MiniMax-16a34a?style=for-the-badge&labelColor=0f172a"></a>
  <a href="#release-packaging"><img alt="Release packaging" src="https://img.shields.io/badge/Packaging-DMG%20ready-7c3aed?style=for-the-badge&labelColor=0f172a"></a>
</p>

<p align="center">
  <a href="#why-tokenbar">Why TokenBar</a>
  <span> | </span>
  <a href="#who-it-is-for">Who it is for</a>
  <span> | </span>
  <a href="#how-it-works">How it works</a>
  <span> | </span>
  <a href="#quick-start">Quick start</a>
  <span> | </span>
  <a href="#local-api">Local API</a>
  <span> | </span>
  <a href="#agent-hooks">Agent hooks</a>
  <span> | </span>
  <a href="README.design-system.md">Design system</a>
  <span> | </span>
  <a href="#data-sources">Data sources</a>
  <span> | </span>
  <a href="#development">Development</a>
</p>

<p align="center">
  <strong>English</strong>
  <span> | </span>
  <a href="README.zh-CN.md">简体中文</a>
</p>

---

## Why TokenBar

AI coding tools moved faster than the guardrails around them.

TokenBar is a menu bar control plane that decides whether an agent run should proceed. It reads workspace policy, local usage, live provider quota, and the proposed run metadata, then returns a clear `ALLOW`, `WARN`, or `BLOCK` decision before a costly task starts.

It is not another API key switcher. Tools like `cc-switch` are good at routing providers. TokenBar focuses on the harder question:

> Should this agent be allowed to run here, with this model, on this workspace, at this cost?

## The Problem It Solves

| Without TokenBar | With TokenBar |
| --- | --- |
| Agents can launch from the wrong repo or client workspace. | Workspace policies travel with the repo through `tokenbar.yml`. |
| Cost caps live in someone's head or a billing dashboard opened too late. | The CLI and local API check budgets before the run starts. |
| Provider usage is fragmented across OpenAI, Anthropic, OpenRouter, MiniMax, Codex, and local proxies. | TokenBar brings live and local usage into one menu bar surface. |
| Claude Code and Codex hooks are hand-rolled per project. | `tokenbar policy init --hooks all` scaffolds working hook examples. |
| Missing live data is often mistaken for zero spend. | TokenBar marks unknown spend, missing keys, and unsupported adapters explicitly. |

## Product Surface

| Layer | What it does |
| --- | --- |
| Menu bar guard | Shows the current policy decision and active workspace at a glance. |
| Dashboard | Tracks provider usage, workspace budgets, source badges, audit events, and policy status. |
| CLI preflight | Lets hooks and scripts call `tokenbar check` before launching an agent run. |
| Local API | Exposes loopback-only policy, quota, pace, and usage endpoints on `127.0.0.1:3847`. |
| Hook bridge | Connects Codex and Claude Code preflight plus usage ingestion into the same policy engine. |
| Smart Routing mode | Optional user-selected mode that recommends a provider/model from recorded outcomes while keeping guard policy enforcement first. |
| Release path | Builds, verifies, signs ad-hoc for local validation, and packages a DMG. |

## Who It Is For

- Developers who use Codex, Claude Code, or local provider routers on client or company repositories.
- Teams that need workspace-level cost, model, and key-source policy before an agent run begins.
- Operators who want a single local view of live provider quota, local agent usage, and policy health.
- Projects that need repeatable Codex and Claude Code hook setup without hand-rolling shell glue each time.
- Users who want local-first guardrails without uploading prompts, transcripts, keys, or repository data to a third-party service.

## Runtime Requirements

- macOS 14 or newer.
- Xcode or Xcode Command Line Tools for local source builds.
- Optional provider credentials for live usage adapters: OpenAI Admin, Anthropic Admin, OpenRouter, or MiniMax keys.
- Optional local agent state for usage ingestion: Codex sessions under `~/.codex/`, Claude Code statusline output, and CC Switch state under `~/.cc-switch/`.
- A running TokenBar app for the authenticated local API path. The CLI still has a narrow offline fallback through `tokenbar.yml`.

## How It Works

```text
Agent request
  -> tokenbar check
  -> workspace policy
  -> provider and model rules
  -> budget projection
  -> local and live usage context
  -> ALLOW, WARN, or BLOCK
```

The decision engine evaluates:

- Workspace, client, and project identity
- Allowed providers and preferred provider
- Blocked model substrings such as `opus` or `gpt-5-pro`
- Per-run estimated cost and token caps
- Daily and monthly budget projection
- Company-key requirements
- Local usage deltas from Claude Code and Codex
- Live provider state when admin or provider keys are available

Smart Routing is off by default. When the user selects Smart Routing in the app, TokenBar still evaluates the normal guard policy first, then attaches a route recommendation from the local routing ledger, configured models, model catalog, and current provider health. A blocked policy stays blocked even if Smart Routing finds a promising route.

## Quick Start

Run the macOS app locally:

```bash
./script/build_and_run.sh
```

Verify the build and local API readiness path:

```bash
./script/build_and_run.sh --verify
```

Check the current project from the CLI:

```bash
./bin/tokenbar status
```

Create a repo-local policy:

```bash
./bin/tokenbar policy init
```

Evaluate a proposed agent run:

```bash
./bin/tokenbar check \
  --agent codex \
  --provider openai \
  --model gpt-5 \
  --estimated-cost 0 \
  --estimated-tokens 0 \
  --intent implement
```

`tokenbar check` exits with product-plan status codes:

| Exit code | Meaning |
| --- | --- |
| `0` | Allow |
| `1` | Warn |
| `2` | Block |
| `3` | CLI, config, or API error |

## First Install: Privacy and Security

TokenBar is currently intended for local development builds and local DMG validation. If you install a packaged build outside the Mac App Store, macOS may ask you to approve it from **System Settings > Privacy & Security** before the first launch.

TokenBar reads only the local state needed for the features you enable:

- Provider keys are read from environment variables or the macOS Keychain.
- The local API token is stored in TokenBar's sandbox container. The CLI automatically detects both the release container path and the legacy local-development path.
- Codex transcript ingestion reads the transcript file you pass to the CLI or hook.
- Claude Code usage ingestion reads the statusline fields sent by the hook.
- CC Switch usage reads local proxy state and rollups without importing CC Switch keys into TokenBar.

TokenBar does not upload prompts, transcripts, raw logs, local paths, provider keys, or usage records to a remote service.

## CLI Command Center

TokenBar includes a dependency-free local CLI at `bin/tokenbar`.

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

The CLI first calls the running app's authenticated `POST /policy/evaluate` endpoint. If the app is not running, it searches upward from the current directory for `tokenbar.yml` or `tokenbar.yaml` and evaluates the same workspace policy locally. For Codex preflight, `tokenbar check --codex-hook-json` can read a `UserPromptSubmit` payload from stdin and fill missing cost/tokens from the prompt, model, and Codex pricing table before the policy is evaluated.

That offline path is intentionally narrow and predictable: provider allowlists, blocked model substrings, per-run cost caps, daily budget projection, and company-key requirements mirror the current `PolicyEngine`.

`tokenbar routing record` and `tokenbar routing stats` feed the local Smart Routing ledger. In Guard Only mode those stats are stored and visible through the API but do not change recommendations. In Smart Routing mode, `/policy/evaluate` includes a `smartRouting` object with the recommended provider/model, confidence, evidence count, win rate, and alternatives.

Production recommendation stats exclude smoke/test/synthetic evidence before routes are aggregated. A run is excluded when `taskIntent` or `selectedBy` is exactly `smoke`, `test`, `synthetic`, or `fixture`; when `workspaceID`, `workspaceName`, `sessionID`, or `taskID` is `smoke-routing-ledger` or is marked with those words as dash-delimited identifiers; when metadata uses those keys with truthy values or `env`/`environment` names one of those values; or when a synthetic model marker such as `*-unknown-cost` is recorded. Raw records remain in `smart-routing-runs.json`, and `/routing/stats` reports `excludedNonProductionRuns`.

## Project Policy

Use `tokenbar policy init` from a repo root to scaffold a project-local policy:

```bash
tokenbar policy init
```

It writes `./tokenbar.yml` with a workspace id and name inferred from the current directory, the absolute path, conservative starter budgets, and a provider/model policy inferred from local agent configuration. TokenBar reads Codex, Claude Code, and CC Switch model settings when present, chooses a preferred provider plus `models.default`, and uses the same inference for the first-run app workspace.

Example:

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

rules:
  # 0 disables the raw-token rule. Set a positive value to block a run whose
  # estimated tokens are above this cap.
  max_estimated_tokens: 0

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

## Local API

The local API binds to loopback only. `GET /health` is intentionally unauthenticated for readiness checks. Every policy, quota, pace, or usage endpoint requires `Authorization: Bearer <local-token>`.

The app creates the token at:

```text
~/Library/Containers/Kral.TokenBar/Data/Library/Application Support/TokenBar/local-api-token
```

The token file is written with user-only permissions, and the CLI reads it automatically from the sandbox container (or the legacy development path when present). Browser CORS responses are restricted to localhost origins. TokenBar does not emit `Access-Control-Allow-Origin: *`.

```bash
curl http://127.0.0.1:3847/health

TOKENBAR_API_TOKEN="$(cat "$HOME/Library/Containers/Kral.TokenBar/Data/Library/Application Support/TokenBar/local-api-token")"

curl http://127.0.0.1:3847/policy \
  -H "Authorization: Bearer $TOKENBAR_API_TOKEN"

curl http://127.0.0.1:3847/quotas/anthropic \
  -H "Authorization: Bearer $TOKENBAR_API_TOKEN"
```

Evaluate a proposed run through the API:

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

Example response:

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

Working hook examples live in `examples/hooks/`.

Fast setup:

```bash
tokenbar policy init --hooks all
tokenbar policy init --codex-hooks
tokenbar policy init --claude-hooks
```

Hook init writes `.codex/hooks.json` and/or `.claude/settings.local.json` using the shell scripts in `examples/hooks/`. Existing files are left untouched unless you pass `--force`, so projects with custom hooks can merge manually.

| Agent | Preflight | Usage ingestion |
| --- | --- | --- |
| Codex | `UserPromptSubmit` calls `tokenbar check` before the run. | `Stop` reads the Codex transcript JSONL and sends cumulative session usage. |
| Claude Code | `UserPromptSubmit` calls `tokenbar check` before the run. | `statusLine` sends recognized cost, token, context-window, and rate-limit fields. |

Codex's preflight hook estimates a run by default from the submitted prompt and model instead of sending zero cost/tokens. The heuristic uses prompt length, task keywords, conservative Codex input/output budgets, and the same pricing overrides used by `tokenbar usage codex-session`. Both shell hooks accept environment overrides:

```bash
TOKENBAR_BIN=/absolute/path/to/tokenbar
TOKENBAR_PROVIDER=anthropic
TOKENBAR_MODEL=claude-sonnet
TOKENBAR_ESTIMATED_COST=0.25
TOKENBAR_ESTIMATED_TOKENS=20000
TOKENBAR_INTENT=refactor
```

For Codex `UserPromptSubmit`, `TOKENBAR_PROVIDER`, `TOKENBAR_MODEL`, `TOKENBAR_ESTIMATED_COST`, and `TOKENBAR_ESTIMATED_TOKENS` are optional. When Codex supplies a prompt but not an estimate, the hook pipes the JSON payload to `tokenbar check --codex-hook-json`; the CLI estimates prompt tokens and likely run cost before evaluating normal workspace policy. `require_company_key` does not trust `TOKENBAR_KEY_SOURCE` or `--key-source`: the running TokenBar app must find an OpenAI organization credential in its Keychain. When the app is unavailable, the offline fallback blocks instead of trusting a self-reported provenance.

This means expensive Codex prompts can be stopped before they run: if the estimated prompt/run tokens imply a cost above `budgets.max_run`, exceed `rules.max_estimated_tokens`, or push projected daily/monthly spend past the workspace budget, `UserPromptSubmit` returns a Codex block decision. Set `rules.max_estimated_tokens` to `0` to disable the raw-token rule.

Users do not need to edit `tokenbar.yml` to tune the live threshold. Open TokenBar's Workspaces view and adjust each workspace's Per-run cap with the amount field and +/- controls; the value is stored locally and used by the running localhost policy API. `tokenbar.yml` remains the offline fallback when the app API is unavailable.

For manual Codex checks you can pass prompt text directly:

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

## Local Usage Ingestion

Send real local agent usage into the running app:

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

By default, usage values are treated as cumulative session totals. TokenBar de-duplicates deltas by `--session-id` or transcript path, so repeated hook calls do not double count.

Codex pricing can be overridden with environment variables:

```bash
TOKENBAR_CODEX_INPUT_USD_PER_1M=1.25
TOKENBAR_CODEX_CACHED_INPUT_USD_PER_1M=0.125
TOKENBAR_CODEX_OUTPUT_USD_PER_1M=10.00
```

Or through project config:

```yaml
codex:
  pricing:
    gpt-5.5:
      input_per_million: 1.25
      cached_input_per_million: 0.125
      output_per_million: 10.00
```

## Live Provider Usage

TokenBar supports live or local usage signals from:

| Provider or source | What TokenBar reads | Key or local state |
| --- | --- | --- |
| OpenAI | Organization usage and cost APIs | `OPENAI_ADMIN_KEY` or `TOKENBAR_OPENAI_ADMIN_KEY` |
| Anthropic | Usage and Cost Admin API | `ANTHROPIC_ADMIN_KEY` or `TOKENBAR_ANTHROPIC_ADMIN_KEY` |
| OpenRouter | Credits API | `OPENROUTER_API_KEY`, `TOKENBAR_OPENROUTER_API_KEY`, or management-key aliases |
| Codex | Local login quota windows | `~/.codex/auth.json` |
| MiniMax | Token Plan current and weekly quota windows | `MINIMAX_API_KEY` or `TOKENBAR_MINIMAX_API_KEY` |
| CC Switch | Local proxy config, health, and rolling usage rollups | `~/.cc-switch/cc-switch.db` |

Keys can be saved from Settings into the macOS Keychain or supplied through the app environment.

TokenBar is deliberately honest about source quality:

| Badge | Meaning |
| --- | --- |
| `Live` | Provider data was fetched successfully. |
| `Local` | Local agent usage was ingested from Claude Code or Codex. |
| `CC Switch` | Local proxy config or rollups were read from the CC Switch sqlite database. |
| `Needs key` | A live adapter exists, but no usable key is available. |
| `Error` | The adapter ran, but the provider returned an error or unreadable response. |
| `Unsupported` | Provider metadata exists, but no live adapter is implemented yet. |

OpenRouter does not expose token buckets, request counts, or period spend through its credits endpoint. TokenBar marks those fields unknown instead of filling them with fake zeros. Anthropic organization usage requires an Admin API key that starts with `sk-ant-admin`; standard Claude API keys do not authorize the organization usage and cost report endpoints.

## Data Sources

TokenBar keeps provider, local, and estimated data visibly separate.

| Source | What it contributes | Trust level |
| --- | --- | --- |
| `tokenbar.yml` | Workspace identity, budgets, allowed providers, blocked models, and offline policy fallback. | Project policy |
| Local API payloads | Authenticated policy decisions, provider status, usage summaries, and Smart Routing stats. | Local runtime |
| Codex sessions | Transcript token events and cumulative session usage when ingested through the CLI or hooks. | Local record |
| Claude Code statusline | Recognized cost, token, context-window, and rate-limit fields. | Local record |
| Provider admin APIs | Organization cost, usage, quota, or credit data when a supported admin key is available. | Live provider |
| Smart Routing ledger | Local outcome evidence used only when Smart Routing is enabled. | Local estimate |

Unknown values stay unknown. Estimated costs, fallback token counts, and route confidence are treated as estimates, not bills or official quota.

## Security Model

TokenBar is designed to be local-first:

- The API binds to `127.0.0.1`, not the public network.
- Non-health endpoints require a bearer token.
- The local token lives under Application Support with user-only permissions.
- Browser CORS is restricted to localhost origins.
- Provider keys are read from environment or Keychain.
- CC Switch keys are read only in memory and are not imported into TokenBar Keychain.
- Unknown provider fields stay unknown instead of becoming misleading zero values.

## Development

Run the app locally:

```bash
./script/build_and_run.sh
```

Verify build and local API:

```bash
./script/build_and_run.sh --verify
```

The verify mode builds `TokenBar.xcodeproj` with Xcode, stops any stale `TokenBar` process, temporarily enables the local API preference, then prepares an ad-hoc signed verifier copy of the freshly built executable.

The verifier runs TokenBar's built-in `--tokenbar-verify-local-api` path without depending on LaunchServices or a window session. It waits for a real process that owns a listening socket on `127.0.0.1:3847` and returns:

```json
{"status":"ok","service":"TokenBar"}
```

`--verify` is a local API acceptance check, not a visual UI smoke test. Use the default `./script/build_and_run.sh` path when you need to launch the signed macOS app through LaunchServices.

Verify the first-run demo defaults upgrade path:

```bash
mkdir -p .build/verification
swiftc TokenBar/App/AppPreferencesStore.swift script/verify_app_preferences_migration.swift -o .build/verification/verify_app_preferences_migration
./.build/verification/verify_app_preferences_migration
```

This creates a temporary `UserDefaults` suite that simulates an older install with `removedDemoSeedDefaultsV1=true` and lingering demo `selectedProviderID`, `selectedWorkspaceID`, `selectedModel`, cost, and session budget values. The success message confirms the V2 cleanup is not short-circuited by the legacy V1 marker and remains stable on a second load.

Run CLI smoke checks:

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

Verify Smart Routing production stats filtering:

```bash
./script/verify_smart_routing_production_stats.sh
```

## Release Packaging

Create a local release DMG:

```bash
./script/package_release.sh
```

The release script archives the macOS app, stages a drag-to-Applications DMG, and reports whether the artifact is ad-hoc, Developer ID signed, or notarized. It does not pretend signing or notarization are complete when Apple credentials are missing.

Run `./script/package_release.sh --help` for Developer ID and notarization inputs.

## FAQ

### Is TokenBar an official OpenAI, Anthropic, or OpenRouter product?

No. TokenBar is an independent local macOS tool for policy checks, local API integration, and provider usage visibility.

### Does TokenBar replace provider routers such as CC Switch?

No. Provider routers decide where requests go. TokenBar decides whether a proposed agent run is allowed under the active workspace policy, then records usage and routing outcomes locally.

### Does TokenBar upload my prompts, transcripts, or usage?

No. TokenBar is local-first. Hooks and CLI commands send data to the loopback API on `127.0.0.1`, and provider calls only happen when you configure the matching live adapter key.

### Why do some provider fields show as unknown?

Some APIs do not expose every budget, quota, or token field. TokenBar keeps those fields unknown instead of pretending missing live data is zero spend.

### Can TokenBar block every expensive Codex prompt automatically?

Yes, when the Codex hook is installed and the estimated run cost exceeds the workspace policy. The default gate is cost-policy based; add explicit policy rules if a workspace needs a fixed token ceiling.

## Current Status

TokenBar is a releaseable early product shell with:

- Guard-first macOS dashboard
- Menu bar decision popover
- Workspace policy cards and durable policy storage
- Loopback local API for agent preflight checks
- Bearer-authenticated policy, quota, pace, and usage endpoints
- CLI preflight with offline `tokenbar.yml` fallback
- Working Codex and Claude Code hook examples
- Claude Code statusline usage ingestion
- Codex transcript usage ingestion with session de-duplication
- Optional Smart Routing mode with local outcome-ledger recommendations
- OpenAI organization usage and cost adapter
- Anthropic Usage and Cost Admin API adapter
- OpenRouter Credits API adapter
- MiniMax Token Plan quota adapter
- Codex login quota adapter
- CC Switch local proxy rollups
- Keychain-backed provider key storage
- Provider source badges that distinguish live data, missing credentials, adapter errors, local usage, and unsupported providers
- Local release DMG packaging

The next production step is adding more real adapters, provider-specific rate-limit headers, and additional admin usage APIs.
