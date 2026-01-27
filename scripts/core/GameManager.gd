extends Node3D
class_name GameManager

signal active_player_changed(new_player: Player)
signal active_player_action_points_changed(new_value: int)
signal new_player_started_moving(new_player: Player)
signal player_turn_finished(player: Player)
signal gameplay_started

const GameConfig = preload("res://scripts/core/GameConfig.gd")
const NodeLocator = preload("res://scripts/core/NodeLocator.gd")
const DiceGameUI = preload("res://scripts/ui/DiceGameUI.gd")
enum GameState { INIT, INTRO, DRAW_LOTS, DAY, SWITCHING_TURN, NIGHT, WAITING_NEW_DAY }
const INTRO_SCENE_PATH := "res://scenes/ui/IntroCutScene.tscn"
const DICE_GAME_UI_SCENE_PATH := "res://scenes/ui/DiceGameUI.tscn"

@export var total_players: int = 3
@export var intro_scene: PackedScene = preload(INTRO_SCENE_PATH)
@export var dice_game_ui_scene: PackedScene = preload(DICE_GAME_UI_SCENE_PATH)

var current_game_day: int = 1
var players: Array[Player] = []
var active_player: Player
var _active_player_index: int = -1
var _intro_instance: IntroCutSceneController
var _intro_started := false
var _intro_completed := false
var state: GameState = GameState.INIT
var _dice_ui_instance

@onready var player_ui := get_node_or_null("../UI/PlayerUI")
@onready var hud_ui := get_node_or_null("../UI/HUD(cheats)")
@onready var ui_layer: CanvasLayer = get_node_or_null("../UI") as CanvasLayer
@onready var main_hud: Node = get_node_or_null("../UI/MainHUD")
@onready var level_manager: LevelManager = get_node_or_null("../LevelManager") as LevelManager
@onready var player_manager: PlayerManager = get_node_or_null("../PlayerManager") as PlayerManager
@onready var camera_root: CameraDrag = get_node_or_null("../CameraRoot") as CameraDrag
@onready var camera_pivot: Node3D = camera_root.get_node_or_null("CameraPivot") if camera_root else null
@onready var main_camera: Camera3D = camera_pivot.get_node_or_null("Camera3D") if camera_pivot else null

func _ready() -> void:
	add_to_group("game_manager")
	_update_day_label()
	await get_tree().process_frame
	_prepare_initial_ui_state()

func _prepare_initial_ui_state() -> void:
	if ui_layer:
		ui_layer.visible = false
	_hide_player_ui()
	if main_hud:
		main_hud.visible = false
	if hud_ui:
		hud_ui.visible = true

func _log_state(label: String) -> void:
	print("Game state: %s" % label)

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
	player.add_to_group("player")
	player.set_active(false)

func current_player_finished_moving() -> void:
	if state != GameState.DAY or not active_player:
		return
	if active_player:
		emit_signal("player_turn_finished", active_player)
	state = GameState.SWITCHING_TURN
	_hide_player_ui()
	var timer := get_tree().create_timer(GameConfig.TURN_SWITCH_DELAY)
	await timer.timeout
	var moved := await _move_to_next_player()
	if moved:
		state = GameState.DAY
		return
	await _start_night_cycle()

func _move_to_next_player() -> bool:
	if players.size() == 0 or _active_player_index == -1:
		return false
	var next_index := _active_player_index + 1
	if next_index >= players.size():
		return false
	set_active_player(players[next_index])
	await _focus_camera_on_active_player()
	_show_player_ui()
	emit_signal("new_player_started_moving", active_player)
	return true

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
	if active_player == player:
		_active_player_index = index
		return
	if active_player:
		_disconnect_active_player_signals(active_player)
		active_player.set_active(false)
	active_player = player
	_active_player_index = index
	active_player.set_active(true)
	_connect_active_player_signals()
	_on_active_player_action_points_changed(active_player.action_points)
	emit_signal("active_player_changed", active_player)

func _clear_active_player() -> void:
	if active_player:
		_disconnect_active_player_signals(active_player)
		active_player.set_active(false)
	active_player = null
	_active_player_index = -1
	emit_signal("active_player_changed", active_player)

func _connect_active_player_signals() -> void:
	if not active_player:
		return
	if not active_player.action_points_changed.is_connected(_on_active_player_action_points_changed):
		active_player.action_points_changed.connect(_on_active_player_action_points_changed)

func _disconnect_active_player_signals(player: Player) -> void:
	if not player:
		return
	if player.action_points_changed.is_connected(_on_active_player_action_points_changed):
		player.action_points_changed.disconnect(_on_active_player_action_points_changed)

