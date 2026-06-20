# labib — Native App Design Language (research-grounded)

**Status:** Reference for the "Polished & native" redesign. Compiled 2026-06-20
from multi-source research (UX practitioners, NN/g, Apple HIG, Material 3,
Duolingo teardowns, Flutter design community). Citations at the bottom.

> Goal: a phone-first app that reads as a **native, premium app**, not a website
> in a shell. This is the coherent definition of "polished" we kept lacking.

---

## 0. The core insight
"Feels like a website" is not vague — it's a **specific, fixable set of cues**.
Premium feel comes from **restraint + correct platform conventions + precise
motion/feedback timing + perceived performance**, not from more decoration.

---

## 1. The "website smell" — anti-patterns to eliminate
(What makes users say "this is just a website")
- **Top/web-style navigation** instead of a **bottom tab bar**. ← our app does this now.
- **No motion**: instant snaps, full-screen swaps, no shared transitions.
- **No haptics** on actions/confirmations.
- **Generic Material defaults**: default AppBar, ripple, FAB, Roboto, auto-seed
  colors → the "Material smell" that screams generic Flutter.
- **Spinners** for content loads instead of **skeletons**.
- **Hover-state thinking**, selectable text on tappable UI, web button/link styling.
- **Wrong scroll physics**: no momentum / no overscroll bounce.
- **Cramped, full-width web layouts** instead of an 8pt rhythm with breathing room.
- **No gestures**: no swipe-to-dismiss sheets, no edge-swipe back, no swipe row actions.
[smell sources: dev.to native guide; UXMatters; Smashing; Flutter docs]

---

## 2. Navigation & structure (phone-first)
- **Persistent bottom tab bar**, 3–5 items, icon + label, always visible (hide
  only under a modal). Reachable one-handed. [appypie; NN/g]
- **Bottom sheets** for secondary/contextual actions (add material, options),
  modal + swipe-down to dismiss.
- **Hierarchical push/pop** with animated transitions; **edge-swipe back**.
- **Swipe row actions** (archive/delete on journey cards).
- Map to labib: tabs ≈ **Home (journeys) · Study/Today · Progress · Profile**.

## 3. Layout & spacing
- **8pt grid**, 4pt subdivisions. Spacing scale: 4/8/12/16/24/32.
- **≥16pt screen-edge padding**; ≥24pt between sections.
- **Card-based** grouping with **soft, diffuse shadows** (blur ~4–8pt, opacity
  ~8–16%); modals stronger (blur ~16–24, opacity ~20–30%). No harsh shadows.
- **Touch targets ≥ 48×48dp** (iOS 44pt), **≥8px gaps**. [web.dev; HIG; M3]

## 4. Typography
- **One typeface**, hierarchy by **weight + size**, not many fonts.
- Weights: 400 body / 600 emphasis / 700 headline; ≤2 weights per view.
- **Body ≥ 17pt**; support Dynamic Type / text scaling.
- Deliberate, restrained jumps between levels.

## 5. Color & theming
- **Semantic tokens**, not scattered hex. Restrained palette: **1–2 accents**,
  neutrals carry most of the UI; accent only on primary actions/highlights.
- **Full light + dark** via semantic palettes.
- Depth through **subtle elevation/shadow**, optional translucent/blur bars.

## 6. Motion & microinteractions (timing is craft)
- **<100ms** = instant feedback; **150–250ms** tap→feedback; **200–400ms**
  screen transitions. Slow *and* instant both feel cheap. [designshack; M3; HIG]
- **Spring/ease-out**, asymmetric easing; never linear. Playful brand = bouncier
  spring; refined brand = stiffer damping.
- **Shared-element / container transitions** between list → detail.
- **Celebrate completion** (0–300ms): subtle confetti/scale/check on correct
  answer & session complete — paired with sound (optional) + haptic.
- **Animate only** transform/scale/opacity to stay in the 16ms frame budget.

## 7. Haptics ("touch punctuation")
- Fire on confirmations (correct/incorrect), primary taps, scroll snaps,
  completion. **Sparingly** — overuse numbs and gets system haptics disabled.
- Same interaction → same haptic. Sync with visual+audio. Respect system setting.
- Flutter: `HapticFeedback`; richer via `haptic_feedback`/`advanced_haptics`.

