extends Node3D
class_name LevelManager

@export var tile_scene: PackedScene
@export var player_scene: PackedScene
@export var circle_radius: int = 9
@export var path_line_color: Color = Color(1, 0.75, 0.25, 0.9)
@export var path_line_thickness: float = 0.25
@export var path_line_height: float = 0.12

const TILE_SIZE := 4
const DIRECTIONS: Array[Vector2i] = [
	Vector2i.UP,
	Vector2i.DOWN,
	Vector2i.LEFT,
	Vector2i.RIGHT
]

var tiles: Dictionary = {}
var green_tile_pos: Vector2i
var red_tile_pos: Vector2i
var player: Player

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

	green_tile_pos = _pick_random_boundary_position(red_circle, red_tile_pos, radius)
	create_circle_tiles(green_tile_pos, radius)

	var green_tile: Tile = tiles[green_tile_pos] as Tile
	green_tile.set_color(Color.GREEN)
	set_tile_exits(green_tile, green_tile_pos, 4, true)

	# Создаем связный граф, начиная от зеленого и красного тайлов
	create_connected_graph(green_tile_pos, red_tile_pos)

	# Гарантируем путь от зеленого до красного
	ensure_path_between(green_tile_pos, red_tile_pos)

	# Добавляем случайные дополнительные выходы, сохраняя связность
	add_random_exits()

	# Обновляем маркеры выходов для всех тайлов
	for tile in tiles.values():
		(tile as Tile).redraw_exit_markers()

	# Скрываем все тайлы, кроме красного и зеленого
	hide_all_tiles_except([green_tile_pos, red_tile_pos])

	# Создаем и размещаем игрока на зеленом тайле
	create_player()

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

func _pick_random_boundary_position(circle_info: Dictionary, center: Vector2i, radius: int) -> Vector2i:
	var candidates := []

	for pos in circle_info["boundary"]:
		if pos != center:
			candidates.append(pos)

	if candidates.size() == 0:
		for pos in circle_info["positions"]:
			if pos != center:
				candidates.append(pos)

	if candidates.size() == 0:
		var fallback := center + Vector2i(radius, 0)
		create_tile(fallback)
		return fallback

	candidates.shuffle()
	return candidates[0]

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
		var num_exits: int
		if rand_val < 0.05:  # 5% - 1 выход (тупик, минимум)
			num_exits = 1
		elif rand_val < 0.35:  # 30% - 2 выхода
			num_exits = min(2, max_exits)
		elif rand_val < 0.80:  # 45% - 3 выхода
			num_exits = min(3, max_exits)
		else:  # 20% - 4 выхода
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

# ===== СОЗДАНИЕ СВЯЗНОГО ГРАФА =====

func create_connected_graph(start_pos1: Vector2i, start_pos2: Vector2i):
	# Используем BFS для создания связного графа от обоих стартовых точек
	var visited := {}
	var queue: Array[Vector2i] = []
	
	# Добавляем оба стартовых тайла в очередь
	visited[start_pos1] = true
	visited[start_pos2] = true
	queue.append(start_pos1)
	queue.append(start_pos2)
	
	# Обрабатываем все тайлы
	while queue.size() > 0:
		var current_pos: Vector2i = queue.pop_front()
		var current_tile: Tile = tiles[current_pos] as Tile
		
		# Пропускаем зеленый и красный тайлы - у них уже есть 4 выхода
		if current_pos == green_tile_pos or current_pos == red_tile_pos:
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
		if not visited.has(pos):
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
		if not next_tile.exits.has(-best_dir):
			next_tile.exits.append(-best_dir)
		
		current_pos = next_pos

# ===== ДОБАВЛЕНИЕ СЛУЧАЙНЫХ ВЫХОДОВ =====

func add_random_exits():
	
	for pos in tiles.keys():
		# Пропускаем зеленый и красный тайлы (у них уже 4 выхода)
		if pos == green_tile_pos or pos == red_tile_pos:
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
		# Если пути нет, создаем его
		create_path_between(from_pos, to_pos)

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
	if player and player.action_points <= 0:
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

func create_player():
	"""Создает игрока и размещает его на зеленом тайле"""
	# Если сцена игрока не задана, используем сцену Player по умолчанию (Sprite3D)
	if not player_scene:
		player_scene = preload("res://scenes/player/Player.tscn") as PackedScene
	player = player_scene.instantiate() as Player
	
	if not player:
		push_error("Не удалось создать игрока")
		return
	
	# Добавляем игрока в группу для поиска
	player.add_to_group("player")
	
	# Находим PlayerRoot или создаем его
	var player_root := get_node_or_null("../PlayerRoot")
	if not player_root:
		player_root = Node3D.new()
		player_root.name = "PlayerRoot"
		get_parent().add_child(player_root)
	
	player_root.add_child(player)
	
	# Устанавливаем ссылку на LevelManager
	player.level_manager = self
	
	# Размещаем игрока на зеленом тайле
	var green_tile: Tile = tiles[green_tile_pos] as Tile
	if green_tile:
		# Сначала обновляем ссылки на игрока во всех тайлах
		_update_tile_player_references()
		
		# Затем инициализируем игрока на тайле (это вызовет on_player_entered)
		player.initialize_on_tile(green_tile)
		
		# Для надежности принудительно обновляем маркеры стартового тайла
		green_tile.redraw_exit_markers()

func _update_tile_player_references():
	"""Обновляет ссылки на игрока во всех тайлах"""
	for tile in tiles.values():
		(tile as Tile).player = player
