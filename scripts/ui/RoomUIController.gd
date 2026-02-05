extends Node

const CameraDrag = preload("res://scripts/core/CameraDrag.gd")
const GameConfig = preload("res://scripts/core/GameConfig.gd")
const GameManager = preload("res://scripts/core/GameManager.gd")
const NodeLocator = preload("res://scripts/core/NodeLocator.gd")
const Player = preload("res://scripts/core/Player.gd")
const Tile = preload("res://scripts/core/Tile.gd")
const RoomUI = preload("res://scenes/ui/RoomUI.tscn")
const WINDOW_ID := "ROOM_UI"

var _game_manager: GameManager
var _room_ui_instance: Control
var _current_tile: Tile
var _marker_target: Node3D
var _buttons: Dictionary = {}
var _tracked_player: Player
var _player_turn_active := false
var _battle_mode := false
var _battle_previous_turn_state := false
var _moved_callable: Callable
var _movement_started_callable: Callable
var _player_ready_after_battle_callable: Callable
var _tile_exit_callable: Callable
var _exit_connected_tile: Tile
var _finish_button: Button
var _camera_root: CameraDrag
var _camera: Camera3D
var _pending_tile: Tile

func _ready() -> void:
	add_to_group("ui_window_%s" % WINDOW_ID)
	set_process(true)
	_moved_callable = Callable(self, "_on_player_moved_to_tile")
	_movement_started_callable = Callable(self, "_on_player_movement_started")
	_player_ready_after_battle_callable = Callable(self, "_on_player_ready_after_battle")
	_tile_exit_callable = Callable(self, "_on_tile_exit_requested")
	_game_manager = NodeLocator.game_manager(get_tree())
	if not _game_manager:
		await get_tree().process_frame
		_game_manager = NodeLocator.game_manager(get_tree())
	if _game_manager:
		_connect_game_manager_signals()
		_connect_player_signals(_game_manager.active_player)
	_ensure_finish_button()
	_ensure_camera_nodes()

func _process(_delta: float) -> void:
	if not _room_ui_instance:
		return
	_ensure_camera_nodes()
	_update_room_ui_position()

func _connect_game_manager_signals() -> void:
	if not _game_manager:
		return
	var turn_started := Callable(self, "_on_player_turn_started")
	var turn_finished := Callable(self, "_on_player_turn_finished")
	var active_changed := Callable(self, "_on_active_player_changed")
	var ap_changed := Callable(self, "_on_action_points_changed")
	var post_battle := Callable(self, "_on_player_ready_after_battle")
	if not _game_manager.is_connected("new_player_started_moving", turn_started):
		_game_manager.connect("new_player_started_moving", turn_started)
	if not _game_manager.is_connected("player_turn_finished", turn_finished):
		_game_manager.connect("player_turn_finished", turn_finished)
	if not _game_manager.is_connected("active_player_changed", active_changed):
		_game_manager.connect("active_player_changed", active_changed)
	if not _game_manager.is_connected("active_player_action_points_changed", ap_changed):
		_game_manager.connect("active_player_action_points_changed", ap_changed)
	if not _game_manager.is_connected("player_ready_after_battle", post_battle):
		_game_manager.connect("player_ready_after_battle", post_battle)
	var trap_check := Callable(self, "_on_trap_check_completed")
	if not _game_manager.is_connected("trap_check_completed", trap_check):
		_game_manager.connect("trap_check_completed", trap_check)

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
	if player and player.current_tile and player.current_tile.room_type == Tile.RoomType.AMBUSH:
		player.current_tile.mark_trap_checked_for_player(player)
	if player and not player.is_moving:
		_update_exit_connection(player.current_tile)
		_request_room_ui_for_tile(player.current_tile)
	if player and player.current_tile and player.current_tile.room_type == Tile.RoomType.AMBUSH:
		# Do not trigger trap re-check as player started on trap
		_update_room_ui_buttons()

func _on_player_turn_finished(_player: Player) -> void:
	if _battle_mode:
		exit_battle_mode()
		return
	_player_turn_active = false
	_clear_room_ui()
	_disconnect_tile_exit()

func _on_active_player_changed(player: Player) -> void:
	_connect_player_signals(player)
	if not _player_turn_active:
		_clear_room_ui()

func _on_player_moved_to_tile(tile: Tile) -> void:
	if not _player_turn_active:
		return
	if tile and _tile_has_active_monster(tile) and _tracked_player:
		_close_room_ui_via_queue()
		if _game_manager and _game_manager.has_method("is_battle_active") and not _game_manager.is_battle_active():
			if _game_manager.has_method("start_monster_battle"):
				_game_manager.start_monster_battle(_tracked_player, tile.occupying_monster, true)
		return
	_update_exit_connection(tile)
	_request_room_ui_for_tile(tile)

