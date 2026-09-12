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
import zipfile

HERE = Path(__file__).resolve().parent
SPEC = importlib.util.spec_from_file_location("gd_audio_package", HERE / "package.py")
assert SPEC and SPEC.loader
package = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(package)
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
    project.joinpath("runtime_smoke.gd").write_text(textwrap.dedent("""
        extends Node

        func _ready() -> void:
            var audio = get_node_or_null("/root/GdAudio")
            if audio == null:
                push_error("packaged GdAudio autoload was not installed")
                get_tree().quit(1)
                return
            audio.configure_music({"settings_path": "", "stream_path": "", "autoplay": false})
            if audio._player.playing:
                push_error("autoplay=false started packaged music")
                get_tree().quit(1)
                return
            print("ASSERTIONS gd-audio package_runtime_smoke 2")
            print("PASS gd-audio package_runtime_smoke")
            if OS.has_feature("web"):
                var label = Label.new()
                label.text = "PASS gd-audio packaged web smoke\\nautoplay=false remained stopped"
                label.position = Vector2(24, 24)
                label.add_theme_font_size_override("font_size", 24)
                add_child(label)
                return
            get_tree().quit()
    """).strip() + "\n", encoding="utf-8")
    project.joinpath("runtime_smoke.tscn").write_text(textwrap.dedent("""
        [gd_scene load_steps=2 format=3]

        [ext_resource path="res://runtime_smoke.gd" type="Script" id="1"]

        [node name="RuntimeSmoke" type="Node"]
        script = ExtResource("1")
    """).strip() + "\n", encoding="utf-8")
    project.joinpath("consumer_runtime_smoke.gd").write_text(textwrap.dedent("""
        extends Node

        func _ready() -> void:
            var consumer = get_node_or_null("/root/GdAudio")
            if consumer == null or consumer.get_script() == null or consumer.get_script().resource_path != "res://consumer.gd":
                push_error("consumer-owned GdAudio autoload was replaced or removed")
                get_tree().quit(1)
                return
            print("ASSERTIONS gd-audio consumer_autoload_smoke 1")
            print("PASS gd-audio consumer_autoload_smoke")
            get_tree().quit()
    """).strip() + "\n", encoding="utf-8")
    project.joinpath("consumer_runtime_smoke.tscn").write_text(textwrap.dedent("""
        [gd_scene load_steps=2 format=3]

        [ext_resource path="res://consumer_runtime_smoke.gd" type="Script" id="1"]

        [node name="ConsumerRuntimeSmoke" type="Node"]
        script = ExtResource("1")
    """).strip() + "\n", encoding="utf-8")
    project.joinpath("disable_smoke.gd").write_text(textwrap.dedent(f"""
        @tool
        extends SceneTree

        func _init() -> void:
            _disable_when_ready.call_deferred()

        func _disable_when_ready() -> void:
            var plugin: Node = null
            for _frame in range(600):
                plugin = _find_plugin(root)
                if plugin != null:
                    break
                await process_frame
            if plugin == null:
                push_error("enabled gd-audio editor plugin instance was not found")
                quit(1)
                return
            for _frame in range(180):
                await process_frame
            plugin._disable_plugin()
            ProjectSettings.set_setting("editor_plugins/enabled", PackedStringArray())
            ProjectSettings.save()
            print("ASSERTIONS gd-audio package_disable_smoke 1")
            print("PASS gd-audio package_disable_smoke")
            for _frame in range(30):
                await process_frame
            quit()

        func _find_plugin(node: Node) -> Node:
            var script = node.get_script()
            if script != null and str(script.resource_path) == "res://addons/{ADDON_DIR}/plugin.gd":
                return node
            for child in node.get_children():
                var found = _find_plugin(child)
                if found != null:
                    return found
            return null
    """).strip() + "\n", encoding="utf-8")
    project.joinpath("noop_editor_smoke.gd").write_text(textwrap.dedent("""
        @tool
        extends SceneTree

        var _held_plugin_script: Script

        func _init() -> void:
            _finish.call_deferred()

        func _finish() -> void:
            for _frame in range(300):
                await process_frame
            _held_plugin_script = load("res://addons/@aviorstudio_gd-audio/plugin.gd")
            print("PASS gd-audio godot_472_editor_script_control")
            quit()
    """).strip() + "\n", encoding="utf-8")
    project.joinpath("export_presets.cfg").write_text(textwrap.dedent("""
        [preset.0]

        name="Web"
        platform="Web"
        runnable=true
        advanced_options=false
        dedicated_server=false
        custom_features=""
        export_filter="all_resources"
        include_filter=""
        exclude_filter=""
        export_path="build/web/index.html"
        patches=PackedStringArray()
        encryption_include_filters=""
        encryption_exclude_filters=""
        seed=0
        encrypt_pck=false
        encrypt_directory=false
        script_export_mode=2

        [preset.0.options]

        variant/extensions_support=false
        variant/thread_support=false
        vram_texture_compression/for_desktop=true
        vram_texture_compression/for_mobile=false
        html/canvas_resize_policy=2
        html/focus_canvas_on_start=true
        progressive_web_app/enabled=false
    """).strip() + "\n", encoding="utf-8")


def install(archive: Path, project: Path) -> Path:
    package.validate(archive)
    addon = project / "addons" / ADDON_DIR
    addon.mkdir(parents=True)
    with zipfile.ZipFile(archive) as source:
        source.extractall(addon)
    package_files = set(package.expected_files())
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
    package.validate(archive)
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
        web_build = project / "build" / "web"
        web_build.mkdir(parents=True)
        run([args.godot, "--headless", "--audio-driver", "Dummy", "--path", str(project), "--export-release", "Web", str(web_build / "index.html")], timeout=120)
        for required in ("index.html", "index.js", "index.wasm", "index.pck"):
            if not web_build.joinpath(required).is_file():
                raise RuntimeError(f"web export omitted {required}")
        if args.web_output:
            output = args.web_output.resolve()
            shutil.rmtree(output, ignore_errors=True)
            shutil.copytree(web_build, output)
        print("PASS gd-audio package_web_export_smoke")
        control_output, control_errors = run(editor + ["--script", "res://noop_editor_smoke.gd"], godot_472_control=True)
        if "PASS gd-audio godot_472_editor_script_control" not in control_output or not control_errors:
            raise RuntimeError("Godot 4.7.2 editor-script shutdown control did not reproduce its narrow error allowlist")
        print("ALLOWLIST_CONTROL gd-audio godot=4.7.2 headless-editor-script-shutdown")
        run(editor + ["--script", "res://disable_smoke.gd"], allowed_errors=control_errors, godot_472_control=True)
        assert_setting(project, "GdAudio=", False)
        assert_setting(project, "plugin_owns_autoload", False)
        run(editor + ["--quit-after", "120"])
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
