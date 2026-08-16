# Focus Drift Philosophy

This note explains the model behind `Focus goal`, `Focus windows`, `Plan vs Drift`, `Recovery Loop`, and `Attention Gradient`.

## 1. Whole-day intent and block-level intent are different

Dayflow separates two planning layers on purpose:

- `Focus goal` answers: "What counts as good progress today overall?"
- `Focus windows` answer: "During which specific blocks do I want stricter plan-vs-drift measurement?"

If these are collapsed into one concept, the result is less useful:

- whole-day goals become too rigid
- focused blocks become too vague

## 2. Windows are diagnostic, not restrictive

Focus windows are not timers and not hard locks.

They exist so Dayflow can compare:

- what you intended to work on in a block
- what categories actually appeared in that block

That is why they are optional.

## 3. Multi-category windows are allowed, but less precise

A window can contain more than one focus category because real work blocks are sometimes mixed.

But broader windows reduce diagnostic sharpness:

- a single-theme window gives stronger drift detection
- a multi-theme window says "any of these categories are acceptable here"

So the model trades flexibility against precision.

## 4. Drift is measured against declared intent

Dayflow does not try to decide "real focus" in the abstract.

It measures focus against the plan you declared:

- selected category inside the window -> on-plan
- distraction, idle, or a non-selected category inside the window -> drift

That keeps the metric explicit and inspectable.

## 5. Recovery matters as much as drift

The system is not only trying to find where attention slipped.

It also tracks whether you returned, how quickly, and whether the block recovered before it ended.

That is why `Recovery Loop` sits next to distraction metrics instead of being buried elsewhere.

## 6. Attention state should be descriptive, not moralized

`Attention Gradient` is meant to describe recent state, not judge the user.

The states are there to answer:

- Did attention settle?
- Did it wander?
- Did it recover?

The point is operational clarity, not self-scoring.
