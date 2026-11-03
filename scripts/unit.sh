#!/usr/bin/env bash
set -euo pipefail
python3 scripts/package_test.py
bash tests/test.sh --self-test
bash tests/test.sh
