extends Node
class_name PlayerService

# Simple registry for players. Intended to decouple player data access from GameManager.

var players: Array = []


func reset() -> void:
	players.clear()


func register_player(player) -> void:
	if player == null:
		return
	if players.has(player):
		return
	players.append(player)


func set_players(list: Array) -> void:
	players = list.duplicate()


func get_players() -> Array:
	return players
