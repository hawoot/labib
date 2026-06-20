# Feature: Gamification

**Status:** Design now (with the redesign), implement in phases. Captured 2026-06-19.
**Why:** for a study app, gamification is load-bearing for the *feel* (cf.
Duolingo) — streaks, XP, progress, rewards live inside the core screens. So the
polished redesign must be **gamification-aware from the start** to avoid
reworking screens later. Mechanics ship incrementally.

---

## Decision on timing
- **Design:** together with the "Polished & native" redesign (same pass).
- **Implementation:** phased, not all at once.

## Candidate mechanics (phase order, rough)
1. **Progress / mastery rings & bars** — surface what we already track (mastery,
   reps, due) visually on home + progress + end-of-session.
2. **Streaks** — daily-practice streak (with the usual streak-freeze grace).
3. **XP / levels** — points per attempt/session; level-ups.
4. **Rewards & celebratory moments** — animations on correct/mastered/streak,
   session-complete celebration.
5. (later) badges/achievements, goals, maybe social.

## Data bones we already have
- SkillState.mastery / reps / due_at; Attempt.score/correct. Enough for rings,
  streaks (from attempt timestamps), and basic XP. New tables for XP/achievements
  come when those phases land.

## Open questions
- Tone: motivating but not manipulative (no dark patterns / guilt loops).
- Streak rules (freezes, timezone, grace period).
- Does gamification tie into notifications ("keep your streak")? (See notifications.md.)
