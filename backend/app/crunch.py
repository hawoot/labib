"""The crunch: Document(s) -> Chunks -> Unit/Skill tree -> Question bank.

A synchronous function driven by the background worker. The LLM does the heavy
lifting (structuring + question writing); this module is orchestration:
parse, chunk, prompt, parse JSON, persist, and report progress on the job.

No embeddings (see the retrieval decision): structuring walks the material in
order, and each skill records the chunk ids it came from (provenance), which
the question pass uses as grounding.
"""
from __future__ import annotations

import logging
from concurrent.futures import ThreadPoolExecutor

from sqlalchemy.orm import Session

from . import models
from .chunking import chunk_text
from .llm import complete_json
from .parsing import parse_document

logger = logging.getLogger(__name__)

# Crunch bounds.
#   - We first try a SINGLE PASS: the whole material in one LLM call, for maximum
#     coherence (an exam / small book never gets chopped up). If the provider
#     rejects it as too long for its context window, we fall back to the chunked
#     path. SINGLE_PASS_CEILING_CHARS skips the attempt only when the material is
#     physically too big for any model's context (so we don't fire a doomed
#     multi-MB request) — it is NOT the decision threshold; the API is.
#   - CHUNKED path: split into STRUCTURE_WINDOW_CHUNKS windows, structure each
#     (in parallel), then a CONSOLIDATION pass merges/regroups the draft skills
#     into one authoritative curriculum (windows overlap, so skills repeat).
#   - SAFETY_MAX_CHUNKS is a high guardrail against runaway cost; if a journey
#     exceeds it the extra is dropped AND a visible notice is recorded.
STRUCTURE_WINDOW_CHUNKS = 24
SAFETY_MAX_CHUNKS = 1500          # ~1500 × ~1500 chars ≈ a few thousand pages
SINGLE_PASS_CEILING_CHARS = 500_000  # ~125k tokens — beyond any current context
MAX_PROVENANCE_CHARS = 4000
STRUCTURE_MAX_TOKENS = 16000
CONSOLIDATION_MAX_TOKENS = 16000
QUESTION_MAX_TOKENS = 4000
# Per-call timeout: a hung LLM call fails the job loudly instead of freezing the
# progress bar forever.
LLM_TIMEOUT = 240

# The structure windows and the per-skill question calls are independent LLM
# calls, so we fan them out concurrently instead of one-after-another. This is
# the difference between a crunch taking minutes vs. hours once a document
# yields many skills (the question pass is one call per skill). The LLM result
# is computed in worker threads; all DB writes stay on the calling thread.
CRUNCH_CONCURRENCY = 8

QUESTION_MODES_HINT = (
    "Generate a spread of modes per skill — about 2 'on_the_go', 1 'short_drill', "
    "1 'deep_dive'. Each mode has a strict meaning:\n"
    "- on_the_go: ZERO logistics. Answerable entirely out loud, hands-free, while "
    "walking down the street — no paper, no screen, no keyboard, no written "
    "calculation. Quick recall, definitions, concepts, intuition, or 'why / how "
    "would you approach this'. For technical subjects keep it conceptual and "
    "verbal (e.g. 'what does integration by parts let you trade off?') and NEVER "
    "ask to compute or derive something on paper. For narrative material, recall "
    "or briefly discuss plot, characters, or themes.\n"
    "- short_drill: one focused, concrete rep — a single application answerable in "
    "a minute or two. A little written/typed working is fine if the subject needs "
    "it (a line of algebra, a short snippet), but keep it small and quick.\n"
    "- deep_dive: the stretch question requiring real engagement — multi-step "
    "problem-solving for technical material (may require paper or a keyboard, which "
    "is expected and fine) or extended analysis / discussion for narrative material "
    "(can be fully conversational)."
)


def _set(db: Session, job: models.IngestionJob, *, phase=None, progress=None):
    if phase is not None:
        job.phase = phase
    if progress is not None:
        job.progress = progress
    db.commit()


