extends Node3D
class_name GameManager

signal active_player_changed(new_player: Player)
signal active_player_action_points_changed(new_value: int)
signal new_player_started_moving(new_player: Player)
signal player_turn_finished(player: Player)
signal gameplay_started
signal battle_state_changed(active: bool)
signal player_ready_after_battle(player: Player)
signal trap_check_completed(tile: Tile, success: bool)

const GameConfig = preload("res://scripts/core/GameConfig.gd")
const NodeLocator = preload("res://scripts/core/NodeLocator.gd")
const DiceGameUI = preload("res://scripts/ui/DiceGameUI.gd")
const MonsterManager = preload("res://scripts/core/MonsterManager.gd")
const TurnStateMachine = preload("res://scripts/turns/TurnStateMachine.gd")
const BattleStateMachine = preload("res://scripts/battle/BattleStateMachine.gd")
const BATTLE_UI_SCENE_PATH := "res://scenes/ui/BattleUI.tscn"
const Tile = preload("res://scripts/core/Tile.gd")
enum GameState { INIT, INTRO, DRAW_LOTS, DAY, BATTLE, SWITCHING_TURN, NIGHT, WAITING_NEW_DAY }
const INTRO_SCENE_PATH := "res://scenes/ui/IntroCutScene.tscn"
const DICE_GAME_UI_SCENE_PATH := "res://scenes/ui/DiceGameUI.tscn"
const BONUS_TYPE_DICE := "Dice"
const BONUS_TYPE_LVL := "LVL"
const DEFAULT_CARD_DATA := {"cost": 1}

@export var total_players: int = 3
@export var intro_scene: PackedScene = preload(INTRO_SCENE_PATH)
@export var dice_game_ui_scene: PackedScene = preload(DICE_GAME_UI_SCENE_PATH)
@export var battle_ui_scene: PackedScene = preload(BATTLE_UI_SCENE_PATH)

var current_game_day: int = 1
var players: Array[Player] = []
var active_player: Player
var _active_player_index: int = -1
var _intro_instance: IntroCutSceneController
var _intro_started := false
var _intro_completed := false
var state: GameState = GameState.INIT : set = _set_state, get = _get_state
var _dice_ui_instance
var _battle_ui_instance
var _turn_state_machine: TurnStateMachine
var _battle_state_machine: BattleStateMachine
var _battle_in_progress := false
var _battle_ctx: Dictionary = {}
var _battle_choice_tile: Tile
var _hand_ui: HandUI
var _player_ui_allowed := false
var _turn_service
var _player_service
var _state_machine
var _state_internal: GameState = GameState.INIT
var _camera_service
var _input_service

@onready var player_ui := get_node_or_null("../UI/PlayerUI")
@onready var hud_ui := get_node_or_null("../UI/HUD(cheats)")
@onready var ui_layer: CanvasLayer = get_node_or_null("../UI") as CanvasLayer
@onready var main_hud: Node = get_node_or_null("../UI/MainHUD")
@onready var level_manager: LevelManager = get_node_or_null("../LevelManager") as LevelManager
@onready var player_manager: PlayerManager = get_node_or_null("../PlayerManager") as PlayerManager
@onready var monster_manager: MonsterManager = get_node_or_null("../MonsterManager") as MonsterManager
@onready var camera_root: CameraDrag = get_node_or_null("../CameraRoot") as CameraDrag
@onready var camera_pivot: Node3D = camera_root.get_node_or_null("CameraPivot") if camera_root else null
@onready var main_camera: Camera3D = camera_pivot.get_node_or_null("Camera3D") if camera_pivot else null
@onready var room_ui_controller: Node = get_node_or_null("../UI/RoomUIController")

func _ready() -> void:
	add_to_group("game_manager")
	_turn_service = get_tree().root.get_node_or_null("TurnService")
	_player_service = get_tree().root.get_node_or_null("PlayerService")
	_state_machine = get_tree().root.get_node_or_null("GameStateMachine")
	_camera_service = get_tree().root.get_node_or_null("CameraService")
	_input_service = get_tree().root.get_node_or_null("InputService")
	_sync_state_machine()
	_update_day_label()
	await get_tree().process_frame
	_prepare_initial_ui_state()
	_init_turn_state_machine()
	_init_battle_state_machine()


func _init_turn_state_machine() -> void:
	"""Создаёт FSM для управления ходами и связывает её с менеджером."""
	if _turn_state_machine:
		return
	_turn_state_machine = TurnStateMachine.new()
	add_child(_turn_state_machine)
	_turn_state_machine.set_dependencies({
		"get_monster_on_tile": Callable(self, "_get_monster_on_tile"),
		"can_player_act_again": Callable(self, "_can_player_act_again"),
		"get_next_player": Callable(self, "_get_next_player"),
		"set_active_player": Callable(self, "set_active_player"),
		"handle_prepare_end_turn": Callable(self, "_handle_prepare_end_turn"),
		"wait_player_ui_hidden": Callable(self, "_wait_player_ui_hidden"),
		"dispose_player_ui": Callable(self, "_dispose_player_ui"),
		"wait_camera_centering_done": Callable(self, "_wait_for_camera_centering_done")
	})
	_turn_state_machine.connect("request_camera_center", Callable(self, "_on_turn_request_camera_center"))
	_turn_state_machine.connect("show_player_ui", Callable(self, "_on_turn_show_player_ui"))
	_turn_state_machine.connect("hide_player_ui", Callable(self, "_on_turn_hide_player_ui"))
	_turn_state_machine.connect("enable_player_input", Callable(self, "_on_turn_enable_player_input"))
	_turn_state_machine.connect("disable_player_input", Callable(self, "_on_turn_disable_player_input"))
	_turn_state_machine.connect("start_combat", Callable(self, "_on_turn_start_combat"))
	_turn_state_machine.connect("state_changed", Callable(self, "_on_turn_state_changed"))
	_turn_state_machine.connect("turns_completed", Callable(self, "_on_turns_completed"))