func _on_active_player_action_points_changed(new_value: int) -> void:
	emit_signal("active_player_action_points_changed", new_value)

func _refill_player_action_points() -> void:
	for player in players:
		if player.has_method("reset_for_new_day"):
			player.reset_for_new_day()
		player.refill_action_points()

func _show_player_ui() -> void:
	if not player_ui:
		player_ui = get_node_or_null("../UI/PlayerUI")
	_refresh_player_display()
	if player_ui:
		player_ui.show_player_ui()

func _hide_player_ui() -> void:
	if not player_ui:
		player_ui = get_node_or_null("../UI/PlayerUI")
	if player_ui:
		player_ui.hide_player_ui()

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

func _find_camera_root() -> CameraDrag:
	if camera_root:
		return camera_root
	var found := NodeLocator.camera_root(self)
	if found and not camera_root:
		camera_root = found
	return found

func _focus_camera_on_active_player() -> void:
	if not active_player or not active_player.current_tile:
		return
	var target_root := _find_camera_root()
	if not target_root:
		return
	var tween := target_root.focus_on_tile(
		active_player.current_tile,
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
		return _generate_rolls_from_data(players_data)
	var ui_instance := dice_game_ui_scene.instantiate()
	if not ui_instance:
		return _generate_rolls_from_data(players_data)
	_dice_ui_instance = ui_instance
	var parent_node: Node = ui_layer if ui_layer else self
	parent_node.add_child(ui_instance)
	var results: Array = await ui_instance.run_lottery(players_data)
	_dice_ui_instance = null
	if results.size() == 0:
		return _generate_rolls_from_data(players_data)
	return results

func _build_lottery_player_data() -> Array:
	var data: Array = []
	for i in range(players.size()):
		var player: Player = players[i]
		if not player:
			continue
		var icon_texture: Texture2D = null
		var icon_name: String = ""
		var view_params: Dictionary = {}
		var params_by_index: Dictionary = {}
		if player_manager and player_manager.has_method("get_view_params_for_index"):
			params_by_index = player_manager.get_view_params_for_index(i)
		if not params_by_index.is_empty():
			view_params = params_by_index
		elif player_manager and player_manager.has_method("get_view_params_for_player"):
			view_params = player_manager.get_view_params_for_player(player)
		if view_params.is_empty() and player_manager:
			var meta_params := player_manager.get_meta("PlayersViewParams") as Array
			if meta_params and i < meta_params.size():
				var meta_entry: Dictionary = meta_params[i] as Dictionary
				if meta_entry:
					view_params = meta_entry

		icon_name = view_params.get("CharIconName", "") as String

		if player_manager and player_manager.has_method("get_icon_texture_for_player"):
			icon_texture = player_manager.get_icon_texture_for_player(player)
		if not icon_texture and icon_name != "":
			var loaded := load("res://image/%s.png" % icon_name)
			if loaded is Texture2D:
				icon_texture = loaded

		data.append({
			"player": player,
			"icon_texture": icon_texture,
			"icon_name": icon_name
		})
	return data

func _generate_rolls_from_data(players_data: Array) -> Array:
	var results: Array = []
	for entry in players_data:
		if not (entry is Dictionary):
			continue
		var player := entry.get("player") as Player
		if not player:
			continue
		var roll_value := randi_range(1, 6)
		results.append({
			"player": player,
			"roll": roll_value
		})
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
			"tie": randf()
		})
	enriched.sort_custom(func(a, b):
		var roll_a := int(a.get("roll", 0))
		var roll_b := int(b.get("roll", 0))
		if roll_a == roll_b:
			return float(a.get("tie", 0.0)) > float(b.get("tie", 0.0))
		return roll_a > roll_b
	)
	return enriched

func _start_day_cycle(increment_day: bool) -> void:
	state = GameState.DAY
	_log_state("игровой день")
	if increment_day:
		current_game_day += 1
	_update_day_label()
	_refill_player_action_points()
	_ensure_camera_nodes()
	if camera_root:
		camera_root.set_follow_enabled(true)
		camera_root.apply_zoom_preset(0, true)
		camera_root.set_input_enabled(true)
	_clear_active_player()
	if players.size() > 0:
		set_active_player(players[0])
		await _focus_camera_on_active_player()
		_show_game_ui()
		emit_signal("new_player_started_moving", active_player)

func _start_night_cycle() -> void:
	state = GameState.NIGHT
	_log_state("ночь")
	_hide_player_ui()
	_clear_active_player()
	await _focus_camera_on_red_tile()
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
	var red_tile := _get_red_tile()
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
		level_manager = tree.get_first_node_in_group("level_manager") as LevelManager
	return level_manager
