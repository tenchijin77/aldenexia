#!/usr/bin/env bash
# One command to publish a test update: exports the dedicated SERVER and a client PATCH, signs the update and rsyncs both
# to the server machine. The intended routine:   git commit  ->  tools/stamp_build.sh  ->  tools/update.sh
#
#   tools/update.sh                     export server + client patch, sign, upload
#   tools/update.sh --new-base          make THIS build the new full client "base" (see below), export server, upload
#   tools/update.sh --stamp             run tools/stamp_build.sh first (so it is one command after the commit)
#   tools/update.sh --server-only       only the server binary          (--client-only: only the client patch)
#   tools/update.sh --skip-export       don't rebuild, just sign + upload what is already in Builds/
#   tools/update.sh --restart 'CMD'     afterwards run CMD on the server (e.g. to restart it)
#   tools/update.sh --host user@host --dir aldenexia     where to upload (defaults below)
#   tools/update.sh --local DIR         "upload" into a local folder instead — for testing this script
#
# HOW CLIENT UPDATES WORK. Players install one FULL client build (Builds/Windows: the exe + the 1.2 GB .pck). That build is
# the BASE. Every update is only a PATCH: a small .pck holding the files that changed since the base (scripts, scenes, data —
# typically well under 10 MB). Players download it from the server (Join screen -> "Download update") and the game restarts
# into it. So players re-download everything only when there is a new base. Make one with --new-base when:
#   * the version number in project.godot (config/version) changes, or project.godot changes in any other way that matters
#     (autoloads, input map, display settings...): a patch cannot carry project.godot;
#   * the executable, the Terrain3D library or the Godot version changes;
#   * the patch has grown large (each patch holds EVERYTHING changed since the base, not just the last commit).
# After --new-base, share Builds/Windows with your players (NAS link) — that's the only time they get the whole game again.
#
# The server binary is always a full export (155 MB; rsync only sends the parts that changed) and is uploaded under a
# temporary name then renamed, so a RUNNING server is never disturbed — it keeps the old file until you restart it.
# On the server the updates live in <dir>/updates and are served over HTTP (tools/run_update_server.sh, TCP port 8911).
# The manifest is uploaded LAST, so a player never sees an update whose patch isn't there yet.
#
# Files kept on this machine (all git-ignored): Builds/Base/ (base.pck + base.json: what the patches are made against),
# Builds/Update/ (the last patch, manifest.json, manifest.sig, export.log). The signing key is ~/.config/aldenexia/
# update_signing.key (create it once with tools/make_update_key.sh); its public half is Data/update_public_key.json.
set -euo pipefail

HOST="${ALDENEXIA_DEPLOY_HOST:-rwilkinson@192.168.77.100}"
DIR="${ALDENEXIA_DEPLOY_DIR:-aldenexia}"
KEY="${ALDENEXIA_SIGNING_KEY:-$HOME/.config/aldenexia/update_signing.key}"
UPDATE_PORT="${ALDENEXIA_UPDATE_PORT:-8911}"
DO_STAMP=0; NEW_BASE=0; DO_SERVER=1; DO_CLIENT=1; DO_EXPORT=1; RESTART_CMD=""; LOCAL_DEST=""

while [ $# -gt 0 ]; do
	case "$1" in
		--host)        HOST="${2:?--host needs user@host}"; shift 2 ;;
		--dir)         DIR="${2:?--dir needs a directory}"; shift 2 ;;
		--local)       LOCAL_DEST="${2:?--local needs a folder}"; shift 2 ;;
		--new-base)    NEW_BASE=1; shift ;;
		--stamp)       DO_STAMP=1; shift ;;
		--server-only) DO_CLIENT=0; shift ;;
		--client-only) DO_SERVER=0; shift ;;
		--skip-export) DO_EXPORT=0; shift ;;
		--restart)     RESTART_CMD="${2:?--restart needs a command}"; shift 2 ;;
		-h|--help)     sed -n '2,35p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
		*) echo "Unknown option: $1 (try --help)" >&2; exit 2 ;;
	esac
done

