extends "res://scripts/battle/BattleState.gd"

const BattleStateMachine = preload("res://scripts/battle/BattleStateMachine.gd")

# PREPARE_PLAYER_CHOICE

func enter(ctx: Dictionary) -> void:
	ctx["monster_defeated"] = false
	ctx["player_died"] = false
	var fsm: BattleStateMachine = ctx.get("machine")
	if not fsm:
		return
	fsm.call_dep("hide_player_ui")
	var player_won := bool(ctx.get("player_won_round", true))
	await fsm.call_dep_await("play_camera_hit", [player_won])
	if player_won:
		ctx["monster_defeated"] = true
		fsm._set_state(BattleStateMachine.StateName.PREPARE_END_BATTLE)
		return
	var player = ctx.get("player")
	var player_died := bool(fsm.call_dep("apply_player_damage", [player, 1]))
	ctx["player_died"] = player_died
	if player_died:
		fsm._set_state(BattleStateMachine.StateName.PREPARE_END_BATTLE)
		return
	fsm._set_state(BattleStateMachine.StateName.PLAYER_CHOICE)
