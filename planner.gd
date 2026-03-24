class_name RoutePlanner
extends RefCounted

## Route planner UI and logic. Gets `game` reference.

const Location = LocationManager.Location

var game  ## Reference to game.gd.

# ---- Planner state ----
var planner_visible := false
var current_plan: RoutePlan = null
var virtual_location: int = -1
var virtual_gold: int = 0
var virtual_inventory: Dictionary = {}
var load_popup: PanelContainer = null

# ---- Route executor ----
var route_executor: RefCounted = null

# ---- Node references (set by game._ready) ----
var plan_route_button: Button
var planner_overlay: HBoxContainer
var plan_name_edit: LineEdit
var save_plan_button: Button
var load_plan_button: Button
var available_actions_vbox: VBoxContainer
var planned_steps_list: VBoxContainer
var estimated_time_label: Label
var start_run_button: Button
var clear_plan_button: Button
var left_panel: PanelContainer
var right_column: VBoxContainer
var timer_section: VBoxContainer
var spacer3: Control
var location_label: Label
var status_label: Label


func _init(game_ref) -> void:
	game = game_ref


func toggle_planner() -> void:
	if planner_visible:
		close_planner()
	else:
		open_planner()


func open_planner() -> void:
	planner_visible = true
	plan_route_button.text = "Close Planner"

	virtual_location = game.current_location
	virtual_gold = game.player.gold
	virtual_inventory = game.player.inventory.duplicate()

	if current_plan == null:
		current_plan = RoutePlan.new()

	timer_section.visible = false
	left_panel.visible = false
	right_column.visible = false
	game.actions_label.visible = false
	game.button_row.visible = false
	game.combat.combat_section.visible = false
	game.combat.combat_log_panel.visible = false
	location_label.visible = false
	spacer3.visible = false
	status_label.visible = false
	planner_overlay.visible = true

	_refresh_available_actions()
	_rebuild_planned_steps_ui()


func close_planner() -> void:
	planner_visible = false
	plan_route_button.text = "Plan Route"
	planner_overlay.visible = false

	timer_section.visible = game.timer_revealed
	left_panel.visible = true
	right_column.visible = true
	location_label.visible = true
	spacer3.visible = true
	status_label.visible = true

	if load_popup and is_instance_valid(load_popup):
		load_popup.queue_free()
		load_popup = null

	game.show_location(game.current_location)


func _refresh_available_actions() -> void:
	for child in available_actions_vbox.get_children():
		child.queue_free()

	var data: Dictionary = game.locations.get_planner_location_data(virtual_location as Location)
	var loc_label := Label.new()
	loc_label.text = "At: %s" % data["name"]
	loc_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	loc_label.modulate = Color(0.85, 0.65, 0.15, 0.9)
	loc_label.add_theme_font_size_override("font_size", 13)
	available_actions_vbox.add_child(loc_label)

	for action in data["actions"]:
		var btn := Button.new()
		var is_combat: bool = action.get("combat_start", false)
		var is_disabled: bool = action.get("disabled", false)

		if is_disabled:
			btn.text = action["label"]
			btn.disabled = true
			btn.tooltip_text = action.get("disabled_reason", "")
		elif is_combat:
			btn.text = action["label"]
		else:
			btn.text = "%s (%ss)" % [action["label"], int(action["duration"])]

		btn.custom_minimum_size = Vector2(280, 36)
		btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER

		if not is_disabled:
			var act: Dictionary = action
			btn.pressed.connect(func() -> void: _add_step(act))

		available_actions_vbox.add_child(btn)


func _add_step(action: Dictionary) -> void:
	if current_plan == null:
		current_plan = RoutePlan.new()

	var step: Dictionary = action.duplicate()
	var is_combat: bool = action.get("combat_start", false)

	if is_combat:
		step["type"] = "combat_all" if action.get("auto_fight_count", 0) > 0 else "combat"
		step["estimated_time"] = 8.0
		if step.get("auto_fight_count", 0) > 0:
			step["estimated_time"] = 8.0 * (step["auto_fight_count"] + 1)
	elif action.get("heal", false):
		step["type"] = "heal"
		step["estimated_time"] = action["duration"]
	elif action.get("shop_buy", false):
		step["type"] = "shop"
		step["estimated_time"] = action["duration"]
	else:
		step["type"] = "travel"
		step["estimated_time"] = action["duration"]

	current_plan.add_step(step)

	if action.get("gold_cost", 0) > 0:
		virtual_gold -= action["gold_cost"]
	if action.get("shop_buy", false):
		var item_id: String = action["item_id"]
		virtual_inventory[item_id] = virtual_inventory.get(item_id, 0) + 1
	if action.get("destination", -1) != -1:
		virtual_location = action["destination"]

	_refresh_available_actions()
	_rebuild_planned_steps_ui()


