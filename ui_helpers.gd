class_name UIHelpers
extends RefCounted

## Shared UI utilities: bar shader, action slots, info panel, modals, stats UI.

const Location = LocationManager.Location

var game  ## Reference to game.gd.

# ---- Bar shader (created once, reused) ----
var _bar_shader: Shader = null

# ---- Modal overlay ----
var _modal_overlay: ColorRect = null

# ---- Node references (set by game._ready) ----
var info_content: VBoxContainer
var info_vbox: VBoxContainer
var info_title: Label
var info_sep: HSeparator
var hp_label: Label
var xp_label: Label
var gold_label: Label
var inventory_list: VBoxContainer


func _init(game_ref) -> void:
	game = game_ref


func get_bar_shader() -> Shader:
	if _bar_shader != null:
		return _bar_shader
	_bar_shader = Shader.new()
	_bar_shader.code = """shader_type canvas_item;
render_mode unshaded;

uniform float progress    : hint_range(0.0, 1.0) = 0.0;
uniform vec2  rect_size   = vec2(300.0, 50.0);
uniform float corner_px   = 10.0;
uniform float border_px   = 2.0;
uniform vec4  bg_color    : source_color = vec4(0.12, 0.12, 0.18, 1.0);
uniform vec4  fill_color  : source_color = vec4(0.2, 0.3, 0.5, 0.7);
uniform vec4  border_color: source_color = vec4(0.3, 0.35, 0.5, 0.8);
uniform vec4  hover_tint  : source_color = vec4(0.0, 0.0, 0.0, 0.0);

float rounded_rect_sdf(vec2 p, vec2 half_size, float r) {
	vec2 q = abs(p) - half_size + r;
	return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
}

void fragment() {
	vec2 pos = UV * rect_size;
	vec2 center = rect_size * 0.5;
	float r = min(corner_px, min(rect_size.x, rect_size.y) * 0.5);
	float d = rounded_rect_sdf(pos - center, center, r);
	float aa = 1.0;
	float edge = smoothstep(aa, -aa, d);
	if (edge < 0.001) { discard; }
	vec4 c = (UV.x <= progress) ? fill_color : bg_color;
	c.rgb += hover_tint.rgb * hover_tint.a;
	float border_edge = smoothstep(-border_px + aa, -border_px - aa, d);
	c = mix(border_color, c, border_edge);
	COLOR = vec4(c.rgb, c.a * edge);
}
"""
	return _bar_shader


func create_bar_overlay(text: String, size: Vector2) -> ColorRect:
	var bar := ColorRect.new()
	bar.color = Color(1, 1, 1, 1)
	bar.custom_minimum_size = size
	bar.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	bar.mouse_filter = Control.MOUSE_FILTER_STOP

	var mat := ShaderMaterial.new()
	mat.shader = get_bar_shader()
	mat.set_shader_parameter("progress", 0.0)
	mat.set_shader_parameter("rect_size", size)
	mat.set_shader_parameter("corner_px", 10.0)
	mat.set_shader_parameter("border_px", 2.0)
	mat.set_shader_parameter("bg_color", Color(0.12, 0.12, 0.18, 1.0))
	mat.set_shader_parameter("fill_color", Color(0.2, 0.3, 0.5, 0.7))
	mat.set_shader_parameter("border_color", Color(0.3, 0.35, 0.5, 0.8))
	mat.set_shader_parameter("hover_tint", Color(0.0, 0.0, 0.0, 0.0))
	bar.material = mat

	bar.mouse_entered.connect(func() -> void:
		(bar.material as ShaderMaterial).set_shader_parameter("hover_tint", Color(0.06, 0.06, 0.08, 1.0))
	)
	bar.mouse_exited.connect(func() -> void:
		(bar.material as ShaderMaterial).set_shader_parameter("hover_tint", Color(0.0, 0.0, 0.0, 0.0))
	)

	var lbl := Label.new()
	lbl.text = text
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_child(lbl)

	var time_lbl := Label.new()
	time_lbl.text = ""
	time_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	time_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	time_lbl.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	time_lbl.add_theme_font_size_override("font_size", 11)
	time_lbl.modulate = Color(0.7, 0.75, 0.85, 0.9)
	time_lbl.offset_right = -10
	time_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_child(time_lbl)

	return bar


