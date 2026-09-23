#!/usr/bin/env bash
# One command to publish a test update: exports the dedicated SERVER and the WINDOWS and LINUX client patches, signs the
# update and rsyncs everything to the server machine. The intended routine:
#     git commit  ->  tools/stamp_build.sh  ->  tools/update.sh
#
#   tools/update.sh                     export server + Windows patch + Linux patch, sign, upload
#   tools/update.sh --new-base          make THIS build the new full client "base" for both platforms (see below)
#   tools/update.sh --stamp             run tools/stamp_build.sh first (so it is one command after the commit)
#   tools/update.sh --platforms linux   only that client platform (windows | linux | windows,linux — default both)
#   tools/update.sh --server-only       only the server binary          (--client-only: only the client patches)
#   tools/update.sh --skip-export       don't rebuild, just sign + upload what is already in Builds/
#   tools/update.sh --restart 'CMD'     afterwards run CMD on the server (e.g. to restart it)
#   tools/update.sh --reboot-in N       after uploading: warn the players (a red message on their screens), wait up to N minutes for them to
#                                       log out, let the server save and exit, then run the --restart command if there is one
#                                       (tools/server_maintenance.sh; needs the server to already run a build with the feature)
#   tools/update.sh --host user@host --dir aldenexia     where to upload (defaults below)
#   (Before exporting, the Lumora navmesh is rebaked automatically if the terrain or zone scene changed since it was baked.)
#   tools/update.sh --local DIR         "upload" into a local folder instead — for testing this script
#
# HOW CLIENT UPDATES WORK. Players install one FULL client build per platform (Builds/Windows: exe + .pck + dll, Builds/Linux:
# binary + .pck + .so). That build is the BASE. Every update is only a PATCH: a small .pck holding the files that changed since
# the base (scripts, scenes, data — typically well under 10 MB). Players download it from the server (Join screen ->
# "Download update") and the game restarts into it. Each platform has its own base and its own patch (a patch is made against
# one specific base pack); the signed manifest lists both and each client picks its own. Players re-download everything only
# when there is a new base. Make one with --new-base when:
#   * the version number in project.godot (config/version) changes, or project.godot changes in any other way that matters
#     (autoloads, input map, display settings...): a patch cannot carry project.godot;
#   * the executable, the Terrain3D library or the Godot version changes;
#   * the patch has grown large (each patch holds EVERYTHING changed since the base, not just the last commit).
# After --new-base, share Builds/Windows (and run Builds/Linux yourself) — the only time players get the whole game again.
#
# The server binary is always a full export (155 MB; rsync only sends the parts that changed) and is uploaded under a
# temporary name then renamed, so a RUNNING server is never disturbed — it keeps the old file until you restart it.
# On the server the updates live in <dir>/updates and are served over HTTP (tools/run_update_server.sh, TCP port 8911).
# The manifest is uploaded LAST, so a player never sees an update whose patch isn't there yet.
#
# Files kept on this machine (all git-ignored): Builds/Base/<platform>/ (base.pck + base.json: what the patches are made
# against), Builds/Update/ (the last patches, manifest.json, manifest.sig, export.log). The signing key is
# ~/.config/aldenexia/update_signing.key (create it once with tools/make_update_key.sh); its public half is
# Data/update_public_key.json.
set -euo pipefail

HOST="${ALDENEXIA_DEPLOY_HOST:-rwilkinson@192.168.77.100}"
DIR="${ALDENEXIA_DEPLOY_DIR:-aldenexia}"
KEY="${ALDENEXIA_SIGNING_KEY:-$HOME/.config/aldenexia/update_signing.key}"
UPDATE_PORT="${ALDENEXIA_UPDATE_PORT:-8911}"
PLATFORMS="windows,linux"
DO_STAMP=0; NEW_BASE=0; DO_SERVER=1; DO_CLIENT=1; DO_EXPORT=1; RESTART_CMD=""; LOCAL_DEST=""; REBOOT_IN=""

