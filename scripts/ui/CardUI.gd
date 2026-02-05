extends Control
class_name CardUI

signal hovered(card)
signal unhovered(card)
signal drag_started(card)
signal drag_ended(card)

@export var art_texture: Texture2D
@export var cost: int = 0

var card_data
var hand_index: int = -1

var _layout_position: Vector2 = Vector2.ZERO
var _layout_rotation: float = 0.0
var _tween: Tween
var _dragging := false
var _base_z_index: int = 0
var _last_global_position: Vector2 = Vector2.ZERO
var _hovered := false
var _bg_default_modulate: Color = Color(1, 1, 1, 1)

const PLAYZONE_HIGHLIGHT_COLOR: Color = Color(0.2, 1.0, 0.2, 1.0)

@onready var card_root: Control = get_node_or_null("CardRoot") as Control
@onready var background: Control = _get_from_card_root("Background")
@onready var art_rect: TextureRect = _get_from_card_root("Art") as TextureRect
@onready var cost_label: Label = _get_from_card_root("Cost") as Label

func _ready():
	_connect_to_inputs()
	_base_z_index = z_index
	_sync_size_with_card_root()
	if background:
		_bg_default_modulate = background.modulate
	_refresh_visuals()
	# Отложим обновление pivot, чтоб размеры уже были
	await get_tree().process_frame
	_sync_size_with_card_root()
	_update_pivot()


func _notification(what):
	if what == NOTIFICATION_RESIZED:
		_sync_size_with_card_root()
		_update_pivot()


func _get_from_card_root(path: String) -> Node:
	if card_root and card_root.has_node(path):
		return card_root.get_node(path)
	return get_node_or_null(path)


func _connect_to_inputs() -> void:
	var target: Control = card_root if card_root else self
	if target:
		target.mouse_entered.connect(_on_mouse_entered)
		target.mouse_exited.connect(_on_mouse_exited)
		target.gui_input.connect(_handle_gui_input)


func _sync_size_with_card_root() -> void:
	if not card_root:
		return
	var target_size := card_root.size
	if target_size != Vector2.ZERO and target_size != size:
		size = target_size
	var min_size := card_root.get_combined_minimum_size()
	if min_size != Vector2.ZERO:
		custom_minimum_size = min_size


func _update_pivot():
	if size.x > 0 and size.y > 0:
		pivot_offset = size * 0.5


func _refresh_visuals():
	if art_rect:
		art_rect.texture = art_texture
	if cost_label:
		cost_label.text = str(cost)


func set_card_data(data):
	if data == null:
		return
	card_data = data
	if typeof(data) == TYPE_DICTIONARY:
		var dict: Dictionary = data
		if dict.has("cost"):
			cost = int(dict["cost"])
		if dict.has("art") and dict["art"] is Texture2D:
			art_texture = dict["art"]
	_refresh_visuals()


func set_layout_target(pos: Vector2, rot: float, animated := true) -> void:
	_layout_position = pos
	_layout_rotation = rot
	_apply_transform(pos, rot, animated)


func restore_layout(animated := true) -> void:
	_apply_transform(_layout_position, _layout_rotation, animated)


func raise_visual(hover_offset := Vector2(0, -80), straighten := true, animated := true) -> void:
	var target_rot := 0.0 if straighten else _layout_rotation * 0.5
	_apply_transform(_layout_position + hover_offset, target_rot, animated)


func push_aside(hovered: CardUI, push_distance := 30.0, animated := true, rot_scale := 0.7) -> void:
	if not hovered:
		return
	var direction: float = sign(hand_index - hovered.hand_index)
	var offset: Vector2 = Vector2(push_distance * direction, 0)
	var target_rot: float = _layout_rotation * rot_scale
	_apply_transform(_layout_position + offset, target_rot, animated)


func start_drag() -> void:
	if _dragging:
		return
	if _tween and _tween.is_running():
		_tween.kill()
	# Сохраняем мировую позицию и переносим в топ-слой без скачка
	_last_global_position = global_position
	set_as_top_level(true)
	global_position = _last_global_position
	_dragging = true
	z_index = 100


func update_drag_position() -> void:
	if not _dragging:
		return
	global_position = get_global_mouse_position() - size * 0.5


func end_drag() -> void:
	if not _dragging:
		return
	# Фиксируем текущую мировую позицию (точка отпускания)
	_last_global_position = global_position
	# Возвращаем из top_level в родителя, сохраняя экранное положение
	set_as_top_level(false)
	if get_parent():
		var parent_control := get_parent() as Control
		if parent_control:
			var inv: Transform2D = parent_control.get_global_transform_with_canvas().affine_inverse()
			position = inv * _last_global_position
	_dragging = false
	z_index = _base_z_index
	emit_signal("drag_ended", self)


func _apply_transform(pos: Vector2, rot: float, animated: bool) -> void:
	if _dragging:
		return
	var target_pos: Vector2 = pos - size * 0.5
	if _tween and _tween.is_running():
		_tween.kill()
	if animated:
		_tween = create_tween()
		_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		_tween.tween_property(self, "position", target_pos, 0.2)
		_tween.parallel().tween_property(self, "rotation", rot, 0.2)
	else:
		position = target_pos
		rotation = rot


func _handle_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		emit_signal("drag_started", self)


func _on_mouse_entered() -> void:
	_hovered = true
	emit_signal("hovered", self)


func _on_mouse_exited() -> void:
	_hovered = false
	set_playzone_highlight(false)
	emit_signal("unhovered", self)


func is_hovered() -> bool:
	return _hovered


func set_playzone_highlight(active: bool) -> void:
	if background:
		background.modulate = PLAYZONE_HIGHLIGHT_COLOR if active else _bg_default_modulate
