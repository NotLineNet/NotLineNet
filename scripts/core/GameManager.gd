extends Node3D
class_name GameManager

signal active_player_changed(new_player: Player)
signal active_player_action_points_changed(new_value: int)
signal new_player_started_moving(new_player: Player)
signal gameplay_started

const TURN_SWITCH_DELAY := 2
const CAMERA_MOVE_DURATION := 0.3
const CAMERA_DELAY := 0.05
const INTRO_SCENE_PATH := "res://scenes/ui/IntroCutScene.tscn"

@export var total_players: int = 3
@export var intro_scene: PackedScene = preload(INTRO_SCENE_PATH)

var currentGameDay: int = 1
var players: Array[Player] = []
var _is_waiting_new_day := false
var _is_switching_turn := false
var active_player: Player
var _active_player_index: int = -1
var _intro_instance: IntroCutSceneController
var _intro_started := false
var _intro_completed := false
var _game_loaded := false
var _game_started := false

@onready var player_ui := get_node_or_null("../UI/PlayerUI")
@onready var hud_ui := get_node_or_null("../UI/HUD(cheats)")
@onready var ui_layer: CanvasLayer = get_node_or_null("../UI") as CanvasLayer
@onready var main_hud: Node = get_node_or_null("../UI/MainHUD")
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
	if _game_loaded:
		return
	_game_loaded = true
	_log_state("загрузка")
	start_intro()

func start_intro() -> void:
	if _intro_started:
		return
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

func _show_game_ui() -> void:
	if ui_layer:
		ui_layer.visible = true
	if main_hud:
		main_hud.visible = true
	_show_player_ui()
	if hud_ui:
		hud_ui.visible = true
	_update_day_label()

func game_started() -> void:
	if _game_started:
		return
	if _intro_started and not _intro_completed:
		intro_finished()
		if _game_started:
			return
	if not _intro_completed:
		return
	_game_started = true
	_log_state("начало игры")
	_ensure_camera_nodes()
	_show_game_ui()
	if camera_root:
		camera_root.set_follow_enabled(true)
		camera_root.apply_zoom_preset(0, true)
	emit_signal("gameplay_started")
	await _start_first_day()

func register_player(player: Player) -> void:
	if not player:
		return
	if players.has(player):
		return
	players.append(player)
	player.add_to_group("player")
	if players.size() == 1:
		set_active_player(player)
	else:
		player.set_active(false)

func current_player_finished_moving() -> void:
	if _is_switching_turn or not active_player:
		return
	_is_switching_turn = true
	_hide_player_ui()
	var timer := get_tree().create_timer(TURN_SWITCH_DELAY)
	await timer.timeout
	var moved := await _move_to_next_player()
	if not moved:
		await all_players_finished_moving()
	_is_switching_turn = false

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
	if _is_waiting_new_day:
		return
	_is_waiting_new_day = true
	await start_new_day()
	_is_waiting_new_day = false

func _start_first_day() -> void:
	_log_state("игровой день")
	_refill_player_action_points()
	if players.size() > 0:
		set_active_player(players[0])
		await _focus_camera_on_active_player()
		_show_player_ui()
		emit_signal("new_player_started_moving", active_player)

func start_new_day() -> void:
	currentGameDay += 1
	_update_day_label()
	_log_state("игровой день")
	_refill_player_action_points()
	if players.size() > 0:
		set_active_player(players[0])
		await _focus_camera_on_active_player()
		_show_player_ui()
		emit_signal("new_player_started_moving", active_player)

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
		hud_ui.set_day_label(currentGameDay)

func _refresh_player_display() -> void:
	var player_manager := get_node_or_null("../PlayerManager")
	if player_manager and player_manager.has_method("update_active_player_display"):
		player_manager.call("update_active_player_display", active_player)

func _find_camera_root() -> CameraDrag:
	if camera_root:
		return camera_root
	var tree := get_tree()
	var found: CameraDrag = null
	if tree:
		found = tree.get_first_node_in_group("camera_root") as CameraDrag
	if not found:
		found = get_node_or_null("../../CameraRoot") as CameraDrag
	if not found:
		found = get_node_or_null("/root/Main/CameraRoot") as CameraDrag
	if found and not camera_root:
		camera_root = found
	return found

func _focus_camera_on_active_player() -> void:
	if not active_player or not active_player.current_tile:
		return
	var target_root := _find_camera_root()
	if not target_root:
		return
	var target_position := Vector3(
		active_player.current_tile.global_position.x,
		target_root.global_position.y,
		active_player.current_tile.global_position.z
	)
	var camera_tween := target_root.create_tween()
	camera_tween.set_ease(Tween.EASE_IN_OUT)
	camera_tween.set_trans(Tween.TRANS_CUBIC)
	camera_tween.tween_interval(CAMERA_DELAY)
	camera_tween.tween_property(target_root, "global_position", target_position, CAMERA_MOVE_DURATION)
	await camera_tween.finished