func _init_battle_state_machine() -> void:
	if _battle_state_machine:
		return
	_battle_state_machine = BattleStateMachine.new()
	add_child(_battle_state_machine)
	_battle_state_machine.set_dependencies({
		"show_battle_ui": Callable(self, "_dep_show_battle_ui"),
		"hide_battle_ui": Callable(self, "_dep_hide_battle_ui"),
		"hide_player_ui": Callable(self, "_hide_player_ui"),
		"show_player_ui": Callable(self, "_show_player_ui"),
		"enter_battle_room_ui": Callable(self, "_dep_enter_battle_room_ui"),
		"exit_battle_room_ui": Callable(self, "_dep_exit_battle_room_ui"),
		"disable_player_input": Callable(self, "_dep_disable_player_input"),
		"enable_player_input": Callable(self, "_dep_enable_player_input"),
		"play_camera_hit": Callable(self, "_dep_play_camera_hit"),
		"run_dice_game": Callable(self, "_dep_run_dice_game"),
		"apply_player_damage": Callable(self, "_dep_apply_player_damage"),
		"apply_run_penalty": Callable(self, "_apply_run_away_penalty"),
		"handle_monster_death": Callable(self, "_handle_monster_defeat"),
		"handle_player_death": Callable(self, "_process_player_death"),
		"finalize_battle": Callable(self, "_dep_finalize_battle")
	})
	_battle_state_machine.connect("state_changed", Callable(self, "_on_battle_state_changed"))
	_battle_state_machine.connect("battle_finished", Callable(self, "_on_battle_finished"))

func _prepare_initial_ui_state() -> void:
	if ui_layer:
		ui_layer.visible = false
	_hide_player_ui()
	if main_hud:
		main_hud.visible = false
	if hud_ui:
		hud_ui.visible = true


func _ui_window_queue() -> Node:
	var tree := get_tree()
	if not tree:
		return null
	return tree.root.get_node_or_null("UIWindowQueue")


func _notify_player_ui_bound(instance: Node) -> void:
	if not instance:
		return
	var ui_root: Node = ui_layer if ui_layer else get_node_or_null("../UI")
	if not ui_root:
		return
	var cheats_ui := ui_root.get_node_or_null("HUD(cheats)")
	if cheats_ui and cheats_ui.has_method("bind_player_ui"):
		cheats_ui.call("bind_player_ui", instance)
	var room_controller := ui_root.get_node_or_null("RoomUIController")
	if room_controller and room_controller.has_method("bind_player_ui"):
		room_controller.call("bind_player_ui", instance)


func _notify_player_ui_unbound() -> void:
	var ui_root: Node = ui_layer if ui_layer else get_node_or_null("../UI")
	if not ui_root:
		return
	var cheats_ui := ui_root.get_node_or_null("HUD(cheats)")
	if cheats_ui and cheats_ui.has_method("unbind_player_ui"):
		cheats_ui.call("unbind_player_ui")
	var room_controller := ui_root.get_node_or_null("RoomUIController")
	if room_controller and room_controller.has_method("unbind_player_ui"):
		room_controller.call("unbind_player_ui")


func _ensure_hand_ui() -> HandUI:
	if _hand_ui and is_instance_valid(_hand_ui):
		return _hand_ui
	if not player_ui or not is_instance_valid(player_ui):
		player_ui = get_node_or_null("../UI/PlayerUI")
	if player_ui and is_instance_valid(player_ui) and player_ui.has_method("get_hand_ui"):
		_hand_ui = player_ui.get_hand_ui()
	_connect_hand_signals()
	return _hand_ui


func _connect_hand_signals() -> void:
	if not _hand_ui:
		return
	if not _hand_ui.card_added.is_connected(_on_hand_card_added):
		_hand_ui.card_added.connect(_on_hand_card_added)
	if not _hand_ui.card_played.is_connected(_on_hand_card_played):
		_hand_ui.card_played.connect(_on_hand_card_played)


func _persist_active_player_hand() -> void:
	if not active_player:
		return
	var hand := _ensure_hand_ui()
	if not hand:
		return
	active_player.cards = hand.get_cards_data()


func _refresh_player_cards_display(animated := false) -> void:
	var hand := _ensure_hand_ui()
	if not hand:
		return
	if not active_player:
		hand.clear_cards(animated)
		return
	var stored_cards: Array = []
	if active_player.cards != null:
		stored_cards = active_player.cards
	hand.set_cards_data(_duplicate_cards_array(stored_cards), animated)


func grant_card_to_player(player: Player, card_data = null, animated := true) -> void:
	if not player:
		return
	var payload: Variant = card_data if card_data != null else _default_card_data()
	var stored: Variant = _duplicate_card_data(payload)
	if player.cards == null:
		player.cards = []
	player.cards.append(_duplicate_card_data(stored))
	if player == active_player:
		var hand := _ensure_hand_ui()
		if hand:
			hand.add_card(_duplicate_card_data(payload), animated)


func _default_card_data():
	return DEFAULT_CARD_DATA.duplicate(true)


func _duplicate_cards_array(source: Array) -> Array:
	var result: Array = []
	for entry in source:
		result.append(_duplicate_card_data(entry))
	return result


func _duplicate_card_data(data: Variant) -> Variant:
	if data is Dictionary:
		return (data as Dictionary).duplicate(true)
	return data


func _on_hand_card_added(_card) -> void:
	_persist_active_player_hand()


func _on_hand_card_played(_card_data) -> void:
	_persist_active_player_hand()

func _log_state(label: String) -> void:
	print("Game state: %s" % label)


func _log_battle_state(label: String) -> void:
	print("CurrentBattleState: %s" % label)


func _on_battle_state_changed(label: String, _ctx: Dictionary) -> void:
	_log_battle_state(label)


func _on_battle_finished(result_ctx: Dictionary) -> void:
	await _finish_battle(result_ctx)

# Turn state machine helpers --------------------------------------------------

func _get_monster_on_tile(player: Player) -> Monster:
	if not player or not player.current_tile:
		return null
	return player.current_tile.occupying_monster

func _can_player_act_again(player: Player) -> bool:
	if not player:
		return false
	if player.has_method("can_act_again"):
		return bool(player.call("can_act_again"))
	return player.action_points > GameConfig.MIN_ACTION_POINTS

func _get_next_player(player: Player) -> Player:
	if not player:
		return null
	var index := players.find(player)
	if index == -1:
		return null
	var next_index := index + 1
	if next_index >= players.size():
		return null
	return players[next_index]

func _handle_prepare_end_turn(player: Player) -> void:
	"""Вызывается перед завершением хода, чтобы изменить глобальный статус."""
	state = GameState.SWITCHING_TURN
	if player:
		emit_signal("player_turn_finished", player)

