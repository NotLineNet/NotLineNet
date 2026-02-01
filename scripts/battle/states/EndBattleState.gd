extends "res://scripts/battle/BattleState.gd"

const BattleStateMachine = preload("res://scripts/battle/BattleStateMachine.gd")

# END_BATTLE

func enter(ctx: Dictionary) -> void:
	var fsm: BattleStateMachine = ctx.get("machine")
	if not fsm:
		return
	fsm.call_dep("finalize_battle", [ctx])
	fsm.finish_battle()
