extends Control

var anim: AnimationPlayer

func _ready():
	visible = false
	anim = get_node_or_null("AnimationPlayer") as AnimationPlayer
	if anim:
		anim.animation_finished.connect(_on_anim_finished)
	
func show_player_ui():
	visible = true
	if anim:
		anim.play("PlayerUI_Show")

func hide_player_ui():
	if anim:
		anim.play("PlayerUI_Hide")
	
func _on_anim_finished(name: String):
	if name == "PlayerUI_Hide":
		visible = false
