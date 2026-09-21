#!/usr/bin/env bash
# One-time setup for signed game updates. Creates the RSA key pair that proves an update came from you:
#   private key  ~/.config/aldenexia/update_signing.key   (stays on THIS machine, never commit or share it — back it up)
#   public key   Data/update_public_key.json               (goes into the game; commit it)
# tools/update.sh signs every update's manifest with the private key; the game refuses any update whose signature
# doesn't verify against the public key baked into it. Replacing the key later means every player needs a new full build,
# because the public key lives in the base build. Refuses to overwrite an existing key.
set -euo pipefail
cd "$(dirname "$0")/.."
KEY="${ALDENEXIA_SIGNING_KEY:-$HOME/.config/aldenexia/update_signing.key}"
PUB="Data/update_public_key.json"
write_pub() {  # stored as JSON so the game export packs it like every other data file (a bare .pem would be skipped)
	openssl rsa -in "$KEY" -pubout 2>/dev/null | python3 -c 'import json,sys; print(json.dumps({"algorithm": "RSA-SHA256", "pem": sys.stdin.read()}, indent=2))' > "$PUB"
}
if [ -f "$KEY" ]; then
	echo "A signing key already exists at $KEY — leaving it alone."
	[ -f "$PUB" ] || { write_pub; echo "Wrote the missing $PUB from it."; }
	exit 0
fi
mkdir -p "$(dirname "$KEY")"
umask 077
openssl genrsa -out "$KEY" 3072 2>/dev/null
chmod 600 "$KEY"
write_pub
echo "Created $KEY (private — back it up somewhere safe)"
echo "Created $PUB (public — commit it; the next full build carries it to players)"
