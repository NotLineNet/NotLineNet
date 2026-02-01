extends Node
class_name BattleState

# Base interface for battle states.
# Concrete states override enter/exit and optionally update/handle_event.

func enter(ctx: Dictionary) -> void:
	pass


func exit(ctx: Dictionary) -> void:
	pass


func update(delta: float, ctx: Dictionary) -> void:
	pass


func handle_event(event: StringName, data: Variant, ctx: Dictionary) -> void:
	pass
