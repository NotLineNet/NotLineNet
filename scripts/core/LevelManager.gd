extends Node3D
class_name LevelManager

@export var tile_scene: PackedScene

const TILE_SIZE := 2.0
const DIRECTIONS := [
	Vector2i.UP,
	Vector2i.DOWN,
	Vector2i.LEFT,
	Vector2i.RIGHT
]

var tiles: Dictionary = {}

func _ready():
	randomize()
	create_start_tile()

func create_start_tile():
	var tile := create_tile(Vector2i.ZERO)

	tile.exits.clear()

	var dirs := DIRECTIONS.duplicate()
	dirs.shuffle()

	var count := randi_range(1, 4)
	for i in count:
		tile.exits.append(dirs[i])

	tile.redraw_exit_markers()S

func create_tile(pos: Vector2i) -> Tile:
	if tiles.has(pos):
		return tiles[pos]

	var tile := tile_scene.instantiate() as Tile
	add_child(tile)

	tile.grid_pos = pos
	tile.position = Vector3(pos.x * TILE_SIZE, 0, pos.y * TILE_SIZE)
	tile.clicked.connect(_on_tile_clicked)

	tiles[pos] = tile
	return tile

func _on_tile_clicked(tile: Tile):
	generate_neighbors(tile)

func generate_neighbors(tile: Tile):
	for dir in tile.exits:
		var new_pos := tile.grid_pos + dir
		if tiles.has(new_pos):
			continue

		var new_tile := create_tile(new_pos)

		# вход обратно
		new_tile.exits = [-dir]

		# случайные дополнительные выходы
		for d in DIRECTIONS:
			if d == -dir:
				continue
			if randf() < 0.4:
				new_tile.exits.append(d)

		new_tile.redraw_exit_markers()
