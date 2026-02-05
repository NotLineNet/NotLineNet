extends Node3D
class_name PlayerManager

const IMAGE_DIR := "res://image/"
const PORTRAIT_CONTAINER_PATH := "/root/Main/UI/MainHUD/Portraits/HBoxContainer"
const MAIN_HUD_PATH := "/root/Main/UI/MainHUD"
const PORTRAIT_SCENE := preload("res://scenes/ui/PlayerUI/PlayerHUDPortrait.tscn")
const NodeLocator = preload("res://scripts/core/NodeLocator.gd")
const PORTRAIT_ANIM_SHOW := "TurnShow"
const PORTRAIT_ANIM_HIDE := "TurnHide"

var _players_view_params: Array = []
var _player_ui: Control
var _player_ui_avatar: Sprite2D
var _player_ui_name_label: Label
var _portrait_container: HBoxContainer
var _portrait_nodes: Array[Control] = []
var _portrait_by_player: Dictionary = {}
var _params_by_player: Dictionary = {}
var _last_active_player: Player = null
var _portraits_ready: bool = false
var _pending_show_player: Player = null
var _main_hud: Control

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
	if not gm.new_player_started_moving.is_connected(_on_player_turn_started):
		gm.new_player_started_moving.connect(_on_player_turn_started)
	if gm.has_signal("player_turn_finished") and not gm.player_turn_finished.is_connected(_on_player_turn_finished):
		gm.player_turn_finished.connect(_on_player_turn_finished)
	_on_active_player_changed(gm.active_player)

func _on_active_player_changed(player) -> void:
	var previous_active: Player = _last_active_player
	_last_active_player = player
	update_active_player_display(player)
	if not player and previous_active:
		_play_turn_hide_for_player(previous_active)
	_highlight_active_portrait()

func _on_player_turn_started(player) -> void:
	_play_turn_show_for_player(player)

func _on_player_turn_finished(player) -> void:
	_play_turn_hide_for_player(player)

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

func _prepare_portrait_instance(texture: Texture2D) -> Control:
	if not PORTRAIT_SCENE:
		return null
	var instance := PORTRAIT_SCENE.instantiate() as Control
	if not instance:
		return null
	_set_portrait_icon_texture(instance, texture)
	_set_portrait_base_state(instance)
	return instance

func _set_portrait_icon_texture(portrait: Node, texture: Texture2D) -> void:
	if not portrait:
		return
	var icon := portrait.get_node_or_null("StriteRoot/PlayerIcon") as Sprite2D
	if icon:
		icon.texture = texture

func _set_portrait_base_state(portrait: Node) -> void:
	if not portrait:
		return
	var strite_root := portrait.get_node_or_null("StriteRoot") as Control
	if strite_root:
		strite_root.position = Vector2(60, 0)
	portrait.set_meta("is_active", false)
	_play_portrait_animation(portrait, PORTRAIT_ANIM_HIDE)

func _get_portrait_anim_player(portrait: Node) -> AnimationPlayer:
	if not portrait:
		return null
	return portrait.get_node_or_null("AnimationPlayer") as AnimationPlayer

func _play_portrait_animation(portrait: Node, animation_name: String) -> void:
	var anim_player := _get_portrait_anim_player(portrait)
	if not anim_player:
		return
	if not anim_player.has_animation(animation_name):
		return
	anim_player.play(animation_name)

func _set_portrait_state(portrait: Node, is_active: bool) -> void:
	if not portrait:
		return
	var current := portrait.get_meta("is_active", false) as bool
	if current == is_active:
		return
	portrait.set_meta("is_active", is_active)
	_play_portrait_animation(portrait, PORTRAIT_ANIM_SHOW if is_active else PORTRAIT_ANIM_HIDE)

func _play_turn_show_for_player(player) -> void:
	if not player:
		_pending_show_player = null
		return
	var portrait: Control = _portrait_by_player.get(player, null) as Control
	if not _portraits_ready or not _is_main_hud_visible():
		_pending_show_player = player
		return
	if not portrait or not portrait.is_inside_tree():
		_pending_show_player = player
		return
	if not portrait.is_visible_in_tree():
		_pending_show_player = player
		await _ensure_portrait_visible_before_show(portrait)
		if not portrait.is_visible_in_tree() or not _is_main_hud_visible():
			return
	_pending_show_player = null
	_set_portrait_state(portrait, true)

func _play_turn_hide_for_player(player) -> void:
	if not player:
		return
	var portrait: Control = _portrait_by_player.get(player, null) as Control
	if portrait:
		_set_portrait_state(portrait, false)

func _ensure_portrait_visible_before_show(portrait: Control) -> void:
	if not portrait:
		return
	var attempts := 0
	while not portrait.is_visible_in_tree() and attempts < 6:
		await get_tree().process_frame
		attempts += 1

func _get_game_manager() -> GameManager:
	var tree := get_tree()
	if not tree:
		return null
	return NodeLocator.game_manager(tree)

func _ensure_main_hud() -> void:
	if _main_hud and is_instance_valid(_main_hud):
		return
	_main_hud = get_node_or_null(MAIN_HUD_PATH) as Control

func _is_main_hud_visible() -> bool:
	_ensure_main_hud()
	if not _main_hud:
		return false
	return _main_hud.is_visible_in_tree()

func _highlight_active_portrait() -> void:
	if not _portraits_ready or not _is_main_hud_visible():
		return
	var gm := _get_game_manager()
	if not gm:
		return
	var active_portrait: Control = null
	if gm.active_player:
		active_portrait = _portrait_by_player.get(gm.active_player, null) as Control
	for portrait in _portrait_nodes:
		if not portrait:
			continue
		if portrait == active_portrait and gm.active_player:
			_set_portrait_state(portrait, true)
		else:
			_set_portrait_state(portrait, false)

func highlight_active_portrait() -> void:
	_highlight_active_portrait()

func _current_active_player_index() -> int:
	var gm := _get_game_manager()
	if not gm or not gm.active_player:
		return -1
	return gm.players.find(gm.active_player)

func _populate_portraits() -> void:
	_portraits_ready = false
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
		var portrait := _prepare_portrait_instance(texture)
		if not portrait:
			continue
		_portrait_container.add_child(portrait)
		_portrait_nodes.append(portrait)
	if gm:
		var limit: int = min(_portrait_nodes.size(), gm.players.size())
		for idx in range(limit):
			var player: Player = gm.players[idx]
			if player:
				_portrait_by_player[player] = _portrait_nodes[idx]
	_mark_portraits_ready_and_flush()

func reorder_portraits(players: Array) -> void:
	_portraits_ready = false
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
		var portrait := _prepare_portrait_instance(texture)
		if not portrait:
			continue
		_portrait_container.add_child(portrait)
		_portrait_nodes.append(portrait)
		_portrait_by_player[player] = portrait
	_mark_portraits_ready_and_flush()

func _mark_portraits_ready_and_flush() -> void:
	_portraits_ready = true
	_highlight_active_portrait()
	_flush_pending_show_if_ready()

func _flush_pending_show_if_ready() -> void:
	if not _pending_show_player:
		return
	if not _portraits_ready or not _is_main_hud_visible():
		return
	var player: Player = _pending_show_player
	_pending_show_player = null
	_play_turn_show_for_player(player)
