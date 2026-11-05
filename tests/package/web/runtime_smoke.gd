extends Node

func _ready() -> void:
    var audio = get_node_or_null("/root/GdAudio")
    if audio == null:
        push_error("packaged GdAudio autoload was not installed")
        get_tree().quit(1)
        return
    var ready = audio.configure_music({"settings_path": "", "stream_path": "res://fixture_audio.tres", "autoplay": false})
    if not ready:
        push_error("packaged music fixture did not become ready")
        get_tree().quit(1)
        return
    if audio._player.playing:
        push_error("autoplay=false started packaged music")
        get_tree().quit(1)
        return
    print("ASSERTIONS gd-audio package_runtime_smoke 3")
    print("PASS gd-audio package_runtime_smoke")
    if OS.has_feature("web"):
        var label = Label.new()
        label.text = "PASS gd-audio packaged web smoke\nautoplay=false remained stopped"
        label.position = Vector2(24, 24)
        label.add_theme_font_size_override("font_size", 24)
        add_child(label)
        return
    get_tree().quit()
