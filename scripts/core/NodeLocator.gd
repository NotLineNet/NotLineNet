class_name NodeLocator
extends RefCounted

static func game_manager(tree: SceneTree) -> GameManager:
	if not tree:
		return null
	return tree.get_first_node_in_group("game_manager") as GameManager

static func camera_root(owner: Node) -> CameraDrag:
	if not owner:
		return null
	var tree := owner.get_tree()
	if tree:
		var found := tree.get_first_node_in_group("camera_root") as CameraDrag
		if found:
			return found
	var via_owner := owner.get_node_or_null("../../CameraRoot") as CameraDrag
	if via_owner:
		return via_owner
	return owner.get_node_or_null("/root/Main/CameraRoot") as CameraDrag
