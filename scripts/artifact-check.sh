#!/usr/bin/env bash
set -euo pipefail
python3 tools/package_smoke.py dist/@aviorstudio_gd-audio.zip --godot "$GODOT_BIN" --web-output dist/web-smoke
