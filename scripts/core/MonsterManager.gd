extends Node3D
class_name MonsterManager

const IMAGE_DIR := "res://image/"

var _monsters_view_params: Array = []
var _default_params: Dictionary = {}

func _ready() -> void:
	add_to_group("monster_manager")
	_monsters_view_params = _load_monsters_view_params()
	if _monsters_view_params.size() > 0:
		_default_params = _monsters_view_params[0]

func _load_monsters_view_params() -> Array:
	var raw := get_meta("MonstersViewParams") as Array
	if raw:
		return raw.duplicate(true)
	return []

func get_default_view_params() -> Dictionary:
	if not _default_params.is_empty():
		return _default_params
	if _monsters_view_params.size() > 0:
		return _monsters_view_params[0]
	return {}

func get_icon_name() -> String:
	var params := get_default_view_params()
	return params.get("MonsterIconName", "") as String

func get_body_name() -> String:
	var params := get_default_view_params()
	return params.get("MonsterBodyName", "") as String

func get_icon_texture_for_monster(_monster: Node = null) -> Texture2D:
	return _load_image_texture(get_icon_name())

func get_body_texture_for_monster(_monster: Node = null) -> Texture2D:
	return _load_image_texture(get_body_name())

func apply_visuals_to_monster(monster: Node) -> void:
	if not monster:
		return
	var body_image := monster.get_node_or_null("BodyImage") as Sprite3D
	if not body_image:
		return
	var texture := get_body_texture_for_monster(monster)
	if texture:
		body_image.texture = texture

func _load_image_texture(resource_name: String) -> Texture2D:
	if resource_name == "":
		return null
	var path := "%s%s.png" % [IMAGE_DIR, resource_name]
	var loaded := load(path)
	if loaded is Texture2D:
		return loaded
	return null
