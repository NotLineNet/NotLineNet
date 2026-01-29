extends "res://scripts/turns/TurnState.gd"

const TurnStateMachine = preload("res://scripts/turns/TurnStateMachine.gd")

# State: PrepareEndTurn
# - Hides UI, fully disables input
# - Handles any end-of-turn cleanup (death processing delegated via dependency)
# - Waits for death animation when needed

func enter(ctx: Dictionary) -> void:
	var fsm: TurnStateMachine = ctx.get("machine")
	var player = ctx.get("player")
	if not fsm:
		return
	fsm.emit_signal("hide_player_ui")
	fsm.emit_signal("disable_player_input")
	fsm.call_dep("handle_prepare_end_turn", [player])
	var awaiting_death: bool = bool(player and player.is_dead)
	ctx["awaiting_death_animation"] = awaiting_death
	if not awaiting_death:
		fsm._set_state(TurnStateMachine.StateName.END_TURN)


func handle_event(event: StringName, data: Variant, ctx: Dictionary) -> void:
	if event == "player_death_animation_finished":
		if data != ctx.get("player"):
			return
		var fsm: TurnStateMachine = ctx.get("machine")
		if not fsm:
			return
		fsm._set_state(TurnStateMachine.StateName.END_TURN)
		return
