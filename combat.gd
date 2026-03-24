class_name CombatManager
extends RefCounted

## All combat logic. Gets a `game` reference in the constructor.

const Location = LocationManager.Location

var game  ## Reference to game.gd.

# ---- Combat state ----
var in_combat := false
var fleeing := false
var drinking_potion := false
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
const HP_FLASH_THRESHOLD := 0.3
const HP_FLASH_SPEED := 4.0
var hp_flash_timer := 0.0

# ---- Flee bar ----
var flee_progress_bar: ColorRect = null

# ---- Auto-fight state ----
var auto_fight_remaining := 0
var last_combat_action: Dictionary = {}

# ---- Auto-fight UI (created dynamically) ----
var auto_fight_label: Label = null
var stop_after_fight_button: Button = null

# ---- Node references (set by game._ready) ----
var combat_section: PanelContainer
var enemy_hp_label: Label
var enemy_attack_bar: ProgressBar
var player_attack_bar: ProgressBar
var player_attack_label: Label
var flee_button: Button
var combat_log_label: Label
var combat_log_scroll: ScrollContainer
var combat_log_panel: PanelContainer
var hp_label: Label
var status_label: Label
var actions_label: Label
var button_row: VBoxContainer
var auto_flee_spinbox: SpinBox

# ---- Temporary action state used during flee ----
var current_action_duration := 0.0
var current_action_elapsed := 0.0


func _init(game_ref) -> void:
	game = game_ref


func enter_combat(action: Dictionary) -> void:
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
	if flee_progress_bar:
		flee_progress_bar.queue_free()
		flee_progress_bar = null
	player_attack_bar.value = 0.0
	enemy_attack_bar.value = 0.0

	_build_combat_footer()
	update_combat_ui()

	game.ui_helpers.show_enemy_info(action)
	combat_log_panel.visible = true
	add_combat_log("A %s appears!" % enemy_name)


func process_combat(delta: float) -> void:
	var player: PlayerData = game.player

	# If fleeing, tick the flee bar — enemy still attacks.
	if fleeing:
		current_action_elapsed += delta
		if flee_progress_bar:
			game.ui_helpers.set_bar_progress(flee_progress_bar, current_action_elapsed / current_action_duration)
		if current_action_elapsed >= current_action_duration:
			_finish_flee()
			return

	# ---- Enemy attack bar ----
	enemy_attack_timer += delta
	if enemy_attack_timer >= enemy_attack_speed:
		enemy_attack_timer -= enemy_attack_speed
		var actual_dmg := player.get_damage_after_reduction(enemy_damage)
		player.hp = maxi(player.hp - actual_dmg, 0)
		game.ui_helpers.update_player_stats_ui()
		if actual_dmg < enemy_damage:
			add_combat_log("%s hits you for %d! (%d blocked)" % [enemy_name, actual_dmg, enemy_damage - actual_dmg])
		else:
			add_combat_log("%s hits you for %d!" % [enemy_name, actual_dmg])
		if player.hp <= 0:
			game.player_died()
			return
	enemy_attack_bar.value = (enemy_attack_timer / enemy_attack_speed) * 100.0

	# ---- Auto-flee check ----
	if not fleeing and not drinking_potion:
		var auto_flee_pct := auto_flee_spinbox.value
		if auto_flee_pct > 0.0:
			var hp_pct := (float(player.hp) / float(player.max_hp)) * 100.0
			if hp_pct <= auto_flee_pct:
				on_flee_pressed()

	# ---- Potion drinking (pauses player attack) ----
	if drinking_potion:
		potion_drink_timer += delta
		player_attack_bar.value = (potion_drink_timer / POTION_DRINK_DURATION) * 100.0
		if potion_drink_timer >= POTION_DRINK_DURATION:
			_finish_drinking_potion()
		if drinking_potion:
			return

	# ---- Player attack bar (only ticks when not fleeing) ----
	if not fleeing:
		player_attack_timer += delta
		var atk_speed := player.get_attack_speed()
		if player_attack_timer >= atk_speed:
			player_attack_timer -= atk_speed
			var dmg := player.get_attack_damage()
			enemy_hp = maxi(enemy_hp - dmg, 0)
			update_combat_ui()
			add_combat_log("You hit %s for %d!" % [enemy_name, dmg])
			if enemy_hp <= 0:
				_enemy_killed()
				return
			_check_auto_potion()
			if drinking_potion:
				player_attack_bar.value = 0.0
				return
		player_attack_bar.value = (player_attack_timer / atk_speed) * 100.0


