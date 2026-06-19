# TokenBar

TokenBar is a local policy guard for AI coding agents on macOS.

It helps developers stop expensive or unsafe agent runs before they happen: wrong project, wrong provider, wrong model, or a budget that is already too hot.

## What It Does

- Shows a menu bar policy decision: allow, warn, or block
- Evaluates Claude Code, Codex, Cursor, Continue, or custom agent runs
- Applies workspace policies by repo/client/project
- Checks provider allowlists, blocked models, per-run caps, daily budgets, and company-key requirements
- Exposes a local-only HTTP API on `localhost:3847`
- Keeps API-key handling local and Keychain-oriented
- Reads live OpenAI and Anthropic organization usage plus OpenRouter credits when keys are available

TokenBar is not trying to be another API key switcher. Tools like cc-switch are good at switching providers. TokenBar focuses on deciding whether the current agent run should proceed.

## Early Product Flow

1. Pick the current agent, workspace, provider, model, estimated cost, and token count.
2. TokenBar evaluates the run against the active workspace policy.
3. The menu bar and dashboard show `ALLOW`, `WARN`, or `BLOCK`.
4. External tools can call the local API before they launch a costly task.

## CLI Preflight

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

./bin/tokenbar check \
  --agent claudeCode \
  --provider anthropic \
  --model claude-opus \
  --estimated-cost 2.40 \
  --estimated-tokens 180000 \
  --intent refactor
```

`tokenbar check` returns the product-plan exit codes:

- `0`: allow
- `1`: warn
- `2`: block
- `3`: CLI/config/API error

The CLI first calls the running app's `POST /policy/evaluate` endpoint on `http://127.0.0.1:3847`. If the app is not running, it searches upward from the current directory for `tokenbar.yml` or `tokenbar.yaml` and evaluates the same workspace policy locally. If the app responds for a different workspace than the discovered config, the CLI also uses the local config instead of silently accepting the wrong workspace decision. That offline path is intentionally narrow: provider allowlists, blocked model substrings, per-run cost caps, daily budget projection, and company-key requirements mirror the current `PolicyEngine`.

`tokenbar status` reports whether the local app API is reachable and which project config file will be used for offline checks.

`tokenbar usage ingest` sends real local agent usage into the running app. The CLI enriches the usage payload with the nearest `tokenbar.yml` policy, so the app can upsert that workspace, update provider cards, and include local spend in later guard decisions. By default, usage values are treated as cumulative session totals and TokenBar de-duplicates them by `--session-id` or transcript path; pass `--event` when the cost/tokens represent a single event delta.

Claude Code statusline ingestion is available as a one-line bridge:

```bash
tokenbar usage claude-statusline
```

Claude Code passes statusline JSON on stdin. TokenBar extracts the local session id, transcript path, model, cost, token, context-window, and rate-limit fields it recognizes, applies the same de-duplication ledger, and prints a compact statusline string unless `--json` is supplied.

Codex local usage ingestion is available through Codex transcript JSONL files:

```bash
tokenbar usage codex-session --transcript ~/.codex/sessions/2026/06/17/rollout-example.jsonl
```

The Codex bridge reads the latest local `token_count` event, extracts cumulative session tokens, model, context window, cwd, and session id, estimates cumulative spend from model pricing, and posts the same `POST /usage/ingest` payload as other local agents. The app-side ledger applies only the delta since the last ingest for that session, so repeated Stop-hook calls do not double count. Pricing can be overridden with `TOKENBAR_CODEX_INPUT_USD_PER_1M`, `TOKENBAR_CODEX_CACHED_INPUT_USD_PER_1M`, and `TOKENBAR_CODEX_OUTPUT_USD_PER_1M`, or with a project config block:

```yaml
codex:
  pricing:
    gpt-5.5:
      input_per_million: 1.25
      cached_input_per_million: 0.125
      output_per_million: 10.00
```

Use `tokenbar policy init` from a repo root to scaffold a project-local policy:

```bash
tokenbar policy init
```

It writes `./tokenbar.yml` with a workspace id/name inferred from the current directory, the current absolute path, conservative starter budgets, the provider allowlist consumed by `tokenbar check`, and blocked model substrings for high-cost model families. The generated file is immediately compatible with the CLI's offline evaluator and the app's current policy model: allowed providers, preferred provider, blocked models, per-run cap, daily/monthly budget fields, current spend fields, and company-key enforcement.

To also wire project hooks:

```bash
tokenbar policy init --hooks all
tokenbar policy init --codex-hooks
tokenbar policy init --claude-hooks
```

Hook init writes `.codex/hooks.json` and/or `.claude/settings.local.json` using the working shell scripts in `examples/hooks/`. Existing files are left untouched unless you pass `--force`, so merge manually when a project already has hooks. The generated Codex config includes both the `UserPromptSubmit` policy preflight and a `Stop` hook that sends local Codex transcript usage into TokenBar.

### `tokenbar.yml`

Project-level policy files use the shape from `docs/PROJECT_PLAN.md`:

