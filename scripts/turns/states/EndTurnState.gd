extends "res://scripts/turns/TurnState.gd"

const TurnStateMachine = preload("res://scripts/turns/TurnStateMachine.gd")

# State: EndTurn
# - Requests camera travel to next player
# - On camera arrival switches active player and moves to PrepareTurn
# - If no next player -> emits turns_completed

func enter(ctx: Dictionary) -> void:
	var fsm: TurnStateMachine = ctx.get("machine")
	var current_player = ctx.get("player")
	if not fsm:
		return
	var next_player = fsm.call_dep("get_next_player", [current_player])
	ctx["next_player"] = next_player
	if not next_player:
		fsm.emit_signal("turns_completed")
		return
	fsm.emit_signal("disable_player_input")
	fsm.emit_signal("hide_player_ui")
	fsm.emit_signal("request_camera_center", next_player)


func handle_event(event: StringName, data: Variant, ctx: Dictionary) -> void:
	if event != "camera_centered":
		return
	var fsm: TurnStateMachine = ctx.get("machine")
	if not fsm:
		return
	var target_player = ctx.get("next_player")
	if target_player and data != target_player:
		return
	if target_player:
		fsm.call_dep("set_active_player", [target_player])
		ctx["player"] = target_player
		ctx["next_player"] = null
		fsm._set_state(TurnStateMachine.StateName.PREPARE_TURN)