def _map_concurrent(fn, items, on_complete=None):
    """Run `fn` over `items` concurrently (bounded by CRUNCH_CONCURRENCY) and
    return results in input order.

    An item that raises has its exception stored as its result (not re-raised)
    so a single bad LLM call doesn't sink the whole batch — callers check
    `isinstance(result, Exception)`. `on_complete(done, total)` (if given) runs
    on the calling thread as each item finishes, for progress updates. The
    worker threads do pure LLM work and never touch the DB session.
    """
    from concurrent.futures import as_completed

    if not items:
        return []
    results: list = [None] * len(items)
    workers = min(CRUNCH_CONCURRENCY, len(items))
    with ThreadPoolExecutor(max_workers=workers) as ex:
        futures = {ex.submit(fn, item): i for i, item in enumerate(items)}
        done = 0
        for fut in as_completed(futures):
            i = futures[fut]
            try:
                results[i] = fut.result()
            except Exception as e:  # noqa: BLE001 - captured per item
                results[i] = e
            done += 1
            if on_complete is not None:
                on_complete(done, len(items))
    return results


def run_crunch(db: Session, journey: models.Journey, job: models.IngestionJob) -> None:
    # Non-destructive versioning: a re-crunch supersedes via a version bump;
    # old units/skills/questions stay on disk.
    has_prior = (
        db.query(models.Skill).filter_by(journey_id=journey.id).count() > 0
    )
    version = journey.curriculum_version + 1 if has_prior else journey.curriculum_version
    journey.curriculum_version = version
    job.curriculum_version = version
    # Capture as a plain string up front: the concurrent LLM calls reference it
    # from worker threads, and reading journey.intent there could lazy-load from
    # the (single-threaded) DB session.
    intent = journey.intent or "general mastery"

    # 1) Parse + chunk every document --------------------------------------
    _set(db, job, phase="parsing", progress=5)
    db.query(models.Chunk).filter_by(journey_id=journey.id).delete()
    chunks: list[models.Chunk] = []
    documents = list(journey.documents)
    for doc in documents:
        text = parse_document(doc)
        for i, piece in enumerate(chunk_text(text)):
            c = models.Chunk(
                document_id=doc.id, journey_id=journey.id, ordinal=i, text=piece
            )
            db.add(c)
            chunks.append(c)
        doc.status = "parsed"
    db.flush()  # assign chunk ids
    if not chunks:
        raise ValueError("No text could be extracted from this journey's documents.")

    # 2) Structure: try one coherent pass; fall back to chunked + consolidate.
    total_chunks = len(chunks)
    used = chunks[:SAFETY_MAX_CHUNKS]
    dropped = total_chunks - len(used)
    job.dropped_count = dropped
    if dropped > 0:
        pct = int(100 * len(used) / total_chunks)
        job.notice = (
            f"This journey is large — only the first {len(used)} of "
            f"{total_chunks} sections (~{pct}%) were included. Split it into "
            "smaller journeys to cover everything."
        )

    skills: list[models.Skill] = []

    # 2a) Single pass: the whole material in one call (skip only if it's
    #     physically too big for any context window). A context error from the
    #     API just routes us to the chunked path — the API is the real arbiter.
    used_chars = sum(len(c.text) for c in used)
    single_units = None
    if used_chars <= SINGLE_PASS_CEILING_CHARS:
        _set(db, job, phase="reading everything", progress=20)
        numbered = "\n\n".join(f"[{i}] {c.text}" for i, c in enumerate(used))
        try:
            single_units = _structure_call(intent, numbered)
        except Exception as e:  # too-long (expected) or any failure -> chunk
            logger.info("single-pass structuring fell back to chunked: %s", e)
            single_units = None

    if single_units is not None:
        job.mode = "single_pass"
        _set(db, job, phase="organising", progress=45)
        skills = _persist_units(
            db, journey, version, single_units.get("units", []) or [], used, None, 0
        )

    # 2b) Chunked fallback: structure each window in parallel -> draft skills.
    if not skills:
        job.mode = "chunked"
        windows = [
            used[i : i + STRUCTURE_WINDOW_CHUNKS]
            for i in range(0, len(used), STRUCTURE_WINDOW_CHUNKS)
        ]
        job.section_count = len(windows)
        _set(db, job, phase=f"reading {len(windows)} sections", progress=22)
        numbered_windows = [
            "\n\n".join(f"[{i}] {c.text}" for i, c in enumerate(window))
            for window in windows
        ]
        structures = _map_concurrent(
            lambda nm: _structure_call(intent, nm),
            numbered_windows,
            on_complete=lambda d, t: _set(db, job, progress=22 + int(20 * d / t)),
        )
        raw_skills: list[dict] = []
        for window, structure in zip(windows, structures):
            if isinstance(structure, Exception) or structure is None:
                logger.warning("structure window failed: %s", structure)
                continue
            raw_skills += _flatten_skills(structure.get("units", []) or [], window)
        if not raw_skills:
            raise ValueError(
                "The structure pass produced no skills — the AI service may be "
                "unavailable. Try crunching again."
            )
        # 2c) Consolidation: merge duplicates + regroup into the authoritative tree.
        _set(db, job, phase="consolidating", progress=46)
        consolidated = _consolidate_skills(intent, raw_skills)
        if consolidated is not None:
            skills = _persist_consolidated(
                db, journey, version,
                consolidated.get("units", []) or [], raw_skills, None, 0,
            )
        if not skills:  # consolidation failed/empty -> keep the draft, ungrouped
            logger.warning("consolidation produced nothing; using draft skills")
            skills = _persist_raw_flat(db, journey, version, raw_skills)

    db.flush()
    if not skills:
        raise ValueError(
            "The structure pass produced no skills — the AI service may be "
            "unavailable. Try crunching again."
        )

    # 3) Question pass: a small bank per skill -----------------------------
    _set(db, job, phase="writing questions", progress=60)
    total = len(skills)
    questions_made = 0

    # Read every skill's name/description/provenance on THIS thread into plain
    # dicts, so the concurrent LLM calls don't lazy-load from the DB session.
    payloads = [
        {
            "name": skill.name,
            "description": skill.description,
            "source": _provenance_text(db, skill),
        }
        for skill in skills
    ]

    def _questions_for(p: dict) -> dict:
        return complete_json(
            [
                {
                    "role": "system",
                    "content": "You write practice questions grounded in the given "
                    "source. Output STRICT JSON only.",
                },
                {
                    "role": "user",
                    "content": (
                        f"INTENT: {intent}\n"
                        f"SKILL: {p['name']}\nDESCRIPTION: {p['description']}\n"
                        f"SOURCE:\n{p['source']}\n\n"
                        'Produce JSON {"questions":[{"mode":'
                        '"on_the_go|short_drill|deep_dive","prompt":str,'
                        '"answer":str,"explanation":str}]}. '
                        f"{QUESTION_MODES_HINT} Keep answers concise."
                    ),
                },
            ],
            max_tokens=QUESTION_MAX_TOKENS,
            timeout=LLM_TIMEOUT,
        )

    results = _map_concurrent(
        _questions_for,
        payloads,
        on_complete=lambda d, t: _set(db, job, progress=60 + int(30 * d / t)),
    )
    for n, (skill, result) in enumerate(zip(skills, results)):
        if isinstance(result, Exception) or result is None:
            logger.warning("question pass failed for skill %s: %s", skill.id, result)
        else:
            for q in result.get("questions", []):
                if not isinstance(q, dict) or not q.get("prompt"):
                    continue
                mode = q.get("mode", "on_the_go")
                if mode not in ("on_the_go", "short_drill", "deep_dive", "discuss"):
                    mode = "on_the_go"
                db.add(
                    models.Question(
                        skill_id=skill.id,
                        journey_id=journey.id,
                        mode=mode,
                        prompt=q["prompt"],
                        answer=q.get("answer"),
                        explanation=q.get("explanation"),
                        provenance=list(skill.provenance or []),
                        curriculum_version=version,
                    )
                )
                questions_made += 1
        _set(db, job, progress=60 + int(35 * (n + 1) / total))

    if questions_made == 0:
        # A "ready" journey with nothing to drill is a dead end — fail so the
        # user can retry rather than land in an empty session.
        raise ValueError(
            "No questions could be generated — the AI service may be "
            "unavailable. Try crunching again."
        )

    journey.status = "ready"
    _set(db, job, phase="done", progress=100)