func _on_turn_request_camera_center(player: Player) -> void:
	if not _turn_state_machine:
		return
	if not player or not player.current_tile:
		_turn_state_machine.handle_event("camera_centered", player)
		return
	await _focus_camera_on_player(player)
	_turn_state_machine.handle_event("camera_centered", player)

func _on_turn_show_player_ui(player: Player) -> void:
	_player_ui_allowed = true
	_show_player_ui(true)

func _on_turn_hide_player_ui() -> void:
	_player_ui_allowed = false
	_hide_player_ui()

func _on_turn_enable_player_input(player: Player) -> void:
	_set_player_input_enabled(true)

func _on_turn_disable_player_input() -> void:
	_set_player_input_enabled(false)

func _set_player_input_enabled(enabled: bool) -> void:
	if not camera_root:
		camera_root = _find_camera_root()
	if camera_root:
		camera_root.set_input_enabled(enabled)

func _on_turn_start_combat(player: Player, monster: Monster) -> void:
	if player and monster:
		# FSM вызывает бой, GameManager отвечает за запуск матч-логики и возврат в DAY.
		await start_monster_battle(player, monster)

func _on_turn_state_changed(label: String, player: Player) -> void:
	_log_state("turn %s (%s)" % [label, player.name if player else "none"])
	if label == "PlayerTurn":
		# Как только игрок готов к действию, возвращаемся в дневной режим и обновляем UI.
		state = GameState.DAY
		emit_signal("new_player_started_moving", player)
	elif label == "PrepareTurn":
		# Начинаем подготовку, чтобы не оставаться в режиме переключения между ходами.
		state = GameState.DAY
	elif label == "EndTurn" and not player:
		state = GameState.DAY

func _on_turns_completed() -> void:
	if _turn_state_machine:
		_turn_state_machine.stop()
	await _start_night_cycle()

func game_loaded_full() -> void:
	if state != GameState.INIT:
		return
	state = GameState.INTRO
	_log_state("загрузка")
	start_intro()

func start_intro() -> void:
	if _intro_started:
		return
	state = GameState.INTRO
	_intro_started = true
	_log_state("кат сцена")
	_prepare_intro_ui()
	_prepare_intro_camera()
	if _start_intro_via_queue():
		return
	_spawn_intro_cutscene()
	if _intro_instance:
		_intro_instance.ensure_camera_current()
		_intro_instance.reset_to_start()
		if not _intro_instance.intro_animation_finished.is_connected(_on_intro_cutscene_finished):
			_intro_instance.intro_animation_finished.connect(_on_intro_cutscene_finished, Object.CONNECT_ONE_SHOT)
		_intro_instance.play_intro()
	else:
		intro_finished()

func _prepare_intro_ui() -> void:
	if ui_layer:
		ui_layer.visible = true
	_hide_player_ui()
	if main_hud:
		main_hud.visible = false
	if hud_ui:
		hud_ui.visible = true

func _prepare_intro_camera() -> void:
	_ensure_camera_nodes()
	if camera_root:
		camera_root.set_follow_enabled(false)
		camera_root.sync_targets_to_current()
		_center_game_camera(camera_root)
		camera_root.set_input_enabled(false)
	if main_camera:
		main_camera.current = false

func _center_game_camera(target_root: Node3D) -> void:
	if not target_root:
		return
	var current_height := target_root.global_position.y
	target_root.global_position = Vector3(0, current_height, 0)

func _spawn_intro_cutscene() -> void:
	if _intro_instance:
		return
	var scene_to_use := intro_scene
	if not scene_to_use:
		scene_to_use = preload(INTRO_SCENE_PATH)
	if not scene_to_use:
		return
	var instance := scene_to_use.instantiate() as IntroCutSceneController
	if not instance:
		return
	_intro_instance = instance
	get_parent().add_child(instance)


func _start_intro_via_queue() -> bool:
	var queue := _ui_window_queue()
	if not queue or not queue.has_method("request_window"):
		return false
	var handle = queue.request_window("INTRO_CUTSCENE", {}, 1)
	if handle.get("status", "") == "FAILED":
		return false
	var instance: Node = handle.get("instance", null)
	if not instance:
		return true
	if instance.has_method("intro_animation_finished"):
		var signal_obj = instance
		if signal_obj and signal_obj.has_signal("intro_animation_finished") and not signal_obj.intro_animation_finished.is_connected(_on_intro_cutscene_finished):
			signal_obj.intro_animation_finished.connect(_on_intro_cutscene_finished, Object.CONNECT_ONE_SHOT)
	return true

func _on_intro_cutscene_finished() -> void:
	intro_finished()

func intro_finished() -> void:
	if _intro_completed:
		return
	_intro_completed = true
	if state == GameState.INTRO:
		state = GameState.INIT
	_ensure_camera_nodes()
	_transfer_cutscene_camera_to_main()
	_cleanup_intro_scene()
	if ui_layer:
		ui_layer.visible = true
	if main_camera:
		main_camera.current = true

func _transfer_cutscene_camera_to_main() -> void:
	var target_root := _find_camera_root()
	if not target_root:
		return
	if _intro_instance:
		var state := _intro_instance.get_camera_state()
		var pivot_transform: Transform3D = state.get("pivot_transform", target_root.global_transform)
		var root_position: Vector3 = state.get("root_position", target_root.global_position)
		var fov_value: float = state.get("fov", main_camera.fov if main_camera else 60.0)
		target_root.apply_external_camera_state(root_position, pivot_transform, fov_value)
	if main_camera:
		main_camera.current = true
	target_root.sync_targets_to_current()
	target_root.set_follow_enabled(false)

func _cleanup_intro_scene() -> void:
	if _intro_instance:
		_intro_instance.queue_free()
	_intro_instance = null

func _ensure_camera_nodes() -> void:
	if not camera_root:
		camera_root = _find_camera_root()
	if camera_root and not camera_pivot:
		camera_pivot = camera_root.get_node_or_null("CameraPivot") as Node3D
	if camera_pivot and not main_camera:
		main_camera = camera_pivot.get_node_or_null("Camera3D") as Camera3D

func _show_core_ui() -> void:
	if ui_layer:
		ui_layer.visible = true
	if main_hud:
		main_hud.visible = true
	if hud_ui:
		hud_ui.visible = true
	_update_day_label()

func _show_game_ui() -> void:
	_show_core_ui()
	_show_player_ui()

