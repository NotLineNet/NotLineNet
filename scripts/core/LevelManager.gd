extends Node3D
class_name LevelManager

const GameConfig = preload("res://scripts/core/GameConfig.gd")
const Directions = preload("res://scripts/core/Directions.gd")

@export var tile_scene: PackedScene
@export var player_scene: PackedScene
@export var circle_radius: int = 9
@export var green_circle_radius: int = 5
@export var path_line_color: Color = Color(1, 0.75, 0.25, 0.9)
@export var path_line_highlight_color: Color = Color(0.2, 1, 0.2, 0.9)
@export var path_line_thickness: float = 0.25
@export var path_line_height: float = 0.12
@export var loop_connection_chance: float = 0.28
@export var max_deadend_ratio: float = 0.18

const TILE_SIZE := GameConfig.TILE_SIZE
const DIRECTIONS: Array[Vector2i] = Directions.ALL

var tiles: Dictionary = {}
var green_tile_positions: Array[Vector2i] = []
var red_tile_pos: Vector2i
var path_debug_root: Node3D
var path_debug_lines_built: bool = false
var path_line_nodes: Dictionary = {}
var highlighted_path_lines: Array[MeshInstance3D] = []
var path_debug_enabled: bool = false
var tracked_active_player: Player
var _player_moved_callable: Callable
var _active_player_changed_callable: Callable

func _ready():
	randomize()
	_player_moved_callable = Callable(self, "_on_player_moved_to_tile")
	_active_player_changed_callable = Callable(self, "_on_active_player_changed")
	_init_path_debug_root()
	add_to_group("level_manager")
	create_grid()
	_connect_game_manager_signals()

# ===== СОЗДАНИЕ СЕТКИ =====

func create_grid():
	_clear_path_debug_lines()
	_clear_tiles()
	red_tile_pos = Vector2i.ZERO
	var red_tile := create_tile(red_tile_pos)
	red_tile.set_color(Color.RED)

	var resolved_radius: int = max(1, circle_radius)
	var main_circle: Dictionary = _build_circle_layer(red_tile_pos, resolved_radius)
	var green_candidates: Array[Vector2i] = _pick_green_tile_positions(main_circle, red_tile_pos, 3)
	if green_candidates.size() == 0:
		var fallback_pos := red_tile_pos + Vector2i(resolved_radius, 0)
		create_tile(fallback_pos)
		green_candidates = [fallback_pos]

	green_tile_positions = green_candidates.duplicate()
	var green_exit_targets: Dictionary = {}
	for green_pos in green_tile_positions:
		green_exit_targets[green_pos] = _determine_green_exit_direction(green_pos)
		var green_tile: Tile = tiles.get(green_pos, null) as Tile
		if green_tile:
			green_tile.set_color(Color.GREEN)
		_build_circle_layer(green_pos, green_circle_radius)

	var connection_map: Dictionary = _finalize_connections(green_exit_targets)
	_apply_connection_map(connection_map)

	for tile in tiles.values():
		(tile as Tile).redraw_exit_markers()

	var visible_positions := green_tile_positions.duplicate()
	visible_positions.append(red_tile_pos)
	hide_all_tiles_except(visible_positions)

	create_players()
	var gm := _get_game_manager()
	if gm and gm.has_method("game_loaded_full"):
		gm.call_deferred("game_loaded_full")

func _init_path_debug_root():
	if path_debug_root:
		return
	path_debug_root = Node3D.new()
	path_debug_root.name = "PathLines"
	add_child(path_debug_root)
	path_debug_root.visible = false

func _grid_to_world(pos: Vector2) -> Vector3:
	return Vector3(pos.x * TILE_SIZE, 0, pos.y * TILE_SIZE)

func _clear_path_debug_lines():
	if not path_debug_root:
		return
	_clear_highlighted_path()
	for child in path_debug_root.get_children():
		child.queue_free()
	path_line_nodes.clear()
	path_debug_lines_built = false

