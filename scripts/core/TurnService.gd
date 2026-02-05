extends Node
class_name TurnService

# Centralized turn state holder. Source of truth for players, active player, and current day.

var players: Array = []
var active_player = null
var _active_index: int = -1
var current_day: int = 1


func reset() -> void:
	players.clear()
	active_player = null
	_active_index = -1
	current_day = 1


func register_player(player) -> void:
	if player == null:
		return
	if players.has(player):
		return
	players.append(player)
	if active_player == null:
		_active_index = 0
		active_player = player


func set_players(list: Array) -> void:
	players = list
	if players.is_empty():
		active_player = null
		_active_index = -1
	else:
		_active_index = clamp(_active_index, 0, players.size() - 1)
		active_player = players[_active_index]


func set_active_player(player) -> void:
	if player == null:
		active_player = null
		_active_index = -1
		return
	active_player = player
	_active_index = players.find(player)


func set_active_player_index(index: int) -> void:
	if index < 0 or index >= players.size():
		return
	_active_index = index
	active_player = players[index]


func next_player() -> Variant:
	if players.is_empty():
		return null
	if _active_index < 0:
		_active_index = 0
		active_player = players[_active_index]
		return active_player
	_active_index = (_active_index + 1) % players.size()
	active_player = players[_active_index]
	return active_player


func set_current_day(day: int) -> void:
	current_day = max(1, day)


func increment_day() -> int:
	current_day += 1
	return current_day


func clear_active_player() -> void:
	active_player = null
	_active_index = -1