func _validate_plan() -> Dictionary:
	var errors: Dictionary = {}
	if current_plan == null or current_plan.steps.is_empty():
		return errors

	var graph: Dictionary = game.locations.get_travel_graph()
	var sim_location: int = game.current_location

	for i in current_plan.steps.size():
		var step: Dictionary = current_plan.steps[i]
		var step_required_loc := _get_step_required_location(step)

		if step_required_loc != -1 and step_required_loc != sim_location:
			var loc_name: String = game.locations.get_planner_location_data(step_required_loc as Location).get("name", "???")
			var cur_name: String = game.locations.get_planner_location_data(sim_location as Location).get("name", "???")
			errors[i] = "Requires %s, but you'd be at %s" % [loc_name, cur_name]
		elif step_required_loc == -1 and step.get("destination", -1) != -1:
			var dest: int = step["destination"]
			var label: String = step.get("label", "")
			var edge_found := false
			var edges: Array = graph.get(sim_location, [])
			for edge in edges:
				if edge["destination"] == dest and edge["label"] == label:
					edge_found = true
					break
			if not edge_found:
				var cur_name: String = game.locations.get_planner_location_data(sim_location as Location).get("name", "???")
				errors[i] = "Can't do '%s' from %s" % [label, cur_name]

		var dest: int = step.get("destination", -1)
		if dest != -1:
			sim_location = dest

	return errors


func _get_step_required_location(step: Dictionary) -> int:
	var player: PlayerData = game.player
	if step.get("jail_guard_fight", false):
		return Location.JAIL_CELL_GUARD
	if step.get("combat_start", false) or step.get("slime_fight", false):
		return Location.DUNGEON_ENTRANCE
	if step.get("desk_loot", false) or step.get("note_read", false) or step.get("unlock_desk", false) or step.get("chest_break", false) or step.get("take_note", false):
		return Location.JAIL_GUARDROOM
	if step.get("heal", false):
		return Location.TOWN_HEALER
	if step.get("shop_buy", false):
		var item_id: String = step.get("item_id", "")
		if item_id in player.blacksmith_stock:
			return Location.TOWN_BLACKSMITH
		if item_id in player.general_goods_stock:
			return Location.TOWN_GENERAL_GOODS
	return -1