func _create_path_line_material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.flags_transparent = true
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return material

func build_path_debug_lines():
	if not path_debug_root:
		return
	_clear_path_debug_lines()
	for pos_key in tiles.keys():
		var pos: Vector2i = pos_key as Vector2i
		var tile := tiles[pos] as Tile
		for dir in tile.exits:
			if dir.x < 0 or (dir.x == 0 and dir.y < 0):
				continue
			var neighbor_pos: Vector2i = pos + dir
			if not tiles.has(neighbor_pos):
				continue
			var line := MeshInstance3D.new()
			var mesh := BoxMesh.new()
			var width := path_line_thickness
			var length := TILE_SIZE * 0.9
			var size := Vector3.ZERO

			if dir.x != 0:
				size.x = length
			else:
				size.x = width

			if dir.y != 0:
				size.z = length
			else:
				size.z = width

			size.y = path_line_height
			mesh.size = size
			line.mesh = mesh
			line.material_override = _create_path_line_material(path_line_color)
			var midpoint := Vector2(
				float(pos.x + neighbor_pos.x) / 2.0,
				float(pos.y + neighbor_pos.y) / 2.0
			)
			var center := _grid_to_world(midpoint)
			center.y = path_line_height * 0.5
			line.position = center
			path_debug_root.add_child(line)
			var forward_key := _line_key(pos, neighbor_pos)
			var backward_key := _line_key(neighbor_pos, pos)
			path_line_nodes[forward_key] = line
			path_line_nodes[backward_key] = line
	path_debug_lines_built = true
	if path_debug_enabled:
		_update_path_highlight_to_active_player()

func set_path_debug_visible(enabled: bool):
	if not path_debug_root:
		return
	path_debug_enabled = enabled

	if enabled:
		if not path_debug_lines_built:
			build_path_debug_lines()
		else:
			_update_path_highlight_to_active_player()
	else:
		_clear_highlighted_path()

	path_debug_root.visible = enabled

func _line_key(from_pos: Vector2i, to_pos: Vector2i) -> String:
	return "%d,%d->%d,%d" % [from_pos.x, from_pos.y, to_pos.x, to_pos.y]

func _update_path_highlight_to_active_player():
	if not path_debug_enabled or not path_debug_lines_built:
		return

	var gm := _get_game_manager()
	if not gm or not gm.active_player or not gm.active_player.current_tile:
		_clear_highlighted_path()
		return

	var start_pos: Vector2i = gm.active_player.current_tile.grid_pos
	var path := _find_path_between_positions(start_pos, red_tile_pos)
	_clear_highlighted_path()
	if path.size() > 1:
		_apply_highlight_for_path(path)

func _apply_highlight_for_path(path: Array[Vector2i]) -> void:
	for i in range(path.size() - 1):
		var key := _line_key(path[i], path[i + 1])
		var line := path_line_nodes.get(key, null) as MeshInstance3D
		if line:
			line.material_override = _create_path_line_material(path_line_highlight_color)
			highlighted_path_lines.append(line)

func _clear_highlighted_path():
	for line in highlighted_path_lines:
		if line and line.is_inside_tree():
			line.material_override = _create_path_line_material(path_line_color)
	highlighted_path_lines.clear()

func _find_path_between_positions(start_pos: Vector2i, target_pos: Vector2i) -> Array[Vector2i]:
	if start_pos == target_pos:
		return [start_pos] as Array[Vector2i]
	if not tiles.has(start_pos) or not tiles.has(target_pos):
		return [] as Array[Vector2i]

	var queue: Array[Vector2i] = [start_pos]
	var visited := {start_pos: true}
	var parent_map: Dictionary = {}

	while queue.size() > 0:
		var current_pos: Vector2i = queue.pop_front()
		var tile := tiles.get(current_pos, null) as Tile
		if not tile:
			continue

		for dir in tile.exits:
			var neighbor_pos: Vector2i = current_pos + dir
			if visited.has(neighbor_pos) or not tiles.has(neighbor_pos):
				continue
			parent_map[neighbor_pos] = current_pos
			if neighbor_pos == target_pos:
				return _reconstruct_path(parent_map, start_pos, target_pos)
			visited[neighbor_pos] = true
			queue.append(neighbor_pos)

	return [] as Array[Vector2i]

