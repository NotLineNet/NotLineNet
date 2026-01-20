extends Node3D
class_name Player

var current_tile: Tile
var action_points: int = 3

func place_on_tile(tile: Tile):
	current_tile = tile
	global_position = tile.global_position + Vector3(0, 0.6, 0)

func can_move_to(tile: Tile) -> bool:
	if action_points <= 0:
		return false
	return current_tile.is_connected_to(tile)

func move_to(tile: Tile):
	if not can_move_to(tile):
		return

	action_points -= 1
	place_on_tile(tile)
