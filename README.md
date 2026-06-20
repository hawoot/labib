# labib

Backend API + (later) Flutter app. See [`InitialDoc.md`](./InitialDoc.md) for the
full architecture blueprint.

## Backend — quick start

Clone to `/home/node/apps/labib`, drop your `.env` inside, then run the deploy
script that matches your host. See [`deploy/README.md`](./deploy/README.md).

```bash
mkdir -p /home/node/apps && cd /home/node/apps
git clone https://github.com/hawoot/labib.git && cd labib
# upload your .env into ./.env

bash deploy/container.sh    # inside a Docker container (SQLite, no Docker needed)
# --- or ---
bash deploy/vps.sh          # on a real VPS with Docker (Postgres + pgvector)
```

Check it's alive:

```bash
curl http://localhost:8000/health        # -> {"status":"ok","database":"ok"}
curl http://localhost:8000/health/llm     # checks the AI provider connection
```

## API so far

All endpoints except `/auth/anonymous` require an `X-User-Id` header (get one
from the bootstrap call).

| Method | Path | Purpose |
|--------|------|---------|
| GET  | `/health`, `/health/llm` | liveness, DB, AI provider |
| POST | `/auth/anonymous` | create an anonymous account → `{user_id}` |
| POST | `/journeys` | create a Journey (`title`, `intent`) |
| GET  | `/journeys` | list my journeys + the shared library |
| GET  | `/journeys/{id}` | get one Journey |
| POST | `/journeys/{id}/documents/text` | add pasted text (`title`, `text`) |
| POST | `/journeys/{id}/documents/file` | upload a file — PDF or text (multipart `file`) |
| GET  | `/journeys/{id}/documents` | list a Journey's documents |
| POST | `/journeys/{id}/ingest` | start the crunch (background) |
| GET  | `/journeys/{id}/ingest` | poll crunch status / phase / progress |
| GET  | `/journeys/{id}/curriculum` | the generated skills + question bank |

Interactive docs are always at `/docs` on the running API.

## Layout

```
docker-compose.yml      # runs db + api together
.env.example            # config template (copy to .env)
backend/
  Dockerfile
  requirements.txt
  app/
    main.py             # API endpoints
    config.py           # reads settings from .env
    db.py               # database connection
    llm.py              # swappable AI provider (OpenAI-compatible / Anthropic)
```