func set_bar_progress(bar: ColorRect, progress: float) -> void:
	if bar and bar.material:
		(bar.material as ShaderMaterial).set_shader_parameter("progress", clampf(progress, 0.0, 1.0))


func create_action_slot(action: Dictionary) -> Control:
	var player: PlayerData = game.player
	var is_disabled: bool = action.get("disabled", false)
	var is_combat: bool = action.get("combat_start", false)
	var has_item: bool = action.has("item_id")
	var is_persistent: bool = action.get("persistent_action", false)
	var aq: ActionQueue = game.action_queue

	var btn := Button.new()
	if is_disabled:
		btn.text = action["label"]
		btn.disabled = true
		btn.tooltip_text = action.get("disabled_reason", "")
	elif is_combat:
		btn.text = action["label"]
	else:
		var dur: float = action["duration"]
		var saved: float = aq.action_progress.get(action["action_id"], 0.0)
		var remaining_dur := maxf(dur - saved, 0.0)
		var time_str: String
		if remaining_dur >= 60.0:
			time_str = "%dm" % int(remaining_dur / 60.0)
		else:
			time_str = "%ss" % int(remaining_dur)
		if saved > 0.0:
			btn.text = "%s (%s left)" % [action["label"], time_str]
		else:
			btn.text = "%s (%s)" % [action["label"], time_str]
	btn.custom_minimum_size = Vector2(300, 50)
	btn.set_meta("action_id", action["action_id"])

	if is_persistent:
		var stylebox := StyleBoxFlat.new()
		stylebox.bg_color = Color(0.15, 0.12, 0.05, 1.0)
		stylebox.border_color = Color(0.85, 0.65, 0.15, 0.8)
		stylebox.set_border_width_all(2)
		stylebox.set_corner_radius_all(8)
		stylebox.set_content_margin_all(8)
		btn.add_theme_stylebox_override("normal", stylebox)
		var hover_box := stylebox.duplicate()
		hover_box.bg_color = Color(0.2, 0.16, 0.06, 1.0)
		btn.add_theme_stylebox_override("hover", hover_box)
		btn.add_theme_color_override("font_color", Color(0.95, 0.8, 0.3))
		btn.add_theme_color_override("font_hover_color", Color(1.0, 0.9, 0.4))
		btn.tooltip_text = "Persistent — progress is saved between loops"

	var bar := create_bar_overlay(action["label"] + "...", Vector2(300, 50))

	if is_persistent:
		var mat: ShaderMaterial = bar.material as ShaderMaterial
		mat.set_shader_parameter("bg_color", Color(0.12, 0.1, 0.04, 1.0))
		mat.set_shader_parameter("fill_color", Color(0.55, 0.42, 0.1, 0.8))
		mat.set_shader_parameter("border_color", Color(0.85, 0.65, 0.15, 0.6))
		for conn in bar.mouse_entered.get_connections():
			bar.mouse_entered.disconnect(conn["callable"])
		for conn in bar.mouse_exited.get_connections():
			bar.mouse_exited.disconnect(conn["callable"])
		bar.mouse_entered.connect(func() -> void:
			(bar.material as ShaderMaterial).set_shader_parameter("hover_tint", Color(0.06, 0.04, 0.01, 1.0))
		)
		bar.mouse_exited.connect(func() -> void:
			(bar.material as ShaderMaterial).set_shader_parameter("hover_tint", Color(0.0, 0.0, 0.0, 0.0))
		)
		if bar.get_child_count() > 0:
			bar.get_child(0).add_theme_color_override("font_color", Color(0.95, 0.8, 0.3))

	var saved_progress: float = aq.action_progress.get(action["action_id"], 0.0)
	if saved_progress > 0.0 and not is_disabled and not is_combat:
		var dur: float = action["duration"]
		bar.visible = true
		set_bar_progress(bar, saved_progress / dur if dur > 0.0 else 0.0)
		btn.visible = false
		if bar.get_child_count() > 1 and dur > 5.0:
			var time_lbl: Label = bar.get_child(1)
			var secs_left := maxf(dur - saved_progress, 0.0)
			if secs_left >= 60.0:
				var mins := int(secs_left) / 60
				var secs := int(secs_left) % 60
				time_lbl.text = "%d:%02d" % [mins, secs]
			else:
				time_lbl.text = "%ds" % ceili(secs_left)
	else:
		bar.visible = false

	var slot := Control.new()
	slot.custom_minimum_size = Vector2(300, 50)
	btn.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bar.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	slot.add_child(btn)
	slot.add_child(bar)

	if not is_disabled:
		var act: Dictionary = action
		if is_combat:
			btn.pressed.connect(func() -> void:
				game.combat.auto_fight_remaining = act.get("auto_fight_count", 0)
				game.combat.enter_combat(act)
			)
		else:
			btn.pressed.connect(func() -> void:
				print("[QUEUE] Left-click enqueue FRONT: ", act["label"])
				aq.enqueue_action(act, true)
			)
			btn.gui_input.connect(func(event: InputEvent) -> void:
				if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
					print("[QUEUE] Right-click enqueue BACK: ", act["label"])
					aq.enqueue_action(act, false)
					btn.accept_event()
			)
			bar.mouse_filter = Control.MOUSE_FILTER_STOP
			bar.gui_input.connect(func(event: InputEvent) -> void:
				if event is InputEventMouseButton and event.pressed:
					if event.button_index == MOUSE_BUTTON_LEFT:
						print("[QUEUE] Bar left-click enqueue FRONT: ", act["label"])
						aq.enqueue_action(act, true)
					elif event.button_index == MOUSE_BUTTON_RIGHT:
						print("[QUEUE] Bar right-click enqueue BACK: ", act["label"])
						aq.enqueue_action(act, false)
			)

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
		info_btn.pressed.connect(func() -> void: show_item_info(iid))
		row.add_child(info_btn)
	elif game._location_has_shop_items:
		var spacer := Control.new()
		spacer.custom_minimum_size = Vector2(40, 0)
		row.add_child(spacer)

	return row


