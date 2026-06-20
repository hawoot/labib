# Feature: Media capture — camera, mic/voice, upload

**Status:** Parked / to build after core is solid. Captured 2026-06-19.
**Why:** the app should "seamlessly integrate media, mic, voice notes, camera,
upload." Today only file upload exists (web), and native upload is stubbed.

---

## Capability layers (all rest on: native media access + backend that *processes* media)
- **Upload** (files/images/audio) — backend already accepts file multipart; the
  missing piece is the **native file picker** (currently web-only stub).
- **Camera** — snap a textbook page / handwritten notes → **OCR** to text → into
  the crunch. Adds a camera permission + an OCR step.
- **Mic / voice** — record → **speech-to-text** (e.g. Whisper) → text. Adds a
  mic permission + an STT step.

## Voice uses (user wants ALL THREE)
1. **Capture material** — record lectures / spoken notes → transcribe → study material.
2. **Answer hands-free** — speak answers during a session (esp. "on the go") instead of typing.
3. **Conversational tutor** — spoken back-and-forth with the tutor (the "discuss" mode).

## Build order
1. Native file upload (foundation for everything else).
2. Camera + OCR; mic + STT; media storage/display.
3. Weave into the redesign as first-class "add material" options + hands-free study.

## Notes / open questions
- OCR + STT are provider calls — added cost/latency; reuse the LLM provider
  abstraction or dedicated services. Which provider for STT (Whisper local vs API)?
- Conversational tutor likely wants streaming + TTS for replies → bigger piece.
- Where audio/images are stored (object storage already used for file docs).
- parsing.py extends from text-only to image (OCR) and audio (STT) inputs.
