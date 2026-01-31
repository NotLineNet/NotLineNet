extends Control

const HP_SCENE: PackedScene = preload("res://scenes/ui/PlayerUI/HP.tscn")

var anim: AnimationPlayer
var _pending_hp_loss: int = 0
var _pending_target_health: int = 0
var _hp_loss_anim_playing := false
var _show_animation_playing := false
var _current_visual_health: int = 0

@onready var hp_container: HBoxContainer = get_node_or_null("PanelRoot/HPContainer") as HBoxContainer

func _ready():
	visible = false
	anim = get_node_or_null("AnimationPlayer") as AnimationPlayer
	if anim:
		anim.animation_finished.connect(_on_anim_finished)
	_clear_hp_icons()

func show_player_ui():
	visible = true
	_show_animation_playing = true
	if anim:
		anim.play("PlayerUI_Show")

func hide_player_ui():
	if anim:
		anim.play("PlayerUI_Hide")

func set_health_icons(count: int) -> void:
	if not hp_container:
		return
	var normalized: int = max(count, 0)
	_clear_hp_icons()
	for i in range(normalized):
		var icon: Control = HP_SCENE.instantiate() as Control
		if icon:
			hp_container.add_child(icon)
	_current_visual_health = normalized
	_pending_target_health = normalized

func queue_hp_loss_animation(loss_count: int = 1, resulting_health: int = -1) -> void:
	if loss_count <= 0:
		return
	_pending_hp_loss += loss_count
	if resulting_health >= 0:
		_pending_target_health = max(resulting_health, 0)
	_try_play_pending_hp_loss()

func _try_play_pending_hp_loss() -> void:
	if _pending_hp_loss == 0:
		return
	if _show_animation_playing or _hp_loss_anim_playing:
		return
	if not visible:
		return
	_hp_loss_anim_playing = true
	var loss_to_play := _pending_hp_loss
	_pending_hp_loss = 0
	await play_hp_loss_animation(loss_to_play)
	_hp_loss_anim_playing = false
	set_health_icons(_pending_target_health)

func reset_pending_hp_loss() -> void:
	_pending_hp_loss = 0
	_hp_loss_anim_playing = false
	_pending_target_health = _current_visual_health

func has_pending_hp_loss_animation() -> bool:
	return _pending_hp_loss > 0 or _hp_loss_anim_playing

func play_hp_loss_animation(loss_count: int = 1) -> void:
	if loss_count <= 0:
		return
	if not hp_container:
		return
	for i in range(loss_count):
		var icon: Node = _get_last_hp_icon()
		if not icon:
			break
		var anim_player: AnimationPlayer = icon.get_node_or_null("AnimationPlayer") as AnimationPlayer
		if anim_player and anim_player.has_animation("Damage"):
			anim_player.play("Damage")
			await anim_player.animation_finished
		icon.queue_free()

func _get_last_hp_icon() -> Node:
	if not hp_container:
		return null
	var total := hp_container.get_child_count()
	if total == 0:
		return null
	return hp_container.get_child(total - 1)

func _clear_hp_icons() -> void:
	if not hp_container:
		return
	for child in hp_container.get_children():
		child.queue_free()

func _on_anim_finished(name: String):
	if name == "PlayerUI_Hide":
		visible = false
	elif name == "PlayerUI_Show":
		_show_animation_playing = false
		_try_play_pending_hp_loss()
