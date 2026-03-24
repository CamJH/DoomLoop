class_name LocationManager
extends RefCounted

## Location data, pathfinding, and the Location enum.

enum Location {
	JAIL_CELL,
	JAIL_CELL_GUARD,
	JAIL_GUARDROOM,
	OUTSIDE,
	TOWN,
	TOWN_HEALER,
	TOWN_BLACKSMITH,
	TOWN_GENERAL_GOODS,
	DUNGEON_ENTRANCE,
}

var game  ## Reference to game.gd.


func _init(game_ref) -> void:
	game = game_ref


func _build_shop_actions(stock: Array[String], back_destination: Location) -> Array:
	var player: PlayerData = game.player
	var actions: Array = []
	for item_id in stock:
		var item: Dictionary = player.item_catalogue[item_id]
		var owned: int = player.inventory.get(item_id, 0)
		var at_limit: bool = owned >= item["max"]
		var can_afford: bool = player.gold >= item["cost"]
		var lbl: String = "Buy %s — %d gold" % [item["name"], item["cost"]]
		var aid: String = "buy_" + item_id

		if at_limit:
			actions.append({
				"action_id": aid,
				"label": lbl, "duration": 0.0, "destination": -1,
				"disabled": true, "disabled_reason": "limit reached",
				"item_id": item_id,
			})
		elif not can_afford:
			actions.append({
				"action_id": aid,
				"label": lbl, "duration": 0.0, "destination": -1,
				"disabled": true, "disabled_reason": "can't afford",
				"item_id": item_id,
			})
		else:
			actions.append({
				"action_id": aid,
				"label": lbl, "duration": 2.0, "destination": -1,
				"shop_buy": true, "item_id": item_id,
				"gold_cost": item["cost"],
			})
	actions.append({ "action_id": "back_to_town", "label": "Back to Town", "duration": 1.0, "destination": back_destination })
	return actions


