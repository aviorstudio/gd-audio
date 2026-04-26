# gd-audio

Game-agnostic audio helpers for Godot 4 projects.

## Installation

### Via gdpm
`gdpm add @aviorstudio/gd-audio`

### Manual
Copy this directory into `addons/@aviorstudio_gd-audio/` and enable the plugin.

## Usage

The addon provides an autoload named `GdAudio`.

```gdscript
GdAudio.configure_music({
	"stream_path": "res://assets/music/theme.mp3",
	"settings_path": "user://audio_settings.cfg",
	"settings_section": "music",
	"settings_key": "volume_percent",
	"default_volume_percent": 70.0,
	"start_offset_seconds": 0.0,
	"fade_in_duration_seconds": 3.0,
	"fade_out_duration_seconds": 3.0,
	"autoplay": true,
	"bus": "Master",
})
```

## API

### Music

- `configure_music(config: Dictionary)`
- `get_music_volume_percent() -> float`
- `set_music_volume_percent(value: float)`
- `stop_music()`
- signal `music_volume_changed(volume_percent: float)`

### SFX

```gdscript
GdAudio.configure_sfx({
	"samples": {
		"click": "res://assets/sfx/click.ogg",
		"hit": {
			"path": "res://assets/sfx/hit.wav",
			"volume_db": -3.0,
		},
	},
	"settings_path": "user://audio_settings.cfg",
	"settings_section": "sfx",
	"settings_key": "volume_percent",
	"default_volume_percent": 70.0,
	"default_volume_db": 0.0,
	"pool_size": 8,
	"bus": "Master",
})

GdAudio.play_sfx("click")
```

- `configure_sfx(config: Dictionary)` — `samples` accepts either a path string or `{path, volume_db}` per name. Reconfiguring rebuilds the pool and sample registry.
- `play_sfx(name: String)` — round-robins across a pool of `AudioStreamPlayer` nodes; ignores unknown sample names. Final volume is per-sample `volume_db` plus a master scalar derived from the persisted volume percent.
- `get_sfx_volume_percent() -> float`
- `set_sfx_volume_percent(value: float)`
- signal `sfx_volume_changed(volume_percent: float)`

## Scope Boundary

- In scope: generic looping music playback, configurable start offsets, fade in/out, persisted volume, pooled SFX one-shots with per-sample volume offsets and persisted master volume.
- Out of scope: game-specific asset selection, route policy, or UI composition.
