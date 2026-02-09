class_name MenuUI
extends Control

signal start_pressed

@onready var _anim_player: AnimationPlayer = %AnimationPlayer
@onready var _start_btn: Button = %StartBTN

func _ready() -> void:
	if _start_btn:
		_start_btn.pressed.connect(_on_start_btn_pressed)
	else:
		push_error("MenuUI: StartBTN not found")

func play_show() -> void:
	if not _anim_player:
		push_error("MenuUI: AnimationPlayer not found")
		return
	_anim_player.play("MenuShow")

func _on_start_btn_pressed() -> void:
	if not _anim_player:
		push_error("MenuUI: AnimationPlayer not found")
		start_pressed.emit()
		return
	_anim_player.play("MenuHide")
	_anim_player.animation_finished.connect(_on_hide_finished, CONNECT_ONE_SHOT)

func _on_hide_finished(_anim_name: String) -> void:
	start_pressed.emit()
	queue_free()