func get_location_data(location: Location) -> Dictionary:
	var player: PlayerData = game.player
	match location:
		Location.JAIL_CELL:
			return {
				"name": "Jail Cell",
				"actions": [
					{
						"action_id": "jail_taunt_guard",
						"label": "Taunt the Guard",
						"duration": 1.0,
						"destination": Location.JAIL_CELL_GUARD,
					},
				],
			}

		Location.JAIL_CELL_GUARD:
			return {
				"name": "Jail Cell",
				"actions": [
					{
						"action_id": "jail_attack_guard",
						"label": "Attack the Guard",
						"duration": 0.0,
						"destination": -1,
						"combat_start": true,
						"enemy_name": "Jail Guard",
						"enemy_hp": 1,
						"enemy_attack_speed": 2.5,
						"enemy_damage": 2,
						"reward_gold": 0,
						"reward_xp": 2,
						"jail_guard_fight": true,
					},
				],
			}

		Location.JAIL_GUARDROOM:
			var actions: Array = []
			if not player.desk_unlocked:
				if player.inventory.get("jail_keys", 0) > 0:
					actions.append({
						"action_id": "jail_unlock_desk",
						"label": "Unlock the Desk",
						"duration": 2.0,
						"destination": -1,
						"unlock_desk": true,
					})
				else:
					actions.append({
						"action_id": "jail_unlock_desk",
						"label": "Unlock the Desk",
						"duration": 0.0, "destination": -1,
						"disabled": true, "disabled_reason": "locked — need keys",
					})
			else:
				var potions_remaining := player.DESK_POTIONS_MAX - player.desk_potions_taken
				if potions_remaining > 0:
					actions.append({
						"action_id": "jail_take_potion",
						"label": "Take Health Potion (%d left)" % potions_remaining,
						"duration": 1.0,
						"destination": -1,
						"desk_loot": true,
					})
				if player.note_fully_read:
					if player.inventory.get("prisoner_note", 0) <= 0:
						actions.append({
							"action_id": "jail_take_note",
							"label": "Take the Note",
							"duration": 1.0,
							"destination": -1,
							"take_note": true,
						})
				else:
					var remaining_time := player.NOTE_READ_DURATION * (1.0 - player.note_read_progress)
					actions.append({
						"action_id": "jail_read_note",
						"label": "Read Prisoner Note",
						"duration": remaining_time,
						"destination": -1,
						"note_read": true,
						"persistent_action": true,
					})
			actions.append({
				"action_id": "jail_break_chest",
				"label": "Break Open the Chest",
				"duration": 1200.0,
				"destination": -1,
				"chest_break": true,
			})
			if player.inventory.get("prisoner_note", 0) > 0:
				actions.append({ "action_id": "jail_leave", "label": "Leave the Jail", "duration": 1.0, "destination": Location.OUTSIDE })
			else:
				actions.append({
					"action_id": "jail_leave",
					"label": "Leave the Jail", "duration": 0.0, "destination": -1,
					"disabled": true, "disabled_reason": "You should look around first...",
				})
			return { "name": "Guard Room", "actions": actions }

		Location.OUTSIDE:
			return {
				"name": "Outside",
				"actions": [
					{ "action_id": "travel_to_town", "label": "Head into Town", "duration": 1.0, "destination": Location.TOWN },
					{ "action_id": "travel_to_dungeon", "label": "Head into the Dungeon", "duration": 1.0, "destination": Location.DUNGEON_ENTRANCE },
				],
			}

		Location.TOWN:
			return {
				"name": "Town",
				"actions": [
					{ "action_id": "travel_enter_dungeon", "label": "Enter the Dungeon", "duration": 1.0, "destination": Location.DUNGEON_ENTRANCE },
					{ "action_id": "travel_to_healer", "label": "Visit the Healer", "duration": 1.0, "destination": Location.TOWN_HEALER },
					{ "action_id": "travel_to_blacksmith", "label": "Visit the Blacksmith", "duration": 1.0, "destination": Location.TOWN_BLACKSMITH },
					{ "action_id": "travel_to_general_goods", "label": "Visit General Goods", "duration": 1.0, "destination": Location.TOWN_GENERAL_GOODS },
				],
			}

		Location.TOWN_HEALER:
			var actions: Array = []
			if player.hp >= player.max_hp:
				actions.append({
					"action_id": "heal_full",
					"label": "Heal to full HP — 1 gold", "duration": 0.0, "destination": -1,
					"disabled": true, "disabled_reason": "full health",
				})
			elif player.gold < 1:
				actions.append({
					"action_id": "heal_full",
					"label": "Heal to full HP — 1 gold", "duration": 0.0, "destination": -1,
					"disabled": true, "disabled_reason": "can't afford",
				})
			else:
				actions.append({
					"action_id": "heal_full",
					"label": "Heal to full HP — 1 gold", "duration": 2.0, "destination": -1,
					"heal": true, "gold_cost": 1,
				})
			actions.append({ "action_id": "back_to_town", "label": "Back to Town", "duration": 1.0, "destination": Location.TOWN })
			return { "name": "Town — Healer", "actions": actions }

		Location.TOWN_BLACKSMITH:
			return {
				"name": "Town — Blacksmith",
				"actions": _build_shop_actions(player.blacksmith_stock, Location.TOWN),
			}

		Location.TOWN_GENERAL_GOODS:
			return {
				"name": "Town — General Goods",
				"actions": _build_shop_actions(player.general_goods_stock, Location.TOWN),
			}

		Location.DUNGEON_ENTRANCE:
			var actions: Array = []
			if not player.all_slimes_cleared:
				var slime_action := {
					"enemy_name": "Slime", "enemy_hp": 3,
					"enemy_attack_speed": 2.0, "enemy_damage": 1,
					"reward_gold": 2, "reward_xp": 1,
					"slime_fight": true,
				}
				var remaining_slimes := player.MAX_SLIMES - player.slimes_defeated
				actions.append({
					"action_id": "fight_slime",
					"label": "Fight a Slime (%d/%d)" % [player.slimes_defeated, player.MAX_SLIMES],
					"duration": 0.0, "destination": -1,
					"combat_start": true,
					"auto_fight_count": 0,
				}.merged(slime_action))
				actions.append({
					"action_id": "fight_all_slimes",
					"label": "Fight All Slimes (%d left)" % remaining_slimes,
					"duration": 0.0, "destination": -1,
					"combat_start": true,
					"auto_fight_count": remaining_slimes - 1,
				}.merged(slime_action))
			else:
				actions.append({
					"action_id": "fight_slime",
					"label": "All slimes defeated!", "duration": 0.0, "destination": -1,
					"disabled": true,
				})
			actions.append({ "action_id": "back_to_town", "label": "Back to Town", "duration": 1.0, "destination": Location.TOWN })
			return { "name": "Dungeon Entrance", "actions": actions }

	return { "name": "???", "actions": [] }


