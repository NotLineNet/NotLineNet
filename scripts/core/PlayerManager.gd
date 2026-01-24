extends Node3D
class_name PlayerManager

const IMAGE_DIR := "res://image/"

var _players_view_params: Array = []
var _player_ui: Control
var _player_ui_avatar: Sprite2D
var _player_ui_name_label: Label

func _ready() -> void:
	_players_view_params = _load_players_view_params()
	_connect_to_game_manager()
	await get_tree().process_frame
	_apply_visuals_to_players()

func update_active_player_display(player) -> void:
	if not player:
		return
	var params := _params_for_player(player)
	if not params:
		return
	_apply_body_texture(player, params)
	_update_player_ui(params)

func _connect_to_game_manager() -> void:
	var gm := _get_game_manager()
	if not gm:
		return
	if not gm.active_player_changed.is_connected(_on_active_player_changed):
		gm.active_player_changed.connect(_on_active_player_changed)
	_on_active_player_changed(gm.active_player)

func _on_active_player_changed(player) -> void:
	update_active_player_display(player)

func _apply_visuals_to_players() -> void:
	var gm := _get_game_manager()
	if not gm:
		return
	for index in range(gm.players.size()):
		var player := gm.players[index]
		var params := _params_for_index(index)
		if player and params:
			_apply_body_texture(player, params)

func _load_players_view_params() -> Array:
	var raw := get_meta("PlayersViewParams") as Array
	if raw:
		return raw.duplicate(true)
	return []

func _params_for_player(player) -> Dictionary:
	var gm := _get_game_manager()
	if not gm:
		return {}
	var index := gm.players.find(player)
	if index == -1:
		return {}
	return _params_for_index(index)

func _params_for_index(index: int) -> Dictionary:
	if index < 0 or index >= _players_view_params.size():
		return {}
	var entry := _players_view_params[index] as Dictionary
	if entry:
		return entry
	return {}

func _apply_body_texture(player, params) -> void:
	if not player:
		return
	var body_name := params.get("CharBodyName", "") as String
	var texture := _load_image_texture(body_name)
	if not texture:
		return
	var body_image := player.get_node_or_null("BodyImage") as Sprite3D
	if body_image:
		body_image.texture = texture

func _update_player_ui(params) -> void:
	_prepare_player_ui_nodes()
	if _player_ui_name_label:
		_player_ui_name_label.text = params.get("CharName", "")
	if _player_ui_avatar:
		var avatar_texture := _load_image_texture(params.get("CharIconName", ""))
		if avatar_texture:
			_player_ui_avatar.texture = avatar_texture

func _prepare_player_ui_nodes() -> void:
	if not _player_ui or not is_instance_valid(_player_ui):
		_player_ui = get_node_or_null("../UI/PlayerUI") as Control
	if not _player_ui:
		return
	_player_ui_avatar = _player_ui.get_node_or_null("PanelRoot/Avatar") as Sprite2D
	_player_ui_name_label = _player_ui.get_node_or_null("PanelRoot/Name") as Label

func _load_image_texture(resource_name: String) -> Texture2D:
	if resource_name == "":
		return null
	var path := "%s%s.png" % [IMAGE_DIR, resource_name]
	var loaded := load(path)
	if loaded is Texture2D:
		return loaded
	return null

func _get_game_manager() -> GameManager:
	var tree := get_tree()
	if not tree:
		return null
	return tree.get_first_node_in_group("game_manager") as GameManager
