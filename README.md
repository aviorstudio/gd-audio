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
	GdAudio.configure_music({
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

- `configure_music`: load and optionally autoplay looping music.
- `set_music_volume_percent` / `get_music_volume_percent`: manage persisted music volume.
- `stop_music`: fade out and stop the active music stream.
- `configure_sfx`: register one-shot samples and configure a player pool.
- `play_sfx`: play a named sound effect.
- `music_volume_changed` and `sfx_volume_changed` signals.

## Notes

- Works in Godot 4.x native and web exports, subject to Godot audio format support.
- No project settings are required beyond enabling the plugin autoload.
- Keep game-specific music selection and settings UI in your game code.

## Repository Layout

- `addon/`: Godot plugin source packaged for GDAM and manual installation.
- `addon/plugin.cfg`: plugin name, version, description, and entry script.
- `addon/src/`: reusable GDScript modules.
- `tests/`: Godot test project/scripts for addon behavior.
- `.github/workflows/ci.yml`: validates package shape and runs tests.
- `.github/workflows/release.yml`: creates GitHub release ZIPs and publishes to GDAM.

## Versioning And Releases

The version in `addon/plugin.cfg` is the addon package version. Releases are created from `main` with the manual release workflow and plain semver tags like `v0.0.1`; the workflow verifies `plugin.cfg`, builds `@aviorstudio_gd-audio.zip`, and publishes `@aviorstudio/gd-audio` to GDAM.

## Testing

Run locally with:

```sh
./tests/test.sh
```

CI runs the same test script when available.

## License

MIT
