#!/usr/bin/env bash
# run_world.sh — runs the whole world: the login server (the starting zone) plus one server per other zone in
# Data/zones.json, each on base-port + its port_offset (8910, 8920, 8921 ...), all sharing the same characters and
# accounts. Ctrl-C / SIGTERM stops them all gracefully (each saves its players) — every one runs under run_server.sh.
#
#   tools/run_world.sh --name=test                      login server on 8910, Dustwind on 8920, Ashfall on 8921
#   tools/run_world.sh --name=test --base-port=8990     a local test world on 8990, 9000, 9001
#   tools/run_world.sh --name=test --zones=lumora_outskirts,dustwind_plateaus   start these zones (others still on demand)
#   tools/run_world.sh --name=test --all-zones          start every zone and keep them all running (the old way)
# Zones run ON DEMAND (2026-09-26): only the "always_on" zones in Data/zones.json start here (the starting zone, which is
# also the login server); the login server starts any other zone when a player travels there (world_link.gd), using the
# command this script hands it in ALDENEXIA_ZONE_LAUNCH, and a zone with nobody in it for 10 minutes shuts itself down
# (--idle-shutdown=<seconds> changes that, for testing). Ctrl-C stops every zone, the on-demand ones too.
# Other options (--max-players=, --tls-dir= ...) go to every server. ALDENEXIA_SERVER_BIN works as in run_server.sh.
# Each zone's output goes to its own log: world_logs/world_<zone>.log next to this script on the server (logs/ in the
# repo), and the servers' own user://logs/godot*.log as before.
set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# Works from the repo (tools/run_world.sh) and on the server, where update.sh puts it next to run_server.sh and the
# server binary (which it then uses automatically).
RUN_SERVER="$SCRIPT_DIR/run_server.sh"
if [ -f "$SCRIPT_DIR/../project.godot" ]; then LOG_DIR="$SCRIPT_DIR/../logs"; else LOG_DIR="$SCRIPT_DIR/world_logs"; fi
if [ -z "${ALDENEXIA_SERVER_BIN:-}" ] && [ -x "$SCRIPT_DIR/Aldenexia_Server.x86_64" ]; then
	export ALDENEXIA_SERVER_BIN="$SCRIPT_DIR/Aldenexia_Server.x86_64"
fi
BASE=8910
ZONES=""
ALL=0
PASS=()
TLS_GIVEN=0
for arg in "$@"; do
	case "$arg" in
		--base-port=*) BASE="${arg#*=}" ;;
		--zones=*)     ZONES="${arg#*=}" ;;
		--all-zones)   ALL=1 ;;
		--port=*|--zone=*) echo "run_world.sh sets --port and --zone itself (use --base-port / --zones)"; exit 1 ;;
		--tls-dir=*)   TLS_GIVEN=1; PASS+=("$arg") ;;
		*) PASS+=("$arg") ;;
	esac
done
# The server's TLS key and certificate: on the server they live in a "tls" folder next to this script (update.sh creates
# it). Without --tls-dir a server makes a NEW certificate that no game client trusts (test 34.5: every connection failed
# with "TLS handshake error"), so use that folder whenever it has a certificate.
if [ "$TLS_GIVEN" = 0 ] && [ -f "$SCRIPT_DIR/tls/server.crt" ]; then
	PASS+=("--tls-dir=$SCRIPT_DIR/tls")
	echo "[run_world] Using the TLS certificate in $SCRIPT_DIR/tls"
fi
# The zones this build has (Data/zones.json, asked from the build itself): "ZONE <id> <port offset>"
if [ -n "${ALDENEXIA_SERVER_BIN:-}" ]; then
	LIST=$("$ALDENEXIA_SERVER_BIN" --headless -- --server --list-zones 2>/dev/null)
else
	LIST=$("${GODOT:-godot}" --headless --path "$SCRIPT_DIR/.." -- --server --list-zones 2>/dev/null)
fi
ENTRIES=()
while read -r tag zone offset mode; do
	[ "$tag" = "ZONE" ] || continue
	if [ "$ALL" = 1 ] || [ "${mode:-always}" = "always" ] || [[ ",$ZONES," == *",$zone,"* ]]; then ENTRIES+=("$zone $offset"); fi
done <<< "$LIST"
[ ${#ENTRIES[@]} -gt 0 ] || { echo "No zones to run (could not ask the build for its zones)."; exit 1; }
mkdir -p "$LOG_DIR"
# How the login server starts a zone on demand: %ZONE% and %PORT% are filled in (world_link.gd _launch()). It runs under
# run_server.sh like the others (graceful stop, its own log), with --on-demand so it stops itself once empty.
if [ "$ALL" = 0 ]; then
	LAUNCH="exec $(printf '%q' "$RUN_SERVER") --zone=%ZONE% --base-port=$BASE --port=%PORT% --on-demand"
	for a in "${PASS[@]}"; do LAUNCH+=" $(printf '%q' "$a")"; done
	LAUNCH+=" >$(printf '%q' "$LOG_DIR")/world_%ZONE%.log 2>&1"
	export ALDENEXIA_ZONE_LAUNCH="$LAUNCH"
	echo "[run_world] Other zones start when a player travels there, and stop after 10 minutes empty."
fi
PIDS=()
for entry in "${ENTRIES[@]}"; do
	zone="${entry% *}"; offset="${entry#* }"; port=$((BASE + offset))
	echo "[run_world] $zone on UDP $port (log: $LOG_DIR/world_$zone.log)"
	"$RUN_SERVER" --zone="$zone" --base-port="$BASE" --port="$port" "${PASS[@]}" >"$LOG_DIR/world_$zone.log" 2>&1 &
	PIDS+=($!)
done
stop_all() {
	echo "[run_world] Stopping every zone (each saves its players)..."
	for pid in "${PIDS[@]}"; do kill -TERM "$pid" 2>/dev/null; done
}
trap stop_all INT TERM HUP
wait
# a trapped signal ends `wait` early: wait for the servers to finish saving
for pid in "${PIDS[@]}"; do
	while kill -0 "$pid" 2>/dev/null; do sleep 0.5; done
done
echo "[run_world] All zones stopped."
