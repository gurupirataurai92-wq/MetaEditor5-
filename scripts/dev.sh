#!/usr/bin/env bash
# One-command local dev launcher for SIMS AI.
# Starts the FastAPI backend and the React dashboard together, seeds demo data,
# and prints the three logins. Ctrl-C stops both.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

echo "▶ Setting up backend…"
cd "$ROOT/backend"
[ -d .venv ] || python3 -m venv .venv
.venv/bin/pip install -q -r requirements-dev.txt

echo "▶ Starting backend on :8000…"
.venv/bin/uvicorn app.main:app --reload --port 8000 &
BACK=$!
trap 'kill $BACK 2>/dev/null || true; kill ${WEB:-} 2>/dev/null || true' EXIT

# Wait for the API, then seed demo data.
for _ in $(seq 1 30); do
  curl -sf http://localhost:8000/health >/dev/null 2>&1 && break
  sleep 0.5
done
echo "▶ Seeding demo data…"
python3 "$ROOT/scripts/seed_demo.py" || true

echo "▶ Starting web dashboard on :5173…"
cd "$ROOT/web"
[ -d node_modules ] || npm install
npm run dev &
WEB=$!

echo ""
echo "✓ SIMS AI is running:"
echo "    Dashboard : http://localhost:5173"
echo "    API docs  : http://localhost:8000/docs"
echo "  Press Ctrl-C to stop."
wait