func _reconstruct_path(parent_map: Dictionary, start_pos: Vector2i, target_pos: Vector2i) -> Array[Vector2i]:
	var path: Array[Vector2i] = [target_pos]
	var current_pos: Vector2i = target_pos
	while current_pos != start_pos:
		if not parent_map.has(current_pos):
			return [] as Array[Vector2i]
		current_pos = parent_map[current_pos] as Vector2i
		path.insert(0, current_pos)
	return path

func _connect_game_manager_signals():
	var gm := _get_game_manager()
	if not gm:
		return

	if _active_player_changed_callable and not gm.is_connected("active_player_changed", _active_player_changed_callable):
		gm.connect("active_player_changed", _active_player_changed_callable)

	_track_active_player_for_highlight(gm.active_player)
	_update_path_highlight_to_active_player()

func _track_active_player_for_highlight(player: Player) -> void:
	if tracked_active_player == player:
		return

	_disconnect_tracked_player()
	if not player or not _player_moved_callable:
		return

	tracked_active_player = player
	if not player.is_connected("moved_to_tile", _player_moved_callable):
		player.connect("moved_to_tile", _player_moved_callable)

func _disconnect_tracked_player():
	if tracked_active_player and _player_moved_callable and tracked_active_player.is_connected("moved_to_tile", _player_moved_callable):
		tracked_active_player.disconnect("moved_to_tile", _player_moved_callable)
	tracked_active_player = null

func _on_active_player_changed(player: Player) -> void:
	_track_active_player_for_highlight(player)
	_update_path_highlight_to_active_player()

func _on_player_moved_to_tile(_tile: Tile) -> void:
	if not path_debug_enabled:
		return
	_update_path_highlight_to_active_player()

# ===== ПОСТРОЕНИЕ КРУГА =====
func _build_circle_layer(center: Vector2i, radius: int) -> Dictionary:
	var positions := []
	var boundary := []
	var tolerance := 0.6

	for dx in range(-radius, radius + 1):
		for dy in range(-radius, radius + 1):
			var offset := Vector2(dx, dy)
			var distance := offset.length()

			if distance <= radius + 0.5:
				var pos := center + Vector2i(dx, dy)
				create_tile(pos)
				positions.append(pos)

				if abs(distance - radius) <= tolerance:
					boundary.append(pos)

	return {
		"positions": positions,
		"boundary": boundary
	}

func _pick_green_tile_positions(circle_info: Dictionary, center: Vector2i, count: int) -> Array[Vector2i]:
	var boundary: Array[Vector2i] = []
	var raw_boundary := circle_info["boundary"] as Array
	if raw_boundary:
		for entry in raw_boundary:
			if entry is Vector2i:
				boundary.append(entry)

	if boundary.size() == 0:
		var raw_positions := circle_info["positions"] as Array
		if raw_positions:
			for entry in raw_positions:
				if entry is Vector2i:
					boundary.append(entry)

	if boundary.size() == 0:
		return []

	var selected: Array[Vector2i] = []
	var used := {}
	var start_angle := randf() * TAU

	for i in range(count):
		var target_angle := start_angle + TAU * (i / float(count))
		var best_pos: Vector2i = Vector2i.ZERO
		var best_found := false
		var best_diff := INF

		for entry in boundary:
			if not entry is Vector2i:
				continue
			var vector_pos: Vector2i = entry
			if used.has(vector_pos):
				continue
			if vector_pos == center:
				continue
			var offset: Vector2 = Vector2(vector_pos.x - center.x, vector_pos.y - center.y)
			var angle := atan2(offset.y, offset.x)
			if angle < 0:
				angle += TAU
			var diff := _angle_difference(angle, target_angle)
			if diff < best_diff:
				best_diff = diff
				best_pos = vector_pos
				best_found = true
		
		if not best_found:
			for entry in boundary:
				if not entry is Vector2i:
					continue
				var vector_pos: Vector2i = entry
				if not used.has(vector_pos):
					best_pos = vector_pos
					best_found = true
					break

		if best_found:
			selected.append(best_pos)
			used[best_pos] = true

	var fallback_index := 0
	while selected.size() < count and boundary.size() > 0:
		var candidate: Vector2i = boundary[fallback_index % boundary.size()]
		fallback_index += 1
		if not used.has(candidate):
			selected.append(candidate)
			used[candidate] = true
		else:
			selected.append(candidate)
		if fallback_index > count * boundary.size():
			break

	return selected

