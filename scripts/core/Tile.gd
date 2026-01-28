extends Node3D
class_name Tile
const GameConfig = preload("res://scripts/core/GameConfig.gd")
const MarkerUI = preload("res://scripts/ui/MarkerUI.gd")

enum RoomType {
	EMPTY,
	CHEST,
	AMBUSH,
	MONSTER
}

const ROOM_TYPE_WEIGHTS := [
	{"type": RoomType.EMPTY, "weight": 0},
	{"type": RoomType.CHEST, "weight": 0},
	{"type": RoomType.AMBUSH, "weight": 0},
	{"type": RoomType.MONSTER, "weight": 1}
]

const ROOM_SCENES := {
	RoomType.CHEST: preload("res://scenes/tile/Ellements/Chest.tscn"),
	RoomType.AMBUSH: preload("res://scenes/tile/Ellements/Ambush.tscn"),
	RoomType.MONSTER: preload("res://scenes/monster/Monster.tscn")
}

var room_type: int = RoomType.EMPTY
var room_assigned := false
var room_content: Node3D
var _chest_button: Control
var _chest_marker: Node3D
var _marker_ui: MarkerUI
var _chest_button_callable: Callable
var has_opened := false

enum WallVisual {
	BLOCKED,
	DOOR,
	LOCKED_DOOR,
	OPENED
}

const WALL_SCENE_FOR_VISUAL := {
	WallVisual.BLOCKED: preload("res://scenes/tile/walls/BlockedWall.tscn"),
	WallVisual.DOOR: preload("res://scenes/tile/walls/DoorWall.tscn"),
	WallVisual.LOCKED_DOOR: preload("res://scenes/tile/walls/LocedDoorWall.tscn"),
	WallVisual.OPENED: preload("res://scenes/tile/walls/OpenedWall.tscn")
}
const WALL_DIRECTION_TO_NODE := {
	Vector2i(0, -1): "UPWall",
	Vector2i(0, 1): "DownWall",
	Vector2i(-1, 0): "LeftWall",
	Vector2i(1, 0): "RightWall"
}
const UNSET_WALL_VISUAL := -1
const DOOR_BREAK_DURATION := 0.5

@export var locked_wall_chance: float = 0.05
@export var door_wall_chance: float = 0.15

signal exit_clicked(tile: Tile, dir: Vector2i)
signal tile_clicked(tile: Tile)

var grid_pos: Vector2i
var exits: Array[Vector2i] = []
var exit_markers: Dictionary = {}  # Хранит маркеры выходов по направлению
var base_room: Node3D
var wall_assignments: Dictionary = {}
var walls_initialized := false
var occupying_monster: Node3D

const EXIT_MARKER_SIZE := GameConfig.EXIT_MARKER_SIZE
const EXIT_OFFSET := GameConfig.EXIT_OFFSET
const HOVER_SCALE := GameConfig.HOVER_SCALE
const NORMAL_SCALE := GameConfig.NORMAL_SCALE

const GATE_COLOR_ACTIVE := GameConfig.GATE_COLOR_ACTIVE
const GATE_COLOR_INACTIVE := GameConfig.GATE_COLOR_INACTIVE

func set_color(color: Color):
	var mesh_instance := get_node_or_null("MeshInstance3D")
	if mesh_instance:
		var material := StandardMaterial3D.new()
		material.albedo_color = color
		mesh_instance.material_override = material

func _ready():
	base_room = get_node_or_null("BaseRoom")
	# Подключаем обработчик клика на Area3D
	var area := get_node_or_null("Area3D")
	if area:
		area.input_event.connect(_on_area_input_event)
	
	var active_player := _get_active_player()
	if active_player:
		var half_tile := GameConfig.TILE_SIZE * 0.5
		var player_pos = Vector2i(round(active_player.global_position.x / half_tile), round(active_player.global_position.z / half_tile))
		if player_pos == grid_pos:
			on_player_entered()
	if not _chest_button_callable:
		_chest_button_callable = Callable(self, "_on_chest_button_pressed")
	_ensure_room_content_parent()

func _on_area_input_event(_camera: Node, event: InputEvent, _position: Vector3, _normal: Vector3, _shape_idx: int):
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		tile_clicked.emit(self)

