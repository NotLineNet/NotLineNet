extends Control
class_name HandUI

signal card_played(card_data)
signal card_returned(card)
signal card_added(card)

@export var card_scene: PackedScene = preload("res://scenes/ui/CardUI.tscn")
@export var play_zone: Control

@onready var cards_container: Control = get_node_or_null("CardsContainer") as Control
@onready var layout_controller: HandLayoutController = get_node_or_null("LayoutController") as HandLayoutController
@onready var play_zone_color: ColorRect = _get_play_zone_color_rect()
@onready var spawn_marker: Node2D = _get_spawn_marker()

var cards: Array[CardUI] = []
var dragging_card: CardUI


func _ready():
	if not layout_controller:
		layout_controller = HandLayoutController.new()
		add_child(layout_controller)
	set_process(true)
	set_process_input(true)
	set_process_unhandled_input(true)
	_set_play_zone_visible(false)
	_relayout()


func _notification(what):
	if what == NOTIFICATION_RESIZED:
		_relayout()


func add_card(card_data = null, animated := true) -> CardUI:
	if not card_scene or not cards_container:
		return null
	var card := card_scene.instantiate() as CardUI
	if not card:
		return null
	# Сбрасываем anchors, чтобы позиция считалась от верхнего левого угла
	card.set_anchors_preset(Control.PRESET_TOP_LEFT)
	if card_data != null:
		card.set_card_data(card_data)
	cards_container.add_child(card)
	# Ждём, когда размеры вычислятся, затем центрируем
	var card_size := await _get_card_size(card)
	card.position = _get_spawn_position(card_size)
	_register_card(card)
	cards.append(card)
	_relayout(animated)
	emit_signal("card_added", card)
	return card


func remove_card(card: CardUI, free := true, animated := true) -> void:
	if not card:
		return
	if dragging_card == card:
		dragging_card = null
	cards.erase(card)
	if free:
		card.queue_free()
	_relayout(animated)


func layout_cards(animated := true) -> void:
	_relayout(animated)


func _register_card(card: CardUI) -> void:
	card.hovered.connect(_on_card_hovered)
	card.unhovered.connect(_on_card_unhovered)
	card.drag_started.connect(_on_card_drag_started)
	card.drag_ended.connect(_on_card_drag_ended)


func _on_card_hovered(card: CardUI) -> void:
	if dragging_card:
		_update_drag_feedback()
		return
	if layout_controller:
		layout_controller.apply_hover(cards, card, true)


func _on_card_unhovered(card: CardUI) -> void:
	if dragging_card:
		_update_drag_feedback()
		return
	if layout_controller:
		layout_controller.reset_hover(cards, true)


func _on_card_drag_started(card: CardUI) -> void:
	dragging_card = card
	card.start_drag()
	if layout_controller:
		layout_controller.reset_hover(cards, true)
	_set_play_zone_visible(true)
	card.set_playzone_highlight(false)


func _on_card_drag_ended(card: CardUI) -> void:
	if dragging_card == card:
		dragging_card = null
	_set_play_zone_visible(false)
	card.set_playzone_highlight(false)


func _process(_delta: float) -> void:
	if dragging_card:
		dragging_card.update_drag_position()
		_update_drag_feedback()


func _unhandled_input(event: InputEvent) -> void:
	if dragging_card and event is InputEventMouseButton and not event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		finish_drag()


func _input(event: InputEvent) -> void:
	if dragging_card and event is InputEventMouseButton and not event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		finish_drag()


func finish_drag() -> void:
	if not dragging_card:
		return
	var card := dragging_card
	dragging_card = null
	if _is_over_play_zone(card):
		_play_card(card)
	else:
		_return_card(card)


func _is_over_play_zone(card: CardUI) -> bool:
	if not play_zone or not card:
		return false
	if not play_zone is Control:
		return false
	var zone := play_zone as Control
	var zone_rect := Rect2(zone.global_position, zone.size)
	var card_rect := Rect2(card.global_position, card.size)
	return zone_rect.intersects(card_rect)


func _play_card(card: CardUI) -> void:
	card.end_drag()
	cards.erase(card)
	emit_signal("card_played", card.card_data)
	card.queue_free()
	_set_play_zone_visible(false)
	_relayout(true)


func _return_card(card: CardUI) -> void:
	card.end_drag()
	card.set_playzone_highlight(false)
	_set_play_zone_visible(false)
	_relayout(true)
	emit_signal("card_returned", card)


func _relayout(animated := true) -> void:
	if layout_controller and cards_container:
		layout_controller.layout_cards(cards, cards_container.size, animated)


func _get_card_size(card: CardUI) -> Vector2:
	var attempts := 3
	var size := card.size
	while size == Vector2.ZERO and attempts > 0:
		await get_tree().process_frame
		size = card.size
		attempts -= 1
	if size == Vector2.ZERO:
		size = card.get_combined_minimum_size()
	if size == Vector2.ZERO and card.card_root:
		size = card.card_root.size
	return size


func _get_play_zone_color_rect() -> ColorRect:
	if play_zone and play_zone.has_node("ColorRect"):
		return play_zone.get_node("ColorRect") as ColorRect
	return null


func _get_spawn_marker() -> Node2D:
	# Ищем маркер в инстансе HandUI: PanelRoot/HandUI/Diller/Marker2D
	if has_node("Diller/Marker2D"):
		return get_node("Diller/Marker2D") as Node2D
	if has_node("Marker2D"):
		return get_node("Marker2D") as Node2D
	return null


func _get_spawn_position(card_size: Vector2) -> Vector2:
	# Если есть маркер, спавним по его позиции (центром карточки)
	if spawn_marker and cards_container:
		var inv: Transform2D = cards_container.get_global_transform_with_canvas().affine_inverse()
		var local_center: Vector2 = inv * spawn_marker.global_position
		return local_center - card_size * 0.5
	# fallback — центр контейнера
	return cards_container.size * 0.5 - card_size * 0.5


func _set_play_zone_visible(visible: bool) -> void:
	if play_zone_color:
		play_zone_color.visible = visible
	elif play_zone:
		play_zone.visible = visible


func _update_drag_feedback() -> void:
	if not dragging_card:
		return
	_set_play_zone_visible(true)
	var over := _is_over_play_zone(dragging_card)
	var highlight := over and dragging_card.is_hovered()
	dragging_card.set_playzone_highlight(highlight)
