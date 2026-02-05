extends Node
class_name TileService

# Registry for tiles by grid position.

var tiles: Dictionary = {}


func reset() -> void:
	clear()


func register_tile(pos: Vector2i, tile: Node) -> void:
	if tile == null:
		return
	tiles[pos] = tile


func unregister_tile(pos: Vector2i) -> void:
	if tiles.has(pos):
		tiles.erase(pos)


func clear() -> void:
	tiles.clear()


func has_tile(pos: Vector2i) -> bool:
	return tiles.has(pos)


func get_tile(pos: Vector2i) -> Node:
	return tiles.get(pos, null)
