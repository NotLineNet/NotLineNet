extends Node3D
class_name LevelManager

@export var tile_scene: PackedScene
@export var player_scene: PackedScene
@export var circle_radius: int = 9
@export var green_circle_radius: int = 5
@export var path_line_color: Color = Color(1, 0.75, 0.25, 0.9)
@export var path_line_thickness: float = 0.25
@export var path_line_height: float = 0.12
# вероятность совторения тайла со входами:
@export var exit_chance_one: float = 0.05
@export var exit_chance_two: float = 0.20
@export var exit_chance_three: float = 0.60
@export var exit_chance_four: float = 0.15

const TILE_SIZE := 4
const DIRECTIONS: Array[Vector2i] = [
	Vector2i.UP,
	Vector2i.DOWN,
	Vector2i.LEFT,
	Vector2i.RIGHT
]

var tiles: Dictionary = {}
var green_tile_positions: Array[Vector2i] = []
var red_tile_pos: Vector2i
var path_debug_root: Node3D
var path_debug_lines_built: bool = false
var path_line_material: StandardMaterial3D

func _ready():
	randomize()
	_init_path_debug_root()
	add_to_group("level_manager")
	create_grid()

# ===== СОЗДАНИЕ СЕТКИ =====

func create_grid():
	_clear_path_debug_lines()
	var radius: int = circle_radius
	if radius < 1:
		radius = 1
	red_tile_pos = Vector2i.ZERO
	var red_circle := create_circle_tiles(red_tile_pos, radius)

	var red_tile: Tile = tiles[red_tile_pos] as Tile
	red_tile.set_color(Color.RED)
	set_tile_exits(red_tile, red_tile_pos, 4, true)

	green_tile_positions = _pick_green_tile_positions(red_circle, red_tile_pos, 3)
	if green_tile_positions.size() == 0:
		var fallback_pos := red_tile_pos + Vector2i(radius, 0)
		create_tile(fallback_pos)
		green_tile_positions = [fallback_pos]

	for green_pos in green_tile_positions:
		create_circle_tiles(green_pos, green_circle_radius)
		var green_tile: Tile = tiles[green_pos] as Tile
		green_tile.set_color(Color.GREEN)
		_configure_green_tile_exit(green_tile, green_pos)

	# Создаем связный граф, начиная от зеленых и красного тайлов
	create_connected_graph(green_tile_positions, red_tile_pos)

	# Гарантируем путь от каждого зеленого до красного
	for green_pos in green_tile_positions:
		ensure_path_between(green_pos, red_tile_pos)

	# Добавляем случайные дополнительные выходы, сохраняя связность
	add_random_exits()

	# Обновляем маркеры выходов для всех тайлов
	for tile in tiles.values():
		(tile as Tile).redraw_exit_markers()

	# Скрываем все тайлы, кроме красного и зеленых
	var visible_positions: Array[Vector2i] = green_tile_positions.duplicate()
	visible_positions.append(red_tile_pos)
	hide_all_tiles_except(visible_positions)

	# Создаем и размещаем игроков на зеленых тайлах
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
	for child in path_debug_root.get_children():
		child.queue_free()
	path_debug_lines_built = false

func _get_path_line_material() -> StandardMaterial3D:
	if not path_line_material:
		path_line_material = StandardMaterial3D.new()
		path_line_material.albedo_color = path_line_color
		path_line_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		path_line_material.flags_transparent = true
		path_line_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return path_line_material

func build_path_debug_lines():
	if not path_debug_root:
		return
	_clear_path_debug_lines()
	var material := _get_path_line_material()
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
			line.material_override = material
			var midpoint := Vector2(
				float(pos.x + neighbor_pos.x) / 2.0,
				float(pos.y + neighbor_pos.y) / 2.0
			)
			var center := _grid_to_world(midpoint)
			center.y = path_line_height * 0.5
			line.position = center
			path_debug_root.add_child(line)
	path_debug_lines_built = true

func set_path_debug_visible(enabled: bool):
	if not path_debug_root:
		return
	if enabled and not path_debug_lines_built:
		build_path_debug_lines()
	path_debug_root.visible = enabled

# ===== ПОСТРОЕНИЕ КРУГА =====

func create_circle_tiles(center: Vector2i, radius: int) -> Dictionary:
	var positions := []
	var boundary := []
	var tolerance := 0.8

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

	if boundary.size() == 0:
		return []

	var selected: Array[Vector2i] = []
	var used := {}

	for i in range(count):
		var target_angle := TAU * (i / float(count))
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

