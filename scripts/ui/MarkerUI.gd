extends Control
class_name MarkerUI

const NodeLocator = preload("res://scripts/core/NodeLocator.gd")

@export var chest_button_scene: PackedScene = preload("res://scenes/ui/ClaimChestBtn.tscn")

var camera: Camera3D
var chest_buttons: Dictionary = {}  # Node3D -> Control

func _ready():
	add_to_group("marker_ui")
	_ensure_camera()

func _process(_delta: float) -> void:
	_ensure_camera()
	if not camera:
		return
	var viewport_rect := _get_viewport_rect()
	var to_remove: Array = []
	for marker in chest_buttons.keys():
		var button := chest_buttons[marker] as Control
		if not _is_marker_valid(marker):
			_queue_button_free(button)
			to_remove.append(marker)
			continue
		_update_button_position(marker, button, viewport_rect)
	for marker in to_remove:
		chest_buttons.erase(marker)

func register_chest_marker(marker: Node3D, on_pressed: Callable = Callable()) -> Control:
	if not marker or not is_instance_valid(marker):
		return null
	if chest_buttons.has(marker):
		return chest_buttons[marker] as Control
	if not chest_button_scene:
		return null
	var instance := chest_button_scene.instantiate() as Control
	if not instance:
		return null
	_prepare_button_control(instance)
	add_child(instance)
	var button_node := instance.get_node_or_null("ButtonClaim") as Button
	if button_node and on_pressed.is_valid():
		if not button_node.is_connected("pressed", on_pressed):
			button_node.pressed.connect(on_pressed)
	chest_buttons[marker] = instance
	_update_button_position(marker, instance, _get_viewport_rect())
	return instance

func unregister_marker(marker: Node3D) -> void:
	if not chest_buttons.has(marker):
		return
	var button := chest_buttons[marker] as Control
	_queue_button_free(button)
	chest_buttons.erase(marker)

func _update_button_position(marker: Node3D, button: Control, viewport_rect: Rect2) -> void:
	if not marker or not button:
		return
	if viewport_rect.size == Vector2.ZERO:
		button.visible = false
		return
	var world_pos := marker.global_transform.origin
	if camera.is_position_behind(world_pos):
		button.visible = false
		return
	var screen_pos: Vector2 = camera.unproject_position(world_pos)
	button.visible = viewport_rect.has_point(screen_pos)
	if not button.visible:
		return
	button.global_position = screen_pos - button.pivot_offset

func _prepare_button_control(button: Control) -> void:
	if not button:
		return
	button.size = button.get_combined_minimum_size()
	button.pivot_offset = button.size * 0.5

func _queue_button_free(button: Control) -> void:
	if button and button.is_inside_tree():
		button.queue_free()

func _is_marker_valid(marker: Node3D) -> bool:
	return marker and is_instance_valid(marker) and marker.is_inside_tree()

func _get_viewport_rect() -> Rect2:
	var viewport := get_viewport()
	if viewport:
		return viewport.get_visible_rect()
	return Rect2()

func _ensure_camera():
	if camera and is_instance_valid(camera):
		return
	var camera_root := NodeLocator.camera_root(self)
	if camera_root and camera_root.camera:
		camera = camera_root.camera
