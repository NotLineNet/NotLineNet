extends Node3D
class_name Player

const GameConfig = preload("res://scripts/core/GameConfig.gd")
const NodeLocator = preload("res://scripts/core/NodeLocator.gd")

signal action_points_changed(new_value: int)
signal moved_to_tile(new_tile: Tile)
signal movement_started()
signal health_changed(new_value: int, old_value: int)
signal level_changed(new_value: int)

const MAX_ACTION_POINTS := GameConfig.MAX_ACTION_POINTS
const MIN_ACTION_POINTS := GameConfig.MIN_ACTION_POINTS
const MIN_LEVEL := 1
const MAX_LEVEL := 10

var current_tile: Tile
var previous_tile: Tile  # Для возврата на предыдущий тайл
var start_tile: Tile  # Стартовый тайл для возврата после смерти
var is_moving := false
var is_active := false
var level_manager: LevelManager
var action_points: int = GameConfig.MAX_ACTION_POINTS  # Количество очков действий
var last_dice_roll: int = 0
var last_moved_tile: Tile
var is_dead := false
var pending_respawn := false
var health_points: int = GameConfig.PLAYER_STARTING_HEALTH
var _default_body_position: Vector3 = Vector3.ZERO
var _tile_combat_requested := false
var level: int = 1
var cards: Array = []
var _movement_service

# Размер игрока - половина размера тайла (TILE_SIZE = 2.0, значит игрок = 1.0)
const PLAYER_SIZE := 1.0

func _ready():
	# Визуал берётся из сцены Player (Sprite3D). Если сцены нет — создаём сферу как запасной вариант
	_create_player_visual()
	_store_default_body_position()
	_movement_service = get_tree().root.get_node_or_null("MovementService")
	
	# LevelManager будет установлен через initialize_on_tile()

func _create_player_visual():
	# Если в сцене уже есть BodyImage или другой Sprite3D — ничего не делаем, используем его
	if get_node_or_null("BodyImage"):
		return
	for child in get_children():
		if child is Sprite3D:
			return

func _store_default_body_position() -> void:
	var body_image := get_node_or_null("BodyImage") as Sprite3D
	if body_image:
		_default_body_position = body_image.position

func _restore_body_image_position() -> void:
	var body_image := get_node_or_null("BodyImage") as Sprite3D
	if body_image:
		body_image.position = _default_body_position

func set_active(active: bool) -> void:
	if is_active == active:
		return
	if not active and current_tile:
		current_tile.on_player_exited()
	is_active = active
	if is_active and current_tile:
		current_tile.on_player_entered()

func take_damage(amount: int) -> bool:
	if amount <= 0:
		return false
	var old_value := health_points
	health_points = max(health_points - amount, 0)
	if health_points != old_value:
		health_changed.emit(health_points, old_value)
	return health_points == 0

func initialize_on_tile(tile: Tile):
	"""Размещает игрока на указанном тайле (стартовый зеленый тайл)"""
	current_tile = tile
	previous_tile = null
	if not start_tile:
		start_tile = tile
	global_position = tile.global_position
	
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
	
	if not level_manager:
		return

	var next_pos: Vector2i = tile.grid_pos + dir
	if not level_manager.tiles.has(next_pos):
		return

	var next_tile: Tile = level_manager.tiles[next_pos] as Tile
	if not next_tile:
		return

	_attempt_move(dir, next_tile)

func _attempt_move(dir: Vector2i, target_tile: Tile) -> void:
	if not current_tile or not target_tile or is_moving:
		return

	if action_points <= MIN_ACTION_POINTS:
		return

	var has_exit: bool = current_tile.exits.has(dir)
	if not has_exit:
		return

	var visual: int = current_tile.wall_visual_for_direction(dir)
	if visual == Tile.WallVisual.DOOR:
		spend_action_point()
		current_tile.trigger_door_break(dir)
		return
	if visual == Tile.WallVisual.LOCKED_DOOR:
		return

	var handled := false
	if _movement_service and _movement_service.has_method("move_player"):
		handled = _movement_service.move_player(self, dir, target_tile)
	if handled:
		return
	previous_tile = current_tile
	move_to_tile(target_tile)

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
	emit_signal("movement_started")
	
	# Уведомляем текущий тайл, что игрок уходит (меняем цвет на серый)
	if current_tile:
		current_tile.on_player_exited()
	
	# Отключаемся от текущего тайла
	_disconnect_from_tile(current_tile)
	
	# Вычисляем целевую позицию
	var target_position: Vector3 = target_tile.global_position
	var start_position: Vector3 = global_position
	
	# Создаем твин для анимации движения с изингом
	var tween := create_tween()
	tween.set_ease(Tween.EASE_IN_OUT)
	tween.set_trans(Tween.TRANS_CUBIC)
	tween.tween_property(self, "global_position", target_position, GameConfig.PLAYER_MOVE_DURATION)
	
	# Перемещаем камеру с небольшим отставанием
	_move_camera_to_tile(target_tile)
	
	# Ждем завершения анимации
	await tween.finished
	
	# Обновляем текущий тайл
	current_tile = target_tile
	last_moved_tile = target_tile
	
	# Подключаемся к новому тайлу
	_connect_to_tile(current_tile)
	
	# Уведомляем новый тайл, что игрок пришел
	current_tile.on_player_entered()
	
	# Показываем тайл, если он скрыт
	if not current_tile.visible:
		current_tile.show_tile()
	
	# Вычитаем очко действия при переходе на новый тайл
	spend_action_point()
	emit_signal("moved_to_tile", current_tile)
	
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
	
	var temp_tile: Tile = previous_tile
	if not temp_tile:
		return

	var dir: Vector2i = temp_tile.grid_pos - current_tile.grid_pos
	_attempt_move(dir, temp_tile)

