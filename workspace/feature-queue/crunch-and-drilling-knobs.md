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

## Where each knob lives
- **Crunch-time:** depth → skill granularity + which modes to generate.
- **Runtime (drilling):** mode mix, daily budget, pacing/deadline.

## Open questions
- Default depth per material type (novel vs textbook) — infer from the journey's `intent`?
- Realistic time estimates per mode (need usage data; start with guesses).
- Should depth be re-applied on a re-crunch, or is it fixed at first crunch?