func _is_green_tile(pos: Vector2i) -> bool:
	return green_tile_positions.has(pos)

func _is_special_tile(pos: Vector2i) -> bool:
	return pos == red_tile_pos or _is_green_tile(pos)

func _special_has_exit_to(pos: Vector2i, dir: Vector2i) -> bool:
	if not tiles.has(pos):
		return false
	var tile: Tile = tiles[pos] as Tile
	return tile.exits.has(dir)

func _remove_invalid_special_neighbors():
	for pos_key in tiles.keys():
		var pos: Vector2i = pos_key as Vector2i
		var tile: Tile = tiles[pos] as Tile
		for i in range(tile.exits.size() - 1, -1, -1):
			var dir: Vector2i = tile.exits[i]
			var neighbor_pos: Vector2i = pos + dir
			if _is_special_tile(neighbor_pos) and not _special_has_exit_to(neighbor_pos, -dir):
				tile.exits.remove_at(i)

# ===== УСТАНОВКА ВЫХОДОВ ДЛЯ ТАЙЛА =====

func set_tile_exits(tile: Tile, pos: Vector2i, count: int, force_all: bool = false):
	tile.exits.clear()
	var available_dirs: Array[Vector2i] = []

	# Собираем доступные направления, где уже есть тайлы
	for dir: Vector2i in DIRECTIONS:
		var neighbor_pos: Vector2i = pos + dir
		if tiles.has(neighbor_pos):
			available_dirs.append(dir)

	if available_dirs.size() == 0:
		return
	
	if force_all:
		# Для зеленого и красного тайлов - все доступные выходы
		for dir: Vector2i in available_dirs:
			tile.exits.append(dir)
			# Создаем обратную связь с соседом
			var neighbor_pos: Vector2i = pos + dir
			if tiles.has(neighbor_pos):
				var neighbor: Tile = tiles[neighbor_pos] as Tile
				if not neighbor.exits.has(-dir):
					neighbor.exits.append(-dir)
	else:
		# Для обычных тайлов - взвешенная вероятность:
		# 1 выход - 5% (тупик, минимум), 2 выхода - 30%, 3 выхода - 45%, 4 выхода - 20%
		var max_exits: int = min(count, available_dirs.size())
		if max_exits < 1:
			max_exits = available_dirs.size()
		
		var rand_val := randf()
		var cumulative := 0.0
		var num_exits: int
		cumulative += exit_chance_one
		if rand_val < cumulative:
			num_exits = 1
		else:
			cumulative += exit_chance_two
			if rand_val < cumulative:
				num_exits = min(2, max_exits)
			else:
				cumulative += exit_chance_three
				if rand_val < cumulative:
					num_exits = min(3, max_exits)
				else:
					cumulative += exit_chance_four
					if rand_val < cumulative:
						num_exits = min(4, max_exits)
					else:
						num_exits = min(4, max_exits)
		
		available_dirs.shuffle()
		
		for i in range(num_exits):
			var dir: Vector2i = available_dirs[i]
			tile.exits.append(dir)
			# Создаем обратную связь с соседом
			var neighbor_pos: Vector2i = pos + dir
			if tiles.has(neighbor_pos):
				var neighbor: Tile = tiles[neighbor_pos] as Tile
				if not neighbor.exits.has(-dir):
					neighbor.exits.append(-dir)

func _configure_green_tile_exit(tile: Tile, pos: Vector2i):
	tile.exits.clear()
	for dir in DIRECTIONS:
		var neighbor_pos := pos + dir
		_set_neighbor_exit(neighbor_pos, -dir, false)

	var dir := _choose_green_exit_direction(pos)
	if dir == Vector2i.ZERO:
		return

	tile.exits.append(dir)
	var neighbor_pos := pos + dir
	_set_neighbor_exit(neighbor_pos, -dir, true)

func _set_neighbor_exit(neighbor_pos: Vector2i, dir: Vector2i, allow: bool):
	if not tiles.has(neighbor_pos):
		return
	var neighbor: Tile = tiles[neighbor_pos] as Tile
	if allow:
		if not neighbor.exits.has(dir):
			neighbor.exits.append(dir)
	else:
		if neighbor.exits.has(dir):
			neighbor.exits.erase(dir)

