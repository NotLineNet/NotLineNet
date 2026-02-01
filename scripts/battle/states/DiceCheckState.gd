extends "res://scripts/battle/BattleState.gd"

const BattleStateMachine = preload("res://scripts/battle/BattleStateMachine.gd")

# DICE_CHECK

func enter(ctx: Dictionary) -> void:
	var fsm: BattleStateMachine = ctx.get("machine")
	if not fsm:
		return
	var player = ctx.get("player")
	var monster = ctx.get("monster")
	fsm.call_dep("hide_player_ui")
	fsm.call_dep("exit_battle_room_ui")
	fsm.call_dep("disable_player_input")
	var results: Array = await fsm.call_dep_await("run_dice_game", [player, monster])
	var player_roll := _extract_roll(results, player)
	var monster_roll := _extract_roll(results, monster)
	ctx["player_roll"] = player_roll
	ctx["monster_roll"] = monster_roll
	ctx["player_won_round"] = player_roll >= monster_roll
	ctx["player_ran"] = false
	fsm._set_state(BattleStateMachine.StateName.PREPARE_PLAYER_CHOICE)


func _extract_roll(results: Array, target) -> int:
	for entry in results:
		if not (entry is Dictionary):
			continue
		if entry.get("player") == target:
			return int(entry.get("roll", 0))
	return 0
