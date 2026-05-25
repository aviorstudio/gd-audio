extends SceneTree

const GdAudioAutoload = preload("res://autoload.gd")

func _init() -> void:
	var audio := GdAudioAutoload.new()
	root.add_child(audio)
	audio.configure_music({
		"settings_path": "",
		"stream_path": "",
		"autoplay": false,
		"default_volume_percent": 42.0,
	})
	_assert(is_equal_approx(audio.get_music_volume_percent(), 42.0), "music default volume should apply")
	audio.set_music_volume_percent(120.0)
	_assert(is_equal_approx(audio.get_music_volume_percent(), 100.0), "music volume should clamp high")
	audio.configure_sfx({
		"settings_path": "",
		"samples": {},
		"default_volume_percent": 33.0,
		"pool_size": 2,
	})
	_assert(is_equal_approx(audio.get_sfx_volume_percent(), 33.0), "sfx default volume should apply")
	_assert(not audio.play_sfx("missing"), "unknown sfx sample should return false")
	audio.set_sfx_volume_percent(-5.0)
	_assert(is_equal_approx(audio.get_sfx_volume_percent(), 0.0), "sfx volume should clamp low")
	audio.queue_free()
	print("PASS gd-audio audio_autoload_test")
	quit()

func _assert(condition: bool, message: String) -> void:
	if not condition:
		push_error(message)
		quit(1)
