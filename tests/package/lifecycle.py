#!/usr/bin/env python3
"""Install packaged bytes into clean projects and exercise editor lifecycle."""

from __future__ import annotations

import argparse
import hashlib
import importlib.util
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import textwrap
import time
import os
import zipfile

ROOT = Path(__file__).resolve().parents[2]
TOOLS = Path(os.environ["TOOLS_ROOT"])
SPEC = importlib.util.spec_from_file_location("shared_addon_package", TOOLS / "helpers/addon-package.py")
package = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(package)
MANIFEST = ROOT / "package-manifest.txt"
FIXTURE = Path(__file__).resolve().parent / "web"

ADDON_DIR = "@aviorstudio_gd-audio"
PLUGIN = f"res://addons/{ADDON_DIR}/plugin.cfg"


GODOT_472_EDITOR_SCRIPT_ERROR = re.compile(
    r"ERROR: (?:\d+ resources? still in use at exit \(run with --verbose for details\)\."
    r"|\d+ RID allocations of type '(?:N16RendererViewport8ViewportE|PN13RendererDummy14TextureStorage12DummyTextureE|N17RendererSceneCull8ScenarioE|PN18TextServerAdvanced22ShapedTextDataAdvancedE|PN18TextServerAdvanced12FontAdvancedE)' were leaked at exit\.)"
)


def error_lines(output: str) -> list[str]:
    return [line.strip() for line in output.splitlines() if line.strip().startswith(("ERROR:", "SCRIPT ERROR:", "FAIL:"))]


def run(command: list[str], timeout: int = 45, allowed_errors: set[str] | None = None, godot_472_control: bool = False) -> tuple[str, set[str]]:
    completed = subprocess.run(command, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=timeout)
    print(completed.stdout, end="")
    if completed.returncode:
        raise RuntimeError(f"command exited {completed.returncode}: {' '.join(command)}")
    errors = set(error_lines(completed.stdout))
    unexpected = errors - (allowed_errors or set())
    if godot_472_control:
        unexpected = {line for line in unexpected if not GODOT_472_EDITOR_SCRIPT_ERROR.fullmatch(line)}
    if unexpected:
        raise RuntimeError(f"unexpected Godot error {sorted(unexpected)}: {' '.join(command)}")
    return completed.stdout, errors