func play_ambush_damage_animation():
	var animation_player := get_node_or_null("AnimationPlayer") as AnimationPlayer
	if animation_player and animation_player.has_animation("AmbushDamage"):
		animation_player.play("AmbushDamage")

func add_action_point():
	"""Добавляет одно очко действия (максимум MAX_ACTION_POINTS)"""
	if action_points < MAX_ACTION_POINTS:
		action_points += 1
		action_points_changed.emit(action_points)
		_refresh_exit_colors()

func mark_tile_combat_requested():
	"""Запоминает, что бой уже запущен извне (например, с клетки)."""
	_tile_combat_requested = true

func consume_tile_combat_request() -> bool:
	"""Сбрасывает флаг внешнего боя и возвращает, был ли он установлен."""
	var value := _tile_combat_requested
	_tile_combat_requested = false
	return value

func refill_action_points():
	"""Восстанавливает очки действий до максимума"""
	if action_points != MAX_ACTION_POINTS:
		action_points = MAX_ACTION_POINTS
		action_points_changed.emit(action_points)
		_refresh_exit_colors()

func reset_for_new_day():
	"""Сбрасывает состояние на начало дня без изменения позиции"""
	previous_tile = null
	last_moved_tile = null
	_tile_combat_requested = false

func increase_level(amount: int = 1) -> bool:
	if amount <= 0:
		return false
	var next_level: int = min(level + amount, MAX_LEVEL)
	if next_level == level:
		return false
	level = next_level
	level_changed.emit(level)
	return true

func decrease_level(amount: int = 1) -> bool:
	if amount <= 0:
		return false
	var next_level: int = max(level - amount, MIN_LEVEL)
	if next_level == level:
		return false
	level = next_level
	level_changed.emit(level)
	return true

func set_dice_roll(value: int) -> void:
	last_dice_roll = value

func register_death() -> void:
	is_dead = true
	pending_respawn = true

func spend_action_point():
	"""Тратит одно очко действия (минимум MIN_ACTION_POINTS)"""
	if action_points > MIN_ACTION_POINTS:
		action_points -= 1
		action_points_changed.emit(action_points)
		_refresh_exit_colors()

func _refresh_exit_colors():
	if current_tile:
		current_tile._update_gate_colors()

func respawn_to_start_tile() -> void:
	if not start_tile:
		return
	_teleport_to_tile(start_tile)

func mark_alive() -> void:
	is_dead = false
	_restore_body_image_position()
	_reset_health_to_max()

func _reset_health_to_max() -> void:
	var old_value := health_points
	health_points = GameConfig.PLAYER_STARTING_HEALTH
	if health_points != old_value:
		health_changed.emit(health_points, old_value)

func _teleport_to_tile(target_tile: Tile) -> void:
	if not target_tile:
		return
	is_moving = false
	if current_tile:
		_disconnect_from_tile(current_tile)
		current_tile.on_player_exited()
	current_tile = target_tile
	previous_tile = null
	global_position = target_tile.global_position
	last_moved_tile = target_tile
	_connect_to_tile(current_tile)
	current_tile.on_player_entered()
	_move_camera_to_tile_immediate(current_tile)
	_restore_body_image_position()

func _move_camera_to_tile(target_tile: Tile):
	"""Перемещает камеру на позицию тайла с изингом и небольшим отставанием"""
	if not is_active:
		return
	var camera_root := NodeLocator.camera_root(self)
	if not camera_root:
		return
	if camera_root.zoom_level == 0:
		camera_root.center_camera_on_tile(target_tile)
		return
	camera_root.focus_on_tile(
		target_tile,
		GameConfig.CAMERA_DELAY,
		GameConfig.CAMERA_MOVE_DURATION
	)

func _move_camera_to_tile_immediate(target_tile: Tile):
	"""Перемещает камеру на позицию тайла без задержки (для инициализации)"""
	if not is_active:
		return
	var camera_root := NodeLocator.camera_root(self)
	if not camera_root:
		return
	var target_camera_position := Vector3(
		target_tile.global_position.x,
		camera_root.global_position.y,
		target_tile.global_position.z
	)
	camera_root.global_position = target_camera_position
