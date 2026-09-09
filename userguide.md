# Dayflow Dev User Guide

## The Daily Routine

Dayflow captures desktop work automatically. Use the optional controls only for context it cannot observe or for analysis you actively want.

1. **Morning:** choose **Set goals** only if you want to set a direction. Pick Focus categories; the time target is optional. Add a Planned block only when you want Plan vs Drift for a specific time.
2. **During the day:** do nothing for desktop work. Add offline activity only for meaningful meetings, errands, or work away from the computer.
3. **Close the day:** use the right-rail **Close the day** action. Resolve open tasks, then optionally use the Day review assistant. Carry a task forward only when you explicitly want it in tomorrow's queue.

## Closing the Day

- **Tasks** are small intentions for the selected day. Only open tasks are shown in the primary resolution list. Marking one done, deferring it, or deleting it is always manual.
- **Tasks** do not record actual time. They answer what you intended to do; Dayflow must not invent duration or completion from a task title. A later version may offer an optional estimate, but that will remain planned time rather than time worked.
- **Offline activity** records meetings, offline work, personal activity, or notes. Add a time range only when you know it; that range is an explicit record of what happened. An untimed capture remains a note rather than becoming invented tracked time.
- A timed capture appears as a clearly marked dashed **Manual** interval on the Day timeline. Untimed captures do not appear on the timeline because Dayflow has no truthful position for them.
- Select a task while saving a capture to create an explicit evidence link. **Review** suggestions also compare task wording with desktop cards; choose **Link evidence** to retain a likely connection. Neither action marks a task complete.
- **Mobile inbox:** choose a shared folder, such as an iCloud Drive folder that an iPhone Shortcut can write to, then choose **Import mobile inbox**. Dayflow reads JSON files but never moves or deletes them. It records each imported file path so repeated imports do not create duplicates. A payload needs `body`; it may also contain `kind` (`offline_work`, `meeting`, `personal`, or `note`), ISO-8601 `start` and `end`, `day` (`YYYY-MM-DD`), `taskID`, `categoryID`, and `projectName`.
- **Day review assistant** submits only the selected day's tasks, captures, and desktop cards when you press **Ask**. The three guided review actions answer different questions: **What did I finish?** separates confirmed task completion from recorded work; **What remains?** lists open tasks; **What should I do next?** recommends one open task only when it has matching same-day evidence. With a direct OpenAI provider configured, it uses that provider for the answer; otherwise it falls back to the same local evidence rules. Hold the microphone button to transcribe a question, review the transcript in the field, then choose **Ask**. The answer can be spoken with the Mac's system voice.
- When **What should I do next?** identifies an open task with matching evidence, choose **Carry ... to tomorrow** to move that task into the next day's queue. This is always an explicit decision; it does not infer completion or create tracked time. Morning setup shows open planned and carried tasks above your direction as a reminder only. They do not change focus categories, planned blocks, or time tracking.

The developer Voice review prototype under Settings -> Other remains available to diagnose transcription separately. It supports on-device and explicitly selected OpenAI high-accuracy transcription; the latter submits only the held recording after release and removes the temporary audio file after transcription. **OpenAI high accuracy affects speech-to-text only.** The `Speak answer` control deliberately uses macOS's local system voice, so it is fast, private, and has no additional API cost.

This guide covers the fork-specific workflow in `Dayflow Dev`.

## Weekly application interactions

The Weekly dashboard now includes **Interactions between most used applications** after the Focus breakdown. It groups the week's non-system, non-idle timeline cards by their recorded primary application/site and draws the most frequent changes from one application to another.

- Nodes represent the applications with the most recorded time; their size follows relative time, not productivity.
- Select a node to inspect its total recorded time, work/personal/distraction split, and its strongest visible application switches.
- Node colour uses the dominant recorded context by minutes. An app is not marked as a distraction because of one short distraction interval.
- Lines represent observed switches between those applications within a day. They are not a claim of causality or task completion, and graph position has no semantic meaning.
- The pattern and distraction panels use the same recorded transitions. When a card has no application/site metadata, Dayflow excludes it from this section instead of guessing.
- Use the download control on hover to export the graph as a PNG.

