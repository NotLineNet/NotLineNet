extends Node
class_name BattleService

# Placeholder battle coordinator to decouple battle orchestration from GameManager.

var current_context: Dictionary = {}
var battle_active := false


func start_battle(ctx: Dictionary) -> bool:
	# Not implemented yet; legacy GameManager flow remains in control.
	return false


func finish_battle() -> void:
	battle_active = false
	current_context.clear()
