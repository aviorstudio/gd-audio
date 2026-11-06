#!/usr/bin/env python3
"""Negative/restored controls for the release archive validator."""

from __future__ import annotations

import importlib.util
import os
from pathlib import Path
import stat
import tempfile
import zipfile

ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location("shared_addon_package", Path(os.environ["TOOLS_ROOT"]) / "helpers/addon-package.py")
package = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(package)
MANIFEST = ROOT / "package.files"


def rejected(name: str, members: list[tuple[zipfile.ZipInfo | str, bytes]]) -> None:
    with tempfile.TemporaryDirectory(prefix="gd-audio-package-control-") as temporary:
        archive = Path(temporary) / f"{name}.zip"
        with zipfile.ZipFile(archive, "w") as output:
            for member, contents in members:
                output.writestr(member, contents)
        try:
            package.verify(archive, MANIFEST)
        except ValueError:
            print(f"EXPECTED_FAILURE gd-audio package-control={name}")
            return
    raise AssertionError(f"package negative control unexpectedly passed: {name}")


def main() -> None:
    expected = []
    for name in package.manifest_files(MANIFEST):
        member = zipfile.ZipInfo(name)
        member.create_system = 3
        member.external_attr = (stat.S_IFREG | 0o644) << 16
        expected.append((member, b"fixture"))
    rejected("traversal", expected + [("../escape", b"bad")])
    rejected("undeclared", expected + [("tests.gd", b"bad")])
    rejected("missing", expected[:-1])
    duplicate = expected + [(expected[0][0], b"duplicate")]
    rejected("duplicate", duplicate)
    symlink = zipfile.ZipInfo(expected[0][0].filename)
    symlink.create_system = 3
    symlink.external_attr = (stat.S_IFLNK | 0o777) << 16
    rejected("symlink", [(symlink, b"target")] + expected[1:])
    with tempfile.TemporaryDirectory(prefix="gd-audio-package-restored-") as temporary:
        archive = Path(temporary) / "restored.zip"
        package.build(ROOT / "addon", MANIFEST, archive)
    print("ASSERTIONS gd-audio package_test 6")
    print("PASS gd-audio package_test")


if __name__ == "__main__":
    main()
