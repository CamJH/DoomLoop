extends MarginContainer
## DoomLoop — Main game script.

#region ---- CONSTANTS & STATE ----

## Total loop time in seconds (10 minutes).
const LOOP_DURATION := 600.0

# ---- Signals for Route Executor ----
signal action_completed(action_name: String)
signal combat_completed(enemy_name: String, victory: bool)
signal loop_ended()

# ---- Location IDs ----
enum Location { OUTSIDE, TOWN, TOWN_HEALER, TOWN_BLACKSMITH, TOWN_GENERAL_GOODS, DUNGEON_ENTRANCE }

# ---- Dungeon state ----
const MAX_SLIMES := 10
var slimes_defeated := 0
var all_slimes_cleared := false

# ---- Player stats ----
var player_max_hp := 10
var player_hp := 10
var player_xp := 0
var player_gold := 0
var player_base_attack_speed := 3.0  ## Base seconds per attack.
var player_attack_speed_bonus := 0.0  ## Percentage bonus from equipment (0.2 = 20%).
var player_base_damage := 1
var player_damage_bonus := 0  ## From equipment (e.g. sword).
var player_damage_reduction := 0  ## From equipment (e.g. shield).

# ---- Inventory ----
var inventory: Dictionary = { "health_potion": 10 }

var item_catalogue := {
	"iron_sword":    { "name": "Iron Sword",    "cost": 3, "max": 1,  "description": "A sturdy blade forged in town.", "bonus_damage": 1, "attack_speed_bonus": 0.2 },
	"wooden_shield": { "name": "Wooden Shield", "cost": 2, "max": 1,  "description": "A simple shield that absorbs blows.", "damage_reduction": 1 },
	"health_potion": { "name": "Health Potion", "cost": 1, "max": 10, "description": "Restores 5 HP instantly." },
}

var blacksmith_stock: Array[String] = ["iron_sword", "wooden_shield"]
var general_goods_stock: Array[String] = ["health_potion"]

# ---- Action / location state ----
var current_location: Location = Location.TOWN
var time_spent := 0.0
var action_in_progress := false
var current_action_duration := 0.0
var current_action_elapsed := 0.0
var current_action_name := ""
var current_action_destination: int = -1
var current_action_data: Dictionary = {}

## Whether the current location has any shop items (used for button alignment).
var _location_has_shop_items := false

## The ProgressBar currently filling (inside a button slot).
var active_action_bar: ProgressBar = null
## The Button that is currently active (hidden behind its bar).
var active_action_button: Button = null

# ---- Combat state ----
var in_combat := false
var fleeing := false
var drinking_potion := false  ## True while the player is drinking a health potion.
var potion_drink_timer := 0.0
const POTION_DRINK_DURATION := 2.0
const POTION_HP_THRESHOLD := 0.4  ## Drink at or below 40% HP.

var enemy_name := ""
var enemy_hp := 0
var enemy_max_hp := 0
var enemy_attack_speed := 2.0
var enemy_damage := 1
var enemy_attack_timer := 0.0
var player_attack_timer := 0.0

var combat_reward_gold := 0
var combat_reward_xp := 0
var combat_is_slime := false

var combat_log_lines: Array[String] = []
const MAX_COMBAT_LOG_LINES := 5

# ---- HP flash state ----
const HP_FLASH_THRESHOLD := 0.3  ## Flash when at or below 30%.
const HP_FLASH_SPEED := 4.0  ## Flashes per second.
var hp_flash_timer := 0.0

## The dynamically created ProgressBar that replaces the flee button.
var flee_progress_bar: ProgressBar = null

# ---- Auto-fight state ----
var auto_fight_remaining := 0  ## Fights left in the current auto-fight chain (0 = off).
var last_combat_action: Dictionary = {}

# ---- Route Planner state ----
var route_executor: RefCounted = null  ## RouteExecutor instance (or null when not auto-playing).
var planner_visible := false

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
# Combat auto-fight UI (created dynamically)
var auto_fight_label: Label = null
var stop_after_fight_button: Button = null
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
# Planner state
var current_plan: RoutePlan = null
var virtual_location: int = -1  ## Location enum value tracked during planning.
var virtual_gold: int = 0
var virtual_inventory: Dictionary = {}
var load_popup: PanelContainer = null  ## Popup for load plan list.


#endregion

#region ---- LIFECYCLE ----

func _ready() -> void:
	main_timer_bar.max_value = LOOP_DURATION
	main_timer_bar.value = LOOP_DURATION
	# Dark background for the whole window.
	RenderingServer.set_default_clear_color(Color(0.06, 0.06, 0.1, 1.0))

	_update_timer_label()
	_update_player_stats_ui()
	_update_inventory_ui()
	_show_location(current_location)
	flee_button.pressed.connect(_on_flee_pressed)

	# Planner connections.
	plan_route_button.pressed.connect(_toggle_planner)
	start_run_button.pressed.connect(_on_start_run)
	clear_plan_button.pressed.connect(_on_clear_plan)
	save_plan_button.pressed.connect(_on_save_plan)
	load_plan_button.pressed.connect(_on_load_plan)


func _process(delta: float) -> void:
	_process_hp_flash(delta)

	if in_combat:
		_process_combat(delta)
		return

	if not action_in_progress:
		return

	_process_action(delta)


func _process_action(delta: float) -> void:
	current_action_elapsed += delta
	time_spent += delta

	var remaining := maxf(LOOP_DURATION - time_spent, 0.0)
	main_timer_bar.value = remaining
	_update_timer_label()

	# Update the button-bar fill.
	if active_action_bar:
		active_action_bar.value = (current_action_elapsed / current_action_duration) * 100.0

	if remaining <= 0.0:
		_end_loop()
		return

	if current_action_elapsed >= current_action_duration:
		_finish_action()


