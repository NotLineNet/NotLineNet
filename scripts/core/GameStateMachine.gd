extends Node
class_name GameStateMachine

signal state_changed(new_state)

var current_state: int = 0


func set_state(new_state: int) -> void:
	if current_state == new_state:
		return
	current_state = new_state
	state_changed.emit(new_state)


func get_state() -> int:
	return current_state


func is_state(expected: int) -> bool:
	return current_state == expected
