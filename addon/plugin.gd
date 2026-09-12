@tool
extends EditorPlugin

const AUTOLOAD_NAME := "GdAudio"
const AUTOLOAD_SCRIPT := "autoload.gd"
const OWNERSHIP_SETTING := "gd_audio/plugin_owns_autoload"

var _added_autoload: bool = false

func _enter_tree() -> void:
	_ensure_autoload()

func _enable_plugin() -> void:
	_ensure_autoload()

func _disable_plugin() -> void:
	var key: String = "autoload/" + AUTOLOAD_NAME
	if bool(ProjectSettings.get_setting(OWNERSHIP_SETTING, false)) and ProjectSettings.has_setting(key) and _autoload_setting_matches(str(ProjectSettings.get_setting(key))):
		ProjectSettings.set_setting(OWNERSHIP_SETTING, null)
		remove_autoload_singleton(AUTOLOAD_NAME)
	elif bool(ProjectSettings.get_setting(OWNERSHIP_SETTING, false)):
		ProjectSettings.set_setting(OWNERSHIP_SETTING, null)
		ProjectSettings.save()
	_added_autoload = false

func _ensure_autoload() -> void:
	var key: String = "autoload/" + AUTOLOAD_NAME
	if ProjectSettings.has_setting(key):
		_added_autoload = bool(ProjectSettings.get_setting(OWNERSHIP_SETTING, false)) and _autoload_setting_matches(str(ProjectSettings.get_setting(key)))
		return
	ProjectSettings.set_setting(OWNERSHIP_SETTING, true)
	add_autoload_singleton(AUTOLOAD_NAME, _autoload_path())
	# Keep the portable path in project.godot. A freshly interrupted editor may
	# not have flushed its UID cache yet, but the enabled autoload must still be
	# usable on the next start.
	ProjectSettings.set_setting(key, "*" + _autoload_path())
	ProjectSettings.save()
	_added_autoload = true

func _autoload_path() -> String:
	return str(get_script().resource_path).get_base_dir().path_join(AUTOLOAD_SCRIPT)

func _autoload_setting_matches(value: String) -> bool:
	var path := value.trim_prefix("*")
	if path.begins_with("uid://"):
		path = ResourceUID.get_id_path(ResourceUID.text_to_id(path))
	return path == _autoload_path()