func _process_combat(delta: float) -> void:
	time_spent += delta
	var remaining := maxf(LOOP_DURATION - time_spent, 0.0)
	main_timer_bar.value = remaining
	_update_timer_label()

	if remaining <= 0.0:
		_end_loop()
		return

	# If fleeing, tick the flee bar — enemy still attacks.
	if fleeing:
		current_action_elapsed += delta
		if flee_progress_bar:
			flee_progress_bar.value = (current_action_elapsed / current_action_duration) * 100.0
		if current_action_elapsed >= current_action_duration:
			_finish_flee()
			return

	# ---- Enemy attack bar ----
	enemy_attack_timer += delta
	if enemy_attack_timer >= enemy_attack_speed:
		enemy_attack_timer -= enemy_attack_speed
		var actual_dmg := _get_damage_after_reduction(enemy_damage)
		player_hp = maxi(player_hp - actual_dmg, 0)
		_update_player_stats_ui()
		if actual_dmg < enemy_damage:
			_add_combat_log("%s hits you for %d! (%d blocked)" % [enemy_name, actual_dmg, enemy_damage - actual_dmg])
		else:
			_add_combat_log("%s hits you for %d!" % [enemy_name, actual_dmg])
		if player_hp <= 0:
			_player_died()
			return
	enemy_attack_bar.value = (enemy_attack_timer / enemy_attack_speed) * 100.0

	# ---- Auto-flee check ----
	if not fleeing and not drinking_potion:
		var auto_flee_pct := auto_flee_spinbox.value
		if auto_flee_pct > 0.0:
			var hp_pct := (float(player_hp) / float(player_max_hp)) * 100.0
			if hp_pct <= auto_flee_pct:
				_on_flee_pressed()

	# ---- Potion drinking (pauses player attack) ----
	if drinking_potion:
		potion_drink_timer += delta
		# Show potion progress on the player attack bar.
		player_attack_bar.value = (potion_drink_timer / POTION_DRINK_DURATION) * 100.0
		if potion_drink_timer >= POTION_DRINK_DURATION:
			_finish_drinking_potion()
		if drinking_potion:
			return  # Skip player attacking only while still drinking.

	# ---- Player attack bar (only ticks when not fleeing) ----
	if not fleeing:
		player_attack_timer += delta
		var atk_speed := _get_player_attack_speed()
		if player_attack_timer >= atk_speed:
			player_attack_timer -= atk_speed
			var dmg := _get_player_attack_damage()
			enemy_hp = maxi(enemy_hp - dmg, 0)
			_update_combat_ui()
			_add_combat_log("You hit %s for %d!" % [enemy_name, dmg])
			if enemy_hp <= 0:
				_enemy_killed()
				return
			# Check for auto potion after the attack completes.
			_check_auto_potion()
			if drinking_potion:
				player_attack_bar.value = 0.0
				return
		player_attack_bar.value = (player_attack_timer / atk_speed) * 100.0


#endregion

#region ---- COMBAT SYSTEM ----

func _enter_combat(action: Dictionary) -> void:
	in_combat = true
	fleeing = false
	drinking_potion = false
	last_combat_action = action

	enemy_name = action["enemy_name"]
	enemy_hp = action["enemy_hp"]
	enemy_max_hp = action["enemy_hp"]
	enemy_attack_speed = action["enemy_attack_speed"]
	enemy_damage = action["enemy_damage"]
	combat_reward_gold = action.get("reward_gold", 0)
	combat_reward_xp = action.get("reward_xp", 0)
	combat_is_slime = action.get("slime_fight", false)

	enemy_attack_timer = 0.0
	player_attack_timer = 0.0
	combat_log_lines.clear()

	actions_label.visible = false
	button_row.visible = false
	combat_section.visible = true
	flee_button.visible = true
	flee_button.disabled = false
	# Clean up any leftover flee bar from a previous fight.
	if flee_progress_bar:
		flee_progress_bar.queue_free()
		flee_progress_bar = null
	player_attack_bar.value = 0.0
	enemy_attack_bar.value = 0.0

	# Build auto-fight UI in the combat section.
	_build_combat_footer()
	_update_combat_ui()

	# Show enemy info in info panel and show combat log panel.
	_show_enemy_info(action)
	combat_log_panel.visible = true
	_add_combat_log("A %s appears!" % enemy_name)


func _build_combat_footer() -> void:
	# Remove old dynamic nodes immediately (not deferred) to avoid stale refs.
	if stop_after_fight_button and is_instance_valid(stop_after_fight_button):
		stop_after_fight_button.get_parent().remove_child(stop_after_fight_button)
		stop_after_fight_button.free()
	stop_after_fight_button = null
	if auto_fight_label and is_instance_valid(auto_fight_label):
		auto_fight_label.get_parent().remove_child(auto_fight_label)
		auto_fight_label.free()
	auto_fight_label = null

	var combat_vbox: VBoxContainer = combat_section.get_child(0)  # CombatVBox

	# ---- Auto-fight status + stop button ----
	if auto_fight_remaining > 0:
		auto_fight_label = Label.new()
		auto_fight_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		auto_fight_label.modulate = Color(0.7, 0.85, 1.0)
		auto_fight_label.add_theme_font_size_override("font_size", 13)
		_update_auto_fight_label()
		combat_vbox.add_child(auto_fight_label)
		# Move before combat log (combat log is last child).
		combat_vbox.move_child(auto_fight_label, combat_vbox.get_child_count() - 2)

		stop_after_fight_button = Button.new()
		stop_after_fight_button.text = "Stop After This Fight"
		stop_after_fight_button.custom_minimum_size = Vector2(200, 36)
		stop_after_fight_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		stop_after_fight_button.pressed.connect(_on_stop_after_fight)
		combat_vbox.add_child(stop_after_fight_button)
		combat_vbox.move_child(stop_after_fight_button, combat_vbox.get_child_count() - 2)


func _update_auto_fight_label() -> void:
	if auto_fight_label and is_instance_valid(auto_fight_label):
		auto_fight_label.text = "Auto-fight: %d remaining" % auto_fight_remaining


func _on_stop_after_fight() -> void:
	auto_fight_remaining = 0
	_update_auto_fight_label()
	if auto_fight_label and is_instance_valid(auto_fight_label):
		auto_fight_label.text = "Auto-fight: stopping after this fight"
	if stop_after_fight_button and is_instance_valid(stop_after_fight_button):
		stop_after_fight_button.disabled = true


func _enemy_killed() -> void:
	player_gold += combat_reward_gold
	player_xp += combat_reward_xp

	var reward_text := "+%d gold, +%d xp" % [combat_reward_gold, combat_reward_xp]

	if combat_is_slime:
		slimes_defeated += 1
		if slimes_defeated >= MAX_SLIMES and not all_slimes_cleared:
			all_slimes_cleared = true
			player_gold += 20
			player_xp += 10
			reward_text += " — All slimes cleared! Bonus: +20 gold, +10 xp!"

	_update_player_stats_ui()
	_update_inventory_ui()
	status_label.text = "%s defeated! (%s)" % [enemy_name, reward_text]

	# Auto-fight: re-enter combat if remaining count > 0 and enemies still exist.
	if auto_fight_remaining > 0 and not last_combat_action.is_empty():
		var can_auto_fight := true
		if last_combat_action.get("slime_fight", false) and all_slimes_cleared:
			can_auto_fight = false
		if can_auto_fight:
			auto_fight_remaining -= 1
			# Re-enter combat directly without hiding/showing combat section.
			_enter_combat(last_combat_action)
			return

	# Exit combat.
	in_combat = false
	fleeing = false
	drinking_potion = false
	auto_fight_remaining = 0
	combat_section.visible = false
	combat_log_panel.visible = false
	_show_location(current_location)
	combat_completed.emit(enemy_name, true)


func _on_flee_pressed() -> void:
	if fleeing:
		return
	fleeing = true

	# Replace flee button with a filling progress bar.
	flee_button.visible = false
	flee_progress_bar = _create_bar_overlay("Fleeing...", Vector2(200, 40))
	flee_progress_bar.custom_minimum_size = Vector2(200, 40)
	flee_progress_bar.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	# Insert where the flee button is (find its index in parent).
	var parent := flee_button.get_parent()
	var idx := flee_button.get_index()
	parent.add_child(flee_progress_bar)
	parent.move_child(flee_progress_bar, idx + 1)

	current_action_duration = 1.0
	current_action_elapsed = 0.0
	_add_combat_log("You attempt to flee!")