func redraw_exit_markers():
	# Очищаем старые маркеры
	for child in get_children():
		if child.name.begins_with("ExitMarker"):
			child.queue_free()
	exit_markers.clear()

	var idx := 0
	for dir: Vector2i in exits:
		var marker := Area3D.new()
		marker.name = "ExitMarker_%d" % idx
		marker.input_ray_pickable = true  # Включаем обнаружение мыши
		idx += 1

		var mesh := MeshInstance3D.new()
		mesh.name = "MeshInstance3D"
		var box := BoxMesh.new()
		box.size = EXIT_MARKER_SIZE
		mesh.mesh = box

		var mat := StandardMaterial3D.new()
		mat.albedo_color = _get_gate_color_for_dir(dir)
		mesh.material_override = mat

		marker.add_child(mesh)

		var shape := CollisionShape3D.new()
		var box_shape := BoxShape3D.new()
		box_shape.size = EXIT_MARKER_SIZE
		shape.shape = box_shape
		marker.add_child(shape)

		marker.position = Vector3(
			dir.x * EXIT_OFFSET,
			0.3,
			dir.y * EXIT_OFFSET
		)
		
		# Инициализируем масштаб
		marker.scale = Vector3.ONE * NORMAL_SCALE

		# Подключаем обработчики событий мыши
		marker.mouse_entered.connect(_on_exit_marker_mouse_entered.bind(dir))
		marker.mouse_exited.connect(_on_exit_marker_mouse_exited.bind(dir))
		marker.input_event.connect(_on_exit_marker_input_event.bind(dir))

		add_child(marker)
		exit_markers[dir] = marker

func _get_current_gate_color() -> Color:
	var active_player := _get_active_player()
	if not active_player:
		return GATE_COLOR_INACTIVE

	if active_player.current_tile != self:
		return GATE_COLOR_INACTIVE

	if active_player.action_points > GameConfig.MIN_ACTION_POINTS:
		return GATE_COLOR_ACTIVE

	return GATE_COLOR_INACTIVE

func _get_gate_color_for_dir(dir: Vector2i, force_inactive: bool = false) -> Color:
	if force_inactive:
		return GATE_COLOR_INACTIVE
	# Базовый цвет зависит от наличия ОД и позиции игрока
	var base_color := _get_current_gate_color()
	# Если в направлении запертая дверь, маркер всегда серый
	if wall_visual_for_direction(dir) == WallVisual.LOCKED_DOOR:
		return GATE_COLOR_INACTIVE
	return base_color

func on_player_entered():
	if not has_opened:
		show_tile()
	_update_gate_colors()
	_handle_room_player_entered()

func on_player_exited():
	_update_gate_colors(true)
	_handle_room_player_exited()

func _update_gate_colors(force_inactive: bool = false):
	for dir in exit_markers.keys():
		var marker: Area3D = exit_markers.get(dir) as Area3D
		var mesh = marker.get_node_or_null("MeshInstance3D")
		if mesh:
			if not mesh.material_override:
				mesh.material_override = StandardMaterial3D.new()
			mesh.material_override.albedo_color = _get_gate_color_for_dir(dir, force_inactive)
		else:
			print("Tile %s: MeshInstance3D not found in marker %s" % [str(grid_pos), marker.name])

func _on_exit_marker_mouse_entered(dir: Vector2i):
	"""Обработчик наведения мыши на маркер выхода"""
	# Увеличиваем масштаб только если игрок на этом тайле и не движется
	if _can_interact_with_exits():
		var marker: Area3D = exit_markers.get(dir) as Area3D
		if marker:
			var tween := create_tween()
			tween.set_ease(Tween.EASE_OUT)
			tween.set_trans(Tween.TRANS_QUAD)
			tween.tween_property(marker, "scale", Vector3.ONE * HOVER_SCALE, 0.1)

func _on_exit_marker_mouse_exited(dir: Vector2i):
	"""Обработчик ухода мыши с маркера выхода"""
	var marker: Area3D = exit_markers.get(dir) as Area3D
	if marker:
		var tween := create_tween()
		tween.set_ease(Tween.EASE_OUT)
		tween.set_trans(Tween.TRANS_QUAD)
		tween.tween_property(marker, "scale", Vector3.ONE * NORMAL_SCALE, 0.1)

