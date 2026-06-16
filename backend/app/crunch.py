"""The crunch: Document(s) -> Chunks -> Unit/Skill tree -> Question bank.

A synchronous function driven by the background worker. The LLM does the heavy
lifting (structuring + question writing); this module is orchestration:
parse, chunk, prompt, parse JSON, persist, and report progress on the job.

No embeddings (see the retrieval decision): structuring walks the material in
order, and each skill records the chunk ids it came from (provenance), which
the question pass uses as grounding.
"""
from __future__ import annotations

from sqlalchemy.orm import Session

from . import models
from .chunking import chunk_text
from .llm import complete_json
from .parsing import parse_document

# Phase-0 bounds (keep a single crunch tractable/cheap). Long-document
# map-reduce is a later improvement. Reasoning models "think" a lot, so we keep
# the structure input modest and give the calls a generous token budget.
MAX_STRUCTURE_CHUNKS = 24
MAX_PROVENANCE_CHARS = 4000
STRUCTURE_MAX_TOKENS = 16000
QUESTION_MAX_TOKENS = 4000

QUESTION_MODES_HINT = (
    "Include about 2 'on_the_go' (quick recall), 1 'short_drill' (focused), and "
    "1 'deep_dive' (applied/deeper — problem-solving for factual material, or "
    "discussion/analysis for narrative)."
)


def _set(db: Session, job: models.IngestionJob, *, phase=None, progress=None):
    if phase is not None:
        job.phase = phase
    if progress is not None:
        job.progress = progress
    db.commit()


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

    # 2) Structure pass: Unit tree + Skills --------------------------------
    _set(db, job, phase="structuring", progress=30)
    used = chunks[:MAX_STRUCTURE_CHUNKS]
    numbered = "\n\n".join(f"[{i}] {c.text}" for i, c in enumerate(used))
    structure = complete_json(
        [
            {
                "role": "system",
                "content": "You are a curriculum designer. Break source material "
                "into a hierarchy of units and atomic, masterable skills. "
                "Output STRICT JSON only.",
            },
            {
                "role": "user",
                "content": (
                    f"INTENT: {journey.intent or 'general mastery'}\n\n"
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
    )

    skills = _persist_units(db, journey, version, structure.get("units", []), used, None, 0)
    db.flush()
    if not skills:
        raise ValueError("The structure pass produced no skills.")

    # 3) Question pass: a small bank per skill -----------------------------
    _set(db, job, phase="questions", progress=60)
    total = len(skills)
    for n, skill in enumerate(skills):
        prov_text = _provenance_text(db, skill)
        result = complete_json(
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
                        f"SKILL: {skill.name}\nDESCRIPTION: {skill.description}\n"
                        f"SOURCE:\n{prov_text}\n\n"
                        'Produce JSON {"questions":[{"mode":'
                        '"on_the_go|short_drill|deep_dive","prompt":str,'
                        '"answer":str,"explanation":str}]}. '
                        f"{QUESTION_MODES_HINT} Keep answers concise."
                    ),
                },
            ],
            max_tokens=QUESTION_MAX_TOKENS,
        )
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
        _set(db, job, progress=60 + int(35 * (n + 1) / total))

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
