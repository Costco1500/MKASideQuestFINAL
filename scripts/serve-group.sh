#!/bin/bash
# Share this Mac's SideQuest API with the group chat's phones through a temporary
# Cloudflare HTTPS tunnel. No account needed; the address changes on every run.
set -euo pipefail
cd "$(dirname "$0")/.."
PORT="${PORT:-8787}"
TOOLS="build/tools"

CLOUDFLARED="$(command -v cloudflared || true)"
if [[ -z "$CLOUDFLARED" ]]; then
  CLOUDFLARED="$TOOLS/cloudflared"
  if [[ ! -x "$CLOUDFLARED" ]]; then
    case "$(uname -m)" in arm64) ARCH=arm64 ;; *) ARCH=amd64 ;; esac
    echo "Downloading cloudflared (Cloudflare's official tunnel client) into $TOOLS…"
    mkdir -p "$TOOLS"
    curl -fsSL "https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-darwin-$ARCH.tgz" | tar -xz -C "$TOOLS"
    chmod +x "$CLOUDFLARED"
  fi
fi

LOG="$(mktemp -t sidequest-tunnel)"
cleanup() { kill ${API_PID:-} ${TUNNEL_PID:-} 2>/dev/null || true; rm -f "$LOG"; }
trap cleanup EXIT INT TERM

if curl -fs "http://127.0.0.1:$PORT/health" >/dev/null 2>&1; then
  echo "Using the SideQuest API already running on port $PORT."
else
  PORT="$PORT" python3 backend/server.py &
  API_PID=$!
  for _ in $(seq 1 40); do curl -fs "http://127.0.0.1:$PORT/health" >/dev/null 2>&1 && break; sleep 0.25; done
fi

"$CLOUDFLARED" tunnel --no-autoupdate --url "http://127.0.0.1:$PORT" >"$LOG" 2>&1 &
TUNNEL_PID=$!
URL=""
for _ in $(seq 1 60); do
  URL="$(grep -Eo 'https://[a-z0-9-]+\.trycloudflare\.com' "$LOG" | head -1 || true)"
  [[ -n "$URL" ]] && break
  sleep 0.5
done
if [[ -z "$URL" ]]; then echo "The tunnel didn't start. cloudflared said:"; cat "$LOG"; exit 1; fi

cat <<EOF

  SideQuest group server is live:  $URL

  Organizer's phone: SideQuest → Settings → paste the address → Save server → Test connection.
  Everyone else joins from the invite card; the address travels with it.
  Keep this window open while the group plans. Press Ctrl-C to stop.

EOF
wait "$TUNNEL_PID"