func game_started() -> void:
	if state == GameState.DAY or state == GameState.DRAW_LOTS or state == GameState.NIGHT:
		return
	if _intro_started and not _intro_completed:
		intro_finished()
		if state == GameState.DAY:
			return
	if not _intro_completed:
		return
	state = GameState.DRAW_LOTS
	_log_state("начало игры")
	_ensure_camera_nodes()
	_show_core_ui()
	emit_signal("gameplay_started")
	await _start_draw_lots(false)

func register_player(player: Player) -> void:
	if not player:
		return
	if players.has(player):
		return
	players.append(player)
	if _turn_service:
		_turn_service.register_player(player)
	if _player_service:
		_player_service.register_player(player)
	player.add_to_group("player")
	player.set_active(false)

func request_player_finish_turn() -> void:
	"""Вызывается, когда игрок завершает ход из UI."""
	if not _turn_state_machine:
		return
	_turn_state_machine.handle_event("player_requested_finish")

func all_players_finished_moving() -> void:
	await _start_night_cycle()

func _start_first_day() -> void:
	await _start_day_cycle(false)

func start_new_day() -> void:
	await _start_day_cycle(true)

func set_active_player(player: Player) -> void:
	if not player:
		return
	var index := players.find(player)
	if index == -1:
		return
	_persist_active_player_hand()
	if active_player == player:
		_active_player_index = index
		_refresh_player_cards_display()
		_refresh_player_display()
		return
	if active_player:
		_disconnect_active_player_signals(active_player)
		active_player.set_active(false)
	active_player = player
	_active_player_index = index
	if _turn_service:
		_turn_service.set_active_player(player)
	active_player.set_active(true)
	_connect_active_player_signals()
	_on_active_player_action_points_changed(active_player.action_points)
	_refresh_player_health_display()
	_refresh_player_cards_display()
	emit_signal("active_player_changed", active_player)

func _clear_active_player() -> void:
	_persist_active_player_hand()
	if active_player:
		_disconnect_active_player_signals(active_player)
		active_player.set_active(false)
	active_player = null
	_active_player_index = -1
	if _turn_service:
		_turn_service.clear_active_player()
	if _hand_ui:
		_hand_ui.clear_cards(false)
	emit_signal("active_player_changed", active_player)

func _connect_active_player_signals() -> void:
	if not active_player:
		return
	if not active_player.action_points_changed.is_connected(_on_active_player_action_points_changed):
		active_player.action_points_changed.connect(_on_active_player_action_points_changed)
	if not active_player.health_changed.is_connected(_on_active_player_health_changed):
		active_player.health_changed.connect(_on_active_player_health_changed)
	if not active_player.level_changed.is_connected(_on_active_player_level_changed):
		active_player.level_changed.connect(_on_active_player_level_changed)

func _disconnect_active_player_signals(player: Player) -> void:
	if not player:
		return
	if player.action_points_changed.is_connected(_on_active_player_action_points_changed):
		player.action_points_changed.disconnect(_on_active_player_action_points_changed)
	if player.health_changed.is_connected(_on_active_player_health_changed):
		player.health_changed.disconnect(_on_active_player_health_changed)
	if player.level_changed.is_connected(_on_active_player_level_changed):
		player.level_changed.disconnect(_on_active_player_level_changed)

func _on_active_player_action_points_changed(new_value: int) -> void:
	emit_signal("active_player_action_points_changed", new_value)

func _on_active_player_health_changed(new_value: int, old_value: int) -> void:
	if not player_ui or not is_instance_valid(player_ui):
		player_ui = get_node_or_null("../UI/PlayerUI")
	if not player_ui or not is_instance_valid(player_ui):
		return
	if not player_ui.is_inside_tree():
		return
	var loss := old_value - new_value
	if loss > 0:
		player_ui.queue_hp_loss_animation(loss, new_value)
		return
	player_ui.set_health_icons(new_value)
	player_ui.reset_pending_hp_loss()

func _on_active_player_level_changed(new_level: int) -> void:
	_refresh_player_level_display()

func _refill_player_action_points() -> void:
	for player in players:
		if player.has_method("reset_for_new_day"):
			player.reset_for_new_day()
		player.refill_action_points()

func _revive_dead_players_for_new_day() -> void:
	for player in players:
		if not player:
			continue
		if player.pending_respawn:
			player.respawn_to_start_tile()
			player.pending_respawn = false

func _show_player_ui(force: bool = false) -> void:
	if not force and not _player_ui_allowed:
		return
	var queue := _ui_window_queue()
	var handled_via_queue := false
	if queue and queue.has_method("request_window"):
		var handle = queue.request_window("PLAYER_UI")
		if handle.has("instance") and handle.instance:
			player_ui = handle.instance
		if handle.get("status", "") != "FAILED":
			handled_via_queue = true
	if not player_ui or not is_instance_valid(player_ui):
		player_ui = get_node_or_null("../UI/PlayerUI")
	if player_ui and not is_instance_valid(player_ui):
		player_ui = null
	if not player_ui and not handled_via_queue:
		var fallback_scene: PackedScene = load("res://scenes/ui/PlayerUI.tscn") as PackedScene
		if fallback_scene:
			var parent_node: Node = ui_layer if ui_layer else self
			player_ui = fallback_scene.instantiate()
			if parent_node and player_ui:
				parent_node.add_child(player_ui)
	if player_ui and is_instance_valid(player_ui):
		_notify_player_ui_bound(player_ui)
		_refresh_player_display()
	if handled_via_queue:
		return
	if player_ui and is_instance_valid(player_ui):
		var should_ensure := false
		if player_ui.has_method("get_animation_player"):
			var ap = player_ui.call("get_animation_player")
			if ap and ap.has_method("is_playing") and ap.is_playing() and ap.current_animation == "PlayerUI_Hide":
				should_ensure = true
		if player_ui.visible and not should_ensure:
			return
		if player_ui.has_method("ensure_shown"):
			player_ui.ensure_shown()
		else:
			player_ui.show_player_ui()

func _hide_player_ui() -> void:
	var queue := _ui_window_queue()
	if queue and queue.has_method("close_window"):
		queue.close_window("PLAYER_UI")
	if not player_ui or not is_instance_valid(player_ui):
		player_ui = get_node_or_null("../UI/PlayerUI")
	if player_ui and is_instance_valid(player_ui) and player_ui.visible:
		player_ui.hide_player_ui()


func _dispose_player_ui() -> void:
	_player_ui_allowed = false
	_hide_player_ui()
	await _wait_player_ui_hidden()
	if player_ui and is_instance_valid(player_ui):
		if player_ui.is_inside_tree():
			player_ui.queue_free()
	player_ui = null
	_hand_ui = null
	_notify_player_ui_unbound()

