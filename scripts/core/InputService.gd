extends Node

# Placeholder for centralized input handling.
# Currently no-op to avoid changing gameplay behavior.

var blocked_mode := "NONE"
var _bus


func block_input(mode: String) -> void:
	blocked_mode = mode


func unblock_input() -> void:
	blocked_mode = "NONE"


func is_blocked() -> bool:
	return blocked_mode != "NONE"


func get_block_mode() -> String:
	return blocked_mode


func _ready() -> void:
	_bus = get_tree().root.get_node_or_null("EventBus")
	if _bus and _bus.has_method("subscribe"):
		_bus.subscribe("input_block_changed", Callable(self, "_on_input_block_changed"))


func _on_input_block_changed(mode: String) -> void:
	blocked_mode = mode
