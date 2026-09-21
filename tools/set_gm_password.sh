#!/usr/bin/env bash
# set_gm_password.sh — set or change the game-master password on the game server, from your own PC.
#
#   tools/set_gm_password.sh user@host                 ask for the new password (typed twice, not shown)
#   tools/set_gm_password.sh user@host --generate      make a random one and print it
#   tools/set_gm_password.sh user@host --show          print the password that is set now
#   tools/set_gm_password.sh user@host --remove        delete it: nobody can become a game master until you set one again
#
# The password is the first line of a file on the server (default ~/.local/share/godot/app_userdata/Aldenexia-Lightfall/gm_password;
# change the folder with ALDENEXIA_SERVER_USERDIR, relative to the server's home, like tools/server_maintenance.sh). Only you can read it
# (mode 600). The server reads the file at every attempt, so a new password works at once, with NO restart. A player then types
# /gm enable <password> in the game (needs a build with this feature); being a game master lasts for that session only.
set -euo pipefail

HOST="${1:-}"
[ -n "$HOST" ] && [ "${HOST#-}" = "$HOST" ] || { sed -n '2,15p' "$0" | sed 's/^# \{0,1\}//'; exit 2; }
shift
MODE="ask"
while [ $# -gt 0 ]; do
	case "$1" in
		--generate) MODE="generate"; shift ;;
		--show) MODE="show"; shift ;;
		--remove) MODE="remove"; shift ;;
		*) echo "Unknown option: $1" >&2; exit 2 ;;
	esac
done

USERDIR="${ALDENEXIA_SERVER_USERDIR:-.local/share/godot/app_userdata/Aldenexia-Lightfall}"
FILE="$USERDIR/gm_password"

case "$MODE" in
	show)
		ssh "$HOST" "cat \"\$HOME/$FILE\"" ;;
	remove)
		ssh "$HOST" "rm -f \"\$HOME/$FILE\"" && echo "Removed: nobody can become a game master until you set a new password." ;;
	*)
		if [ "$MODE" = "generate" ]; then
			PW="$(python3 -c "import secrets,string;print(''.join(secrets.choice(string.ascii_letters+string.digits) for _ in range(20)))")"
		else
			read -r -s -p "New game master password: " PW; echo
			read -r -s -p "Again: " PW2; echo
			[ "$PW" = "$PW2" ] || { echo "The two passwords differ; nothing changed." >&2; exit 1; }
		fi
		[ "${#PW}" -ge 8 ] || { echo "Use at least 8 characters; nothing changed." >&2; exit 1; }
		# through ssh's standard input, so it never appears in a process list
		printf '%s\n' "$PW" | ssh "$HOST" "umask 077; mkdir -p \"\$HOME/$USERDIR\" && cat > \"\$HOME/$FILE.tmp\" && mv \"\$HOME/$FILE.tmp\" \"\$HOME/$FILE\" && chmod 600 \"\$HOME/$FILE\""
		echo "Game master password set on $HOST ($FILE); no restart needed."
		[ "$MODE" = "generate" ] && echo "It is: $PW"
		;;
esac