## 8. Perceived performance
- Feedback within **<100ms**; **300ms with progress feels faster than 100ms with
  none**. Optimistic UI: act immediately, sync in background.
- **Skeleton screens** (match final layout) for content; perceived ~30–50%
  faster than spinners. Spinners only for short submits.
- 60fps: `ListView.builder` (+ `itemExtent` when uniform), `const` widgets,
  `RepaintBoundary`, no heavy work in `build()`/animation, **test in release on
  a real device**. [LogRocket; Android perf; Flutter docs]

## 9. Gamification — motivating, not manipulative
**Do** (grounded in SDT autonomy/competence/relatedness + goal-gradient):
- **Progress rings/bars & mastery** (we already track mastery/reps/due) — micro-wins.
- **Streaks WITH a freeze/repair** earned by effort (not paid). Duolingo's freeze
  cut churn ~21% and ~48% longer streaks; separates habit-maintenance from goals.
- **XP/levels** for momentum; **daily goal** the user sets (autonomy).
- **Celebratory "juice"** on wins; gentle, natural session end-points.
**Avoid (dark patterns):**
- Streak/guilt anxiety with no recovery (the Snapchat trap), shame/FOMO
  notifications, grinding, infinite scroll, forced public comparison, opaque
  manipulation. Test: "would I explain the mechanic to the user's face / their parents?"
[NN/g; UX Mag; StriveCloud; Duolingo teardowns]

## 10. Flutter execution (kill the "Material smell")
- **Custom `ThemeData`**: `ColorScheme.fromSeed` then **override roles**; custom
  text theme + a real font; theme **every** component (`AppBarTheme`,
  button/input themes). Consider **FlexColorScheme** to do this cleanly.
- Centralize **design tokens** (`app_colors.dart`, `spacing.dart`, `typography.dart`),
  custom `ThemeExtension` (with `copyWith`/`lerp`).
- **Tame ripple** (or replace with custom press/scale + haptic).
- **Motion**: implicit animations for state; `animations` pkg for shared-axis/
  container-transform; **Rive** for interactive/celebration; **Lottie** for simple.
- Native scroll physics + edge-swipe back; consider `flutter_platform_widgets`.
- Pitfalls: default theme, debug-mode perf judgments, jank from heavy list items.

---

## 11. How this maps to labib's screens
- **App shell**: bottom tabs (Home · Study · Progress · Profile), themed.
- **Home (journeys)**: cards with status + a **mastery ring**, swipe actions,
  container-transform into the journey, skeletons while loading, real empty state.
- **Add material**: bottom sheet with paste / file / (later) camera / mic.
- **Crunch/progress**: skeletons + progress, calm states (ties to resilient crunch).
- **Study/drill**: focused card per question, instant feedback + haptic + a
  celebratory correct/complete moment, streak/XP surfaced.
- **Onboarding**: short, progressive; sensible empty states everywhere.

## 12. Build order (gamification-aware from the start)
1. **Foundation**: design tokens + custom theme/typography + app shell (bottom nav)
   + motion/haptic helpers. (No feature change — pure look/feel.)
2. **Home** redesign (cards, rings, skeletons, transitions, swipe) — first visible win.
3. **Study/drill** redesign (feedback, celebration, streak/XP surfaced).
4. **Progress** + **onboarding/empty states**.
5. Gamification mechanics phased in (rings → streak+freeze → XP → rewards).
6. Media inputs woven into "add material" + hands-free study.

---

## Sources (key)
- "Feels like a website" cues: dev.to native guide; UXMatters; Smashing (scroll); Flutter Material docs.
- Premium patterns: superdesign Apple system; NN/g HIG; 925studios & Bundu (Duolingo); procreator; muz.li (dark mode); LogRocket (skeletons).
- Native fundamentals: Apple HIG; Material 3 motion/easing; web.dev tap targets; Android haptics/responsiveness; WWDC springs.
- Gamification: NN/g (autonomy/competence/relatedness; gamification UX); UX Mag (ethics, hot-streak); StriveCloud/Orizon/Propel (Duolingo data); PMC (wellbeing ethics).
- Flutter: Flutter docs (Material3 default, rendering perf); FlexColorScheme; freeCodeCamp theming; Rive/Lottie guides; "make Flutter feel native" (supratimdhara).
