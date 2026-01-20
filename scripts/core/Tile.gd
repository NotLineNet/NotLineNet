extends Node3D
class_name Tile

signal exit_clicked(tile: Tile, dir: Vector2i)

var grid_pos: Vector2i
var exits: Array[Vector2i] = []

const EXIT_MARKER_SIZE := Vector3(0.3, 0.3, 0.3)
const EXIT_OFFSET := 0.9

func redraw_exit_markers():
	for child in get_children():
		if child.name.begins_with("ExitMarker"):
			child.queue_free()

	var idx := 0
	for dir: Vector2i in exits:
		var marker := Area3D.new()
		marker.name = "ExitMarker_%d" % idx
		idx += 1

		var mesh := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = EXIT_MARKER_SIZE
		mesh.mesh = box

		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.2, 1.0, 0.2)
		mesh.material_override = mat

		marker.add_child(mesh)

		var shape := CollisionShape3D.new()
		shape.shape = BoxShape3D.new()
		marker.add_child(shape)

		marker.position = Vector3(
			dir.x * EXIT_OFFSET,
			0.3,
			dir.y * EXIT_OFFSET
		)

		marker.input_event.connect(
			func(_cam, event, _pos, _norm, _idx):
				if event is InputEventMouseButton \
				and event.pressed \
				and event.button_index == MOUSE_BUTTON_LEFT:
					exit_clicked.emit(self, dir)
		)

		add_child(marker)
