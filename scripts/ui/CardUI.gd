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

@onready var background: Control = get_node_or_null("Background") as Control
@onready var art_rect: TextureRect = get_node_or_null("Art") as TextureRect
@onready var cost_label: Label = get_node_or_null("Cost") as Label

func _ready():
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)
	_base_z_index = z_index
	_refresh_visuals()
	# Отложим обновление pivot, чтоб размеры уже были
	await get_tree().process_frame
	_update_pivot()


func _notification(what):
	if what == NOTIFICATION_RESIZED:
		_update_pivot()


func _update_pivot():
	if size.x > 0 and size.y > 0:
		pivot_offset = size * 0.5


func _refresh_visuals():
	if art_rect:
		art_rect.texture = art_texture
	if cost_label:
		cost_label.text = str(cost)


func set_card_data(data):
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
	_dragging = true
	set_as_top_level(true)
	z_index = 100


func update_drag_position() -> void:
	if not _dragging:
		return
	global_position = get_global_mouse_position() - size * 0.5


func end_drag() -> void:
	if not _dragging:
		return
	_dragging = false
	set_as_top_level(false)
	z_index = _base_z_index
	emit_signal("drag_ended", self)


func _apply_transform(pos: Vector2, rot: float, animated: bool) -> void:
	if _dragging:
		return
	if _tween and _tween.is_running():
		_tween.kill()
	if animated:
		_tween = create_tween()
		_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		_tween.tween_property(self, "position", pos, 0.2)
		_tween.parallel().tween_property(self, "rotation", rot, 0.2)
	else:
		position = pos
		rotation = rot


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		emit_signal("drag_started", self)


func _on_mouse_entered() -> void:
	emit_signal("hovered", self)


func _on_mouse_exited() -> void:
	emit_signal("unhovered", self)
