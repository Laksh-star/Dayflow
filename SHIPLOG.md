# Dayflow Dev Ship Log

This file tracks local fork work that may or may not be suitable for upstream Dayflow.

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

## Working Principles

- Keep dev-only app identity and storage isolated from public Dayflow.
- Prefer small upstreamable PRs for generic improvements.
- Keep personal/client workflow features in the fork unless they are generalized.
- Build and install through `./scripts/install-dev-app.sh` after app changes.
