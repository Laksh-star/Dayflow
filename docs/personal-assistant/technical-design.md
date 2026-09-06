# Dayflow Personal Assistant - Technical Design

**Status:** Draft for review  
**Companion:** [Product Requirements](requirements.md)

## 1. Architecture Position

The feature extends existing Dayflow-local storage, daily timeline views, Markdown export, and AI-provider infrastructure. It does not introduce an independent cloud service.

```
Timeline cards + manual captures + tasks + focus windows
                         |
                         v
                 Day context assembler
                         |
                         v
         Reconciliation engine / conversation retrieval
                         |
                         v
      Review UI, text conversation, push-to-talk voice UI
```

The database is authoritative. Markdown is a rendered human-readable record plus an optional suggestion source.

## 2. Proposed Data Model

Names are provisional and should match existing GRDB conventions during implementation.

### `dayflow_tasks`

| Field | Notes |
| --- | --- |
| `id` | UUID primary key. |
| `title` | Required user-facing text. |
| `status` | inbox, planned, in_progress, done, deferred, dropped. |
| `created_day` | Dayflow 4 AM-boundary day. |
| `planned_day` | Nullable; supports inbox tasks. |
| `category_id` | Nullable existing timeline category. |
| `project_name` | Nullable, fork-local project/mapping value. |
| `estimate_minutes` | Nullable; never inferred as actual time. |
| `notes` | Nullable user note. |
| `created_at`, `updated_at`, `completed_at` | Unix timestamps. |

Indexes: `planned_day`, `status`, and `updated_at`.

### `manual_captures`

| Field | Notes |
| --- | --- |
| `id` | UUID primary key. |
| `day` | Dayflow day boundary. |
| `body` | Required original capture text. |
| `kind` | offline_work, meeting, personal, note. |
| `start_ts`, `end_ts` | Nullable; both required for a timed interval. |
| `category_id`, `project_name` | Nullable. |
| `source` | desktop, mobile_shortcut, review, conversation. |
| `source_payload` | Nullable raw structured import payload for audit/debug. |
| `created_at`, `updated_at` | Unix timestamps. |

Constraint: `end_ts > start_ts` whenever both values are present. A timed capture stays separate from automated cards to preserve provenance.

### `task_evidence_links`

| Field | Notes |
| --- | --- |
| `id` | UUID primary key. |
| `task_id` | Foreign key to task. |
| `source_type` | timeline_card or manual_capture. |
| `source_id` | Existing card ID or capture UUID. |
| `strength` | direct, likely, manual. |
| `matched_by` | user, deterministic, semantic_suggestion. |
| `created_at` | Unix timestamp. |

Unique index: `task_id`, `source_type`, `source_id`.

### `day_review_decisions`

This records explicit user decisions, not model conclusions.

| Field | Notes |
| --- | --- |
| `id` | UUID primary key. |
| `day` | Day reviewed. |
| `task_id` | Nullable for capture-only decisions. |
| `kind` | complete, carry_forward, defer, drop, link_evidence, create_task, dismiss. |
| `payload_json` | Decision-specific data. |
| `created_at` | Unix timestamp. |

### Conversation persistence

V1 stores a compact review text thread only when the user chooses `Save review`. Audio is never stored. The persisted record contains user text, assistant text, selected scope, cited record IDs, and provider metadata needed for transparency. A transient session remains in memory only.

## 3. Services

### `TaskService`

Owns validation, lifecycle changes, task queries, carry-forward, and task/capture links. It must be the only write path for task state.

### `ManualCaptureService`

Validates time ranges, assigns the 4 AM-boundary day, imports Shortcut payloads, and exposes timeline-ready intervals. It never creates an automated processing card.

### `DayReconciliationService`

Builds review candidates in two stages:

1. **Deterministic:** time overlap, matching category, matching project, explicit task link, and capture type.
2. **Optional semantic ranking:** LLM or local heuristic may rank candidate cards by title/body similarity, but it can only create a `likely` suggestion.

No service may mark a task done, add a time range, or export Toggl time without a user decision.

### `DayContextAssembler`

Creates a bounded, source-labeled context bundle for conversation:

- selected-day timeline cards and their time ranges;
- focus windows and Plan vs Drift metrics;
- task list and task evidence links;
- manual captures;
- relevant previous-day carry-forward history; and
- optional Markdown note excerpts only when explicitly selected.

The bundle uses stable record identifiers. The UI uses those IDs to render citations and deep links.

### `ReviewConversationService`

Uses the existing provider abstraction and chat UI pathway where possible. It receives:

- user question;
- selected scope;
- assembled context bundle;
- explicit permissions: `read_only` or `propose_actions`.

It must return structured output, not only prose:

```json
{
  "answer": "...",
  "evidence": [{"type": "timeline_card", "id": "1042", "claim": "..."}],
  "uncertainties": ["..."],
  "proposals": [{"kind": "carry_forward", "task_id": "...", "label": "..."}]
}
```

