extends Node3D
class_name LevelManager

@export var tile_scene: PackedScene

const TILE_SIZE := 2.0
const DIRECTIONS: Array[Vector2i] = [
	Vector2i.UP,
	Vector2i.DOWN,
	Vector2i.LEFT,
	Vector2i.RIGHT
]

var tiles: Dictionary = {}

func _ready():
	randomize()
	create_start_tile()

# ===== СТАРТОВЫЙ ТАЙЛ =====

func create_start_tile():
	var tile: Tile = create_tile(Vector2i.ZERO)

	tile.exits.clear()
	for d: Vector2i in DIRECTIONS:
		tile.exits.append(d)

	tile.redraw_exit_markers()

# ===== СОЗДАНИЕ ТАЙЛА =====

func create_tile(pos: Vector2i) -> Tile:
	if tiles.has(pos):
		return tiles[pos] as Tile

	var tile := tile_scene.instantiate() as Tile
	add_child(tile)

	tile.grid_pos = pos
	tile.position = Vector3(pos.x * TILE_SIZE, 0, pos.y * TILE_SIZE)

	tile.exit_clicked.connect(_on_exit_clicked)

	tiles[pos] = tile
	return tile

# ===== КЛИК =====

func _on_tile_clicked(tile: Tile):
	generate_neighbors(tile)

# ===== ГЕНЕРАЦИЯ СОСЕДЕЙ =====

func generate_neighbors(tile: Tile):
	for dir: Vector2i in tile.exits:
		var new_pos: Vector2i = tile.grid_pos + dir

		if tiles.has(new_pos):
			continue

		var allowed := true

		for d: Vector2i in DIRECTIONS:
			var check_pos: Vector2i = new_pos + d

			if not tiles.has(check_pos):
				continue

			var neighbor: Tile = tiles[check_pos] as Tile

			# если сосед ждёт вход, а мы его не даём — запрет
			if neighbor.exits.has(-d) and d != -dir:
				continue

			if not neighbor.exits.has(-d) and d == -dir:
				allowed = false
				break

		if not allowed:
			continue

		var new_tile: Tile = create_tile(new_pos)

		new_tile.exits.clear()
		new_tile.exits.append(-dir) # вход обязателен

		for d: Vector2i in DIRECTIONS:
			if d == -dir:
				continue

			var neighbor_pos: Vector2i = new_pos + d

			if tiles.has(neighbor_pos):
				var neighbor: Tile = tiles[neighbor_pos] as Tile
				if neighbor.exits.has(-d):
					new_tile.exits.append(d)
			else:
				if randf() < 0.4:
					new_tile.exits.append(d)

		new_tile.redraw_exit_markers()
		
func _on_exit_clicked(tile: Tile, dir: Vector2i):
	var new_pos: Vector2i = tile.grid_pos + dir

	if tiles.has(new_pos):
		return

	var new_tile := create_tile(new_pos)

	new_tile.exits.clear()
	new_tile.exits.append(-dir) # вход обязателен

	for d: Vector2i in DIRECTIONS:
		if d == -dir:
			continue

		var neighbor_pos: Vector2i = new_tile.grid_pos + d

		# 🔒 если сосед существует — ТОЛЬКО если он уже имеет выход
		if tiles.has(neighbor_pos):
			var neighbor: Tile = tiles[neighbor_pos] as Tile
			if neighbor.exits.has(-d):
				new_tile.exits.append(d)
		else:
			# 🎲 если соседа нет — можно рандомно
			if randf() < 0.4:
				new_tile.exits.append(d)

	new_tile.redraw_exit_markers()
