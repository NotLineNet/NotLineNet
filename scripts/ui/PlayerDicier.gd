extends Control
class_name PlayerDicier

const IMAGE_DIR := "res://image/"
const DICER_BONUS_SCENE: PackedScene = preload("res://scenes/ui/PlayerUI/PlayerEllements/DicierBonus.tscn")
const BONUS_TYPE_DICE := "Dice"

var player
var roll_value: int = 0
var _pending_icon_texture: Texture2D
var _pending_icon_name: String = ""
var _bonus_node: Control
var _bonus_anim_player: AnimationPlayer
var _bonus_label: Label

@onready var player_icon: Sprite2D = get_node_or_null("Portrait/PlayerIcon") as Sprite2D
@onready var dice_label: Label = get_node_or_null("Dice/DiceCounter/Label") as Label
@onready var bonuses_container: HBoxContainer = get_node_or_null("BonusesPanel/HBoxContainer") as HBoxContainer

func setup(data: Dictionary) -> void:
	player = data.get("player")
	var icon_texture: Texture2D = data.get("icon_texture")
	var icon_name: String = data.get("icon_name", "")
	_pending_icon_texture = icon_texture
	_pending_icon_name = icon_name
	_apply_icon_texture()
	_prepare_bonus()

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
	_update_bonus_label(roll_value)
	await _play_bonus_animation()
	return {"player": player, "roll": roll_value}

func _prepare_bonus() -> void:
	_clear_bonus()
	if not bonuses_container:
		return
	var bonus_scene := DICER_BONUS_SCENE.instantiate() as Control
	if not bonus_scene:
		return
	bonuses_container.add_child(bonus_scene)
	_bonus_node = bonus_scene
	_bonus_anim_player = bonus_scene.get_node_or_null("AnimationPlayer") as AnimationPlayer
	_bonus_label = bonus_scene.get_node_or_null("Bonus/BonusValue/Label") as Label
	_update_bonus_label(0)
	_apply_bonus_icon(bonus_scene, BONUS_TYPE_DICE)

func _apply_bonus_icon(bonus_scene: Control, bonus_type: String) -> void:
	var icon := bonus_scene.get_node_or_null("Bonus/BonusIcon") as Sprite2D
	if not icon:
		return
	var texture := _load_bonus_icon(bonus_scene, bonus_type)
	if texture:
		icon.texture = texture

func _load_bonus_icon(bonus_scene: Control, bonus_type: String) -> Texture2D:
	if not bonus_scene:
		return null
	var metadata: Dictionary = bonus_scene.get_meta("BonusImages") as Dictionary
	if metadata and metadata.has(bonus_type):
		var image_name := metadata.get(bonus_type, "") as String
		if image_name != "":
			var path := "%s%s.png" % [IMAGE_DIR, image_name]
			var loaded := load(path)
			if loaded is Texture2D:
				return loaded
	var fallback_path := "%s%s.png" % [IMAGE_DIR, bonus_type]
	var fallback := load(fallback_path)
	if fallback is Texture2D:
		return fallback
	return null

func _clear_bonus() -> void:
	if _bonus_node and is_instance_valid(_bonus_node):
		_bonus_node.queue_free()
	_bonus_node = null
	_bonus_anim_player = null
	_bonus_label = null

func _update_bonus_label(value: int) -> void:
	if not _bonus_label:
		return
	_bonus_label.text = str(value)

func _play_bonus_animation() -> void:
	if not _bonus_anim_player:
		return
	if not _bonus_anim_player.has_animation("BonusShow"):
		return
	_bonus_anim_player.play("BonusShow")
	await _bonus_anim_player.animation_finished
