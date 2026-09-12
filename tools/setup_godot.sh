#!/usr/bin/env bash
set -euo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
manifest_fields=$(python3 - "$script_dir/godot-release.json" <<'PY'
import json, re, sys
with open(sys.argv[1], encoding="utf-8") as handle:
    release = json.load(handle)
assert re.fullmatch(r"\d+\.\d+\.\d+", release["version"])
for key in ("binary_sha512", "templates_sha512"):
    assert re.fullmatch(r"[0-9a-f]{128}", release[key])
assert release["binary_archive"] == f"Godot_v{release['version']}-stable_linux.x86_64.zip"
assert release["templates_archive"] == f"Godot_v{release['version']}-stable_export_templates.tpz"
for key in ("version", "binary_archive", "binary_sha512", "templates_archive", "templates_sha512"):
    print(release[key])
PY
)
mapfile -t release_fields <<< "$manifest_fields"
version=${release_fields[0]}
if [[ -n ${GODOT_VERSION:-} && $GODOT_VERSION != "$version" ]]; then
  echo "Unsupported Godot version $GODOT_VERSION; update the reviewed manifest first" >&2
  exit 1
fi

runner_temp=${RUNNER_TEMP:-${TMPDIR:-/tmp}}
archive_dir=${GODOT_ARCHIVE_DIR:-$runner_temp/gd-audio-godot-downloads}
binary_dir=${GODOT_BINARY_DIR:-$runner_temp/gd-audio-godot-bin}
mkdir -p "$archive_dir" "$binary_dir"

fetch_verified() {
  local name=$1 checksum=$2 archive="$archive_dir/$1"
  if [[ ! -f $archive ]]; then
    curl -fsSL --connect-timeout 15 --max-time 600 --retry 3 --retry-delay 2 \
      "https://github.com/godotengine/godot/releases/download/$version-stable/$name" \
      -o "$archive.part"
    mv "$archive.part" "$archive"
  fi
  printf '%s  %s\n' "$checksum" "$archive" | sha512sum --check --strict
}

fetch_verified "${release_fields[1]}" "${release_fields[2]}"
rm -rf "$binary_dir/unpacked"
mkdir -p "$binary_dir/unpacked"
unzip -oq "$archive_dir/${release_fields[1]}" -d "$binary_dir/unpacked"
install -m 755 "$binary_dir/unpacked/${release_fields[1]%.zip}" "$binary_dir/godot"
if [[ -n ${GITHUB_PATH:-} ]]; then
  printf '%s\n' "$binary_dir" >> "$GITHUB_PATH"
fi
"$binary_dir/godot" --version

if [[ ${INSTALL_TEMPLATES:-false} == true ]]; then
  fetch_verified "${release_fields[3]}" "${release_fields[4]}"
  template_dir="${XDG_DATA_HOME:-$HOME/.local/share}/godot/export_templates/$version.stable"
  rm -rf "$template_dir"
  mkdir -p "$template_dir"
  unzip -ojq "$archive_dir/${release_fields[3]}" -d "$template_dir"
  test -f "$template_dir/web_debug.zip"
  test -f "$template_dir/web_release.zip"
fi
