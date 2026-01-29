extends "res://scripts/turns/TurnState.gd"

const TurnStateMachine = preload("res://scripts/turns/TurnStateMachine.gd")

var _alive_animation_callable
var _alive_animation_ctx

# State: PrepareTurn
# - Blocks player input
# - Recenters camera on current player
# - Waits for camera to finish, then proceeds to CheckPlayerTurn

func enter(ctx: Dictionary) -> void:
	var fsm: TurnStateMachine = ctx.get("machine")
	var player = ctx.get("player")
	if not fsm:
		return
	ctx["camera_centered_ready"] = false
	ctx["awaiting_alive_animation"] = false
	ctx["alive_animation_complete"] = false
	ctx["alive_animation_player"] = null
	if player and player.is_dead:
		var animation_player := player.get_node_or_null("AnimationPlayer") as AnimationPlayer
		if animation_player and animation_player.has_animation("Alive"):
			ctx["awaiting_alive_animation"] = true
			ctx["alive_animation_player"] = animation_player
			_alive_animation_callable = Callable(self, "_on_alive_animation_finished")
			_alive_animation_ctx = ctx
			animation_player.animation_finished.connect(_alive_animation_callable)
			animation_player.play("Alive")
		if player.has_method("mark_alive"):
			player.mark_alive()
	fsm.emit_signal("disable_player_input")
	fsm.emit_signal("hide_player_ui")
	fsm.emit_signal("request_camera_center", player)


func exit(ctx: Dictionary) -> void:
	_cleanup_animation_connection(ctx)


func handle_event(event: StringName, data: Variant, ctx: Dictionary) -> void:
	if event != "camera_centered":
		return
	ctx["camera_centered_ready"] = true
	_try_transition(ctx)


func _on_alive_animation_finished(anim_name: String) -> void:
	if anim_name != "Alive":
		return
	var ctx: Dictionary = _alive_animation_ctx as Dictionary
	if not ctx:
		return
	ctx["alive_animation_complete"] = true
	ctx["awaiting_alive_animation"] = false
	_cleanup_animation_connection(ctx)
	_try_transition(ctx)


func _cleanup_animation_connection(ctx: Dictionary) -> void:
	var animation_player: AnimationPlayer = ctx.get("alive_animation_player")
	if animation_player and _alive_animation_callable and animation_player.animation_finished.is_connected(_alive_animation_callable):
		animation_player.animation_finished.disconnect(_alive_animation_callable)
	ctx["alive_animation_player"] = null
	_alive_animation_callable = null
	_alive_animation_ctx = null


func _try_transition(ctx: Dictionary) -> void:
	var camera_ready: bool = bool(ctx.get("camera_centered_ready", false))
	var waiting_alive: bool = bool(ctx.get("awaiting_alive_animation", false))
	var alive_ready: bool = bool(ctx.get("alive_animation_complete", false))
	if not camera_ready:
		return
	if waiting_alive and not alive_ready:
		return
	var fsm: TurnStateMachine = ctx.get("machine")
	if not fsm:
		return
	fsm._set_state(TurnStateMachine.StateName.CHECK_PLAYER_TURN)