func _rebuild_planned_steps_ui() -> void:
	for child in planned_steps_list.get_children():
		child.queue_free()

	if current_plan == null or current_plan.steps.is_empty():
		var empty_lbl := Label.new()
		empty_lbl.text = "(no steps planned)"
		empty_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty_lbl.modulate = Color(1, 1, 1, 0.4)
		planned_steps_list.add_child(empty_lbl)
		estimated_time_label.text = "~0s / 600s"
		start_run_button.disabled = false
		return

	var errors := _validate_plan()
	var has_errors := not errors.is_empty()

	for i in current_plan.steps.size():
		var step: Dictionary = current_plan.steps[i]
		var step_container := VBoxContainer.new()
		step_container.add_theme_constant_override("separation", 2)

		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)

		var num_lbl := Label.new()
		num_lbl.text = "%d." % (i + 1)
		num_lbl.custom_minimum_size = Vector2(24, 0)
		num_lbl.modulate = Color(0.6, 0.65, 0.75)
		num_lbl.add_theme_font_size_override("font_size", 13)
		row.add_child(num_lbl)

		var step_lbl := Label.new()
		step_lbl.text = step.get("label", "???")
		step_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		step_lbl.add_theme_font_size_override("font_size", 13)
		step_lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		row.add_child(step_lbl)

		var time_lbl := Label.new()
		var est: float = step.get("estimated_time", 0.0)
		time_lbl.text = "~%ds" % int(est) if est > 0 else ""
		time_lbl.modulate = Color(0.7, 0.7, 0.75)
		time_lbl.add_theme_font_size_override("font_size", 12)
		row.add_child(time_lbl)

		var up_btn := Button.new()
		up_btn.text = "▲"
		up_btn.custom_minimum_size = Vector2(28, 24)
		if i > 0:
			var idx: int = i
			up_btn.pressed.connect(func() -> void: _move_step(idx, idx - 1))
		else:
			up_btn.disabled = true
		row.add_child(up_btn)

		var down_btn := Button.new()
		down_btn.text = "▼"
		down_btn.custom_minimum_size = Vector2(28, 24)
		if i < current_plan.steps.size() - 1:
			var idx: int = i
			down_btn.pressed.connect(func() -> void: _move_step(idx, idx + 1))
		else:
			down_btn.disabled = true
		row.add_child(down_btn)

		var remove_btn := Button.new()
		remove_btn.text = "✕"
		remove_btn.custom_minimum_size = Vector2(28, 24)
		var idx: int = i
		remove_btn.pressed.connect(func() -> void: _remove_step(idx))
		row.add_child(remove_btn)

		step_container.add_child(row)

		if i in errors:
			num_lbl.modulate = Color(1.0, 0.35, 0.35)
			step_lbl.modulate = Color(1.0, 0.35, 0.35)
			var err_lbl := Label.new()
			err_lbl.text = "⚠ %s" % errors[i]
			err_lbl.modulate = Color(1.0, 0.5, 0.3, 0.9)
			err_lbl.add_theme_font_size_override("font_size", 11)
			err_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			step_container.add_child(err_lbl)

		planned_steps_list.add_child(step_container)

	var total_est := current_plan.get_estimated_time()
	estimated_time_label.text = "~%ds / %ds" % [int(total_est), int(game.LOOP_DURATION)]

	start_run_button.disabled = has_errors
	save_plan_button.disabled = has_errors
	if has_errors:
		start_run_button.tooltip_text = "Fix route errors before running"
		save_plan_button.tooltip_text = "Fix route errors before saving"
	else:
		start_run_button.tooltip_text = ""
		save_plan_button.tooltip_text = ""


func _move_step(from_idx: int, to_idx: int) -> void:
	current_plan.move_step(from_idx, to_idx)
	_recompute_virtual_state()
	_refresh_available_actions()
	_rebuild_planned_steps_ui()


func _remove_step(index: int) -> void:
	current_plan.remove_step(index)
	_recompute_virtual_state()
	_refresh_available_actions()
	_rebuild_planned_steps_ui()


func _recompute_virtual_state() -> void:
	virtual_location = game.current_location
	virtual_gold = game.player.gold
	virtual_inventory = game.player.inventory.duplicate()

	if current_plan == null:
		return

	for step in current_plan.steps:
		if step.get("gold_cost", 0) > 0:
			virtual_gold -= step["gold_cost"]
		if step.get("shop_buy", false):
			var item_id: String = step["item_id"]
			virtual_inventory[item_id] = virtual_inventory.get(item_id, 0) + 1
		if step.get("destination", -1) != -1:
			virtual_location = step["destination"]


func on_clear_plan() -> void:
	if current_plan:
		current_plan.clear()
	_recompute_virtual_state()
	_refresh_available_actions()
	_rebuild_planned_steps_ui()


func on_start_run() -> void:
	if current_plan == null or current_plan.steps.is_empty():
		status_label.text = "No steps in plan!"
		return

	close_planner()

	route_executor = RouteExecutor.new(game)
	route_executor.step_started.connect(_on_executor_step_started)
	route_executor.plan_completed.connect(_on_executor_plan_completed)
	route_executor.plan_failed.connect(_on_executor_plan_failed)
	route_executor.execution_paused.connect(_on_executor_paused)

	plan_route_button.text = "Take Control"
	plan_route_button.pressed.disconnect(toggle_planner)
	plan_route_button.pressed.connect(_on_take_control)

	route_executor.start(current_plan)


func _on_take_control() -> void:
	if route_executor and route_executor.is_running():
		route_executor.pause()


