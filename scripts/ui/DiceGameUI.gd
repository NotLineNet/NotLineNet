extends Control
class_name DiceGameUI

signal lottery_finished(results: Array)

const PlayerDicier = preload("res://scripts/ui/PlayerDicier.gd")

@export var player_dicier_scene: PackedScene = preload("res://scenes/ui/PlayerDicier.tscn")

var _dicier_nodes: Array = []

@onready var animation_player: AnimationPlayer = $AnimationPlayer
@onready var fade: ColorRect = $Fade
@onready var players_container: HBoxContainer = $PlayersRoot/HBoxContainer
@onready var next_button: Button = $Next/Button

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
	lottery_finished.emit(results)

	await _wait_next_click()

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
	lottery_finished.emit(results)

	await _wait_next_click()

	if animation_player:
		await _play_animation_safe("UI_Hide")

	_clear_dicier_nodes()
	queue_free()
	return results

func _spawn_dicier_nodes(players_data: Array) -> void:
	if not players_container:
		return
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

func _roll_all_dicers() -> Array:
	var results: Array = []
	for dicier in _dicier_nodes:
		var result = await dicier.roll_and_wait()
		results.append(result)
	return results

func _hide_next_button() -> void:
	if not next_button:
		return
	next_button.visible = false
	next_button.disabled = true

func _wait_next_click() -> void:
	if not next_button:
		return
	next_button.disabled = false
	next_button.visible = true
	await next_button.pressed

func _play_animation_safe(anim_name: String) -> void:
	if not animation_player:
		return
	if not animation_player.has_animation(anim_name):
		return
	animation_player.play(anim_name)
	await animation_player.animation_finished
