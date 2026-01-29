extends Node
class_name TurnState

# Base interface for turn states.
# Every concrete state should implement enter/exit and optionally update/handle_event.

func enter(ctx: Dictionary) -> void:
	pass


func exit(ctx: Dictionary) -> void:
	pass


func update(delta: float, ctx: Dictionary) -> void:
	pass


func handle_event(event: StringName, data: Variant, ctx: Dictionary) -> void:
	pass
