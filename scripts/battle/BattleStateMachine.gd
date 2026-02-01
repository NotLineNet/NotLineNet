extends Node
class_name BattleStateMachine

const BattleState = preload("res://scripts/battle/BattleState.gd")

signal state_changed(state_name: String, ctx: Dictionary)
signal battle_finished(result_ctx: Dictionary)

enum StateName {
	PREPARE_BATTLE,
	DICE_CHECK,
	PREPARE_PLAYER_CHOICE,
	PLAYER_CHOICE,
	PREPARE_END_BATTLE,
	END_BATTLE
}

var STATE_LABELS: Dictionary[StateName, String] = {
	StateName.PREPARE_BATTLE: "PrepareBattle",
	StateName.DICE_CHECK: "DiceCheck",
	StateName.PREPARE_PLAYER_CHOICE: "PreparePlayerChoice",
	StateName.PLAYER_CHOICE: "PlayerChoice",
	StateName.PREPARE_END_BATTLE: "PrepareEndBattle",
	StateName.END_BATTLE: "EndBattle"
}

var _states: Dictionary = {}
var _current: BattleState = null
var _deps: Dictionary = {}
var ctx: Dictionary = {}
var _current_state_name: StateName = StateName.PREPARE_BATTLE
var _running := false


func _ready() -> void:
	_load_states()
	set_process(true)


func set_dependencies(deps: Dictionary) -> void:
	# Expected optional keys (Callable):
	# show_battle_ui(battle_type: String) -> awaitable void
	# hide_battle_ui() -> awaitable void
	# hide_player_ui() -> void
	# show_player_ui(player) -> void
	# enter_battle_room_ui(player) -> void
	# exit_battle_room_ui() -> void
	# disable_player_input() -> void
	# enable_player_input(player) -> void
	# play_camera_hit(player_won: bool) -> awaitable void
	# run_dice_game(player, monster) -> awaitable Array
	# apply_player_damage(player, amount: int) -> bool (returns died)
	# apply_run_penalty(player, tile) -> bool (returns died)
	# handle_monster_death(monster) -> awaitable void
	# handle_player_death(player) -> awaitable void
	# finalize_battle(ctx: Dictionary) -> void
	_deps = deps


func start(battle_ctx: Dictionary) -> Signal:
	if _running:
		return battle_finished
	ctx = battle_ctx.duplicate(true)
	ctx["machine"] = self
	_running = true
	_set_state(StateName.PREPARE_BATTLE)
	return battle_finished


func stop() -> void:
	if _current:
		_current.exit(ctx)
	_current = null
	ctx.clear()
	_running = false
	_current_state_name = StateName.PREPARE_BATTLE


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
		emit_signal("state_changed", label, ctx)
		_current.enter(ctx)


func _load_states() -> void:
	if _states.size() > 0:
		return
	_states = {
		StateName.PREPARE_BATTLE: preload("res://scripts/battle/states/PrepareBattleState.gd").new(),
		StateName.DICE_CHECK: preload("res://scripts/battle/states/DiceCheckState.gd").new(),
		StateName.PREPARE_PLAYER_CHOICE: preload("res://scripts/battle/states/PreparePlayerChoiceState.gd").new(),
		StateName.PLAYER_CHOICE: preload("res://scripts/battle/states/PlayerChoiceState.gd").new(),
		StateName.PREPARE_END_BATTLE: preload("res://scripts/battle/states/PrepareEndBattleState.gd").new(),
		StateName.END_BATTLE: preload("res://scripts/battle/states/EndBattleState.gd").new()
	}
	for state in _states.values():
		add_child(state)


# Dependency helpers
func call_dep(key: String, args: Array = []) -> Variant:
	if not _deps.has(key):
		return null
	var callable: Callable = _deps.get(key)
	if not callable or not callable.is_valid():
		return null
	return callable.callv(args)


func call_dep_await(key: String, args: Array = []) -> Variant:
	if not _deps.has(key):
		return null
	var callable: Callable = _deps.get(key)
	if not callable or not callable.is_valid():
		return null
	var result = callable.callv(args)
	return await result


func finish_battle() -> void:
	if not _running:
		return
	_running = false
	emit_signal("battle_finished", ctx.duplicate(true))
	stop()
