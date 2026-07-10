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

## Implemented Changes

### Dev-safe local fork

- Isolated the dev app name, bundle ID, app support folder, keychain namespace, and URL scheme.
- Disabled production Sparkle update behavior for the dev build path.
- Added local signing cleanup notes and kept generated build artifacts ignored.

### Markdown export

- Added timeline Markdown export from Settings.
- Added Markdown v2 range export with frontmatter, daily sections, tags/categories, and weekly rollup content.
- Added a standup-friendly text path for quick copy/paste into Slack or Teams.

### OpenAI-compatible API provider

- Added a configurable API provider path for OpenAI-compatible endpoints.
- Supports API key storage in Keychain, base URL, model ID, and provider health test.
- Handles newer OpenAI reasoning/chat models that require `max_completion_tokens` instead of `max_tokens`.
- Reused the richer timeline-card prompt flow so API-generated cards can split a batch into multiple activities.

### Privacy rules engine

- Added app-level screenshot exclusion controls in Settings.
- Added domain and window-title sensitive rules for capture blocking.
- Added current-window preview status so the user can see whether recording is allowed.

### Reprocess and repair controls

- Added failed-batch summary for the selected day.
- Added duplicate failed-card cleanup.
- Added retry for only failed batches instead of full-day destructive reprocessing.
- Added repair-run provider override so failed batches can be retried with the current provider, API, Gemini, ChatGPT CLI, Claude CLI, or local provider.
- Added optional model override for API and Gemini repair retries.

### Project and standup utilities

- Added project/client tagging rules based on keywords, domains, apps, and card text.
- Added standup composer for Yesterday / Today / Blockers text.

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
- Standup composer and project tagging, if framed as optional productivity tools.

## Known Gaps

- API provider compatibility is currently OpenAI-compatible chat/completions oriented, not a fully generic provider abstraction.
- Gemini repair model override only applies when the entered model maps to a known `GeminiModel` case.
- Repair retries do not yet let the user select an arbitrary custom endpoint per run.
- Privacy preview is app/window oriented; it does not yet show screenshot redaction thumbnails.
- Project tagging is rules-based and lightweight; it does not yet infer repo paths or Git metadata.

## Verification Notes

- Use Xcode or `xcodebuild` with the dev signing team selected.
- CLI build check:
  `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Dayflow/Dayflow.xcodeproj -scheme Dayflow -configuration Debug -derivedDataPath DerivedData build`
- CLI unit test check:
  `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test -project Dayflow/Dayflow.xcodeproj -scheme Dayflow -destination 'platform=macOS' -derivedDataPath DerivedData`
- Keep `DerivedData/` and `Dayflow/Config/LocalSecrets.xcconfig` out of commits.
- After provider or signing changes, restart Dayflow Dev so macOS permission identity and runtime settings are cleanly reloaded.
