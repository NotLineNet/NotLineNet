extends Control
class_name DiceGameUI

const WINDOW_ID := "DICE_GAME_UI"

signal lottery_finished(results: Array)

const PlayerDicier = preload("res://scripts/ui/PlayerDicier.gd")

@export var player_dicier_scene: PackedScene = preload("res://scenes/ui/PlayerDicier.tscn")

var _dicier_nodes: Array = []
var _last_players_data: Array[Dictionary] = []
var _next_clicked: bool = false
var _confirmation_action: String = ""

@onready var animation_player: AnimationPlayer = $AnimationPlayer
@onready var fade: ColorRect = $Fade
@onready var players_container: HBoxContainer = $PlayersRoot/HBoxContainer
@onready var next_button: Button = $Next/Button
@onready var debug_controls: HBoxContainer = $DebugControls
@onready var debug_win_button: Button = $DebugControls/WinButton
@onready var debug_lose_button: Button = $DebugControls/LoseButton

func _ready() -> void:
	add_to_group("ui_window_%s" % WINDOW_ID)
	if next_button:
		next_button.pressed.connect(Callable(self, "_on_next_button_pressed"))
		next_button.visible = false
		next_button.disabled = true
	if debug_controls:
		debug_controls.visible = false
	if debug_win_button:
		debug_win_button.pressed.connect(Callable(self, "_on_debug_win_pressed"))
	if debug_lose_button:
		debug_lose_button.pressed.connect(Callable(self, "_on_debug_lose_pressed"))

func run_lottery(players_data: Array) -> Array:
	_clear_dicier_nodes()
	_spawn_dicier_nodes(players_data)
	_hide_next_button()
	if fade:
		var color := fade.color
		color.a = 0.0
		fade.color = color

	if animation_player:
		await _play_animation_safe("UI_Show")

	var results := await _roll_all_dicers()
	results = await _finalize_results(results)
	lottery_finished.emit(results)

	_clear_dicier_nodes()

	if animation_player:
		await _play_animation_safe("UI_Hide")

	queue_free()
	return results

func run_battle(players_data: Array) -> Array:
	_clear_dicier_nodes()
	_spawn_dicier_nodes(players_data)
	_hide_next_button()
	if fade:
		var color := fade.color
		color.a = 0.0
		fade.color = color

	if animation_player:
		await _play_animation_safe("UI_Show")

	var results := await _roll_all_dicers()
	results = await _finalize_results(results)
	lottery_finished.emit(results)

	if animation_player:
		await _play_animation_safe("UI_Hide")

	_clear_dicier_nodes()
	return results


# UIWindowQueue integration
func prepare(params: Dictionary) -> void:
	var data: Array = params.get("participants", []) as Array
	_last_players_data = []
	# store for potential debug
	for entry in data:
		if entry is Dictionary:
			_last_players_data.append(entry.duplicate(true) as Dictionary)


func show_animated() -> void:
	# For queue-driven show, no-op; actual flow happens inside run_battle/run_lottery.
	pass

func _spawn_dicier_nodes(players_data: Array) -> void:
	if not players_container:
		return
	_last_players_data.clear()
	if players_data:
		for entry in players_data:
			if entry is Dictionary:
				_last_players_data.append(entry.duplicate(true) as Dictionary)
	for data in players_data:
		if not player_dicier_scene:
			continue
		var dicier := player_dicier_scene.instantiate()
		if not dicier:
			continue
		players_container.add_child(dicier)
		if data is Dictionary:
			dicier.setup(data)
		_dicier_nodes.append(dicier)

func _clear_dicier_nodes() -> void:
	if players_container:
		for child in players_container.get_children():
			child.queue_free()
	_dicier_nodes.clear()
	_last_players_data.clear()

func _roll_all_dicers() -> Array:
	var results: Array = []
	for dicier in _dicier_nodes:
		var result = await dicier.roll_and_wait()
		results.append(result)
	return results

func _hide_next_button() -> void:
	_hide_confirmation_controls()

func _show_confirmation_controls() -> void:
	if next_button:
		next_button.visible = true
		next_button.disabled = false
	if debug_controls:
		debug_controls.visible = true

func _hide_confirmation_controls() -> void:
	if next_button:
		next_button.visible = false
		next_button.disabled = true
	if debug_controls:
		debug_controls.visible = false

func _has_confirmation_buttons() -> bool:
	return next_button != null or debug_controls != null

func _wait_for_confirmation() -> String:
	if not _has_confirmation_buttons():
		return "next"
	_next_clicked = false
	_confirmation_action = ""
	while true:
		if _confirmation_action != "":
			break
		if _next_clicked:
			break
		await get_tree().process_frame
	var action := _confirmation_action
	if action == "" and _next_clicked:
		action = "next"
	_next_clicked = false
	_confirmation_action = ""
	return action

func _finalize_results(results: Array) -> Array:
	if not _has_confirmation_buttons():
		return results
	_show_confirmation_controls()
	var action := await _wait_for_confirmation()
	_hide_confirmation_controls()
	if action == "win":
		var forced := _build_debug_results(true)
		if forced.size() > 0:
			return forced
	elif action == "lose":
		var forced := _build_debug_results(false)
		if forced.size() > 0:
			return forced
	return results

func _build_debug_results(force_win: bool) -> Array:
	if _last_players_data.size() == 0:
		return []
	var forced_results: Array[Dictionary] = []
	for i in range(_last_players_data.size()):
		var entry: Dictionary = _last_players_data[i] as Dictionary
		if not (entry is Dictionary):
			continue
		var participant: Object = entry.get("player") as Object
		if not participant:
			continue
		var roll_value := 1
		if force_win:
			roll_value = 6 if i == 0 else 1
		else:
			roll_value = 1 if i == 0 else 6
		var forced_entry: Dictionary = {"player": participant, "roll": roll_value}
		forced_results.append(forced_entry)
	return forced_results

func _on_next_button_pressed() -> void:
	_next_clicked = true

func _on_debug_win_pressed() -> void:
	_confirmation_action = "win"

func _on_debug_lose_pressed() -> void:
	_confirmation_action = "lose"

func _play_animation_safe(anim_name: String) -> void:
	if not animation_player:
		return
	if not animation_player.has_animation(anim_name):
		return
	animation_player.play(anim_name)
	await animation_player.animation_finished
