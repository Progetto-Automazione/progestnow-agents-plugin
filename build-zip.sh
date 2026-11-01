#!/usr/bin/env bash
# Genera lo zip del plugin ProgestNOW Agents.
#
# USO (dalla root del repo o da qualsiasi cartella):
#   ./build-zip.sh
#
# Output: dist/progestnow-agents-<versione>.zip (versione letta da plugin.json)
# Esclusi dallo zip: misc/, dist/, .git/, .gitignore e questo script.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT"

SCRIPT="$(basename "${BASH_SOURCE[0]}")"
VERSION="$(sed -n 's/^[[:space:]]*"version":[[:space:]]*"\([^"]*\)".*/\1/p' plugin.json | head -1)"
OUT="dist/progestnow-agents-${VERSION:-dev}.zip"

mkdir -p dist
rm -f "$OUT"

zip -r -q "$OUT" . \
  -x 'misc/*' 'dist/*' '.git/*' '.gitignore' "$SCRIPT"

echo "Creato $OUT"
unzip -l "$OUT" | tail -n 1
