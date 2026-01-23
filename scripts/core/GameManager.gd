extends Node3D
class_name GameManager

var currentGameDay: int = 1
var player: Player
var _is_waiting_new_day := false

@onready var player_ui := get_node_or_null("../UI/PlayerUI")
@onready var hud_ui := get_node_or_null("../UI/HUD(cheats)")

func _ready() -> void:
	_find_player()
	_update_day_label()
	await get_tree().process_frame
	_show_player_ui()

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

func _find_player() -> void:
	var tree := get_tree()
	if not tree:
		return
	player = tree.get_first_node_in_group("player") as Player
	if not player:
		await tree.process_frame
		player = tree.get_first_node_in_group("player") as Player

func _refill_player_action_points() -> void:
	if not player:
		_find_player()
	if player:
		player.refill_action_points()

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
