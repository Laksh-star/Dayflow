# Dayflow Dev Ship Log

This file tracks local fork work that may or may not be suitable for upstream Dayflow.

## 2026-08-25

- Added the fork-local `Shape of your day` feature:
  - `Constellation` and `Day Trace` views on the Daily screen.
  - Topic threads inferred from timeline content, saved project mappings, app/domain context, and timing rather than relying only on categories.
  - Local JSON and SVG archives for completed days under `~/Library/Application Support/DayflowDev/day-shapes/`.
  - Automatic refresh when processed cards or focus windows change; no extra AI request or screenshot upload.
- Fixed SVG archive legend serialization and added a format-version refresh so existing local archives regenerate as valid SVG.
- Refined Shape of your day visual output into a structured Constellation and a separate Day Trace archive, with the in-app trace reading panel aligned to the saved view.
- Created `agent/dayflow-upstream-2026-08-25` at upstream Dayflow v2.1.1 as the dated sync/reference branch. The active custom branch remains separate until an upstream change is deliberately integrated.

## 2026-08-13

- Added the Focus Drift suite:
  - Focus windows stored per day for plan-vs-drift analysis.
  - Plan vs Drift summary card in the day rail.
  - Recovery Loop analytics for drift-return behavior inside planned windows.
  - Attention Gradient state derived from recent focus-window context.
  - Planned-window overlays in the timeline.
- Extended the day goal setup flow so whole-day targets and optional focus windows live in the same morning setup.
- Fixed the focus-window editor so a row no longer disappears when editing `Start` or `End`.
- Clarified the setup UX:
  - whole-day goals first
  - optional focus windows second
  - clearer summary-card copy in the right rail
  - clearer focus-window toggle guidance and stronger selected/unselected chip states
  - improved contrast handling for pale category colors in goal/window chips
- Added `userguide.md` documenting the Dayflow Dev workflow, focus-window semantics, sidebar metrics, and export flow.
- Added `docs/focus-drift-philosophy.md` documenting the planning model behind Focus Drift.
- Removed synthetic source-card count tags from Toggl CSV export and kept row counts as preview-only review metadata.

## 2026-08-10

- Rebased the active fork onto upstream `origin/main` at Dayflow v2.0.3.
- Re-established the local dev identity:
  - App name: `Dayflow Dev`
  - Bundle ID: `teleportlabs.com.Dayflow.dev`
  - URL scheme: `dayflow-dev`
  - App support folder: `~/Library/Application Support/DayflowDev/`
- Added `scripts/install-dev-app.sh` for repeatable signed installs into `/Applications/Dayflow Dev.app`.
- Disabled public release notes and Sparkle update checks for the dev bundle.
- Added processing failure diagnostics on failed timeline cards.
- Added Toggl draft export v2:
  - Dayflow-project-to-Toggl-project mapping rules.
  - Grouped preview rows.
  - Personal/distraction exclusion toggles.
  - Exact, 5-minute, or 15-minute rounding.
  - CSV draft export for review/import.
- Added Toggl draft export v3:
  - Detailed, consolidated, and summary export modes.
  - Editable review rows for include/exclude, description, and Toggl project.
  - CSV export now uses the reviewed rows instead of regenerating hidden defaults.
  - Consolidation keeps adjacent related Dayflow cards together while summary mode rolls up by day/project.
- Replaced the production Account/Pro/referral settings with a local Dayflow Dev status panel for the dev bundle.
- Updated Toggl CSV export to use Toggl's import headers and require the Toggl account email.
- Added known-project validation for Toggl export so unknown project names are flagged in preview and blocked at export time.

## Working Principles

- Keep dev-only app identity and storage isolated from public Dayflow.
- Prefer small upstreamable PRs for generic improvements.
- Keep personal/client workflow features in the fork unless they are generalized.
- Build and install through `./scripts/install-dev-app.sh` after app changes.