cd "$(dirname "$0")/.."
GODOT="${GODOT:-godot}"
SERVER_BIN="Builds/Server/Aldenexia_Server.x86_64"
# (These can be overridden with environment variables — used to test this script against the Linux client without touching
# the real base: ALDENEXIA_CLIENT_PRESET, ALDENEXIA_CLIENT_DIR, ALDENEXIA_CLIENT_BIN, ALDENEXIA_BASE_DIR, ALDENEXIA_UPDATE_DIR.)
CLIENT_PRESET="${ALDENEXIA_CLIENT_PRESET:-Windows Desktop}"
CLIENT_DIR="${ALDENEXIA_CLIENT_DIR:-Builds/Windows}"
CLIENT_BIN="${ALDENEXIA_CLIENT_BIN:-$CLIENT_DIR/Aldenexia_Lightfall.exe}"
SERVER_PRESET="Linux Server"
BASE_DIR="${ALDENEXIA_BASE_DIR:-Builds/Base}"; UPD_DIR="${ALDENEXIA_UPDATE_DIR:-Builds/Update}"
say()  { printf '\033[1m[update]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[update] WARNING:\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m[update] ERROR:\033[0m %s\n' "$*" >&2; exit 1; }
json() { python3 -c "import json,sys; d=json.load(open(sys.argv[1])); print(d.get(sys.argv[2],''))" "$1" "$2" 2>/dev/null || true; }
mkdir -p "$BASE_DIR" "$UPD_DIR" "$(dirname "$CLIENT_BIN")" "$(dirname "$SERVER_BIN")"  # Godot will not create an export folder itself

# ── preflight ────────────────────────────────────────────────────────────────
[ "$DO_STAMP" = 1 ] && tools/stamp_build.sh
[ -f Data/build_info.json ] || die "No build stamp. Run tools/stamp_build.sh (or add --stamp) after committing."
STAMP="$(json Data/build_info.json build)"; COUNT="$(json Data/build_info.json commit_count)"
HEAD_HASH="$(git rev-parse --short HEAD 2>/dev/null || echo '?')"
VERSION="$(sed -n 's/^config\/version="\(.*\)"/\1/p' project.godot | head -1)"
say "Build $STAMP (commit #$COUNT, game v$VERSION, git HEAD $HEAD_HASH)"
case "$STAMP" in *-dirty) warn "the stamp says -dirty: there are uncommitted changes in this build. Fine for testing, but the stamp then isn't unique to a commit." ;; esac
[ "$STAMP" = "$HEAD_HASH" ] || [ "$STAMP" = "$HEAD_HASH-dirty" ] || warn "the stamp ($STAMP) is not the current commit ($HEAD_HASH): run tools/stamp_build.sh again."
if [ "$DO_CLIENT" = 1 ]; then
	[ -f "$KEY" ] || die "No signing key at $KEY. Run tools/make_update_key.sh once (then make a --new-base build so players get the public half)."
	[ -f Data/update_public_key.json ] || die "Data/update_public_key.json is missing. Run tools/make_update_key.sh."
fi
if [ -z "$LOCAL_DEST" ]; then
	command -v rsync >/dev/null || die "rsync is not installed on this machine."
fi

# export_logged <label> <expected output file> <godot args...>: quiet unless it fails. An export that "succeeds" without
# writing its output (an old file would then be uploaded as if new) counts as a failure.
export_logged() {
	local label="$1" output="$2"; shift 2
	local mark; mark="$(mktemp)"
	say "$label (about a minute)..."
	if ! "$GODOT" --headless --path . "$@" >"$UPD_DIR/export.log" 2>&1; then
		tail -25 "$UPD_DIR/export.log" >&2; rm -f "$mark"
		die "$label failed — full output in $UPD_DIR/export.log"
	fi
	if [ ! -f "$output" ] || [ ! "$output" -nt "$mark" ]; then
		tail -25 "$UPD_DIR/export.log" >&2; rm -f "$mark"
		die "$label did not produce $output — full output in $UPD_DIR/export.log"
	fi
	rm -f "$mark"
}

# ── build ────────────────────────────────────────────────────────────────────
if [ "$DO_EXPORT" = 1 ]; then
	[ "$DO_SERVER" = 1 ] && export_logged "Exporting the dedicated server" "$SERVER_BIN" --export-release "$SERVER_PRESET"
fi
[ "$DO_SERVER" = 0 ] || [ -f "$SERVER_BIN" ] || die "No server build at $SERVER_BIN."

