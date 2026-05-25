extends Node

signal music_volume_changed(volume_percent: float)
signal sfx_volume_changed(volume_percent: float)

const DEFAULT_MUSIC_CONFIG := {
	"stream_path": "",
	"tracks": [],
	"settings_path": "user://gd_audio.cfg",
	"settings_section": "music",
	"settings_key": "volume_percent",
	"default_volume_percent": 70.0,
	"start_offset_seconds": 0.0,
	"fade_in_duration_seconds": 0.0,
	"fade_out_duration_seconds": 0.0,
	"autoplay": true,
	"bus": "Master",
}
const DEFAULT_SFX_CONFIG := {
	"samples": {},
	"settings_path": "user://gd_audio.cfg",
	"settings_section": "sfx",
	"settings_key": "volume_percent",
	"default_volume_percent": 70.0,
	"default_volume_db": 0.0,
	"pool_size": 8,
	"bus": "Master",
}
const MIN_VOLUME_DB: float = -80.0

var _player: AudioStreamPlayer = null
var _fade_tween: Tween = null
var _is_fading_out: bool = false
var _music_config: Dictionary = DEFAULT_MUSIC_CONFIG.duplicate(true)
var _music_volume_percent: float = float(DEFAULT_MUSIC_CONFIG.default_volume_percent)
var _configured: bool = false
var _tracks: Array = []
var _current_track_index: int = 0

var _sfx_config: Dictionary = DEFAULT_SFX_CONFIG.duplicate(true)
var _sfx_streams: Dictionary = {}
var _sfx_volumes_db: Dictionary = {}
var _sfx_players: Array[AudioStreamPlayer] = []
var _sfx_next_player_index: int = 0
var _sfx_volume_percent: float = float(DEFAULT_SFX_CONFIG.default_volume_percent)
var _sfx_configured: bool = false

func _ready() -> void:
	_player = AudioStreamPlayer.new()
	_player.name = "MusicPlayer"
	_player.finished.connect(_on_player_finished)
	add_child(_player)
	set_process(false)

func configure_music(config: Dictionary) -> void:
	_music_config = DEFAULT_MUSIC_CONFIG.duplicate(true)
	for key in config.keys():
		_music_config[key] = config[key]
	_configured = true
	_load_settings()
	_resolve_tracks()
	_current_track_index = 0
	_configure_current_track_stream()
	_apply_bus()
	_apply_volume(true)
	if bool(_music_config.get("autoplay", true)):
		_restart_music()
	else:
		_refresh_music_process_state()

func get_music_volume_percent() -> float:
	return _music_volume_percent

func set_music_volume_percent(value: float) -> void:
	_music_volume_percent = clampf(value, 0.0, 100.0)
	_save_settings()
	if _is_fading_out:
		music_volume_changed.emit(_music_volume_percent)
		return
	_apply_volume()
	music_volume_changed.emit(_music_volume_percent)

func stop_music() -> void:
	if _fade_tween != null:
		_fade_tween.kill()
		_fade_tween = null
	_is_fading_out = false
	if _player:
		_player.stop()
	_refresh_music_process_state()

func _process(_delta: float) -> void:
	if not _configured or _player == null or _player.stream == null or not _player.playing or _is_fading_out:
		return
	var fade_out_duration: float = float(_music_config.get("fade_out_duration_seconds", 0.0))
	if fade_out_duration <= 0.0:
		return
	var stream_length: float = _player.stream.get_length()
	if stream_length <= 0.0:
		return
	var start_offset: float = _get_current_track_start_offset()
	var fade_start: float = maxf(stream_length - fade_out_duration, start_offset)
	if _player.get_playback_position() >= fade_start:
		_fade_out_and_advance()

func _refresh_music_process_state() -> void:
	var should_process: bool = false
	if _configured and _player != null and _player.stream != null and _player.playing and not _is_fading_out:
		should_process = float(_music_config.get("fade_out_duration_seconds", 0.0)) > 0.0
	set_process(should_process)

func _resolve_tracks() -> void:
	_tracks.clear()
	var configured_tracks: Variant = _music_config.get("tracks", [])
	if configured_tracks is Array and (configured_tracks as Array).size() > 0:
		for entry in (configured_tracks as Array):
			var resolved: Dictionary = _normalize_track_entry(entry)
			if not resolved.is_empty():
				_tracks.append(resolved)
	if _tracks.is_empty():
		var fallback: Dictionary = _normalize_track_entry({
			"stream_path": _music_config.get("stream_path", ""),
			"start_offset_seconds": _music_config.get("start_offset_seconds", 0.0),
		})
		if not fallback.is_empty():
			_tracks.append(fallback)

