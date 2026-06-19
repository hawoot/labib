# Feature: Polished & native redesign

**Status:** Parked / to design. Captured 2026-06-19.
**Why:** the current frontend is a functional MVP — stock Material widgets,
default styling. User's reaction: "it really looks like a basic website, nothing
like what I imagined." Engine-first was deliberate; now the look needs to catch
up. **Direction chosen: "Polished & native."**

---

## Direction
- Polished consumer-app feel: custom color theme, rounded cards, smooth
  transitions/animations, a proper home/onboarding, app-shell navigation —
  less "web form."

## Scope (screens to redesign)
- Journey list (home) — start here; highest visibility.
- Add material flow.
- Crunch / progress view.
- Study / drill flow — make it a focused, card-based experience.

## Approach
- Do **theme + home screen first** as a single PR so the user can react on the
  web app before applying the language everywhere.
- Only after the core is confirmed working (see #14) — "make it work, then make
  it pretty."

## Open questions
- Reference apps the user likes the look of (none given yet — ask again).
- Light/dark both polished? (theme already supports both.)
- Bottom nav vs. simple stack given few top-level screens.