## Get location data for the planner — shows ALL possible actions as enabled.
func get_planner_location_data(location: Location) -> Dictionary:
	var player: PlayerData = game.player
	match location:
		Location.JAIL_CELL:
			return {
				"name": "Jail Cell",
				"actions": [
					{ "action_id": "jail_taunt_guard", "label": "Taunt the Guard", "duration": 1.0, "destination": Location.JAIL_CELL_GUARD },
				],
			}

		Location.JAIL_CELL_GUARD:
			return {
				"name": "Jail Cell (Guard)",
				"actions": [
					{
						"action_id": "jail_attack_guard",
						"label": "Attack the Guard",
						"duration": 0.0, "destination": -1,
						"combat_start": true,
						"enemy_name": "Jail Guard", "enemy_hp": 1,
						"enemy_attack_speed": 2.5, "enemy_damage": 2,
						"reward_gold": 0, "reward_xp": 2,
						"jail_guard_fight": true,
						"condition": { "type": "always", "on_fail": "skip" },
					},
				],
			}

		Location.JAIL_GUARDROOM:
			var actions: Array = []
			actions.append({
				"action_id": "jail_unlock_desk",
				"label": "Unlock the Desk", "duration": 2.0, "destination": -1,
				"unlock_desk": true,
				"condition": { "type": "desk_locked", "on_fail": "skip" },
			})
			actions.append({
				"action_id": "jail_take_potion",
				"label": "Take Health Potion", "duration": 1.0, "destination": -1,
				"desk_loot": true,
				"condition": { "type": "desk_has_potions", "on_fail": "skip" },
			})
			if not player.note_fully_read:
				var remaining_time := player.NOTE_READ_DURATION * (1.0 - player.note_read_progress)
				actions.append({
					"action_id": "jail_read_note",
					"label": "Read Prisoner Note", "duration": remaining_time, "destination": -1,
					"note_read": true, "persistent_action": true,
					"condition": { "type": "note_not_read", "on_fail": "skip" },
				})
			actions.append({
				"action_id": "jail_take_note",
				"label": "Take the Note", "duration": 1.0, "destination": -1,
				"take_note": true,
				"condition": { "type": "note_read_and_not_taken", "on_fail": "skip" },
			})
			actions.append({ "action_id": "jail_break_chest", "label": "Break Open the Chest", "duration": 1200.0, "destination": -1, "chest_break": true })
			actions.append({ "action_id": "jail_leave", "label": "Leave the Jail", "duration": 1.0, "destination": Location.OUTSIDE })
			return { "name": "Guard Room", "actions": actions }

		Location.OUTSIDE:
			return {
				"name": "Outside",
				"actions": [
					{ "action_id": "travel_to_town", "label": "Head into Town", "duration": 1.0, "destination": Location.TOWN },
					{ "action_id": "travel_to_dungeon", "label": "Head into the Dungeon", "duration": 1.0, "destination": Location.DUNGEON_ENTRANCE },
				],
			}

		Location.TOWN:
			return {
				"name": "Town",
				"actions": [
					{ "action_id": "travel_enter_dungeon", "label": "Enter the Dungeon", "duration": 1.0, "destination": Location.DUNGEON_ENTRANCE },
					{ "action_id": "travel_to_healer", "label": "Visit the Healer", "duration": 1.0, "destination": Location.TOWN_HEALER },
					{ "action_id": "travel_to_blacksmith", "label": "Visit the Blacksmith", "duration": 1.0, "destination": Location.TOWN_BLACKSMITH },
					{ "action_id": "travel_to_general_goods", "label": "Visit General Goods", "duration": 1.0, "destination": Location.TOWN_GENERAL_GOODS },
				],
			}

		Location.TOWN_HEALER:
			return {
				"name": "Town — Healer",
				"actions": [
					{
						"action_id": "heal_full",
						"label": "Heal to full HP — 1 gold", "duration": 2.0, "destination": -1,
						"heal": true, "gold_cost": 1,
						"condition": { "type": "needs_heal_and_gold", "on_fail": "skip" },
					},
					{ "action_id": "back_to_town", "label": "Back to Town", "duration": 1.0, "destination": Location.TOWN },
				],
			}

		Location.TOWN_BLACKSMITH:
			var actions: Array = []
			for item_id in player.blacksmith_stock:
				var item: Dictionary = player.item_catalogue[item_id]
				actions.append({
					"action_id": "buy_" + item_id,
					"label": "Buy %s — %d gold" % [item["name"], item["cost"]],
					"duration": 2.0, "destination": -1,
					"shop_buy": true, "item_id": item_id, "gold_cost": item["cost"],
					"condition": { "type": "can_buy_item", "item_id": item_id, "on_fail": "skip" },
				})
			actions.append({ "action_id": "back_to_town", "label": "Back to Town", "duration": 1.0, "destination": Location.TOWN })
			return { "name": "Town — Blacksmith", "actions": actions }

		Location.TOWN_GENERAL_GOODS:
			var actions: Array = []
			for item_id in player.general_goods_stock:
				var item: Dictionary = player.item_catalogue[item_id]
				actions.append({
					"action_id": "buy_" + item_id,
					"label": "Buy %s — %d gold" % [item["name"], item["cost"]],
					"duration": 2.0, "destination": -1,
					"shop_buy": true, "item_id": item_id, "gold_cost": item["cost"],
					"condition": { "type": "can_buy_item", "item_id": item_id, "on_fail": "skip" },
				})
			actions.append({ "action_id": "back_to_town", "label": "Back to Town", "duration": 1.0, "destination": Location.TOWN })
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
				"action_id": "fight_slime",
				"label": "Fight a Slime",
				"duration": 0.0, "destination": -1,
				"combat_start": true, "auto_fight_count": 0,
				"condition": { "type": "slimes_remaining", "on_fail": "skip" },
			}.merged(slime_action))
			actions.append({
				"action_id": "fight_all_slimes",
				"label": "Fight All Slimes",
				"duration": 0.0, "destination": -1,
				"combat_start": true, "auto_fight_count": 9,
				"condition": { "type": "slimes_remaining", "on_fail": "skip" },
			}.merged(slime_action))
			actions.append({ "action_id": "back_to_town", "label": "Back to Town", "duration": 1.0, "destination": Location.TOWN })
			return { "name": "Dungeon Entrance", "actions": actions }

	return { "name": "???", "actions": [] }