func _on_exit_marker_input_event(_cam: Node, event: InputEvent, _pos: Vector3, _norm: Vector3, _idx: int, dir: Vector2i):
	"""Обработчик клика на маркер выхода"""
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		# Проверяем, что можно взаимодействовать с выходами
		if _can_interact_with_exits():
			# Возвращаем масштаб к нормальному при клике
			var marker: Area3D = exit_markers.get(dir) as Area3D
			if marker:
				var tween := create_tween()
				tween.set_ease(Tween.EASE_OUT)
				tween.set_trans(Tween.TRANS_QUAD)
				tween.tween_property(marker, "scale", Vector3.ONE * NORMAL_SCALE, 0.1)
			
			exit_clicked.emit(self, dir)

func _can_interact_with_exits() -> bool:
	"""Проверяет, можно ли взаимодействовать с выходами (игрок на тайле и не движется)"""
	var active_player := _get_active_player()
	if not active_player:
		return false
	var gm := _get_game_manager()
	if gm and gm.state != gm.GameState.DAY:
		return false

	# Проверяем, что игрок на этом тайле и не движется
	return active_player.current_tile == self and not active_player.is_moving

func _get_game_manager() -> GameManager:
	var tree := get_tree()
	if not tree:
		return null
	return tree.get_first_node_in_group("game_manager") as GameManager

func _get_active_player() -> Player:
	var gm := _get_game_manager()
	if gm:
		return gm.active_player
	return null

func _get_level_manager() -> LevelManager:
	var tree := get_tree()
	if not tree:
		return null
	return tree.get_first_node_in_group("level_manager") as LevelManager

func wall_visual_for_direction(dir: Vector2i) -> int:
	if not wall_assignments.has(dir):
		return UNSET_WALL_VISUAL
	var state: Dictionary = wall_assignments[dir] as Dictionary
	if state.has("visual"):
		return state["visual"] as int
	return UNSET_WALL_VISUAL

func wall_owner_for_direction(dir: Vector2i) -> Tile:
	if not wall_assignments.has(dir):
		return self
	var state: Dictionary = wall_assignments[dir] as Dictionary
	if state.has("owner"):
		return state["owner"] as Tile
	return self

func _assign_wall_visual(dir: Vector2i, visual: int, owner: Tile, propagate: bool = true) -> void:
	wall_assignments[dir] = {"visual": visual, "owner": owner}
	if propagate:
		_propagate_to_neighbor(dir, visual, owner)

func _propagate_to_neighbor(dir: Vector2i, visual: int, owner: Tile) -> void:
	var level_manager := _get_level_manager()
	if not level_manager:
		return
	var neighbor_pos: Vector2i = grid_pos + dir
	if not level_manager.tiles.has(neighbor_pos):
		return
	var neighbor := level_manager.tiles[neighbor_pos] as Tile
	neighbor._assign_wall_visual(-dir, visual, owner, false)

func _determine_visual_for_exit() -> int:
	var locked: float = clamp(locked_wall_chance, 0.0, 1.0)
	var door: float = clamp(door_wall_chance, 0.0, max(0.0, 1.0 - locked))
	var roll: float = randf()
	if roll < locked:
		return WallVisual.LOCKED_DOOR
	if roll < locked + door:
		return WallVisual.DOOR
	return WallVisual.OPENED

func _neighbor_has_visual(dir: Vector2i) -> bool:
	var level_manager := _get_level_manager()
	if not level_manager:
		return false
	var neighbor_pos: Vector2i = grid_pos + dir
	if not level_manager.tiles.has(neighbor_pos):
		return false
	var neighbor := level_manager.tiles[neighbor_pos] as Tile
	return neighbor and neighbor.walls_initialized

func _refresh_wall_scene(dir: Vector2i, visual: int) -> void:
	if wall_owner_for_direction(dir) != self:
		return
	var container := get_node_or_null("WallsContainer") as Node3D
	if not container:
		return
	var wall_name: String = WALL_DIRECTION_TO_NODE.get(dir, "")
	if wall_name == "":
		return
	var wall_holder := container.get_node_or_null(wall_name) as Node3D
	if not wall_holder:
		return
	for child in wall_holder.get_children():
		child.queue_free()
	var scene: PackedScene = WALL_SCENE_FOR_VISUAL.get(visual, null) as PackedScene
	if scene:
		var wall_instance := scene.instantiate() as Node3D
		if wall_instance:
			wall_holder.add_child(wall_instance)

