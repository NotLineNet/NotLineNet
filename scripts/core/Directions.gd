extends Node

const UP := Vector2i(0, -1)
const DOWN := Vector2i(0, 1)
const LEFT := Vector2i(-1, 0)
const RIGHT := Vector2i(1, 0)

const ALL: Array[Vector2i] = [UP, DOWN, LEFT, RIGHT]

static func opposite(dir: Vector2i) -> Vector2i:
	return -dir
