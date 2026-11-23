#!/bin/bash
# Build the copy of this project that is safe to publish: committed files only,
# minus device-specific receipts, with hardware and account identifiers replaced.
# Usage: scripts/make_public_export.sh DEST_DIR   (DEST_DIR must be empty or absent)
set -euo pipefail
cd "$(dirname "$0")/.."
dest=${1:?destination directory required}
mkdir -p "$dest"
[ -z "$(ls -A "$dest" | grep -v '^\.git$' || true)" ] || { echo "destination not empty" >&2; exit 1; }
git archive HEAD | tar -x -C "$dest"
# Raw device install receipts carry the iPad's identifier and add nothing for readers.
find "$dest/docs/evidence" \( -name install.json -o -name installed.json \) -delete
team=$(sed -n "s/.*'DEVELOPMENT_TEAM':'\([A-Z0-9]*\)'.*/\1/p" scripts/make_project.py | head -1)
serials=$(grep -rhoE '"serial" *: *"[A-Z0-9]+"' docs/evidence | sed -E 's/.*"([A-Z0-9]+)"$/\1/' | sort -u)
uuid='[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}'
grep -rlIE "$team|$uuid|$(echo "$serials" | paste -sd'|' -)" "$dest" --exclude-dir=.git | while read -r f; do
  for s in $serials; do sed -i '' "s/$s/SERIAL-REDACTED/g" "$f"; done
  sed -i '' -E "s/$team/YOURTEAMID/g; s/$uuid/DEVICE-ID-REDACTED/g" "$f"
done
# Refuse to hand back a copy that still carries any of them, or a home-folder path.
if grep -rnIE "$team|$uuid|/Users/[a-z]+|$(echo "$serials" | paste -sd'|' -)" "$dest" --exclude-dir=.git; then
  echo "identifiers remain; not safe to publish" >&2; exit 1
fi
echo "public copy ready: $dest"