def _structure_call(intent: str, numbered: str) -> dict:
    """One structuring call over the given numbered material (whole doc or one
    window). Pure LLM work — safe to run in a worker thread."""
    return complete_json(
        [
            {
                "role": "system",
                "content": "You are a curriculum designer. Break source material "
                "into a hierarchy of units and atomic, masterable skills. Output "
                "STRICT JSON only.",
            },
            {
                "role": "user",
                "content": (
                    f"INTENT: {intent}\n\n"
                    f"MATERIAL (numbered chunks):\n{numbered}\n\n"
                    'Produce JSON: {"units":[{"title":str,"skills":'
                    '[{"name":str,"description":str,"source_chunks":[int]}],'
                    '"units":[...optional nested...]}]}. '
                    "Keep skills atomic and specific. source_chunks are the chunk "
                    "numbers each skill draws from."
                ),
            },
        ],
        max_tokens=STRUCTURE_MAX_TOKENS,
        timeout=LLM_TIMEOUT,
    )


def _flatten_skills(units, window) -> list[dict]:
    """Flatten a window's unit tree into draft skills, resolving each skill's
    source_chunks (window-local indices) to chunk ids for provenance."""
    out: list[dict] = []
    for u in units:
        if not isinstance(u, dict):
            continue
        for s in u.get("skills", []) or []:
            if not isinstance(s, dict) or not s.get("name"):
                continue
            prov = [
                window[i].id
                for i in s.get("source_chunks", []) or []
                if isinstance(i, int) and 0 <= i < len(window)
            ]
            out.append(
                {
                    "name": str(s["name"]),
                    "description": str(s.get("description", "")),
                    "provenance": prov,
                }
            )
        out += _flatten_skills(u.get("units", []) or [], window)
    return out