func _angle_difference(a: float, b: float) -> float:
	var diff := a - b
	while diff < -PI:
		diff += TAU
	while diff > PI:
		diff -= TAU
	return abs(diff)

func _clear_tiles() -> void:
	for tile in tiles.values():
		if tile:
			tile.queue_free()
	tiles.clear()

func _determine_green_exit_direction(green_pos: Vector2i) -> Vector2i:
	var direction: Vector2i = _choose_green_exit_direction(green_pos)
	if direction != Vector2i.ZERO:
		return direction

	var best_dir := Vector2i.ZERO
	var best_distance := INF
	for dir: Vector2i in DIRECTIONS:
		var neighbor_pos := green_pos + dir
		if not tiles.has(neighbor_pos):
			continue
		var distance := neighbor_pos.distance_to(red_tile_pos)
		if distance < best_distance:
			best_distance = distance
			best_dir = dir
	return best_dir

func _choose_green_exit_direction(pos: Vector2i) -> Vector2i:
	var best_dir := Vector2i.ZERO
	var best_distance := INF
	var found_best := false

	for dir: Vector2i in DIRECTIONS:
		var neighbor_pos: Vector2i = pos + dir
		if not tiles.has(neighbor_pos):
			continue
		var distance := neighbor_pos.distance_to(red_tile_pos)
		if distance < best_distance:
			best_distance = distance
			best_dir = dir
			found_best = true

	if found_best:
		return best_dir

	for dir: Vector2i in DIRECTIONS:
		var neighbor_pos: Vector2i = pos + dir
		if tiles.has(neighbor_pos):
			return dir

	return Vector2i.ZERO

func _finalize_connections(green_exit_targets: Dictionary) -> Dictionary:
	var neighbor_map: Dictionary = _build_neighbors_map()
	var connection_map: Dictionary = {}
	for pos_key in tiles.keys():
		connection_map[pos_key] = [] as Array[Vector2i]

	var queue: Array[Vector2i] = [red_tile_pos]
	var visited: Dictionary = {}
	visited[red_tile_pos] = true

	while queue.size() > 0:
		var current_pos: Vector2i = queue.pop_front()
		if _is_green_tile(current_pos) and current_pos != red_tile_pos:
			continue
		var candidate_dirs: Array[Vector2i] = (neighbor_map[current_pos] as Array[Vector2i]).duplicate()
		candidate_dirs.shuffle()

		for dir: Vector2i in candidate_dirs:
			var neighbor_pos: Vector2i = current_pos + dir
			if not tiles.has(neighbor_pos) or visited.has(neighbor_pos):
				continue
			if green_exit_targets.has(neighbor_pos):
				var required_dir: Vector2i = green_exit_targets[neighbor_pos] as Vector2i
				if -required_dir != dir:
					continue
			_add_connection(connection_map, current_pos, dir)
			visited[neighbor_pos] = true
			queue.append(neighbor_pos)

	for dir: Vector2i in DIRECTIONS:
		var neighbor_pos: Vector2i = red_tile_pos + dir
		if tiles.has(neighbor_pos):
			_add_connection(connection_map, red_tile_pos, dir)

	for pos_key in tiles.keys():
		if visited.has(pos_key):
			continue
		var neighbor_dirs: Array[Vector2i] = neighbor_map[pos_key] as Array[Vector2i]
		for dir: Vector2i in neighbor_dirs:
			var neighbor_pos: Vector2i = pos_key + dir
			if visited.has(neighbor_pos) and not _is_green_tile(neighbor_pos):
				_add_connection(connection_map, pos_key, dir)
				visited[pos_key] = true
				break

	_sprinkle_loops(connection_map, neighbor_map)
	_control_deadends(connection_map, neighbor_map)
	return connection_map

