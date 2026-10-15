extends Node
## Checkpoint (autoload): a snapshot of the game taken at the start of every
## day and every night, restored when the player dies and restarts, so the
## world is exactly as it was when that day or night began:
##   - the inventory (Inventory.save_checkpoint), the flashlight battery,
##     the generator's fuel;
##   - story progress and objectives (RoutineManager), evidence
##     (EvidenceManager);
##   - windows (glass, planks), scrap heap contents, the van's repairs,
##     doors, light switches, the fuse box, the nests;
##   - items lying in the world (picked up since: put back; dropped since:
##     removed), and the trap: the portable light and its power cable;
##   - the notebook's pages, the thoughts had (so the ones after it come
##     again), where the knockable props stand, and the night and story
##     flags (NightManager: used when "Play Again" reloads the scene).
##
## "Play Again" after an ending (ending_screen.gd) reloads the game scene and
## restores this snapshot into it (restore_on_load, NightManager).
##
## NightManager captures (start_night, and when a day begins) and restores
## (restart_from_checkpoint). State is read from each object's script
## variables of plain types (bools, numbers, strings, vectors, arrays,
## dictionaries); an object can refresh itself afterwards in
## _on_checkpoint_restored().

const STATE_SCRIPTS := [
	"cabin_window.gd", "scrap_heap.gd", "escape_van.gd", "door.gd", "cabin_light.gd",
	"fuse_box.gd", "hasselmus_nest.gd", "generator_outlet.gd", "notebook_ui.gd",
]
## NightManager's night and story flags (restored when the scene reloads).
const STORY_FLAGS := ["current_night", "van_sequence_started", "is_van_sequence_active"]
const STATE_AUTOLOADS := ["RoutineManager", "EvidenceManager"]
## World items: anything whose script is a pickup (but not the flashlight and
## camera: having those is the player's own state, not restored).
const PICKUP_SCRIPT_HINT := "pickup"
const PICKUP_EXCLUDED := ["flashlight_pickup.gd", "camera_pickup.gd"]

## "day" or "night": which kind of start the snapshot was taken at.
var kind := ""
## A special moment it was taken at ("van_alarm": the Night 2.2 car alarm
## going off; a death then restarts there, at the van).
var tag := ""
var _taken := false
var _inventory_saved := false
var _night_fuel := 0.0
var _generator_on := true
var _time_progress := 0.0
var _battery := -1.0
## node path -> {var: value}
var _states := {}
## [{"template": Node, "parent": NodePath, "transform": Transform3D}]
var _pickups: Array = []
## [{"template": Node, "parent": NodePath, "transform": Transform3D, "state": {}}]
var _lamps: Array = []
## [{"outlet": NodePath, "lamp": int (index in _lamps, -1 none), "state": int}]
var _cables: Array = []
var restoring := false
## Set by "Play Again": the next game scene is put back to this snapshot.
var restore_on_load := false
var _story := {}
var _thoughts := {}
## knockable prop path -> Transform3D
var _props := {}


## The template copies live outside the tree: free them with the game.
func _exit_tree() -> void:
	_free_templates()


func has_checkpoint() -> bool:
	return _taken


## Takes a snapshot of the game now (`snapshot_kind`: "day" or "night").
func capture(snapshot_kind: String, snapshot_tag: String = "") -> void:
	if restoring:
		return
	var scene := get_tree().current_scene
	if not scene:
		return
	kind = snapshot_kind
	tag = snapshot_tag
	_taken = true
	_free_templates()
	_states.clear()

	var inventory := get_node_or_null("/root/Inventory")
	if inventory and inventory.has_method("save_checkpoint"):
		inventory.save_checkpoint()
		_inventory_saved = true
	var nm := get_node_or_null("/root/NightManager")
	if nm:
		_night_fuel = nm.generator_fuel
		_generator_on = nm.is_generator_on
	var gt := get_node_or_null("/root/GameTime")
	_time_progress = gt.cycle_progress if gt else 0.0
	_story.clear()
	if nm:
		for flag in STORY_FLAGS:
			_story[flag] = nm.get(flag)
	var monologue := get_node_or_null("/root/Monologue")
	_thoughts = monologue._had.duplicate() if monologue else {}
	_props.clear()
	for prop in get_tree().get_nodes_in_group("knockable"):
		if prop is Node3D and prop.is_inside_tree():
			_props[prop.get_path()] = (prop as Node3D).global_transform
	var flashlight := _flashlight()
	_battery = flashlight.battery_level if flashlight and "battery_level" in flashlight else -1.0

	for autoload in STATE_AUTOLOADS:
		var node := get_node_or_null("/root/" + autoload)
		if node:
			_states[NodePath("/root/" + autoload)] = _read_state(node)
	for node in _state_nodes(scene):
		_states[node.get_path()] = _read_state(node)

	for node in _pickup_nodes(scene):
		_pickups.append({
			"template": _template(node),
			"parent": node.get_parent().get_path(),
			"transform": (node as Node3D).global_transform if node is Node3D else Transform3D.IDENTITY,
		})
	var lamp_index := {}
	for lamp in get_tree().get_nodes_in_group("portable_trap"):
		if not lamp.has_method("drop_trap") or lamp.is_queued_for_deletion():
			continue
		lamp_index[lamp] = _lamps.size()
		_lamps.append({
			"template": _template(lamp),
			"parent": lamp.get_parent().get_path(),
			"transform": lamp.global_transform,
			"state": _read_state(lamp),
		})
	for cable in get_tree().get_nodes_in_group("power_cable"):
		if cable.is_queued_for_deletion() or not cable.has_method("get_state") or cable.get_state() == 0:
			continue
		var source: Node = cable.get("source_node")
		var target: Node = cable.get("target_node")
		_cables.append({
			"outlet": source.get_path() if source else NodePath(),
			"lamp": lamp_index.get(target, -1),
			"state": cable.get_state(),
		})
	print("[Checkpoint] %s snapshot: %d objects, %d world items, %d lamps, %d cables." % [kind, _states.size(), _pickups.size(), _lamps.size(), _cables.size()])


