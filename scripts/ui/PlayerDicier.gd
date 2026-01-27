extends Control
class_name PlayerDicier

var player: Player
var roll_value: int = 0
const IMAGE_DIR := "res://image/"
var _pending_icon_texture: Texture2D
var _pending_icon_name: String = ""

@onready var animation_player: AnimationPlayer = $AnimationPlayer
@onready var player_icon: Sprite2D = $Portrait/PlayerIcon
@onready var dice_label: Label = $Dice/DiceCounter/Label

func setup(data: Dictionary) -> void:
	player = data.get("player")
	var icon_texture: Texture2D = data.get("icon_texture")
	var icon_name: String = data.get("icon_name", "")
	_pending_icon_texture = icon_texture
	_pending_icon_name = icon_name
	_apply_icon_texture()

func _apply_icon_texture() -> void:
	if not player_icon:
		return
	if _pending_icon_texture:
		player_icon.texture = _pending_icon_texture
		return
	if _pending_icon_name != "":
		var loaded := load("%s%s.png" % [IMAGE_DIR, _pending_icon_name])
		if loaded is Texture2D:
			player_icon.texture = loaded

func _ready():
	_apply_icon_texture()

func roll_and_wait() -> Dictionary:
	roll_value = randi_range(1, 6)
	if dice_label:
		dice_label.text = str(roll_value)
	if animation_player and animation_player.has_animation("RollTheDice"):
		animation_player.play("RollTheDice")
		await animation_player.animation_finished
	return {"player": player, "roll": roll_value}
