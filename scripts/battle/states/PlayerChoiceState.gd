extends "res://scripts/battle/BattleState.gd"

const BattleStateMachine = preload("res://scripts/battle/BattleStateMachine.gd")

# PLAYER_CHOICE

func enter(ctx: Dictionary) -> void:
	var fsm: BattleStateMachine = ctx.get("machine")
	if not fsm:
		return
	var player = ctx.get("player")
	fsm.call_dep("enable_player_input", [player])
	fsm.call_dep("show_player_ui")
	fsm.call_dep("enter_battle_room_ui", [player])
	# На внезапном бое PlayerUI мог быть скрыт — страхуемся повторным показом на следующий кадр.
	await get_tree().process_frame
	fsm.call_dep("show_player_ui")


func exit(ctx: Dictionary) -> void:
	var fsm: BattleStateMachine = ctx.get("machine")
	if not fsm:
		return
	fsm.call_dep("disable_player_input")
	fsm.call_dep("exit_battle_room_ui")


func handle_event(event: StringName, data: Variant, ctx: Dictionary) -> void:
	if event != "player_choice":
		return
	var choice := ""
	var tile = null
	if data is Dictionary:
		choice = str(data.get("choice", ""))
		tile = data.get("tile")
	else:
		choice = str(data)
	var fsm: BattleStateMachine = ctx.get("machine")
	if not fsm:
		return
	if choice == "fight":
		ctx["player_ran"] = false
		fsm._set_state(BattleStateMachine.StateName.DICE_CHECK)
		return
	if choice == "run":
		ctx["player_ran"] = true
		var player = ctx.get("player")
		var died := bool(fsm.call_dep("apply_run_penalty", [player, tile]))
		ctx["player_died"] = died
		fsm._set_state(BattleStateMachine.StateName.PREPARE_END_BATTLE)
