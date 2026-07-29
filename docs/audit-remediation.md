# Fable 5 audit remediation

This ledger records the repository changes made for the 120 findings in
`tokenbarreview.html`. Duplicate findings are grouped by root cause; a finding
is considered closed only when its concrete failure mode is removed, covered
by a regression check, or explicitly retained as a documented product
boundary.

## Coverage

| Findings | Remediation |
| --- | --- |
| 1–5 | Recoverable JSON persistence; ingest policy isolation; sandbox-safe key discovery; template menu-bar rendering; provider-specific CC Switch credentials and verified official hosts. |
| 6–14 | XCTest runs in CI; finite Ruby policy values and stable exit codes; fail-closed hooks; pinned, same-repository PR review workflow; production models replace verifier shadows; shared provider inference. |
| 15–31 | Shared Swift/Ruby policy contract; validated Local API URLs; explicit Ruby command context/API sessions; functional draft skip; all verifiers registered; isolated verification state; bounded fake servers and CI jobs; prompt via stdin; read-only WAL-aware CC Switch access; shared Xcode scheme and repository-neutral configuration. |
| 32–41 | Trend/responsibility source-size guard; domain types moved into Core and presentation types into UI; App refresh/persistence controllers; DEBUG-only verification; real XCTest execution; unknown data is no longer fabricated or cross-unit summed; shared MiniMax quota mapper; normal `docs/` layout; project license and linked third-party notices. |
| 42–56 | Trusted ingest timestamps; unknown workspaces fail closed; shared provider inference/default models; debounced background persistence; verification does not write user state; deterministic statusline decoding; audit cleanup no longer matches real content; bundle-backed probe templates; calendar bucket resets; severity aggregation; separate context-window values; localization key parity tests and narrower AppState controllers. |
| 57–66 | Local API parsing/encoding runs outside the UI actor with bounded connections; SQLite errors and duplicate external keys are handled; notification recovery resets state; UTC day buckets and request timeouts; token-boundary provider normalization; shared MiniMax transport/window mapping. |
| 67–84 | Ruby coercion/provider helpers; dead launcher removal; portable Ruby entrypoint; safe shell/YAML quoting; meaningful JSON error reporting; nonblocking statusline input; global options in either position; compact policy payloads; hidden notary password; cleaned temporary release fixtures; canonical hook verification; strict release version extraction; Host/Content-Length/path error handling; race-free stable API token; structured logging. |
| 85–108 | Dead menu-bar helpers removed; quota formatting shared; provider normalization dead branches removed; verifier support code shared; provider ordering consolidated where mutated; probe resources loaded from the bundle; README translations corrected; workspace path components enforced; refresh operations are timeout-bounded by provider requests; no fake summary projections; secure token creation; Local API DTO encoding is nonisolated; safe URLs/settings API/model picker tags; legacy Codable defaults are tested. |
| 109–119 | Shared quota-window formatter and MiniMax mapper; official MiniMax hosts aligned; credential precedence and Gemini header transport fixed; SQLite failure handles closed; finite integer decoding; Data Protection Keychain migration; Local API errors and percent-decoded paths distinguished; unofficial Codex usage is explicitly degradable; service responsibilities are represented by dedicated controllers/helpers rather than empty extensions. |
| 120 | Retained as the report's documented design decision: company-key enforcement is OpenAI-specific, and the cross-language policy contract locks that behavior. |

## Verification gates

- `script/verify_regressions.sh`
- `xcodebuild ... test`
- Debug and Release builds with signing disabled
- `git diff --check`

The verification runner covers policy parity, persistence recovery and
migration, SQLite/CC Switch handling, MiniMax mapping, Local API wire and
application behavior, smart-routing accounting, CLI and hook contracts,
release cleanup, and source-responsibility limits.
