extends Node3D
class_name Monster

const GameConfig = preload("res://scripts/core/GameConfig.gd")
const MonsterManager = preload("res://scripts/core/MonsterManager.gd")

signal moved_to_tile(new_tile: Tile)

var current_tile: Tile
var level_manager: LevelManager
var is_moving := false
var is_dead := false

func initialize_on_tile(tile: Tile) -> void:
	if not tile:
		return
	current_tile = tile
	current_tile.occupying_monster = self
	global_position = tile.global_position + Vector3(0, 0.3, 0)
	level_manager = tile._get_level_manager()
	_apply_visuals_from_manager()
	if level_manager:
		level_manager.register_monster(self)

func move_to_tile(target_tile: Tile) -> void:
	if is_moving or not target_tile or not level_manager:
		return
	if target_tile == current_tile:
		return
	if target_tile.occupying_monster:
		return

	is_moving = true
	var target_position := target_tile.global_position + Vector3(0, 0.3, 0)
	var tween := create_tween()
	tween.set_ease(Tween.EASE_IN_OUT)
	tween.set_trans(Tween.TRANS_CUBIC)
	tween.tween_property(self, "global_position", target_position, GameConfig.PLAYER_MOVE_DURATION)
	await tween.finished

	if current_tile and current_tile.occupying_monster == self:
		current_tile.occupying_monster = null

	current_tile = target_tile
	current_tile.occupying_monster = self
	is_moving = false
	emit_signal("moved_to_tile", current_tile)

func despawn() -> void:
	if current_tile and current_tile.occupying_monster == self:
		current_tile.occupying_monster = null
	if level_manager:
		level_manager.unregister_monster(self)
	queue_free()

func register_death() -> void:
	is_dead = true

func _apply_visuals_from_manager() -> void:
	var manager: MonsterManager = _find_monster_manager()
	if manager and manager.has_method("apply_visuals_to_monster"):
		manager.apply_visuals_to_monster(self)

func _find_monster_manager() -> MonsterManager:
	var tree := get_tree()
	if not tree:
		return null
	return tree.get_first_node_in_group("monster_manager") as MonsterManager