func _normalize_track_entry(entry: Variant) -> Dictionary:
	if not (entry is Dictionary):
		return {}
	var entry_dict: Dictionary = entry
	var stream_path: String = str(entry_dict.get("stream_path", "")).strip_edges()
	if stream_path.is_empty():
		return {}
	var stream: AudioStream = load(stream_path) as AudioStream
	if stream == null:
		push_warning("Failed to load music stream: %s" % stream_path)
		return {}
	var start_offset: float = maxf(float(entry_dict.get("start_offset_seconds", 0.0)), 0.0)
	return {
		"stream": stream,
		"start_offset_seconds": start_offset,
	}

func _get_current_track() -> Dictionary:
	if _tracks.is_empty():
		return {}
	if _current_track_index < 0 or _current_track_index >= _tracks.size():
		_current_track_index = 0
	return _tracks[_current_track_index]

func _get_current_track_start_offset() -> float:
	var track: Dictionary = _get_current_track()
	if track.is_empty():
		return 0.0
	return float(track.get("start_offset_seconds", 0.0))

func _configure_current_track_stream() -> void:
	if _player == null:
		return
	var track: Dictionary = _get_current_track()
	if track.is_empty():
		_player.stream = null
		return
	_player.stream = track.get("stream")

func _apply_bus() -> void:
	if _player == null:
		return
	_player.bus = str(_music_config.get("bus", "Master"))

func _apply_volume(immediate_silence: bool = false) -> void:
	if _player == null:
		return
	if _fade_tween != null:
		_fade_tween.kill()
		_fade_tween = null
	_is_fading_out = false
	if immediate_silence:
		_player.volume_db = MIN_VOLUME_DB
		return
	_player.volume_db = _resolve_target_volume_db()

func _resolve_target_volume_db() -> float:
	if _music_volume_percent <= 0.0:
		return MIN_VOLUME_DB
	return linear_to_db(_music_volume_percent / 100.0)

func _restart_music() -> void:
	if _player == null or _player.stream == null:
		return
	if _fade_tween != null:
		_fade_tween.kill()
		_fade_tween = null
	_is_fading_out = false
	_player.stop()
	var start_offset: float = _get_current_track_start_offset()
	_player.play(start_offset)
	_fade_in_to_target_volume()
	_refresh_music_process_state()

func _fade_in_to_target_volume() -> void:
	if _player == null:
		return
	var fade_in_duration: float = maxf(float(_music_config.get("fade_in_duration_seconds", 0.0)), 0.0)
	var target_db: float = _resolve_target_volume_db()
	if fade_in_duration <= 0.0:
		_player.volume_db = target_db
		return
	_player.volume_db = MIN_VOLUME_DB
	_fade_tween = create_tween()
	_fade_tween.set_trans(Tween.TRANS_SINE)
	_fade_tween.set_ease(Tween.EASE_OUT)
	_fade_tween.tween_property(_player, "volume_db", target_db, fade_in_duration)

func _fade_out_and_advance() -> void:
	if _player == null or _is_fading_out:
		return
	var fade_out_duration: float = maxf(float(_music_config.get("fade_out_duration_seconds", 0.0)), 0.0)
	if fade_out_duration <= 0.0:
		_advance_and_play()
		return
	_is_fading_out = true
	_refresh_music_process_state()
	if _fade_tween != null:
		_fade_tween.kill()
		_fade_tween = null
	_fade_tween = create_tween()
	_fade_tween.set_trans(Tween.TRANS_SINE)
	_fade_tween.set_ease(Tween.EASE_IN)
	_fade_tween.tween_property(_player, "volume_db", MIN_VOLUME_DB, fade_out_duration)
	_fade_tween.finished.connect(func() -> void:
		_advance_and_play()
	)

func _advance_and_play() -> void:
	if _tracks.is_empty():
		return
	_current_track_index = (_current_track_index + 1) % _tracks.size()
	_configure_current_track_stream()
	_restart_music()

func _on_player_finished() -> void:
	if not _configured or _is_fading_out:
		return
	if bool(_music_config.get("autoplay", true)):
		_advance_and_play()
	else:
		_refresh_music_process_state()

func _load_settings() -> void:
	var settings_path: String = str(_music_config.get("settings_path", "")).strip_edges()
	if settings_path.is_empty():
		_music_volume_percent = clampf(float(_music_config.get("default_volume_percent", 70.0)), 0.0, 100.0)
		return
	var config := ConfigFile.new()
	if config.load(settings_path) != OK:
		_music_volume_percent = clampf(float(_music_config.get("default_volume_percent", 70.0)), 0.0, 100.0)
		return
	var section: String = str(_music_config.get("settings_section", "music"))
	var key: String = str(_music_config.get("settings_key", "volume_percent"))
	var fallback: float = float(_music_config.get("default_volume_percent", 70.0))
	_music_volume_percent = clampf(float(config.get_value(section, key, fallback)), 0.0, 100.0)

func _save_settings() -> void:
	var settings_path: String = str(_music_config.get("settings_path", "")).strip_edges()
	if settings_path.is_empty():
		return
	var config := ConfigFile.new()
	config.load(settings_path)
	var section: String = str(_music_config.get("settings_section", "music"))
	var key: String = str(_music_config.get("settings_key", "volume_percent"))
	config.set_value(section, key, _music_volume_percent)
	config.save(settings_path)