func _restore_player_ui_if_hidden(should_restore: bool) -> void:
	if should_restore and _player_ui_allowed:
		_show_player_ui()


func _hide_room_ui() -> void:
	var queue := _ui_window_queue()
	if queue and queue.has_method("close_window"):
		queue.close_window("ROOM_UI")
	elif room_ui_controller and room_ui_controller.has_method("hide_room_ui"):
		room_ui_controller.call("hide_room_ui")

func _update_day_label() -> void:
	if not hud_ui:
		hud_ui = get_node_or_null("../UI/HUD(cheats)")
	if hud_ui and hud_ui.has_method("set_day_label"):
		hud_ui.set_day_label(current_game_day)

func _refresh_player_display() -> void:
	if not player_manager:
		player_manager = get_node_or_null("../PlayerManager")
	if player_manager and player_manager.has_method("update_active_player_display"):
		player_manager.call("update_active_player_display", active_player)
	_refresh_player_health_display()
	_refresh_player_level_display()
	_refresh_player_cards_display()

func _refresh_player_health_display() -> void:
	if not player_ui or not is_instance_valid(player_ui):
		player_ui = get_node_or_null("../UI/PlayerUI")
	if not player_ui or not is_instance_valid(player_ui) or not active_player:
		return
	player_ui.set_health_icons(active_player.health_points)
	player_ui.reset_pending_hp_loss()
	_refresh_player_level_display()

func _refresh_player_level_display() -> void:
	if not player_ui or not is_instance_valid(player_ui):
		player_ui = get_node_or_null("../UI/PlayerUI")
	if not player_ui or not is_instance_valid(player_ui) or not active_player:
		return
	if player_ui.has_method("set_level"):
		player_ui.set_level(active_player.level)

func _find_camera_root() -> CameraDrag:
	if camera_root:
		return camera_root
	var found := NodeLocator.camera_root(self)
	if found and not camera_root:
		camera_root = found
	return found

func _focus_camera_on_player(player: Player) -> void:
	"""Фокусирует камеру на конкретном игроке и ждёт завершения движения."""
	if not player or not player.current_tile:
		return
	var target_root := _find_camera_root()
	if not target_root:
		return
	if target_root.has_method("stop_auto_centering"):
		target_root.stop_auto_centering()
	var tween := target_root.focus_on_tile(
		player.current_tile,
		GameConfig.CAMERA_DELAY,
		GameConfig.CAMERA_MOVE_DURATION
	)
	if tween:
		await tween.finished

func _start_draw_lots(increment_day: bool) -> void:
	state = GameState.DRAW_LOTS
	_log_state("жеребьевка")
	_ensure_camera_nodes()
	await _focus_camera_on_red_tile()
	_show_core_ui()
	if main_hud:
		main_hud.visible = false
	_hide_player_ui()
	_clear_active_player()
	var results: Array = await _run_dice_lottery()
	_apply_turn_order_from_rolls(results)
	await _start_day_cycle(increment_day)

func _run_dice_lottery() -> Array:
	var players_data: Array = _build_lottery_player_data()
	if players_data.size() == 0:
		return []
	if not dice_game_ui_scene:
		return _generate_rolls_from_data(players_data, false)
	var ui_instance := dice_game_ui_scene.instantiate()
	if not ui_instance:
		return _generate_rolls_from_data(players_data, false)
	_dice_ui_instance = ui_instance
	var parent_node: Node = ui_layer if ui_layer else self
	parent_node.add_child(ui_instance)
	_hide_player_ui()
	var results: Array = await ui_instance.run_lottery(players_data)
	_apply_master_bonus(results, false)
	_dice_ui_instance = null
	_restore_player_ui_if_hidden(true)
	if results.size() == 0:
		return _generate_rolls_from_data(players_data, false)
	return results

func start_trap_check(player: Player, tile: Tile) -> void:
	if not player or not tile:
		return
	if tile._has_trap_been_checked_for_player(player):
		return
	var players_data: Array = []
	players_data.append(_build_participant_view_data(player, false))
	if players_data.size() == 0:
		return
	var results: Array = []
	if not dice_game_ui_scene:
		results = _generate_rolls_from_data(players_data, false)
		await _handle_trap_check_results(results, player, tile)
		return
	var ui_instance := dice_game_ui_scene.instantiate()
	if not ui_instance:
		results = _generate_rolls_from_data(players_data, false)
		await _handle_trap_check_results(results, player, tile)
		return
	_dice_ui_instance = ui_instance
	var parent_node: Node = ui_layer if ui_layer else self
	parent_node.add_child(ui_instance)
	_hide_player_ui()
	results = await ui_instance.run_lottery(players_data)
	_apply_master_bonus(results, false)
	_dice_ui_instance = null
	_restore_player_ui_if_hidden(true)
	if results.size() == 0:
		results = _generate_rolls_from_data(players_data, false)
	await _handle_trap_check_results(results, player, tile)

func _handle_trap_check_results(results: Array, player: Player, tile: Tile) -> void:
	var entry: Dictionary = {}
	var found_entry := false
	for item in results:
		if not (item is Dictionary):
			continue
		if item.get("player") != player:
			continue
		entry = item
		found_entry = true
		break
	if not found_entry:
		return
	var roll_value := int(entry.get("roll", 0))
	var success := roll_value >= 5
	if player:
		player.last_moved_tile = null
	if tile:
		tile.set_ambush_ready_to_disarm(success)
		tile.mark_trap_checked_for_player(player)
	emit_signal("trap_check_completed", tile, success)
	if success:
		return
	player.play_ambush_damage_animation()
	var died := player.take_damage(1)
	if died:
		await handle_trap_player_death(player)

func start_monster_battle(player: Player, monster: Monster, from_tile: bool = false) -> void:
	print("Битва с монстром")
	if not player or not monster:
		return
	if _battle_in_progress or state == GameState.BATTLE:
		return
	if state != GameState.DAY and state != GameState.SWITCHING_TURN:
		return
	if from_tile and player:
		player.mark_tile_combat_requested()
	_battle_ctx = {
		"player": player,
		"monster": monster,
		"from_tile": from_tile,
		"battle_type": "Обычный" if from_tile else "Внезапный",
		"player_roll": 0,
		"monster_roll": 0,
		"player_won_round": false,
		"player_died": false,
		"monster_defeated": false,
		"player_ran": false
	}
	_battle_choice_tile = player.current_tile
	_battle_in_progress = true
	emit_signal("battle_state_changed", true)
	state = GameState.BATTLE
	print("BattleType: %s" % _battle_ctx.get("battle_type", ""))
	if _battle_state_machine:
		await _battle_state_machine.start(_battle_ctx)
	else:
		_finish_battle(_battle_ctx)


