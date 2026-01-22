extends Node3D

@export var drag_speed: float = 0.05
@export var zoom_speed: float = 1.0
@export var min_zoom: float = 2.0
@export var max_zoom: float = 50.0

var dragging: bool = false
var last_mouse_pos: Vector2
var camera: Camera3D

func _ready():
	camera = get_node_or_null("Camera3D")
	# Добавляем в группу для удобного поиска
	add_to_group("camera_root")

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
	
	elif event is InputEventMouseButton and camera:
		# Обработка колесика мыши для зума
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			# Приближение (уменьшаем size)
			camera.size = clamp(camera.size - zoom_speed, min_zoom, max_zoom)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			# Отдаление (увеличиваем size)
			camera.size = clamp(camera.size + zoom_speed, min_zoom, max_zoom)
