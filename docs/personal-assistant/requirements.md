# Dayflow Personal Assistant - Product Requirements

**Status:** Draft for review  
**Audience:** Dayflow Dev fork  
**Principle:** Dayflow is a private work-memory and reflection product. It is not a generic task manager or an always-listening assistant.

## 1. Product Outcome

Dayflow should help the user close the loop between intention and lived activity:

1. plan a small number of tasks or focus intentions;
2. automatically collect desktop evidence and accept lightweight offline/mobile captures;
3. review what happened at the end of the day; and
4. discuss the day by voice to understand progress and decide what to do next.

The differentiator is evidence-led conversation. The assistant answers from local Dayflow records and makes uncertainty visible. It does not pretend to know whether a task is complete merely because a related app was open.

## 2. Product Boundaries

### In scope

- A lightweight local task model connected to daily work.
- Manual and mobile-friendly captures for activity outside desktop recording.
- An end-of-day reconciliation flow between tasks, timeline evidence, and captures.
- Push-to-talk conversation for post-activity analysis, review, and next-step guidance.
- Markdown export of the resulting daily record.

### Explicitly out of scope

- Replacing Todoist, Things, Linear, or a project-management system.
- Always-on microphone capture, ambient meeting recording, or real-time coaching.
- Automatically marking tasks complete or creating calendar events.
- Cloud sync, collaboration, calendar write access, and external task-service sync.
- Treating free-form Markdown as the authoritative task database.

## 3. Core Concepts

| Concept | Meaning |
| --- | --- |
| Timeline evidence | Processed Dayflow cards produced from desktop activity. |
| Task | A user-owned intention or follow-up with a lifecycle and optional project/category. |
| Capture | A lightweight manual record of offline, mobile, or otherwise uncaptured activity. |
| Evidence link | A connection between a task and timeline cards or captures; it indicates likely work, not completion. |
| Review item | A suggested daily decision, such as completing, carrying forward, or clarifying a task. |
| Conversation | A grounded voice or text discussion over the selected day and its linked records. |

## 4. User Workflows

### 4.1 Start of day

The existing Day Goal and Focus Window flow remains optional and unchanged in purpose. A compact `Today` task list is added alongside it.

The user can:

- create a task from scratch;
- carry forward an unfinished task from yesterday;
- assign an optional project/category and estimate; and
- optionally link a task to a focus window.

The user should be able to start the day with no tasks and use Dayflow as before.

### 4.2 During the day

Desktop activity remains automatic. For activity Dayflow cannot see, the user creates a capture with:

- plain-language note;
- occurrence type: `offline work`, `meeting`, `personal`, or `note`;
- start/end time or duration, when known;
- optional project/category; and
- optional task link.

Examples:

- `Cooked dinner, 7:30 PM - 8:15 PM`
- `Met Priya: campaign follow-up, 35 min`
- `Read the research paper, 25 min`
- `Send proposal to client`

The existing iPhone Shortcut/mobile inbox should evolve to create these structured captures, while retaining raw-note fallback.

### 4.3 End of day

Dayflow presents a small review queue, not a compulsory audit:

- `Likely work found: 48 min on Finch article. Mark task complete?`
- `Captured client meeting has no follow-up task. Create one?`
- `Planned task has no linked evidence. Carry forward, defer, or dismiss?`

The user may ignore every suggestion. The underlying timeline and captures remain unchanged.

### 4.4 Voice conversation

Voice is an analysis and guidance interface, not an activity-capture mechanism.

The user activates it with a visible push-to-talk control and can ask:

- `What did I actually accomplish today?`
- `What was I doing after the Finch work?`
- `What changed since I last worked on this?`
- `What did I plan but not get to?`
- `What are the three best things to resume tomorrow?`

Every substantive answer should identify its evidence in the interface: linked task, capture, and/or timeline interval. The user can open the cited interval from the response.

When an action is proposed, the assistant asks for confirmation. Examples:

- `Create “Send proposal” for tomorrow?`
- `Carry “Review deployment notes” to Monday?`
- `Attach the 35-minute meeting capture to this task?`

## 5. Functional Requirements

### Tasks

- Tasks have a title, lifecycle state, creation day, optional planned day, optional project/category, optional estimate, and notes.
- Supported states are `inbox`, `planned`, `in_progress`, `done`, `deferred`, and `dropped`.
- A task can be created manually, created from a confirmed review suggestion, or carried forward.
- A task can have multiple evidence links.
- Completing or dropping a task always remains a user-confirmed action.

### Captures

- Captures must be creatable without a desktop recording.
- A capture with a time range can appear in the day timeline as a visually distinct manual interval.
- A capture without a duration remains a dated note, not invented tracked time.
- Mobile imports must preserve source, received time, original text, and any supplied occurrence time.

