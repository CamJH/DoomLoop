class_name RouteExecutor
extends RefCounted

## Reads a RoutePlan and drives the game through each step automatically.

enum State { IDLE, EXECUTING, IN_COMBAT, PAUSED, FINISHED, FAILED }

var plan: RoutePlan
var current_step_index: int = 0
var state: State = State.IDLE
var game: Node  ## Reference to game.gd (GameRoot node).

signal step_started(index: int, step: Dictionary)
signal step_completed(index: int)
signal plan_completed()
signal plan_failed(reason: String, step_index: int)
signal execution_paused(step_index: int)


func _init(game_node: Node) -> void:
	game = game_node


## Start executing a plan from the beginning.
func start(p: RoutePlan) -> void:
	plan = p
	current_step_index = 0
	state = State.EXECUTING

	# Connect to game signals.
	if not game.action_completed.is_connected(_on_action_completed):
		game.action_completed.connect(_on_action_completed)
	if not game.combat_completed.is_connected(_on_combat_completed):
		game.combat_completed.connect(_on_combat_completed)
	if not game.loop_ended.is_connected(_on_loop_ended):
		game.loop_ended.connect(_on_loop_ended)

	_execute_current_step()


## Resume from the current step after being paused.
func resume() -> void:
	if state != State.PAUSED:
		return
	state = State.EXECUTING
	_execute_current_step()


## Pause execution after the current step finishes.
func pause() -> void:
	if state == State.EXECUTING or state == State.IN_COMBAT:
		state = State.PAUSED


## Stop execution completely and disconnect signals.
func stop() -> void:
	state = State.IDLE
	_disconnect_signals()


## Whether the executor is actively running (not paused, idle, finished, or failed).
func is_running() -> bool:
	return state == State.EXECUTING or state == State.IN_COMBAT


func _execute_current_step() -> void:
	if state == State.PAUSED:
		execution_paused.emit(current_step_index)
		return

	if current_step_index >= plan.steps.size():
		state = State.FINISHED
		_disconnect_signals()
		plan_completed.emit()
		return

	var step: Dictionary = plan.steps[current_step_index]
	step_started.emit(current_step_index, step)

	# Check conditions before executing.
	if not _check_step_condition(step):
		var condition: Dictionary = step.get("condition", {})
		var on_fail: String = condition.get("on_fail", step.get("on_fail", "skip"))
		if on_fail == "stop":
			state = State.PAUSED
			execution_paused.emit(current_step_index)
			return
		else:
			# Skip this step.
			current_step_index += 1
			_execute_current_step()
			return

	# Execute based on step type.
	var step_type: String = step.get("type", "action")
	match step_type:
		"combat", "combat_all":
			state = State.IN_COMBAT
			var auto_count: int = step.get("auto_fight_count", 0)
			# For "Fight All", dynamically compute remaining slimes at runtime.
			if step_type == "combat_all" and step.get("slime_fight", false):
				auto_count = maxi(game.MAX_SLIMES - game.slimes_defeated - 1, 0)
			game.execute_combat(step, auto_count)
		_:
			# Travel, shop, heal — all use execute_action.
			state = State.EXECUTING
			game.execute_action(step)


func _check_step_condition(step: Dictionary) -> bool:
	var condition: Dictionary = step.get("condition", {})
	if condition.is_empty():
		return true

	match condition.get("type", ""):
		"gold_gte":
			return game.player_gold >= condition.get("value", 0)
		"gold_lt":
			return game.player_gold < condition.get("value", 0)
		"hp_below_pct":
			var hp_pct := (float(game.player_hp) / float(game.player_max_hp)) * 100.0
			return hp_pct < condition.get("value", 100)
		"has_item":
			var item_id: String = condition.get("item_id", "")
			return game.inventory.get(item_id, 0) > 0
		"slimes_remaining":
			return not game.all_slimes_cleared
		"needs_heal_and_gold":
			# Skip if already at full HP or can't afford.
			return game.player_hp < game.player_max_hp and game.player_gold >= 1
		"can_buy_item":
			# Skip if can't afford or already at item limit.
			var item_id: String = condition.get("item_id", "")
			var item: Dictionary = game.item_catalogue.get(item_id, {})
			if item.is_empty():
				return false
			var owned: int = game.inventory.get(item_id, 0)
			var at_limit: bool = owned >= item.get("max", 1)
			var can_afford: bool = game.player_gold >= item.get("cost", 0)
			return can_afford and not at_limit

	return true


func _on_action_completed(_action_name: String) -> void:
	if state == State.IDLE or state == State.FINISHED or state == State.FAILED:
		return

	step_completed.emit(current_step_index)
	current_step_index += 1

	if state == State.PAUSED:
		execution_paused.emit(current_step_index)
		return

	# Small delay before next step so the player can see what happened.
	if game.get_tree():
		await game.get_tree().create_timer(0.3).timeout
	_execute_current_step()


func _on_combat_completed(_enemy_name: String, victory: bool) -> void:
	if state == State.IDLE or state == State.FINISHED or state == State.FAILED:
		return

	if not victory:
		state = State.FAILED
		_disconnect_signals()
		plan_failed.emit("Player died in combat", current_step_index)
		return

	step_completed.emit(current_step_index)
	current_step_index += 1

	if state == State.PAUSED:
		execution_paused.emit(current_step_index)
		return

	state = State.EXECUTING
	if game.get_tree():
		await game.get_tree().create_timer(0.3).timeout
	_execute_current_step()


func _on_loop_ended() -> void:
	state = State.FAILED
	_disconnect_signals()
	plan_failed.emit("Time ran out", current_step_index)


func _disconnect_signals() -> void:
	if game.action_completed.is_connected(_on_action_completed):
		game.action_completed.disconnect(_on_action_completed)
	if game.combat_completed.is_connected(_on_combat_completed):
		game.combat_completed.disconnect(_on_combat_completed)
	if game.loop_ended.is_connected(_on_loop_ended):
		game.loop_ended.disconnect(_on_loop_ended)