func _build_neighbors_map() -> Dictionary:
	var map: Dictionary = {}
	for pos_key in tiles.keys():
		var dirs: Array[Vector2i] = []
		for dir: Vector2i in DIRECTIONS:
			var neighbor_pos: Vector2i = pos_key + dir
			if tiles.has(neighbor_pos):
				dirs.append(dir)
		map[pos_key] = dirs
	return map

func _add_connection(connection_map: Dictionary, pos: Vector2i, dir: Vector2i) -> void:
	var neighbor_pos: Vector2i = pos + dir
	if not tiles.has(neighbor_pos):
		return
	if connection_map[pos].has(dir):
		return
	if connection_map[pos].size() >= 4 or connection_map[neighbor_pos].size() >= 4:
		return
	connection_map[pos].append(dir)
	if not connection_map[neighbor_pos].has(-dir):
		connection_map[neighbor_pos].append(-dir)

func _sprinkle_loops(connection_map: Dictionary, neighbor_map: Dictionary) -> void:
	for pos_key in tiles.keys():
		if _is_special_tile(pos_key):
			continue
		var candidate_dirs: Array[Vector2i] = (neighbor_map[pos_key] as Array[Vector2i]).duplicate()
		candidate_dirs.shuffle()
		for dir: Vector2i in candidate_dirs:
			var neighbor_pos: Vector2i = pos_key + dir
			if connection_map[pos_key].has(dir):
				continue
			if _is_green_tile(neighbor_pos):
				continue
			if connection_map[pos_key].size() >= 4 or connection_map[neighbor_pos].size() >= 4:
				continue
			if randf() < loop_connection_chance:
				_add_connection(connection_map, pos_key, dir)

func _control_deadends(connection_map: Dictionary, neighbor_map: Dictionary) -> void:
	var target: int = max(1, int(tiles.size() * max_deadend_ratio))
	var attempts := 0
	while _count_dead_ends(connection_map) > target and attempts < tiles.size() * 4:
		var dead_end := _find_dead_end(connection_map)
		var dead_connections: Array[Vector2i] = connection_map.get(dead_end, []) as Array[Vector2i]
		if dead_connections.size() != 1:
			break
		var candidate_dirs: Array[Vector2i] = (neighbor_map[dead_end] as Array[Vector2i]).duplicate()
		candidate_dirs.shuffle()
		for dir: Vector2i in candidate_dirs:
			var neighbor_pos: Vector2i = dead_end + dir
			if connection_map[dead_end].has(dir):
				continue
			if _is_green_tile(neighbor_pos):
				continue
			if connection_map[dead_end].size() >= 4 or connection_map[neighbor_pos].size() >= 4:
				continue
			_add_connection(connection_map, dead_end, dir)
			break
		attempts += 1

func _count_dead_ends(connection_map: Dictionary) -> int:
	var count := 0
	for pos_key in tiles.keys():
		if _is_special_tile(pos_key):
			continue
		if connection_map[pos_key].size() == 1:
			count += 1
	return count

func _find_dead_end(connection_map: Dictionary) -> Vector2i:
	var pool: Array[Vector2i] = []
	for pos_key in tiles.keys():
		if _is_special_tile(pos_key):
			continue
		if connection_map[pos_key].size() == 1:
			pool.append(pos_key)
	if pool.size() == 0:
		return Vector2i.ZERO
	pool.shuffle()
	return pool[0]

