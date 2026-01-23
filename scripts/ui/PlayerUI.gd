extends Control

@onready var anim: AnimationPlayer = $AnimationPlayer

func _ready():
	visible = false
	anim.animation_finished.connect(_on_anim_finished)
	
func show_player_ui():
	visible = true
	anim.play("PlayerUI_Show")

func hide_player_ui():
	anim.play("PlayerUI_Hide")
	
func _on_anim_finished(name: String):
	if name == "PlayerUI_Hide":
		visible = false
