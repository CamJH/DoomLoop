class_name PlayerData
extends RefCounted

## Pure data + logic for the player. No UI references.

# ---- Stats ----
var max_hp := 10
var hp := 10
var xp := 0
var gold := 0
var base_attack_speed := 3.0  ## Base seconds per attack.
var attack_speed_bonus := 0.0  ## Percentage bonus from equipment (0.2 = 20%).
var base_damage := 1
var damage_bonus := 0  ## From equipment (e.g. sword).
var damage_reduction := 0  ## From equipment (e.g. shield).

# ---- Inventory ----
var inventory: Dictionary = {}

var item_catalogue := {
	"iron_sword":    { "name": "Iron Sword",    "cost": 3, "max": 1,  "description": "A sturdy blade forged in town.", "bonus_damage": 1, "attack_speed_bonus": 0.2 },
	"wooden_shield": { "name": "Wooden Shield", "cost": 2, "max": 1,  "description": "A simple shield that absorbs blows.", "damage_reduction": 1 },
	"health_potion": { "name": "Health Potion", "cost": 1, "max": 10, "description": "Restores 5 HP instantly." },
	"cudgel":        { "name": "Cudgel",        "cost": 0, "max": 1,  "description": "A crude wooden club taken from the jail guard.", "bonus_damage": 1, "attack_speed_bonus": 0.1 },
	"jail_keys":     { "name": "Jail Keys",     "cost": 0, "max": 1,  "description": "A ring of iron keys taken from the guard. Opens most locks in the jail." },
	"prisoner_note": { "name": "Prisoner Note", "cost": 0, "max": 1,  "description": "A crumpled note from Warden Aldric about Prisoner #347 — you. Mentions a curse and temporal displacement." },
}

var blacksmith_stock: Array[String] = ["iron_sword", "wooden_shield"]
var general_goods_stock: Array[String] = ["health_potion"]

# ---- Dungeon state ----
var slimes_defeated := 0
var all_slimes_cleared := false
const MAX_SLIMES := 10

# ---- Desk state ----
var desk_potions_taken := 0
const DESK_POTIONS_MAX := 2
var desk_unlocked := false

# ---- Note state (persistent across loops) ----
var note_read_progress := 0.0  ## 0.0 to 1.0 — how much of the prisoner note has been read.
var note_fully_read := false  ## True once the note has been completely read.
const NOTE_READ_DURATION := 15.0  ## Total seconds to read the full note.

# ---- UI reveal state ----
var xp_revealed := false
var gold_revealed := false


func recalculate_equipment() -> void:
	damage_bonus = 0
	damage_reduction = 0
	attack_speed_bonus = 0.0
	for item_id in inventory:
		if inventory[item_id] <= 0:
			continue
		var item: Dictionary = item_catalogue.get(item_id, {})
		damage_bonus += item.get("bonus_damage", 0)
		damage_reduction += item.get("damage_reduction", 0)
		attack_speed_bonus += item.get("attack_speed_bonus", 0.0)


func get_attack_damage() -> int:
	return base_damage + damage_bonus


func get_attack_speed() -> float:
	## Lower = faster. 20% bonus means 20% less time between attacks.
	return base_attack_speed * (1.0 - attack_speed_bonus)


func get_damage_after_reduction(raw_damage: int) -> int:
	return maxi(raw_damage - damage_reduction, 0)


func reset_for_new_loop() -> void:
	hp = max_hp
	xp = 0
	gold = 0
	inventory = {}
	slimes_defeated = 0
	all_slimes_cleared = false
	desk_potions_taken = 0
	desk_unlocked = false
	recalculate_equipment()
