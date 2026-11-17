#!/usr/bin/env bash
# Build the web app and drop it into the backend, which serves it at /app/.
#
#   ./scripts/build_web_local.sh            # GARAZ next to this repo
#   GARAZ_DIR=/path/to/GARAZ ./scripts/build_web_local.sh
#
# The API is reached as /api on the same origin, so no CORS and no host baked in.
set -euo pipefail
# Git Bash on Windows would rewrite "/app/" into a Windows path.
export MSYS_NO_PATHCONV=1

here="$(cd "$(dirname "$0")/.." && pwd)"
backend="${GARAZ_DIR:-$here/../GARAZ}"
target="$backend/webapp"

cd "$here"
flutter build web --release --base-href=/app/ --dart-define=API_BASE_URL=/api

mkdir -p "$target"
# Empty the folder rather than recreate it: the container bind-mounts it.
find "$target" -mindepth 1 -delete
cp -R build/web/. "$target/"
echo "Copied build to $target"

# The backend registers the /app routes at startup, and only if index.html exists.
if docker ps --format '{{.Names}}' 2>/dev/null | grep -qx garaz-api; then
  docker restart garaz-api >/dev/null
  echo "Restarted garaz-api → http://localhost:${PORT:-8000}/app/"
else
  echo "garaz-api is not running; start it with: (cd \"$backend\" && docker compose up -d --build)"
fi
