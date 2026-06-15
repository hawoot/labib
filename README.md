# labib

Backend API + (later) Flutter app. See [`InitialDoc.md`](./InitialDoc.md) for the
full architecture blueprint.

## Backend — quick start

Requirements on the host: **Docker** + **Docker Compose**.

```bash
# 1. Configure
cp .env.example .env
nano .env            # set a DB password and your LLM key

# 2. Build & run (API + Postgres/pgvector)
docker compose up -d --build

# 3. Check it's alive
curl http://localhost:8000/health
# -> {"status":"ok","database":"ok"}

# 4. (optional) Check the AI brain is wired up
curl http://localhost:8000/health/llm
```

Useful commands:

```bash
docker compose logs -f api     # watch API logs
docker compose ps              # see running containers
docker compose down            # stop everything (data is kept)
docker compose up -d --build   # rebuild after pulling new code
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