func _finish_flee() -> void:
	in_combat = false
	fleeing = false
	drinking_potion = false
	auto_fight_remaining = 0
	combat_section.visible = false
	combat_log_panel.visible = false
	if flee_progress_bar:
		flee_progress_bar.queue_free()
		flee_progress_bar = null
	status_label.text = "Escaped from %s!" % enemy_name
	_show_location(current_location)
	combat_completed.emit(enemy_name, true)  # Treat flee as completing the step.


#endregion

#region ---- PLAYER STATS & EQUIPMENT ----

func _recalculate_equipment() -> void:
	player_damage_bonus = 0
	player_damage_reduction = 0
	player_attack_speed_bonus = 0.0
	for item_id in inventory:
		if inventory[item_id] <= 0:
			continue
		var item: Dictionary = item_catalogue.get(item_id, {})
		player_damage_bonus += item.get("bonus_damage", 0)
		player_damage_reduction += item.get("damage_reduction", 0)
		player_attack_speed_bonus += item.get("attack_speed_bonus", 0.0)


func _get_player_attack_damage() -> int:
	return player_base_damage + player_damage_bonus


func _get_player_attack_speed() -> float:
	## Lower = faster. 20% bonus means 20% less time between attacks.
	return player_base_attack_speed * (1.0 - player_attack_speed_bonus)


func _get_damage_after_reduction(raw_damage: int) -> int:
	return maxi(raw_damage - player_damage_reduction, 0)


# ---- Auto health potion ----

func _check_auto_potion() -> void:
	var hp_ratio := float(player_hp) / float(player_max_hp)
	if hp_ratio > POTION_HP_THRESHOLD:
		return
	var potions: int = inventory.get("health_potion", 0)
	if potions <= 0:
		return
	# Start drinking.
	drinking_potion = true
	potion_drink_timer = 0.0
	player_attack_timer = 0.0  # Reset attack progress.
	player_attack_label.text = "Drinking Health Potion..."
	_add_combat_log("You drink a Health Potion...")


func _finish_drinking_potion() -> void:
	drinking_potion = false
	potion_drink_timer = 0.0
	player_attack_label.text = "Your Attack"
	# Consume the potion and heal.
	inventory["health_potion"] = inventory.get("health_potion", 0) - 1
	if inventory["health_potion"] <= 0:
		inventory.erase("health_potion")
	var heal_amount := 5
	var old_hp := player_hp
	player_hp = mini(player_hp + heal_amount, player_max_hp)
	var healed := player_hp - old_hp
	_update_player_stats_ui()
	_update_inventory_ui()
	_add_combat_log("Healed for %d HP! (%d/%d)" % [healed, player_hp, player_max_hp])


#endregion

#region ---- LOCATION DATA & ACTIONS ----

func _build_shop_actions(stock: Array[String], back_destination: Location) -> Array:
	var actions: Array = []
	for item_id in stock:
		var item: Dictionary = item_catalogue[item_id]
		var owned: int = inventory.get(item_id, 0)
		var at_limit: bool = owned >= item["max"]
		var can_afford: bool = player_gold >= item["cost"]
		var lbl: String = "Buy %s — %d gold" % [item["name"], item["cost"]]

		if at_limit:
			actions.append({
				"label": lbl, "duration": 0.0, "destination": -1,
				"disabled": true, "disabled_reason": "limit reached",
				"item_id": item_id,
			})
		elif not can_afford:
			actions.append({
				"label": lbl, "duration": 0.0, "destination": -1,
				"disabled": true, "disabled_reason": "can't afford",
				"item_id": item_id,
			})
		else:
			actions.append({
				"label": lbl, "duration": 2.0, "destination": -1,
				"shop_buy": true, "item_id": item_id,
				"gold_cost": item["cost"],
			})
	actions.append({ "label": "Back to Town", "duration": 1.0, "destination": back_destination })
	return actions


func get_location_data(location: Location) -> Dictionary:
	match location:
		Location.OUTSIDE:
			return {
				"name": "Outside",
				"actions": [
					{ "label": "Head into Town", "duration": 1.0, "destination": Location.TOWN },
					{ "label": "Head into the Dungeon", "duration": 1.0, "destination": Location.DUNGEON_ENTRANCE },
				],
			}

		Location.TOWN:
			return {
				"name": "Town",
				"actions": [
					{ "label": "Enter the Dungeon", "duration": 1.0, "destination": Location.DUNGEON_ENTRANCE },
					{ "label": "Visit the Healer", "duration": 1.0, "destination": Location.TOWN_HEALER },
					{ "label": "Visit the Blacksmith", "duration": 1.0, "destination": Location.TOWN_BLACKSMITH },
					{ "label": "Visit General Goods", "duration": 1.0, "destination": Location.TOWN_GENERAL_GOODS },
				],
			}

		Location.TOWN_HEALER:
			var actions: Array = []
			if player_hp >= player_max_hp:
				actions.append({
					"label": "Heal to full HP — 1 gold", "duration": 0.0, "destination": -1,
					"disabled": true, "disabled_reason": "full health",
				})
			elif player_gold < 1:
				actions.append({
					"label": "Heal to full HP — 1 gold", "duration": 0.0, "destination": -1,
					"disabled": true, "disabled_reason": "can't afford",
				})
			else:
				actions.append({
					"label": "Heal to full HP — 1 gold", "duration": 2.0, "destination": -1,
					"heal": true, "gold_cost": 1,
				})
			actions.append({ "label": "Back to Town", "duration": 1.0, "destination": Location.TOWN })
			return { "name": "Town — Healer", "actions": actions }

		Location.TOWN_BLACKSMITH:
			return {
				"name": "Town — Blacksmith",
				"actions": _build_shop_actions(blacksmith_stock, Location.TOWN),
			}

		Location.TOWN_GENERAL_GOODS:
			return {
				"name": "Town — General Goods",
				"actions": _build_shop_actions(general_goods_stock, Location.TOWN),
			}

		Location.DUNGEON_ENTRANCE:
			var actions: Array = []
			if not all_slimes_cleared:
				var slime_action := {
					"enemy_name": "Slime", "enemy_hp": 3,
					"enemy_attack_speed": 2.0, "enemy_damage": 1,
					"reward_gold": 2, "reward_xp": 1,
					"slime_fight": true,
				}
				var remaining_slimes := MAX_SLIMES - slimes_defeated
				actions.append({
					"label": "Fight a Slime (%d/%d)" % [slimes_defeated, MAX_SLIMES],
					"duration": 0.0, "destination": -1,
					"combat_start": true,
					"auto_fight_count": 0,
				}.merged(slime_action))
				actions.append({
					"label": "Fight All Slimes (%d left)" % remaining_slimes,
					"duration": 0.0, "destination": -1,
					"combat_start": true,
					"auto_fight_count": remaining_slimes - 1,
				}.merged(slime_action))
			else:
				actions.append({
					"label": "All slimes defeated!", "duration": 0.0, "destination": -1,
					"disabled": true,
				})
			actions.append({ "label": "Back to Town", "duration": 1.0, "destination": Location.TOWN })
			return { "name": "Dungeon Entrance", "actions": actions }

	return { "name": "???", "actions": [] }


#endregion

#region ---- UI HELPERS ----

