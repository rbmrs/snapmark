#!/bin/zsh

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_DIR="${OUTPUT_DIR:-$ROOT_DIR/dist}/Snapmark.app"

"$ROOT_DIR/scripts/build-app.sh"

echo "Launching Snapmark…"
open "$APP_DIR"
