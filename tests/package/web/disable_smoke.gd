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
    if script != null and str(script.resource_path) == "res://addons/@aviorstudio_gd-audio/plugin.gd":
        return node
    for child in node.get_children():
        var found = _find_plugin(child)
        if found != null:
            return found
    return null