func is_battle_active() -> bool:
	return _battle_in_progress


func handle_battle_player_choice(choice: String, tile: Tile = null) -> void:
	if not _battle_in_progress or not _battle_state_machine:
		return
	_battle_choice_tile = tile if tile else _battle_choice_tile
	_battle_state_machine.handle_event("player_choice", {"choice": choice, "tile": _battle_choice_tile})


func _dep_show_battle_ui(battle_type: String) -> void:
	_hide_room_ui()
	_ensure_camera_nodes()
	# Не ждём завершения центрирования — бой может стартовать сразу,
	# камера доедет сама.
	_set_player_input_enabled(false)
	if camera_root:
		camera_root.set_input_enabled(false)
	await _show_battle_ui(battle_type)


func _dep_hide_battle_ui() -> void:
	await _hide_battle_ui()


func _dep_enter_battle_room_ui(player: Player) -> void:
	if room_ui_controller and room_ui_controller.has_method("enter_battle_mode"):
		room_ui_controller.call("enter_battle_mode", player)


func _dep_exit_battle_room_ui() -> void:
	if room_ui_controller:
		if room_ui_controller.has_method("exit_battle_mode"):
			room_ui_controller.call("exit_battle_mode")
		if room_ui_controller.has_method("hide_room_ui"):
			room_ui_controller.call("hide_room_ui")


func _dep_disable_player_input() -> void:
	_set_player_input_enabled(false)


func _dep_enable_player_input(player: Player) -> void:
	_set_player_input_enabled(true)


func _dep_play_camera_hit(player_won: bool) -> void:
	await _play_camera_hit_animation(player_won)


func _dep_run_dice_game(player: Player, monster: Monster) -> Array:
	return await _run_monster_battle(player, monster)


func _dep_apply_player_damage(player: Player, amount: int) -> bool:
	if not player:
		return false
	return player.take_damage(amount)


func _dep_finalize_battle(result_ctx: Dictionary) -> void:
	_battle_ctx = result_ctx.duplicate(true)


func _finish_battle(result_ctx: Dictionary) -> void:
	var player: Player = result_ctx.get("player")
	var player_died := bool(result_ctx.get("player_died", false))
	var monster_defeated := bool(result_ctx.get("monster_defeated", false))
	var player_won := monster_defeated and not player_died
	if monster_defeated and player and not player_died:
		player.increase_level()
	state = GameState.DAY
	if camera_root:
		camera_root.set_follow_enabled(true)
	if player_died:
		_hide_player_ui()
		await _wait_player_ui_hidden()
	else:
		_set_player_input_enabled(true)
		if monster_defeated:
			_show_player_ui()
			await _wait_player_ui_shown()
			_refresh_player_cards_display()
			grant_card_to_player(player, null, true)
		if player:
			_battle_choice_tile = player.current_tile
		if player and (result_ctx.get("from_tile", false)) and monster_defeated:
			emit_signal("player_ready_after_battle", player)
	if player_died:
		_clear_active_player()
	if _turn_state_machine:
		var combat_result := {
			"result": "win" if player_won else "lose",
			"player_died": player_died
		}
		_turn_state_machine.handle_event("combat_resolved", combat_result)
		if player_died:
			_turn_state_machine.handle_event("player_death_animation_finished", player)
	if result_ctx.get("from_tile", false) and player:
		player.consume_tile_combat_request()
	_battle_in_progress = false
	emit_signal("battle_state_changed", false)
	_battle_ctx.clear()
	_battle_choice_tile = null


func _show_battle_ui(battle_type: String = "") -> void:
	if _battle_ui_instance and is_instance_valid(_battle_ui_instance):
		var anim_player := _battle_ui_instance.get_node_or_null("AnimationPlayer") as AnimationPlayer
		await _play_animation_safe(anim_player, "BattleShow")
		return
	var queue := _ui_window_queue()
	if queue and queue.has_method("request_window"):
		var handle = queue.request_window("BATTLE_UI", {"battle_type": battle_type}, 2)
		var instance: Node = handle.get("instance", null)
		if instance:
			_battle_ui_instance = instance
			var anim_player := instance.get_node_or_null("AnimationPlayer") as AnimationPlayer
			if anim_player and anim_player.has_animation("RESET"):
				anim_player.play("RESET")
			await _play_animation_safe(anim_player, "BattleShow")
			return
	# Fallback legacy instantiation
	var scene_to_use := battle_ui_scene
	if not scene_to_use:
		scene_to_use = preload(BATTLE_UI_SCENE_PATH)
	if not scene_to_use:
		return
	var instance := scene_to_use.instantiate()
	if not instance:
		return
	_battle_ui_instance = instance
	var parent_node: Node = ui_layer if ui_layer else self
	parent_node.add_child(instance)
	var anim_player := instance.get_node_or_null("AnimationPlayer") as AnimationPlayer
	if anim_player and anim_player.has_animation("RESET"):
		anim_player.play("RESET")
	await _play_animation_safe(anim_player, "BattleShow")


func _hide_battle_ui() -> void:
	if _battle_ui_instance and is_instance_valid(_battle_ui_instance):
		var anim_player := _battle_ui_instance.get_node_or_null("AnimationPlayer") as AnimationPlayer
		await _play_animation_safe(anim_player, "BattleHide")
	var queue := _ui_window_queue()
	if queue and queue.has_method("close_window"):
		queue.close_window("BATTLE_UI")
	_battle_ui_instance = null


func _play_animation_safe(anim_player: AnimationPlayer, anim_name: String) -> void:
	if not anim_player:
		return
	if not anim_player.has_animation(anim_name):
		return
	anim_player.play(anim_name)
	await anim_player.animation_finished


func _set_state(value: GameState) -> void:
	_state_internal = value
	_sync_state_machine()


func _get_state() -> GameState:
	return _state_internal


func _sync_state_machine() -> void:
	if _state_machine and _state_machine.has_method("set_state"):
		_state_machine.set_state(_state_internal)