## Creates a ProgressBar with a centered text label overlaid on it.
## Used for button-as-progress-bar and the flee bar.
func _create_bar_overlay(text: String, size: Vector2) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.min_value = 0.0
	bar.max_value = 100.0
	bar.value = 0.0
	bar.show_percentage = false
	bar.custom_minimum_size = size
	bar.size_flags_horizontal = Control.SIZE_SHRINK_CENTER

	var lbl := Label.new()
	lbl.text = text
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bar.add_child(lbl)

	return bar


## Each action slot is a container holding a Button (clickable) and a
## ProgressBar (hidden, shown when active).  The button and bar are the
## same size and stacked so the bar fills "inside" the button area.
## Shop items get an [?] info button beside them.
func _create_action_slot(action: Dictionary) -> Control:
	var is_disabled: bool = action.get("disabled", false)
	var is_combat: bool = action.get("combat_start", false)
	var has_item: bool = action.has("item_id")

	# -- Build the button --
	var btn := Button.new()
	if is_disabled:
		btn.text = action["label"]
		btn.disabled = true
		btn.tooltip_text = action.get("disabled_reason", "")
	elif is_combat:
		btn.text = action["label"]
	else:
		btn.text = "%s (%ss)" % [action["label"], int(action["duration"])]
	btn.custom_minimum_size = Vector2(300, 50)

	# -- Build the progress bar overlay (hidden by default) --
	var bar := _create_bar_overlay(action["label"] + "...", Vector2(300, 50))
	bar.visible = false

	# -- Stack button and bar --
	var slot := Control.new()
	slot.custom_minimum_size = Vector2(300, 50)
	btn.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bar.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	slot.add_child(btn)
	slot.add_child(bar)

	# -- Wire up clicks --
	if not is_disabled:
		var act: Dictionary = action
		if is_combat:
			btn.pressed.connect(func() -> void:
				auto_fight_remaining = act.get("auto_fight_count", 0)
				_enter_combat(act)
			)
		else:
			btn.pressed.connect(func() -> void: _start_action_from_slot(act, btn, bar))

	# -- Always wrap in an HBox so all rows are the same width --
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	slot.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(slot)

	if has_item:
		var info_btn := Button.new()
		info_btn.text = "?"
		info_btn.custom_minimum_size = Vector2(40, 50)
		var iid: String = action["item_id"]
		info_btn.pressed.connect(func() -> void: _show_item_info(iid))
		row.add_child(info_btn)
	elif _location_has_shop_items:
		var spacer := Control.new()
		spacer.custom_minimum_size = Vector2(40, 0)
		row.add_child(spacer)

	return row


## Shows item info in the right-side info panel.
func _show_enemy_info(action: Dictionary) -> void:
	_clear_info_panel()
	info_title.visible = false
	info_sep.visible = false

	var title := Label.new()
	title.text = action["enemy_name"]
	title.add_theme_font_size_override("font_size", 18)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.modulate = Color(1.0, 0.5, 0.5)
	info_content.add_child(title)

	var sep_line := ColorRect.new()
	sep_line.color = Color(1.0, 0.4, 0.4, 0.4)
	sep_line.custom_minimum_size = Vector2(0, 2)
	info_content.add_child(sep_line)

	# Description.
	var desc_text := ""
	if action.get("slime_fight", false):
		desc_text = "A quivering blob of translucent goo. Weak alone, but their numbers can wear you down."
	else:
		desc_text = "A hostile creature lurking in the dungeon."
	var desc := Label.new()
	desc.text = desc_text
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.modulate = Color(0.75, 0.75, 0.8)
	desc.add_theme_font_size_override("font_size", 13)
	info_content.add_child(desc)

	# Spacer.
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 4)
	info_content.add_child(spacer)

	# Stats.
	var stats: Array[String] = []
	stats.append("HP: %d" % action["enemy_hp"])
	stats.append("Damage: %d" % action["enemy_damage"])
	stats.append("Attack Speed: %.1fs" % action["enemy_attack_speed"])
	var stats_label := Label.new()
	stats_label.text = "\n".join(stats)
	stats_label.modulate = Color(1.0, 0.7, 0.7)
	stats_label.add_theme_font_size_override("font_size", 14)
	info_content.add_child(stats_label)

	# Rewards.
	var reward_spacer := Control.new()
	reward_spacer.custom_minimum_size = Vector2(0, 4)
	info_content.add_child(reward_spacer)

	var rewards_title := Label.new()
	rewards_title.text = "Rewards"
	rewards_title.modulate = Color(0.55, 0.75, 1.0)
	rewards_title.add_theme_font_size_override("font_size", 14)
	info_content.add_child(rewards_title)

	var rewards := Label.new()
	rewards.text = "%d Gold, %d XP" % [action.get("reward_gold", 0), action.get("reward_xp", 0)]
	rewards.modulate = Color(1.0, 0.85, 0.3)
	rewards.add_theme_font_size_override("font_size", 13)
	info_content.add_child(rewards)

	# Count remaining (for slimes).
	if action.get("slime_fight", false):
		var remaining := MAX_SLIMES - slimes_defeated
		var count_label := Label.new()
		count_label.text = "Remaining: %d / %d" % [remaining, MAX_SLIMES]
		count_label.modulate = Color(0.65, 0.65, 0.7)
		count_label.add_theme_font_size_override("font_size", 13)
		info_content.add_child(count_label)


func _show_item_info(item_id: String) -> void:
	var item: Dictionary = item_catalogue.get(item_id, {})
	if item.is_empty():
		return

	_clear_info_panel()
	info_title.visible = false
	info_sep.visible = false

	# ---- Item name header with accent color ----
	var title := Label.new()
	title.text = item["name"]
	title.add_theme_font_size_override("font_size", 18)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	# Color based on item type.
	var rarity_color := Color.WHITE
	if item.get("bonus_damage", 0) > 0 or item.get("attack_speed_bonus", 0.0) > 0.0:
		rarity_color = Color(0.55, 0.75, 1.0)
	elif item.get("damage_reduction", 0) > 0:
		rarity_color = Color(0.6, 0.85, 0.6)
	else:
		rarity_color = Color(1.0, 0.75, 0.45)
	title.modulate = rarity_color
	info_content.add_child(title)

	# ---- Accent separator ----
	var sep_line := ColorRect.new()
	sep_line.color = Color(rarity_color, 0.4)
	sep_line.custom_minimum_size = Vector2(0, 2)
	info_content.add_child(sep_line)

	# ---- Stat lines ----
	var stats: Array[String] = []
	if item.get("bonus_damage", 0) > 0:
		stats.append("+%d Damage" % item["bonus_damage"])
	if item.get("attack_speed_bonus", 0.0) > 0.0:
		stats.append("+%d%% Attack Speed" % int(item["attack_speed_bonus"] * 100))
	if item.get("damage_reduction", 0) > 0:
		stats.append("-%d Damage Taken" % item["damage_reduction"])

	if stats.size() > 0:
		var stats_label := Label.new()
		stats_label.text = "\n".join(stats)
		stats_label.modulate = Color(0.7, 1.0, 0.7)
		stats_label.add_theme_font_size_override("font_size", 14)
		info_content.add_child(stats_label)

	# ---- Description ----
	var desc := Label.new()
	desc.text = item.get("description", "No description.")
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.modulate = Color(0.75, 0.75, 0.8)
	desc.add_theme_font_size_override("font_size", 13)
	info_content.add_child(desc)

	# ---- Cost ----
	var cost_label := Label.new()
	cost_label.text = "%d gold" % item["cost"]
	cost_label.modulate = Color(1.0, 0.85, 0.3)
	cost_label.add_theme_font_size_override("font_size", 14)
	info_content.add_child(cost_label)

	# ---- Owned count ----
	var owned: int = inventory.get(item_id, 0)
	var limit: int = item.get("max", 1)
	var owned_label := Label.new()
	owned_label.text = "Owned: %d / %d" % [owned, limit]
	owned_label.modulate = Color(0.65, 0.65, 0.7)
	owned_label.add_theme_font_size_override("font_size", 13)
	info_content.add_child(owned_label)


