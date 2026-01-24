extends Node3D
class_name Player

const MOVE_DURATION := 0.2  # Длительность анимации движения в секундах
const CAMERA_MOVE_DURATION := 0.3  # Длительность анимации движения камеры (немного дольше)
const CAMERA_DELAY := 0.05  # Небольшое отставание перед началом движения камеры

signal action_points_changed(new_value: int)

const MAX_ACTION_POINTS := 3
const MIN_ACTION_POINTS := 0

var current_tile: Tile
var previous_tile: Tile  # Для возврата на предыдущий тайл
var is_moving := false
var is_active := false
var level_manager: LevelManager
var action_points: int = 3  # Количество очков действий

# Размер игрока - половина размера тайла (TILE_SIZE = 2.0, значит игрок = 1.0)
const PLAYER_SIZE := 1.0

func _ready():
	# Визуал берётся из сцены Player (Sprite3D). Если сцены нет — создаём сферу как запасной вариант
	_create_player_visual()
	
	# LevelManager будет установлен через initialize_on_tile()

func _create_player_visual():
	# Если в сцене уже есть BodyImage или другой Sprite3D — ничего не делаем, используем его
	if get_node_or_null("BodyImage"):
		return
	for child in get_children():
		if child is Sprite3D:
			return

func set_active(active: bool) -> void:
	if is_active == active:
		return
	if not active and current_tile:
		current_tile.on_player_exited()
	is_active = active
	if is_active and current_tile:
		current_tile.on_player_entered()
		_move_camera_to_tile_immediate(current_tile)

func initialize_on_tile(tile: Tile):
	"""Размещает игрока на указанном тайле (стартовый зеленый тайл)"""
	current_tile = tile
	previous_tile = null
	global_position = tile.global_position + Vector3(0, PLAYER_SIZE / 2.0 + 0.1, 0)
	
	# Подключаемся к сигналам тайла
	_connect_to_tile(tile)
	
	# Если игрок активный, обновляем визуальные маркеры
	if is_active:
		tile.on_player_entered()
		_move_camera_to_tile_immediate(tile)

func _connect_to_tile(tile: Tile):
	"""Подключается к сигналам тайла для обработки кликов на ворота"""
	if not tile:
		return
	
	# Отключаемся от предыдущего тайла
	if current_tile and current_tile != tile:
		_disconnect_from_tile(current_tile)
	
	# Подключаемся к новому тайлу
	if not tile.exit_clicked.is_connected(_on_exit_clicked):
		tile.exit_clicked.connect(_on_exit_clicked)

func _disconnect_from_tile(tile: Tile):
	"""Отключается от сигналов тайла"""
	if tile and tile.exit_clicked.is_connected(_on_exit_clicked):
		tile.exit_clicked.disconnect(_on_exit_clicked)

func _on_exit_clicked(tile: Tile, dir: Vector2i):
	"""Обработчик клика на ворота тайла"""
	# Проверяем, что клик был на текущем тайле и игрок не движется
	if tile != current_tile or is_moving:
		return
	if not is_active:
		return
	
	# Проверяем наличие очков действий
	if action_points <= MIN_ACTION_POINTS:
		return
	
	# Проверяем, что в этом направлении есть выход
	if not tile.exits.has(dir):
		return
	
	# Находим следующий тайл
	var next_pos := tile.grid_pos + dir
	if not level_manager or not level_manager.tiles.has(next_pos):
		return
	
	var next_tile: Tile = level_manager.tiles[next_pos] as Tile
	if not next_tile:
		return
	
	# Сохраняем текущий тайл как предыдущий
	previous_tile = current_tile
	
	# Двигаемся на следующий тайл
	move_to_tile(next_tile)

func move_to_tile(target_tile: Tile):
	"""Двигает игрока на указанный тайл с анимацией"""
	if is_moving or not target_tile:
		return
	if not is_active:
		return
	
	# Проверяем наличие очков действий
	if action_points <= MIN_ACTION_POINTS:
		return
	
	is_moving = true
	
	# Уведомляем текущий тайл, что игрок уходит (меняем цвет на серый)
	if current_tile:
		current_tile.on_player_exited()
	
	# Отключаемся от текущего тайла
	_disconnect_from_tile(current_tile)
	
	# Вычисляем целевую позицию
	var target_position := target_tile.global_position + Vector3(0, PLAYER_SIZE / 2.0 + 0.1, 0)
	var start_position := global_position
	
	# Создаем твин для анимации движения с изингом
	var tween := create_tween()
	tween.set_ease(Tween.EASE_IN_OUT)
	tween.set_trans(Tween.TRANS_CUBIC)
	tween.tween_property(self, "global_position", target_position, MOVE_DURATION)
	
	# Перемещаем камеру с небольшим отставанием
	_move_camera_to_tile(target_tile)
	
	# Ждем завершения анимации
	await tween.finished
	
	# Обновляем текущий тайл
	current_tile = target_tile
	
	# Подключаемся к новому тайлу
	_connect_to_tile(current_tile)
	
	# Уведомляем новый тайл, что игрок пришел
	current_tile.on_player_entered()
	
	# Показываем тайл, если он скрыт
	if not current_tile.visible:
		current_tile.show_tile()
	
	# Вычитаем очко действия при переходе на новый тайл
	spend_action_point()
	
	is_moving = false

