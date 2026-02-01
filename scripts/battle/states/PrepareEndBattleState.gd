extends "res://scripts/battle/BattleState.gd"

const BattleStateMachine = preload("res://scripts/battle/BattleStateMachine.gd")

# PREPARE_END_BATTLE

func enter(ctx: Dictionary) -> void:
	var fsm: BattleStateMachine = ctx.get("machine")
	if not fsm:
		return
	fsm.call_dep("disable_player_input")
	fsm.call_dep("exit_battle_room_ui")
	var player_ran := bool(ctx.get("player_ran", false))
	if not player_ran:
		fsm.call_dep("hide_player_ui")
	var monster_defeated := bool(ctx.get("monster_defeated", false))
	var player_died := bool(ctx.get("player_died", false))
	if monster_defeated:
		await fsm.call_dep_await("handle_monster_death", [ctx.get("monster")])
	elif player_died:
		await fsm.call_dep_await("handle_player_death", [ctx.get("player")])
	await fsm.call_dep_await("hide_battle_ui")
	fsm._set_state(BattleStateMachine.StateName.END_BATTLE)
