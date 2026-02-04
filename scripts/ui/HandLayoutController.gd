extends Node
class_name HandLayoutController

@export var spread: float = 120.0
@export var hover_offset: Vector2 = Vector2(0, -80)
@export var hover_straighten := true


func layout_cards(cards: Array, container_size: Vector2, animated := true) -> void:
	var count := cards.size()
	if count == 0:
		return
	var center_x: float = container_size.x * 0.5
	for i in count:
		var card: CardUI = cards[i]
		if not card:
			continue
		card.hand_index = i
		var x: float = center_x + (float(i) - float(count - 1) * 0.5) * spread
		var y: float = container_size.y * 0.5
		card.set_layout_target(Vector2(x, y), 0.0, animated)


func apply_hover(cards: Array, hovered: CardUI, animated := true) -> void:
	if not hovered:
		return
	hovered.raise_visual(hover_offset, hover_straighten, animated)


func reset_hover(cards: Array, animated := true) -> void:
	for card in cards:
		if card:
			card.restore_layout(animated)
