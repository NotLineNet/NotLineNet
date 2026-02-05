extends PanelContainer

const NodeLocator = preload("res://scripts/core/NodeLocator.gd")

@onready var reload_button: Button = $HBoxContainer/ReloadButton
@onready var way_button: Button = $HBoxContainer/WayButton
@onready var start_button: Button = $HBoxContainer/StartButton
var player_ui_action_points: HBoxContainer
var button_finish: Button
var player_ui: Control
@onready var add_card_button: Button = $HBoxContainer/AddCardButton
@onready var game_manager: GameManager = get_node_or_null("../../GameManager") as GameManager
@onready var day_label: Label = $HBoxContainer/DayLabel

var paths_visible: bool = false
var level_manager: LevelManager
var _battle_active := false

func _ready():
	_find_level_manager()
	_ensure_player_ui_refs()
	way_button.pressed.connect(_on_way_button_pressed)
	reload_button.pressed.connect(_on_reload_button_pressed)
	if start_button:
		start_button.visible = true
		start_button.pressed.connect(_on_start_button_pressed)
	_update_way_button_text()
	if button_finish:
		button_finish.visible = false
		button_finish.pressed.connect(_on_button_finish_pressed)
	if add_card_button:
		add_card_button.pressed.connect(_on_add_card_button_pressed)
	_setup_game_manager_connections()

func _on_gameplay_started() -> void:
	if start_button:
		start_button.visible = false
	_highlight_active_portrait()

func _on_action_points_changed(new_value: int):
	"""Обновляет визуальное отображение очков действий"""
	_update_player_ui_action_points(new_value)
	_update_finish_button(new_value)

func _on_battle_state_changed(active: bool) -> void:
	_battle_active = active
	_update_finish_button(_get_active_action_points())

func _update_player_ui_action_points(count: int):
	"""Скрывает/показывает ColorRect внутри AP нод в PlayerUI"""
	_ensure_player_ui_refs()
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
	_ensure_player_ui_refs()
	if not button_finish:
		return
	button_finish.visible = count == 0 and not _is_battle_active()

func _is_battle_active() -> bool:
	if game_manager and game_manager.has_method("is_battle_active"):
		_battle_active = game_manager.is_battle_active()
	return _battle_active

func _get_active_action_points() -> int:
	if game_manager and game_manager.active_player:
		return game_manager.active_player.action_points
	return 0

func _setup_game_manager_connections() -> void:
	if not game_manager:
		return
	if not game_manager.is_connected("active_player_action_points_changed", Callable(self, "_on_action_points_changed")):
		game_manager.connect("active_player_action_points_changed", Callable(self, "_on_action_points_changed"))
	if not game_manager.is_connected("active_player_changed", Callable(self, "_on_active_player_changed")):
		game_manager.connect("active_player_changed", Callable(self, "_on_active_player_changed"))
	if not game_manager.is_connected("gameplay_started", Callable(self, "_on_gameplay_started")):
		game_manager.connect("gameplay_started", Callable(self, "_on_gameplay_started"))
	if not game_manager.is_connected("battle_state_changed", Callable(self, "_on_battle_state_changed")):
		game_manager.connect("battle_state_changed", Callable(self, "_on_battle_state_changed"))
	_apply_active_player_state(game_manager.active_player)
	_highlight_active_portrait()
	_on_battle_state_changed(game_manager.is_battle_active() if game_manager.has_method("is_battle_active") else false)

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
	level_manager = NodeLocator.level_manager(tree)
	if not level_manager:
		await tree.process_frame
		level_manager = NodeLocator.level_manager(tree)

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
		game_manager.request_player_finish_turn()


func _on_add_card_button_pressed() -> void:
	var card_data := {"cost": 1}
	if game_manager and game_manager.active_player and game_manager.has_method("grant_card_to_player"):
		game_manager.grant_card_to_player(game_manager.active_player, card_data, true)
		return
	_ensure_player_ui_refs()
	if not player_ui:
		return
	var hand: HandUI = player_ui.get_hand_ui()
	if not hand:
		return
	hand.add_card(card_data, true)

func _on_start_button_pressed() -> void:
	if game_manager:
		game_manager.game_started()

func set_day_label(day: int) -> void:
	if day_label:
		day_label.text = "День %d" % day


func bind_player_ui(instance: Control) -> void:
	if not instance:
		return
	if player_ui == instance and is_instance_valid(player_ui):
		return
	player_ui = instance
	player_ui_action_points = instance.get_node_or_null("PanelRoot/ActionPoints") as HBoxContainer
	button_finish = instance.get_node_or_null("PanelRoot/ButtonFinish") as Button
	if button_finish and not button_finish.pressed.is_connected(_on_button_finish_pressed):
		button_finish.pressed.connect(_on_button_finish_pressed)
	_update_finish_button(_get_active_action_points())


func unbind_player_ui() -> void:
	player_ui = null
	player_ui_action_points = null
	button_finish = null


func _ensure_player_ui_refs() -> void:
	if player_ui and is_instance_valid(player_ui):
		return
	var candidate := get_node_or_null("../PlayerUI") as Control
	if not candidate:
		player_ui = null
		player_ui_action_points = null
		button_finish = null
		return
	bind_player_ui(candidate)
