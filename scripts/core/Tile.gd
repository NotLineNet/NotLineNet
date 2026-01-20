extends Node3D
class_name Tile

signal clicked(tile: Tile)

var grid_pos: Vector2i
var exits: Array[Vector2i] = []

const EXIT_MARKER_SIZE := Vector3(0.3, 0.3, 0.3)
const EXIT_OFFSET := 0.9

func _ready():
	$Area3D.input_event.connect(_on_area_input)

func _on_area_input(_camera, event, _pos, _normal, _shape_idx):
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		clicked.emit(self)

func redraw_exit_markers():
	for child in get_children():
		if child.name.begins_with("ExitMarker"):
			child.queue_free()

	var i := 0
	for dir in exits:
		var m := MeshInstance3D.new()
		m.name = "ExitMarker_%d" % i
		i += 1

		var mesh := BoxMesh.new()
		mesh.size = EXIT_MARKER_SIZE
		m.mesh = mesh

		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color.GREEN
		m.material_override = mat

		m.position = Vector3(dir.x * EXIT_OFFSET, 0.3, dir.y * EXIT_OFFSET)
		add_child(m)