### Reconciliation

- Deterministic temporal/category/project matches generate evidence candidates first.
- Semantic matching may rank additional candidates, but it cannot mutate task state.
- The review identifies evidence strength as `direct`, `likely`, or `none`.
- Carry-forward creates a new planned-day association while retaining task history.

### Conversation

- Conversation is scoped to a selected day by default, with explicit options for `today`, `yesterday`, `this week`, or a task history.
- Responses distinguish direct evidence from inference.
- The assistant can summarize, compare plans against activity, identify unresolved tasks, and propose next actions.
- Voice transcription is shown before the assistant acts on it.
- The user can use the same conversation as text when microphone access is unavailable.

### Markdown

- Dayflow renders structured task, capture, and review data into the existing daily Markdown export.
- It may parse clearly structured Markdown patterns into review suggestions, but user edits to free text never silently create or modify tasks.
- Export contains a stable `Tasks`, `Manual captures`, and `Review decisions` section when data exists.

## 6. Privacy and Trust Requirements

- Task, capture, evidence, and conversation state are local by default.
- Raw microphone audio is transient and is not stored in v1.
- Voice transcription is retained only when the user explicitly saves it as a capture, task note, or review decision.
- Existing provider settings govern LLM requests. The conversation surface clearly indicates when a cloud provider will receive the selected context.
- The assistant must never fabricate precise durations, task completion, or evidence citations.

## 7. Success Criteria

- A user can reconstruct a day that includes desktop and offline work without manually tracking every minute.
- A user can complete a daily review in under five minutes when they choose to do one.
- A user can ask a voice question and open the specific records that support the answer.
- A user can decline suggestions without breaking their timeline or task history.
- Existing Dayflow workflows work unchanged when tasks, captures, and voice are never used.

## 8. Delivery Blocks

Each block is intended to be independently shippable in one focused implementation pass.

### Block 0 - Voice capability spike

**Goal:** Verify macOS push-to-talk transcription, local speech output, permission behavior, and integration with the existing chat/provider pathway.

**Delivers:** A hidden/developer-only voice panel that transcribes one held utterance and can speak its transient transcript. The default mode stays on-device; an explicit `OpenAI high accuracy` mode may submit held audio once to OpenAI's `gpt-transcribe` API after release.

**Done when:** Permission denial is graceful; no audio is persisted; the cloud mode has a clear pre-send disclosure and only accepts a direct `api.openai.com` configuration; text fallback works; the test does not touch task or timeline data.

### Block 1 - Tasks and manual captures

**Goal:** Establish durable local objects for intention and off-desktop activity.

**Delivers:** Task list, capture inbox, manual time range, task/capture storage, and timeline rendering for timed captures.

**Done when:** Tasks and captures persist across relaunches, are editable/deletable, and do not affect existing processing or Toggl export by default.

### Block 2 - Daily reconciliation and Markdown

**Goal:** Turn tasks and evidence into a practical end-of-day review.

**Delivers:** Deterministic evidence linking, review queue, carry-forward decisions, and structured Markdown export sections.

**Done when:** Suggestions never alter task status automatically, links open supporting records, and days without tasks/captures remain visually unchanged.

### Block 3 - Grounded conversation

**Goal:** Make the existing work journal conversational before adding microphone input to the public workflow.

**Delivers:** Text conversation over selected day/task context, evidence citations, response uncertainty rules, and confirmation cards for proposed actions.

**Done when:** The assistant can answer review questions from the local context bundle and cannot write without confirmation.

### Block 4 - Voice review and guidance

**Goal:** Add push-to-talk and optional local speech output to the grounded conversation experience.

**Delivers:** Voice button, transcript preview, spoken answer option, and retained text-thread continuity for the current review.

**Done when:** Voice and text produce the same evidence-backed result, privacy controls are explicit, and no continuous listening exists.

### Block 5 - Mobile structured capture

**Goal:** Extend the existing Shortcut/mobile inbox to submit structured captures.

**Delivers:** A documented Shortcut payload for note, optional time range, type, category/project, and task title; plus an inbox triage surface in Dayflow.

**Done when:** A phone-created capture can be reviewed, linked to a task, and shown in the relevant day without requiring cloud sync.

## 9. Decisions Needed Before Build

1. Should tasks be day-scoped by default, or may they exist without a planned day from the start?
2. Should `personal` captures appear beside work activity in the default timeline, or behind a visibility toggle?
3. Which existing AI providers are acceptable for conversation when local models are unavailable?
4. Should spoken answers be on by default after push-to-talk, or opt-in per response?
5. Should Block 0 be implemented before the foundational task/capture work, or only as a short technical spike?
