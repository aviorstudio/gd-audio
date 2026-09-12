#!/usr/bin/env python3
"""Build or validate the closed gd-audio release archive."""

from __future__ import annotations

import argparse
import hashlib
import os
from pathlib import Path, PurePosixPath
import stat
import sys
import zipfile

ROOT = Path(__file__).resolve().parents[1]
MANIFEST = ROOT / "tools" / "package_manifest.txt"


def expected_files() -> list[str]:
    entries = [line.strip() for line in MANIFEST.read_text(encoding="utf-8").splitlines() if line.strip()]
    if len(entries) != len(set(entries)) or entries != sorted(entries):
        raise ValueError("package manifest must be unique and sorted")
    return entries


def validate_member(info: zipfile.ZipInfo) -> None:
    path = PurePosixPath(info.filename)
    if info.filename.endswith("/"):
        raise ValueError(f"directory entries are not allowed: {info.filename}")
    if path.is_absolute() or ".." in path.parts or len(path.parts) != 1:
        raise ValueError(f"unsafe or undeclared package path: {info.filename}")
    mode = info.external_attr >> 16
    if stat.S_ISLNK(mode):
        raise ValueError(f"symlink is not allowed: {info.filename}")


def validate(archive: Path) -> str:
    expected = expected_files()
    with zipfile.ZipFile(archive) as package:
        infos = package.infolist()
        names = [info.filename for info in infos]
        if len(names) != len(set(names)):
            raise ValueError("duplicate ZIP members are not allowed")
        for info in infos:
            validate_member(info)
        if sorted(names) != expected:
            raise ValueError(f"closed manifest mismatch: expected {expected}, got {sorted(names)}")
        for info in infos:
            with package.open(info) as member:
                while member.read(1024 * 1024):
                    pass
    digest = hashlib.sha256(archive.read_bytes()).hexdigest()
    print(f"PACKAGE_SHA256={digest}")
    print(f"PACKAGE_FILES={len(expected)}")
    return digest


def build(archive: Path) -> str:
    archive.parent.mkdir(parents=True, exist_ok=True)
    temporary = archive.with_suffix(archive.suffix + ".part")
    temporary.unlink(missing_ok=True)
    with zipfile.ZipFile(temporary, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=9) as package:
        for name in expected_files():
            source = ROOT / "addon" / name
            if not source.is_file() or source.is_symlink():
                raise ValueError(f"manifest source must be a regular non-symlink file: {source}")
            info = zipfile.ZipInfo(name, date_time=(1980, 1, 1, 0, 0, 0))
            info.create_system = 3
            info.external_attr = (stat.S_IFREG | 0o644) << 16
            package.writestr(info, source.read_bytes(), compress_type=zipfile.ZIP_DEFLATED, compresslevel=9)
    os.replace(temporary, archive)
    return validate(archive)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("command", choices=("build", "validate"))
    parser.add_argument("archive", type=Path)
    args = parser.parse_args()
    try:
        (build if args.command == "build" else validate)(args.archive.resolve())
    except (OSError, ValueError, zipfile.BadZipFile) as error:
        print(f"package error: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
