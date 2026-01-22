extends Node3D
class_name CameraDrag

# ===== ПАРАМЕТРЫ ДВИЖЕНИЯ =====
@export var drag_speed: float = 0.05  # Базовая скорость скролла (используется если не указана в пресете)
var current_drag_speed: float = 0.05  # Текущая скорость скролла (из пресета)

# ===== ПАРАМЕТРЫ ЗУМА =====
@export var zoom_speed: float = 5.0  # Скорость интерполяции зума
@export var camera_center_speed: float = 3.0  # Скорость центрирования камеры на тайле (для пресета 0)

# Массив зум-пресетов (4 уровня: 0-3)
# Каждый пресет задает: высоту CameraRig (Y координата), Z позицию CameraPivot, наклон CameraPivot, FOV камеры, скорость скролла
# Примечание: X координата в position игнорируется - она управляется движением камеры (drag)
# Z позиция применяется к CameraPivot, чтобы не конфликтовать с движением камеры
# drag_speed - скорость скролла мышкой (если не указана, используется базовое значение drag_speed)
@export var zoom_presets: Array[Dictionary] = [
	# Уровень 0 - максимальное отдаление
	{"position": Vector3(0, 8, 0), "rotation_x": -30.0, "fov": 70.0},
	# Уровень 1 - среднее отдаление
	{"position": Vector3(0, 6, 0), "rotation_x": -35.0, "fov": 60.0},
	# Уровень 2 - среднее приближение
	{"position": Vector3(0, 4, 0), "rotation_x": -40.0, "fov": 50.0},
	# Уровень 3 - максимальное приближение
	{"position": Vector3(0, 2, 0), "rotation_x": -45.0, "fov": 40.0}
]

# ===== ВНУТРЕННИЕ ПЕРЕМЕННЫЕ =====
var dragging: bool = false
var last_mouse_pos: Vector2

# Ссылки на узлы камеры
var camera_pivot: Node3D  # CameraPivot - отвечает за наклон
var camera: Camera3D      # Camera3D - отвечает за FOV

# Текущий уровень зума (0 до количества пресетов - 1)
# Пресет 0 - стартовый уровень
var zoom_level: int = 0

# Текущие значения для интерполяции
var current_position_y: float  # Y позиция CameraRig
var current_pivot_z: float      # Z позиция CameraPivot
var current_rotation_x: float   # Наклон CameraPivot
var current_fov: float          # FOV Camera3D

# Целевые значения из пресета
var target_position_y: float
var target_pivot_z: float
var target_rotation_x: float
var target_fov: float

# Целевая позиция для центрирования на тайле (для пресета 0)
var target_tile_position: Vector3
var is_centering_on_tile: bool = false

# ===== ИНИЦИАЛИЗАЦИЯ =====
func _ready():
	# Добавляем в группу для удобного поиска
	add_to_group("camera_root")
	
	# Находим CameraPivot (должен быть дочерним узлом)
	camera_pivot = get_node_or_null("CameraPivot")
	if not camera_pivot:
		push_error("CameraPivot не найден! Создайте CameraPivot как дочерний узел CameraRoot")
		return
	
	# Находим Camera3D (должен быть дочерним узлом CameraPivot)
	camera = camera_pivot.get_node_or_null("Camera3D") as Camera3D
	if not camera:
		push_error("Camera3D не найден! Создайте Camera3D как дочерний узел CameraPivot")
		return
	
	# Инициализируем пресеты из массива
	_initialize_presets()
	
	# Инициализируем текущие значения из текущего состояния камеры
	# Y позиция берется из CameraRig, Z позиция из CameraPivot
	current_position_y = position.y
	if camera_pivot:
		current_pivot_z = camera_pivot.position.z
		current_rotation_x = camera_pivot.rotation_degrees.x
	if camera:
		current_fov = camera.fov
	
	# Инициализируем текущую скорость скролла
	current_drag_speed = drag_speed
	
	# Устанавливаем начальный уровень зума
	_set_zoom_level(zoom_level, false)  # false = без интерполяции при старте
	
	# Если начальный уровень 0, центрируем камеру на тайле игрока
	if zoom_level == 0:
		_center_camera_on_player_tile()

