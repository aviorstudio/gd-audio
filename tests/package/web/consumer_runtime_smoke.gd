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
