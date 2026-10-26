#!/usr/bin/env bash
set -euo pipefail
python3 tools/package_test.py
bash tests/test.sh --self-test
bash tests/test.sh
