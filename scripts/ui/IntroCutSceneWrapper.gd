extends Node

const WINDOW_ID := "INTRO_CUTSCENE"

@export var scene: PackedScene

var _instance: IntroCutSceneController

signal intro_animation_finished


func _ready() -> void:
	add_to_group("ui_window_%s" % WINDOW_ID)
	if not scene:
		scene = preload("res://scenes/ui/IntroCutScene.tscn")


func prepare(_params: Dictionary) -> void:
	if _instance and is_instance_valid(_instance):
		return
	if not scene:
		return
	_instance = scene.instantiate()
	if not _instance:
		return
	add_child(_instance)
	if not _instance.intro_animation_finished.is_connected(_on_finished):
		_instance.intro_animation_finished.connect(_on_finished)


func show_animated() -> void:
	if not _instance:
		prepare({})
	if _instance and _instance.has_method("play_intro"):
		_instance.play_intro()


func hide_animated() -> void:
	if _instance and _instance.animation_player:
		_instance.animation_player.stop()
	if _instance and _instance.is_inside_tree():
		_instance.queue_free()
	_instance = null


func _on_finished() -> void:
	if has_signal("intro_animation_finished"):
		intro_animation_finished.emit()
	hide_animated()
