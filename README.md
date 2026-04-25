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

- `configure_music(config: Dictionary)`
- `get_music_volume_percent() -> float`
- `set_music_volume_percent(value: float)`
- `stop_music()`
- signal `music_volume_changed(volume_percent: float)`

## Scope Boundary

- In scope: generic looping music playback, configurable start offsets, fade in/out, and persisted volume.
- Out of scope: game-specific asset selection, route policy, or UI composition.
