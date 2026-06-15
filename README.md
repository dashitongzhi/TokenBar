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
- Reads live OpenAI and Anthropic organization usage when admin keys are available

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

## Agent Hook Examples

Working hook examples live in `examples/hooks/`.

For Codex, copy or adapt `examples/hooks/codex-hooks.json` into `.codex/hooks.json`. Codex discovers project hooks from `.codex/hooks.json` or inline `.codex/config.toml` hook tables, and `UserPromptSubmit` hooks receive the prompt and model on stdin. See the [Codex hooks docs](https://developers.openai.com/codex/hooks).

For Claude Code, merge `examples/hooks/claude-settings.example.json` into `.claude/settings.json` or `.claude/settings.local.json`. Claude Code `UserPromptSubmit` hooks can return a top-level `decision: "block"` with a `reason`, which the TokenBar example emits when `tokenbar check` returns `2`. See the [Claude Code hooks docs](https://docs.anthropic.com/en/docs/claude-code/hooks).

Both shell hooks accept these environment overrides:

```bash
TOKENBAR_BIN=/absolute/path/to/tokenbar
TOKENBAR_PROVIDER=anthropic
TOKENBAR_MODEL=claude-sonnet
TOKENBAR_ESTIMATED_COST=0.25
TOKENBAR_ESTIMATED_TOKENS=20000
TOKENBAR_INTENT=refactor
```

## Live Provider Usage

TokenBar supports live organization usage for:

- OpenAI organization usage and cost APIs with `OPENAI_ADMIN_KEY` or `TOKENBAR_OPENAI_ADMIN_KEY`
- Anthropic Usage and Cost Admin API with `ANTHROPIC_ADMIN_KEY` or `TOKENBAR_ANTHROPIC_ADMIN_KEY`

Keys can be saved from Settings into the macOS Keychain, or supplied through the app environment. Anthropic live usage requires an Admin API key that starts with `sk-ant-admin`; standard Claude API keys are still useful for inference, but they do not authorize the organization usage and cost report endpoints. Anthropic currently supplies live token and cost buckets here; TokenBar marks message request counts and Claude Console subscription quotas as unknown instead of estimating them.

Provider source badges are deliberately literal:

- `Live`: TokenBar fetched provider data successfully.
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
- CLI preflight with `tokenbar status`, `tokenbar check`, upward `tokenbar.yml` lookup, and offline policy fallback
- Working Codex and Claude Code `UserPromptSubmit` hook examples
- OpenAI organization usage and cost adapter with Keychain-backed admin key storage
- Anthropic Usage and Cost Admin API adapter with matching Keychain-backed admin key storage
- Provider source badges that distinguish live data, missing credentials, adapter errors, and unsupported providers
- API monitor catalog retained as an integration surface

The next production step is adding more real adapters, such as Claude Code statusline data, OpenRouter credits, or provider-specific rate-limit headers.
