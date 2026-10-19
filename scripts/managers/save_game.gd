class_name SaveGame
extends RefCounted
## The last checkpoint on disk (user://savegame.dat), for the main menu's
## "Continue": the start of the day or night the player last reached.
##
## Checkpoint.capture() writes it (once a game was started from the main
## menu: Checkpoint.save_to_disk); Continue reads it back into Checkpoint and
## loads the game scene, which NightManager then restores as "Play Again"
## does. On top of the checkpoint it keeps what a fresh start would lose:
## the managers' state (TutorialManager's learned hints, the Night 2 story,
## the peekers, the endgame) and the player's own (the flashlight, sprint,
## exhaustion).
##
## Values are kept as Godot's own (store_var); resources as their file path,
## or (made at runtime, like the inventory's item copies) as their script and
## properties.

## (Tests point it elsewhere.)
static var path := "user://savegame.dat"
const VERSION := 1
## Managers kept (GameReset.MANAGERS without the ones the checkpoint itself
## covers or that run the restore).
const MANAGERS := ["TutorialManager", "NightTwoStory", "PeekerManager", "EndgameManager"]
const PLAYER_VARS := ["_has_flashlight", "sprint_unlocked", "is_exhausted"]


static func exists() -> bool:
	return FileAccess.file_exists(path)


static func delete() -> void:
	if exists():
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


## "Day 2" / "Night 1": where Continue would start (for the menu).
static func describe() -> String:
	var data := _read()
	if data.is_empty():
		return ""
	var night := int(data.get("story", {}).get("current_night", 0))
	# (As the HUD names it: RoutineManager.get_current_day_string.)
	if data.get("kind") == "night":
		return "Night %d" % maxi(night, 1)
	return "Day %d" % (1 if night <= 0 else maxi(night, 2))


## Writes the checkpoint just taken.
static func write(checkpoint: Node) -> void:
	var tree := checkpoint.get_tree()
	var managers := {}
	for manager in MANAGERS:
		var node := tree.root.get_node_or_null(manager)
		if node:
			managers[manager] = encode(checkpoint._read_state(node))
	var player := {}
	var player_node := tree.get_first_node_in_group("player")
	if player_node:
		for property in PLAYER_VARS:
			if property in player_node:
				player[property] = player_node.get(property)
	# Saved on leaving: where the player stands (Checkpoint.capture_on_quit).
	if checkpoint.tag == "quit" and player_node is Node3D:
		player["$at"] = (player_node as Node3D).global_transform
	var inventory: Array = []
	var inventory_node := tree.root.get_node_or_null("Inventory")
	if inventory_node and "_checkpoint_items" in inventory_node:
		for item in inventory_node._checkpoint_items:
			inventory.append(encode(item))
	var states := {}
	for node_path in checkpoint._states:
		# (Encoded: a scrap heap's contents hold item resources, which
		# store_var would keep only as object IDs, meaningless next launch.)
		states[String(node_path)] = encode(checkpoint._states[node_path])
	var props := {}
	for node_path in checkpoint._props:
		props[String(node_path)] = checkpoint._props[node_path]
	var data := {
		"version": VERSION,
		"game_version": game_version(),
		"saved": Time.get_unix_time_from_system(),
		"kind": checkpoint.kind,
		"tag": checkpoint.tag,
		"fuel": checkpoint._night_fuel,
		"generator_on": checkpoint._generator_on,
		"time": checkpoint._time_progress,
		"battery": checkpoint._battery,
		"story": checkpoint._story,
		"thoughts": checkpoint._thoughts,
		"states": states,
		"props": props,
		"pickups": checkpoint._pickups.map(func(e): return _encode_entry(e)),
		"lamps": checkpoint._lamps.map(func(e): return _encode_entry(e)),
		"cables": checkpoint._cables.map(func(c): return {"outlet": String(c.outlet), "lamp": c.lamp, "state": c.state}),
		"inventory": inventory,
		"managers": managers,
		"player": player,
	}
	var file := FileAccess.open(path, FileAccess.WRITE)
	if not file:
		push_warning("[SaveGame] Can't write %s." % path)
		return
	file.store_var(data)
	file.close()
	print("[SaveGame] Saved the %s checkpoint." % checkpoint.kind)


