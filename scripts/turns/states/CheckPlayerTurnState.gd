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
	await fsm.call_dep_await("wait_camera_centering_done")
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
	var payload: Dictionary = _parse_combat_result(data)
	var result: String = payload.get("result", "") as String
	var player_died: bool = bool(payload.get("player_died", false))
	if result == "win" or (result == "lose" and not player_died):
		ctx["force_prepare_end_turn"] = false
		await fsm.call_dep_await("wait_camera_centering_done")
		fsm._set_state(TurnStateMachine.StateName.PLAYER_TURN)
	elif result == "lose" and player_died:
		ctx["force_prepare_end_turn"] = true
		fsm._set_state(TurnStateMachine.StateName.PREPARE_END_TURN)

func _parse_combat_result(data: Variant) -> Dictionary:
	if data is Dictionary:
		return {
			"result": str(data.get("result", "")),
			"player_died": bool(data.get("player_died", false))
		}
	return {"result": str(data), "player_died": false}
