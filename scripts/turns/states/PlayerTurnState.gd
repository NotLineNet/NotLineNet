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
	if event == "combat_resolved":
		var payload: Dictionary = _parse_combat_result(data)
		var result: String = payload.get("result", "") as String
		var player_died: bool = bool(payload.get("player_died", false))
		if result == "lose" and player_died:
			var fsm: TurnStateMachine = ctx.get("machine")
			if not fsm:
				return
			ctx["force_prepare_end_turn"] = true
			fsm._set_state(TurnStateMachine.StateName.CAN_PLAYER_ACT_AGAIN)

func _parse_combat_result(data: Variant) -> Dictionary:
	if data is Dictionary:
		return {
			"result": str(data.get("result", "")),
			"player_died": bool(data.get("player_died", false))
		}
	return {"result": str(data), "player_died": false}

