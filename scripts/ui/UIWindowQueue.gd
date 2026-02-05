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

const INPUT_BLOCK := {
	"NONE": 0,
	"GAMEPLAY": 1,
	"FULL": 2,
}

@export var registry_path: String = "res://scripts/ui/WindowRegistry.tres"

var registry: Resource
var _active_windows: Dictionary = {}
var _instances_owned: Dictionary = {}
var _current_block_mode: String = "NONE"


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
	var singleton := bool(config.get("singleton", true))
	if singleton and _active_windows.has(window_id):
		var existing := _active_windows[window_id]
		_prepare_window(existing, params)
		_show_window(existing)
		handle.status = STATUS.SHOWING
		handle.instance = existing
		return handle
	var instance := _resolve_window_instance(config)
	if instance == null:
		push_warning("UIWindowQueue: window '%s' instance not found." % window_id)
		return handle
	_prepare_window(instance, params)
	_show_window(instance)
	_active_windows[window_id] = instance
	_instances_owned[instance] = not singleton
	handle.status = STATUS.SHOWING
	handle.instance = instance
	_update_block_mode()
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
	if _instances_owned.get(instance, false):
		if instance.is_inside_tree():
			instance.queue_free()
		_instances_owned.erase(instance)
	_update_block_mode()


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
	var scene_path: String = config.get("scene_path", "")
	if scene_path != "":
		var resource := load(scene_path)
		if resource is PackedScene:
			var packed: PackedScene = resource
			var instance := packed.instantiate()
			var parent := _resolve_parent(config)
			parent.add_child(instance)
			return instance
		elif resource is Script:
			var script_instance := resource.new()
			if script_instance is Node:
				var parent := _resolve_parent(config)
				parent.add_child(script_instance)
				return script_instance
	return null


func _resolve_parent(config: Dictionary) -> Node:
	var parent_path := config.get("parent_path", NodePath())
	if parent_path is String:
		parent_path = NodePath(parent_path)
	if parent_path != NodePath():
		var node := get_tree().root.get_node_or_null(parent_path)
		if node:
			return node
	return get_tree().root


func _prepare_window(window: Node, params: Dictionary) -> void:
	if window.has_method("prepare"):
		window.call("prepare", params)


func _show_window(window: Node) -> void:
	if window.has_method("ensure_shown"):
		window.call("ensure_shown")
		return
	if window.has_method("show_room_ui"):
		window.call("show_room_ui")
		return
	if window.has_method("show_player_ui"):
		window.call("show_player_ui")
		return
	if window.has_method("show_animated"):
		window.call("show_animated")
		return
	if window.has_method("show"):
		window.show()
	_update_block_mode()


func _hide_window(window: Node) -> void:
	if window.has_method("hide_room_ui"):
		window.call("hide_room_ui")
		return
	if window.has_method("hide_player_ui"):
		window.call("hide_player_ui")
		return
	if window.has_method("hide_animated"):
		window.call("hide_animated")
		return
	if window.has_method("hide"):
		window.hide()
	_update_block_mode()


func _update_block_mode() -> void:
	var max_mode_value := INPUT_BLOCK["NONE"]
	for window_id in _active_windows.keys():
		var cfg := _get_window_config(window_id)
		var mode_name: String = cfg.get("input_block_mode", "NONE")
		var mode_value := INPUT_BLOCK.get(mode_name, 0)
		if mode_value > max_mode_value:
			max_mode_value = mode_value
	var new_mode := "NONE"
	for key in INPUT_BLOCK.keys():
		if INPUT_BLOCK[key] == max_mode_value:
			new_mode = key
			break
	if new_mode == _current_block_mode:
		return
	_current_block_mode = new_mode
	_emit_input_block_changed(new_mode)


func _emit_input_block_changed(mode: String) -> void:
	var bus := get_tree().root.get_node_or_null("EventBus")
	if bus and bus.has_method("emit"):
		bus.emit("input_block_changed", mode)
