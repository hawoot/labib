# New App — Architecture Blueprint

> The successor to the Proactive Tutor Agent. Same engine, inverted authoring,
> proactive by default. This doc is the north star for the new repo, distilled
> from the design conversation. The old app is **inspiration, not canon** — we
> keep what is the moat and drop the passive posture.

---

## 1. Vision

**Make the book come to life.** A user (or admin) creates a *Learning*, uploads
material — a textbook, a manual, a novel, past exams, or their own structured
notes — and the backend **crunches** it into bite-sized, masterable questions in
three modes. Reading stops being passive: the material drills you, on your
schedule, through on-device nudges.

Two posture changes from the old app define the product:

1. **Material is the first-class citizen.** No more hand-authored curriculum.
   The user uploads documents; an ingestion pipeline derives the curriculum.
2. **The whole app is proactive, not just notifications.** The app always has a
   next thing to suggest. The empty state is a prompt ("What do you want to
   learn? Upload or paste something"), never a void that waits for the user.

---

## 2. The core reframe (why this is low-risk)

The old app already split **engine (code)** from **curriculum (data)**. The
engine — skill selection, EMA mastery, spaced repetition, the three question
modes, the coach/mark/follow-up chat loop, devices, nudges, profile/skill
memory — is subject-agnostic. It does not care whether a `Skill` was typed by an
admin or derived from a book.

So the new app is **not a new engine**. It is the same engine with the
**authoring front-end replaced**: instead of an admin building
`Program → Unit → Skill → Question` by hand (the stated pain point), an
**ingestion pipeline** produces those same rows from uploaded documents.

- **Carries over almost verbatim:** the whole engine (`agent.py`,
  `retrieval.py`), the `owner_id` shared-vs-private trick, the swappable-LLM
  seam, on-device notifications, voice/photo message modalities.
- **New:** the document layer, the crunch pipeline, the proactive **nudge
  engine**, real accounts, per-Learning **intent**.

`retrieval.py` in the old app even says *"Later: embeddings/search over big
programs. Same method."* — the seam for this was designed in advance.

---

## 3. Storage: three layers, each holding what it is best at

```
Object storage (R2/S3/MinIO)   raw uploaded files (PDF/EPUB/docx)   private, per-object ACL
Postgres (relational)          structured world: Learnings,         one shared DB,
                               Documents-metadata, Units, Skills,   owner_id-scoped
                               Questions + all PERSONAL tables
Postgres + pgvector            Chunk embeddings                     retrieval substrate (same DB)
```

Decisions settled in the design talk:

- **Relational, not document store.** The engine scores *every* skill by joining
  `SkillState ↔ Skill ↔ Enrollment`, filtering on `due_at`, aggregating
  `Attempt` history. That is the case *for* SQL. **Postgres.**
- **Files never go in the DB.** Blobs live in object storage; the DB stores a
  pointer + metadata. This is what keeps the DB from bloating — the only growing
  tables are `Attempt` and `Chunk`, handled by indexing then partitioning far
  later. A non-concern until millions of users.
- **One shared DB, `owner_id`-scoped — not a database per user.** Isolation ≠
  separate database. `owner_id IS NULL` = shared library; `owner_id = user` =
  private. Real per-tenant isolation (Postgres RLS / schema-per-tenant) is an
  enterprise concern addable later without a rewrite.
- **Vectors in pgvector, same Postgres** — no separate vector service.
  `sqlite-vec` covers local dev.

---

## 4. Data model

### 4.1 PERSONAL domain — KEEP AS-IS

`User`, `Device`, `NudgeTime`, `Enrollment`, `SkillState`, `Attempt`,
`AttemptMessage`, `Note`, `PracticeOverride`. This is the proven adaptive core.
`AttemptMessage.modality` already supports `voice`; `chat_turn` already accepts
photos — so voice notes and handwriting photos are first-class from day one.

### 4.2 CONTENT domain — evolve

- **Learning** (was `Program`)
  - `owner_id` (NULL = shared library, set = private) — kept.
  - **`intent`** (new): free-text on *how* to crunch/run it — "Socratic novel",
    "A-level exam prep", "just the concepts, no exam". Conditions both the crunch
    and the runtime question/coaching prompts.
  - `status` incl. ingestion state; `curriculum_version` (see §4.3).

- **Document** (new) — **polymorphic** for future media
  - `kind`: `file | url | text | youtube | …` (pluggable per-kind parser).
  - `storage_key` (object-storage pointer) or inline `source_ref` for url/text.
  - `mime`, `title`, `sha256` (dedupe + change detection),
    `status` (`uploaded → parsing → parsed → failed`).

- **Chunk** (new): `document_id`, `ordinal`, `text`, `embedding` (vector),
  page/location. The retrieval substrate.

- **Unit** (recursive tree, kept): now `source = generated|manual`, plus
  **provenance** (which document/chunks it came from).

- **Skill** (kept): plus
  - **`content_key`** (new, critical): a stable slug/hash of the skill's meaning
    (normalized name + short embedding signature), **not** the auto-increment id.
    This is what lets a future re-crunch match new skills to old ones.
  - **provenance** (which chunks).

- **Question** (kept): three modes `on_the_go | short_drill | problem`
  (+ a `discuss` variant for novels), now auto-generated, with provenance.

- **IngestionJob** (new): `learning_id`, `status`, `progress`, token cost,
  `error`, timestamps. Drives the "crunching… 60%" UI and re-runs.

### 4.3 The re-crunch / mastery-preservation decision

**Problem:** the learner's `SkillState` (mastery, spaced-rep) and `Attempt`
history are keyed to skill ids. A naive re-crunch makes new skills with new ids,
orphaning all earned progress.

**Decision:** ship **"accept the reset" in Phase 0**, but bake in three schema
choices now so upgrading to **"carry mastery over"** later is *additive code*,
not a rearchitecture:

1. **`content_key`** on every skill from day one (even if unused at first).
2. **Non-destructive crunch** — re-crunch supersedes (archive / version bump),
   never hard-deletes. Old skills + their `SkillState` survive on disk.
3. **Provenance** recorded — so a later matcher can reason about splits/merges.

The later upgrade: on re-crunch, embed new skills, cosine-match against archived
ones, carry `SkillState` across 1:1 high-confidence matches, start genuinely-new
ones fresh; ambiguous cases keep history on the closest match. Well-trodden,
not exotic.

---

## 5. The two engines

### 5.1 The crunch (ingestion pipeline) — async, token-costly

`Document → structured curriculum`, in passes:

1. **Parse** (pluggable per `Document.kind`): PDF (PyMuPDF), EPUB, docx, md/txt;
   later YouTube transcript, etc. Adding media = add a parser.
2. **Chunk + embed** → `Chunk` rows (+ pgvector).
3. **Structure pass** (LLM): produce the `Unit` tree + atomic `Skill`s,
   **conditioned on the Learning's `intent`** (novel → discussion beats;
   textbook → masterable skills).