func _constrain_green_exits():
	for green_pos in green_tile_positions:
		if tiles.has(green_pos):
			var green_tile: Tile = tiles[green_pos] as Tile
			_configure_green_tile_exit(green_tile, green_pos)
	_remove_invalid_special_neighbors()

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

# ===== СОЗДАНИЕ СВЯЗНОГО ГРАФА =====

func create_connected_graph(green_starts: Array[Vector2i], red_pos: Vector2i):
	# Используем BFS для создания связного графа от зелёных и красного тайлов
	var visited := {}
	var queue: Array[Vector2i] = []
	
	for pos in green_starts:
		if not visited.has(pos):
			visited[pos] = true
			queue.append(pos)

	if not visited.has(red_pos):
		visited[red_pos] = true
		queue.append(red_pos)
	
	# Обрабатываем все тайлы
	while queue.size() > 0:
		var current_pos: Vector2i = queue.pop_front()
		var current_tile: Tile = tiles[current_pos] as Tile
		
		# Пропускаем красный и зеленые тайлы — их выходы уже настроены
		if _is_special_tile(current_pos):
			# Просто добавляем их соседей в очередь
			for dir: Vector2i in current_tile.exits:
				var neighbor_pos: Vector2i = current_pos + dir
				if tiles.has(neighbor_pos) and not visited.has(neighbor_pos):
					visited[neighbor_pos] = true
					queue.append(neighbor_pos)
			continue
		
		# Если у тайла еще нет выходов, создаем минимальные для связности
		if current_tile.exits.size() == 0:
			# Находим непосещенных соседей
			var unvisited_neighbors: Array[Vector2i] = []
			for dir: Vector2i in DIRECTIONS:
				var neighbor_pos: Vector2i = current_pos + dir
				if tiles.has(neighbor_pos) and not visited.has(neighbor_pos):
					unvisited_neighbors.append(neighbor_pos)
			
			# Если есть непосещенные соседи, создаем к ним выходы
			if unvisited_neighbors.size() > 0:
				# Выбираем случайного соседа для связи
				unvisited_neighbors.shuffle()
				var target_pos: Vector2i = unvisited_neighbors[0]
				
				# Находим направление к целевому соседу
				for dir: Vector2i in DIRECTIONS:
					if current_pos + dir == target_pos:
						if not current_tile.exits.has(dir):
							current_tile.exits.append(dir)
						# Создаем обратную связь
						var neighbor: Tile = tiles[target_pos] as Tile
						if not neighbor.exits.has(-dir):
							neighbor.exits.append(-dir)
						
						visited[target_pos] = true
						queue.append(target_pos)
						break
		
		# Добавляем всех соседей текущего тайла в очередь, если они еще не посещены
		for dir: Vector2i in current_tile.exits:
			var neighbor_pos: Vector2i = current_pos + dir
			if tiles.has(neighbor_pos) and not visited.has(neighbor_pos):
				visited[neighbor_pos] = true
				queue.append(neighbor_pos)
	
	# Убеждаемся, что все тайлы достижимы
	# Если есть непосещенные тайлы, создаем к ним связи
	for pos in tiles.keys():
		if _is_special_tile(pos) or visited.has(pos):
			continue
		# Находим ближайший посещенный тайл
		var nearest_visited: Vector2i
		var min_distance := INF
		
		for visited_pos in visited.keys():
			var distance: float = pos.distance_to(visited_pos)
			if distance < min_distance:
				min_distance = distance
				nearest_visited = visited_pos
		
		# Создаем путь от непосещенного к посещенному
		create_path_between(pos, nearest_visited)

# ===== СОЗДАНИЕ ПУТИ МЕЖДУ ДВУМЯ ТАЙЛАМИ =====

func create_path_between(from_pos: Vector2i, to_pos: Vector2i):
	# Простой алгоритм: идем по прямой
	var current_pos := from_pos
	var target_pos := to_pos
	
	while current_pos != target_pos:
		var best_dir: Vector2i
		var best_distance := INF
		
		# Находим направление, которое максимально приближает к цели
		for dir: Vector2i in DIRECTIONS:
			var next_pos: Vector2i = current_pos + dir
			if not tiles.has(next_pos):
				continue
			
			var distance: float = next_pos.distance_to(target_pos)
			if distance < best_distance:
				best_distance = distance
				best_dir = dir
		
		# Создаем выход в выбранном направлении
		var current_tile: Tile = tiles[current_pos] as Tile
		if not current_tile.exits.has(best_dir):
			current_tile.exits.append(best_dir)
		
		# Создаем обратную связь
		var next_pos: Vector2i = current_pos + best_dir
		var next_tile: Tile = tiles[next_pos] as Tile
		if not _is_special_tile(next_pos) and not next_tile.exits.has(-best_dir):
			next_tile.exits.append(-best_dir)
		
		current_pos = next_pos

