# Feature: Crunch & Drilling Knobs (adaptive configuration)

**Status:** Parked / to design. Captured 2026-06-16.
**Why:** the crunch is currently generic and superficial — same output regardless
of the material or the user's goal. Users need control over *what* gets generated
and *how* they practise it. Default should be sensible ("balanced"), but every
knob is user-adjustable per journey.

---

## Knob 1 — Question modes (rename + mix)
- **Modes:** *On the Go*, *Short Drill*, *Deep Dive*.
  - "Deep Dive" replaces the old "Problem" mode and **generalises** it:
    problem-solving for a textbook, long discussion / analysis for a novel.
- **Default mix:** ~**40% On the Go / 40% Short Drill / 20% Deep Dive**.
- User can change the mix per journey.

## Knob 2 — Depth (how deeply to master the material)
- A level from **broad overview** → **full mastery**.
  - Novel: maybe just "know the plot and themes."
  - School textbook: "master the details" — overview is not enough.
- Proposed levels (names TBD): **Overview / Familiar / Proficient / Mastery**.
- **Conditions the crunch:** skill granularity, how many skills, depth of
  questions — *and* the bar for considering a skill "done/mastered."

## Knob 3 — Length / pacing  ("40% of what?")
- The mix percentages are of a **per-session / per-day question budget**.
- Define a **daily budget**, e.g. *3 On the Go + 1 Short Drill + 1 Deep Dive*.
- **Convert questions ↔ time** (assume an average time per mode) so a goal can be
  expressed as **time** ("10 min/day") and the app can compute **total days/months**
  to finish a journey.
- User defines **either** a daily budget **or** a deadline; the app derives the other.

---

## Knob 4 — Next-question selection (weighted scorer)  ✅ *implemented*
Replaces the old flat "due-first, then weakest" sort with a **weighted priority
score** per candidate skill (in `drilling.build_session` / `_skill_score`):

```
score = w_overdue · overdue      # days past due ÷ interval, capped at 3
      + w_weak    · (1 − mastery) # shaky skills first
      + w_new     · isNew         # never-seen skills get a leg up
      + w_recency · idleness      # haven't touched it in a while (→1 over ~2 weeks)
```

- **Defaults** (`SELECT_WEIGHTS`): overdue 1.0, weak 1.0, new 0.6, recency 0.3.
  These are the knobs — meant to become per-journey adjustable.
- **Pool:** due-or-new skills first; if a session would be short, top up with the
  next-closest-to-due so you can always get ahead (this also feeds the streak's
  **bank-ahead**).
- **Mode/intensity:** the chosen intensity still filters which question mode is
  served for each picked skill (Knob 1).
- **Adaptive:** weights are nudged by recent accuracy (last ~10 attempts) —
  ≥80% correct leans toward **new** material; ≤40% leans toward reinforcing
  **weak** skills.
- *Not yet:* multiple questions per skill in one session (so no intra-session
  interleaving needed yet); time-based pacing (Knob 3).

## Where each knob lives
- **Crunch-time:** depth → skill granularity + which modes to generate.
- **Runtime (drilling):** mode mix, daily budget, pacing/deadline, **selection weights**.

## Open questions
- Default depth per material type (novel vs textbook) — infer from the journey's `intent`?
- Realistic time estimates per mode (need usage data; start with guesses).
- Should depth be re-applied on a re-crunch, or is it fixed at first crunch?
