extends "res://scripts/turns/TurnState.gd"

const TurnStateMachine = preload("res://scripts/turns/TurnStateMachine.gd")

# State: CanPlayerActAgain
# - Evaluates if player can continue acting
# - Transitions:
#   * can act -> PlayerTurn
#   * cannot -> PrepareEndTurn

func enter(ctx: Dictionary) -> void:
	var fsm: TurnStateMachine = ctx.get("machine")
	var player = ctx.get("player")
	if not fsm:
		return
	if bool(ctx.get("force_prepare_end_turn", false)) or (player and player.is_dead):
		fsm._set_state(TurnStateMachine.StateName.PREPARE_END_TURN)
		return
	var can_act = fsm.call_dep("can_player_act_again", [player])
	if can_act:
		await fsm.call_dep_await("wait_camera_centering_done")
		fsm._set_state(TurnStateMachine.StateName.PLAYER_TURN)
	else:
		fsm._set_state(TurnStateMachine.StateName.PREPARE_END_TURN)
