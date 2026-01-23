extends Node3D
class_name GameManager

signal active_player_changed(new_player: Player)
signal active_player_action_points_changed(new_value: int)

@export var total_players: int = 3

var currentGameDay: int = 1
var players: Array[Player] = []
var _is_waiting_new_day := false
var active_player: Player

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

func all_players_finished_moving() -> void:
	if _is_waiting_new_day:
		return
	_is_waiting_new_day = true
	var timer := get_tree().create_timer(2.0)
	await timer.timeout
	start_new_day()

func start_new_day() -> void:
	currentGameDay += 1
	_update_day_label()
	_refill_player_action_points()
	_show_player_ui()
	_is_waiting_new_day = false

func set_active_player(player: Player) -> void:
	if active_player == player:
		return
	if active_player:
		_disconnect_active_player_signals(active_player)
		active_player.set_active(false)
	active_player = player
	if active_player:
		active_player.set_active(true)
		_connect_active_player_signals()
		_on_active_player_action_points_changed(active_player.action_points)
	_show_player_ui()
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
	if active_player:
		active_player.refill_action_points()

func _show_player_ui() -> void:
	if not player_ui:
		player_ui = get_node_or_null("../UI/PlayerUI")
	if player_ui:
		player_ui.show_player_ui()

func _update_day_label() -> void:
	if not hud_ui:
		hud_ui = get_node_or_null("../UI/HUD(cheats)")
	if hud_ui and hud_ui.has_method("set_day_label"):
		hud_ui.set_day_label(currentGameDay)