# ===== ИНИЦИАЛИЗАЦИЯ ПРЕСЕТОВ =====
func _initialize_presets():
	"""Преобразует массив словарей в массив ZoomPreset объектов"""
	# Если пресеты не заданы (массив пустой), используем значения по умолчанию
	if zoom_presets.size() == 0:
		zoom_presets = [
			{"position": Vector3(0, 8, 0), "rotation_x": -30.0, "fov": 70.0, "drag_speed": drag_speed},
			{"position": Vector3(0, 6, 0), "rotation_x": -35.0, "fov": 60.0, "drag_speed": drag_speed * 1.5},
			{"position": Vector3(0, 4, 0), "rotation_x": -40.0, "fov": 50.0, "drag_speed": drag_speed * 2.0},
			{"position": Vector3(0, 2, 0), "rotation_x": -45.0, "fov": 40.0, "drag_speed": drag_speed * 2.5}
		]

# ===== ОБРАБОТКА ВВОДА =====
func _unhandled_input(event):
	# Обработка перетаскивания камеры (правая кнопка мыши)
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT:
		if event.pressed:
			dragging = true
			last_mouse_pos = event.position
		else:
			dragging = false
	
	elif event is InputEventMouseMotion and dragging:
		# Блокируем движение камеры на пресете 0 (камера привязана к тайлу)
		if zoom_level == 0:
			return
		
		var delta: Vector2 = event.position - last_mouse_pos
		last_mouse_pos = event.position
		
		# Движение камеры (изменяем позицию CameraRig)
		# Используем current_drag_speed из текущего пресета
		global_position.x -= delta.x * current_drag_speed
		global_position.z -= delta.y * current_drag_speed
	
	# Обработка колеса мыши для зума
	elif event is InputEventMouseButton and camera and event.pressed:
		var max_level: int = zoom_presets.size() - 1
		var old_level: int = zoom_level
		
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			# Колесико вверх - камера ниже (уменьшаем zoom_level) - ИНВЕРТИРОВАНО
			zoom_level = clamp(zoom_level - 1, 0, max_level)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			# Колесико вниз - камера выше (увеличиваем zoom_level) - ИНВЕРТИРОВАНО
			# Пресет 1 - камера выше, пресет 2 - камера еще выше
			zoom_level = clamp(zoom_level + 1, 0, max_level)
		
		# Логируем только если уровень изменился
		if zoom_level != old_level:
			_set_zoom_level(zoom_level, true)  # true = с интерполяцией
			
			# Если перешли на пресет 0, центрируем камеру на тайле игрока
			if zoom_level == 0:
				_center_camera_on_player_tile()

# ===== УСТАНОВКА УРОВНЯ ЗУМА =====
func _set_zoom_level(level: int, interpolate: bool = true):
	"""Устанавливает целевой уровень зума из пресета"""
	if level < 0 or level >= zoom_presets.size():
		return
	
	# Получаем пресет для текущего уровня
	var preset_dict: Dictionary = zoom_presets[level]
	
	# Устанавливаем целевые значения
	# Из position берем Y координату (высоту CameraRig) и Z координату (позиция CameraPivot)
	var preset_pos: Vector3 = preset_dict.get("position", Vector3.ZERO)
	target_position_y = preset_pos.y
	target_pivot_z = preset_pos.z
	target_rotation_x = preset_dict.get("rotation_x", 0.0)
	target_fov = preset_dict.get("fov", 50.0)
	
	# Устанавливаем скорость скролла из пресета (если не указана, используем базовое значение)
	current_drag_speed = preset_dict.get("drag_speed", drag_speed)
	
	# Если интерполяция не нужна, сразу устанавливаем значения
	if not interpolate:
		current_position_y = target_position_y
		current_pivot_z = target_pivot_z
		current_rotation_x = target_rotation_x
		current_fov = target_fov
		_apply_zoom_values()

