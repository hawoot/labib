# Deploy

Two ways to run the backend. Pick the one that matches your host.

| Your host | Script | Database |
|-----------|--------|----------|
| **A Docker container** (can't run Docker inside it) | `bash deploy/container.sh` | local SQLite file |
| **A proper VPS / machine with Docker** | `bash deploy/vps.sh` | Postgres + pgvector (containers) |

Both expect:
1. The repo cloned to **`/home/node/apps/labib`** (override with `APP_DIR=...`).
2. Your **`.env`** file placed inside that folder.

## First-time setup

```bash
# clone (repo is public)
mkdir -p /home/node/apps && cd /home/node/apps
git clone https://github.com/hawoot/labib.git
cd labib

# upload your .env into /home/node/apps/labib/.env  (download from Claude)

# then run ONE of:
bash deploy/container.sh     # inside a Docker container (SQLite)
bash deploy/vps.sh           # on a real VPS with Docker (Postgres)
```

Confirm it's alive:

```bash
curl http://localhost:8000/health        # -> {"status":"ok","database":"ok"}
curl http://localhost:8000/health/llm     # checks the OpenCode Zen connection
```

## Notes
- **SQLite vs Postgres:** SQLite has no `pgvector`, so the later
  embeddings/RAG features need either `deploy/vps.sh` or an external Postgres
  (set `DATABASE_URL=postgresql+psycopg://...` in `.env`). Everything up to and
  including the data model runs fine on SQLite.
- **Updating after new code:** `git pull`, then re-run the same script.
- **container.sh** runs uvicorn in the background (`api.log`, `api.pid`). Stop
  with `kill $(cat /home/node/apps/labib/api.pid)`.