func _clear_info_panel() -> void:
	for child in info_content.get_children():
		child.queue_free()
	info_title.visible = true
	info_sep.visible = true


func _show_location(location: Location) -> void:
	current_location = location
	var data: Dictionary = get_location_data(location)

	location_label.text = data["name"]
	_cancel_active_action()
	_clear_info_panel()

	# Clear old slots.
	for child in button_row.get_children():
		child.queue_free()

	var actions: Array = data["actions"]

	# Check if any action in this location has an item (shop) or combat,
	# so non-matching buttons can add spacers to keep widths aligned.
	_location_has_shop_items = false
	for action in actions:
		if action.has("item_id"):
			_location_has_shop_items = true
			break

	for action in actions:
		button_row.add_child(_create_action_slot(action))

	actions_label.visible = true
	button_row.visible = true
	combat_section.visible = false
	combat_log_panel.visible = false


func _cancel_active_action() -> void:
	if not action_in_progress:
		active_action_bar = null
		active_action_button = null
		return

	# Refund gold if the cancelled action had a cost.
	var gold_cost: int = current_action_data.get("gold_cost", 0)
	if gold_cost > 0:
		player_gold += gold_cost
		_update_player_stats_ui()

	# Reset the old bar/button visuals.
	if active_action_bar:
		active_action_bar.visible = false
		active_action_bar.value = 0.0
	if active_action_button:
		active_action_button.visible = true

	action_in_progress = false
	active_action_bar = null
	active_action_button = null


func _start_action_from_slot(action: Dictionary, btn: Button, bar: ProgressBar) -> void:
	# If clicking the same button that's already active, ignore.
	if action_in_progress and active_action_bar == bar:
		return

	# If a different action was in progress, cancel it first.
	if action_in_progress:
		_cancel_active_action()

	action_in_progress = true
	current_action_name = action["label"]
	current_action_duration = action["duration"]
	current_action_elapsed = 0.0
	current_action_destination = action["destination"]
	current_action_data = action

	var gold_cost: int = action.get("gold_cost", 0)
	if gold_cost > 0:
		player_gold -= gold_cost
		_update_player_stats_ui()

	# Show the bar on top of the button.
	btn.visible = false
	bar.visible = true
	bar.value = 0.0
	active_action_bar = bar
	active_action_button = btn

	status_label.text = ""


## Public: programmatically execute an action (used by RouteExecutor).
## Shows the full location UI, then activates the matching button slot.
func execute_action(action: Dictionary) -> void:
	if action_in_progress or in_combat:
		return

	# First, ensure the location UI is fully built so all buttons are visible.
	_show_location(current_location)

	# Wait a frame so queue_free'd old nodes are gone and new nodes are ready.
	await get_tree().process_frame

	# Find the matching button/bar slot by label text.
	var target_label: String = action.get("label", "")
	var found := false
	for row in button_row.get_children():
		# Each row is an HBoxContainer containing a Control slot (with btn + bar).
		if not is_instance_valid(row):
			continue
		var slot: Control = null
		if row is HBoxContainer:
			slot = row.get_child(0) if row.get_child_count() > 0 else null
		elif row is Control:
			slot = row
		if slot == null or slot.get_child_count() < 2:
			continue
		var btn: Button = slot.get_child(0) as Button
		var bar: ProgressBar = slot.get_child(1) as ProgressBar
		if btn == null or bar == null:
			continue
		# Match by checking if the button text starts with the action label.
		if btn.text.begins_with(target_label) or btn.text == target_label + " (%ss)" % int(action["duration"]):
			_start_action_from_slot(action, btn, bar)
			found = true
			break

	# Fallback: if no matching button found, run the action directly.
	if not found:
		action_in_progress = true
		current_action_name = action["label"]
		current_action_duration = action["duration"]
		current_action_elapsed = 0.0
		current_action_destination = action["destination"]
		current_action_data = action
		var gold_cost: int = action.get("gold_cost", 0)
		if gold_cost > 0:
			player_gold -= gold_cost
			_update_player_stats_ui()
		active_action_bar = null
		active_action_button = null
		status_label.text = ""


## Public: programmatically start combat (used by RouteExecutor).
func execute_combat(action: Dictionary, auto_count: int = 0) -> void:
	if action_in_progress or in_combat:
		return
	auto_fight_remaining = auto_count
	_enter_combat(action)


func _finish_action() -> void:
	action_in_progress = false
	active_action_bar = null
	active_action_button = null

	var reward_text := ""

	# ---- Healing ----
	if current_action_data.get("heal", false):
		player_hp = player_max_hp
		_update_player_stats_ui()
		reward_text = "  (HP restored!)"

	# ---- Shop purchase ----
	if current_action_data.get("shop_buy", false):
		var item_id: String = current_action_data["item_id"]
		inventory[item_id] = inventory.get(item_id, 0) + 1
		var item_name: String = item_catalogue[item_id]["name"]
		reward_text = "  (Purchased %s)" % item_name
		_recalculate_equipment()
		_update_inventory_ui()

	status_label.text = "Completed: " + current_action_name + reward_text

	var completed_name := current_action_name
	if current_action_destination != -1:
		_show_location(current_action_destination as Location)
	else:
		_show_location(current_location)

	action_completed.emit(completed_name)


func _player_died() -> void:
	in_combat = false
	fleeing = false
	drinking_potion = false
	auto_fight_remaining = 0
	action_in_progress = false
	combat_section.visible = false
	combat_log_panel.visible = false
	actions_label.visible = false
	button_row.visible = false
	location_label.text = ""
	status_label.text = "You have been slain! The loop has ended."
	active_action_bar = null
	active_action_button = null
	if flee_progress_bar:
		flee_progress_bar.queue_free()
		flee_progress_bar = null
	_update_player_stats_ui()
	combat_completed.emit(enemy_name, false)
	loop_ended.emit()


func _end_loop() -> void:
	in_combat = false
	fleeing = false
	drinking_potion = false
	action_in_progress = false
	combat_section.visible = false
	combat_log_panel.visible = false
	actions_label.visible = false
	button_row.visible = false
	location_label.text = ""
	status_label.text = "Time's up! The loop has ended."
	main_timer_bar.value = 0.0
	active_action_bar = null
	active_action_button = null
	if flee_progress_bar:
		flee_progress_bar.queue_free()
		flee_progress_bar = null
	_update_timer_label()
	loop_ended.emit()


