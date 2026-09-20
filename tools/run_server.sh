#!/usr/bin/env bash
# Runs the Aldenexia dedicated server and shuts it down GRACEFULLY (players' characters saved, world clock
# saved) on Ctrl-C / SIGTERM / SIGHUP. Godot's headless server can't catch those signals itself, so this
# script catches them and creates the server's stop file instead (see net.gd, "Graceful shutdown").
#
#   tools/run_server.sh --name=test --port=8910 --max-players=6
#
# By default it runs the project with the `godot` on your PATH. To run an exported server binary instead:
#   ALDENEXIA_SERVER_BIN=/path/to/Aldenexia_Server.x86_64 tools/run_server.sh --name=test
# Everything you pass is handed to the server (--name= --port= --max-players= --tls-dir=).
set -u
HERE="$(cd "$(dirname "$0")/.." && pwd)"
STOP="${XDG_RUNTIME_DIR:-/tmp}/aldenexia-stop-$$"
rm -f "$STOP"

if [ -n "${ALDENEXIA_SERVER_BIN:-}" ]; then
	"$ALDENEXIA_SERVER_BIN" --headless -- --server --stop-file="$STOP" "$@" &
else
	"${GODOT:-godot}" --headless --path "$HERE" -- --server --stop-file="$STOP" "$@" &
fi
SERVER_PID=$!

request_stop() {
	echo "[run_server] Stop requested — asking the server to save and exit..."
	touch "$STOP"
}
trap request_stop INT TERM HUP

wait "$SERVER_PID"
# `wait` returns early when a trapped signal arrives; keep waiting for the server to finish saving (up to ~25 s).
for _ in $(seq 1 50); do
	kill -0 "$SERVER_PID" 2>/dev/null || break
	sleep 0.5
done
if kill -0 "$SERVER_PID" 2>/dev/null; then
	echo "[run_server] Server did not exit in time — killing it."
	kill -9 "$SERVER_PID"
fi
wait "$SERVER_PID" 2>/dev/null
STATUS=$?
rm -f "$STOP"
exit "$STATUS"