# ===== ПРИМЕНЕНИЕ ЗНАЧЕНИЙ ЗУМА =====
func _apply_zoom_values():
	"""Применяет текущие значения зума к узлам камеры"""
	if not camera_pivot or not camera:
		return
	
	# Применяем позицию к CameraRig (этот узел)
	# Сохраняем X и Z из текущей позиции (X управляется drag, Z не используется в CameraRig)
	# Меняем только Y (высоту) из пресета
	position = Vector3(position.x, current_position_y, position.z)
	
	# Применяем Z позицию и наклон к CameraPivot
	camera_pivot.position.z = current_pivot_z
	camera_pivot.rotation_degrees.x = current_rotation_x
	
	# Применяем FOV к Camera3D
	camera.fov = current_fov

# ===== ИНТЕРПОЛЯЦИЯ ЗУМА =====
func _process(delta: float):
	"""Плавная интерполяция между текущими и целевыми значениями зума"""
	if not camera_pivot or not camera:
		return
	
	# Интерполируем позицию CameraRig (только Y координата)
	# X остается неизменным, управляется движением камеры (drag) или привязан к тайлу на пресете 0
	current_position_y = lerp(current_position_y, target_position_y, zoom_speed * delta)
	
	# Интерполируем Z позицию CameraPivot
	current_pivot_z = lerp(current_pivot_z, target_pivot_z, zoom_speed * delta)
	
	# Интерполируем наклон CameraPivot (используем lerp_angle для правильной работы с углами)
	var target_rad: float = deg_to_rad(target_rotation_x)
	var current_rad: float = deg_to_rad(current_rotation_x)
	current_rad = lerp_angle(current_rad, target_rad, zoom_speed * delta)
	current_rotation_x = rad_to_deg(current_rad)
	
	# Интерполируем FOV
	current_fov = lerp(current_fov, target_fov, zoom_speed * delta)
	
	# Если на пресете 0 и включен режим центрирования, плавно центрируем камеру на тайле
	if zoom_level == 0 and is_centering_on_tile:
		# Плавно интерполируем позицию камеры к позиции тайла
		var current_pos := global_position
		var new_pos := current_pos.lerp(target_tile_position, camera_center_speed * delta)
		
		# Проверяем, достигли ли мы цели (с небольшой погрешностью)
		if current_pos.distance_to(target_tile_position) < 0.01:
			global_position = target_tile_position
			is_centering_on_tile = false
		else:
			global_position = new_pos
	
	# Применяем интерполированные значения
	_apply_zoom_values()

# ===== ЦЕНТРИРОВАНИЕ КАМЕРЫ НА ТАЙЛЕ ИГРОКА =====
func _center_camera_on_player_tile():
	"""Устанавливает цель для плавного центрирования камеры на тайле игрока (при переходе на пресет 0)"""
	# Находим игрока через группу
	var tree := get_tree()
	if not tree:
		return
	
	var player = tree.get_first_node_in_group("player") as Player
	if not player or not player.current_tile:
		return
	
	var target_tile: Tile = player.current_tile
	
	# Вычисляем целевую позицию камеры (только x и z, y остается прежним)
	target_tile_position = Vector3(
		target_tile.global_position.x,
		global_position.y,  # Сохраняем текущую высоту камеры
		target_tile.global_position.z
	)
	
	# Включаем режим центрирования (интерполяция будет происходить в _process)
	is_centering_on_tile = true

func center_camera_on_tile(target_tile: Tile):
	"""Публичный метод для центрирования камеры на тайле (вызывается из Player.gd)"""
	# Если мы не на пресете 0, не центрируем камеру
	if zoom_level != 0:
		is_centering_on_tile = false
		return
	
	if not target_tile:
		return
	
	# Вычисляем целевую позицию камеры (только x и z, y остается прежним)
	target_tile_position = Vector3(
		target_tile.global_position.x,
		global_position.y,  # Сохраняем текущую высоту камеры
		target_tile.global_position.z
	)
	
	# Включаем режим центрирования (интерполяция будет происходить в _process)
	is_centering_on_tile = true
