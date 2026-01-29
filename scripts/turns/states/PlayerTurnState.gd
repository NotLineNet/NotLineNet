extends "res://scripts/turns/TurnState.gd"

const TurnStateMachine = preload("res://scripts/turns/TurnStateMachine.gd")

# State: PlayerTurn
# - Shows UI, enables player input
# - Awaits completion of any player action

func enter(ctx: Dictionary) -> void:
	var fsm: TurnStateMachine = ctx.get("machine")
	var player = ctx.get("player")
	if not fsm:
		return
	fsm.emit_signal("show_player_ui", player)
	fsm.emit_signal("enable_player_input", player)


func handle_event(event: StringName, data: Variant, ctx: Dictionary) -> void:
	if event == "player_requested_finish":
		var fsm: TurnStateMachine = ctx.get("machine")
		if not fsm:
			return
		ctx["force_prepare_end_turn"] = false
		fsm._set_state(TurnStateMachine.StateName.CAN_PLAYER_ACT_AGAIN)
		return
	if event == "combat_resolved" and str(data) == "lose":
		var fsm: TurnStateMachine = ctx.get("machine")
		if not fsm:
			return
		ctx["force_prepare_end_turn"] = true
		fsm._set_state(TurnStateMachine.StateName.CAN_PLAYER_ACT_AGAIN)

