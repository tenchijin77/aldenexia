#!/usr/bin/env bash
# Prints the RPC declarations of the scripts that must stay identical between released builds (the autoloads: Net carries the
# version handshake). Godot refuses every RPC on a node whose RPC list differs between the two peers, and a client that cannot
# complete the handshake sees the server as "offline" and can never be offered an update. tools/update.sh compares this output with
# tools/net_rpc_released.txt (written by `tools/update.sh --new-base`).
cd "$(dirname "$0")/.."
for f in Scripts/net.gd Scripts/global.gd Scripts/game_log.gd Scripts/inventory_autoload.gd Scripts/patch_loader.gd; do
	echo "## $f"
	grep -A1 '^@rpc' "$f" | grep -v '^--$' || true   # a file with no @rpc lines makes grep exit 1: not an error here
done
exit 0