while [ $# -gt 0 ]; do
	case "$1" in
		--host)        HOST="${2:?--host needs user@host}"; shift 2 ;;
		--dir)         DIR="${2:?--dir needs a directory}"; shift 2 ;;
		--local)       LOCAL_DEST="${2:?--local needs a folder}"; shift 2 ;;
		--platforms)   PLATFORMS="${2:?--platforms needs windows, linux or windows,linux}"; shift 2 ;;
		--new-base)    NEW_BASE=1; shift ;;
		--stamp)       DO_STAMP=1; shift ;;
		--server-only) DO_CLIENT=0; shift ;;
		--client-only) DO_SERVER=0; shift ;;
		--skip-export) DO_EXPORT=0; shift ;;
		--restart)     RESTART_CMD="${2:?--restart needs a command}"; shift 2 ;;
		--reboot-in)   REBOOT_IN="${2:?--reboot-in needs minutes}"; shift 2 ;;
		-h|--help)     sed -n '2,37p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
		*) echo "Unknown option: $1 (try --help)" >&2; exit 2 ;;
	esac
done

cd "$(dirname "$0")/.."
GODOT="${GODOT:-godot}"
SERVER_BIN="Builds/Server/Aldenexia_Server.x86_64"
SERVER_PRESET="Linux Server"
# (Overridable with environment variables — used to test this script without touching the real builds/base:
# ALDENEXIA_WINDOWS_DIR, ALDENEXIA_LINUX_DIR, ALDENEXIA_BASE_DIR, ALDENEXIA_UPDATE_DIR.)
BASE_DIR="${ALDENEXIA_BASE_DIR:-Builds/Base}"; UPD_DIR="${ALDENEXIA_UPDATE_DIR:-Builds/Update}"
say()  { printf '\033[1m[update]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[update] WARNING:\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m[update] ERROR:\033[0m %s\n' "$*" >&2; exit 1; }
json() { python3 -c "import json,sys; d=json.load(open(sys.argv[1])); print(d.get(sys.argv[2],''))" "$1" "$2" 2>/dev/null || true; }

# Sets P_PRESET, P_DIR, P_BIN, P_PCK for one client platform.
platform_setup() {
	case "$1" in
		windows) P_PRESET="Windows Desktop"; P_DIR="${ALDENEXIA_WINDOWS_DIR:-Builds/Windows}"; P_BIN="$P_DIR/Aldenexia_Lightfall.exe" ;;
		linux)   P_PRESET="Linux";           P_DIR="${ALDENEXIA_LINUX_DIR:-Builds/Linux}";     P_BIN="$P_DIR/Aldenexia_Lightfall.x86_64" ;;
		*) die "Unknown platform '$1' (use windows, linux or windows,linux)." ;;
	esac
	P_PCK="$P_DIR/Aldenexia_Lightfall.pck"
}
PLATFORM_LIST="${PLATFORMS//,/ }"
mkdir -p "$BASE_DIR" "$UPD_DIR" "$(dirname "$SERVER_BIN")"
# The first version of this script kept a single (Windows) base in Builds/Base/ and a manifest without per-platform entries.
# Move that base into Builds/Base/windows/ and keep its published state as the Windows entry, so nothing already handed out is lost.
if [ -f "$BASE_DIR/base.json" ] && [ ! -f "$BASE_DIR/windows/base.json" ]; then
	mkdir -p "$BASE_DIR/windows" && mv "$BASE_DIR/base.json" "$BASE_DIR/base.pck" "$BASE_DIR/windows/"
	printf '\033[1m[update]\033[0m %s\n' "Moved the existing Windows base into $BASE_DIR/windows/."
fi
if [ -f "$UPD_DIR/manifest.json" ] && [ ! -f "$UPD_DIR/entry-windows.json" ] && ! grep -q '"platforms"' "$UPD_DIR/manifest.json"; then
	python3 - "$UPD_DIR/manifest.json" "$UPD_DIR/entry-windows.json" <<'PY'
