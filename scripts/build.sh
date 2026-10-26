#!/usr/bin/env bash
set -euo pipefail
mkdir -p dist
python3 tools/package.py build dist/@aviorstudio_gd-audio.zip | tee dist/package-evidence.txt
sha256sum dist/@aviorstudio_gd-audio.zip > dist/package.sha256