## Takes the snapshot once the frame's pending changes (spawns) are done.
func capture_deferred(snapshot_kind: String) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	capture(snapshot_kind)


## Puts the game back to the snapshot (not the clock: NightManager does
## that). Returns false if there is none.
func restore() -> bool:
	if not _taken:
		return false
	var scene := get_tree().current_scene
	if not scene:
		return false
	restoring = true

	var inventory := get_node_or_null("/root/Inventory")
	if _inventory_saved and inventory and inventory.has_method("reset_to_checkpoint"):
		inventory.reset_to_checkpoint()
	var nm := get_node_or_null("/root/NightManager")
	if nm:
		nm.generator_fuel = _night_fuel
		nm.is_generator_on = _generator_on
		if nm.has_signal("fuel_changed"):
			nm.fuel_changed.emit(nm.generator_fuel)
		if nm.has_signal("generator_state_changed"):
			nm.generator_state_changed.emit(nm.is_generator_on)
	var flashlight := _flashlight()
	if flashlight and _battery >= 0.0:
		if flashlight.has_method("set_battery_level"):
			flashlight.set_battery_level(_battery)
		elif "battery_level" in flashlight:
			flashlight.battery_level = _battery

	# The trap first (objects below may refer to it), then world items.
	for cable in get_tree().get_nodes_in_group("power_cable"):
		cable.queue_free()
	for lamp in get_tree().get_nodes_in_group("portable_trap"):
		if lamp.has_method("drop_trap"):
			lamp.queue_free()
	for node in _pickup_nodes(scene):
		node.queue_free()
	var restored_lamps: Array = []
	for entry in _lamps:
		var lamp: Node3D = _spawn(entry)
		if lamp:
			_write_state(lamp, entry.state)
			lamp.freeze = false
		restored_lamps.append(lamp)
	for entry in _pickups:
		_spawn(entry)

	for path in _states:
		var node := get_node_or_null(path)
		if node:
			_write_state(node, _states[path])
	# The outlet's live cable reference (an object) isn't in its state.
	for outlet in get_tree().get_nodes_in_group("generator_outlet"):
		if "_active_cable" in outlet:
			outlet._active_cable = null
	for entry in _cables:
		_restore_cable(entry, restored_lamps)

	for path in _states:
		var node := get_node_or_null(path)
		if node and node.has_method("_on_checkpoint_restored"):
			node._on_checkpoint_restored()
	var monologue := get_node_or_null("/root/Monologue")
	if monologue:
		monologue._had = _thoughts.duplicate()
	for path in _props:
		var prop := get_node_or_null(path) as RigidBody3D
		if prop:
			prop.global_transform = _props[path]
			prop.linear_velocity = Vector3.ZERO
			prop.angular_velocity = Vector3.ZERO
			prop.sleeping = true
	# The weather isn't part of the snapshot: it follows the story. From
	# Nest Gamma until the Day 3 wake-up it rains; otherwise it's clear.
	var weather := get_node_or_null("/root/Weather")
	var rm := get_node_or_null("/root/RoutineManager")
	if weather and weather.has_method("clear_now"):
		if rm and rm.day2_step >= 5 and not rm.is_day3_sandbox:
			weather.start_storm(0.0, true)
		else:
			weather.clear_now()
	restoring = false
	print("[Checkpoint] Restored the %s snapshot." % kind)
	return true


