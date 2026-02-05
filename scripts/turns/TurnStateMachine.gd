extends Node
class_name TurnStateMachine

const TurnState = preload("res://scripts/turns/TurnState.gd")
const Player = preload("res://scripts/core/Player.gd")

signal request_camera_center(player)
signal show_player_ui(player)
signal hide_player_ui()
signal enable_player_input(player)
signal disable_player_input()
signal start_combat(player, monster)
signal turns_completed
signal state_changed(state_name, player)

enum StateName {
	PREPARE_TURN,
	CHECK_PLAYER_TURN,
	PLAYER_TURN,
	CAN_PLAYER_ACT_AGAIN,
	PREPARE_END_TURN,
	END_TURN
}

var STATE_LABELS: Dictionary[StateName, String] = {
	StateName.PREPARE_TURN: "PrepareTurn",
	StateName.CHECK_PLAYER_TURN: "CheckPlayerTurn",
	StateName.PLAYER_TURN: "PlayerTurn",
	StateName.CAN_PLAYER_ACT_AGAIN: "CanPlayerActAgain",
	StateName.PREPARE_END_TURN: "PrepareEndTurn",
	StateName.END_TURN: "EndTurn"
}

var _states: Dictionary = {}
var _current: TurnState = null
var ctx: Dictionary = {}
var _deps: Dictionary = {}
var _current_state_name: StateName = StateName.PREPARE_TURN


func _ready() -> void:
	_load_states()
	set_process(true)


func set_dependencies(deps: Dictionary) -> void:
	# Expected keys (all optional):
	# - get_monster_on_tile: Callable(player) -> Monster|Nil
	# - can_player_act_again: Callable(player) -> bool
	# - get_next_player: Callable(player) -> Player|Nil
	# - set_active_player: Callable(player) -> void
	# - wait_player_ui_hidden: Callable() -> awaitable void
	# - dispose_player_ui: Callable() -> awaitable void
	# - wait_camera_centering_done: Callable() -> awaitable void
	_deps = deps


func start_for_player(player) -> void:
	ctx = {
		"machine": self,
		"player": player,
		"next_player": null
	}
	_set_state(StateName.PREPARE_TURN)


func stop() -> void:
	if _current:
		_current.exit(ctx)
	_current = null
	ctx.clear()
	_current_state_name = StateName.PREPARE_TURN


func handle_event(event: StringName, data: Variant = null) -> void:
	if _current:
		_current.handle_event(event, data, ctx)


func _process(delta: float) -> void:
	if _current:
		_current.update(delta, ctx)


func _set_state(state_name: StateName) -> void:
	_current_state_name = state_name
	if _current:
		_current.exit(ctx)
	_current = _states.get(state_name, null)
	if _current:
		var label: String = STATE_LABELS.get(state_name, "Unknown")
		var player_ref := ctx.get("player") as Player
		var player_name: String = "Unknown"
		if player_ref:
			player_name = player_ref.name
		emit_signal("state_changed", label, ctx.get("player"))
		_current.enter(ctx)

func get_current_state_name() -> StateName:
	return _current_state_name


func _load_states() -> void:
	if _states.size() > 0:
		return
	_states = {
		StateName.PREPARE_TURN: preload("res://scripts/turns/states/PrepareTurnState.gd").new(),
		StateName.CHECK_PLAYER_TURN: preload("res://scripts/turns/states/CheckPlayerTurnState.gd").new(),
		StateName.PLAYER_TURN: preload("res://scripts/turns/states/PlayerTurnState.gd").new(),
		StateName.CAN_PLAYER_ACT_AGAIN: preload("res://scripts/turns/states/CanPlayerActAgainState.gd").new(),
		StateName.PREPARE_END_TURN: preload("res://scripts/turns/states/PrepareEndTurnState.gd").new(),
		StateName.END_TURN: preload("res://scripts/turns/states/EndTurnState.gd").new()
	}
	for state in _states.values():
		add_child(state)


# Helpers to safely call dependency functions from states.
func call_dep(key: String, args: Array = []) -> Variant:
	if not _deps.has(key):
		return null
	var callable: Callable = _deps.get(key)
	if callable and callable.is_valid():
		return callable.callv(args)
	return null


func call_dep_await(key: String, args: Array = []) -> Variant:
	if not _deps.has(key):
		return null
	var callable: Callable = _deps.get(key)
	if callable and callable.is_valid():
		var result = callable.callv(args)
		return await result
	return null
