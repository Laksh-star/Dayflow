# Dayflow Dev Fork Report

This file tracks the local development work added on top of the upstream
`JerryZLiu/Dayflow` repository.

## Fork Goals

- Run a dev-safe Dayflow variant without colliding with the installed production app.
- Add practical export, provider, repair, and privacy tooling for local experimentation.
- Keep changes organized so upstream-friendly pieces can later be proposed as focused PRs.
- Fork/upstream development practices are documented in `docs/fork-development-practices.md`.

## Current Branch

- Branch: `agent/markdown-export-dev-fork`
- App name: `Dayflow Dev`
- Dev bundle ID: `teleportlabs.com.Dayflow.dev`
- Dev data directory: `~/Library/Application Support/DayflowDev/`
- Fork remote: `https://github.com/Laksh-star/Dayflow.git`
- Latest pushed commit: current branch HEAD, `Document Toggl export implementation`

## Current Status

- The dev fork is buildable and has a working shared Xcode scheme.
- The CLI unit test path is working and currently covers provider settings, weekly dashboard logic, time parsing, privacy matching, and project-rule suggestions.
- The paid/public app can remain uninstalled or unused while this fork is the active local Dayflow build.
- New Settings areas now cover export, Toggl draft export, reprocess/repair, privacy rules, provider routing/API configuration, and project tagging.
- First focused upstream PR is open as a draft: [JerryZLiu/Dayflow#319](https://github.com/JerryZLiu/Dayflow/pull/319) for Markdown export v2.

## Recent Commit Ledger

- `HEAD` - Add privacy v3 diagnostics and Toggl API draft export.
- `44762e3` - Remove the duplicate Settings standup composer and keep Daily as the canonical standup workflow.
- `9f106b6` - Add Markdown export v2 on the clean upstream PR branch `agent/markdown-export-v2-pr`.
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
- Relaxed API/OpenAI-compatible card validation so a coherent continuation card up to 90 minutes does not fail the whole batch.

### Privacy rules engine

- Added app-level screenshot exclusion controls in Settings.
- Added domain and window-title sensitive rules for capture blocking.
- Added current-window preview status so the user can see whether recording is allowed.
- Added v2 diagnostics that explain whether the current screenshot would be captured or hidden and why.
- Added v3 diagnostic rows for blocked-app, domain, and window-title checks so the user can see each rule family matching or clearing the current window.
- Added rule presets for Gmail, WhatsApp, banking, and password managers.
- Improved browser-domain matching by extracting URL/domain candidates from window titles.

### Toggl API export

- Added a local Toggl export flow in Settings > Export.
- Stores the Toggl API token in the Dayflow Dev keychain namespace under the `toggl` provider key.
- Stores the Toggl workspace ID in UserDefaults.
- Loads workspace projects from `GET /api/v9/workspaces/{workspace_id}/projects` using Toggl Basic auth with `api_token`.
- Prepares editable draft time entries from the selected Dayflow export date range.
- Draft rows are generated from timeline cards and use Dayflow project-tagging rules as the first-pass source project.
- Draft rows let the user include/exclude entries, edit the Toggl description, and select a real Toggl project before submitting.
- Submits selected rows through `POST /api/v9/workspaces/{workspace_id}/time_entries`.
- Settings > Export now separates local Dayflow tags from real Toggl projects.
- Toggl project mappings use `Dayflow tag=Toggl project` rows so local Dayflow rollups can target explicit Toggl workspace projects.
- Draft preparation checks existing Toggl time entries for the selected date range and unchecks likely duplicates before submit.

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

### Fork account surface

- Replaced the upstream Pro pricing, referral, and upgrade UI in Settings > Account with a local fork status panel.
- The fork panel identifies `LN's Dayflow Dev`, the dev bundle ID, the isolated `DayflowDev` data folder, and `/Applications/Dayflow Dev.app` as the intended installed app.
- Recommendation: keep commercial Dayflow Pro billing/referral surfaces out of this local fork unless a future upstream PR specifically touches account management.

## Local-only Changes

These should probably stay local or be heavily reshaped before an upstream PR:

- Dev app identity and storage isolation.
- Local signing assumptions.
- Any defaults tuned specifically for this machine or fork.

## Candidate Upstream PRs

Good candidates for focused upstream pull requests:

- Markdown export improvements. Draft PR opened: [#319](https://github.com/JerryZLiu/Dayflow/pull/319).
- OpenAI-compatible API provider, if generalized and documented.
- Privacy exclusion UI and capture rules.
- Failed-batch repair controls.
- Project tagging, if framed as an optional productivity tool.
- Toggl export, likely only after the UI language is cleaned up and the integration is documented.

Recommended upstream order:

1. Markdown export v2. Draft opened as [#319](https://github.com/JerryZLiu/Dayflow/pull/319).
2. OpenAI-compatible API provider.
3. Privacy exclusion rules.
4. Failed-batch repair controls.
5. Project tagging.
6. Toggl export.

## Repository Layout Notes

- The nested `Dayflow/Dayflow/` layout is expected for this upstream Xcode project: the repository root contains docs, scripts, and top-level test folders; the first `Dayflow/` folder contains the Xcode project and app targets; the second `Dayflow/Dayflow/` folder contains the app source.
- Important source paths:
  - `Dayflow/Dayflow.xcodeproj` - Xcode project.
  - `Dayflow/Dayflow/` - app source, assets, views, core services, system utilities.
  - `Dayflow/DayflowTests/` and `Dayflow/DayflowUITests/` - Xcode test targets.
  - top-level `DayflowTests/` - an additional upstream test folder.
- Local/generated folders such as `DerivedData/` and files such as `.DS_Store` are not source organization and should stay out of commits.
- Use separate build output folders to avoid dev/public identity confusion:
  - `DerivedDataDev/` for the local dev fork.
  - `DerivedDataPR/` for clean upstream PR builds.

## Known Gaps

- API provider compatibility is currently OpenAI-compatible chat/completions oriented, not a fully generic provider abstraction.
- API provider profiles do not yet support arbitrary extra headers such as OpenRouter attribution headers.
- Gemini repair model override only applies when the entered model maps to a known `GeminiModel` case.
- Repair retries do not yet let the user select an arbitrary custom endpoint per run.
- Privacy preview is app/window oriented; it does not yet show screenshot redaction thumbnails.
- Project tagging is rules-based and lightweight; it does not yet infer repo paths or Git metadata.
- Suggested project mappings currently append simple `Project=pattern` rules and do not edit existing project rows in place.
- Toggl duplicate detection is heuristic; it checks close start/end matches and overlapping entries with matching descriptions or project IDs.
- Toggl export supports explicit Dayflow-tag-to-Toggl-project mappings, but it does not yet support Toggl tasks, tags, or billable flags.

## Next Priorities

1. Run Dayflow Dev for another real work session and validate cards, privacy blocking, repair retries, exports, and project rollups against actual usage.
2. Add API provider v2 support for arbitrary extra headers and provider-specific request metadata.
3. Add screenshot/redaction thumbnail preview for privacy rules.
4. Improve project tagging edits so suggestions can merge into existing project rows instead of always appending new rules.
5. Start Git/repo context enrichment for project inference.
6. Add Toggl task/tag/billable mappings before broader use.
7. Monitor draft PR [#319](https://github.com/JerryZLiu/Dayflow/pull/319), respond to maintainer feedback, and make it ready for review once the scope looks acceptable.

## Verification Notes

- Use Xcode or `xcodebuild` with the dev signing team selected.
- CLI build check:
  `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Dayflow/Dayflow.xcodeproj -scheme Dayflow -configuration Debug -derivedDataPath DerivedDataDev build`
- CLI unit test check:
  `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test -project Dayflow/Dayflow.xcodeproj -scheme Dayflow -destination 'platform=macOS' -derivedDataPath DerivedDataDev`
- Keep `DerivedData/`, `DerivedDataDev/`, `DerivedDataPR/`, and `Dayflow/Config/LocalSecrets.xcconfig` out of commits.
- After provider or signing changes, restart Dayflow Dev so macOS permission identity and runtime settings are cleanly reloaded.
