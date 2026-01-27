extends Node3D
class_name PlayerManager

const IMAGE_DIR := "res://image/"
const PORTRAIT_CONTAINER_PATH := "/root/Main/UI/MainHUD/Portraits/HBoxContainer"
const PORTRAIT_SCALE_ACTIVE := 1.1
const PORTRAIT_SCALE_IDLE := 1.0
const PORTRAIT_TWEEN_DURATION := 0.15

var _players_view_params: Array = []
var _player_ui: Control
var _player_ui_avatar: Sprite2D
var _player_ui_name_label: Label
var _portrait_container: HBoxContainer
var _portrait_nodes: Array[TextureRect] = []
var _portrait_by_player: Dictionary = {}
var _params_by_player: Dictionary = {}

func _ready() -> void:
	_players_view_params = _load_players_view_params()
	_connect_to_game_manager()
	await get_tree().process_frame
	_apply_visuals_to_players()
	_populate_portraits()
	_highlight_active_portrait()

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
	_highlight_active_portrait()

func _apply_visuals_to_players() -> void:
	var gm := _get_game_manager()
	if not gm:
		return
	_params_by_player.clear()
	for index in range(gm.players.size()):
		var player := gm.players[index]
		var params := _params_for_index(index)
		if player and params:
			_params_by_player[player] = params
			_apply_body_texture(player, params)

func _load_players_view_params() -> Array:
	var raw := get_meta("PlayersViewParams") as Array
	if raw:
		return raw.duplicate(true)
	return []

func _params_for_player(player) -> Dictionary:
	if _params_by_player.has(player):
		return _params_by_player[player]
	var gm := _get_game_manager()
	if not gm:
		return {}
	var index := gm.players.find(player)
	if index == -1:
		return {}
	var params := _params_for_index(index)
	if params:
		_params_by_player[player] = params
	return params

func get_view_params_for_player(player) -> Dictionary:
	return _params_for_player(player)

func get_view_params_for_index(index: int) -> Dictionary:
	return _params_for_index(index)

func get_icon_texture_for_player(player) -> Texture2D:
	var params := _params_for_player(player)
	var icon_name := params.get("CharIconName", "") as String
	return _load_image_texture(icon_name)

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

func _highlight_active_portrait() -> void:
	var gm := _get_game_manager()
	if not gm or not gm.active_player:
		return
	var active_portrait := _portrait_by_player.get(gm.active_player, null) as TextureRect
	if not active_portrait:
		return
	for portrait in _portrait_nodes:
		if not portrait:
			continue
		var target_scale := PORTRAIT_SCALE_ACTIVE if portrait == active_portrait else PORTRAIT_SCALE_IDLE
		_animate_portrait_scale(portrait, target_scale)

func highlight_active_portrait() -> void:
	_highlight_active_portrait()

func _current_active_player_index() -> int:
	var gm := _get_game_manager()
	if not gm or not gm.active_player:
		return -1
	return gm.players.find(gm.active_player)

func _animate_portrait_scale(portrait: TextureRect, scale_value: float) -> void:
	if not portrait:
		return
	var tween := portrait.create_tween()
	tween.set_trans(Tween.TRANS_QUINT)
	tween.set_ease(Tween.EASE_OUT)
	tween.tween_property(portrait, "scale", Vector2(scale_value, scale_value), PORTRAIT_TWEEN_DURATION)

func _populate_portraits() -> void:
	if not _portrait_container or not is_instance_valid(_portrait_container):
		_portrait_container = get_node_or_null(PORTRAIT_CONTAINER_PATH) as HBoxContainer
	if not _portrait_container:
		return
	var gm := _get_game_manager()
	for child in _portrait_container.get_children():
		child.queue_free()
	_portrait_nodes.clear()
	_portrait_by_player.clear()
	for params in _players_view_params:
		if not params or not (params is Dictionary):
			continue
		var icon_name := params.get("CharIconName", "") as String
		var texture := _load_image_texture(icon_name)
		if not texture:
			continue
		var portrait := TextureRect.new()
		portrait.texture = texture
		portrait.stretch_mode = TextureRect.STRETCH_KEEP
		portrait.custom_minimum_size = texture.get_size()
		portrait.size_flags_horizontal = Control.SIZE_FILL | Control.SIZE_SHRINK_CENTER
		portrait.pivot_offset = Vector2(texture.get_width() * 0.5, 0)
		portrait.scale = Vector2(PORTRAIT_SCALE_IDLE, PORTRAIT_SCALE_IDLE)
		_portrait_container.add_child(portrait)
		_portrait_nodes.append(portrait)
	if gm:
		var limit: int = min(_portrait_nodes.size(), gm.players.size())
		for idx in range(limit):
			var player: Player = gm.players[idx]
			if player:
				_portrait_by_player[player] = _portrait_nodes[idx]

func reorder_portraits(players: Array) -> void:
	if not _portrait_container or not is_instance_valid(_portrait_container):
		_portrait_container = get_node_or_null(PORTRAIT_CONTAINER_PATH) as HBoxContainer
	if not _portrait_container:
		return
	for child in _portrait_container.get_children():
		child.queue_free()
	_portrait_nodes.clear()
	_portrait_by_player.clear()
	for player in players:
		if not player:
			continue
		var texture := get_icon_texture_for_player(player)
		if not texture:
			continue
		var portrait := TextureRect.new()
		portrait.texture = texture
		portrait.stretch_mode = TextureRect.STRETCH_KEEP
		portrait.custom_minimum_size = texture.get_size()
		portrait.size_flags_horizontal = Control.SIZE_FILL | Control.SIZE_SHRINK_CENTER
		portrait.pivot_offset = Vector2(texture.get_width() * 0.5, 0)
		portrait.scale = Vector2(PORTRAIT_SCALE_IDLE, PORTRAIT_SCALE_IDLE)
		_portrait_container.add_child(portrait)
		_portrait_nodes.append(portrait)
		_portrait_by_player[player] = portrait
	_highlight_active_portrait()
