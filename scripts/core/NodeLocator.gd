class_name NodeLocator
extends RefCounted

static func _main(tree: SceneTree) -> Node:
	if not tree:
		return null
	return tree.root.get_node_or_null("Main")


static func game_manager(tree: SceneTree) -> GameManager:
	if not tree:
		return null
	var main := _main(tree)
	if main:
		var gm := main.get_node_or_null("GameManager") as GameManager
		if gm:
			return gm
	return tree.root.get_node_or_null("GameManager") as GameManager


static func level_manager(tree: SceneTree) -> LevelManager:
	if not tree:
		return null
	var main := _main(tree)
	if main:
		var lm := main.get_node_or_null("LevelManager") as LevelManager
		if lm:
			return lm
	return tree.root.get_node_or_null("LevelManager") as LevelManager


static func monster_manager(tree: SceneTree) -> MonsterManager:
	if not tree:
		return null
	var main := _main(tree)
	if main:
		var mm := main.get_node_or_null("MonsterManager") as MonsterManager
		if mm:
			return mm
	return tree.root.get_node_or_null("MonsterManager") as MonsterManager


static func camera_root(owner: Node) -> CameraDrag:
	if not owner:
		return null
	var tree := owner.get_tree()
	var main := _main(tree) if tree else null
	if main:
		var cam := main.get_node_or_null("CameraRoot") as CameraDrag
		if cam:
			return cam
	var via_owner := owner.get_node_or_null("../../CameraRoot") as CameraDrag
	if via_owner:
		return via_owner
	return owner.get_node_or_null("/root/Main/CameraRoot") as CameraDrag
