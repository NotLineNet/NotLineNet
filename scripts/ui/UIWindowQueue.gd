extends Node

# Minimal placeholder for the UI window queue.
# Current responsibilities: load registry, accept requests, return immediate closed handle.
# Will be expanded in later steps.

const Status := {
	"QUEUED": "QUEUED",
	"SHOWING": "SHOWING",
	"CLOSED": "CLOSED",
	"FAILED": "FAILED",
}

var registry := load("res://scripts/ui/WindowRegistry.tres")


func request_window(window_id: String, params: Dictionary = {}, priority: int = 0) -> Dictionary:
	# Stub: returns closed handle immediately; logs missing registry/window.
	var handle := {
		"window_id": window_id,
		"params": params,
		"priority": priority,
		"status": Status.CLOSED,
		"result": null,
	}
	if registry == null:
		push_warning("UIWindowQueue: registry is missing; request handled as FAILED.")
		handle.status = Status.FAILED
		return handle
	var windows := registry.get("windows", {})
	if not windows.has(window_id):
		push_warning("UIWindowQueue: window_id '%s' not registered; request handled as CLOSED." % window_id)
	return handle


func close_window(window_id: String, result: Variant = null) -> void:
	# Placeholder: no-op until real queue is implemented.
	pass