def _consolidate_skills(intent: str, raw_skills: list[dict]) -> dict | None:
    """Ask the LLM to merge duplicates and regroup the draft skills (which came
    from overlapping windows) into one authoritative unit/skill hierarchy.

    Each final skill lists `source_skills` (draft indices it covers) so we can
    union their provenance. Returns None on failure so the caller can fall back
    to the ungrouped draft.
    """
    listing = "\n".join(
        f"[{i}] {s['name']}: {s['description'][:200]}"
        for i, s in enumerate(raw_skills)
    )
    try:
        return complete_json(
            [
                {
                    "role": "system",
                    "content": "You are a curriculum designer consolidating a draft "
                    "skill list extracted from overlapping sections of the same "
                    "material. Merge duplicates and near-duplicates, group related "
                    "skills into a clean unit hierarchy, and produce the "
                    "authoritative curriculum. Output STRICT JSON only.",
                },
                {
                    "role": "user",
                    "content": (
                        f"INTENT: {intent}\n\n"
                        f"DRAFT SKILLS (index: name: description):\n{listing}\n\n"
                        'Produce JSON: {"units":[{"title":str,"skills":[{"name":str,'
                        '"description":str,"source_skills":[int]}],"units":'
                        '[...optional nested...]}]}. Merge duplicates/near-duplicates '
                        "into single skills. source_skills lists the draft indices "
                        "each final skill covers (so their grounding can be combined). "
                        "Every draft index should be covered by exactly one final "
                        "skill. Keep skills atomic and specific."
                    ),
                },
            ],
            max_tokens=CONSOLIDATION_MAX_TOKENS,
            timeout=LLM_TIMEOUT,
        )
    except Exception as e:  # noqa: BLE001 - fall back to the draft on any failure
        logger.warning("consolidation pass failed: %s", e)
        return None