4. **Question pass** (LLM): seed the `Question` bank per skill across the three
   modes — the old curated-bank concept, auto-filled.

Cannot run inside an HTTP request. **Phase 0:** a DB-backed job table polled by
an in-process background worker (close to the old "single process" ethos).
**Phase 2:** a real queue (`arq`/`dramatiq` + Redis), which the old
`docker-compose.split.yml` already anticipates.

`ContextRetriever.shared()` changes only its source: retrieve top-k relevant
chunks for a skill (RAG) instead of reading `Unit.content`. `personal()` and
`session()` are untouched.

### 5.2 The nudge engine (the proactive core) — NEW

Mirror image of skill selection. The old engine answers *"what should the
learner practice next?"*. The new app **also** answers *"what should the app
prompt the user to **do** next?"* — deterministic scoring over **candidate
actions** against current state:

- no learnings yet → "What do you want to learn? Upload or paste something."
- un-crunched document → "Fresh material in *X* — want me to crunch it?"
- crunch finished → "*X* is alive — start a 2-min drill?"
- overdue skills → "Integration by parts is due — quick drill?"
- gone quiet N days → "Got something new to add?"

Surfaces as **the home-screen call-to-action** *and* feeds notification copy —
so nudges cover the *whole loop*, not just drilling. Implementation: a computed
`GET /next-actions` (and/or a small `Suggestion` model). Onboarding is just the
first-run state of this engine: the app leads, no empty dashboard.

