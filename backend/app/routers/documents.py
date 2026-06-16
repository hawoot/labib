"""Documents: material added to a Journey (pasted text or an uploaded file)."""
import hashlib

from fastapi import APIRouter, Depends, File, UploadFile
from sqlalchemy.orm import Session

from .. import models
from ..db import get_db
from ..deps import get_current_user
from ..schemas import DocumentOut, DocumentTextCreate
from ..storage import get_storage
from .journeys import get_owned_journey

router = APIRouter(prefix="/journeys/{journey_id}/documents", tags=["documents"])


@router.get("", response_model=list[DocumentOut])
def list_documents(
    journey_id: str,
    user: models.User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    get_owned_journey(journey_id, user, db)
    return (
        db.query(models.Document)
        .filter(models.Document.journey_id == journey_id)
        .order_by(models.Document.created_at.desc())
        .all()
    )


@router.post("/text", response_model=DocumentOut, status_code=201)
def add_text_document(
    journey_id: str,
    payload: DocumentTextCreate,
    user: models.User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Add pasted text as a document."""
    journey = get_owned_journey(journey_id, user, db)
    doc = models.Document(
        journey_id=journey.id,
        owner_id=user.id,
        kind="text",
        title=payload.title,
        mime="text/plain",
        source_ref=payload.text,
        sha256=hashlib.sha256(payload.text.encode()).hexdigest(),
        status="uploaded",
    )
    db.add(doc)
    db.commit()
    db.refresh(doc)
    return doc


@router.post("/file", response_model=DocumentOut, status_code=201)
async def add_file_document(
    journey_id: str,
    file: UploadFile = File(...),
    user: models.User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Upload a file (PDF, etc.). The bytes go to object storage; the DB keeps a pointer."""
    journey = get_owned_journey(journey_id, user, db)
    data = await file.read()
    doc = models.Document(
        journey_id=journey.id,
        owner_id=user.id,
        kind="file",
        title=file.filename or "untitled",
        mime=file.content_type,
        sha256=hashlib.sha256(data).hexdigest(),
        status="uploaded",
    )
    db.add(doc)
    db.flush()  # populates doc.id so we can build the storage key
    doc.storage_key = f"{journey.id}/{doc.id}/{file.filename or 'file'}"
    get_storage().save(doc.storage_key, data)
    db.commit()
    db.refresh(doc)
    return doc