func can_move_back() -> bool:
	"""Проверяет, может ли игрок вернуться на предыдущий тайл"""
	return previous_tile != null and not is_moving

func move_back():
	"""Возвращает игрока на предыдущий тайл"""
	if not is_active:
		return
	if not can_move_back():
		return
	
	var temp_tile := previous_tile
	previous_tile = current_tile
	move_to_tile(temp_tile)

func add_action_point():
	"""Добавляет одно очко действия (максимум MAX_ACTION_POINTS)"""
	if action_points < MAX_ACTION_POINTS:
		action_points += 1
		action_points_changed.emit(action_points)

func refill_action_points():
	"""Восстанавливает очки действий до максимума"""
	if action_points != MAX_ACTION_POINTS:
		action_points = MAX_ACTION_POINTS
		action_points_changed.emit(action_points)

func spend_action_point():
	"""Тратит одно очко действия (минимум MIN_ACTION_POINTS)"""
	if action_points > MIN_ACTION_POINTS:
		action_points -= 1
		action_points_changed.emit(action_points)

func _move_camera_to_tile(target_tile: Tile):
	"""Перемещает камеру на позицию тайла с изингом и небольшим отставанием"""
	if not is_active:
		return
	# Находим CameraRoot в дереве сцены
	var camera_root: CameraDrag = null
	
	# Пробуем найти через дерево сцены (группа)
	var tree := get_tree()
	if tree:
		camera_root = tree.get_first_node_in_group("camera_root") as CameraDrag
	
	# Если не нашли через группу, пробуем через путь
	if not camera_root:
		camera_root = get_node_or_null("../../CameraRoot") as CameraDrag
	
	# Если все еще не нашли, пробуем абсолютный путь
	if not camera_root:
		camera_root = get_node_or_null("/root/Main/CameraRoot") as CameraDrag
	
	if not camera_root:
		return
	
	# Если камера на пресете 0, используем метод центрирования (камера привязана к тайлу)
	if camera_root.zoom_level == 0:
		camera_root.center_camera_on_tile(target_tile)
		return
	
	# Обычное перемещение камеры с отставанием (для других пресетов)
	var target_camera_position := Vector3(
		target_tile.global_position.x,
		camera_root.global_position.y,  # Сохраняем текущую высоту камеры
		target_tile.global_position.z
	)
	
	# Создаем твин для камеры с изингом и отставанием
	var camera_tween := create_tween()
	camera_tween.set_ease(Tween.EASE_IN_OUT)
	camera_tween.set_trans(Tween.TRANS_CUBIC)
	
	# Добавляем небольшую задержку перед началом движения камеры
	camera_tween.tween_interval(CAMERA_DELAY)
	camera_tween.tween_property(camera_root, "global_position", target_camera_position, CAMERA_MOVE_DURATION)

func _move_camera_to_tile_immediate(target_tile: Tile):
	"""Перемещает камеру на позицию тайла без задержки (для инициализации)"""
	if not is_active:
		return
	# Находим CameraRoot в дереве сцены
	var camera_root: Node3D = null
	
	# Пробуем найти через дерево сцены (группа)
	var tree := get_tree()
	if tree:
		camera_root = tree.get_first_node_in_group("camera_root") as Node3D
	
	# Если не нашли через группу, пробуем через путь
	if not camera_root:
		camera_root = get_node_or_null("../../CameraRoot") as Node3D
	
	# Если все еще не нашли, пробуем абсолютный путь
	if not camera_root:
		camera_root = get_node_or_null("/root/Main/CameraRoot") as Node3D
	
	if not camera_root:
		return
	
	# Вычисляем целевую позицию камеры (только x и z, y остается прежним)
	var target_camera_position := Vector3(
		target_tile.global_position.x,
		camera_root.global_position.y,  # Сохраняем текущую высоту камеры
		target_tile.global_position.z
	)
	
	# Создаем твин для камеры с изингом (без задержки)
	var camera_tween := create_tween()
	camera_tween.set_ease(Tween.EASE_IN_OUT)
	camera_tween.set_trans(Tween.TRANS_CUBIC)
	camera_tween.tween_property(camera_root, "global_position", target_camera_position, CAMERA_MOVE_DURATION)
