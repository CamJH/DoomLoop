extends MarginContainer
## DoomLoop — Main game script (slim hub).
## Delegates to: PlayerData, LocationManager, CombatManager, ActionQueue,
## UIHelpers, and RoutePlanner.

#region ---- CONSTANTS & SIGNALS ----

const LOOP_DURATION := 600.0
const Location = LocationManager.Location

signal action_completed(action_name: String)
signal combat_completed(enemy_name: String, victory: bool)
signal loop_ended()

#endregion

#region ---- SUB-SYSTEMS ----

var player: PlayerData
var locations: LocationManager
var combat: CombatManager
var action_queue: ActionQueue
var ui_helpers: UIHelpers
var planner: RoutePlanner

#endregion

#region ---- PASS-THROUGH PROPERTIES (for RouteExecutor compatibility) ----

var player_max_hp: int:
	get: return player.max_hp
var player_hp: int:
	get: return player.hp
var player_gold: int:
	get: return player.gold
var player_xp: int:
	get: return player.xp
var inventory: Dictionary:
	get: return player.inventory
var item_catalogue: Dictionary:
	get: return player.item_catalogue
var slimes_defeated: int:
	get: return player.slimes_defeated
var all_slimes_cleared: bool:
	get: return player.all_slimes_cleared
var MAX_SLIMES: int:
	get: return player.MAX_SLIMES

#endregion

#region ---- GAME STATE ----

var loop_count := 0
var timer_revealed := false

# ---- Action / location state ----
var current_location: int = Location.JAIL_CELL
var time_spent := 0.0
var action_in_progress := false
var current_action_duration := 0.0
var current_action_elapsed := 0.0
var current_action_name := ""
var current_action_id := ""
var current_action_destination: int = -1
var current_action_data: Dictionary = {}

## Whether the current location has any shop items.
var _location_has_shop_items := false

## The ColorRect currently filling (inside a button slot).
var active_action_bar: ColorRect = null
## The Button that is currently active.
var active_action_button: Button = null

#endregion

#region ---- NODE REFERENCES ----

@onready var main_timer_bar: ProgressBar = %MainTimerBar
@onready var timer_label: Label = %TimerLabel
@onready var location_label: Label = %LocationLabel
@onready var actions_label: Label = %ActionsLabel
@onready var button_row: VBoxContainer = %ButtonRow
@onready var status_label: Label = %StatusLabel
@onready var hp_label: Label = %HPLabel
@onready var xp_label: Label = %XPLabel
@onready var gold_label: Label = %GoldLabel
@onready var inventory_list: VBoxContainer = %InventoryList
@onready var auto_flee_spinbox: SpinBox = %AutoFleeSpinBox
# Combat UI
@onready var combat_section: PanelContainer = %CombatSection
@onready var enemy_hp_label: Label = %EnemyHPLabel
@onready var enemy_attack_bar: ProgressBar = %EnemyAttackBar
@onready var player_attack_bar: ProgressBar = %PlayerAttackBar
@onready var player_attack_label: Label = %PlayerAttackLabel
@onready var flee_button: Button = %FleeButton
@onready var combat_log_label: Label = %CombatLogLabel
@onready var combat_log_scroll: ScrollContainer = %CombatLogScroll
@onready var combat_log_panel: PanelContainer = %CombatLogPanel
# Info panel
@onready var info_content: VBoxContainer = %InfoContent
@onready var info_vbox: VBoxContainer = %InfoVBox
@onready var info_title: Label = %InfoTitle
@onready var info_sep: HSeparator = %InfoSep
# Sections hidden during planner
@onready var left_panel: PanelContainer = %LeftPanel
@onready var right_column: VBoxContainer = %RightColumn
@onready var timer_section: VBoxContainer = %TimerSection
@onready var spacer3: Control = %Spacer3
# Planner UI
@onready var plan_route_button: Button = %PlanRouteButton
@onready var planner_overlay: HBoxContainer = %PlannerOverlay
@onready var plan_name_edit: LineEdit = %PlanNameEdit
@onready var save_plan_button: Button = %SaveButton
@onready var load_plan_button: Button = %LoadButton
@onready var available_actions_vbox: VBoxContainer = %AvailableActions
@onready var planned_steps_list: VBoxContainer = %PlannedStepsList
@onready var estimated_time_label: Label = %EstimatedTimeLabel
@onready var start_run_button: Button = %StartRunButton
@onready var clear_plan_button: Button = %ClearPlanButton

