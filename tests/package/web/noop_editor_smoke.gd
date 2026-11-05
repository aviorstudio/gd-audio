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
