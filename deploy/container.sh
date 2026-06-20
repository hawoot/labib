#!/usr/bin/env bash
# ============================================================
#  Deploy INSIDE a Docker container (no nested Docker available).
#  Runs the API natively with Python + a local SQLite database
#  (no Postgres server to install). Good for getting started fast.
#
#  NOTE: SQLite has no pgvector, so vector/RAG features (a later
#  milestone) will require either a real VPS (deploy/vps.sh) or an
#  external Postgres via DATABASE_URL in .env. The current API and
#  the upcoming data model work fine on SQLite.
#
#  Usage (from anywhere):  bash deploy/container.sh
#  Repo expected at $APP_DIR (default /home/node/apps/labib) with .env inside.
# ============================================================
set -euo pipefail

APP_DIR="${APP_DIR:-/home/node/apps/labib}"
cd "$APP_DIR"

if [ ! -f .env ]; then
  echo "ERROR: .env not found in $APP_DIR — upload your .env there first."
  exit 1
fi

# 1. Ensure Python is available -------------------------------------------------
if ! command -v python3 >/dev/null 2>&1; then
  echo "==> Installing Python..."
  if command -v sudo >/dev/null 2>&1; then
    sudo apt-get update && sudo apt-get install -y python3 python3-venv python3-pip
  else
    apt-get update && apt-get install -y python3 python3-venv python3-pip
  fi
fi

# 2. Virtualenv + dependencies --------------------------------------------------
echo "==> Setting up virtualenv and installing dependencies..."
python3 -m venv .venv
./.venv/bin/pip install --upgrade pip >/dev/null
./.venv/bin/pip install -r backend/requirements.txt

# 2b. Build the Flutter web app so the served UI matches the current code. ------
#     Skipped (with a warning) if the Flutter SDK isn't installed — the existing
#     prebuilt bundle in backend/app/webapp is served as-is in that case.
#
#     We `clean` + `pub get` first on purpose: a stale .dart_tool can carry an
#     out-of-date web *plugin registrant*, which silently drops a plugin's web
#     implementation from the build (e.g. speech_to_text) — the app then throws
#     MissingPluginException at runtime. A clean build regenerates it.
if command -v flutter >/dev/null 2>&1; then
  echo "==> Building Flutter web app (clean)..."
  ( cd "$APP_DIR/frontend" && flutter clean && flutter pub get && flutter build web --release )
  rm -rf "$APP_DIR/backend/app/webapp"
  cp -r "$APP_DIR/frontend/build/web" "$APP_DIR/backend/app/webapp"
else
  echo "==> WARNING: 'flutter' not found — serving the existing prebuilt web app."
fi

# 3. Load .env, default the DB to a local SQLite file ---------------------------
set -a; . ./.env; set +a
export DATABASE_URL="${DATABASE_URL:-sqlite:///$APP_DIR/labib.db}"
PORT="${API_PORT:-8000}"

# 4. (Re)start the API in the background ----------------------------------------
echo "==> Starting API on port $PORT..."
pkill -f "uvicorn app.main:app" 2>/dev/null || true
cd "$APP_DIR/backend"
nohup ../.venv/bin/uvicorn app.main:app --host 0.0.0.0 --port "$PORT" \
  > "$APP_DIR/api.log" 2>&1 &
echo $! > "$APP_DIR/api.pid"

# 5. Health check ---------------------------------------------------------------
for i in $(seq 1 15); do
  if curl -fsS "http://localhost:${PORT}/health" >/dev/null 2>&1; then
    echo "==> API healthy (pid $(cat "$APP_DIR/api.pid")):"
    curl -s "http://localhost:${PORT}/health"; echo
    echo "Logs: tail -f $APP_DIR/api.log   |   Stop: kill \$(cat $APP_DIR/api.pid)"
    exit 0
  fi
  sleep 2
done

echo "API did not become healthy. Last log lines:"
tail -20 "$APP_DIR/api.log"
exit 1
