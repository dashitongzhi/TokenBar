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

Verify build, launch, and the local API:

```bash
./script/build_and_run.sh --verify
```

The verify mode builds `TokenBar.xcodeproj` with Xcode, stops any stale `TokenBar` process, temporarily enables the local API preference for the launch, then waits up to 20 seconds for an actually started process, not a launch-suspended stub, that owns a listening socket on `127.0.0.1:3847` and returns the expected `{"status":"ok","service":"TokenBar"}` health payload. It restores the previous local API preference when the script exits; if the API was disabled before verification, it also stops the verification app process so the listener does not remain active. Set `TOKENBAR_VERIFY_TIMEOUT=<seconds>` to adjust the deadline.

The script is wired into Codex through `.codex/environments/environment.toml`.

## Release Packaging

Create a local release DMG:

```bash
./script/package_release.sh
```

The release script archives the macOS app, stages a drag-to-Applications DMG, and reports whether the artifact is ad-hoc, Developer ID signed, or notarized. It does not pretend signing or notarization are complete when Apple credentials are missing.

Run `./script/package_release.sh --help` for Developer ID and notarization inputs.

## Current Status

This is a releaseable early product shell:

- Guard-first dashboard
- Workspace policy cards
- Menu bar decision popover
- Local API for agent preflight checks
- OpenAI organization usage and cost adapter with Keychain-backed admin key storage
- Provider source badges that distinguish live data, missing credentials, and unsupported providers
- API monitor catalog retained as an integration surface

The next production step is adding another real adapter, such as Claude Code statusline data, Anthropic Admin API, or OpenRouter credits.
