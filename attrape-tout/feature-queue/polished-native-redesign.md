# Feature: Polished & native redesign

**Status:** Parked / to design. Captured 2026-06-19.
**Why:** the current frontend is a functional MVP — stock Material widgets,
default styling. User's reaction: "it really looks like a basic website, nothing
like what I imagined." Engine-first was deliberate; now the look needs to catch
up. **Direction chosen: "Polished & native."**

---

## Direction
- **Mobile-app-first.** NOT a polished website — a sleek, modern, native-feeling
  **mobile app**, designed phone-first. Mobile layouts & touch targets, app
  navigation patterns (bottom nav / gestures, not web menus), real motion &
  transitions, native-feeling components. On desktop, the web build is the same
  mobile app centered in a column — not a desktop website. The phone is primary.
- Custom color theme, rounded cards, smooth animations, proper onboarding.
- **Media woven in** as first-class (see media-capture-and-voice.md).
- **Gamification-aware from the start** (see gamification.md): design reserves
  space + a visual language for streaks / XP / progress rings / rewards so the
  mechanics can be added in phases without reworking these screens.

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