func _update_timer_label() -> void:
	var remaining := maxf(LOOP_DURATION - time_spent, 0.0)
	var minutes := int(remaining) / 60
	var seconds := int(remaining) % 60
	timer_label.text = "Time Remaining: %d:%02d" % [minutes, seconds]


func _process_hp_flash(delta: float) -> void:
	var hp_ratio := float(player_hp) / float(player_max_hp)
	if hp_ratio <= HP_FLASH_THRESHOLD and player_hp > 0:
		hp_flash_timer += delta
		# Use a sine wave to pulse between white and red.
		var flash := (sin(hp_flash_timer * HP_FLASH_SPEED * TAU) + 1.0) / 2.0
		hp_label.modulate = Color(1.0, 1.0 - flash * 0.7, 1.0 - flash * 0.7)
	else:
		hp_flash_timer = 0.0
		hp_label.modulate = Color.WHITE


func _update_player_stats_ui() -> void:
	hp_label.text = "HP: %d / %d" % [player_hp, player_max_hp]
	xp_label.text = "XP: %d" % player_xp
	gold_label.text = "Gold: %d" % player_gold


func _update_combat_ui() -> void:
	var count_text := ""
	if combat_is_slime:
		count_text = "  (%d/%d)" % [slimes_defeated, MAX_SLIMES]
	enemy_hp_label.text = "%s  HP: %d / %d%s" % [enemy_name, enemy_hp, enemy_max_hp, count_text]


func _add_combat_log(msg: String) -> void:
	combat_log_lines.append(msg)
	if combat_log_lines.size() > MAX_COMBAT_LOG_LINES:
		combat_log_lines.remove_at(0)
	combat_log_label.text = "\n".join(combat_log_lines)
	# Auto-scroll to bottom after the label resizes (deferred so layout updates first).
	await get_tree().process_frame
	if is_instance_valid(combat_log_scroll):
		combat_log_scroll.scroll_vertical = int(combat_log_scroll.get_v_scroll_bar().max_value)


func _update_inventory_ui() -> void:
	for child in inventory_list.get_children():
		child.queue_free()

	var has_items := false
	for item_id in item_catalogue:
		var count: int = inventory.get(item_id, 0)
		if count <= 0:
			continue
		has_items = true
		var item: Dictionary = item_catalogue[item_id]
		var btn := Button.new()
		btn.flat = true
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		if item["max"] == 1:
			btn.text = item["name"]
		else:
			btn.text = "%s  x%d" % [item["name"], count]
		btn.tooltip_text = item.get("description", "")
		btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		var iid: String = item_id
		btn.pressed.connect(func() -> void: _show_item_info(iid))
		inventory_list.add_child(btn)

	if not has_items:
		var empty_lbl := Label.new()
		empty_lbl.text = "(empty)"
		empty_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty_lbl.modulate = Color(1, 1, 1, 0.5)
		inventory_list.add_child(empty_lbl)


#endregion

#region ---- ROUTE PLANNER ----

func _toggle_planner() -> void:
	if planner_visible:
		_close_planner()
	else:
		_open_planner()


func _open_planner() -> void:
	planner_visible = true
	plan_route_button.text = "Close Planner"

	# Initialize virtual state from current game state.
	virtual_location = current_location
	virtual_gold = player_gold
	virtual_inventory = inventory.duplicate()

	# Create a new plan if none exists.
	if current_plan == null:
		current_plan = RoutePlan.new()

	# Hide everything except the planner for full-screen mode.
	timer_section.visible = false
	left_panel.visible = false
	right_column.visible = false
	actions_label.visible = false
	button_row.visible = false
	combat_section.visible = false
	combat_log_panel.visible = false
	location_label.visible = false
	spacer3.visible = false
	status_label.visible = false
	planner_overlay.visible = true

	_refresh_planner_available_actions()
	_rebuild_planned_steps_ui()


func _close_planner() -> void:
	planner_visible = false
	plan_route_button.text = "Plan Route"
	planner_overlay.visible = false

	# Restore timer, side panels, and spacers.
	timer_section.visible = true
	left_panel.visible = true
	right_column.visible = true
	location_label.visible = true
	spacer3.visible = true
	status_label.visible = true

	# Close load popup if open.
	if load_popup and is_instance_valid(load_popup):
		load_popup.queue_free()
		load_popup = null

	# Restore normal game UI.
	_show_location(current_location)


## Travel graph: maps each location to its direct travel connections.
## Each entry is { destination: Location, label: String, duration: float }.
func _get_travel_graph() -> Dictionary:
	return {
		Location.OUTSIDE: [
			{ "label": "Head into Town", "duration": 1.0, "destination": Location.TOWN },
			{ "label": "Head into the Dungeon", "duration": 1.0, "destination": Location.DUNGEON_ENTRANCE },
		],
		Location.TOWN: [
			{ "label": "Enter the Dungeon", "duration": 1.0, "destination": Location.DUNGEON_ENTRANCE },
			{ "label": "Visit the Healer", "duration": 1.0, "destination": Location.TOWN_HEALER },
			{ "label": "Visit the Blacksmith", "duration": 1.0, "destination": Location.TOWN_BLACKSMITH },
			{ "label": "Visit General Goods", "duration": 1.0, "destination": Location.TOWN_GENERAL_GOODS },
		],
		Location.TOWN_HEALER: [
			{ "label": "Back to Town", "duration": 1.0, "destination": Location.TOWN },
		],
		Location.TOWN_BLACKSMITH: [
			{ "label": "Back to Town", "duration": 1.0, "destination": Location.TOWN },
		],
		Location.TOWN_GENERAL_GOODS: [
			{ "label": "Back to Town", "duration": 1.0, "destination": Location.TOWN },
		],
		Location.DUNGEON_ENTRANCE: [
			{ "label": "Back to Town", "duration": 1.0, "destination": Location.TOWN },
		],
	}


## BFS to find the shortest travel path from one location to another.
## Returns an array of travel step dictionaries (empty if already there).
func _find_travel_path(from_loc: int, to_loc: int) -> Array:
	if from_loc == to_loc:
		return []

	var graph := _get_travel_graph()
	var queue: Array = [[from_loc]]  # Queue of paths (each path is array of locations).
	var visited := { from_loc: true }

	while queue.size() > 0:
		var path: Array = queue.pop_front()
		var current: int = path.back()
		var neighbors: Array = graph.get(current, [])

		for edge in neighbors:
			var next_loc: int = edge["destination"]
			if next_loc in visited:
				continue
			var new_path := path.duplicate()
			new_path.append(next_loc)
			if next_loc == to_loc:
				# Convert path to travel steps.
				var steps: Array = []
				for i in range(1, new_path.size()):
					var prev: int = new_path[i - 1]
					var dest: int = new_path[i]
					# Find the matching edge.
					for e in graph.get(prev, []):
						if e["destination"] == dest:
							steps.append({
								"label": e["label"], "duration": e["duration"],
								"destination": dest, "type": "travel",
								"estimated_time": e["duration"],
							})
							break
				return steps
			visited[next_loc] = true
			queue.append(new_path)

	return []  # No path found.


