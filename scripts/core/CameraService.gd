extends Node
class_name CameraService

# Placeholder camera coordinator to decouple camera control from GameManager/CameraDrag later.
# Currently no-op; legacy camera flow remains unchanged.

func focus_on_player(_player) -> void:
	pass


func apply_zoom_preset(_level: int, _interpolate := true) -> void:
	pass


func set_follow_enabled(_enabled: bool) -> void:
	pass


func set_input_enabled(_enabled: bool) -> void:
	pass


func center_on_tile(_tile) -> void:
	pass
