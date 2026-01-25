extends PanelContainer

@onready var reload_button: Button = $HBoxContainer/ReloadButton
@onready var way_button: Button = $HBoxContainer/WayButton
@onready var start_button: Button = $HBoxContainer/StartButton
@onready var player_ui_action_points: HBoxContainer = $"../PlayerUI/PanelRoot/ActionPoints"
@onready var button_finish: Button = $"../PlayerUI/PanelRoot/ButtonFinish"
@onready var player_ui := $"../PlayerUI"
@onready var game_manager: GameManager = get_node_or_null("../../GameManager") as GameManager
@onready var day_label: Label = $HBoxContainer/DayLabel

var paths_visible: bool = false
var level_manager: LevelManager

func _ready():
	_find_level_manager()
	way_button.pressed.connect(_on_way_button_pressed)
	reload_button.pressed.connect(_on_reload_button_pressed)
	if start_button:
		start_button.visible = true
		start_button.pressed.connect(_on_start_button_pressed)
	_update_way_button_text()
	if button_finish:
		button_finish.visible = false
		button_finish.pressed.connect(_on_button_finish_pressed)
	_setup_game_manager_connections()

func _on_gameplay_started() -> void:
	if start_button:
		start_button.visible = false
	_highlight_active_portrait()

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

func _setup_game_manager_connections() -> void:
	if not game_manager:
		return
	if not game_manager.is_connected("active_player_action_points_changed", Callable(self, "_on_action_points_changed")):
		game_manager.connect("active_player_action_points_changed", Callable(self, "_on_action_points_changed"))
	if not game_manager.is_connected("active_player_changed", Callable(self, "_on_active_player_changed")):
		game_manager.connect("active_player_changed", Callable(self, "_on_active_player_changed"))
	if not game_manager.is_connected("gameplay_started", Callable(self, "_on_gameplay_started")):
		game_manager.connect("gameplay_started", Callable(self, "_on_gameplay_started"))
	_apply_active_player_state(game_manager.active_player)
	_highlight_active_portrait()

func _highlight_active_portrait() -> void:
	var player_manager := get_node_or_null("../../PlayerManager") as PlayerManager
	if not player_manager:
		return
	player_manager.highlight_active_portrait()

func _on_active_player_changed(player: Player) -> void:
	_apply_active_player_state(player)

func _apply_active_player_state(player: Player) -> void:
	if not player:
		return
	_update_player_ui_action_points(player.action_points)
	_update_finish_button(player.action_points)

func _on_od_button_pressed() -> void:
	# Если активный игрок найден, добавляем очко действия
	if game_manager and game_manager.active_player:
		game_manager.active_player.add_action_point()

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

func _on_reload_button_pressed() -> void:
	var tree := get_tree()
	if tree:
		tree.reload_current_scene()

func _on_button_finish_pressed() -> void:
	if game_manager:
		game_manager.current_player_finished_moving()

func _on_start_button_pressed() -> void:
	if game_manager:
		game_manager.game_started()

func set_day_label(day: int) -> void:
	if day_label:
		day_label.text = "День %d" % day