## Advanced Planning

Open **Set goals** only when you want to set a direction. Most days need just Focus categories; everything else is optional.

### Focus Categories

These are whole-day targets.

- `Focus categories`: categories you want to spend focused time on today, plus an optional total target duration.
- `Distraction budget`: categories you want to constrain today, plus a total allowed duration. It is under **More options**.

These numbers are independent of planned blocks. They describe the entire day.

### Planned Blocks

These are optional planned blocks used only for drift analysis.

Each planned block has:

- a label
- a start time
- an end time
- one or more focus categories

Use them when you want Dayflow to compare planned deep-work blocks against what actually happened.

Examples:

- `Writing block`, `9:00 AM - 11:00 AM`, categories: `Research & Strategy`
- `Build block`, `2:00 PM - 4:00 PM`, categories: `Engineering / Product`

If you skip planned blocks, Dayflow still tracks your day normally. You just will not get plan-vs-drift metrics for that day.

Important:

- Planned-block categories come from your current `Focus categories`.
- Each window can use one or more of those categories.
- Filled chips mean `this category counts as on-plan in this window`.
- Gray chips mean `this category is available, but ignored for this window`.
- Removing a category from `Focus categories` removes it from all planned blocks because it is no longer part of your focus set for the day.

## How Planning Works

Recommended order:

1. Pick your `Focus categories` and optional total time.
2. Open `More options` only if you use a distraction budget.
3. Add one or more `Planned blocks` only if you want plan-vs-drift analysis.
4. Click `Confirm`.

Notes:

- Planned blocks do not replace Focus categories.
- Planned blocks are narrower: they only define specific blocks to evaluate.
- A multi-category window means: `any of these categories counts as focused during this block`.
- If you want stricter drift analysis, prefer one theme per window instead of mixing many categories together.
- The app now keeps a window visible while you edit start and end times, even if the intermediate state is temporarily invalid.

### Example Mental Model

- `Focus categories`
  - "What categories do I want to make progress on today overall?"
- `Planned block`
  - "During this specific block, which subset of those focus categories should count as on-plan?"

Example:

- Focus categories:
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

### Today’s Direction

Shows progress against:

- your whole-day focus categories target
- your whole-day distraction budget

### Plan vs Drift

Only measures time inside planned blocks.

- `Planned`: total minutes inside all planned blocks
- `On plan`: recorded card time inside windows that matches the selected focus categories
- `Drift`: recorded card time inside windows that was distraction, idle, or a non-selected category

### Attention Gradient

This is a recent-state indicator based on the last 30 minutes of planned-block context.

States:

- `Friction`
- `Wandering`
- `Re-entry`
- `Steady`
- `Locked In`

This is descriptive, not a goal.

### Recovery Loop

Only tracks drift and return events inside planned blocks.

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

### Planned block disappeared while editing

This was a bug in earlier builds. Current builds keep the row visible and auto-adjust the opposite bound if needed.

### Sidebar numbers do not match my whole-day goal

Check whether you are looking at:

- `Today’s direction` for whole-day progress
- `Plan vs Drift` for planned-block-only analysis

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
- `Day Trace` places the same intervals across the day, with planned blocks shown behind the trace when you planned them.

Threads are inferred from card titles, saved project mappings, app/domain context, and timing. Existing categories are only a fallback, so this is not a category chart or a performance score.

Select a dot to inspect the source card. Shapes update when the underlying cards or planned blocks change. Dayflow also archives the seven most recently completed days automatically as JSON and SVG files:

`~/Library/Application Support/DayflowDev/day-shapes/YYYY/MM/YYYY-MM-DD.json`

Each day saves two compact visual snapshots beside its JSON archive:

- `YYYY-MM-DD-constellation.svg` for the reflective clustered view.
- `YYYY-MM-DD-day-trace.svg` for the time-ordered view with focus-window overlays.

These files are local-only and do not trigger an AI request or upload any recording.

## Further Reading

- [Focus Drift Philosophy](docs/focus-drift-philosophy.md)
