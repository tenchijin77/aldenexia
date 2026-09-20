#!/usr/bin/env bash
# Uploads the Aldenexia dedicated-server files to the server machine, so updating is one command.
#
#   tools/deploy_server.sh                     upload the current Builds/Server build + tools/run_server.sh
#   tools/deploy_server.sh --export            export the "Linux Server" preset first, then upload
#   tools/deploy_server.sh --restart 'CMD'     afterwards run CMD on the server (e.g. 'sudo systemctl restart aldenexia-server')
#   tools/deploy_server.sh --tls               FIRST-TIME SETUP: also copy the TLS key + certificate (see below)
#   tools/deploy_server.sh --host user@host --dir aldenexia     override where it goes
#
# Defaults: host rwilkinson@192.168.77.100, directory "aldenexia" (relative to that user's home on the server).
# Override with --host/--dir or the environment variables ALDENEXIA_DEPLOY_HOST / ALDENEXIA_DEPLOY_DIR.
#
# What it does, in order: (optionally export) -> upload under temporary names -> rename into place -> verify the
# checksum on the server. The temporary-name step matters: overwriting a RUNNING binary fails with "Text file
# busy", and overwriting a running shell script can corrupt it; renaming is safe, and the running server simply
# keeps using the old file until you restart it. It does NOT restart the server unless you pass --restart.
#
# TLS: the server's key + certificate must be the pair whose certificate is baked into the game as
# Data/server_cert.crt, or clients can't connect. --tls copies them from this machine, but will NOT overwrite a
# key that is already on the server (that is the point of not regenerating it) unless you add --force-tls.
# It uses one SSH connection for everything, so a password (if you use one) is asked for only once.
set -euo pipefail

HOST="${ALDENEXIA_DEPLOY_HOST:-rwilkinson@192.168.77.100}"
DIR="${ALDENEXIA_DEPLOY_DIR:-aldenexia}"
DO_EXPORT=0
DO_TLS=0
FORCE_TLS=0
RESTART_CMD=""

while [ $# -gt 0 ]; do
	case "$1" in
		--host)      HOST="${2:?--host needs user@host}"; shift 2 ;;
		--dir)       DIR="${2:?--dir needs a directory}"; shift 2 ;;
		--export)    DO_EXPORT=1; shift ;;
		--tls)       DO_TLS=1; shift ;;
		--force-tls) DO_TLS=1; FORCE_TLS=1; shift ;;
		--restart)   RESTART_CMD="${2:?--restart needs a command}"; shift 2 ;;
		-h|--help)   sed -n '2,25p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
		*) echo "Unknown option: $1 (try --help)" >&2; exit 2 ;;
	esac
done

cd "$(dirname "$0")/.."
BIN="Builds/Server/Aldenexia_Server.x86_64"
WRAPPER="tools/run_server.sh"
say() { printf '\033[1m[deploy]\033[0m %s\n' "$*"; }

if [ "$DO_EXPORT" = 1 ]; then
	say "Exporting the 'Linux Server' preset (about a minute)..."
	"${GODOT:-godot}" --headless --path . --export-release "Linux Server" >/dev/null 2>&1 || { echo "Export failed — run it by hand to see why:  godot --headless --path . --export-release \"Linux Server\"" >&2; exit 1; }
fi

[ -f "$BIN" ] || { echo "No server build at $BIN. Run with --export (or export the 'Linux Server' preset in the editor) first." >&2; exit 1; }

# Which commit is this build from? (Server and clients must match when builds are stamped.)
STAMP="$(python3 -c "import json;print(json.load(open('Data/build_info.json')).get('build',''))" 2>/dev/null || true)"
HEAD_HASH="$(git rev-parse --short HEAD 2>/dev/null || echo '?')"
say "Build stamp: ${STAMP:-none}   (git HEAD: $HEAD_HASH)"
if [ -n "$STAMP" ] && [ "$STAMP" != "$HEAD_HASH" ]; then
	echo "         ^ the stamp differs from HEAD (or is '-dirty'). If clients are built from HEAD, run tools/stamp_build.sh and export again." >&2
