extends Node3D

@export var drag_speed: float = 0.05

var dragging: bool = false
var last_mouse_pos: Vector2

func _unhandled_input(event):
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT:
		if event.pressed:
			dragging = true
			last_mouse_pos = event.position
		else:
			dragging = false

	elif event is InputEventMouseMotion and dragging:
		var delta: Vector2 = event.position - last_mouse_pos
		last_mouse_pos = event.position

		global_position.x -= delta.x * drag_speed
		global_position.z -= delta.y * drag_speed