```yaml
version: 1

workspace:
  id: client-app
  name: Client App
  path: ~/project/client-app
  client: acme

budgets:
  daily: 8.00
  monthly: 160.00
  max_run: 1.50
  spend_today: 4.70

providers:
  allowed:
    - anthropic
    - openai
    - openrouter
  preferred: anthropic
  require_company_key: true

models:
  blocked:
    - opus
    - gpt-5-pro
```

The repo includes its own `tokenbar.yml`, so you can dogfood the offline flow immediately.

## Local API

```bash
curl http://127.0.0.1:3847/health
curl http://127.0.0.1:3847/policy
curl http://127.0.0.1:3847/quotas/anthropic
```

Evaluate a proposed agent run:

```bash
curl -X POST http://127.0.0.1:3847/policy/evaluate \
  -H 'Content-Type: application/json' \
  -d '{
    "agent": "claudeCode",
    "workspaceID": "client-app",
    "providerID": "anthropic",
    "model": "claude-opus",
    "estimatedCost": 2.4,
    "estimatedTokens": 180000,
    "intent": "refactor"
  }'
```

Example response:

```json
{
  "decision": {
    "status": "block",
    "agent": "Claude Code",
    "provider": "anthropic",
    "model": "claude-opus",
    "reasons": [
      "Model is blocked by the workspace policy.",
      "Estimated run cost is above the per-run cap.",
      "Projected daily spend would exceed the workspace budget."
    ],
    "recommendation": "Stop this run. Switch provider/model or raise the workspace budget after review."
  },
  "localOnly": true
}
```

Ingest local agent usage:

```bash
curl -X POST http://127.0.0.1:3847/usage/ingest \
  -H 'Content-Type: application/json' \
  -d '{
    "agent": "claudeCode",
    "providerID": "anthropic",
    "model": "claude-sonnet",
    "workspaceID": "client-app",
    "sessionID": "demo-session",
    "source": "Claude Code statusline",
    "costUSD": 0.12,
    "totalTokens": 24000,
    "contextWindowSize": 200000,
    "cumulative": true
  }'
```

Direct Claude Code statusline JSON can also be posted to `POST /usage/claude-statusline`, but the CLI bridge is preferred because it attaches the nearest `tokenbar.yml` policy before ingestion.

## Agent Hook Examples

Working hook examples live in `examples/hooks/`.