#endregion

#region ---- LIFECYCLE ----

func _ready() -> void:
	# ---- Create sub-systems ----
	player = PlayerData.new()
	locations = LocationManager.new(self)
	combat = CombatManager.new(self)
	action_queue = ActionQueue.new(self)
	ui_helpers = UIHelpers.new(self)
	planner = RoutePlanner.new(self)

	# ---- Pass node references to combat ----
	combat.combat_section = combat_section
	combat.enemy_hp_label = enemy_hp_label
	combat.enemy_attack_bar = enemy_attack_bar
	combat.player_attack_bar = player_attack_bar
	combat.player_attack_label = player_attack_label
	combat.flee_button = flee_button
	combat.combat_log_label = combat_log_label
	combat.combat_log_scroll = combat_log_scroll
	combat.combat_log_panel = combat_log_panel
	combat.hp_label = hp_label
	combat.status_label = status_label
	combat.actions_label = actions_label
	combat.button_row = button_row
	combat.auto_flee_spinbox = auto_flee_spinbox

	# ---- Pass node references to action_queue ----
	action_queue.button_row = button_row

	# ---- Pass node references to ui_helpers ----
	ui_helpers.info_content = info_content
	ui_helpers.info_vbox = info_vbox
	ui_helpers.info_title = info_title
	ui_helpers.info_sep = info_sep
	ui_helpers.hp_label = hp_label
	ui_helpers.xp_label = xp_label
	ui_helpers.gold_label = gold_label
	ui_helpers.inventory_list = inventory_list

	# ---- Pass node references to planner ----
	planner.plan_route_button = plan_route_button
	planner.planner_overlay = planner_overlay
	planner.plan_name_edit = plan_name_edit
	planner.save_plan_button = save_plan_button
	planner.load_plan_button = load_plan_button
	planner.available_actions_vbox = available_actions_vbox
	planner.planned_steps_list = planned_steps_list
	planner.estimated_time_label = estimated_time_label
	planner.start_run_button = start_run_button
	planner.clear_plan_button = clear_plan_button
	planner.left_panel = left_panel
	planner.right_column = right_column
	planner.timer_section = timer_section
	planner.spacer3 = spacer3
	planner.location_label = location_label
	planner.status_label = status_label

	# ---- Initialize UI ----
	main_timer_bar.max_value = LOOP_DURATION
	main_timer_bar.value = LOOP_DURATION
	RenderingServer.set_default_clear_color(Color(0.06, 0.06, 0.1, 1.0))

	_update_timer_visibility()
	_update_timer_label()
	xp_label.visible = false
	gold_label.visible = false
	auto_flee_spinbox.get_parent().visible = false
	auto_flee_spinbox.value = 0.0
	ui_helpers.update_player_stats_ui()
	ui_helpers.update_inventory_ui()
	show_location(current_location)
	flee_button.pressed.connect(combat.on_flee_pressed)
	status_label.text = "You awaken on a cold stone floor. The smell of damp earth fills the air.\nIron bars block the only way out. You can hear heavy footsteps nearby."

	# Planner connections.
	plan_route_button.pressed.connect(planner.toggle_planner)
	start_run_button.pressed.connect(planner.on_start_run)
	clear_plan_button.pressed.connect(planner.on_clear_plan)
	save_plan_button.pressed.connect(planner.on_save_plan)
	load_plan_button.pressed.connect(planner.on_load_plan)


