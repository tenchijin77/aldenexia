#!/usr/bin/env bash
# Serves the published game updates (<this folder>/updates: manifest.json, manifest.sig, patch-*.pck) over plain HTTP so
# players' games can download them — run it on the server machine next to the game server (own tmux window, or as a
# service). Players' games find it at http://<server address>:8911 and verify everything with the signature in the manifest,
# so HTTP is fine. Needs python3 and TCP port 8911 open/forwarded (the game itself uses UDP 8910).
#
#   ./run_update_server.sh                 port 8911, folder ./updates
#   ./run_update_server.sh 9000 /some/dir  another port / folder
# The port must match ALDENEXIA_UPDATE_PORT / "update_port" in Data/servers.json if you change it.
set -eu
PORT="${1:-8911}"
ROOT="${2:-$(cd "$(dirname "$0")" && pwd)/updates}"
mkdir -p "$ROOT"
echo "[update-server] serving $ROOT on TCP $PORT (Ctrl-C to stop)"
exec python3 -m http.server "$PORT" --bind 0.0.0.0 --directory "$ROOT"
