extends PanelContainer

@onready var action_points_container: HBoxContainer = $HBoxContainer/ActionPoints
@onready var point_template: ColorRect = $HBoxContainer/ActionPoints/Point
@onready var way_button: Button = $HBoxContainer/WayButton

var player: Player
var paths_visible: bool = false
var level_manager: LevelManager

func _ready():
	# Находим игрока через группу
	_find_player()
	_find_level_manager()
	way_button.pressed.connect(_on_way_button_pressed)
	_update_way_button_text()

func _find_player():
	"""Находит игрока в дереве сцены"""
	var tree := get_tree()
	if not tree:
		return
	
	# Пробуем найти игрока
	player = tree.get_first_node_in_group("player") as Player
	
	# Если игрок еще не создан, ждем и пробуем снова
	if not player:
		await get_tree().process_frame
		player = tree.get_first_node_in_group("player") as Player
	
	# Если игрок найден, подключаемся к сигналу
	if player:
		if not player.action_points_changed.is_connected(_on_action_points_changed):
			player.action_points_changed.connect(_on_action_points_changed)
		# Инициализируем UI с начальным количеством очков
		_update_action_points_display(player.action_points)

func _on_action_points_changed(new_value: int):
	"""Обновляет визуальное отображение очков действий"""
	_update_action_points_display(new_value)

func _update_action_points_display(count: int):
	"""Обновляет количество Point'ов в UI"""
	# Скрываем шаблон, он используется только как образец
	point_template.visible = false
	
	# Удаляем все существующие Point'ы (кроме шаблона)
	var children = action_points_container.get_children()
	for child in children:
		if child != point_template:
			child.queue_free()
	
	# Создаем нужное количество Point'ов
	for i in count:
		var new_point := ColorRect.new()
		new_point.custom_minimum_size = point_template.custom_minimum_size
		new_point.color = point_template.color
		new_point.layout_mode = point_template.layout_mode
		action_points_container.add_child(new_point)

func _on_od_button_pressed() -> void:
	# Если игрок найден, добавляем очко действия
	if player:
		player.add_action_point()
	else:
		_find_level_manager()
		if level_manager:
			level_manager.set_path_debug_visible(paths_visible)

func _find_level_manager():
	var tree := get_tree()
	if not tree:
		return
	level_manager = tree.get_first_node_in_group("level_manager") as LevelManager
	if not level_manager:
		await tree.process_frame
		level_manager = tree.get_first_node_in_group("level_manager") as LevelManager

func _update_way_button_text():
	if paths_visible:
		way_button.text = "Пути: вкл"
	else:
		way_button.text = "Пути: выкл"

func _on_way_button_pressed():
	paths_visible = not paths_visible
	_update_way_button_text()
	if not level_manager:
		_find_level_manager()
	if level_manager:
		level_manager.set_path_debug_visible(paths_visible)
	else:
		# Если игрок еще не найден, пробуем найти его
		_find_player()
		if player:
			player.add_action_point()
