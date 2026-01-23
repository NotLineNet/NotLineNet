extends PanelContainer

@onready var reload_button: Button = $HBoxContainer/ReloadButton
@onready var way_button: Button = $HBoxContainer/WayButton
@onready var player_ui_action_points: HBoxContainer = $"../PlayerUI/PanelRoot/ActionPoints"
@onready var button_finish: Button = $"../PlayerUI/PanelRoot/ButtonFinish"

var player: Player
var paths_visible: bool = false
var level_manager: LevelManager

func _ready():
	# Находим игрока через группу
	_find_player()
	_find_level_manager()
	way_button.pressed.connect(_on_way_button_pressed)
	reload_button.pressed.connect(_on_reload_button_pressed)
	_update_way_button_text()
	if button_finish:
		button_finish.visible = false

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
		_update_player_ui_action_points(player.action_points)
		_update_finish_button(player.action_points)

func _on_action_points_changed(new_value: int):
	"""Обновляет визуальное отображение очков действий"""
	_update_player_ui_action_points(new_value)
	_update_finish_button(new_value)

func _update_player_ui_action_points(count: int):
	"""Скрывает/показывает ColorRect внутри AP нод в PlayerUI"""
	if not player_ui_action_points:
		return
	var ap_nodes := player_ui_action_points.get_children()
	for i in ap_nodes.size():
		var ap_node := ap_nodes[i] as Node
		if not ap_node:
			continue
		var color_rect := ap_node.get_node_or_null("ColorRect") as ColorRect
		if color_rect:
			color_rect.visible = i < count

func _update_finish_button(count: int):
	if not button_finish:
		return
	button_finish.visible = count == 0

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

func _on_reload_button_pressed() -> void:
	var tree := get_tree()
	if tree:
		tree.reload_current_scene()