func _play_camera_hit_animation(player_won: bool) -> void:
	_ensure_camera_nodes()
	if not camera_pivot:
		return
	var anim_player := camera_pivot.get_node_or_null("AnimationPlayer") as AnimationPlayer
	if not anim_player:
		return
	var anim_name := "PlayerHit" if player_won else "EnemyHIT"
	if anim_player.has_animation(anim_name):
		anim_player.play(anim_name)
		await anim_player.animation_finished
	if anim_player.has_animation("RESET"):
		anim_player.play("RESET")


func _apply_run_away_penalty(player: Player, tile: Tile) -> bool:
	if not player:
		return false
	player.play_ambush_damage_animation()
	var died := player.take_damage(1)
	if tile and tile.has_method("_unlock_exits_for_monster"):
		tile._unlock_exits_for_monster()
	return died


func _wait_for_camera_centering_done() -> void:
	if not camera_root:
		return
	var guard := 0
	while camera_root.is_centering_on_tile:
		await get_tree().process_frame
		guard += 1
		if guard > 120: # ~2 секунды при 60 fps, чтобы не зависнуть
			break


func _wait_player_ui_hidden() -> void:
	if not player_ui or not is_instance_valid(player_ui):
		player_ui = get_node_or_null("../UI/PlayerUI")
	if not player_ui or not is_instance_valid(player_ui):
		player_ui = null
		return
	var guard := 0
	while player_ui and is_instance_valid(player_ui) and player_ui.visible:
		await get_tree().process_frame
		guard += 1
		if guard > 120: # ~2 секунды при 60 fps
			break
	if player_ui and not is_instance_valid(player_ui):
		player_ui = null


func _wait_player_ui_shown() -> void:
	if not player_ui or not is_instance_valid(player_ui):
		player_ui = get_node_or_null("../UI/PlayerUI")
	if not player_ui or not is_instance_valid(player_ui):
		player_ui = null
		return
	if player_ui.has_method("wait_for_show_complete"):
		await player_ui.wait_for_show_complete()
		return
	var guard := 0
	while player_ui and is_instance_valid(player_ui) and not player_ui.visible:
		await get_tree().process_frame
		guard += 1
		if guard > 120:
			break
	if player_ui and not is_instance_valid(player_ui):
		player_ui = null

func _run_monster_battle(player: Player, monster: Monster) -> Array:
	var participants_data: Array = []
	participants_data.append(_build_battle_participant_data(player))
	participants_data.append(_build_battle_participant_data(monster))
	var queue := _ui_window_queue()
	if queue and queue.has_method("request_window"):
		var handle = queue.request_window("DICE_GAME_UI", {"participants": participants_data, "mode": "battle"}, 2)
		var instance = handle.get("instance", null)
		if instance and instance.has_method("run_battle"):
			_hide_player_ui()
			var results: Array = await instance.run_battle(participants_data)
			_apply_master_bonus(results, true)
			if queue.has_method("close_window"):
				queue.close_window("DICE_GAME_UI")
			_restore_player_ui_if_hidden(true)
			if results.size() == 0:
				return _generate_rolls_from_data(participants_data, true)
			return results
	# Fallback to legacy instantiation
	if not dice_game_ui_scene:
		return _generate_rolls_from_data(participants_data, true)
	var ui_instance := dice_game_ui_scene.instantiate()
	if not ui_instance:
		return _generate_rolls_from_data(participants_data, true)
	_dice_ui_instance = ui_instance
	var parent_node: Node = ui_layer if ui_layer else self
	parent_node.add_child(ui_instance)
	_hide_player_ui()
	var results: Array = []
	if ui_instance.has_method("run_battle"):
		results = await ui_instance.run_battle(participants_data)
		_apply_master_bonus(results, true)
		_dice_ui_instance = null
	else:
		results = _generate_rolls_from_data(participants_data, true)
		_dice_ui_instance = null
	_restore_player_ui_if_hidden(true)
	if ui_instance and ui_instance.is_inside_tree():
		ui_instance.queue_free()
	if results.size() == 0:
		return _generate_rolls_from_data(participants_data, true)
	return results

func _build_battle_participant_data(participant) -> Dictionary:
	if participant is Player or participant is Monster:
		return _build_participant_view_data(participant, true)
	return {"player": participant}

func _level_for_participant(participant) -> int:
	if not participant:
		return 0
	if participant is Player or participant is Monster:
		return int(participant.level)
	return 0

func _bonus_config(include_level: bool, participant) -> Array:
	var config: Array = []
	config.append({
		"type": BONUS_TYPE_DICE,
		"value": 0
	})
	if include_level:
		config.append({
			"type": BONUS_TYPE_LVL,
			"value": _level_for_participant(participant)
		})
	return config

func _build_participant_view_data(participant, include_level: bool) -> Dictionary:
	var icon_texture: Texture2D = null
	var icon_name: String = ""
	if participant is Player:
		var view_params: Dictionary = {}
		if player_manager:
			view_params = player_manager.get_view_params_for_player(participant)
			icon_texture = player_manager.get_icon_texture_for_player(participant)
		icon_name = view_params.get("CharIconName", "") as String
	elif participant is Monster:
		var params: Dictionary = monster_manager.get_default_view_params() if monster_manager else {}
		icon_name = params.get("MonsterIconName", "") as String
		if monster_manager:
			icon_texture = monster_manager.get_icon_texture_for_monster(participant)
		if not icon_texture and icon_name != "":
			var loaded := load("res://image/%s.png" % icon_name)
			if loaded is Texture2D:
				icon_texture = loaded
	else:
		return {"player": participant}

	var entry: Dictionary = {
		"player": participant,
		"icon_texture": icon_texture,
		"icon_name": icon_name
	}
	entry["bonuses"] = _bonus_config(include_level, participant)
	return entry

func _process_battle_outcome(results: Array, player: Player, monster: Monster) -> Dictionary:
	var player_roll := _extract_roll_for_participant(results, player)
	var monster_roll := _extract_roll_for_participant(results, monster)
	var player_master := _extract_master_bonus_for_participant(results, player)
	var monster_master := _extract_master_bonus_for_participant(results, monster)
	var player_won := player_master >= monster_master
	var player_died := false
	if player_won:
		await _handle_monster_defeat(monster)
	else:
		player_died = await _handle_player_defeat(player)
	return {"player_won": player_won, "player_died": player_died}