PATCH_FILE=""; PATCH_SIZE=0; PATCH_SHA=""
if [ "$DO_CLIENT" = 1 ]; then
	if [ "$NEW_BASE" = 1 ]; then
		if [ "$DO_EXPORT" = 1 ]; then
			export_logged "Exporting the FULL client (new base)" "$CLIENT_DIR/Aldenexia_Lightfall.pck" --export-release "$CLIENT_PRESET" "$CLIENT_BIN"
		fi
		CLIENT_PCK="$CLIENT_DIR/Aldenexia_Lightfall.pck"
		[ -f "$CLIENT_PCK" ] || die "No client pack at $CLIENT_PCK."
		cp -f "$CLIENT_PCK" "$BASE_DIR/base.pck"
		python3 - "$BASE_DIR/base.json" "$STAMP" "$VERSION" "$(sha256sum project.godot | cut -d' ' -f1)" <<'PY'
import json, sys, datetime
path, stamp, version, project_sha = sys.argv[1:5]
json.dump({"stamp": stamp, "version": version, "project_godot_sha256": project_sha,
           "created": datetime.datetime.now().isoformat(timespec="seconds")}, open(path, "w"), indent=2)
PY
		say "New base: $STAMP. SHARE Builds/Windows with your players (exe + pck + dll) — everyone needs it once."
	else
		[ -f "$BASE_DIR/base.json" ] && [ -f "$BASE_DIR/base.pck" ] || die "No base build yet. Run once with --new-base (exports the full client and remembers it as the base)."
		BASE_STAMP="$(json "$BASE_DIR/base.json" stamp)"
		[ "$(json "$BASE_DIR/base.json" version)" = "$VERSION" ] || die "The game version changed ($(json "$BASE_DIR/base.json" version) -> $VERSION). A patch can't change that: run with --new-base and share the new full build."
		[ "$(json "$BASE_DIR/base.json" project_godot_sha256)" = "$(sha256sum project.godot | cut -d' ' -f1)" ] || warn "project.godot has changed since the base ($BASE_STAMP). Patches can't carry project.godot changes (autoloads, input map, display settings...), so those won't reach players until a --new-base build."
		PATCH_FILE="patch-$STAMP.pck"
		if [ "$DO_EXPORT" = 1 ]; then
			rm -f "$UPD_DIR"/patch-*.pck
			export_logged "Exporting the client patch against base $BASE_STAMP" "$UPD_DIR/$PATCH_FILE" --export-patch "$CLIENT_PRESET" "$UPD_DIR/$PATCH_FILE" --patches "$BASE_DIR/base.pck"
		fi
		[ -f "$UPD_DIR/$PATCH_FILE" ] || die "The patch was not created ($UPD_DIR/$PATCH_FILE)."
		PATCH_SIZE="$(stat -c %s "$UPD_DIR/$PATCH_FILE")"; PATCH_SHA="$(sha256sum "$UPD_DIR/$PATCH_FILE" | cut -d' ' -f1)"
		say "Patch: $PATCH_FILE, $(numfmt --to=iec --suffix=B "$PATCH_SIZE")"
		[ "$PATCH_SIZE" -lt 314572800 ] || warn "the patch is over 300 MB — time for a --new-base build."
	fi

	# ── manifest + signature ──
	[ -f "$BASE_DIR/base.json" ] || die "No base.json."
	python3 - "$UPD_DIR/manifest.json" "$VERSION" "$(json "$BASE_DIR/base.json" stamp)" "$STAMP" "$COUNT" "$PATCH_FILE" "$PATCH_SIZE" "$PATCH_SHA" <<'PY'
import json, sys, datetime
path, version, base, stamp, count, patch_file, size, sha = sys.argv[1:9]
json.dump({"format": 1, "version": version, "base": base, "stamp": stamp, "commit_count": int(count or 0),
           "patch_file": patch_file, "patch_size": int(size), "patch_sha256": sha,
           "published": datetime.datetime.now().isoformat(timespec="seconds")}, open(path, "w"), indent=2)
