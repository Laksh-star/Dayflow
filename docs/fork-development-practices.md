# Fork Development Practices

This note documents how to keep this Dayflow fork useful as a personal/team build while still contributing clean changes back to `JerryZLiu/Dayflow`.

## Working Model

Treat upstream and this fork as related but separate products:

- Upstream is the public Dayflow product and source of truth.
- This fork is a downstream product variant for local development, personal workflows, and team/client experiments.
- Not every useful fork feature should become an upstream pull request.
- Upstream pull requests should be small, generic, and easy for maintainers to review.

## Branch Strategy

Use separate branches for separate jobs:

- `upstream/main`: the latest public source from `JerryZLiu/Dayflow`.
- `main`: the fork's clean mirror of upstream, kept close to `upstream/main`.
- `agent/markdown-export-dev-fork`: the active local Dayflow Dev product branch.
- `pr/<feature-name>`: short-lived clean branches created from `upstream/main` for upstream pull requests.

The dev product branch is allowed to contain local branding, dev signing, local install scripts, Toggl integration, API-provider experiments, and workflow-specific features. PR branches should not contain those local-only changes.

## Feature Classification

Classify each feature before deciding where it belongs.

### Upstream Candidate

A feature is an upstream candidate when it is broadly useful, optional, generic, documented, and has a focused diff.

Examples:

- Markdown export v2.
- OpenAI-compatible API provider, once generalized.
- Privacy exclusion rules.
- Failed-batch repair controls.
- Project tagging, if framed as an optional productivity tool.

### Fork-Only

A feature should stay fork-only when it is personal, team/client-specific, tied to local signing/storage, or opinionated around this machine's workflow.

Examples:

- `LN's Dayflow Dev` account surface.
- Dev bundle ID, app name, app support folder, and install script.
- Personal privacy defaults.
- Local project/Toggl mappings.
- Client-specific exports or report formats.

### Maybe Later

A feature can stay in the fork until it is cleaned up enough for upstream.

Examples:

- Toggl export before tasks/tags/billable mapping and docs are finished.
- API provider profiles before arbitrary headers/provider metadata are supported.
- Git/repo context enrichment before it has clear UI and tests.

## Upstream PR Hygiene

For every upstream PR:

- Start from `upstream/main`, not the long-lived dev fork branch.
- Keep one PR to one feature.
- Avoid local branding, signing changes, generated files, and unrelated cleanup.
- Prefer generic names and defaults.
- Add tests where the behavior is shared or easy to regress.
- Explain the user value from an upstream user's perspective.
- Keep the diff small enough that maintainers can review it without understanding the whole fork.

Recommended upstream order:

1. Markdown export v2.
2. OpenAI-compatible API provider.
3. Privacy exclusion rules.
4. Failed-batch repair controls.
5. Project tagging.
6. Toggl export, only after broader cleanup and documentation.

## Syncing Upstream Into The Fork

Periodically pull upstream changes into the dev branch:

```bash
git fetch upstream
git checkout agent/markdown-export-dev-fork
git rebase upstream/main
```

If the fork grows large and rebases become noisy, switch the long-lived dev branch to merges:

```bash
git fetch upstream
git checkout agent/markdown-export-dev-fork
git merge upstream/main
```

Use rebase while the fork is small and the history is manageable. Use merge once the fork is a durable product branch with many local-only commits.

## Building The Local Product

For this fork, the active local app should be built and installed as `Dayflow Dev`:

```bash
./scripts/install-dev-app.sh
```

After a build, verify the installed app identity:

```bash
plutil -p "/Applications/Dayflow Dev.app/Contents/Info.plist" | rg "CFBundleName|CFBundleIdentifier"
codesign -dv "/Applications/Dayflow Dev.app"
```

Expected identity:

- App name: `Dayflow Dev`
- Bundle ID: `teleportlabs.com.Dayflow.dev`
- Installed path: `/Applications/Dayflow Dev.app`
- Data path: `~/Library/Application Support/DayflowDev/`

## Documentation Discipline

Keep `project-report.md` current with:

- Latest meaningful fork commits.
- Upstream PR candidates.
- Fork-only changes.
- Known gaps.
- Build/install notes.
- Upstream PR status.

Use this note for development policy and `project-report.md` for current state.
