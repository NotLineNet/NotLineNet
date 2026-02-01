extends "res://scripts/battle/BattleState.gd"

const BattleStateMachine = preload("res://scripts/battle/BattleStateMachine.gd")

# PREPARE_BATTLE

func enter(ctx: Dictionary) -> void:
	var fsm: BattleStateMachine = ctx.get("machine")
	if not fsm:
		return
	# Disable player control and prepare UI visibility based on battle type.
	fsm.call_dep("disable_player_input")
	fsm.call_dep("exit_battle_room_ui")
	var battle_type := str(ctx.get("battle_type", "Обычный"))
	if battle_type == "Внезапный":
		fsm.call_dep("hide_player_ui")
	else:
		fsm.call_dep("show_player_ui")
	fsm.call_dep("hide_battle_ui")
	await fsm.call_dep_await("show_battle_ui", [battle_type])
	if battle_type == "Внезапный":
		fsm._set_state(BattleStateMachine.StateName.DICE_CHECK)
	else:
		fsm._set_state(BattleStateMachine.StateName.PLAYER_CHOICE)