func _process(delta: float) -> void:
	combat.process_hp_flash(delta)

	if combat.in_combat:
		_process_combat_wrapper(delta)
		return

	if not action_in_progress:
		return

	_process_action(delta)


func _process_combat_wrapper(delta: float) -> void:
	time_spent += delta
	var remaining := maxf(LOOP_DURATION - time_spent, 0.0)
	main_timer_bar.value = remaining
	_update_timer_label()

	if remaining <= 0.0:
		_end_loop()
		return

	combat.process_combat(delta)


func _process_action(delta: float) -> void:
	current_action_elapsed += delta
	time_spent += delta

	var remaining := maxf(LOOP_DURATION - time_spent, 0.0)
	main_timer_bar.value = remaining
	_update_timer_label()

	if active_action_bar:
		ui_helpers.set_bar_progress(active_action_bar, current_action_elapsed / current_action_duration)

		if current_action_duration > 5.0 and active_action_bar.get_child_count() > 1:
			var time_lbl: Label = active_action_bar.get_child(1)
			var secs_left := maxf(current_action_duration - current_action_elapsed, 0.0)
			if secs_left >= 60.0:
				var mins := int(secs_left) / 60
				var secs := int(secs_left) % 60
				time_lbl.text = "%d:%02d" % [mins, secs]
			else:
				time_lbl.text = "%ds" % ceili(secs_left)

	if action_queue.queue_display and is_instance_valid(action_queue.queue_display) and int(current_action_elapsed) != int(current_action_elapsed - delta):
		action_queue.update_active_time()

	if remaining <= 0.0:
		_end_loop()
		return

	if current_action_elapsed >= current_action_duration:
		_finish_action()


#endregion

#region ---- LOCATION UI ----

func show_location(location) -> void:
	current_location = location
	var data: Dictionary = locations.get_location_data(location)

	location_label.text = data["name"]
	_cancel_active_action()
	ui_helpers.clear_info_panel()

	# Clear queue display.
	if action_queue.queue_display and is_instance_valid(action_queue.queue_display):
		action_queue.queue_display.get_parent().remove_child(action_queue.queue_display)
		action_queue.queue_display.free()
		action_queue.queue_display = null

	var old_children := button_row.get_children()
	for child in old_children:
		button_row.remove_child(child)
		child.free()

	var actions: Array = data["actions"]

	_location_has_shop_items = false
	for action in actions:
		if action.has("item_id"):
			_location_has_shop_items = true
			break

	for action in actions:
		button_row.add_child(ui_helpers.create_action_slot(action))

	actions_label.visible = true
	button_row.visible = true
	combat_section.visible = false
	combat_log_panel.visible = false

	ui_helpers.show_location_synopsis(location)


func _cancel_active_action() -> void:
	if not action_in_progress:
		active_action_bar = null
		active_action_button = null
		return

	if current_action_elapsed > 0.0 and not current_action_id.is_empty():
		action_queue.action_progress[current_action_id] = current_action_elapsed

	var gold_cost: int = current_action_data.get("gold_cost", 0)
	if gold_cost > 0:
		player.gold += gold_cost
		ui_helpers.update_player_stats_ui()

	if active_action_bar:
		active_action_bar.visible = false
	if active_action_button:
		active_action_button.visible = true

	action_in_progress = false
	active_action_bar = null
	active_action_button = null


## Called deferred after an interrupt to safely rebuild UI and start the new action.
func _deferred_start_queue_after_interrupt() -> void:
	action_queue.deferred_start_queue_after_interrupt()


#endregion

#region ---- PUBLIC API (for RouteExecutor) ----

