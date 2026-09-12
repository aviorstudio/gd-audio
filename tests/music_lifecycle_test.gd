extends SceneTree

const GdAudioAutoload = preload("res://addon/autoload.gd")
var _assertion_count := 0
var _ready_count := 0
var _failure_paths: Array[String] = []
var _stopped_count := 0

func _init() -> void:
	_run.call_deferred()

func _run() -> void:
	var audio := GdAudioAutoload.new()
	root.add_child(audio)
	audio.music_ready.connect(func() -> void: _ready_count += 1)
	audio.music_load_failed.connect(func(path: String) -> void: _failure_paths.append(path))
	audio.music_stopped.connect(func() -> void: _stopped_count += 1)

	var missing_path := "res://tests/does-not-exist.wav"
	_assert(not audio.configure_music({"settings_path": "", "stream_path": missing_path, "autoplay": true}), "failed load should not become ready")
	_assert(_failure_paths == [missing_path], "failed load should identify its configured path once")
	_assert(not audio._player.playing, "failed load must remain stopped")

	var stream_path := "user://gd_audio_music_lifecycle_test.tres"
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = 8000
	stream.data = PackedByteArray()
	stream.data.resize(32000)
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_end = 16000
	_assert(ResourceSaver.save(stream, stream_path) == OK, "audio fixture should save")
	_assert(audio.configure_music({
		"settings_path": "",
		"stream_path": stream_path,
		"autoplay": false,
		"fade_in_duration_seconds": 0.0,
		"fade_out_duration_seconds": 0.10,
	}), "valid stream should become ready")
	_assert(_ready_count == 1, "ready should settle exactly once after successful synchronous load")
	_assert(not audio._player.playing, "autoplay=false must remain stopped")
	_assert(not audio._music_active, "autoplay=false must not arm implicit continuation")

	_assert(audio.start_music(), "explicit start should succeed when ready")
	_assert(audio._player.playing, "explicit start should begin playback")
	var generation_before_restart: int = audio._transition_generation
	_assert(audio.start_music(), "repeated explicit start should succeed")
	_assert(audio._transition_generation == generation_before_restart + 1 and audio._player.playing, "repeated start should execute one fresh restart")

	audio.stop_music()
	_assert(not audio._player.playing, "default stop should preserve instant public timing")
	_assert(not audio._music_active, "instant stop should clear active playback intent")
	_assert(_stopped_count == 1, "instant stop should settle once")
	_assert(audio.start_music(), "start after instant stop should succeed")
	var fade_started_at := Time.get_ticks_msec()
	audio.stop_music(true)
	_assert(audio._is_fading_out and _stopped_count == 1, "faded stop should not settle immediately")
	await create_timer(0.04).timeout
	_assert(audio._is_fading_out and _stopped_count == 1, "faded stop should honor the configured duration")
	audio.stop_music(true)
	await create_timer(0.09).timeout
	var fade_elapsed := Time.get_ticks_msec() - fade_started_at
	_assert(not audio._player.playing, "faded stop should stop after its tween")
	_assert(fade_elapsed >= 70 and fade_elapsed <= 500, "100ms fade settlement should stay within the 70-500ms scheduling window (elapsed %dms)" % fade_elapsed)
	_assert(_stopped_count == 2, "repeated faded stop should settle exactly once")

	_assert(audio.start_music(), "start before cancellation check should succeed")
	audio.stop_music(true)
	await create_timer(0.03).timeout
	_assert(audio.start_music(), "start during stop fade should cancel stale completion and restart")
	await create_timer(0.11).timeout
	_assert(_stopped_count == 2, "canceled stop completion must not emit a stale settlement")
	_assert(audio._music_active, "start during fade should retain active playback intent")

	_assert(audio.configure_music({"settings_path": "", "stream_path": stream_path, "autoplay": false}), "reconfigure should remain ready")
	_assert(not audio._player.playing, "reconfigure with autoplay=false should stop prior playback")
	_assert(not audio._music_active, "reconfigure with autoplay=false should clear prior playback intent")
	audio.queue_free()
	await process_frame

	print("ASSERTIONS gd-audio music_lifecycle_test %d" % _assertion_count)
	print("PASS gd-audio music_lifecycle_test")
	quit()

func _assert(condition: bool, message: String) -> void:
	_assertion_count += 1
	if not condition:
		push_error(message)
		quit(1)
