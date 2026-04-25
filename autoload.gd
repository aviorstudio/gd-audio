extends Node

signal music_volume_changed(volume_percent: float)

const DEFAULT_MUSIC_CONFIG := {
	"stream_path": "",
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
const MIN_VOLUME_DB: float = -80.0

var _player: AudioStreamPlayer = null
var _fade_tween: Tween = null
var _is_fading_out: bool = false
var _music_config: Dictionary = DEFAULT_MUSIC_CONFIG.duplicate(true)
var _music_volume_percent: float = float(DEFAULT_MUSIC_CONFIG.default_volume_percent)
var _configured: bool = false

func _ready() -> void:
	_player = AudioStreamPlayer.new()
	_player.name = "MusicPlayer"
	_player.finished.connect(_on_player_finished)
	add_child(_player)
	set_process(true)

func configure_music(config: Dictionary) -> void:
	_music_config = DEFAULT_MUSIC_CONFIG.duplicate(true)
	for key in config.keys():
		_music_config[key] = config[key]
	_configured = true
	_load_settings()
	_configure_stream()
	_apply_bus()
	_apply_volume(true)
	if bool(_music_config.get("autoplay", true)):
		_restart_music()

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

func _process(_delta: float) -> void:
	if not _configured or _player == null or _player.stream == null or not _player.playing or _is_fading_out:
		return
	var fade_out_duration: float = float(_music_config.get("fade_out_duration_seconds", 0.0))
	if fade_out_duration <= 0.0:
		return
	var stream_length: float = _player.stream.get_length()
	if stream_length <= 0.0:
		return
	var start_offset: float = float(_music_config.get("start_offset_seconds", 0.0))
	var fade_start: float = maxf(stream_length - fade_out_duration, start_offset)
	if _player.get_playback_position() >= fade_start:
		_fade_out_and_restart()

func _configure_stream() -> void:
	if _player == null:
		return
	var stream_path: String = str(_music_config.get("stream_path", "")).strip_edges()
	if stream_path.is_empty():
		_player.stream = null
		return
	var stream: AudioStream = load(stream_path) as AudioStream
	if stream == null:
		push_warning("Failed to load music stream: %s" % stream_path)
		_player.stream = null
		return
	_player.stream = stream

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
	var start_offset: float = maxf(float(_music_config.get("start_offset_seconds", 0.0)), 0.0)
	_player.play(start_offset)
	_fade_in_to_target_volume()

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

func _fade_out_and_restart() -> void:
	if _player == null or _is_fading_out:
		return
	var fade_out_duration: float = maxf(float(_music_config.get("fade_out_duration_seconds", 0.0)), 0.0)
	if fade_out_duration <= 0.0:
		_restart_music()
		return
	_is_fading_out = true
	if _fade_tween != null:
		_fade_tween.kill()
		_fade_tween = null
	_fade_tween = create_tween()
	_fade_tween.set_trans(Tween.TRANS_SINE)
	_fade_tween.set_ease(Tween.EASE_IN)
	_fade_tween.tween_property(_player, "volume_db", MIN_VOLUME_DB, fade_out_duration)
	_fade_tween.finished.connect(func() -> void:
		_restart_music()
	)

func _on_player_finished() -> void:
	if not _configured or _is_fading_out:
		return
	if bool(_music_config.get("autoplay", true)):
		_restart_music()

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
