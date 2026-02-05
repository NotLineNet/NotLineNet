extends Control

const WINDOW_ID := "BATTLE_UI"

@onready var _anim: AnimationPlayer = get_node_or_null("AnimationPlayer") as AnimationPlayer


func _ready() -> void:
	add_to_group("ui_window_%s" % WINDOW_ID)
	if _anim and _anim.has_animation("RESET"):
		_anim.play("RESET")


func prepare(_params: Dictionary) -> void:
	# Placeholder for future context data (battle type, participants, etc.)
	pass


func show_animated() -> void:
	if _anim:
		if _anim.has_animation("RESET"):
			_anim.play("RESET")
		if _anim.has_animation("BattleShow"):
			_anim.play("BattleShow")
			await _anim.animation_finished
	show()


func hide_animated() -> void:
	if _anim and _anim.has_animation("BattleHide"):
		_anim.play("BattleHide")
		await _anim.animation_finished
	hide()
