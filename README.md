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
