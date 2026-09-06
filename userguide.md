# Dayflow Dev User Guide

## Review Day: tasks, manual captures, and voice

Open the right-side day summary and choose **Review day**. This is the local workspace for closing the loop between what you intended, what Dayflow observed on the desktop, and activity it could not observe.

- **Tasks** are small intentions for the selected day. Marking one done, deferring it, or deleting it is always manual.
- **Manual captures** record meetings, offline work, personal activity, or notes. Add a time range only when you know it; an untimed capture remains a note rather than becoming invented tracked time.
- **Review** suggestions compare task wording with the day's desktop cards. They are suggestions, not automatic completion.
- **Ask about this day** answers from the selected day's local tasks, captures, and desktop cards. Hold the microphone button to transcribe a question, review the transcript in the field, then choose **Ask**. The current answer is grounded locally and can be spoken with the Mac's system voice.

The developer Voice review prototype under Settings -> Other remains available to diagnose transcription separately. It supports on-device and explicitly selected OpenAI high-accuracy transcription; the latter submits only the held recording after release and removes the temporary audio file after transcription.

This guide covers the fork-specific workflow in `Dayflow Dev`.

## Morning Setup

When Dayflow asks, "Where do you want to spend your time today?", treat the screen in two layers.

### 1. Day Targets

These are whole-day targets.

- `Focus goal`: categories you want to spend focused time on today, plus a total target duration.
- `Distraction limit`: categories you want to constrain today, plus a total allowed duration.

These numbers are independent of focus windows. They describe the entire day.

### 2. Focus Windows

These are optional planned blocks used only for drift analysis.

Each focus window has:

- a label
- a start time
- an end time
- one or more focus categories

Use them when you want Dayflow to compare planned deep-work blocks against what actually happened.

Examples:

- `Writing block`, `9:00 AM - 11:00 AM`, categories: `Research & Strategy`
- `Build block`, `2:00 PM - 4:00 PM`, categories: `Engineering / Product`

If you skip focus windows, Dayflow still tracks your day normally. You just will not get plan-vs-drift metrics for that day.

Important:

- Focus-window categories come from your current `Focus goal` categories.
- Each window can use one or more of those categories.
- Filled chips mean `this category counts as on-plan in this window`.
- Gray chips mean `this category is available, but ignored for this window`.
- Removing a category from `Focus goal` removes it from all focus windows because it is no longer part of your focus set for the day.

## How the Setup Screen Works

Recommended order:

1. Pick your `Focus goal` categories and total time.
2. Pick your `Distraction limit` categories and total time if you use it.
3. Add one or more `Focus windows` if you want plan-vs-drift analysis.
4. Click `Confirm`.

Notes:

- Focus windows do not replace the focus goal.
- Focus windows are narrower: they only define specific blocks to evaluate.
- A multi-category window means: `any of these categories counts as focused during this block`.
- If you want stricter drift analysis, prefer one theme per window instead of mixing many categories together.
- The app now keeps a window visible while you edit start and end times, even if the intermediate state is temporarily invalid.

### Example Mental Model

- `Focus goal`
  - "What categories do I want to make progress on today overall?"
- `Focus window`
  - "During this specific block, which subset of those focus categories should count as on-plan?"

Example:

- Focus goal categories:
  - `Engineering / Product`
  - `Directing Business C&A`
- Window 1:
  - `9:00 AM - 11:00 AM`
  - selected categories: `Engineering / Product`
- Window 2:
  - `2:00 PM - 3:00 PM`
  - selected categories: `Directing Business C&A`

That gives cleaner `Plan vs Drift` signals than one large mixed window covering both.

## Right Rail Summary

### Today's targets

Shows progress against:

- your whole-day focus goal
- your whole-day distraction budget

### Plan vs Drift

Only measures time inside focus windows.

- `Planned`: total minutes inside all focus windows
- `On plan`: recorded card time inside windows that matches the selected focus categories
- `Drift`: recorded card time inside windows that was distraction, idle, or a non-selected category

### Attention Gradient

This is a recent-state indicator based on the last 30 minutes of focus-window context.

States:

- `Friction`
- `Wandering`
- `Re-entry`
- `Steady`
- `Locked In`

This is descriptive, not a goal.

### Recovery Loop

Only tracks drift and return events inside focus windows.

It summarizes:

- recovery count
- average return time
- unresolved drift count

## Export Workflow

### Markdown Export

Use Settings -> Export -> `Export as Markdown` for structured day exports.

### Toggl Draft Export

Use Settings -> Export -> `Export Toggl CSV` when you want a reviewable draft before importing into Toggl.

The mapping format is:

```text
Dayflow project -> Toggl project | keyword,domain,app
```

Examples:

```text
Coding -> Directing Business Consulting | xcode,cursor,github,git,swift
Meetings -> Directing Business Consulting | zoom,teams,meet,calendar
Distractions -> SKIP | distraction,x.com,twitter,youtube
```

Export notes:

- The preview row count is for review only; it is not exported as a Toggl tag.
- The CSV tags are intended to stay lightweight and should not contain synthetic card-count markers.

## Troubleshooting

### Focus window disappeared while editing

This was a bug in earlier builds. Current builds keep the row visible and auto-adjust the opposite bound if needed.

### Sidebar numbers do not match my whole-day goal

Check whether you are looking at:

- `Today's targets` for whole-day progress
- `Plan vs Drift` for focus-window-only analysis

Those are different metrics by design.

### Processing failed

Open the failed card and read the diagnostics panel.

Common causes:

- no provider configured
- invalid provider model or API settings
- temporary provider outage or rate limit
- privacy-blocked screenshots

Retry only after the provider issue is fixed.

## Dev App Notes

- Installed app: `/Applications/Dayflow Dev.app`
- Bundle ID: `teleportlabs.com.Dayflow.dev`
- Data folder: `~/Library/Application Support/DayflowDev/`

If you rebuild locally, reinstall with:

```bash
./scripts/install-dev-app.sh
```

## Shape of Your Day

On the `Daily` screen, below the workflow sections, `Shape of your day` turns processed timeline cards into two complementary local views.

- `Constellation` is a reflective end-of-day view. Each dot is a captured work interval; dot size represents duration and lines connect related inferred work threads.
- `Day Trace` places the same intervals across the day, with focus windows shown behind the trace when you planned them.

Threads are inferred from card titles, saved project mappings, app/domain context, and timing. Existing categories are only a fallback, so this is not a category chart or a performance score.

Select a dot to inspect the source card. Shapes update when the underlying cards or focus windows change. Dayflow also archives the seven most recently completed days automatically as JSON and SVG files:

`~/Library/Application Support/DayflowDev/day-shapes/YYYY/MM/YYYY-MM-DD.json`

Each day saves two compact visual snapshots beside its JSON archive:

- `YYYY-MM-DD-constellation.svg` for the reflective clustered view.
- `YYYY-MM-DD-day-trace.svg` for the time-ordered view with focus-window overlays.

These files are local-only and do not trigger an AI request or upload any recording.

## Further Reading

- [Focus Drift Philosophy](docs/focus-drift-philosophy.md)
