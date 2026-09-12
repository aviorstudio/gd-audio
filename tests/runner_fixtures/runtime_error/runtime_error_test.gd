extends SceneTree

func _init() -> void:
	push_error("intentional runner runtime-error control")
	print("ASSERTIONS gd-audio runtime_error_test 1")
	print("PASS gd-audio runtime_error_test")
	quit()
