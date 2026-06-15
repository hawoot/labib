#!/usr/bin/env bash
# ============================================================
#  Deploy on a PROPER VPS (one that has Docker + Docker Compose).
#  Runs the API + a real Postgres/pgvector database as containers.
#
#  Usage (from anywhere):  bash deploy/vps.sh
#  The repo is expected at $APP_DIR (default /home/node/apps/labib),
#  with your .env file already placed inside it.
# ============================================================
set -euo pipefail

APP_DIR="${APP_DIR:-/home/node/apps/labib}"
cd "$APP_DIR"

if [ ! -f .env ]; then
  echo "ERROR: .env not found in $APP_DIR — upload your .env there first."
  exit 1
fi

if ! command -v docker >/dev/null 2>&1; then
  echo "ERROR: docker is not installed. This host needs Docker."
  echo "If this is a Docker CONTAINER (no nested Docker), use deploy/container.sh instead."
  exit 1
fi

echo "==> Building and starting containers (api + db)..."
docker compose up -d --build

PORT="$(grep -E '^API_PORT=' .env | cut -d= -f2)"; PORT="${PORT:-8000}"
echo "==> Waiting for the API to come up on port $PORT..."
for i in $(seq 1 30); do
  if curl -fsS "http://localhost:${PORT}/health" >/dev/null 2>&1; then
    echo "==> API healthy:"
    curl -s "http://localhost:${PORT}/health"; echo
    exit 0
  fi
  sleep 2
done

echo "API did not become healthy in time. Check logs with:"
echo "  cd $APP_DIR && docker compose logs -f api"
exit 1
