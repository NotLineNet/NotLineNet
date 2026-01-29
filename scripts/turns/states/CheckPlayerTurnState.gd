extends "res://scripts/turns/TurnState.gd"

const TurnStateMachine = preload("res://scripts/turns/TurnStateMachine.gd")

# State: CheckPlayerTurn
# - Decides if combat starts based on monster presence on player's tile
# - Transitions:
#   * No monster -> PlayerTurn
#   * Combat win -> PlayerTurn
#   * Combat loss -> PrepareEndTurn

func enter(ctx: Dictionary) -> void:
	var fsm: TurnStateMachine = ctx.get("machine")
	var player = ctx.get("player")
	if not fsm or not player:
		return
	if player.consume_tile_combat_request():
		ctx["combat_in_progress"] = true
		return
	ctx["combat_in_progress"] = false
	var monster = fsm.call_dep("get_monster_on_tile", [player])
	if monster and monster.is_inside_tree() and not monster.is_dead:
		ctx["combat_in_progress"] = true
		fsm.emit_signal("start_combat", player, monster)
		return
	ctx["force_prepare_end_turn"] = false
	fsm._set_state(TurnStateMachine.StateName.PLAYER_TURN)
	log(1)


func handle_event(event: StringName, data: Variant, ctx: Dictionary) -> void:
	if event != "combat_resolved":
		return
	if not ctx.get("combat_in_progress", false):
		return
	ctx["combat_in_progress"] = false
	var fsm: TurnStateMachine = ctx.get("machine")
	if not fsm:
		return
	match str(data):
		"win":
			ctx["force_prepare_end_turn"] = false
			fsm._set_state(TurnStateMachine.StateName.PLAYER_TURN)
		"lose":
			ctx["force_prepare_end_turn"] = true
			fsm._set_state(TurnStateMachine.StateName.PREPARE_END_TURN)
