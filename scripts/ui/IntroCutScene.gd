extends Node3D
class_name IntroCutSceneController

signal intro_animation_finished

@onready var animation_player: AnimationPlayer = $AnimationPlayer
@onready var camera_root: Node3D = $CameraRoot
@onready var camera_pivot: Node3D = $CameraRoot/CameraPivot
@onready var camera: Camera3D = $CameraRoot/CameraPivot/Camera3D

func play_intro() -> void:
	reset_to_start()
	ensure_camera_current()
	if not animation_player:
		intro_animation_finished.emit()
		return
	if not animation_player.animation_finished.is_connected(_on_animation_finished):
		animation_player.animation_finished.connect(_on_animation_finished)
	animation_player.play("intro_camera_out")

func reset_to_start() -> void:
	if animation_player and animation_player.has_animation("RESET"):
		animation_player.play("RESET")
		animation_player.seek(0.0, true)
		animation_player.stop()

func ensure_camera_current() -> void:
	if camera:
		camera.current = true

func get_camera_state() -> Dictionary:
	var pivot_transform := camera_pivot.global_transform if camera_pivot else Transform3D.IDENTITY
	var root_position := camera_root.global_position if camera_root else Vector3.ZERO
	var fov_value := camera.fov if camera else 60.0
	return {
		"root_position": root_position,
		"pivot_transform": pivot_transform,
		"fov": fov_value
	}

func _on_animation_finished(anim_name: StringName) -> void:
	if anim_name != "intro_camera_out":
		return
	intro_animation_finished.emit()
