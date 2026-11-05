#!/usr/bin/env python3
"""Run the owned engine failure corpus against the shared assertion runner."""
import contextlib
import importlib.util
import io
import os
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("shared_godot_assertions", Path(os.environ["TOOLS_ROOT"]) / "helpers/godot-test.py")
native = importlib.util.module_from_spec(spec)
spec.loader.exec_module(native)

class AudioRunnerControls(unittest.TestCase):
    def test_failure_corpus_and_restored_pass(self):
        fixtures = ROOT / "tests/runner_fixtures"
        for name in ["runtime_error", "assertion_overwrite", "parse_failure", "timeout"]:
            program = next((fixtures / name).glob("*_test.gd"))
            with self.subTest(control=name), self.assertRaises((ValueError, OSError)):
                native.run(os.environ["GODOT_BIN"], ROOT, program,
                           "PASS gd-audio " + program.stem, 1 if name == "timeout" else 10,
                           arguments=["--audio-driver", "Dummy"], environment=os.environ.copy(),
                           assertions_regex=r"^ASSERTIONS gd-audio " + program.stem + r" ([1-9][0-9]*)$")
        program = fixtures / "pass/reachable_test.gd"
        native.run(os.environ["GODOT_BIN"], ROOT, program, "PASS gd-audio reachable_test", 30,
                   arguments=["--audio-driver", "Dummy"], environment=os.environ.copy(),
                   assertions_regex=r"^ASSERTIONS gd-audio reachable_test ([1-9][0-9]*)$")

    def test_missing_suite_fails(self):
        import tempfile
        with tempfile.TemporaryDirectory() as directory, self.assertRaises(ValueError):
            native.suite(os.environ["GODOT_BIN"], ROOT, Path(directory), "PASS gd-audio", 30, os.environ.copy())

if __name__ == "__main__":
    unittest.main(verbosity=2)
