extends Node

# Lightweight global event bus for decoupled communication between systems.
# API: subscribe(event_name, callable), unsubscribe(event_name, callable), emit(event_name, payload).

var _subscribers: Dictionary = {}


func subscribe(event_name: String, callable: Callable) -> void:
	if event_name.is_empty():
		return
	var listeners: Array = _subscribers.get(event_name, [])
	if callable in listeners:
		return
	listeners.append(callable)
	_subscribers[event_name] = listeners


func unsubscribe(event_name: String, callable: Callable) -> void:
	if not _subscribers.has(event_name):
		return
	var listeners: Array = _subscribers[event_name]
	listeners.erase(callable)
	if listeners.is_empty():
		_subscribers.erase(event_name)
	else:
		_subscribers[event_name] = listeners


func emit(event_name: String, payload: Variant = null) -> void:
	if not _subscribers.has(event_name):
		return
	var listeners: Array = _subscribers[event_name].duplicate()
	for listener in listeners:
		if not listener.is_valid():
			_subscribers[event_name].erase(listener)
			continue
		listener.call(payload)
	if _subscribers.get(event_name, []).is_empty():
		_subscribers.erase(event_name)