---

## 6. API surface (FastAPI, kept)

Keep **FastAPI + SQLAlchemy + Alembic** (auto-migrations on startup). New/changed
routers:

- `auth` — anonymous bootstrap + later credential linking (provider-backed).
- `learnings` — CRUD (was library/programs), incl. `intent`.
- `documents` — upload (→ object storage), list, delete; polymorphic `kind`.
- `ingest` — trigger crunch, poll `IngestionJob` status.
- `next_actions` — the proactive feed for the home screen.
- **Kept:** `practice`, `today`, `progress`, `enrollments`, `notes`, `devices`.

Add a **storage abstraction** (local disk dev → R2/S3 prod) mirroring the LLM
provider pattern, and an **embeddings interface** alongside the existing
swappable `llm/` brain.

---

## 7. Auth — anonymous-first via a managed provider

- **Open → use immediately.** A device-backed anonymous account from first
  launch; create a learning and upload with zero signup.
- **Link later, painlessly.** Attach email/Apple/Google to the *same* account id
  when there's something worth syncing — a documented one-liner with the
  provider. No migration of anonymous users.
- **Provider, not roll-your-own:** Supabase Auth or Firebase Auth (bundles Apple
  Sign-In, mandatory on iOS). Clean Flutter SDKs for both.

---

## 8. Frontend — Flutter

Decided: **rewrite the app in Flutter** (best native feel/animation out of the
box, single codebase). The backend stays the moat; the Flutter app is a thin
client over the same HTTP API — so the *API contract* (today the old `api.js`)
carries over even though the code does not. Port: screens, notifications,
theme/brand, the mascot system, voice/photo capture.

Both Flutter and RN are cross-platform, so "nothing platform-dependent" holds.

---

## 9. Extensibility (designed-in, not built now)

- **Polymorphic `Document` + per-kind parser** → YouTube/audio/media later by
  adding a parser; the rest of the pipeline is identical.
- **Swappable LLM + embeddings + storage** behind interfaces.
- **Non-destructive, versioned curriculum** → mastery-preservation upgrade is
  additive.

---

## 10. Plan of action (phased — "design for 3, build 0")

**Phase 0 — prove the loop (self-use):**
1. New repo: FastAPI backend + Postgres (pgvector) + object storage (local disk).
2. Port the PERSONAL domain + engine (`agent.py`, `retrieval.py`) ~verbatim.
3. Build CONTENT domain: `Learning` (+`intent`), `Document` (file + paste-text),
   `Chunk`, `IngestionJob`; `Skill.content_key` + non-destructive crunch baked in.
4. Crunch pipeline (parse md/txt + PDF → chunk/embed → structure → questions) on
   the in-process background worker.
5. `next-actions` endpoint + proactive onboarding.
6. Anonymous auth via provider.
7. Flutter app: onboarding → create learning → upload → crunch status → drill.
   Target the new backend; reuse the API contract from the old app.

**Phase 1:** incremental re-crunch **with mastery carry-over** (light up the
`content_key` matcher), EPUB, public-domain shared library, real push.

**Phase 2:** Postgres + pgvector at scale, real worker queue, R2 storage,
credential linking / multi-device sync, payments.

**Future:** media documents (YouTube, audio), third-party publishing.

---

## 11. Parked decisions

- **Name.** "Learning" as a noun is awkward. Candidates: a *Study*, a
  *Companion*, a *Living Book*, or keep *Course*. Decide later.
- **Re-crunch matching algorithm.** Schema is ready; algorithm lands in Phase 1.
- **Auth provider** (Supabase vs Firebase) — pick at Phase 0 start.