import json, sys
m = json.load(open(sys.argv[1]))
json.dump({k: m.get(k, "") for k in ("base", "stamp", "commit_count", "patch_file", "patch_size", "patch_sha256")}, open(sys.argv[2], "w"), indent=2)
PY
fi
for plat in $PLATFORM_LIST; do platform_setup "$plat"; mkdir -p "$BASE_DIR/$plat" "$P_DIR"; done  # Godot will not create an export folder itself

# ── preflight ────────────────────────────────────────────────────────────────
# The RPC lists of the autoloads (Net above all) must not change between released builds: an older client could no longer complete the
# handshake, would show the server as "offline" and could never be offered this update. New RPCs belong on scene nodes.
# tools/net_rpc_released.txt is the list of the build players run; --new-base (a fresh full build for everyone) rewrites it.
if [ "$NEW_BASE" = 1 ]; then
	tools/net_rpc_signature.sh > tools/net_rpc_released.txt
elif [ -f tools/net_rpc_released.txt ] && [ "$(tools/net_rpc_signature.sh)" != "$(cat tools/net_rpc_released.txt)" ]; then
	echo "The RPC declarations of an autoload (Net, Global...) changed since the released build:" >&2
	diff <(tools/net_rpc_signature.sh) tools/net_rpc_released.txt >&2 || true
	[ "${ALDENEXIA_ALLOW_RPC_CHANGE:-0}" = 1 ] || die "Publishing this would make every existing client see the server as offline (RPC checksum mismatch on Net). Move the new RPC to a scene node, or make a --new-base build for everyone (ALDENEXIA_ALLOW_RPC_CHANGE=1 skips this check)."
fi
[ "$DO_STAMP" = 1 ] && tools/stamp_build.sh
[ -f Data/build_info.json ] || die "No build stamp. Run tools/stamp_build.sh (or add --stamp) after committing."
STAMP="$(json Data/build_info.json build)"; COUNT="$(json Data/build_info.json commit_count)"
HEAD_HASH="$(git rev-parse --short HEAD 2>/dev/null || echo '?')"
VERSION="$(sed -n 's/^config\/version="\(.*\)"/\1/p' project.godot | head -1)"
PROJECT_SHA="$(sha256sum project.godot | cut -d' ' -f1)"
say "Build $STAMP (commit #$COUNT, game v$VERSION, git HEAD $HEAD_HASH) — clients: ${PLATFORM_LIST// /, }"
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
	say "$label ..."
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
# A navmesh baked before the last terrain/scene edit would ship with walkable areas that no longer match the ground (NPCs
# snag on new hills). If anything under zones/lumora_terrain/ or the zone scene is newer than the navmesh, rebake it first.
NAVMESH="Data/lumora_outskirts_terrain_navmesh.tres"
if [ "$DO_EXPORT" = 1 ] && [ -n "$(find zones/lumora_terrain Scenes/lumora_outskirts3d.tscn -newer "$NAVMESH" -print -quit 2>/dev/null)" ]; then
	echo "Terrain changed since the navmesh was baked — rebaking $NAVMESH..."
	"$GODOT" --headless --path . --script res://tools/bake_lumora_navmesh.gd >"$UPD_DIR/navmesh_bake.log" 2>&1 \
		|| { tail -20 "$UPD_DIR/navmesh_bake.log" >&2; die "Navmesh bake failed — full output in $UPD_DIR/navmesh_bake.log"; }
	echo "  navmesh rebaked (commit $NAVMESH afterwards)."
fi
if [ "$DO_SERVER" = 1 ] && [ "$DO_EXPORT" = 1 ]; then
	export_logged "Exporting the dedicated server" "$SERVER_BIN" --export-release "$SERVER_PRESET"
fi
[ "$DO_SERVER" = 0 ] || [ -f "$SERVER_BIN" ] || die "No server build at $SERVER_BIN."