def start_editor_and_interrupt(command: list[str], project: Path, timeout: int = 45) -> str:
    process = subprocess.Popen(command, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    deadline = time.monotonic() + timeout
    try:
        while time.monotonic() < deadline:
            settings = project.joinpath("project.godot").read_text(encoding="utf-8")
            if "GdAudio=" in settings and "plugin_owns_autoload=true" in settings:
                process.kill()
                output, _ = process.communicate(timeout=5)
                print(output, end="")
                if re.search(r"(^|\s)(ERROR:|SCRIPT ERROR:|FAIL:)", output):
                    raise RuntimeError("unexpected Godot error while enabling packaged plugin")
                print("INTERRUPTED gd-audio editor-restart-control")
                return output
            if process.poll() is not None:
                output, _ = process.communicate()
                print(output, end="")
                raise RuntimeError(f"editor exited before plugin enable: {process.returncode}")
            time.sleep(0.1)
        raise TimeoutError("editor did not persist plugin state before timeout")
    finally:
        if process.poll() is None:
            process.kill()
            process.communicate()


def tree_digest(root: Path) -> str:
    digest = hashlib.sha256()
    for path in sorted(item for item in root.rglob("*") if item.is_file()):
        digest.update(path.relative_to(root).as_posix().encode())
        digest.update(b"\0")
        digest.update(path.read_bytes())
        digest.update(b"\0")
    return digest.hexdigest()


def write_project(project: Path, consumer_owned: bool = False) -> None:
    autoload = "\n[autoload]\nGdAudio=\"*res://consumer.gd\"\n" if consumer_owned else ""
    main_scene = "res://consumer_runtime_smoke.tscn" if consumer_owned else "res://runtime_smoke.tscn"
    project.joinpath("project.godot").write_text(textwrap.dedent(f"""
        ; generated package smoke fixture
        config_version=5

        [application]
        config/name="gd-audio package smoke"
        run/main_scene="{main_scene}"

        [editor_plugins]
        enabled=PackedStringArray("{PLUGIN}")
        {autoload}
        [rendering]
        renderer/rendering_method="gl_compatibility"
    """).strip() + "\n", encoding="utf-8")
    project.joinpath("consumer.gd").write_text("extends Node\n", encoding="utf-8")


def write_scripts(project: Path) -> None:
    for path in FIXTURE.iterdir():
        if path.is_file() and path.name != "project.godot":
            shutil.copyfile(path, project / path.name)


def install(archive: Path, project: Path) -> Path:
    package.verify(archive, MANIFEST, source=ROOT / "addon")
    addon = project / "addons" / ADDON_DIR
    addon.mkdir(parents=True)
    with zipfile.ZipFile(archive) as source:
        source.extractall(addon)
    package_files = set(package.manifest_files(MANIFEST))
    installed = {path.relative_to(addon).as_posix() for path in addon.rglob("*") if path.is_file()}
    if installed != package_files:
        raise RuntimeError(f"installed tree mismatch: {sorted(installed)}")
    return addon


def assert_setting(project: Path, needle: str, present: bool) -> None:
    text = project.joinpath("project.godot").read_text(encoding="utf-8")
    if (needle in text) != present:
        raise RuntimeError(f"project setting assertion failed for {needle!r}, present={present}\n{text}")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("archive", type=Path)
    parser.add_argument("--godot", default="godot")
    parser.add_argument("--web-output", type=Path)
    args = parser.parse_args()
    archive = args.archive.resolve()
    package.verify(archive, MANIFEST, source=ROOT / "addon")
    with tempfile.TemporaryDirectory(prefix="gd-audio-installed-") as temporary:
        project = Path(temporary)
        write_project(project)
        addon = install(archive, project)
        write_scripts(project)
        editor = [args.godot, "--headless", "--editor", "--audio-driver", "Dummy", "--path", str(project)]
        start_editor_and_interrupt(editor, project)
        assert_setting(project, "GdAudio=", True)
        assert_setting(project, "plugin_owns_autoload=true", True)
        start_editor_and_interrupt(editor, project)
        run([args.godot, "--headless", "--audio-driver", "Dummy", "--path", str(project)])
        web_build = (args.web_output or ROOT / "dist/web-smoke").resolve()
        for required in ("index.html", "index.js", "index.wasm", "index.pck"):
            if not web_build.joinpath(required).is_file():
                raise RuntimeError(f"existing Web fixture omitted {required}; run make build")
        print("PASS gd-audio package_web_export_smoke")
        control_output, control_errors = run(editor + ["--script", "res://noop_editor_smoke.gd"], godot_472_control=True)
        if "PASS gd-audio godot_472_editor_script_control" not in control_output or not control_errors:
            raise RuntimeError("Godot 4.7.2 editor-script shutdown control did not reproduce its narrow error allowlist")
        print("ALLOWLIST_CONTROL gd-audio godot=4.7.2 headless-editor-script-shutdown")
        run(editor + ["--script", "res://disable_smoke.gd"], allowed_errors=control_errors, godot_472_control=True)
        assert_setting(project, "GdAudio=", False)
        assert_setting(project, "plugin_owns_autoload", False)
        run(editor + ["--quit-after", "120"])
        package.verify(archive, MANIFEST, source=ROOT / "addon", installed=addon)
        print(f"INSTALLED_TREE_SHA256={tree_digest(addon)}")

    with tempfile.TemporaryDirectory(prefix="gd-audio-consumer-owned-") as temporary:
        project = Path(temporary)
        write_project(project, consumer_owned=True)
        install(archive, project)
        write_scripts(project)
        editor = [args.godot, "--headless", "--editor", "--audio-driver", "Dummy", "--path", str(project)]
        run(editor + ["--quit-after", "120"])
        _, control_errors = run(editor + ["--script", "res://noop_editor_smoke.gd"], godot_472_control=True)
        run(editor + ["--script", "res://disable_smoke.gd"], allowed_errors=control_errors, godot_472_control=True)
        assert_setting(project, "GdAudio=", True)
        assert_setting(project, "plugin_owns_autoload", False)
        run([args.godot, "--headless", "--audio-driver", "Dummy", "--path", str(project)])
        run(editor + ["--quit-after", "120"])
    print("ASSERTIONS gd-audio package_smoke 13")
    print("PASS gd-audio package_smoke")


if __name__ == "__main__":
    main()