def _persist_consolidated(
    db, journey, version, units, raw_skills, parent_id, start_ordinal
) -> list[models.Skill]:
    """Persist the consolidated hierarchy; each skill's provenance is the union
    of the draft skills it absorbed."""
    created: list[models.Skill] = []
    for ordinal, u in enumerate(units, start=start_ordinal):
        if not isinstance(u, dict):
            continue
        unit = models.Unit(
            journey_id=journey.id,
            parent_id=parent_id,
            title=str(u.get("title", "Untitled")),
            ordinal=ordinal,
            curriculum_version=version,
        )
        db.add(unit)
        db.flush()
        for s_ord, s in enumerate(u.get("skills", []) or []):
            if not isinstance(s, dict) or not s.get("name"):
                continue
            prov: list[str] = []
            for i in s.get("source_skills", []) or []:
                if isinstance(i, int) and 0 <= i < len(raw_skills):
                    prov += raw_skills[i]["provenance"]
            prov = list(dict.fromkeys(prov))  # de-dup, keep order
            skill = models.Skill(
                journey_id=journey.id,
                unit_id=unit.id,
                name=str(s["name"]),
                description=str(s.get("description", "")),
                content_key=models.content_key(str(s["name"])),
                provenance=prov,
                ordinal=s_ord,
                curriculum_version=version,
            )
            db.add(skill)
            created.append(skill)
        created += _persist_consolidated(
            db, journey, version, u.get("units", []) or [], raw_skills, unit.id, 0
        )
    return created


def _persist_raw_flat(db, journey, version, raw_skills) -> list[models.Skill]:
    """Fallback when consolidation fails: persist the draft skills as-is under a
    single unit, so the crunch still yields a usable curriculum."""
    unit = models.Unit(
        journey_id=journey.id, parent_id=None, title="Skills", ordinal=0,
        curriculum_version=version,
    )
    db.add(unit)
    db.flush()
    created: list[models.Skill] = []
    for s_ord, s in enumerate(raw_skills):
        skill = models.Skill(
            journey_id=journey.id,
            unit_id=unit.id,
            name=s["name"],
            description=s["description"],
            content_key=models.content_key(s["name"]),
            provenance=list(dict.fromkeys(s["provenance"])),
            ordinal=s_ord,
            curriculum_version=version,
        )
        db.add(skill)
        created.append(skill)
    return created


def _persist_units(
    db, journey, version, units, used_chunks, parent_id, start_ordinal
) -> list[models.Skill]:
    """Recursively create Unit + Skill rows; return all created skills."""
    created: list[models.Skill] = []
    for ordinal, u in enumerate(units, start=start_ordinal):
        if not isinstance(u, dict):
            continue
        unit = models.Unit(
            journey_id=journey.id,
            parent_id=parent_id,
            title=str(u.get("title", "Untitled")),
            ordinal=ordinal,
            curriculum_version=version,
        )
        db.add(unit)
        db.flush()
        for s_ord, s in enumerate(u.get("skills", []) or []):
            if not isinstance(s, dict) or not s.get("name"):
                continue
            prov = [
                used_chunks[i].id
                for i in s.get("source_chunks", []) or []
                if isinstance(i, int) and 0 <= i < len(used_chunks)
            ]
            skill = models.Skill(
                journey_id=journey.id,
                unit_id=unit.id,
                name=str(s["name"]),
                description=str(s.get("description", "")),
                content_key=models.content_key(str(s["name"])),
                provenance=prov,
                ordinal=s_ord,
                curriculum_version=version,
            )
            db.add(skill)
            created.append(skill)
        created += _persist_units(
            db, journey, version, u.get("units", []) or [], used_chunks, unit.id, 0
        )
    return created


def _provenance_text(db: Session, skill: models.Skill) -> str:
    if not skill.provenance:
        return ""
    rows = (
        db.query(models.Chunk)
        .filter(models.Chunk.id.in_(list(skill.provenance)))
        .all()
    )
    text = "\n\n".join(r.text for r in rows)
    return text[:MAX_PROVENANCE_CHARS]