# What each platform's clients are offered is kept in $UPD_DIR/entry-<platform>.json, so publishing one platform doesn't
# drop the other one from the manifest.
write_entry() {  # write_entry <platform> <base> <patch file> <size> <sha256>
	python3 - "$UPD_DIR/entry-$1.json" "$2" "$STAMP" "${COUNT:-0}" "$3" "${4:-0}" "$5" <<'PY'
import json, sys
path, base, stamp, count, patch_file, size, sha = sys.argv[1:8]
json.dump({"base": base, "stamp": stamp, "commit_count": int(count), "patch_file": patch_file, "patch_size": int(size), "patch_sha256": sha}, open(path, "w"), indent=2)
PY
}
PATCH_FILES=()
if [ "$DO_CLIENT" = 1 ]; then
	for plat in $PLATFORM_LIST; do
		platform_setup "$plat"
		BD="$BASE_DIR/$plat"
		if [ "$NEW_BASE" = 1 ]; then
			[ "$DO_EXPORT" = 1 ] && export_logged "Exporting the FULL $plat client (new base)" "$P_PCK" --export-release "$P_PRESET" "$P_BIN"
			[ -f "$P_PCK" ] || die "No $plat client pack at $P_PCK."
			cp -f "$P_PCK" "$BD/base.pck"
			python3 - "$BD/base.json" "$STAMP" "$VERSION" "$PROJECT_SHA" <<'PY'
import json, sys, datetime
path, stamp, version, project_sha = sys.argv[1:5]
json.dump({"stamp": stamp, "version": version, "project_godot_sha256": project_sha,
           "created": datetime.datetime.now().isoformat(timespec="seconds")}, open(path, "w"), indent=2)
PY
			say "New $plat base: $STAMP  ($P_DIR)"
			write_entry "$plat" "$STAMP" "" 0 ""
		else
			[ -f "$BD/base.json" ] && [ -f "$BD/base.pck" ] || die "No $plat base build yet. Run once with --new-base (exports the full client and remembers it as the base)."
			BASE_STAMP="$(json "$BD/base.json" stamp)"
			[ "$(json "$BD/base.json" version)" = "$VERSION" ] || die "The game version changed ($(json "$BD/base.json" version) -> $VERSION). A patch can't change that: run with --new-base and share the new full builds."
			[ "$(json "$BD/base.json" project_godot_sha256)" = "$PROJECT_SHA" ] || warn "project.godot has changed since the $plat base ($BASE_STAMP). Patches can't carry project.godot changes (autoloads, input map, display settings...), so those won't reach players until a --new-base build."
			PATCH_FILE="patch-$STAMP-$plat.pck"
			if [ "$DO_EXPORT" = 1 ]; then
				rm -f "$UPD_DIR"/patch-*-"$plat".pck
				export_logged "Exporting the $plat client patch against base $BASE_STAMP" "$UPD_DIR/$PATCH_FILE" --export-patch "$P_PRESET" "$UPD_DIR/$PATCH_FILE" --patches "$BD/base.pck"
			fi
			[ -f "$UPD_DIR/$PATCH_FILE" ] || die "The $plat patch was not created ($UPD_DIR/$PATCH_FILE)."
			PATCH_SIZE="$(stat -c %s "$UPD_DIR/$PATCH_FILE")"; PATCH_SHA="$(sha256sum "$UPD_DIR/$PATCH_FILE" | cut -d' ' -f1)"
			say "$plat patch: $PATCH_FILE, $(numfmt --to=iec --suffix=B "$PATCH_SIZE")"
			[ "$PATCH_SIZE" -lt 314572800 ] || warn "the $plat patch is over 300 MB — time for a --new-base build."
			write_entry "$plat" "$BASE_STAMP" "$PATCH_FILE" "$PATCH_SIZE" "$PATCH_SHA"
			PATCH_FILES+=("$UPD_DIR/$PATCH_FILE")
		fi
	done

	# ── manifest + signature ──
	python3 - "$UPD_DIR" "$VERSION" <<'PY'
import json, sys, glob, os, datetime
upd, version = sys.argv[1:3]
platforms = {}
for path in sorted(glob.glob(os.path.join(upd, "entry-*.json"))):
    platforms[os.path.basename(path)[len("entry-"):-len(".json")]] = json.load(open(path))
