extends Control
class_name HandUI

signal card_played(card_data)
signal card_returned(card)
signal card_added(card)

@export var card_scene: PackedScene = preload("res://scenes/ui/CardUI.tscn")
@export var play_zone: Control

@onready var cards_container: Control = get_node_or_null("CardsContainer") as Control
@onready var layout_controller: HandLayoutController = get_node_or_null("LayoutController") as HandLayoutController

var cards: Array[CardUI] = []
var dragging_card: CardUI


func _ready():
	if not layout_controller:
		layout_controller = HandLayoutController.new()
		add_child(layout_controller)
	set_process(true)
	set_process_input(true)
	set_process_unhandled_input(true)
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
	if card_data == null:
		card_data = {}
	card.set_card_data(card_data)
	cards_container.add_child(card)
	# Ждём, когда размеры вычислятся, затем центрируем
	await get_tree().process_frame
	# position + pivot_offset = мировая позиция центра, поэтому вычитаем половину размера
	card.position = cards_container.size * 0.5 - card.size * 0.5
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
		return
	if layout_controller:
		layout_controller.apply_hover(cards, card, true)


func _on_card_unhovered(card: CardUI) -> void:
	if dragging_card:
		return
	if layout_controller:
		layout_controller.reset_hover(cards, true)


func _on_card_drag_started(card: CardUI) -> void:
	dragging_card = card
	card.start_drag()
	if layout_controller:
		layout_controller.reset_hover(cards, true)


func _on_card_drag_ended(card: CardUI) -> void:
	if dragging_card == card:
		dragging_card = null


func _process(_delta: float) -> void:
	if dragging_card:
		dragging_card.update_drag_position()


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
	return zone_rect.has_point(get_global_mouse_position())


func _play_card(card: CardUI) -> void:
	card.end_drag()
	cards.erase(card)
	emit_signal("card_played", card.card_data)
	card.queue_free()
	_relayout(true)


func _return_card(card: CardUI) -> void:
	card.end_drag()
	_relayout(true)
	emit_signal("card_returned", card)


func _relayout(animated := true) -> void:
	if layout_controller and cards_container:
		layout_controller.layout_cards(cards, cards_container.size, animated)
