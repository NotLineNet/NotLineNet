extends Node

const GameConfig = preload("res://scripts/core/GameConfig.gd")
const GameManager = preload("res://scripts/core/GameManager.gd")
const NodeLocator = preload("res://scripts/core/NodeLocator.gd")
const Player = preload("res://scripts/core/Player.gd")
const Tile = preload("res://scripts/core/Tile.gd")
const RoomUI = preload("res://scenes/ui/RoomUI.tscn")

var _game_manager: GameManager
var _room_ui_instance: Control
var _current_tile: Tile
var _buttons: Dictionary = {}
var _tracked_player: Player
var _player_turn_active := false
var _moved_callable: Callable
var _movement_started_callable: Callable
var _finish_button: Button

func _ready() -> void:
	_moved_callable = Callable(self, "_on_player_moved_to_tile")
	_movement_started_callable = Callable(self, "_on_player_movement_started")
	_game_manager = NodeLocator.game_manager(get_tree())
	if not _game_manager:
		await get_tree().process_frame
		_game_manager = NodeLocator.game_manager(get_tree())
	if _game_manager:
		_connect_game_manager_signals()
		_connect_player_signals(_game_manager.active_player)
	_finish_button = get_parent().get_node_or_null("PlayerUI/PanelRoot/ButtonFinish") as Button
	if _finish_button and not _finish_button.is_connected("pressed", Callable(self, "_on_finish_button_pressed")):
		_finish_button.pressed.connect(Callable(self, "_on_finish_button_pressed"))

func _connect_game_manager_signals() -> void:
	if not _game_manager:
		return
	var turn_started := Callable(self, "_on_player_turn_started")
	var turn_finished := Callable(self, "_on_player_turn_finished")
	var active_changed := Callable(self, "_on_active_player_changed")
	var ap_changed := Callable(self, "_on_action_points_changed")
	if not _game_manager.is_connected("new_player_started_moving", turn_started):
		_game_manager.connect("new_player_started_moving", turn_started)
	if not _game_manager.is_connected("player_turn_finished", turn_finished):
		_game_manager.connect("player_turn_finished", turn_finished)
	if not _game_manager.is_connected("active_player_changed", active_changed):
		_game_manager.connect("active_player_changed", active_changed)
	if not _game_manager.is_connected("active_player_action_points_changed", ap_changed):
		_game_manager.connect("active_player_action_points_changed", ap_changed)

func _connect_player_signals(player: Player) -> void:
	_disconnect_player_signals()
	if not player:
		return
	_tracked_player = player
	if not player.is_connected("moved_to_tile", _moved_callable):
		player.connect("moved_to_tile", _moved_callable)
	if not player.is_connected("movement_started", _movement_started_callable):
		player.connect("movement_started", _movement_started_callable)

func _disconnect_player_signals() -> void:
	if not _tracked_player:
		return
	if _tracked_player.is_connected("moved_to_tile", _moved_callable):
		_tracked_player.disconnect("moved_to_tile", _moved_callable)
	if _tracked_player.is_connected("movement_started", _movement_started_callable):
		_tracked_player.disconnect("movement_started", _movement_started_callable)
	_tracked_player = null

func _on_player_turn_started(player: Player) -> void:
	_player_turn_active = true
	_connect_player_signals(player)
	if player and not player.is_moving:
		_show_room_ui_for_tile(player.current_tile)

func _on_player_turn_finished(_player: Player) -> void:
	_player_turn_active = false
	_clear_room_ui()

func _on_active_player_changed(player: Player) -> void:
	_connect_player_signals(player)
	if not _player_turn_active:
		_clear_room_ui()

func _on_player_moved_to_tile(tile: Tile) -> void:
	if not _player_turn_active:
		return
	_show_room_ui_for_tile(tile)

func _on_player_movement_started() -> void:
	_clear_room_ui()

func _on_action_points_changed(_value: int) -> void:
	_update_room_ui_buttons()

func _on_finish_button_pressed() -> void:
	_clear_room_ui()

