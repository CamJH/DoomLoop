extends MarginContainer

## Total loop time in seconds (10 minutes).
const LOOP_DURATION := 600.0

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

# ---- Node references ----
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
# Info panel
@onready var info_content: VBoxContainer = %InfoContent


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


# ---- Combat enter / exit ----

func _enter_combat(action: Dictionary) -> void:
	in_combat = true
	fleeing = false
	drinking_potion = false

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
	_update_combat_ui()
	_add_combat_log("A %s appears!" % enemy_name)


func _enemy_killed() -> void:
	in_combat = false
	fleeing = false
	drinking_potion = false
	combat_section.visible = false

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
	status_label.text = "%s defeated! (%s)" % [enemy_name, reward_text]
	_show_location(current_location)


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
	combat_section.visible = false
	if flee_progress_bar:
		flee_progress_bar.queue_free()
		flee_progress_bar = null
	status_label.text = "Escaped from %s!" % enemy_name
	_show_location(current_location)


# ---- Equipment stats ----

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


# ---- Dynamic location data ----

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


func _get_location_data(location: Location) -> Dictionary:
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
				actions.append({
					"label": "Fight a Slime (%d/%d)" % [slimes_defeated, MAX_SLIMES],
					"duration": 0.0, "destination": -1,
					"combat_start": true,
					"enemy_name": "Slime", "enemy_hp": 3,
					"enemy_attack_speed": 2.0, "enemy_damage": 1,
					"reward_gold": 2, "reward_xp": 1,
					"slime_fight": true,
				})
			else:
				actions.append({
					"label": "All slimes defeated!", "duration": 0.0, "destination": -1,
					"disabled": true,
				})
			actions.append({ "label": "Back to Town", "duration": 1.0, "destination": Location.TOWN })
			return { "name": "Dungeon Entrance", "actions": actions }

	return { "name": "???", "actions": [] }


# ---- Location / UI helpers ----

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
			btn.pressed.connect(func() -> void: _enter_combat(act))
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
		# Add an invisible spacer so this row matches the width of shop rows.
		var spacer := Control.new()
		spacer.custom_minimum_size = Vector2(40, 0)
		row.add_child(spacer)

	return row


## Shows item info in the right-side info panel.
func _show_item_info(item_id: String) -> void:
	var item: Dictionary = item_catalogue.get(item_id, {})
	if item.is_empty():
		return

	_clear_info_panel()

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


func _show_location(location: Location) -> void:
	current_location = location
	var data: Dictionary = _get_location_data(location)

	location_label.text = data["name"]
	_cancel_active_action()
	_clear_info_panel()

	# Clear old slots.
	for child in button_row.get_children():
		child.queue_free()

	var actions: Array = data["actions"]

	# Check if any action in this location has an item (shop), so non-shop
	# buttons can add a spacer to match the [?] button width.
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

	if current_action_destination != -1:
		_show_location(current_action_destination as Location)
	else:
		_show_location(current_location)


func _player_died() -> void:
	in_combat = false
	fleeing = false
	drinking_potion = false
	action_in_progress = false
	combat_section.visible = false
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


func _end_loop() -> void:
	in_combat = false
	fleeing = false
	drinking_potion = false
	action_in_progress = false
	combat_section.visible = false
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
	enemy_hp_label.text = "%s  HP: %d / %d" % [enemy_name, enemy_hp, enemy_max_hp]


func _add_combat_log(msg: String) -> void:
	combat_log_lines.append(msg)
	if combat_log_lines.size() > MAX_COMBAT_LOG_LINES:
		combat_log_lines.remove_at(0)
	combat_log_label.text = "\n".join(combat_log_lines)


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
		var lbl := Label.new()
		if item["max"] == 1:
			lbl.text = item["name"]
		else:
			lbl.text = "%s  x%d" % [item["name"], count]
		lbl.tooltip_text = item.get("description", "")
		lbl.mouse_filter = Control.MOUSE_FILTER_STOP
		inventory_list.add_child(lbl)

	if not has_items:
		var empty_lbl := Label.new()
		empty_lbl.text = "(empty)"
		empty_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty_lbl.modulate = Color(1, 1, 1, 0.5)
		inventory_list.add_child(empty_lbl)
