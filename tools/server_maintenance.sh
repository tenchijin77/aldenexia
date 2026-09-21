#!/usr/bin/env bash
# server_maintenance.sh — warn the players and take the game server down for an update, from your own PC.
#
#   tools/server_maintenance.sh user@host [--minutes 5] [--wait] [--restart 'CMD']
#   tools/server_maintenance.sh user@host --cancel
#
# What happens on the server (Scripts/server_notice.gd): a big red message appears in the middle of every player's screen
# ("An update approaches and the end draws near! Save your player and log out now!"), new logins are refused, reminders follow at 3 min,
# 1 min, 30 s and 10 s, and the server saves everyone and exits: the moment nobody is logged in (at once when nobody is), or when the
# minutes are up. The words: Data/server_notices.json.
#   --minutes N    how long to wait for players to log out (default 5)
#   --wait         stay here until the server process has exited (up to N + 3 minutes)
#   --restart CMD  after it exited, run CMD on the server to start it again, e.g.
#                    --restart 'tmux send-keys -t aldenexia "./run_aldenexia.sh" Enter'   (or 'cd ~/aldenexia && nohup ./run_aldenexia.sh &')
#   --cancel       stop a countdown that is running ("The end is postponed...")
# The request is a small file the server checks every second (its default place is the game's user folder on the server:
# ~/.local/share/godot/app_userdata/Aldenexia-Lightfall/server_maintenance; change it with ALDENEXIA_SERVER_USERDIR, relative to the
# server's home folder, if your server runs from somewhere else). A GM in the game can do the same with /maintenance [minutes|cancel].
# tools/update.sh --reboot-in N does upload + this in one go. NOTE: the server can only announce once it is running a build that has this
# feature; the first update after it was added still needs a manual restart.
set -euo pipefail

HOST="${1:-}"
[ -n "$HOST" ] && [ "${HOST#-}" = "$HOST" ] || { sed -n '2,22p' "$0" | sed 's/^# \{0,1\}//'; exit 2; }
shift
MINUTES=5; WAIT=0; RESTART=""; CANCEL=0
while [ $# -gt 0 ]; do
	case "$1" in
		--minutes) MINUTES="${2:?--minutes needs a number}"; shift 2 ;;
		--wait) WAIT=1; shift ;;
		--restart) RESTART="${2:?--restart needs a command}"; shift 2 ;;
		--cancel) CANCEL=1; shift ;;
		*) echo "Unknown option: $1" >&2; exit 2 ;;
	esac
done

USERDIR="${ALDENEXIA_SERVER_USERDIR:-.local/share/godot/app_userdata/Aldenexia-Lightfall}"
FILE="$USERDIR/server_maintenance"
SSH_OPTS=(-o ControlMaster=auto -o "ControlPath=/tmp/aldenexia-maint-%C" -o ControlPersist=120)
say()  { printf '\033[1m[maintenance]\033[0m %s\n' "$*"; }
RUN()  { ssh "${SSH_OPTS[@]}" "$HOST" "$@"; }
# the [-] trick keeps pgrep from matching this very command line
server_running() { RUN "pgrep -f -- '[-]-server' >/dev/null"; }

if [ "$CANCEL" = 1 ]; then
	RUN "mkdir -p \"\$HOME/$USERDIR\" && echo cancel > \"\$HOME/$FILE\""
	say "Cancel requested: the players will be told the end is postponed."
	exit 0
fi

if ! server_running; then
	say "No game server is running on $HOST: nothing to warn."
else
	RUN "mkdir -p \"\$HOME/$USERDIR\" && echo '$MINUTES' > \"\$HOME/$FILE\""
	say "Requested: players are warned and the server goes down within $MINUTES minute(s), sooner once everyone is out."
fi

if [ "$WAIT" = 1 ] || [ -n "$RESTART" ]; then
	LIMIT=$(( (MINUTES + 3) * 60 )); WAITED=0
	while server_running; do
		if [ "$WAITED" -ge "$LIMIT" ]; then
			echo "The server has not exited after $((LIMIT / 60)) minutes. Check it (tmux / terminal) before restarting it." >&2
			exit 1
		fi
		sleep 5; WAITED=$((WAITED + 5))
		[ $((WAITED % 30)) -eq 0 ] && say "still waiting for the server to exit (${WAITED}s)..."
	done
	say "The server has exited (it saved everyone first)."
	if [ -n "$RESTART" ]; then
		say "Starting it again: $RESTART"
		ssh -t "${SSH_OPTS[@]}" "$HOST" "$RESTART"
	fi
fi