func _refresh_planner_available_actions() -> void:
	for child in available_actions_vbox.get_children():
		child.queue_free()

	# Build a virtual version of location data for the current virtual location.
	var data: Dictionary = _get_planner_location_data(virtual_location as Location)
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
			btn.pressed.connect(func() -> void: _planner_add_step(act))

		available_actions_vbox.add_child(btn)


## Get location data for the planner — shows ALL possible actions as enabled,
## even if the player can't currently afford them or doesn't meet the criteria.
## Actions that might not be available at runtime get a "condition" so the
## executor can skip them if conditions aren't met.
func _get_planner_location_data(location: Location) -> Dictionary:
	match location:
		Location.OUTSIDE:
			return {
				"name": "Outside",
				"actions": [
					{ "label": "Head into Town", "duration": 1.0, "destination": Location.TOWN },
					{ "label": "Head into the Dungeon", "duration": 1.0, "destination": Location.DUNGEON_ENTRANCE },
				],
			}

		Location.TOWN:
			return {
				"name": "Town",
				"actions": [
					{ "label": "Enter the Dungeon", "duration": 1.0, "destination": Location.DUNGEON_ENTRANCE },
					{ "label": "Visit the Healer", "duration": 1.0, "destination": Location.TOWN_HEALER },
					{ "label": "Visit the Blacksmith", "duration": 1.0, "destination": Location.TOWN_BLACKSMITH },
					{ "label": "Visit General Goods", "duration": 1.0, "destination": Location.TOWN_GENERAL_GOODS },
				],
			}

		Location.TOWN_HEALER:
			return {
				"name": "Town — Healer",
				"actions": [
					{
						"label": "Heal to full HP — 1 gold", "duration": 2.0, "destination": -1,
						"heal": true, "gold_cost": 1,
						"condition": { "type": "needs_heal_and_gold", "on_fail": "skip" },
					},
					{ "label": "Back to Town", "duration": 1.0, "destination": Location.TOWN },
				],
			}

		Location.TOWN_BLACKSMITH:
			var actions: Array = []
			for item_id in blacksmith_stock:
				var item: Dictionary = item_catalogue[item_id]
				actions.append({
					"label": "Buy %s — %d gold" % [item["name"], item["cost"]],
					"duration": 2.0, "destination": -1,
					"shop_buy": true, "item_id": item_id, "gold_cost": item["cost"],
					"condition": { "type": "can_buy_item", "item_id": item_id, "on_fail": "skip" },
				})
			actions.append({ "label": "Back to Town", "duration": 1.0, "destination": Location.TOWN })
			return { "name": "Town — Blacksmith", "actions": actions }

		Location.TOWN_GENERAL_GOODS:
			var actions: Array = []
			for item_id in general_goods_stock:
				var item: Dictionary = item_catalogue[item_id]
				actions.append({
					"label": "Buy %s — %d gold" % [item["name"], item["cost"]],
					"duration": 2.0, "destination": -1,
					"shop_buy": true, "item_id": item_id, "gold_cost": item["cost"],
					"condition": { "type": "can_buy_item", "item_id": item_id, "on_fail": "skip" },
				})
			actions.append({ "label": "Back to Town", "duration": 1.0, "destination": Location.TOWN })
			return { "name": "Town — General Goods", "actions": actions }

		Location.DUNGEON_ENTRANCE:
			var slime_action := {
				"enemy_name": "Slime", "enemy_hp": 3,
				"enemy_attack_speed": 2.0, "enemy_damage": 1,
				"reward_gold": 2, "reward_xp": 1,
				"slime_fight": true,
			}
			var actions: Array = []
			actions.append({
				"label": "Fight a Slime",
				"duration": 0.0, "destination": -1,
				"combat_start": true, "auto_fight_count": 0,
				"condition": { "type": "slimes_remaining", "on_fail": "skip" },
			}.merged(slime_action))
			actions.append({
				"label": "Fight All Slimes",
				"duration": 0.0, "destination": -1,
				"combat_start": true, "auto_fight_count": 9,
				"condition": { "type": "slimes_remaining", "on_fail": "skip" },
			}.merged(slime_action))
			actions.append({ "label": "Back to Town", "duration": 1.0, "destination": Location.TOWN })
			return { "name": "Dungeon Entrance", "actions": actions }

	return { "name": "???", "actions": [] }


func _planner_add_step(action: Dictionary) -> void:
	if current_plan == null:
		current_plan = RoutePlan.new()

	# Build step data.
	var step: Dictionary = action.duplicate()
	var is_combat: bool = action.get("combat_start", false)

	if is_combat:
		step["type"] = "combat_all" if action.get("auto_fight_count", 0) > 0 else "combat"
		step["estimated_time"] = 8.0  # Rough estimate per slime fight.
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

	# Update virtual state.
	if action.get("gold_cost", 0) > 0:
		virtual_gold -= action["gold_cost"]
	if action.get("shop_buy", false):
		var item_id: String = action["item_id"]
		virtual_inventory[item_id] = virtual_inventory.get(item_id, 0) + 1
	if action.get("destination", -1) != -1:
		virtual_location = action["destination"]

	_refresh_planner_available_actions()
	_rebuild_planned_steps_ui()


## Validate the plan step sequence. Returns a dictionary mapping step index
## to an error message. Empty dict = valid plan.
func _validate_plan() -> Dictionary:
	var errors: Dictionary = {}
	if current_plan == null or current_plan.steps.is_empty():
		return errors

	var graph := _get_travel_graph()
	var sim_location: int = current_location  # Simulate from the player's starting location.

	for i in current_plan.steps.size():
		var step: Dictionary = current_plan.steps[i]

		# Determine what location this step requires the player to be at.
		var step_required_loc := _get_step_required_location(step)

		if step_required_loc != -1 and step_required_loc != sim_location:
			# Step requires a specific location and we're not there.
			var loc_name: String = _get_planner_location_data(step_required_loc as Location).get("name", "???")
			var cur_name: String = _get_planner_location_data(sim_location as Location).get("name", "???")
			errors[i] = "Requires %s, but you'd be at %s" % [loc_name, cur_name]
		elif step_required_loc == -1 and step.get("destination", -1) != -1:
			# Travel step — verify the current simulated location has this edge.
			var dest: int = step["destination"]
			var label: String = step.get("label", "")
			var edge_found := false
			var edges: Array = graph.get(sim_location, [])
			for edge in edges:
				if edge["destination"] == dest and edge["label"] == label:
					edge_found = true
					break
			if not edge_found:
				var cur_name: String = _get_planner_location_data(sim_location as Location).get("name", "???")
				errors[i] = "Can't do '%s' from %s" % [label, cur_name]

		# Advance simulated location if this step moves us.
		var dest: int = step.get("destination", -1)
		if dest != -1:
			sim_location = dest

	return errors


