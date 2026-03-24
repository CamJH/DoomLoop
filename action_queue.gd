class_name ActionQueue
extends RefCounted

## Queue state and UI. Gets `game` reference in constructor.

var game  ## Reference to game.gd.

# ---- Action queue ----
var action_queue: Array = []
var queue_display: VBoxContainer = null
var action_progress: Dictionary = {}
## Reference to the active action's label for lightweight time updates.
var _active_time_label: Label = null

# ---- Node references (set by game._ready) ----
var button_row: VBoxContainer


func _init(game_ref) -> void:
	game = game_ref


## Add an action to the queue. front=true inserts at position 1 (after current),
## front=false appends to end. If nothing is running, starts it immediately.
func enqueue_action(action: Dictionary, front: bool) -> void:
	var entry := { "action": action.duplicate(), "action_id": action["action_id"] }

	if not game.action_in_progress:
		action_queue.push_front(entry)
		start_queue_head()
	elif front:
		# Interrupt: pause current action, insert new one at front, start it.
		if game.current_action_elapsed > 0.0 and not game.current_action_id.is_empty():
			action_progress[game.current_action_id] = game.current_action_elapsed
		var gold_cost: int = game.current_action_data.get("gold_cost", 0)
		if gold_cost > 0:
			game.player.gold += gold_cost
			game.ui_helpers.update_player_stats_ui()
		if game.active_action_bar:
			game.active_action_bar.visible = false
		if game.active_action_button:
			game.active_action_button.visible = true
		game.action_in_progress = false
		game.active_action_bar = null
		game.active_action_button = null
		# Remove any existing queue entry for this action (prevents duplicates).
		var action_aid: String = action["action_id"]
		for j in range(action_queue.size() - 1, -1, -1):
			if action_queue[j]["action_id"] == action_aid:
				action_queue.remove_at(j)
		action_queue.insert(0, entry)
		# Defer the rebuild.
		game.call_deferred("_deferred_start_queue_after_interrupt")
	else:
		action_queue.append(entry)

	update_queue_ui()


## Called deferred after an interrupt to safely rebuild UI and start the new action.
func deferred_start_queue_after_interrupt() -> void:
	game.show_location(game.current_location)
	start_queue_head()
	update_queue_ui()


## Start executing the action at index 0 of the queue.
func start_queue_head() -> void:
	if action_queue.is_empty():
		return

	var entry: Dictionary = action_queue[0]
	var action: Dictionary = entry["action"]

	game.action_in_progress = true
	game.current_action_name = action["label"]
	game.current_action_id = action["action_id"]
	game.current_action_duration = action["duration"]
	game.current_action_destination = action["destination"]
	game.current_action_data = action.duplicate()

	var saved_elapsed: float = action_progress.get(action["action_id"], 0.0)
	game.current_action_elapsed = saved_elapsed
	print("[START] %s elapsed=%.1f dur=%.1f" % [action["label"], saved_elapsed, game.current_action_duration])

	if action.get("note_read", false):
		game.current_action_data["_note_start_progress"] = game.player.note_read_progress
		print("[NOTE START] note_read_progress=%.3f, _note_start_progress=%.3f" % [game.player.note_read_progress, game.player.note_read_progress])

	var gold_cost: int = action.get("gold_cost", 0)
	if gold_cost > 0:
		game.player.gold -= gold_cost
		game.ui_helpers.update_player_stats_ui()

	activate_bar_for_action(action)
	update_queue_ui()


## Find the button slot matching the action and show its fill bar.
func activate_bar_for_action(action: Dictionary) -> void:
	var target_id: String = action["action_id"]
	for row_node in button_row.get_children():
		if not is_instance_valid(row_node):
			continue
		var slot: Control = null
		if row_node is HBoxContainer and row_node.get_child_count() > 0:
			slot = row_node.get_child(0)
		elif row_node is Control:
			slot = row_node
		if slot == null or slot.get_child_count() < 2:
			continue
		var btn: Button = slot.get_child(0) as Button
		var bar: ColorRect = slot.get_child(1) as ColorRect
		if btn and bar and btn.has_meta("action_id") and btn.get_meta("action_id") == target_id:
			btn.visible = false
			bar.visible = true
			if game.current_action_duration > 0.0:
				game.ui_helpers.set_bar_progress(bar, game.current_action_elapsed / game.current_action_duration)
			else:
				game.ui_helpers.set_bar_progress(bar, 0.0)
			game.active_action_bar = bar
			game.active_action_button = btn
			return
	game.active_action_bar = null
	game.active_action_button = null