func show_enemy_info(action: Dictionary) -> void:
	var player: PlayerData = game.player
	clear_info_panel()
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

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 4)
	info_content.add_child(spacer)

	var stats: Array[String] = []
	stats.append("HP: %d" % action["enemy_hp"])
	stats.append("Damage: %d" % action["enemy_damage"])
	stats.append("Attack Speed: %.1fs" % action["enemy_attack_speed"])
	var stats_label := Label.new()
	stats_label.text = "\n".join(stats)
	stats_label.modulate = Color(1.0, 0.7, 0.7)
	stats_label.add_theme_font_size_override("font_size", 14)
	info_content.add_child(stats_label)

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

	if action.get("slime_fight", false):
		var remaining := player.MAX_SLIMES - player.slimes_defeated
		var count_label := Label.new()
		count_label.text = "Remaining: %d / %d" % [remaining, player.MAX_SLIMES]
		count_label.modulate = Color(0.65, 0.65, 0.7)
		count_label.add_theme_font_size_override("font_size", 13)
		info_content.add_child(count_label)


func show_item_info(item_id: String) -> void:
	var player: PlayerData = game.player
	var item: Dictionary = player.item_catalogue.get(item_id, {})
	if item.is_empty():
		return

	clear_info_panel()
	info_title.visible = false
	info_sep.visible = false

	var title := Label.new()
	title.text = item["name"]
	title.add_theme_font_size_override("font_size", 18)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var rarity_color := Color.WHITE
	if item.get("bonus_damage", 0) > 0 or item.get("attack_speed_bonus", 0.0) > 0.0:
		rarity_color = Color(0.55, 0.75, 1.0)
	elif item.get("damage_reduction", 0) > 0:
		rarity_color = Color(0.6, 0.85, 0.6)
	else:
		rarity_color = Color(1.0, 0.75, 0.45)
	title.modulate = rarity_color
	info_content.add_child(title)

	var sep_line := ColorRect.new()
	sep_line.color = Color(rarity_color, 0.4)
	sep_line.custom_minimum_size = Vector2(0, 2)
	info_content.add_child(sep_line)

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

	var desc := Label.new()
	desc.text = item.get("description", "No description.")
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.modulate = Color(0.75, 0.75, 0.8)
	desc.add_theme_font_size_override("font_size", 13)
	info_content.add_child(desc)

	var cost_label := Label.new()
	cost_label.text = "%d gold" % item["cost"]
	cost_label.modulate = Color(1.0, 0.85, 0.3)
	cost_label.add_theme_font_size_override("font_size", 14)
	info_content.add_child(cost_label)

	var owned: int = player.inventory.get(item_id, 0)
	var limit: int = item.get("max", 1)
	var owned_label := Label.new()
	owned_label.text = "Owned: %d / %d" % [owned, limit]
	owned_label.modulate = Color(0.65, 0.65, 0.7)
	owned_label.add_theme_font_size_override("font_size", 13)
	info_content.add_child(owned_label)