func execute_action(action: Dictionary) -> void:
	if action_in_progress or combat.in_combat:
		return

	show_location(current_location)
	await get_tree().process_frame

	action_queue.enqueue_action(action, true)

	if not action_in_progress:
		action_in_progress = true
		current_action_name = action["label"]
		current_action_id = action["action_id"]
		current_action_duration = action["duration"]
		current_action_elapsed = 0.0
		current_action_destination = action["destination"]
		current_action_data = action
		var gold_cost: int = action.get("gold_cost", 0)
		if gold_cost > 0:
			player.gold -= gold_cost
			ui_helpers.update_player_stats_ui()
		active_action_bar = null
		active_action_button = null
		status_label.text = ""


func execute_combat(action: Dictionary, auto_count: int = 0) -> void:
	if action_in_progress or combat.in_combat:
		return
	combat.auto_fight_remaining = auto_count
	combat.enter_combat(action)


#endregion

#region ---- ACTION COMPLETION ----

func _finish_action() -> void:
	action_in_progress = false
	active_action_bar = null
	active_action_button = null

	action_queue.action_progress.erase(current_action_id)

	var reward_text := ""

	# ---- Leaving the jail: drop the keys ----
	if current_action_data.get("action_id", "") == "jail_leave":
		if player.inventory.has("jail_keys"):
			player.inventory.erase("jail_keys")
			ui_helpers.update_inventory_ui()

	# ---- Unlock desk ----
	if current_action_data.get("unlock_desk", false):
		player.desk_unlocked = true
		reward_text = "  (The desk drawer slides open...)"

	# ---- Desk loot: health potion ----
	if current_action_data.get("desk_loot", false):
		player.inventory["health_potion"] = player.inventory.get("health_potion", 0) + 1
		player.desk_potions_taken += 1
		ui_helpers.update_inventory_ui()
		var remaining_potions := player.DESK_POTIONS_MAX - player.desk_potions_taken
		if remaining_potions > 0:
			reward_text = "  (Found a Health Potion! %d more in the drawer)" % remaining_potions
		else:
			reward_text = "  (Found a Health Potion! The drawer is now empty)"

	# ---- Prisoner note: persistent reading ----
	if current_action_data.get("note_read", false):
		player.note_read_progress = 1.0
		player.note_fully_read = true
		reward_text = ""
		ui_helpers.show_modal("Prisoner Note", locations.get_prisoner_note_text())
		status_label.text = "You finish reading the crumpled note..."

	# ---- Take the note ----
	if current_action_data.get("take_note", false):
		player.inventory["prisoner_note"] = 1
		ui_helpers.update_inventory_ui()
		reward_text = "  (Took the prisoner note)"

	# ---- Healing ----
	if current_action_data.get("heal", false):
		player.hp = player.max_hp
		ui_helpers.update_player_stats_ui()
		reward_text = "  (HP restored!)"

	# ---- Shop purchase ----
	if current_action_data.get("shop_buy", false):
		var item_id: String = current_action_data["item_id"]
		player.inventory[item_id] = player.inventory.get(item_id, 0) + 1
		var item_name: String = player.item_catalogue[item_id]["name"]
		reward_text = "  (Purchased %s)" % item_name
		player.recalculate_equipment()
		ui_helpers.update_inventory_ui()

	if not current_action_data.get("note_read", false):
		status_label.text = "Completed: " + current_action_name + reward_text

	var completed_name := current_action_name

	if not action_queue.action_queue.is_empty():
		action_queue.action_queue.remove_at(0)

	if current_action_destination != -1:
		action_queue.action_queue.clear()
		show_location(current_action_destination as Location)
		if current_action_destination == Location.JAIL_CELL_GUARD:
			status_label.text = "The guard storms into your cell, keys jangling.\nGuard: \"That's it! I warned you — now you're gonna get it!\""
	else:
		show_location(current_location)
		if not action_queue.action_queue.is_empty():
			action_queue.start_queue_head()
		else:
			action_queue.update_queue_ui()

	action_completed.emit(completed_name)


#endregion

#region ---- DEATH, LOOP RESET ----

