extends Node

# Minimal UI window queue stub.
# Current responsibilities:
# - load registry
# - resolve window instance (existing node_path)
# - show/hide window via known methods
# - return handle with status/instance
# Will be expanded with real queuing later.

const STATUS := {
	"QUEUED": "QUEUED",
	"SHOWING": "SHOWING",
	"CLOSED": "CLOSED",
	"FAILED": "FAILED",
}

@export var registry_path: String = "res://scripts/ui/WindowRegistry.tres"

var registry: Resource
var _active_windows: Dictionary = {}


func _ready() -> void:
	if registry == null:
		registry = load(registry_path)
	if registry == null:
		push_warning("UIWindowQueue: registry is missing; using empty stub.")
		registry = Resource.new()


func request_window(window_id: String, params: Dictionary = {}, priority: int = 0) -> Dictionary:
	var handle := {
		"window_id": window_id,
		"params": params,
		"priority": priority,
		"status": STATUS.FAILED,
		"result": null,
		"instance": null,
	}
	var config := _get_window_config(window_id)
	if config.is_empty():
		return handle
	var instance := _resolve_window_instance(config)
	if instance == null:
		push_warning("UIWindowQueue: window '%s' instance not found." % window_id)
		return handle
	_prepare_window(instance, params)
	_show_window(instance)
	_active_windows[window_id] = instance
	handle.status = STATUS.SHOWING
	handle.instance = instance
	return handle


func close_window(window_id: String, result: Variant = null) -> void:
	var config := _get_window_config(window_id)
	if config.is_empty():
		return
	var instance := _active_windows.get(window_id, _resolve_window_instance(config))
	if instance == null:
		return
	_hide_window(instance)
	_active_windows.erase(window_id)


func _get_window_config(window_id: String) -> Dictionary:
	if registry == null:
		return {}
	var windows := registry.get("windows", {})
	if not windows.has(window_id):
		push_warning("UIWindowQueue: window_id '%s' not registered." % window_id)
		return {}
	var cfg = windows[window_id]
	if cfg is Dictionary:
		return cfg
	return {}


func _resolve_window_instance(config: Dictionary) -> Node:
	var node_path_value = config.get("node_path", NodePath())
	if node_path_value is String:
		node_path_value = NodePath(node_path_value)
	if node_path_value != NodePath():
		var node := get_tree().root.get_node_or_null(node_path_value)
		if node:
			return node
	# Placeholder: no instantiation logic yet.
	return null


func _prepare_window(window: Node, params: Dictionary) -> void:
	if window.has_method("prepare"):
		window.call("prepare", params)


func _show_window(window: Node) -> void:
	if window.has_method("ensure_shown"):
		window.call("ensure_shown")
		return
	if window.has_method("show_player_ui"):
		window.call("show_player_ui")
		return
	if window.has_method("show_animated"):
		window.call("show_animated")
		return
	if window.has_method("show"):
		window.show()


func _hide_window(window: Node) -> void:
	if window.has_method("hide_player_ui"):
		window.call("hide_player_ui")
		return
	if window.has_method("hide_animated"):
		window.call("hide_animated")
		return
	if window.has_method("hide"):
		window.hide()
