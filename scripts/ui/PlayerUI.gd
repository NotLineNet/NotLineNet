extends Control

@onready var anim: AnimationPlayer = $AnimationPlayer

func _ready():
	visible = false
	anim.animation_finished.connect(_on_anim_finished)
	
func show_PlayerUi():
	visible = true
	anim.play("UI_Show")

func hide_playerUi():
	anim.play("UI_Hide")
	
func _on_anim_finished(name: String):
	if name == "UI_Hide":
		visible = false