## Update the queue display UI below the button row.
func update_queue_ui() -> void:
	if queue_display and is_instance_valid(queue_display):
		queue_display.get_parent().remove_child(queue_display)
		queue_display.free()
		queue_display = null

	_active_time_label = null

	if action_queue.is_empty():
		return

	queue_display = VBoxContainer.new()
	queue_display.add_theme_constant_override("separation", 4)

	var header := Label.new()
	header.text = "— Action Queue —"
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	header.modulate = Color(0.6, 0.65, 0.75, 0.8)
	header.add_theme_font_size_override("font_size", 11)
	queue_display.add_child(header)

	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 3)
	grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	queue_display.add_child(grid)

	for i in action_queue.size():
		var entry: Dictionary = action_queue[i]
		var action: Dictionary = entry["action"]
		var is_active: bool = (i == 0 and game.action_in_progress)

		var lbl := Label.new()
		var saved: float = action_progress.get(action["action_id"], 0.0)
		var dur: float = action["duration"]
		var time_info := ""
		if is_active:
			var secs_left: float = maxf(dur - game.current_action_elapsed, 0.0)
			if secs_left >= 60.0:
				time_info = " [%d:%02d]" % [int(secs_left) / 60, int(secs_left) % 60]
			else:
				time_info = " [%ds]" % ceili(secs_left)
			lbl.text = "▶ %s%s" % [action["label"], time_info]
			lbl.modulate = Color(0.4, 0.8, 1.0)
			lbl.set_meta("action_label", action["label"])
			lbl.set_meta("action_duration", dur)
			_active_time_label = lbl
		elif saved > 0.0:
			var secs_left := maxf(dur - saved, 0.0)
			if secs_left >= 60.0:
				time_info = " [%d:%02d left]" % [int(secs_left) / 60, int(secs_left) % 60]
			else:
				time_info = " [%ds left]" % ceili(secs_left)
			lbl.text = "%d. %s%s" % [i, action["label"], time_info]
			lbl.modulate = Color(0.7, 0.75, 0.85, 0.9)
		else:
			lbl.text = "%d. %s" % [i, action["label"]]
			lbl.modulate = Color(0.7, 0.75, 0.85, 0.9)

		lbl.add_theme_font_size_override("font_size", 12)
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(lbl)

		var cancel_btn := Button.new()
		cancel_btn.text = "✕"
		cancel_btn.custom_minimum_size = Vector2(36, 30)
		cancel_btn.add_theme_font_size_override("font_size", 12)
		var entry_ref: Dictionary = entry
		cancel_btn.pressed.connect(func() -> void:
			var found_idx := action_queue.find(entry_ref)
			if found_idx >= 0:
				cancel_queued_action(found_idx)
		)
		grid.add_child(cancel_btn)

	button_row.get_parent().add_child(queue_display)


## Cancel/remove a queued action by index.
func cancel_queued_action(index: int) -> void:
	if index < 0 or index >= action_queue.size():
		return

	if index == 0 and game.action_in_progress:
		if game.current_action_elapsed > 0.0 and not game.current_action_id.is_empty():
			action_progress[game.current_action_id] = game.current_action_elapsed
		var gold_cost: int = game.current_action_data.get("gold_cost", 0)
		if gold_cost > 0:
			game.player.gold += gold_cost
			game.ui_helpers.update_player_stats_ui()
		game.action_in_progress = false
		game.active_action_bar = null
		game.active_action_button = null
		action_queue.remove_at(0)
		game.show_location(game.current_location)
		if not action_queue.is_empty():
			start_queue_head()
		else:
			update_queue_ui()
	else:
		action_queue.remove_at(index)
		update_queue_ui()


## Lightweight update: only refresh the active action's time label (no rebuild).
func update_active_time() -> void:
	if _active_time_label == null or not is_instance_valid(_active_time_label):
		return
	var dur: float = _active_time_label.get_meta("action_duration", 0.0)
	var label_text: String = _active_time_label.get_meta("action_label", "")
	var secs_left: float = maxf(dur - game.current_action_elapsed, 0.0)
	var time_info := ""
	if secs_left >= 60.0:
		time_info = " [%d:%02d]" % [int(secs_left) / 60, int(secs_left) % 60]
	else:
		time_info = " [%ds]" % ceili(secs_left)
	_active_time_label.text = "▶ %s%s" % [label_text, time_info]


func clear() -> void:
	action_queue.clear()
	action_progress.clear()
	if queue_display and is_instance_valid(queue_display):
		queue_display.get_parent().remove_child(queue_display)
		queue_display.free()
		queue_display = null