Malformed provider output falls back to plain text with no actionable proposals.

### `VoiceConversationService`

This service is an adapter around the text conversation service:

1. user holds push-to-talk;
2. speech is transcribed locally when available;
3. transcript is displayed and can be edited or cancelled;
4. submitted text goes through `ReviewConversationService`;
5. response may be spoken with local `AVSpeechSynthesizer`.

The voice layer is not allowed to write data directly.

## 4. Voice Capability Approach

The implementation must begin with a contained technical spike because macOS speech-recognition availability and on-device language support vary by OS and machine.

Preferred APIs:

- `AVAudioEngine` for push-to-talk audio capture.
- `SFSpeechRecognizer` for transcription when authorization and local recognition are available.
- `AVSpeechSynthesizer` for local spoken output.

Fallback behavior:

- microphone denied or speech unavailable: open the same conversation field with typed input;
- transcription unavailable: show a clear unavailable state, never upload audio to a provider as a fallback;
- cloud speech transcription is out of scope unless separately approved.

Permission requests occur only after the user invokes voice. The first release has no background audio session and no wake word.

## 5. UI Integration

### Daily view

- Add a compact `Tasks` section near existing goals/focus surfaces.
- Add manual captures as differentiated timeline intervals and/or a capture row in day review.
- Add `Review day` entry point after sufficient activity exists.

### Review surface

Use a panel or sheet with three regions:

1. summary of planned work, observed work, and manual captures;
2. small, actionable review queue;
3. conversation thread with evidence links and confirmation buttons.

No modal should block normal timeline use. Empty states should make no claim about missing activity.

### Voice affordance

Use a microphone icon with a visible pressed/recording state and a tooltip. It belongs in the conversation composer, not permanently in the main recording controls.

## 6. Markdown Export and Import

Exported Markdown appends structured sections only when they contain data:

```markdown
## Tasks
- [x] Prepare Finch review (42m linked evidence)
- [ ] Send proposal -> carried to 2026-09-07

## Manual captures
- 7:30 PM-8:15 PM | Personal | Cooked dinner

## Review decisions
- Carried “Send proposal” to tomorrow.
```

Optional Markdown-derived suggestions recognize only stable patterns:

- Markdown checkbox lines;
- explicit `HH:MM-HH:MM | type | text` capture lines;
- a named `## Tomorrow` section.

Parsing runs on demand in review and returns suggestions. It never writes directly.

## 7. Toggl Relationship

Tasks are not Toggl entries. Existing Toggl export continues to use reviewed timeline rows and mappings.

Later, a reviewed task may provide default project/category metadata for a linked capture or card. The CSV export preview remains the final review boundary, preserving current safeguards against unwanted project creation.

## 8. Migration, Compatibility, and Failure Handling

- Add GRDB migrations only; do not alter existing timeline-card semantics.
- New tables must tolerate empty state and be safe to delete individually only through an explicit settings action.
- Keep all new views hidden/empty when no feature data exists.
- A provider failure leaves review data untouched and offers retry or text-only local summary where possible.
- A failed mobile import remains in the inbox with its original payload and a visible reason.

## 9. Tests

### Block-level tests

- Task lifecycle, carry-forward, and state transitions.
- Capture day-boundary handling and timed interval validation.
- Evidence matching clips overlap correctly and does not create duplicate links.
- Reconciliation does not mutate task state without a decision.
- Markdown render/parse round trips for structured sections.
- Conversation context bundle excludes unrelated days by default and preserves citations.
- Structured conversation-output parsing degrades safely on invalid provider output.
- Voice permission denial and transcription-unavailable fallback to text.

### Manual acceptance checks

- Existing daily timeline and Toggl export operate with no task/capture data.
- A timed mobile capture renders on the correct day and remains visibly manual.
- A user can reject every review suggestion without losing activity data.
- A voiced question and the equivalent typed question produce the same cited answer.
- No raw audio remains after a session ends.

## 10. File-Level Starting Points

Exact files should be confirmed against the current upstream-rebased checkout before implementation. Likely surfaces include:

- `Dayflow/Dayflow/Models/` for new models.
- `Dayflow/Dayflow/Core/StorageManager.swift` and migrations for persistence.
- `Dayflow/Dayflow/Views/UI/MainView/` and daily-view components for tasks, capture, and review entry points.
- Existing chat/provider services for `ReviewConversationService` integration.
- Existing Markdown export services for structured task/capture sections.
- Existing iPhone/mobile-inbox import code for structured Shortcut payloads.

## 11. Delivery Order

1. Block 0: voice capability spike.
2. Block 1: local task and capture foundation.
3. Block 2: reconciliation and Markdown.
4. Block 3: grounded text conversation.
5. Block 4: public push-to-talk voice review.
6. Block 5: structured mobile capture.

Blocks 1 and 2 create the durable evidence model. Block 3 is the minimum useful assistant. Block 4 changes the interaction mode, not the assistant's authority or data model.