# ===== ДОБАВЛЕНИЕ СЛУЧАЙНЫХ ВЫХОДОВ =====

func add_random_exits():
	
	for pos in tiles.keys():
		# Пропускаем красный и зеленые тайлы — их выходы уже задано
		if _is_special_tile(pos):
			continue
		
		var tile: Tile = tiles[pos] as Tile
		
		# Пропускаем тайлы, у которых уже 4 выхода
		if tile.exits.size() >= 4:
			continue
		
		# Собираем доступные направления
		var available_dirs: Array[Vector2i] = []
		for dir: Vector2i in DIRECTIONS:
			var neighbor_pos: Vector2i = pos + dir
			if tiles.has(neighbor_pos) and not tile.exits.has(dir):
				available_dirs.append(dir)
		
		# Случайно добавляем дополнительные выходы с низкой вероятностью
		# (чтобы сохранить больше тупиков)
		available_dirs.shuffle()
		var max_additional: int = min(4 - tile.exits.size(), available_dirs.size())
		
		for i in range(max_additional):
			# Низкая вероятность добавления дополнительного выхода (15%)
			if randf() < 0.15:
				var dir: Vector2i = available_dirs[i]
				tile.exits.append(dir)
				# Создаем обратную связь
				var neighbor_pos: Vector2i = pos + dir
				if tiles.has(neighbor_pos):
					var neighbor: Tile = tiles[neighbor_pos] as Tile
					if not neighbor.exits.has(-dir):
						neighbor.exits.append(-dir)
	
	# Синхронизируем связи с особыми тайлами, чтобы не было входов туда, где выходов нет
	_remove_invalid_special_neighbors()

	# Проверяем достижимость каждого зеленого тайла
	_ensure_green_reachability()

	# Принудительно ограничиваем зеленые тайлы одним выходом
	_constrain_green_exits()

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

# ===== ГАРАНТИЯ ПУТИ МЕЖДУ ДВУМЯ ТАЙЛАМИ =====

func ensure_path_between(from_pos: Vector2i, to_pos: Vector2i):
	# Проверяем, есть ли путь от from_pos до to_pos
	var path := find_path(from_pos, to_pos)
	if path.size() == 0:
		# Если пути нет, создаем его (если это не специальные тайлы)
		if _is_special_tile(from_pos) or _is_special_tile(to_pos):
			push_warning("Пропущен шаг соединения специальных тайлов, пути нет.")
			return
		create_path_between(from_pos, to_pos)

func _ensure_green_reachability():
	for green_pos in green_tile_positions:
		for pos_key in tiles.keys():
			var target_pos: Vector2i = pos_key as Vector2i
			if green_pos == target_pos:
				continue
			if find_path(green_pos, target_pos).size() == 0:
				create_path_between(green_pos, target_pos)

# ===== ПОИСК ПУТИ (BFS) =====

func find_path(from_pos: Vector2i, to_pos: Vector2i) -> Array[Vector2i]:
	if from_pos == to_pos:
		return [from_pos]
	
	var queue: Array[Vector2i] = []
	var visited := {}
	var parent := {}
	
	queue.append(from_pos)
	visited[from_pos] = true
	
	while queue.size() > 0:
		var current_pos: Vector2i = queue.pop_front()
		
		if current_pos == to_pos:
			# Восстанавливаем путь
			var path: Array[Vector2i] = []
			var pos := to_pos
			while pos != from_pos:
				path.append(pos)
				pos = parent[pos]
			path.append(from_pos)
			path.reverse()
			return path
		
		var current_tile: Tile = tiles[current_pos] as Tile
		for dir: Vector2i in current_tile.exits:
			var neighbor_pos: Vector2i = current_pos + dir
			if tiles.has(neighbor_pos) and not visited.has(neighbor_pos):
				visited[neighbor_pos] = true
				parent[neighbor_pos] = current_pos
				queue.append(neighbor_pos)
	
	return []  # Путь не найден

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
