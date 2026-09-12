#!/usr/bin/env python3
"""Negative/restored controls for the release archive validator."""

from __future__ import annotations

import importlib.util
from pathlib import Path
import stat
import tempfile
import zipfile

HERE = Path(__file__).resolve().parent
SPEC = importlib.util.spec_from_file_location("gd_audio_package", HERE / "package.py")
assert SPEC and SPEC.loader
package = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(package)


def rejected(name: str, members: list[tuple[zipfile.ZipInfo | str, bytes]]) -> None:
    with tempfile.TemporaryDirectory(prefix="gd-audio-package-control-") as temporary:
        archive = Path(temporary) / f"{name}.zip"
        with zipfile.ZipFile(archive, "w") as output:
            for member, contents in members:
                output.writestr(member, contents)
        try:
            package.validate(archive)
        except ValueError:
            print(f"EXPECTED_FAILURE gd-audio package-control={name}")
            return
    raise AssertionError(f"package negative control unexpectedly passed: {name}")


def main() -> None:
    expected = [(name, b"fixture") for name in package.expected_files()]
    rejected("traversal", expected + [("../escape", b"bad")])
    rejected("undeclared", expected + [("tests.gd", b"bad")])
    rejected("missing", expected[:-1])
    duplicate = expected + [(expected[0][0], b"duplicate")]
    rejected("duplicate", duplicate)
    symlink = zipfile.ZipInfo(expected[0][0])
    symlink.create_system = 3
    symlink.external_attr = (stat.S_IFLNK | 0o777) << 16
    rejected("symlink", [(symlink, b"target")] + expected[1:])
    with tempfile.TemporaryDirectory(prefix="gd-audio-package-restored-") as temporary:
        archive = Path(temporary) / "restored.zip"
        package.build(archive)
    print("ASSERTIONS gd-audio package_test 6")
    print("PASS gd-audio package_test")


if __name__ == "__main__":
    main()