func player_died() -> void:
	combat.in_combat = false
	combat.fleeing = false
	combat.drinking_potion = false
	combat.auto_fight_remaining = 0
	action_in_progress = false
	combat_section.visible = false
	combat_log_panel.visible = false
	actions_label.visible = false
	button_row.visible = false
	location_label.text = ""
	active_action_bar = null
	active_action_button = null
	if combat.flee_progress_bar:
		combat.flee_progress_bar.queue_free()
		combat.flee_progress_bar = null
	ui_helpers.update_player_stats_ui()
	combat_completed.emit(combat.enemy_name, false)
	_trigger_loop_reset("death")


func _end_loop() -> void:
	combat.in_combat = false
	combat.fleeing = false
	combat.drinking_potion = false
	action_in_progress = false
	combat_section.visible = false
	combat_log_panel.visible = false
	actions_label.visible = false
	button_row.visible = false
	location_label.text = ""
	main_timer_bar.value = 0.0
	active_action_bar = null
	active_action_button = null
	if combat.flee_progress_bar:
		combat.flee_progress_bar.queue_free()
		combat.flee_progress_bar = null
	_update_timer_label()
	_trigger_loop_reset("time")


func _trigger_loop_reset(reason: String) -> void:
	# Commit any in-progress persistent action progress before reset.
	if action_in_progress and current_action_data.get("note_read", false):
		var start_progress: float = current_action_data.get("_note_start_progress", player.note_read_progress)
		player.note_read_progress = clampf(start_progress + (current_action_elapsed / player.NOTE_READ_DURATION), 0.0, 1.0)
	elif action_queue.action_progress.has("jail_read_note"):
		var saved: float = action_queue.action_progress["jail_read_note"]
		player.note_read_progress = clampf(player.note_read_progress + (saved / player.NOTE_READ_DURATION), 0.0, 1.0)

	loop_count += 1

	var narrative := ""
	match reason:
		"death":
			if loop_count <= 1:
				narrative = "Everything goes dark..."
			elif loop_count == 2:
				narrative = "The darkness takes you again..."
			else:
				narrative = "You feel the familiar pull of the curse as everything fades..."
		"time":
			if not timer_revealed:
				narrative = "A strange force overwhelms you. Everything goes dark..."
			elif loop_count <= 3:
				narrative = "The curse's power surges. Time has run out."
			else:
				narrative = "The loop ends. You feel reality rewinding..."

	if loop_count >= 2 and not timer_revealed:
		timer_revealed = true
		narrative += "\n\nSomething stirs in your mind... a sense of time slipping away."
		narrative += "\nYou feel the curse's grip — you can almost sense how long you have."

	status_label.text = narrative

	var restart_timer := get_tree().create_timer(3.0)
	restart_timer.timeout.connect(_restart_loop)
	loop_ended.emit()


func _restart_loop() -> void:
	time_spent = 0.0
	player.reset_for_new_loop()
	action_queue.action_progress.clear()
	action_queue.action_queue.clear()

	current_location = Location.JAIL_CELL
	main_timer_bar.value = LOOP_DURATION
	_update_timer_visibility()
	_update_timer_label()
	ui_helpers.update_player_stats_ui()
	ui_helpers.update_inventory_ui()
	ui_helpers.clear_info_panel()
	show_location(current_location)

	if loop_count == 2:
		status_label.text = "You wake with a jolt. This feels... familiar."
	elif loop_count == 3:
		status_label.text = "Again. You're back in the cell. This has happened before."
	else:
		status_label.text = "The loop begins anew. You know what to do."


#endregion

#region ---- TIMER HELPERS ----

func _update_timer_label() -> void:
	var remaining := maxf(LOOP_DURATION - time_spent, 0.0)
	var minutes := int(remaining) / 60
	var seconds := int(remaining) % 60
	timer_label.text = "Time Remaining: %d:%02d" % [minutes, seconds]


func _update_timer_visibility() -> void:
	timer_section.visible = timer_revealed


#endregion