## Reads the save into Checkpoint, ready for the game scene to restore it
## (restore_on_load). False if there's none or it can't be read.
static func read_into(checkpoint: Node) -> bool:
	var data := _read()
	if data.is_empty():
		return false
	checkpoint._free_templates()
	checkpoint._states.clear()
	checkpoint._props.clear()
	checkpoint.kind = data.kind
	checkpoint.tag = data.tag
	checkpoint._night_fuel = data.fuel
	checkpoint._generator_on = data.generator_on
	checkpoint._time_progress = data.time
	checkpoint._battery = data.battery
	checkpoint._story = data.story
	checkpoint._thoughts = data.thoughts
	for node_path in data.states:
		checkpoint._states[NodePath(node_path)] = _decode_state(data.states[node_path])
	for node_path in data.props:
		checkpoint._props[NodePath(node_path)] = data.props[node_path]
	for entry in data.pickups:
		checkpoint._pickups.append(_decode_entry(entry))
	for entry in data.lamps:
		checkpoint._lamps.append(_decode_entry(entry))
	for cable in data.cables:
		checkpoint._cables.append({"outlet": NodePath(cable.outlet), "lamp": cable.lamp, "state": cable.state})
	var inventory := checkpoint.get_node_or_null("/root/Inventory")
	if inventory and "_checkpoint_items" in inventory:
		var items: Array = []
		for item in data.inventory:
			items.append(decode(item))
		inventory._checkpoint_items = items
		checkpoint._inventory_saved = true
	# The managers now (before the scene: they set it up), the player's own
	# once it's restored (Checkpoint.apply_saved_player).
	for manager in data.managers:
		var node := checkpoint.get_node_or_null("/root/" + manager)
		if node:
			checkpoint._write_state(node, _decode_state(data.managers[manager]))
	checkpoint.saved_player = data.player
	checkpoint._taken = true
	checkpoint.restore_on_load = true
	return true


## A node's saved state, decoded. A value that held objects saved as bare
## IDs (saves from before they were encoded) is left out: the fresh level's
## own value stays (a scrap heap's contents, not a list of nulls).
static func _decode_state(state: Dictionary) -> Dictionary:
	var out := {}
	for key in state:
		if _lost_objects(state[key]):
			continue
		out[key] = decode(state[key])
	return out


static func _lost_objects(value: Variant) -> bool:
	if value is EncodedObjectAsID:
		return true
	if value is Array:
		for element in value:
			if _lost_objects(element):
				return true
	elif value is Dictionary:
		for key in value:
			if _lost_objects(value[key]):
				return true
	return false


static func _read() -> Dictionary:
	if not exists():
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if not file:
		return {}
	var data = file.get_var()
	file.close()
	if not data is Dictionary or int(data.get("version", 0)) != VERSION:
		return {}
	# Saved by another version of the game: its level may have changed (things
	# moved or renamed), so it's not restored onto it.
	if str(data.get("game_version", "")) != game_version():
		return {}
	return data


## The game's version (Project Settings > Application > Config > Version):
## raise it with every upload.
static func game_version() -> String:
	return str(ProjectSettings.get_setting("application/config/version", ""))


## A world item or lamp: placed from a scene (its scene and properties), or
## part of the level (its path: the fresh level has it).
static func _encode_entry(entry: Dictionary) -> Dictionary:
	var out := {"parent": String(entry.parent), "transform": entry.transform}
	if entry.has("state"):
		out["state"] = entry.state
	if entry.template.has("scene"):
		out["scene"] = entry.template.scene
		out["props"] = encode(entry.template.props)
	else:
		out["node"] = String(entry.get("path", NodePath()))
	return out


static func _decode_entry(entry: Dictionary) -> Dictionary:
	var out := {"parent": NodePath(entry.parent), "transform": entry.transform}
	if entry.has("state"):
		out["state"] = entry.state
	if entry.has("scene"):
		out["template"] = {"scene": entry.scene, "props": decode(entry.props)}
	else:
		out["template"] = {"node": NodePath(entry.node)}
		out["path"] = NodePath(entry.node)
	return out


## A value as plain data: resources from files as their path, others as
## their script (or class) and stored properties; nodes are dropped.
static func encode(value: Variant) -> Variant:
	if value is Node:
		return null
	if value is Resource:
		var resource := value as Resource
		if resource.resource_path != "" and not "::" in resource.resource_path:
			return {"$res": resource.resource_path}
		var props := {}
		for property in resource.get_property_list():
			if property.usage & PROPERTY_USAGE_STORAGE and not property.name in ["script", "resource_path", "resource_name", "resource_local_to_scene"]:
				props[property.name] = encode(resource.get(property.name))
		var script: Script = resource.get_script()
		return {"$obj": script.resource_path if script else resource.get_class(), "props": props}
	if value is Object:
		return null
	if value is Array:
		return (value as Array).map(func(v): return encode(v))
	if value is Dictionary:
		var out := {}
		for key in value:
			out[key] = encode(value[key])
		return out
	return value


static func decode(value: Variant) -> Variant:
	if value is Dictionary:
		if value.has("$res"):
			return load(value["$res"]) if ResourceLoader.exists(value["$res"]) else null
		if value.has("$obj"):
			var kind: String = value["$obj"]
			var resource: Object = null
			if kind.begins_with("res://"):
				var script := load(kind) as Script
				resource = script.new() if script else null
			elif ClassDB.can_instantiate(kind):
				resource = ClassDB.instantiate(kind)
			if resource:
				for key in value.props:
					resource.set(key, decode(value.props[key]))
			return resource
		var out := {}
		for key in value:
			out[key] = decode(value[key])
		return out
	if value is Array:
		return (value as Array).map(func(v): return decode(v))
	return value
