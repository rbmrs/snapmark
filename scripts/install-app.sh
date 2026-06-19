#!/bin/zsh

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SOURCE_APP="${OUTPUT_DIR:-$ROOT_DIR/dist}/Printy.app"
DESTINATION_APP="${DESTINATION_APP:-$HOME/Applications/Printy.app}"

"$ROOT_DIR/scripts/build-app.sh"

mkdir -p "$(dirname "$DESTINATION_APP")"
rm -rf "$DESTINATION_APP"
cp -R "$SOURCE_APP" "$DESTINATION_APP"

echo "Installed:"
echo "$DESTINATION_APP"
echo
echo "Launching Printy…"
open "$DESTINATION_APP"