For the fastest setup, run `tokenbar policy init --codex-hooks` or `tokenbar policy init --hooks all` from the target repo. To wire it manually, copy or adapt `examples/hooks/codex-hooks.json` into `.codex/hooks.json`. Codex discovers project hooks from `.codex/hooks.json` or inline `.codex/config.toml` hook tables. The TokenBar example uses `UserPromptSubmit` for preflight policy and `Stop` for transcript-backed usage ingestion. See the [Codex hooks docs](https://developers.openai.com/codex/hooks).

For Claude Code, run `tokenbar policy init --claude-hooks` or merge `examples/hooks/claude-settings.example.json` into `.claude/settings.json` or `.claude/settings.local.json`. Claude Code `UserPromptSubmit` hooks can return a top-level `decision: "block"` with a `reason`, which the TokenBar example emits when `tokenbar check` returns `2`. See the [Claude Code hooks docs](https://docs.anthropic.com/en/docs/claude-code/hooks).

Both shell hooks accept these environment overrides:

```bash
TOKENBAR_BIN=/absolute/path/to/tokenbar
TOKENBAR_PROVIDER=anthropic
TOKENBAR_MODEL=claude-sonnet
TOKENBAR_ESTIMATED_COST=0.25
TOKENBAR_ESTIMATED_TOKENS=20000
TOKENBAR_INTENT=refactor
```

For Codex usage ingestion, keep the generated `Stop` hook or run the helper directly with Codex hook JSON on stdin:

```bash
TOKENBAR_BIN=/absolute/path/to/tokenbar examples/hooks/codex-tokenbar-stop.sh
```

For Claude Code statusline ingestion, merge the `statusLine` block from `examples/hooks/claude-settings.example.json` or run the helper directly:

```bash
TOKENBAR_BIN=/absolute/path/to/tokenbar examples/hooks/claude-tokenbar-statusline.sh
```

## Live Provider Usage

TokenBar supports live provider usage for:

- OpenAI organization usage and cost APIs with `OPENAI_ADMIN_KEY` or `TOKENBAR_OPENAI_ADMIN_KEY`
- Anthropic Usage and Cost Admin API with `ANTHROPIC_ADMIN_KEY` or `TOKENBAR_ANTHROPIC_ADMIN_KEY`
- OpenRouter Credits API with `OPENROUTER_API_KEY` or `TOKENBAR_OPENROUTER_API_KEY`; `OPENROUTER_MANAGEMENT_KEY` and `TOKENBAR_OPENROUTER_MANAGEMENT_KEY` are also accepted as aliases
- Codex login quota from the local `~/.codex/auth.json` session via ChatGPT's `/backend-api/wham/usage` endpoint
- MiniMax Anthropic-compatible access verification with `MINIMAX_API_KEY` or `TOKENBAR_MINIMAX_API_KEY`; TokenBar uses the built-in base URL `https://api.minimaxi.com/anthropic` and verifies `GET /v1/models`
- CC Switch local proxy rollups from `~/.cc-switch/cc-switch.db` for configured providers such as MiniMax, DeepSeek, Xiaomi MiMo, GLM, and CC Switch Codex

Keys can be saved from Settings into the macOS Keychain, or supplied through the app environment. Anthropic live usage requires an Admin API key that starts with `sk-ant-admin`; standard Claude API keys are still useful for inference, but they do not authorize the organization usage and cost report endpoints. Anthropic currently supplies live token and cost buckets here; TokenBar marks message request counts and Claude Console subscription quotas as unknown instead of estimating them. OpenRouter live support calls `GET https://openrouter.ai/api/v1/credits` and uses the returned `total_credits` and `total_usage` values as a credit balance meter. OpenRouter does not expose token buckets, request counts, or period spend through that endpoint, so TokenBar marks those fields unknown instead of filling them with estimates. Codex live quota is separate from OpenAI organization usage: it uses the signed-in Codex/ChatGPT auth state on the local machine and reports the 5-hour and 7-day quota windows exposed by the Codex web backend. MiniMax verification proves the key can see the Anthropic-compatible model list; MiniMax token-plan quota and period spend are still shown from local CC Switch rollups when available, not invented from the model-list endpoint. CC Switch keys are read only in memory for optional provider checks such as DeepSeek balance, and are not imported into TokenBar Keychain.

Provider source badges are deliberately literal:

- `Live`: TokenBar fetched provider data successfully.
- `Local`: TokenBar ingested local agent usage, such as Claude Code statusline data or Codex transcript token counts. This is useful for provider cards and guard decisions, but it is not a provider-admin billing API.
- `CC Switch`: TokenBar read local proxy config, health, and rolling usage rollups from the CC Switch sqlite database.
- `Needs key`: the provider has a live adapter, but no usable admin key is available.
- `Error`: the live adapter ran and the provider returned an error or unreadable response.
- `Unsupported`: TokenBar has metadata for the provider, but no live adapter yet.

## Development

Run the app locally:

```bash
./script/build_and_run.sh
```

Verify build and the local API:

```bash
./script/build_and_run.sh --verify
```

The verify mode builds `TokenBar.xcodeproj` with Xcode, stops any stale `TokenBar` process, temporarily enables the local API preference, then prepares an ad-hoc signed verifier copy of the freshly built TokenBar executable. That verifier runs TokenBar's built-in `--tokenbar-verify-local-api` path without depending on LaunchServices or a window session. The script waits up to 20 seconds for an actually started process, not a launch-suspended stub, that owns a listening socket on `127.0.0.1:3847` and returns the expected `{"status":"ok","service":"TokenBar"}` health payload. It restores the previous local API preference and stops the verifier process when the script exits. Set `TOKENBAR_VERIFY_TIMEOUT=<seconds>` to adjust the deadline.

`--verify` is a local API acceptance check, not a visual UI smoke test. Use the default `./script/build_and_run.sh` path when you need to launch the signed macOS app through LaunchServices.

The script is wired into Codex through `.codex/environments/environment.toml`.

Run the CLI smoke checks:

```bash
./bin/tokenbar status
./bin/tokenbar usage ingest --agent claudeCode --provider anthropic --model claude-sonnet --session-id smoke --cost-usd 0.12 --total-tokens 24000 --json
./bin/tokenbar usage codex-session --transcript /path/to/codex-rollout.jsonl --json
./bin/tokenbar check --agent codex --provider anthropic --model claude-sonnet --estimated-cost 0.20 --estimated-tokens 12000 --intent debug
./bin/tokenbar check --agent claudeCode --provider anthropic --model claude-opus --estimated-cost 2.40 --estimated-tokens 180000 --intent refactor
```

## Release Packaging

Create a local release DMG:

```bash
./script/package_release.sh
```

The release script archives the macOS app, stages a drag-to-Applications DMG, and reports whether the artifact is ad-hoc, Developer ID signed, or notarized. It does not pretend signing or notarization are complete when Apple credentials are missing. The default local path uses ad-hoc signing for internal validation; public distribution still needs a Developer ID Application certificate plus notarization credentials.

Run `./script/package_release.sh --help` for Developer ID and notarization inputs.

## Current Status

This is a releaseable early product shell:

- Guard-first dashboard
- Workspace policy cards
- Menu bar decision popover
- Local API for agent preflight checks
- CLI preflight with `tokenbar status`, `tokenbar check`, `tokenbar policy init`, upward `tokenbar.yml` lookup, and offline policy fallback
- Working Codex and Claude Code hook examples
- Claude Code statusline and Codex transcript local usage ingestion with session de-duplication and app workspace policy upsert
- OpenAI organization usage and cost adapter with Keychain-backed admin key storage
- Anthropic Usage and Cost Admin API adapter with matching Keychain-backed admin key storage
- OpenRouter Credits API adapter with matching Keychain-backed API key storage
- Provider source badges that distinguish live data, missing credentials, adapter errors, and unsupported providers
- API monitor catalog retained as an integration surface

The next production step is adding more real adapters, such as provider-specific rate-limit headers and additional admin usage APIs.