PY
	openssl dgst -sha256 -sign "$KEY" -out "$UPD_DIR/manifest.sig" "$UPD_DIR/manifest.json"
	python3 -c "import json;print(json.load(open('Data/update_public_key.json'))['pem'],end='')" > "$UPD_DIR/.pub.pem"
	openssl dgst -sha256 -verify "$UPD_DIR/.pub.pem" -signature "$UPD_DIR/manifest.sig" "$UPD_DIR/manifest.json" >/dev/null \
		|| die "The signature does not verify against Data/update_public_key.json — is that the public half of $KEY?"
	rm -f "$UPD_DIR/.pub.pem"
	say "Manifest signed (build $STAMP on base $(json "$BASE_DIR/base.json" stamp))."
fi

# ── upload ───────────────────────────────────────────────────────────────────
if [ -n "$LOCAL_DEST" ]; then
	DEST="$LOCAL_DEST"; mkdir -p "$DEST/updates"
	RSH=(); RUN() { bash -c "$*"; }
else
	SSH_OPTS=(-o ControlMaster=auto -o "ControlPath=/tmp/aldenexia-update-%C" -o ControlPersist=120)
	RSH=(-e "ssh ${SSH_OPTS[*]}"); DEST="$HOST:$DIR"
	RUN() { ssh "${SSH_OPTS[@]}" "$HOST" "$@"; }
	say "Uploading to $DEST ..."
	RUN "mkdir -p '$DIR/updates' '$DIR/tls'"
fi
RS=(rsync -rlt --partial --info=stats1,progress2 -h)

if [ "$DO_SERVER" = 1 ]; then
	# rsync writes each file under a temporary name and renames it into place: a running server binary is never overwritten.
	"${RS[@]}" "${RSH[@]}" --chmod=F755 "$SERVER_BIN" tools/run_server.sh tools/run_update_server.sh "$DEST/"
fi
if [ "$DO_CLIENT" = 1 ]; then
	[ -z "$PATCH_FILE" ] || "${RS[@]}" "${RSH[@]}" "$UPD_DIR/$PATCH_FILE" "$DEST/updates/"
	"${RS[@]}" "${RSH[@]}" "$UPD_DIR/manifest.json" "$UPD_DIR/manifest.sig" "$DEST/updates/"   # last: makes the update visible
	# keep the newest three patches on the server (a player mid-download of the previous one isn't cut off)
	if [ -n "$LOCAL_DEST" ]; then
		( cd "$DEST/updates" && ls -t patch-*.pck 2>/dev/null | tail -n +4 | xargs -r rm -f )
	else
		RUN "cd '$DIR/updates' && ls -t patch-*.pck 2>/dev/null | tail -n +4 | xargs -r rm -f"
	fi
fi

# ── verify + next steps ─────────────────────────────────────────────────────
if [ "$DO_SERVER" = 1 ] && [ -z "$LOCAL_DEST" ]; then
	L="$(sha256sum "$SERVER_BIN" | cut -d' ' -f1)"; R="$(RUN "sha256sum '$DIR/Aldenexia_Server.x86_64'" | cut -d' ' -f1)"
	[ "$L" = "$R" ] && say "Server binary verified on the server (sha256 ${L:0:12}...)." || die "Server binary checksum MISMATCH after upload — run again."
fi
if [ "$DO_CLIENT" = 1 ] && [ -z "$LOCAL_DEST" ]; then
	URL_HOST="${HOST#*@}"
	if curl -fsS --max-time 6 "http://$URL_HOST:$UPDATE_PORT/manifest.json" 2>/dev/null | grep -q "\"stamp\": \"$STAMP\""; then
		say "Players can now download build $STAMP from http://$URL_HOST:$UPDATE_PORT/."
	else
		warn "uploaded, but http://$URL_HOST:$UPDATE_PORT/manifest.json is not being served (yet). Start the update web server on the server:"
		echo "         cd $DIR && ./run_update_server.sh          (see --help in that script; needs TCP $UPDATE_PORT open)" >&2
	fi
fi
if [ -n "$RESTART_CMD" ] && [ -z "$LOCAL_DEST" ]; then
	say "Restarting: $RESTART_CMD"
	ssh -t "${SSH_OPTS[@]}" "$HOST" "$RESTART_CMD"
elif [ "$DO_SERVER" = 1 ]; then
	say "The running server still uses the OLD build until you restart it (Ctrl-C in its terminal saves everyone, then start it again)."
fi
say "Done."