func _extract_roll_for_participant(results: Array, target) -> int:
	for entry in results:
		if not (entry is Dictionary):
			continue
		if entry.get("player") == target:
			return int(entry.get("roll", 0))
	return 0

func _extract_master_bonus_for_participant(results: Array, target) -> int:
	for entry in results:
		if not (entry is Dictionary):
			continue
		if entry.get("player") == target:
			return int(entry.get("master_bonus", entry.get("roll", 0)))
	return 0

func _handle_monster_defeat(monster: Monster) -> void:
	if not monster or not is_instance_valid(monster):
		return
	if monster.has_method("register_death"):
		monster.register_death()
	var animation_player := monster.get_node_or_null("AnimationPlayer") as AnimationPlayer
	if animation_player and animation_player.has_animation("Death"):
		animation_player.play("Death")
		await animation_player.animation_finished
	monster.despawn()

func _handle_player_defeat(player: Player) -> bool:
	if not player:
		return false
	var died := player.take_damage(1)
	if not died:
		return false
	await _process_player_death(player)
	return true

func handle_trap_player_death(player: Player) -> void:
	if not player or not _turn_state_machine:
		return
	await _process_player_death(player)
	var payload := {
		"result": "lose",
		"player_died": true
	}
	_turn_state_machine.handle_event("combat_resolved", payload)
	_turn_state_machine.handle_event("player_death_animation_finished", player)

func _process_player_death(player: Player) -> void:
	if not player or not is_instance_valid(player):
		return
	if player.has_method("register_death"):
		player.register_death()
	var animation_player := player.get_node_or_null("AnimationPlayer") as AnimationPlayer
	if animation_player and animation_player.has_animation("Death"):
		animation_player.play("Death")
		await animation_player.animation_finished
	if player.has_method("decrease_level"):
		player.decrease_level()

func _build_lottery_player_data() -> Array:
	var data: Array = []
	for i in range(players.size()):
		var player: Player = players[i]
		if not player:
			continue
		data.append(_build_participant_view_data(player, false))
	return data

func _generate_rolls_from_data(players_data: Array, include_level: bool = false) -> Array:
	var results: Array = []
	for entry in players_data:
		if not (entry is Dictionary):
			continue
		var participant = entry.get("player")
		if not participant:
			continue
		var roll_value := randi_range(1, 6)
		results.append({
			"player": participant,
			"roll": roll_value
		})
	_apply_master_bonus(results, include_level)
	return results

func _apply_turn_order_from_rolls(rolls: Array) -> void:
	if rolls.size() == 0:
		return
	var sorted_rolls := _sort_roll_results(rolls)
	var ordered_players: Array[Player] = []
	for entry in sorted_rolls:
		if not (entry is Dictionary):
			continue
		var player := entry.get("player") as Player
		if not player:
			continue
		var roll_value := int(entry.get("roll", 0))
		player.set_dice_roll(roll_value)
		ordered_players.append(player)
	if ordered_players.size() == 0:
		return
	players = ordered_players
	if _turn_service:
		_turn_service.set_players(players)
	if _player_service:
		_player_service.set_players(players)
	if player_manager and player_manager.has_method("reorder_portraits"):
		player_manager.reorder_portraits(players)
	_clear_active_player()

func _sort_roll_results(rolls: Array) -> Array:
	var enriched: Array = []
	for entry in rolls:
		if not (entry is Dictionary):
			continue
		enriched.append({
			"player": entry.get("player"),
			"roll": int(entry.get("roll", 0)),
			"master_bonus": int(entry.get("master_bonus", entry.get("roll", 0))),
			"tie": randf()
		})
	enriched.sort_custom(func(a, b):
		var bonus_a := int(a.get("master_bonus", a.get("roll", 0)))
		var bonus_b := int(b.get("master_bonus", b.get("roll", 0)))
		if bonus_a == bonus_b:
			return float(a.get("tie", 0.0)) > float(b.get("tie", 0.0))
		return bonus_a > bonus_b
	)
	return enriched

func _apply_master_bonus(results: Array, include_level: bool) -> void:
	for entry in results:
		if not (entry is Dictionary):
			continue
		var roll_value := int(entry.get("roll", 0))
		var master := roll_value
		if include_level:
			master += _level_for_participant(entry.get("player"))
		entry["master_bonus"] = master

func _start_day_cycle(increment_day: bool) -> void:
	state = GameState.DAY
	_log_state("игровой день")
	if increment_day:
		current_game_day += 1
	if _turn_service:
		_turn_service.set_current_day(current_game_day)
		_turn_service.set_players(players)
	_update_day_label()
	_refill_player_action_points()
	_revive_dead_players_for_new_day()
	_ensure_camera_nodes()
	if camera_root:
		camera_root.set_follow_enabled(true)
		camera_root.apply_zoom_preset(0, true)
		camera_root.set_input_enabled(true)
	_clear_active_player()
	if players.size() > 0:
		set_active_player(players[0])
		_show_core_ui()
		_hide_player_ui()
		# FSM самостоятельно подготовит игрока и камеры.
		if _turn_state_machine and active_player:
			_turn_state_machine.start_for_player(active_player)

func _start_night_cycle() -> void:
	state = GameState.NIGHT
	_log_state("ночь")
	_hide_player_ui()
	_clear_active_player()
	await _focus_camera_on_red_tile()
	if level_manager:
		await level_manager.move_monsters_at_night()
	if camera_root:
		camera_root.set_follow_enabled(false)
		camera_root.set_input_enabled(false)
	var timer := get_tree().create_timer(GameConfig.NIGHT_DELAY)
	await timer.timeout
	await _start_draw_lots(true)

func _focus_camera_on_red_tile() -> void:
	var target_root := _find_camera_root()
	if not target_root:
		return
	target_root.set_follow_enabled(false)
	target_root.set_input_enabled(false)
	var red_tile: Tile = _get_red_tile()
	if red_tile:
		var tween := target_root.focus_on_tile(
			red_tile,
			0.0,
			GameConfig.CAMERA_MOVE_DURATION
		)
		if tween:
			await tween.finished
	else:
		_center_game_camera(target_root)

func _get_red_tile() -> Tile:
	var manager := _find_level_manager()
	if not manager:
		return null
	return manager.tiles.get(manager.red_tile_pos, null) as Tile

func _find_level_manager() -> LevelManager:
	if level_manager:
		return level_manager
	var tree := get_tree()
	if tree:
		level_manager = NodeLocator.level_manager(tree)
	return level_manager