func _enemy_killed() -> void:
	var player: PlayerData = game.player
	player.gold += combat_reward_gold
	player.xp += combat_reward_xp

	var reward_text := ""
	if combat_reward_gold > 0 or combat_reward_xp > 0:
		reward_text = "+%d gold, +%d xp" % [combat_reward_gold, combat_reward_xp]

	# ---- Jail Guard: defeating the guard lets you escape ----
	if last_combat_action.get("jail_guard_fight", false):
		player.inventory["cudgel"] = player.inventory.get("cudgel", 0) + 1
		player.inventory["jail_keys"] = player.inventory.get("jail_keys", 0) + 1
		player.recalculate_equipment()
		game.ui_helpers.update_player_stats_ui()
		game.ui_helpers.update_inventory_ui()
		status_label.text = "You overpower the guard and take his cudgel and keys.\nThe cell door swings open. Outside is a small room with a desk and a locked chest."
		in_combat = false
		fleeing = false
		drinking_potion = false
		auto_fight_remaining = 0
		combat_section.visible = false
		combat_log_panel.visible = false
		game.show_location(Location.JAIL_GUARDROOM)
		game.combat_completed.emit(enemy_name, true)
		return

	if combat_is_slime:
		player.slimes_defeated += 1
		if player.slimes_defeated >= player.MAX_SLIMES and not player.all_slimes_cleared:
			player.all_slimes_cleared = true
			player.gold += 20
			player.xp += 10
			reward_text += " — All slimes cleared! Bonus: +20 gold, +10 xp!"

	game.ui_helpers.update_player_stats_ui()
	game.ui_helpers.update_inventory_ui()
	status_label.text = "%s defeated! (%s)" % [enemy_name, reward_text]

	# Auto-fight: re-enter combat if remaining count > 0 and enemies still exist.
	if auto_fight_remaining > 0 and not last_combat_action.is_empty():
		var can_auto_fight := true
		if last_combat_action.get("slime_fight", false) and player.all_slimes_cleared:
			can_auto_fight = false
		if can_auto_fight:
			auto_fight_remaining -= 1
			enter_combat(last_combat_action)
			return

	# Exit combat.
	in_combat = false
	fleeing = false
	drinking_potion = false
	auto_fight_remaining = 0
	combat_section.visible = false
	combat_log_panel.visible = false
	game.show_location(game.current_location)
	game.combat_completed.emit(enemy_name, true)


func on_flee_pressed() -> void:
	if fleeing:
		return
	fleeing = true

	flee_button.visible = false
	flee_progress_bar = game.ui_helpers.create_bar_overlay("Fleeing...", Vector2(200, 40))
	flee_progress_bar.custom_minimum_size = Vector2(200, 40)
	flee_progress_bar.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var parent := flee_button.get_parent()
	var idx := flee_button.get_index()
	parent.add_child(flee_progress_bar)
	parent.move_child(flee_progress_bar, idx + 1)

	current_action_duration = 1.0
	current_action_elapsed = 0.0
	add_combat_log("You attempt to flee!")


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
	game.show_location(game.current_location)
	game.combat_completed.emit(enemy_name, true)


func _build_combat_footer() -> void:
	if stop_after_fight_button and is_instance_valid(stop_after_fight_button):
		stop_after_fight_button.get_parent().remove_child(stop_after_fight_button)
		stop_after_fight_button.free()
	stop_after_fight_button = null
	if auto_fight_label and is_instance_valid(auto_fight_label):
		auto_fight_label.get_parent().remove_child(auto_fight_label)
		auto_fight_label.free()
	auto_fight_label = null

	var combat_vbox: VBoxContainer = combat_section.get_child(0)

	if auto_fight_remaining > 0:
		auto_fight_label = Label.new()
		auto_fight_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		auto_fight_label.modulate = Color(0.7, 0.85, 1.0)
		auto_fight_label.add_theme_font_size_override("font_size", 13)
		_update_auto_fight_label()
		combat_vbox.add_child(auto_fight_label)
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


func _check_auto_potion() -> void:
	var player: PlayerData = game.player
	var hp_ratio := float(player.hp) / float(player.max_hp)
	if hp_ratio > POTION_HP_THRESHOLD:
		return
	var potions: int = player.inventory.get("health_potion", 0)
	if potions <= 0:
		return
	drinking_potion = true
	potion_drink_timer = 0.0
	player_attack_timer = 0.0
	player_attack_label.text = "Drinking Health Potion..."
	add_combat_log("You drink a Health Potion...")


func _finish_drinking_potion() -> void:
	var player: PlayerData = game.player
	drinking_potion = false
	potion_drink_timer = 0.0
	player_attack_label.text = "Your Attack"
	player.inventory["health_potion"] = player.inventory.get("health_potion", 0) - 1
	if player.inventory["health_potion"] <= 0:
		player.inventory.erase("health_potion")
	var heal_amount := 5
	var old_hp := player.hp
	player.hp = mini(player.hp + heal_amount, player.max_hp)
	var healed := player.hp - old_hp
	game.ui_helpers.update_player_stats_ui()
	game.ui_helpers.update_inventory_ui()
	add_combat_log("Healed for %d HP! (%d/%d)" % [healed, player.hp, player.max_hp])


func process_hp_flash(delta: float) -> void:
	var player: PlayerData = game.player
	var hp_ratio := float(player.hp) / float(player.max_hp)
	if hp_ratio <= HP_FLASH_THRESHOLD and player.hp > 0:
		hp_flash_timer += delta
		var flash := (sin(hp_flash_timer * HP_FLASH_SPEED * TAU) + 1.0) / 2.0
		hp_label.modulate = Color(1.0, 1.0 - flash * 0.7, 1.0 - flash * 0.7)
	else:
		hp_flash_timer = 0.0
		hp_label.modulate = Color.WHITE


func update_combat_ui() -> void:
	var player: PlayerData = game.player
	var count_text := ""
	if combat_is_slime:
		count_text = "  (%d/%d)" % [player.slimes_defeated, player.MAX_SLIMES]
	enemy_hp_label.text = "%s  HP: %d / %d%s" % [enemy_name, enemy_hp, enemy_max_hp, count_text]


func add_combat_log(msg: String) -> void:
	combat_log_lines.append(msg)
	if combat_log_lines.size() > MAX_COMBAT_LOG_LINES:
		combat_log_lines.remove_at(0)
	combat_log_label.text = "\n".join(combat_log_lines)
	# Auto-scroll to bottom (deferred so layout updates first).
	var tree: SceneTree = game.get_tree()
	if tree:
		await tree.process_frame
		if is_instance_valid(combat_log_scroll):
			combat_log_scroll.scroll_vertical = int(combat_log_scroll.get_v_scroll_bar().max_value)
