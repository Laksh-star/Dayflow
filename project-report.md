# Dayflow Dev Fork Report

This file tracks the local development work added on top of the upstream
`JerryZLiu/Dayflow` repository.

## Fork Goals

- Run a dev-safe Dayflow variant without colliding with the installed production app.
- Add practical export, provider, repair, and privacy tooling for local experimentation.
- Keep changes organized so upstream-friendly pieces can later be proposed as focused PRs.

## Current Branch

- Branch: `agent/markdown-export-dev-fork`
- App name: `Dayflow Dev`
- Dev bundle ID: `teleportlabs.com.Dayflow.dev`
- Dev data directory: `~/Library/Application Support/DayflowDev/`
- Fork remote: `https://github.com/Laksh-star/Dayflow.git`
- Latest pushed commit: current branch HEAD, `Remove duplicate settings standup composer`

## Current Status

- The dev fork is buildable and has a working shared Xcode scheme.
- The CLI unit test path is working and currently covers provider settings, weekly dashboard logic, time parsing, privacy matching, and project-rule suggestions.
- The paid/public app can remain uninstalled or unused while this fork is the active local Dayflow build.
- New Settings areas now cover export, reprocess/repair, privacy rules, provider routing/API configuration, and project tagging.

## Recent Commit Ledger

- `HEAD` - Remove the duplicate Settings standup composer and keep Daily as the canonical standup workflow.
- `8eb9829` - Update fork project report.
- `29be612` - Add privacy diagnostics, privacy presets, improved domain matching, project rollups, and suggested project mappings.
- `bb582fb` - Generalize API provider settings with profiles, auth modes, and token-parameter controls.
- `b9c4012` - Add shared dev test scheme and fix the Dayflow Dev unit-test host/module setup.
- `26f77dd` - Add repair-run provider/model override controls and create this fork report.
- `0d075a2` - Add repair controls, project tagging basics, standup composer, and Markdown v2 export workflow upgrades.
- `0de4c33` - Add privacy rules for recording capture.
- `353e853` - Keep local signing settings out of project metadata.
- `bc2e44e` - Improve API provider card generation.
- `7764e7b` - Support `max_completion_tokens` for newer OpenAI models.
- `89241e5` - Add OpenAI-compatible API provider.

## Implemented Changes

### Dev-safe local fork

- Isolated the dev app name, bundle ID, app support folder, keychain namespace, and URL scheme.
- Disabled production Sparkle update behavior for the dev build path.
- Added local signing cleanup notes and kept generated build artifacts ignored.

### Markdown export

- Added timeline Markdown export from Settings.
- Added Markdown v2 range export with frontmatter, daily sections, tags/categories, and weekly rollup content.
- Kept the Daily view as the canonical standup workflow with copy, regenerate, and export actions.

### OpenAI-compatible API provider

- Added a configurable API provider path for OpenAI-compatible endpoints.
- Supports API key storage in Keychain, base URL, model ID, and provider health test.
- Handles newer OpenAI reasoning/chat models that require `max_completion_tokens` instead of `max_tokens`.
- Reused the richer timeline-card prompt flow so API-generated cards can split a batch into multiple activities.
- Added API profiles for OpenAI, OpenRouter, LiteLLM, local proxies, and custom endpoints.
- Added configurable auth headers: Bearer token, x-api-key, custom header, or no auth header.
- Added token-parameter override so providers can force `max_tokens` or `max_completion_tokens` when auto-detection is wrong.

### Privacy rules engine

- Added app-level screenshot exclusion controls in Settings.
- Added domain and window-title sensitive rules for capture blocking.
- Added current-window preview status so the user can see whether recording is allowed.
- Added v2 diagnostics that explain whether the current screenshot would be captured or hidden and why.
- Added rule presets for Gmail, WhatsApp, banking, and password managers.
- Improved browser-domain matching by extracting URL/domain candidates from window titles.

### Reprocess and repair controls

- Added failed-batch summary for the selected day.
- Added duplicate failed-card cleanup.
- Added retry for only failed batches instead of full-day destructive reprocessing.
- Added repair-run provider override so failed batches can be retried with the current provider, API, Gemini, ChatGPT CLI, Claude CLI, or local provider.
- Added optional model override for API and Gemini repair retries.

### Project utilities

- Added project/client tagging rules based on keywords, domains, apps, and card text.
- Added Settings rollups for today's time by project/client.
- Added suggested project mappings from untagged observed cards.
- Removed the duplicate Settings standup composer so the Daily standup surface remains the single user-facing workflow.

## Local-only Changes

These should probably stay local or be heavily reshaped before an upstream PR:

- Dev app identity and storage isolation.
- Local signing assumptions.
- Any defaults tuned specifically for this machine or fork.

## Candidate Upstream PRs

Good candidates for focused upstream pull requests:

- Markdown export improvements.
- OpenAI-compatible API provider, if generalized and documented.
- Privacy exclusion UI and capture rules.
- Failed-batch repair controls.
- Project tagging, if framed as an optional productivity tool.

Recommended upstream order:

1. Markdown export v2.
2. OpenAI-compatible API provider.
3. Privacy exclusion rules.
4. Failed-batch repair controls.
5. Project tagging.

## Known Gaps

- API provider compatibility is currently OpenAI-compatible chat/completions oriented, not a fully generic provider abstraction.
- API provider profiles do not yet support arbitrary extra headers such as OpenRouter attribution headers.
- Gemini repair model override only applies when the entered model maps to a known `GeminiModel` case.
- Repair retries do not yet let the user select an arbitrary custom endpoint per run.
- Privacy preview is app/window oriented; it does not yet show screenshot redaction thumbnails.
- Project tagging is rules-based and lightweight; it does not yet infer repo paths or Git metadata.
- Suggested project mappings currently append simple `Project=pattern` rules and do not edit existing project rows in place.

## Next Priorities

1. Run Dayflow Dev for another real work session and validate cards, privacy blocking, repair retries, exports, and project rollups against actual usage.
2. Add API provider v2 support for arbitrary extra headers and provider-specific request metadata.
3. Add screenshot/redaction thumbnail preview for privacy rules.
4. Improve project tagging edits so suggestions can merge into existing project rows instead of always appending new rules.
5. Start Git/repo context enrichment for project inference.
6. Prepare a clean upstream Markdown export branch if we decide to open the first PR.

## Verification Notes

- Use Xcode or `xcodebuild` with the dev signing team selected.
- CLI build check:
  `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Dayflow/Dayflow.xcodeproj -scheme Dayflow -configuration Debug -derivedDataPath DerivedData build`
- CLI unit test check:
  `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test -project Dayflow/Dayflow.xcodeproj -scheme Dayflow -destination 'platform=macOS' -derivedDataPath DerivedData`
- Keep `DerivedData/` and `Dayflow/Config/LocalSecrets.xcconfig` out of commits.
- After provider or signing changes, restart Dayflow Dev so macOS permission identity and runtime settings are cleanly reloaded.
