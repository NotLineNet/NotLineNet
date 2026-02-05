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
var _bus: Node = null


func _ready() -> void:
	if registry == null:
		registry = load(registry_path)
	if registry == null:
		push_warning("UIWindowQueue: registry is missing; using empty stub.")
		registry = Resource.new()
	_bus = get_tree().root.get_node_or_null("EventBus")


func request_window(window_id: String, params: Dictionary = {}, priority: int = 0) -> Dictionary:
	var handle: Dictionary = {
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
	var effective_priority: int = int(config.get("priority", priority))
	_close_other_windows(window_id, effective_priority)
	var singleton := bool(config.get("singleton", true))
	if singleton and _active_windows.has(window_id):
		var existing: Node = _active_windows[window_id]
		_prepare_window(existing, params)
		_show_window(existing)
		handle.status = STATUS.SHOWING
		handle.instance = existing
		return handle
	var instance: Node = _resolve_window_instance(config, window_id)
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
	var instance: Node = null
	if _active_windows.has(window_id):
		instance = _active_windows[window_id]
	else:
		var node_path_value = config.get("node_path", NodePath())
		if node_path_value is String:
			node_path_value = NodePath(node_path_value)
		if node_path_value != NodePath():
			config["node_path"] = node_path_value
			instance = _resolve_window_instance(config, window_id)
	if instance == null:
		return
	_hide_window(instance)
	_active_windows.erase(window_id)
	var owned: bool = bool(_instances_owned.get(instance, false))
	_instances_owned.erase(instance)
	if owned and instance.is_inside_tree():
		instance.queue_free()
	_update_block_mode()


func _get_window_config(window_id: String) -> Dictionary:
	if registry == null:
		return {}
	var windows_variant = registry.get("windows") if registry.has_method("get") else {}
	var windows: Dictionary = windows_variant if windows_variant is Dictionary else {}
	if not windows.has(window_id):
		push_warning("UIWindowQueue: window_id '%s' not registered." % window_id)
		return {}
	var cfg = windows[window_id]
	if cfg is Dictionary:
		return cfg
	return {}


func _resolve_window_instance(config: Dictionary, window_id: String = "") -> Node:
	var tree := get_tree()
	if not tree:
		return null
	var node_path_value = config.get("node_path", NodePath())
	if node_path_value is String:
		node_path_value = NodePath(node_path_value)
	if node_path_value != NodePath():
		var node := tree.root.get_node_or_null(node_path_value)
		if node:
			return node
	if window_id != "":
		var group_name := "ui_window_%s" % window_id
		var in_group := tree.get_nodes_in_group(group_name)
		for node in in_group:
			if node is Node and is_instance_valid(node) and node.is_inside_tree() and not node.is_queued_for_deletion():
				return node
	var scene_path: String = config.get("scene_path", "")
	if scene_path != "":
		var resource := load(scene_path)
		if resource is PackedScene:
			var packed: PackedScene = resource
			var instance: Node = packed.instantiate()
			var parent := _resolve_parent(config)
			if "visible" in instance:
				instance.visible = false
			parent.add_child(instance)
			return instance
		elif resource is Script:
			var script_instance: Node = resource.new()
			if script_instance:
				var parent := _resolve_parent(config)
				if "visible" in script_instance:
					script_instance.visible = false
				parent.add_child(script_instance)
				return script_instance
	return null


func _resolve_parent(config: Dictionary) -> Node:
	var parent_path: NodePath = NodePath()
	if config.has("parent_path"):
		var raw_parent = config["parent_path"]
		if raw_parent is String:
			parent_path = NodePath(raw_parent)
		elif raw_parent is NodePath:
			parent_path = raw_parent
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
	var max_mode_value: int = INPUT_BLOCK["NONE"]
	for window_id in _active_windows.keys():
		var cfg := _get_window_config(window_id)
		var mode_name: String = cfg.get("input_block_mode", "NONE")
		var mode_value: int = INPUT_BLOCK.get(mode_name, 0)
		if mode_value > max_mode_value:
			max_mode_value = mode_value
	var new_mode: String = "NONE"
	for key in INPUT_BLOCK.keys():
		if INPUT_BLOCK[key] == max_mode_value:
			new_mode = key
			break
	if new_mode == _current_block_mode:
		return
	_current_block_mode = new_mode
	_emit_input_block_changed(new_mode)


func _emit_input_block_changed(mode: String) -> void:
	if _bus and _bus.has_method("emit"):
		_bus.emit("input_block_changed", mode)


func _close_other_windows(except_id: String, requested_priority: int) -> void:
	var to_close: Array[String] = []
	for id in _active_windows.keys():
		if id == except_id:
			continue
		var cfg := _get_window_config(id)
		var other_priority: int = int(cfg.get("priority", requested_priority))
		# Разрешаем сосуществование PlayerUI и RoomUI (одно и то же "геймплейное" окно).
		var is_player_room_pair: bool = ((id == "PLAYER_UI" and except_id == "ROOM_UI") or (id == "ROOM_UI" and except_id == "PLAYER_UI"))
		if is_player_room_pair:
			continue
		# Закрываем только окна с строго более высоким приоритетом.
		if other_priority > requested_priority:
			to_close.append(id)
	for id in to_close:
		close_window(id)