func show_modal(title_text: String, body_text: String) -> void:
	if _modal_overlay and is_instance_valid(_modal_overlay):
		_modal_overlay.queue_free()

	_modal_overlay = ColorRect.new()
	_modal_overlay.color = Color(0.0, 0.0, 0.0, 0.6)
	_modal_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_modal_overlay.z_index = 100
	game.add_child(_modal_overlay)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_modal_overlay.add_child(center)

	var panel := PanelContainer.new()
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.1, 0.1, 0.16, 1.0)
	panel_style.border_color = Color(0.4, 0.45, 0.6, 0.8)
	panel_style.set_border_width_all(2)
	panel_style.set_corner_radius_all(12)
	panel_style.set_content_margin_all(24)
	panel.add_theme_stylebox_override("panel", panel_style)
	panel.custom_minimum_size = Vector2(700, 500)
	center.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	panel.add_child(vbox)

	var title_lbl := Label.new()
	title_lbl.text = title_text
	title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_lbl.add_theme_font_size_override("font_size", 20)
	title_lbl.add_theme_color_override("font_color", Color(0.95, 0.8, 0.3))
	vbox.add_child(title_lbl)

	var sep := HSeparator.new()
	sep.modulate = Color(0.4, 0.45, 0.6, 0.6)
	vbox.add_child(sep)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 380)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(scroll)

	var body_lbl := Label.new()
	body_lbl.text = body_text
	body_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body_lbl.custom_minimum_size = Vector2(650, 0)
	body_lbl.add_theme_font_size_override("font_size", 14)
	body_lbl.modulate = Color(0.85, 0.85, 0.9)
	scroll.add_child(body_lbl)

	var close_btn := Button.new()
	close_btn.text = "Close"
	close_btn.custom_minimum_size = Vector2(120, 40)
	close_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	close_btn.pressed.connect(close_modal)

	var close_style := StyleBoxFlat.new()
	close_style.bg_color = Color(0.15, 0.15, 0.22, 1.0)
	close_style.border_color = Color(0.4, 0.45, 0.6, 0.6)
	close_style.set_border_width_all(1)
	close_style.set_corner_radius_all(8)
	close_style.set_content_margin_all(8)
	close_btn.add_theme_stylebox_override("normal", close_style)
	var close_hover := close_style.duplicate()
	close_hover.bg_color = Color(0.2, 0.2, 0.3, 1.0)
	close_btn.add_theme_stylebox_override("hover", close_hover)
	vbox.add_child(close_btn)


func close_modal() -> void:
	if _modal_overlay and is_instance_valid(_modal_overlay):
		_modal_overlay.queue_free()
		_modal_overlay = null


func clear_info_panel() -> void:
	for child in info_content.get_children():
		child.queue_free()
	info_title.visible = true
	info_sep.visible = true