func _on_player_movement_started() -> void:
	_close_room_ui_via_queue()

func _on_action_points_changed(_value: int) -> void:
	_update_room_ui_buttons()

func _on_finish_button_pressed() -> void:
	_close_room_ui_via_queue()


func bind_player_ui(instance: Node) -> void:
	if not instance:
		return
	_finish_button = instance.get_node_or_null("PanelRoot/ButtonFinish") as Button
	if _finish_button and not _finish_button.pressed.is_connected(Callable(self, "_on_finish_button_pressed")):
		_finish_button.pressed.connect(Callable(self, "_on_finish_button_pressed"))


func unbind_player_ui() -> void:
	_finish_button = null


func _ensure_finish_button() -> void:
	if _finish_button and is_instance_valid(_finish_button):
		return
	var parent := get_parent()
	if not parent:
		return
	var player_ui := parent.get_node_or_null("PlayerUI")
	if player_ui:
		_finish_button = player_ui.get_node_or_null("PanelRoot/ButtonFinish") as Button
		if _finish_button and not _finish_button.pressed.is_connected(Callable(self, "_on_finish_button_pressed")):
			_finish_button.pressed.connect(Callable(self, "_on_finish_button_pressed"))

func _show_room_ui_for_tile(tile: Tile) -> void:
	if not tile or not _player_turn_active:
		_close_room_ui_via_queue()
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
	_marker_target = tile.get_node_or_null("MarkerForRoomUI") as Node3D
	_initialize_room_ui(instance)
	_update_room_ui_buttons()
	_ensure_camera_nodes()
	_update_room_ui_position()

func _initialize_room_ui(instance: Control) -> void:
	_buttons.clear()
	var container_path := "ButtonsRoot/VBoxContainer"
	for name in ["ChestButton", "MonsterFightButton", "MonsterRunButton", "RoomExplore", "AmbushDisarm"]:
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
				"AmbushDisarm":
					button.pressed.connect(Callable(self, "_on_ambush_disarm_pressed"))

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
			var can_explore := _has_action_points(player) and not _is_button_active("ChestButton")
			_set_button_state("RoomExplore", can_explore)
		Tile.RoomType.EMPTY:
			_set_button_state("RoomExplore", _has_action_points(player))
	if _current_tile.room_type == Tile.RoomType.AMBUSH and _current_tile.ambush_ready_to_disarm and player and player.action_points > GameConfig.MIN_ACTION_POINTS:
		_set_button_state("AmbushDisarm", true)

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

func _is_button_active(name: String) -> bool:
	var button := _buttons.get(name, null) as Button
	return button and button.visible and not button.disabled

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
	_marker_target = null
	_buttons.clear()
	_disconnect_tile_exit()

func _get_active_player() -> Player:
	if not _game_manager:
		return null
	return _game_manager.active_player

func _on_player_ready_after_battle(player: Player) -> void:
	if not _player_turn_active:
		return
	if not player or player != _tracked_player:
		return
	_request_room_ui_for_tile(player.current_tile)

func _on_trap_check_completed(tile: Tile, success: bool) -> void:
	if not _player_turn_active:
		return
	if not tile or tile != _current_tile:
		return
	_update_room_ui_buttons()

func _on_room_explore_pressed() -> void:
	var player := _get_active_player()
	if not player:
		return
	if player.action_points <= GameConfig.MIN_ACTION_POINTS:
		return
	player.spend_action_point()
	_try_grant_explore_card(player)
	_update_room_ui_buttons()

func _on_chest_button_pressed() -> void:
	var player := _get_active_player()
	if player:
		if randf() < 0.5:
			player.add_action_point()
		else:
			_grant_card_to_player(player)
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
	if _game_manager and _game_manager.has_method("is_battle_active") and _game_manager.is_battle_active():
		if _game_manager.has_method("handle_battle_player_choice"):
			_game_manager.handle_battle_player_choice("fight", _current_tile)
		return
	_clear_room_ui()
	if _game_manager and _game_manager.has_method("start_monster_battle"):
		_game_manager.start_monster_battle(player, monster, true)

func _on_monster_run_pressed() -> void:
	var player := _get_active_player()
	if not player:
		return
	if _game_manager and _game_manager.has_method("is_battle_active") and _game_manager.is_battle_active():
		if _game_manager.has_method("handle_battle_player_choice"):
			_game_manager.handle_battle_player_choice("run", _current_tile)
		return
	# Running away hurts the player instead of costing action points.
	player.play_ambush_damage_animation()
	var died := player.take_damage(1)
	if _current_tile and _current_tile.has_method("_unlock_exits_for_monster"):
		_current_tile._unlock_exits_for_monster()
	_clear_room_ui()
	if died and _game_manager and _game_manager.has_method("handle_trap_player_death"):
		await _game_manager.handle_trap_player_death(player)

