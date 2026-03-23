class_name RoutePlan
extends Resource

## A saved route plan consisting of ordered steps the player wants to auto-execute.

@export var plan_name: String = "Untitled Route"
@export var steps: Array[Dictionary] = []


## Add a step to the plan.
func add_step(step: Dictionary) -> void:
	steps.append(step)


## Remove a step by index.
func remove_step(index: int) -> void:
	if index >= 0 and index < steps.size():
		steps.remove_at(index)


## Move a step from one index to another.
func move_step(from_index: int, to_index: int) -> void:
	if from_index < 0 or from_index >= steps.size():
		return
	if to_index < 0 or to_index >= steps.size():
		return
	var step := steps[from_index]
	steps.remove_at(from_index)
	steps.insert(to_index, step)


## Clear all steps.
func clear() -> void:
	steps.clear()


## Get estimated total time in seconds.
func get_estimated_time() -> float:
	var total := 0.0
	for step in steps:
		total += step.get("estimated_time", 0.0)
	return total


## Save this plan to user:// filesystem.
static func save_plan(plan: RoutePlan, filename: String) -> Error:
	DirAccess.make_dir_recursive_absolute("user://routes")
	return ResourceSaver.save(plan, "user://routes/%s.tres" % filename)


## Load a plan from user:// filesystem.
static func load_plan(filename: String) -> RoutePlan:
	var path := "user://routes/%s.tres" % filename
	if ResourceLoader.exists(path):
		return ResourceLoader.load(path) as RoutePlan
	return null


## List all saved plan filenames.
static func list_saved_plans() -> Array[String]:
	var plans: Array[String] = []
	var dir := DirAccess.open("user://routes")
	if dir == null:
		return plans
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if file_name.ends_with(".tres"):
			plans.append(file_name.get_basename())
		file_name = dir.get_next()
	return plans


## Delete a saved plan.
static func delete_plan(filename: String) -> Error:
	return DirAccess.remove_absolute("user://routes/%s.tres" % filename)