## The night and story flags back on NightManager (the scene was reloaded,
## so NightManager's own may be from the end of the game).
func apply_story(nm: Node) -> void:
	for flag in _story:
		nm.set(flag, _story[flag])


## GameTime's progress when the snapshot was taken.
func time_progress() -> float:
	return _time_progress


func _restore_cable(entry: Dictionary, lamps: Array) -> void:
	var outlet := get_node_or_null(entry.outlet) as Node3D
	if not outlet or not "POWER_CABLE_SCENE" in outlet:
		return
	var cable: Node = outlet.POWER_CABLE_SCENE.instantiate()
	get_tree().current_scene.add_child(cable)
	var lamp: Node = lamps[entry.lamp] if entry.lamp >= 0 and entry.lamp < lamps.size() else null
	cable.source_node = outlet
	if entry.state == 2 and lamp:
		cable.connect_to_lamp(lamp)
	else:
		cable.disconnect_cable()
		cable.queue_free()
		return
	outlet._active_cable = cable


func _spawn(entry: Dictionary) -> Node:
	var parent := get_node_or_null(entry.parent)
	if not parent:
		parent = get_tree().current_scene
	var node := _from_template(entry.template)
	if not node:
		return null
	parent.add_child(node)
	if node is Node3D:
		(node as Node3D).global_transform = entry.transform
	return node


func _state_nodes(scene: Node) -> Array[Node]:
	var found: Array[Node] = []
	for node in scene.find_children("*", "", true, false):
		var script: Script = node.get_script()
		if script and script.resource_path.get_file() in STATE_SCRIPTS:
			found.append(node)
	return found


func _pickup_nodes(scene: Node) -> Array[Node]:
	var found: Array[Node] = []
	for node in scene.find_children("*", "", true, false):
		var script: Script = node.get_script()
		var file := script.resource_path.get_file() if script else ""
		if PICKUP_SCRIPT_HINT in file and not file in PICKUP_EXCLUDED and not node.is_queued_for_deletion():
			found.append(node)
	return found


## The node's script variables of plain types (deep copies).
func _read_state(node: Object) -> Dictionary:
	var state := {}
	for property in node.get_property_list():
		if not property.usage & PROPERTY_USAGE_SCRIPT_VARIABLE:
			continue
		var value = node.get(property.name)
		if _is_plain(value):
			state[property.name] = value.duplicate(true) if value is Array or value is Dictionary else value
	return state


func _write_state(node: Object, state: Dictionary) -> void:
	for key in state:
		var value = state[key]
		node.set(key, value.duplicate(true) if value is Array or value is Dictionary else value)


func _is_plain(value) -> bool:
	match typeof(value):
		TYPE_BOOL, TYPE_INT, TYPE_FLOAT, TYPE_STRING, TYPE_STRING_NAME, TYPE_VECTOR2, TYPE_VECTOR3, TYPE_COLOR, \
		TYPE_PACKED_STRING_ARRAY, TYPE_PACKED_INT32_ARRAY, TYPE_PACKED_FLOAT32_ARRAY, TYPE_PACKED_VECTOR3_ARRAY:
			return true
		TYPE_ARRAY:
			for element in value:
				if element is Node:
					return false
			return true
		TYPE_DICTIONARY:
			for key in value:
				if key is Node or value[key] is Node:
					return false
			return true
	return false


func _flashlight() -> Node:
	var player := get_tree().get_first_node_in_group("player")
	if not player:
		return null
	for node in player.find_children("*", "", true, false):
		if node.has_method("toggle") and "battery_level" in node:
			return node
	return null


## How to make the object again: a node placed from a scene is re-instanced
## from that scene with its saved properties (a copy would also copy children
## its _ready() added at runtime); anything else is copied.
func _template(node: Node) -> Dictionary:
	if node.scene_file_path != "":
		var props := {}
		for property in node.get_property_list():
			if property.usage & PROPERTY_USAGE_STORAGE and property.name != "script":
				props[property.name] = node.get(property.name)
		return {"scene": node.scene_file_path, "props": props}
	return {"copy": node.duplicate()}


func _from_template(template: Dictionary) -> Node:
	if template.has("copy"):
		return template.copy.duplicate() if is_instance_valid(template.copy) else null
	var scene := load(template.scene) as PackedScene
	if not scene:
		return null
	var node := scene.instantiate()
	for key in template.props:
		node.set(key, template.props[key])
	return node


func _free_templates() -> void:
	for entry in _pickups + _lamps:
		if entry.template.has("copy") and is_instance_valid(entry.template.copy):
			entry.template.copy.free()
	_pickups.clear()
	_lamps.clear()
	_cables.clear()