func _on_ambush_disarm_pressed() -> void:
	var player := _get_active_player()
	if not player or player.action_points <= GameConfig.MIN_ACTION_POINTS:
		return
	player.spend_action_point()
	if not _current_tile:
		return
	_current_tile.disarm_ambush()
	_update_room_ui_buttons()


func _grant_card_to_player(player: Player, animated := true) -> void:
	if not player:
		return
	if _game_manager and _game_manager.has_method("grant_card_to_player"):
		_game_manager.grant_card_to_player(player, null, animated)


func _try_grant_explore_card(player: Player) -> void:
	if randf() < 0.1:
		_grant_card_to_player(player)

func _update_exit_connection(tile: Tile) -> void:
	if _exit_connected_tile == tile:
		return
	_disconnect_tile_exit()
	if tile and tile.exit_clicked:
		tile.exit_clicked.connect(_tile_exit_callable)
		_exit_connected_tile = tile

func _disconnect_tile_exit() -> void:
	if _exit_connected_tile and _tile_exit_callable and _exit_connected_tile.exit_clicked.is_connected(_tile_exit_callable):
		_exit_connected_tile.exit_clicked.disconnect(_tile_exit_callable)
	_exit_connected_tile = null

func _on_tile_exit_requested(_tile: Tile, _dir: Vector2i) -> void:
	if not _player_turn_active:
		return
	_close_room_ui_via_queue()

func _ensure_camera_nodes() -> void:
	if _camera_root and is_instance_valid(_camera_root):
		if not _camera and _camera_root.camera:
			_camera = _camera_root.camera
		return
	_camera_root = NodeLocator.camera_root(self)
	if _camera_root:
		_camera = _camera_root.camera

func _update_room_ui_position() -> void:
	if not _room_ui_instance or not _marker_target or not _camera:
		return
	var viewport := get_viewport()
	if not viewport:
		_room_ui_instance.visible = false
		return
	var visible_rect := viewport.get_visible_rect()
	if visible_rect.size == Vector2.ZERO:
		_room_ui_instance.visible = false
		return
	if not _is_camera_preset_zero():
		_room_ui_instance.visible = false
		return
	var world_pos := _marker_target.global_transform.origin
	if _camera.is_position_behind(world_pos):
		_room_ui_instance.visible = false
		return
	var screen_pos := _camera.unproject_position(world_pos)
	if not visible_rect.has_point(screen_pos):
		_room_ui_instance.visible = false
		return
	_room_ui_instance.visible = true
	_room_ui_instance.global_position = screen_pos - _room_ui_instance.pivot_offset

func _is_camera_preset_zero() -> bool:
	return not _camera_root or _camera_root.zoom_level == 0


func enter_battle_mode(player: Player) -> void:
	_battle_mode = true
	_battle_previous_turn_state = _player_turn_active
	_player_turn_active = true
	_connect_player_signals(player)
	if player and not player.is_moving:
		_update_exit_connection(player.current_tile)
		_request_room_ui_for_tile(player.current_tile)


func exit_battle_mode() -> void:
	if not _battle_mode:
		return
	_close_room_ui_via_queue()
	_player_turn_active = _battle_previous_turn_state
	_battle_mode = false


func hide_room_ui() -> void:
	_clear_room_ui()

# UIWindowQueue integration
func prepare(params: Dictionary) -> void:
	_pending_tile = params.get("tile", null)


func ensure_shown() -> void:
	if _pending_tile:
		_show_room_ui_for_tile(_pending_tile)
		_pending_tile = null
	elif _current_tile:
		_show_room_ui_for_tile(_current_tile)


func show_room_ui() -> void:
	ensure_shown()


func _request_room_ui_for_tile(tile: Tile) -> void:
	_pending_tile = tile
	var queue := _queue()
	if queue and queue.has_method("request_window"):
		var handle: Dictionary = queue.request_window(WINDOW_ID, {"tile": tile}, 3)
		# Если очередь не смогла показать окно (например, из-за конкуренции с другими окнами),
		# пробуем показать напрямую, чтобы RoomUI не зависела от PlayerUI.
		if handle.get("status", "") == "FAILED":
			_show_room_ui_for_tile(tile)
		return
	_show_room_ui_for_tile(tile)


func _close_room_ui_via_queue() -> void:
	var queue := _queue()
	if queue and queue.has_method("close_window"):
		queue.close_window(WINDOW_ID)
	else:
		_clear_room_ui()


func _queue() -> Node:
	return get_tree().root.get_node_or_null("UIWindowQueue")