## Determine which location a step requires the player to be at.
## Returns the Location enum value, or -1 if the step works anywhere.
func _get_step_required_location(step: Dictionary) -> int:
	# Combat steps require being at the dungeon.
	if step.get("combat_start", false) or step.get("slime_fight", false):
		return Location.DUNGEON_ENTRANCE

	# Heal requires being at healer.
	if step.get("heal", false):
		return Location.TOWN_HEALER

	# Shop buy — check which shop has this item.
	if step.get("shop_buy", false):
		var item_id: String = step.get("item_id", "")
		if item_id in blacksmith_stock:
			return Location.TOWN_BLACKSMITH
		if item_id in general_goods_stock:
			return Location.TOWN_GENERAL_GOODS

	# Travel steps — multiple locations may offer the same travel action
	# (e.g. "Back to Town"), so we return -1 here and let _validate_plan
	# check if the current simulated location has this travel edge.
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

	# Validate the plan.
	var errors := _validate_plan()
	var has_errors := not errors.is_empty()

	for i in current_plan.steps.size():
		var step: Dictionary = current_plan.steps[i]
		var step_container := VBoxContainer.new()
		step_container.add_theme_constant_override("separation", 2)

		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)

		# Step number.
		var num_lbl := Label.new()
		num_lbl.text = "%d." % (i + 1)
		num_lbl.custom_minimum_size = Vector2(24, 0)
		num_lbl.modulate = Color(0.6, 0.65, 0.75)
		num_lbl.add_theme_font_size_override("font_size", 13)
		row.add_child(num_lbl)

		# Step label.
		var step_lbl := Label.new()
		step_lbl.text = step.get("label", "???")
		step_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		step_lbl.add_theme_font_size_override("font_size", 13)
		step_lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		row.add_child(step_lbl)

		# Time estimate.
		var time_lbl := Label.new()
		var est: float = step.get("estimated_time", 0.0)
		time_lbl.text = "~%ds" % int(est) if est > 0 else ""
		time_lbl.modulate = Color(0.7, 0.7, 0.75)
		time_lbl.add_theme_font_size_override("font_size", 12)
		row.add_child(time_lbl)

		# Move up button (disabled for first item).
		var up_btn := Button.new()
		up_btn.text = "▲"
		up_btn.custom_minimum_size = Vector2(28, 24)
		if i > 0:
			var idx: int = i
			up_btn.pressed.connect(func() -> void: _planner_move_step(idx, idx - 1))
		else:
			up_btn.disabled = true
		row.add_child(up_btn)

		# Move down button (disabled for last item).
		var down_btn := Button.new()
		down_btn.text = "▼"
		down_btn.custom_minimum_size = Vector2(28, 24)
		if i < current_plan.steps.size() - 1:
			var idx: int = i
			down_btn.pressed.connect(func() -> void: _planner_move_step(idx, idx + 1))
		else:
			down_btn.disabled = true
		row.add_child(down_btn)

		# Remove button.
		var remove_btn := Button.new()
		remove_btn.text = "✕"
		remove_btn.custom_minimum_size = Vector2(28, 24)
		var idx: int = i
		remove_btn.pressed.connect(func() -> void: _planner_remove_step(idx))
		row.add_child(remove_btn)

		step_container.add_child(row)

		# Show error if this step has a validation error.
		if i in errors:
			# Tint the step number and label red.
			num_lbl.modulate = Color(1.0, 0.35, 0.35)
			step_lbl.modulate = Color(1.0, 0.35, 0.35)

			var err_lbl := Label.new()
			err_lbl.text = "⚠ %s" % errors[i]
			err_lbl.modulate = Color(1.0, 0.5, 0.3, 0.9)
			err_lbl.add_theme_font_size_override("font_size", 11)
			err_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			step_container.add_child(err_lbl)

		planned_steps_list.add_child(step_container)

	# Update estimated time.
	var total_est := current_plan.get_estimated_time()
	estimated_time_label.text = "~%ds / %ds" % [int(total_est), int(LOOP_DURATION)]

	# Disable Start Run and Save if there are errors.
	start_run_button.disabled = has_errors
	save_plan_button.disabled = has_errors
	if has_errors:
		start_run_button.tooltip_text = "Fix route errors before running"
		save_plan_button.tooltip_text = "Fix route errors before saving"
	else:
		start_run_button.tooltip_text = ""
		save_plan_button.tooltip_text = ""


func _planner_move_step(from_idx: int, to_idx: int) -> void:
	current_plan.move_step(from_idx, to_idx)
	_recompute_virtual_state()
	_refresh_planner_available_actions()
	_rebuild_planned_steps_ui()


func _planner_remove_step(index: int) -> void:
	current_plan.remove_step(index)
	_recompute_virtual_state()
	_refresh_planner_available_actions()
	_rebuild_planned_steps_ui()


## Replay all plan steps to recompute virtual location/gold/inventory.
func _recompute_virtual_state() -> void:
	virtual_location = current_location
	virtual_gold = player_gold
	virtual_inventory = inventory.duplicate()

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


func _on_clear_plan() -> void:
	if current_plan:
		current_plan.clear()
	_recompute_virtual_state()
	_refresh_planner_available_actions()
	_rebuild_planned_steps_ui()


func _on_start_run() -> void:
	if current_plan == null or current_plan.steps.is_empty():
		status_label.text = "No steps in plan!"
		return

	_close_planner()

	# Create executor and start the plan.
	route_executor = RouteExecutor.new(self)
	route_executor.step_started.connect(_on_executor_step_started)
	route_executor.plan_completed.connect(_on_executor_plan_completed)
	route_executor.plan_failed.connect(_on_executor_plan_failed)
	route_executor.execution_paused.connect(_on_executor_paused)

	plan_route_button.text = "Take Control"
	plan_route_button.pressed.disconnect(_toggle_planner)
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
	# Disconnect all dynamic connections.
	if plan_route_button.pressed.is_connected(_on_take_control):
		plan_route_button.pressed.disconnect(_on_take_control)
	if plan_route_button.pressed.is_connected(_on_resume_plan):
		plan_route_button.pressed.disconnect(_on_resume_plan)
	if not plan_route_button.pressed.is_connected(_toggle_planner):
		plan_route_button.pressed.connect(_toggle_planner)
	route_executor = null


func _on_save_plan() -> void:
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


func _on_load_plan() -> void:
	var plans := RoutePlan.list_saved_plans()
	if plans.is_empty():
		status_label.text = "No saved routes found."
		return

	# Show saved routes in the available actions area.
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
			_on_load_plan()  # Refresh the list.
		)
		row.add_child(del_btn)

		available_actions_vbox.add_child(row)

	# Add a "Back" button to return to available actions.
	var back_btn := Button.new()
	back_btn.text = "Back"
	back_btn.custom_minimum_size = Vector2(100, 32)
	back_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	back_btn.pressed.connect(_refresh_planner_available_actions)
	available_actions_vbox.add_child(back_btn)


func _load_plan_by_name(filename: String) -> void:
	var loaded := RoutePlan.load_plan(filename)
	if loaded == null:
		status_label.text = "Failed to load route."
		return

	current_plan = loaded
	plan_name_edit.text = current_plan.plan_name
	_recompute_virtual_state()
	_refresh_planner_available_actions()
	_rebuild_planned_steps_ui()
	status_label.text = "Route '%s' loaded!" % current_plan.plan_name
