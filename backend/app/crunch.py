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

# Crunch bounds. The structure pass walks the WHOLE document in windows of
# STRUCTURE_WINDOW_CHUNKS, appending the unit/skill tree from each window, so
# material past the first window is no longer silently dropped (previously the
# crunch only ever saw the first 24 chunks ≈ ~30 pages). MAX_STRUCTURE_CHUNKS is
# a generous overall safety cap (~240 chunks × ~1500 chars ≈ a few hundred
# pages) that keeps a single crunch's cost/time bounded. Reasoning models
# "think" a lot, so each call gets a generous token budget.
STRUCTURE_WINDOW_CHUNKS = 24
MAX_STRUCTURE_CHUNKS = 240
MAX_PROVENANCE_CHARS = 4000
STRUCTURE_MAX_TOKENS = 16000
QUESTION_MAX_TOKENS = 4000

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

    # 2) Structure pass: walk the WHOLE document in windows, appending the
    #    unit/skill tree from each so material past the first window survives.
    _set(db, job, phase="structuring", progress=30)
    used = chunks[:MAX_STRUCTURE_CHUNKS]
    windows = [
        used[i : i + STRUCTURE_WINDOW_CHUNKS]
        for i in range(0, len(used), STRUCTURE_WINDOW_CHUNKS)
    ]
    skills: list[models.Skill] = []
    unit_ordinal = 0

    # Build the prompt text on THIS thread (reads chunk rows); the worker
    # threads then get plain strings and never touch the DB session.
    numbered_windows = [
        "\n\n".join(f"[{i}] {c.text}" for i, c in enumerate(window))
        for window in windows
    ]

    def _structure_window(numbered: str) -> dict | None:
        # Chunks are numbered locally to this window; source_chunks the model
        # returns are resolved against `window` in _persist_units. Pure LLM work.
        return complete_json(
            [
                {
                    "role": "system",
                    "content": "You are a curriculum designer. Break source "
                    "material into a hierarchy of units and atomic, masterable "
                    "skills. Output STRICT JSON only.",
                },
                {
                    "role": "user",
                    "content": (
                        f"INTENT: {journey.intent or 'general mastery'}\n\n"
                        f"MATERIAL (numbered chunks):\n{numbered}\n\n"
                        'Produce JSON: {"units":[{"title":str,"skills":'
                        '[{"name":str,"description":str,"source_chunks":[int]}],'
                        '"units":[...optional nested...]}]}. '
                        "Keep skills atomic and specific. source_chunks are the "
                        "chunk numbers each skill draws from."
                    ),
                },
            ],
            max_tokens=STRUCTURE_MAX_TOKENS,
        )

    # Fan the window calls out concurrently; persist in window order so unit
    # ordinals stay stable and source_chunks resolve against the right window.
    structures = _map_concurrent(
        _structure_window,
        numbered_windows,
        on_complete=lambda d, t: _set(db, job, progress=30 + int(28 * d / t)),
    )
    for w, (window, structure) in enumerate(zip(windows, structures)):
        if isinstance(structure, Exception) or structure is None:
            logger.warning("structure pass failed for window %d/%d: %s",
                           w + 1, len(windows), structure)
            continue
        units = structure.get("units", []) or []
        skills += _persist_units(db, journey, version, units, window, None, unit_ordinal)
        unit_ordinal += len(units)
    # Structuring spans progress 30 -> 58.
    _set(db, job, progress=58)

    db.flush()
    if not skills:
        raise ValueError(
            "The structure pass produced no skills — the AI service may be "
            "unavailable. Try crunching again."
        )

    # 3) Question pass: a small bank per skill -----------------------------
    _set(db, job, phase="questions", progress=60)
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
                        f"INTENT: {journey.intent or 'general mastery'}\n"
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