func _apply_connection_map(connection_map: Dictionary) -> void:
	for pos_key in tiles.keys():
		var tile := tiles[pos_key] as Tile
		tile.exits.clear()
		var dirs: Array[Vector2i] = connection_map.get(pos_key, []) as Array[Vector2i]
		for dir: Vector2i in dirs:
			if not tile.exits.has(dir):
				tile.exits.append(dir)

func _is_green_tile(pos: Vector2i) -> bool:
	return green_tile_positions.has(pos)

func _is_special_tile(pos: Vector2i) -> bool:
	return pos == red_tile_pos or _is_green_tile(pos)

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

# ===== УПРАВЛЕНИЕ ВИДИМОСТЬЮ ТАЙЛОВ =====

func hide_all_tiles_except(visible_positions: Array[Vector2i]):
	# Скрываем все тайлы
	for pos in tiles.keys():
		var tile: Tile = tiles[pos] as Tile
		tile.hide_tile()
	
	# Показываем только указанные тайлы
	for pos in visible_positions:
		if tiles.has(pos):
			var tile: Tile = tiles[pos] as Tile
			tile.show_tile()

# ===== ОБРАБОТКА КЛИКА =====

func _on_exit_clicked(tile: Tile, dir: Vector2i):
	# Проверяем наличие очков действий у игрока
	# Если нет очков (action_points <= 0), не показываем следующий тайл
	var gm: GameManager = _get_game_manager()
	if not gm:
		return

	var active_player: Player = gm.active_player
	if not active_player or active_player.action_points <= 0:
		return
	
	# Раскрываем следующий тайл в направлении клика
	var current_pos := tile.grid_pos
	var next_pos := current_pos + dir
	
	# Проверяем, существует ли следующий тайл
	if tiles.has(next_pos):
		var next_tile: Tile = tiles[next_pos] as Tile
		# Показываем тайл и его выходы
		next_tile.show_tile()

# ===== СОЗДАНИЕ ИГРОКА =====

func create_players():
	var gm: GameManager = _get_game_manager()
	var desired_count: int = 3
	if gm:
		desired_count = max(1, gm.total_players)

	if green_tile_positions.size() == 0:
		push_error("Не удалось найти зеленые тайлы для игроков")
		return

	var spawn_positions: Array[Vector2i] = green_tile_positions.duplicate()
	spawn_positions.shuffle()
	var spawn_count: int = min(desired_count, spawn_positions.size())
	if spawn_count == 0:
		push_error("Недостаточно зеленых тайлов для размещения игроков")
		return

	var player_root: Node3D = _ensure_player_root()
	for i in range(spawn_count):
		var player_instance: Player = _instantiate_player(player_root)
		if not player_instance:
			continue

		player_instance.level_manager = self
		if gm:
			gm.register_player(player_instance)

		var start_pos: Vector2i = spawn_positions.pop_back() as Vector2i
		var green_tile: Tile = tiles.get(start_pos, null) as Tile
		if not green_tile:
			push_error("Не удалось получить зеленый тайл для игрока")
			continue

		player_instance.initialize_on_tile(green_tile)
		green_tile.redraw_exit_markers()

func _instantiate_player(parent: Node3D) -> Player:
	if not player_scene:
		player_scene = preload("res://scenes/player/Player.tscn") as PackedScene
	var new_player := player_scene.instantiate() as Player
	if not new_player:
		push_error("Не удалось создать игрока")
		return null
	parent.add_child(new_player)
	return new_player

func _ensure_player_root() -> Node3D:
	var player_root := get_node_or_null("../PlayerRoot")
	if not player_root:
		player_root = Node3D.new()
		player_root.name = "PlayerRoot"
		get_parent().add_child(player_root)
	return player_root

func _get_game_manager() -> GameManager:
	var tree := get_tree()
	if not tree:
		return null
	return tree.get_first_node_in_group("game_manager") as GameManager