fi

# One SSH connection shared by every ssh/scp below.
SSH_OPTS=(-o ControlMaster=auto -o "ControlPath=/tmp/aldenexia-deploy-%C" -o ControlPersist=120)
run() { ssh "${SSH_OPTS[@]}" "$HOST" "$@"; }
say "Uploading to $HOST:$DIR/ ..."
run "mkdir -p '$DIR' '$DIR/tls'"

scp "${SSH_OPTS[@]}" "$BIN" "$HOST:$DIR/Aldenexia_Server.x86_64.new"
scp "${SSH_OPTS[@]}" "$WRAPPER" "$HOST:$DIR/run_server.sh.new"
run "cd '$DIR' && chmod +x Aldenexia_Server.x86_64.new run_server.sh.new && mv -f Aldenexia_Server.x86_64.new Aldenexia_Server.x86_64 && mv -f run_server.sh.new run_server.sh"

LOCAL_SUM="$(sha256sum "$BIN" | cut -d' ' -f1)"
REMOTE_SUM="$(run "sha256sum '$DIR/Aldenexia_Server.x86_64'" | cut -d' ' -f1)"
if [ "$LOCAL_SUM" = "$REMOTE_SUM" ]; then
	say "Upload verified (sha256 ${LOCAL_SUM:0:12}...)."
else
	echo "CHECKSUM MISMATCH after upload (local ${LOCAL_SUM:0:12}..., server ${REMOTE_SUM:0:12}...). Try again." >&2
	exit 1
fi

if [ "$DO_TLS" = 1 ]; then
	TLS_LOCAL="${XDG_DATA_HOME:-$HOME/.local/share}/godot/app_userdata/Aldenexia-Lightfall/server_tls"
	[ -f "$TLS_LOCAL/server.key" ] && [ -f "$TLS_LOCAL/server.crt" ] || { echo "No key/certificate in $TLS_LOCAL — start a server on this machine once to create them." >&2; exit 1; }
	if run "test -f '$DIR/tls/server.key'" && [ "$FORCE_TLS" = 0 ]; then
		say "The server already has a TLS key — leaving it alone (add --force-tls to replace it)."
	else
		say "Copying the TLS key + certificate..."
		scp "${SSH_OPTS[@]}" "$TLS_LOCAL/server.key" "$TLS_LOCAL/server.crt" "$HOST:$DIR/tls/"
		run "chmod 600 '$DIR/tls/server.key'"
	fi
fi

# Cheap safety net: does the certificate the SERVER will use match the one baked into the game?
CLIENT_CERT_SUM="$(sha256sum Data/server_cert.crt | cut -d' ' -f1)"
SERVER_CERT_SUM="$(run "sha256sum '$DIR/tls/server.crt' 2>/dev/null" | cut -d' ' -f1 || true)"
if [ -z "$SERVER_CERT_SUM" ]; then
	echo "         NOTE: the server has no tls/server.crt yet — copy your key with --tls, or it will create a NEW one that clients won't trust." >&2
elif [ "$SERVER_CERT_SUM" != "$CLIENT_CERT_SUM" ]; then
	echo "         WARNING: the server's tls/server.crt is NOT the certificate in Data/server_cert.crt — clients will see the server as offline. Fix with --force-tls (from the machine that has the right key)." >&2
else
	say "TLS certificate on the server matches the game's Data/server_cert.crt."
fi

if [ -n "$RESTART_CMD" ]; then
	say "Restarting: $RESTART_CMD"
	ssh -t "${SSH_OPTS[@]}" "$HOST" "$RESTART_CMD"
else
	say "Done. The running server still uses the OLD build until you restart it:"
	echo "         stop it with Ctrl-C in its terminal (run_server.sh saves everyone first) and start it again, e.g."
	echo "         cd $DIR && ALDENEXIA_SERVER_BIN=\$PWD/Aldenexia_Server.x86_64 ./run_server.sh --name=test --port=8910 --tls-dir=\$PWD/tls"
fi