func show_location_synopsis(location) -> void:
	var player: PlayerData = game.player
	var synopsis := ""
	match location:
		Location.JAIL_CELL:
			synopsis = "You're locked in a damp cell. The door is barred and there's no obvious way out.\n\nYou can hear a guard pacing just outside. Maybe you can get his attention."
		Location.JAIL_CELL_GUARD:
			synopsis = "The guard has entered your cell. He looks angry but careless — his keys are dangling from his belt.\n\nThis might be your only chance."
		Location.JAIL_GUARDROOM:
			synopsis = "A small room outside the cell. A wooden desk sits against the wall with a drawer that has a keyhole. In the corner, a heavy iron chest catches your eye — it looks far too sturdy to open easily."
			if player.desk_unlocked:
				synopsis = "A small room outside the cell. The desk drawer hangs open."
				if player.desk_potions_taken < player.DESK_POTIONS_MAX or not player.note_fully_read:
					synopsis += " There are still things inside worth taking."
				if player.note_fully_read:
					synopsis += "\n\nThe prisoner note's contents are seared into your memory."
				synopsis += "\n\nThe heavy iron chest in the corner remains stubbornly locked."
		Location.OUTSIDE:
			synopsis = "You've escaped the jail. The open air hits your face.\n\nA town lies to the west. To the east, the entrance to a dungeon looms."
		Location.TOWN:
			synopsis = "A small town with a few establishments. You could prepare yourself before heading into danger.\n\nThe healer can patch you up, the blacksmith sells weapons and armor, and the general store has supplies."
		Location.TOWN_HEALER:
			synopsis = "A quiet healer's hut. For a small fee, the healer will restore you to full health."
		Location.TOWN_BLACKSMITH:
			synopsis = "The clang of hammer on anvil fills the air. The blacksmith offers weapons and armor for sale."
		Location.TOWN_GENERAL_GOODS:
			synopsis = "Shelves lined with potions and supplies. The shopkeeper eyes you expectantly."
		Location.DUNGEON_ENTRANCE:
			synopsis = "A dark passage leads deeper underground. You can hear faint squelching sounds echoing from within."
			if not player.all_slimes_cleared:
				synopsis += "\n\nSlimes infest the entrance — %d of %d remain." % [player.MAX_SLIMES - player.slimes_defeated, player.MAX_SLIMES]
			else:
				synopsis += "\n\nThe entrance is clear of slimes. The way forward is open."

	if synopsis.is_empty():
		return

	info_title.visible = false
	info_sep.visible = false

	var synopsis_label := Label.new()
	synopsis_label.text = synopsis
	synopsis_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	synopsis_label.modulate = Color(0.75, 0.78, 0.85)
	synopsis_label.add_theme_font_size_override("font_size", 13)
	info_content.add_child(synopsis_label)


func update_player_stats_ui() -> void:
	var player: PlayerData = game.player
	hp_label.text = "HP: %d / %d" % [player.hp, player.max_hp]
	hp_label.add_theme_color_override("font_color", Color(0.9, 0.3, 0.3))

	if player.xp > 0 and not player.xp_revealed:
		player.xp_revealed = true
	xp_label.visible = player.xp_revealed
	xp_label.text = "XP: %d" % player.xp

	if player.gold > 0 and not player.gold_revealed:
		player.gold_revealed = true
	gold_label.visible = player.gold_revealed
	gold_label.text = "Gold: %d" % player.gold


func update_inventory_ui() -> void:
	var player: PlayerData = game.player
	for child in inventory_list.get_children():
		child.queue_free()

	var has_items := false
	for item_id in player.item_catalogue:
		var count: int = player.inventory.get(item_id, 0)
		if count <= 0:
			continue
		has_items = true
		var item: Dictionary = player.item_catalogue[item_id]
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
		btn.pressed.connect(func() -> void: show_item_info(iid))
		inventory_list.add_child(btn)

	if not has_items:
		var empty_lbl := Label.new()
		empty_lbl.text = "(empty)"
		empty_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty_lbl.modulate = Color(1, 1, 1, 0.5)
		inventory_list.add_child(empty_lbl)
