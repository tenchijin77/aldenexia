#!/usr/bin/env bash
# Stamps the current git commit into Data/build_info.json so an EXPORTED build
# knows exactly what it was built from (shown next to the version on the main
# menu, and compared during the multiplayer join check). Run it right before
# exporting; the file is git-ignored. A "-dirty" suffix means uncommitted
# changes were present. Usage: tools/stamp_build.sh [output-path]
set -euo pipefail
cd "$(dirname "$0")/.."
out="${1:-Data/build_info.json}"
hash="$(git rev-parse --short HEAD)"
if [ -n "$(git status --porcelain --untracked-files=no)" ]; then hash="${hash}-dirty"; fi
count="$(git rev-list --count HEAD)"
printf '{\n  "build": "%s",\n  "commit_count": %s,\n  "date": "%s"\n}\n' "$hash" "$count" "$(date +%Y-%m-%d)" > "$out"
echo "Wrote $out: build $hash (commit #$count)"