func _show_room_ui_for_tile(tile: Tile) -> void:
	if not tile or not _player_turn_active:
		_clear_room_ui()
		return
	if _current_tile == tile and _room_ui_instance:
		_update_room_ui_buttons()
		return
	_clear_room_ui()
	var instance := RoomUI.instantiate() as Control
	if not instance:
		return
	var parent := get_parent()
	if parent:
		parent.add_child(instance)
	_room_ui_instance = instance
	_current_tile = tile
	_initialize_room_ui(instance)
	_update_room_ui_buttons()

func _initialize_room_ui(instance: Control) -> void:
	_buttons.clear()
	var container_path := "ButtonsRoot/VBoxContainer"
	for name in ["ChestButton", "MonsterFightButton", "MonsterRunButton", "RoomExplore"]:
		var button := instance.get_node_or_null("%s/%s" % [container_path, name]) as Button
		if button:
			button.visible = false
			button.disabled = true
			_buttons[name] = button
			match name:
				"RoomExplore":
					button.pressed.connect(Callable(self, "_on_room_explore_pressed"))
				"ChestButton":
					button.pressed.connect(Callable(self, "_on_chest_button_pressed"))
				"MonsterFightButton":
					button.pressed.connect(Callable(self, "_on_monster_fight_pressed"))
				"MonsterRunButton":
					button.pressed.connect(Callable(self, "_on_monster_run_pressed"))

func _update_room_ui_buttons() -> void:
	if not _room_ui_instance or not _current_tile or not _player_turn_active:
		return
	_reset_button_states()
	var player := _get_active_player()
	if _tile_has_active_monster(_current_tile):
		_set_button_state("MonsterFightButton", true)
		_set_button_state("MonsterRunButton", _has_action_points(player))
		return
	match _current_tile.room_type:
		Tile.RoomType.CHEST:
			_set_button_state("ChestButton", true)
			_set_button_state("RoomExplore", _has_action_points(player))
		Tile.RoomType.EMPTY:
			_set_button_state("RoomExplore", _has_action_points(player))

func _reset_button_states() -> void:
	for button in _buttons.values():
		if button:
			button.visible = false
			button.disabled = true

func _set_button_state(name: String, show: bool) -> void:
	var button := _buttons.get(name, null) as Button
	if not button:
		return
	button.visible = show
	button.disabled = not show

func _has_action_points(player: Player) -> bool:
	return player and player.action_points > GameConfig.MIN_ACTION_POINTS

func _tile_has_active_monster(tile: Tile) -> bool:
	if not tile:
		return false
	var monster := tile.occupying_monster
	return monster and monster.is_inside_tree() and not monster.is_dead

func _clear_room_ui() -> void:
	if _room_ui_instance and _room_ui_instance.is_inside_tree():
		_room_ui_instance.queue_free()
	_room_ui_instance = null
	_current_tile = null
	_buttons.clear()

func _get_active_player() -> Player:
	if not _game_manager:
		return null
	return _game_manager.active_player

func _on_room_explore_pressed() -> void:
	var player := _get_active_player()
	if not player:
		return
	if player.action_points <= GameConfig.MIN_ACTION_POINTS:
		return
	player.spend_action_point()
	_update_room_ui_buttons()

func _on_chest_button_pressed() -> void:
	var player := _get_active_player()
	if player:
		player.add_action_point()
	if _current_tile:
		_current_tile.claim_chest()
	_update_room_ui_buttons()

func _on_monster_fight_pressed() -> void:
	var player := _get_active_player()
	if not player or not _current_tile:
		return
	var monster := _current_tile.occupying_monster
	if not monster:
		return
	_clear_room_ui()
	if _game_manager and _game_manager.has_method("start_monster_battle"):
		_game_manager.start_monster_battle(player, monster, true)

func _on_monster_run_pressed() -> void:
	var player := _get_active_player()
	if not player:
		return
	if player.action_points > GameConfig.MIN_ACTION_POINTS:
		player.spend_action_point()
	_clear_room_ui()