## Travel graph: maps each location to its direct travel connections.
func get_travel_graph() -> Dictionary:
	return {
		Location.JAIL_CELL: [
			{ "label": "Taunt the Guard", "duration": 1.0, "destination": Location.JAIL_CELL_GUARD },
		],
		Location.JAIL_CELL_GUARD: [],
		Location.JAIL_GUARDROOM: [
			{ "label": "Leave the Jail", "duration": 1.0, "destination": Location.OUTSIDE },
		],
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
func find_travel_path(from_loc: int, to_loc: int) -> Array:
	if from_loc == to_loc:
		return []

	var graph := get_travel_graph()
	var queue: Array = [[from_loc]]
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
				var steps: Array = []
				for i in range(1, new_path.size()):
					var prev: int = new_path[i - 1]
					var dest: int = new_path[i]
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

	return []


func get_prisoner_note_text() -> String:
	return """Prisoner #347 — DO NOT RELEASE under any circumstances.

Subject exhibits signs of temporal displacement. Claims to have 'lived this day before' — repeatedly.

Court mage confirms presence of a curse, origin unknown. The subject appears unaware of the full extent of the affliction. Each recurrence seems to restore the subject's body to its prior state, though the mind retains fragments.

Subject is to remain confined until further study. Under no circumstances allow subject access to the dungeon — reports of unstable magical artifacts below may interact with the curse in unpredictable ways.

— Warden Aldric"""