# format stays 1: the first Windows builds handed out only read the top-level fields, which are the Windows entry
# (or the first entry there is); newer builds read "platforms".
legacy = platforms.get("windows") or next(iter(platforms.values()), {})
manifest = {"format": 1, "version": version, **{k: legacy.get(k, "") for k in ("base", "stamp", "commit_count", "patch_file", "patch_size", "patch_sha256")},
            "platforms": platforms, "published": datetime.datetime.now().isoformat(timespec="seconds")}
json.dump(manifest, open(os.path.join(upd, "manifest.json"), "w"), indent=2)
PY
	openssl dgst -sha256 -sign "$KEY" -out "$UPD_DIR/manifest.sig" "$UPD_DIR/manifest.json"
	python3 -c "import json;print(json.load(open('Data/update_public_key.json'))['pem'],end='')" > "$UPD_DIR/.pub.pem"
	openssl dgst -sha256 -verify "$UPD_DIR/.pub.pem" -signature "$UPD_DIR/manifest.sig" "$UPD_DIR/manifest.json" >/dev/null \
		|| die "The signature does not verify against Data/update_public_key.json — is that the public half of $KEY?"
	rm -f "$UPD_DIR/.pub.pem"
	say "Manifest signed (build $STAMP for: ${PLATFORM_LIST// /, })."
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
	# Native libraries the export puts next to the binary (Terrain3D's libterrain.linux.release.x86_64.so) must travel with
	# it — without it the server can't load the Terrain3D zone ("Cannot get class 'Terrain3DMaterial'").
	SERVER_LIBS=("$(dirname "$SERVER_BIN")"/*.so)
	[ -e "${SERVER_LIBS[0]}" ] || SERVER_LIBS=()
	[ "${#SERVER_LIBS[@]}" -gt 0 ] || warn "no .so next to $SERVER_BIN — a Terrain3D zone will not load on the server."
	"${RS[@]}" "${RSH[@]}" --chmod=F755 "$SERVER_BIN" "${SERVER_LIBS[@]}" tools/run_server.sh tools/run_update_server.sh "$DEST/"
fi
if [ "$DO_CLIENT" = 1 ]; then
	if [ "${#PATCH_FILES[@]}" -gt 0 ]; then "${RS[@]}" "${RSH[@]}" "${PATCH_FILES[@]}" "$DEST/updates/"; fi
	"${RS[@]}" "${RSH[@]}" "$UPD_DIR/manifest.json" "$UPD_DIR/manifest.sig" "$DEST/updates/"   # last: makes the update visible
	# keep the newest three patches per platform on the server (a player mid-download of the previous one isn't cut off)
	PRUNE='for p in windows linux; do ls -t patch-*-$p.pck 2>/dev/null | tail -n +4 | xargs -r rm -f; done'
	if [ -n "$LOCAL_DEST" ]; then ( cd "$DEST/updates" && bash -c "$PRUNE" ); else RUN "cd '$DIR/updates' && $PRUNE"; fi
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
		echo "         cd $DIR && ./run_update_server.sh          (see the top of that script; needs TCP $UPDATE_PORT open)" >&2
	fi
fi
if [ "$NEW_BASE" = 1 ] && [ "$DO_CLIENT" = 1 ]; then
	say "New base: run the fresh Builds/Linux yourself, and share Builds/Windows (exe + pck + dll) with your Windows players — once."
fi
if [ -n "$REBOOT_IN" ] && [ -z "$LOCAL_DEST" ]; then
	say "Warning the players and waiting for the server to go down (up to $REBOOT_IN minute(s))..."
	MAINT=(tools/server_maintenance.sh "$HOST" --minutes "$REBOOT_IN" --wait)
	[ -n "$RESTART_CMD" ] && MAINT+=(--restart "$RESTART_CMD")
	"${MAINT[@]}"
elif [ -n "$RESTART_CMD" ] && [ -z "$LOCAL_DEST" ]; then
	say "Restarting: $RESTART_CMD"
	ssh -t "${SSH_OPTS[@]}" "$HOST" "$RESTART_CMD"
elif [ "$DO_SERVER" = 1 ]; then
	say "The running server still uses the OLD build until you restart it (Ctrl-C in its terminal saves everyone, then start it again)."
fi
say "Done."