func _on_executor_step_started(index: int, step: Dictionary) -> void:
	status_label.text = "Auto: Step %d — %s" % [index + 1, step.get("label", "???")]


func _on_executor_plan_completed() -> void:
	status_label.text = "Route complete!"
	_restore_plan_button()


func _on_executor_plan_failed(reason: String, _step_index: int) -> void:
	status_label.text = "Route stopped: %s" % reason
	_restore_plan_button()


func _on_executor_paused(step_index: int) -> void:
	status_label.text = "Route paused at step %d. Click 'Resume' to continue." % (step_index + 1)
	plan_route_button.text = "Resume Plan"
	if plan_route_button.pressed.is_connected(_on_take_control):
		plan_route_button.pressed.disconnect(_on_take_control)
	if not plan_route_button.pressed.is_connected(_on_resume_plan):
		plan_route_button.pressed.connect(_on_resume_plan)


func _on_resume_plan() -> void:
	if route_executor:
		plan_route_button.text = "Take Control"
		if plan_route_button.pressed.is_connected(_on_resume_plan):
			plan_route_button.pressed.disconnect(_on_resume_plan)
		if not plan_route_button.pressed.is_connected(_on_take_control):
			plan_route_button.pressed.connect(_on_take_control)
		route_executor.resume()


func _restore_plan_button() -> void:
	plan_route_button.text = "Plan Route"
	if plan_route_button.pressed.is_connected(_on_take_control):
		plan_route_button.pressed.disconnect(_on_take_control)
	if plan_route_button.pressed.is_connected(_on_resume_plan):
		plan_route_button.pressed.disconnect(_on_resume_plan)
	if not plan_route_button.pressed.is_connected(toggle_planner):
		plan_route_button.pressed.connect(toggle_planner)
	route_executor = null


func on_save_plan() -> void:
	if current_plan == null or current_plan.steps.is_empty():
		status_label.text = "Nothing to save!"
		return
	var plan_name := plan_name_edit.text.strip_edges()
	if plan_name.is_empty():
		plan_name = "Untitled Route"
	current_plan.plan_name = plan_name
	var err := RoutePlan.save_plan(current_plan, plan_name.to_snake_case())
	if err == OK:
		status_label.text = "Route '%s' saved!" % plan_name
	else:
		status_label.text = "Failed to save route."


func on_load_plan() -> void:
	var plans := RoutePlan.list_saved_plans()
	if plans.is_empty():
		status_label.text = "No saved routes found."
		return

	for child in available_actions_vbox.get_children():
		child.queue_free()

	var title := Label.new()
	title.text = "Saved Routes"
	title.add_theme_font_size_override("font_size", 16)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.modulate = Color(0.85, 0.65, 0.15)
	available_actions_vbox.add_child(title)

	for plan_filename in plans:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		row.size_flags_horizontal = Control.SIZE_SHRINK_CENTER

		var btn := Button.new()
		btn.text = plan_filename.replace("_", " ").capitalize()
		btn.custom_minimum_size = Vector2(200, 32)
		var fname: String = plan_filename
		btn.pressed.connect(func() -> void: _load_plan_by_name(fname))
		row.add_child(btn)

		var del_btn := Button.new()
		del_btn.text = "✕"
		del_btn.custom_minimum_size = Vector2(32, 32)
		del_btn.pressed.connect(func() -> void:
			RoutePlan.delete_plan(fname)
			on_load_plan()
		)
		row.add_child(del_btn)

		available_actions_vbox.add_child(row)

	var back_btn := Button.new()
	back_btn.text = "Back"
	back_btn.custom_minimum_size = Vector2(100, 32)
	back_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	back_btn.pressed.connect(_refresh_available_actions)
	available_actions_vbox.add_child(back_btn)


func _load_plan_by_name(filename: String) -> void:
	var loaded := RoutePlan.load_plan(filename)
	if loaded == null:
		status_label.text = "Failed to load route."
		return

	current_plan = loaded
	plan_name_edit.text = current_plan.plan_name
	_recompute_virtual_state()
	_refresh_available_actions()
	_rebuild_planned_steps_ui()
	status_label.text = "Route '%s' loaded!" % current_plan.plan_name
