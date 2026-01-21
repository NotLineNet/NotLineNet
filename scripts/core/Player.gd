extends Node3D
class_name Player

const MOVE_DURATION := 0.2  # Длительность анимации движения в секундах

var current_tile: Tile
var previous_tile: Tile  # Для возврата на предыдущий тайл
var is_moving := false
var level_manager: LevelManager

# Размер игрока - половина размера тайла (TILE_SIZE = 2.0, значит игрок = 1.0)
const PLAYER_SIZE := 1.0

func _ready():
	# Создаем визуальное представление игрока (шар)
	_create_player_visual()
	
	# LevelManager будет установлен через initialize_on_tile()

func _create_player_visual():
	# Удаляем существующие дочерние элементы, если есть
	for child in get_children():
		child.queue_free()
	
	# Создаем сферу для игрока
	var mesh_instance := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = PLAYER_SIZE / 2.0  # Радиус = половина размера
	sphere.height = PLAYER_SIZE
	mesh_instance.mesh = sphere
	
	# Материал для игрока
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.2, 0.6, 1.0)  # Синий цвет
	mesh_instance.material_override = material
	
	add_child(mesh_instance)
	
	# Позиционируем визуал в центре
	mesh_instance.position = Vector3.ZERO

func initialize_on_tile(tile: Tile):
	"""Размещает игрока на указанном тайле (стартовый зеленый тайл)"""
	current_tile = tile
	previous_tile = null
	global_position = tile.global_position + Vector3(0, PLAYER_SIZE / 2.0 + 0.1, 0)
	
	# Подключаемся к сигналам тайла
	_connect_to_tile(tile)
	
	# Принудительно обновляем цвет ворот на текущем тайле
	tile.on_player_entered()

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
	
	is_moving = false

func can_move_back() -> bool:
	"""Проверяет, может ли игрок вернуться на предыдущий тайл"""
	return previous_tile != null and not is_moving

func move_back():
	"""Возвращает игрока на предыдущий тайл"""
	if not can_move_back():
		return
	
	var temp_tile := previous_tile
	previous_tile = current_tile
	move_to_tile(temp_tile)
