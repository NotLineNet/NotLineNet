extends Node3D
class_name GameManager

signal active_player_changed(new_player: Player)
signal active_player_action_points_changed(new_value: int)
signal new_player_started_moving(new_player: Player)

const TURN_SWITCH_DELAY := 2.0
const CAMERA_MOVE_DURATION := 0.3
const CAMERA_DELAY := 0.05

@export var total_players: int = 3

var currentGameDay: int = 1
var players: Array[Player] = []
var _is_waiting_new_day := false
var _is_switching_turn := false
var active_player: Player
var _active_player_index: int = -1

@onready var player_ui := get_node_or_null("../UI/PlayerUI")
@onready var hud_ui := get_node_or_null("../UI/HUD(cheats)")

func _ready() -> void:
	add_to_group("game_manager")
	_update_day_label()
	await get_tree().process_frame
	_show_player_ui()

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

func start_new_day() -> void:
	currentGameDay += 1
	_update_day_label()
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

func _find_camera_root() -> Node3D:
	var tree := get_tree()
	var camera_root: Node3D = null
	if tree:
		camera_root = tree.get_first_node_in_group("camera_root") as Node3D
	if not camera_root:
		camera_root = get_node_or_null("../../CameraRoot") as Node3D
	if not camera_root:
		camera_root = get_node_or_null("/root/Main/CameraRoot") as Node3D
	return camera_root

func _focus_camera_on_active_player() -> void:
	if not active_player or not active_player.current_tile:
		return
	var camera_root := _find_camera_root()
	if not camera_root:
		return
	var target_position := Vector3(
		active_player.current_tile.global_position.x,
		camera_root.global_position.y,
		active_player.current_tile.global_position.z
	)
	var camera_tween := camera_root.create_tween()
	camera_tween.set_ease(Tween.EASE_IN_OUT)
	camera_tween.set_trans(Tween.TRANS_CUBIC)
	camera_tween.tween_interval(CAMERA_DELAY)
	camera_tween.tween_property(camera_root, "global_position", target_position, CAMERA_MOVE_DURATION)
	await camera_tween.finished
