# Feature: Notifications

**Status:** Parked until core is solid. Captured 2026-06-19.
**Why:** local phone reminders are reliable but have "no context" (just an
alarm). Want richer, server-driven notifications ("3 skills due in Calculus").
User previously tried Firebase and it didn't work, so settled for local.

---

## Key fact
Push is **not** "just a server job." A phone only receives push through a
transport it's registered with: transport + app registration + server send. The
*trigger* logic is easy (we already compute due items in /progress); the
*delivery transport* is the work.

## Options
- **Local notifications** — both platforms, no extra app, no server. No context. (have now)
- **ntfy / UnifiedPush** — self-hostable, no Firebase. Requires the **ntfy app**
  as the delivery pipe. Great on Android; works on iOS too.
- **FCM (Firebase)** — the standard, but the setup the user already fought.
- **Web Push (VAPID)** — server-driven, **no extra app**, and the one option
  that covers **web + Android + iPhone** from labib itself. Catch: user must
  "Add to Home Screen" (PWA); iPhone needs iOS 16.4+.

## Recommendation
**Web Push via the PWA** — cross-platform, no extra app, context-rich. Revisit
once the core is rock-solid.

## Open questions
- Are we committing to the installable PWA as the primary mobile surface, or the
  native APK? (Affects push choice: Web Push fits PWA; native APK leans FCM/UnifiedPush.)
- Notification content/cadence (due counts, streaks, quiet hours).