func _apply_wall_visual(dir: Vector2i, visual: int) -> void:
	_assign_wall_visual(dir, visual, self)
	_refresh_wall_scene(dir, visual)

func trigger_door_break(dir: Vector2i) -> void:
	if wall_visual_for_direction(dir) != WallVisual.DOOR:
		return

	var owner := wall_owner_for_direction(dir)
	if owner and owner != self:
		owner.trigger_door_break(-dir)
		return

	if not owner:
		owner = self
	_assign_wall_visual(dir, WallVisual.OPENED, owner)

	var container := get_node_or_null("WallsContainer") as Node3D
	var wall_holder: Node3D = null
	if container:
		var wall_name: String = WALL_DIRECTION_TO_NODE.get(dir, "")
		if wall_name != "":
			wall_holder = container.get_node_or_null(wall_name) as Node3D
	var door_node: Node3D = null
	if wall_holder and wall_holder.get_child_count() > 0:
		door_node = wall_holder.get_child(0) as Node3D
	var animation_player: AnimationPlayer = null
	if door_node:
		animation_player = door_node.get_node_or_null("AnimationPlayer") as AnimationPlayer
	if animation_player and animation_player.has_animation("Break_Door"):
		animation_player.play("Break_Door")
		_finalize_broken_door(dir)
	else:
		_refresh_wall_scene(dir, WallVisual.OPENED)
		var level_manager := _get_level_manager()
		if level_manager:
			var neighbor_pos: Vector2i = grid_pos + dir
			if level_manager.tiles.has(neighbor_pos):
				var neighbor := level_manager.tiles[neighbor_pos] as Tile
				neighbor._refresh_wall_scene(-dir, WallVisual.OPENED)

func _finalize_broken_door(dir: Vector2i) -> void:
	await get_tree().create_timer(DOOR_BREAK_DURATION).timeout
	_refresh_wall_scene(dir, WallVisual.OPENED)
	var level_manager := _get_level_manager()
	if level_manager:
		var neighbor_pos: Vector2i = grid_pos + dir
		if level_manager.tiles.has(neighbor_pos):
			var neighbor := level_manager.tiles[neighbor_pos] as Tile
			neighbor._refresh_wall_scene(-dir, WallVisual.OPENED)

func _ensure_walls_created() -> void:
	if walls_initialized:
		return
	var container := get_node_or_null("WallsContainer") as Node3D
	if not container:
		return
	for dir in WALL_DIRECTION_TO_NODE.keys():
		var visual := wall_visual_for_direction(dir)
		var owner := wall_owner_for_direction(dir)
		if visual == UNSET_WALL_VISUAL:
			var has_exit := exits.has(dir)
			if has_exit:
				visual = _determine_visual_for_exit()
			else:
				visual = WallVisual.BLOCKED
			var assigned_owner: Tile = self
			if has_exit and _neighbor_has_visual(dir):
				var level_manager := _get_level_manager()
				if level_manager:
					var neighbor_pos: Vector2i = grid_pos + dir
					if level_manager.tiles.has(neighbor_pos):
						assigned_owner = level_manager.tiles[neighbor_pos] as Tile
			_assign_wall_visual(dir, visual, assigned_owner)
			owner = assigned_owner
		else:
			if owner == self:
				_propagate_to_neighbor(dir, visual, self)
		if owner == self:
			_refresh_wall_scene(dir, visual)
	walls_initialized = true

func hide_tile():
	_remove_chest_button()
	if base_room:
		base_room.visible = false
	for marker in exit_markers.values():
		marker.input_ray_pickable = false
		var shape := marker.get_node_or_null("CollisionShape3D") as CollisionShape3D
		if shape:
			shape.disabled = true

func show_tile():
	_ensure_walls_created()
	if base_room:
		base_room.visible = true
	for marker in exit_markers.values():
		marker.input_ray_pickable = true
		var shape := marker.get_node_or_null("CollisionShape3D") as CollisionShape3D
		if shape:
			shape.disabled = false
	_ensure_room_generated()
	if not has_opened:
		has_opened = true

func _ensure_room_generated() -> void:
	if room_assigned:
		return
	room_assigned = true
	room_type = _pick_room_type()
	_spawn_room_content()

func force_empty_room() -> void:
	room_assigned = true
	room_type = RoomType.EMPTY
	_clear_room_content()
	_clear_monster()