func configure_sfx(config: Dictionary) -> void:
	_sfx_config = DEFAULT_SFX_CONFIG.duplicate(true)
	for key in config.keys():
		_sfx_config[key] = config[key]
	_sfx_configured = true
	_sfx_load_settings()
	_sfx_rebuild_pool()
	_sfx_load_samples()

func play_sfx(sample_name: String) -> bool:
	if not _sfx_configured:
		return false
	if not _sfx_streams.has(sample_name):
		return false
	var player: AudioStreamPlayer = _sfx_take_player()
	if player == null:
		return false
	player.stream = _sfx_streams[sample_name]
	var sample_db: float = float(_sfx_volumes_db.get(sample_name, _sfx_config.get("default_volume_db", 0.0)))
	player.volume_db = sample_db + _sfx_percent_to_db_offset(_sfx_volume_percent)
	player.play()
	return true

func get_sfx_volume_percent() -> float:
	return _sfx_volume_percent

func set_sfx_volume_percent(value: float) -> void:
	var clamped: float = clampf(value, 0.0, 100.0)
	if is_equal_approx(clamped, _sfx_volume_percent):
		return
	_sfx_volume_percent = clamped
	_sfx_save_settings()
	sfx_volume_changed.emit(clamped)

func _sfx_rebuild_pool() -> void:
	for existing in _sfx_players:
		if existing and is_instance_valid(existing):
			existing.queue_free()
	_sfx_players.clear()
	_sfx_next_player_index = 0
	var pool_size: int = int(_sfx_config.get("pool_size", 8))
	var bus_name: String = str(_sfx_config.get("bus", "Master"))
	for _i in range(pool_size):
		var player: AudioStreamPlayer = AudioStreamPlayer.new()
		player.bus = bus_name
		add_child(player)
		_sfx_players.append(player)

func _sfx_load_samples() -> void:
	_sfx_streams.clear()
	_sfx_volumes_db.clear()
	var samples: Variant = _sfx_config.get("samples", {})
	if not (samples is Dictionary):
		return
	var default_db: float = float(_sfx_config.get("default_volume_db", 0.0))
	for sample_name: Variant in (samples as Dictionary).keys():
		var entry: Variant = (samples as Dictionary)[sample_name]
		var path: String = ""
		var volume_db: float = default_db
		if entry is String:
			path = entry
		elif entry is Dictionary:
			path = str((entry as Dictionary).get("path", ""))
			volume_db = float((entry as Dictionary).get("volume_db", default_db))
		if path.is_empty():
			continue
		var stream: AudioStream = load(path) as AudioStream
		if stream == null:
			push_warning("gd-audio: failed to load sfx sample '%s' from %s" % [sample_name, path])
			continue
		_sfx_streams[sample_name] = stream
		_sfx_volumes_db[sample_name] = volume_db

func _sfx_take_player() -> AudioStreamPlayer:
	if _sfx_players.is_empty():
		return null
	for _i in range(_sfx_players.size()):
		var candidate: AudioStreamPlayer = _sfx_players[_sfx_next_player_index]
		_sfx_next_player_index = (_sfx_next_player_index + 1) % _sfx_players.size()
		if candidate and is_instance_valid(candidate) and not candidate.playing:
			return candidate
	var fallback: AudioStreamPlayer = _sfx_players[_sfx_next_player_index]
	_sfx_next_player_index = (_sfx_next_player_index + 1) % _sfx_players.size()
	return fallback

func _sfx_percent_to_db_offset(percent: float) -> float:
	if percent <= 0.0:
		return MIN_VOLUME_DB
	return linear_to_db(clampf(percent, 0.0, 100.0) / 100.0)

func _sfx_load_settings() -> void:
	var settings_path: String = str(_sfx_config.get("settings_path", "")).strip_edges()
	var fallback: float = float(_sfx_config.get("default_volume_percent", 70.0))
	if settings_path.is_empty():
		_sfx_volume_percent = clampf(fallback, 0.0, 100.0)
		return
	var config := ConfigFile.new()
	if config.load(settings_path) != OK:
		_sfx_volume_percent = clampf(fallback, 0.0, 100.0)
		return
	var section: String = str(_sfx_config.get("settings_section", "sfx"))
	var key: String = str(_sfx_config.get("settings_key", "volume_percent"))
	_sfx_volume_percent = clampf(float(config.get_value(section, key, fallback)), 0.0, 100.0)

func _sfx_save_settings() -> void:
	var settings_path: String = str(_sfx_config.get("settings_path", "")).strip_edges()
	if settings_path.is_empty():
		return
	var config := ConfigFile.new()
	config.load(settings_path)
	var section: String = str(_sfx_config.get("settings_section", "sfx"))
	var key: String = str(_sfx_config.get("settings_key", "volume_percent"))
	config.set_value(section, key, _sfx_volume_percent)
	config.save(settings_path)
