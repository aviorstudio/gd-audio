<!-- Generated from private documentation source. Do not edit directly. Source SHA256: b33ba7708db04f85abf49899ba5a6dfcfa31d7d3bc7c0cf958b018da94df56af -->

# gd-audio

Add looping music, saved volume settings, fades, and pooled sound effects to Godot 4 games.

Use this addon when you want one simple `GdAudio` autoload for common game audio tasks.

## Installation

### Via gdam

`gdam install @aviorstudio/gd-audio`

### Manual

Copy `addon/` into `res://addons/@aviorstudio_gd-audio/` and enable the plugin.

## Quick Start

The plugin installs an autoload named `GdAudio`.

```gdscript
func _ready() -> void:
	var ready := GdAudio.configure_music({
		"stream_path": "res://assets/music/theme.mp3",
		"settings_path": "user://audio_settings.cfg",
		"settings_section": "music",
		"settings_key": "volume_percent",
		"default_volume_percent": 70.0,
		"fade_in_duration_seconds": 2.0,
		"fade_out_duration_seconds": 2.0,
		"autoplay": true,
		"bus": "Master",
	})
```

`configure_music` loads synchronously and returns whether at least one track is ready. It emits `music_load_failed(stream_path)` for each configured path that fails and emits `music_ready` once after a successful configuration. Set `autoplay` to `false` when startup must be explicit, then call `GdAudio.start_music()`. Calling `start_music()` while playing restarts the current track from its configured offset.

`GdAudio.stop_music()` remains an instant stop. Call `GdAudio.stop_music(true)` to use `fade_out_duration_seconds`; repeated stop calls share one completion and `music_stopped` emits exactly once. Starting or reconfiguring during a pending stop cancels its stale completion.

## Sound Effects

Configure a small sample registry, then play effects by name.

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
	"pool_size": 8,
	"bus": "Master",
})

GdAudio.play_sfx("click")
```

## What You Get

- `configure_music`: synchronously load music, report readiness/failures, and optionally autoplay.
- `start_music`: explicitly start or restart the current ready track.
- `set_music_volume_percent` / `get_music_volume_percent`: manage persisted music volume.
- `stop_music`: stop instantly by default or honor the configured fade when passed `true`.
- `configure_sfx`: register one-shot samples and configure a player pool.
- `play_sfx`: play a named sound effect.
- `music_ready`, `music_load_failed`, `music_stopped`, `music_volume_changed`, and `sfx_volume_changed` signals.

## Notes

- Supported and release-tested on Godot 4.7.2 native Linux and web exports, subject to Godot audio format and browser autoplay support.
- No project settings are required beyond enabling the plugin autoload.
- Keep game-specific music selection and settings UI in your game code.


## License

See `LICENSE`.

## Contributor checks

Install [mise](https://mise.jdx.dev/), then use the pinned cookbook entrypoint:

```sh
make setup
make build
make test
```

`mise.toml` pins SDK versions and reviewed engine/template checksums. `cookbook.toml` declares native package inputs, fixture exports and test groups; `Makefile` loads the exact shared cookbook revision. `make build` packages and validates the closed addon payload and exports its installed Web fixture. Tests use those existing artifacts and never build or install dependencies.

Use `make test:lint`, `make test:unit`, `make test:integration` and `make test:security` for individual groups. The unit suite retains the native assertion reach and failure controls; integration covers installed editor lifecycle and consumer autoload ownership. `make fmt` formats native GDScript, `make clean` removes declared generated outputs, and `make help` describes the supported commands. Build and test receipts remain in `.artifacts/verification`.
