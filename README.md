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

TokenBar is not trying to be another API key switcher. Tools like cc-switch are good at switching providers. TokenBar focuses on deciding whether the current agent run should proceed.

## Early Product Flow

1. Pick the current agent, workspace, provider, model, estimated cost, and token count.
2. TokenBar evaluates the run against the active workspace policy.
3. The menu bar and dashboard show `ALLOW`, `WARN`, or `BLOCK`.
4. External tools can call the local API before they launch a costly task.

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

## Development

Run the app locally:

```bash
./script/build_and_run.sh
```

Verify build and launch:

```bash
./script/build_and_run.sh --verify
```

The script builds `TokenBar.xcodeproj` with Xcode, launches the resulting macOS app, and is wired into Codex through `.codex/environments/environment.toml`.

## Current Status

This is a releaseable early product shell:

- Guard-first dashboard
- Workspace policy cards
- Menu bar decision popover
- Local API for agent preflight checks
- Demo provider/workspace data
- API monitor catalog retained as an integration surface

The next production step is replacing demo spend estimates with real adapters for Claude Code statusline data, OpenAI usage/cost APIs, Anthropic Admin API, and OpenRouter credits.