func _handle_room_player_entered() -> void:
	var player := _get_active_player()
	if not player:
		return

	if occupying_monster:
		var gm := _get_game_manager()
		if gm and gm.has_method("start_monster_battle"):
			gm.start_monster_battle(player, occupying_monster)
		return

	match room_type:
		RoomType.CHEST:
			_show_chest_button()
		RoomType.AMBUSH:
			_trigger_ambush(player)
		_:
			pass

func _handle_room_player_exited() -> void:
	if room_type == RoomType.CHEST:
		_remove_chest_button()

func _get_marker_ui() -> MarkerUI:
	if _marker_ui and is_instance_valid(_marker_ui):
		return _marker_ui
	var tree := get_tree()
	if not tree:
		return null
	_marker_ui = tree.get_first_node_in_group("marker_ui") as MarkerUI
	return _marker_ui

func _register_chest_button() -> void:
	if room_type != RoomType.CHEST:
		return
	if not room_content:
		return
	var marker := room_content.get_node_or_null("Marker3D") as Node3D
	if not marker:
		return
	if _chest_marker == marker and _chest_button and is_instance_valid(_chest_button):
		return
	var marker_ui := _get_marker_ui()
	if not marker_ui:
		return
	_chest_marker = marker
	if not _chest_button_callable:
		_chest_button_callable = Callable(self, "_on_chest_button_pressed")
	_chest_button = marker_ui.register_chest_marker(marker, _chest_button_callable)

func _show_chest_button() -> void:
	_register_chest_button()

func _remove_chest_button() -> void:
	if _marker_ui and is_instance_valid(_marker_ui) and _chest_marker:
		_marker_ui.unregister_marker(_chest_marker)
	_chest_button = null
	_chest_marker = null

func _on_chest_button_pressed() -> void:
	var player := _get_active_player()
	if player:
		player.add_action_point()

	_clear_room_content()
	room_type = RoomType.EMPTY

func _trigger_ambush(player: Player) -> void:
	if not room_content:
		return
	player.play_ambush_damage_animation()
	player.spend_action_point()
	_clear_room_content()
	room_type = RoomType.EMPTY

func _clear_room_content() -> void:
	_remove_chest_button()
	if room_content and room_content.is_inside_tree():
		room_content.queue_free()
	room_content = null

func _clear_monster() -> void:
	if occupying_monster:
		occupying_monster.despawn()
	occupying_monster = null

func _pick_room_type() -> int:
	var roll := randf()
	var cumulative := 0.0
	for entry in ROOM_TYPE_WEIGHTS:
		cumulative += entry["weight"]
		if roll < cumulative:
			return entry["type"]
	return RoomType.EMPTY

func _spawn_room_content() -> void:
	if room_type == RoomType.MONSTER:
		_spawn_monster()
		return

	if not ROOM_SCENES.has(room_type):
		return
	var scene := ROOM_SCENES[room_type] as PackedScene
	if not scene:
		return
	var instance := scene.instantiate() as Node3D
	if not instance:
		return

	add_child(instance)
	room_content = instance
	_ensure_room_content_parent()
	if room_type == RoomType.CHEST:
		_register_chest_button()

func _spawn_monster() -> void:
	var scene := ROOM_SCENES.get(RoomType.MONSTER, null) as PackedScene
	if not scene:
		return
	var instance := scene.instantiate() as Node3D
	if not instance:
		return

	var monster_root := _get_monster_root()
	if not monster_root:
		instance.queue_free()
		return

	monster_root.add_child(instance)
	if instance.has_method("initialize_on_tile"):
		instance.call("initialize_on_tile", self)

func _get_monster_root() -> Node3D:
	var level_manager := _get_level_manager()
	if not level_manager:
		return null
	var parent_node := level_manager.get_parent()
	if not parent_node:
		return null
	return parent_node.get_node_or_null("MonsterRoot") as Node3D

func _ensure_room_content_parent() -> void:
	if not room_content:
		return
	var current_parent := room_content.get_parent()
	if base_room:
		if current_parent != base_room:
			if current_parent:
				current_parent.remove_child(room_content)
			base_room.add_child(room_content)
	else:
		if current_parent != self:
			if current_parent:
				current_parent.remove_child(room_content)
			add_child(room_content)
