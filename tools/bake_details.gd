extends SceneTree
## Writes the details SiteDresser adds at runtime (the level already has the
## barn's and the other sites' in "Sites") into the level, so they can be seen
## and moved in the editor:
##   "CabinDetails"  - in and around the cabin (the loose things as
##                     KnockableProps, with their models and colliders)
##   "ForestDetails" - the trails' logs, stumps and rocks, the survey stakes,
##                     the boulders, the clear-cut's pile
## From then on SiteDresser doesn't add them (WorldDetails skips it when the
## level has "CabinDetails").
##
## The level is run once so SiteDresser places everything (it needs physics
## to land things); what it placed is saved (DETAILS_OUT: a folder) as
## CabinDetails.tscn and ForestDetails.tscn, and tools/merge_details.py
## appends them to the level's .tscn as text, leaving the rest of the file as
## it was.
##
## Run: DETAILS_OUT=<folder> godot --headless --path . --fixed-fps 60 --script res://tools/bake_details.gd
##      python tools/merge_details.py <folder>
## Close the level in the editor first; reopen it afterwards.

const SCENE := "res://scenes/cottage_horror.tscn"
const CABIN := Vector3(9.0, 0.0, 15.0)
## Within this of the cabin: CabinDetails; further: ForestDetails.
const CABIN_REACH := 30.0


func _initialize() -> void:
	_run()


func _run() -> void:
	var packed: PackedScene = load(SCENE)
	var probe := packed.instantiate()
	var already := probe.get_node_or_null("CabinDetails") != null
	probe.free()
	if already:
		print("[DETAILS] The level already has a \"CabinDetails\" node: nothing to do.")
		quit(0)
		return
	var out_dir := OS.get_environment("DETAILS_OUT")
	if out_dir == "":
		push_error("[DETAILS] Set DETAILS_OUT to a folder.")
		quit(1)
		return

	var live: Node = packed.instantiate()
	live.get_node("Player").start_in_dev_mode = false
	root.add_child(live)
	current_scene = live
	var dresser: Node = null
	for i in 900:
		await physics_frame
		dresser = live.find_child("SiteDresser", true, false)
		if dresser and dresser.built:
			break
	if not dresser or not dresser.built:
		push_error("[DETAILS] SiteDresser didn't run")
		quit(1)
		return
	# (A moment for anything loose to settle where it was put.)
	for i in 30:
		await physics_frame

	var groups := {"CabinDetails": Node3D.new(), "ForestDetails": Node3D.new()}
	for group_name in groups:
		groups[group_name].name = group_name
		groups[group_name].add_to_group("navmesh_source", true)
	var used := {}
	for prop in dresser.get_children():
		if not prop is Node3D:
			continue
		var xform: Transform3D = (prop as Node3D).global_transform
		var near_cabin := Vector2(xform.origin.x - CABIN.x, xform.origin.z - CABIN.z).length() < CABIN_REACH
		var target: Node3D = groups["CabinDetails" if near_cabin else "ForestDetails"]
		var copy := prop.duplicate() as Node3D
		var base := _base_name(prop)
		used[base] = used.get(base, 0) + 1
		copy.name = base if used[base] == 1 else "%s_%d" % [base, used[base]]
		target.add_child(copy)
		copy.transform = xform
		_own(copy, target)
	var counts := []
	var err := OK
	for group_name in groups:
		var group: Node3D = groups[group_name]
		var scene := PackedScene.new()
		err = scene.pack(group)
		if err == OK:
			err = ResourceSaver.save(scene, out_dir.path_join(group_name + ".tscn"))
		counts.append("%s %d" % [group_name, group.get_child_count()])
		group.free()
	print("[DETAILS] Wrote %s to %s (%s)." % [", ".join(counts), out_dir, error_string(err)])
	quit(0 if err == OK else 1)


## A readable name: the model's file name (a loose prop's, its model's).
func _base_name(prop: Node) -> String:
	var path := prop.scene_file_path
	if prop is KnockableProp and prop.get_node_or_null("Model"):
		path = prop.get_node("Model").scene_file_path
		return path.get_file().get_basename() if path != "" else "LooseProp"
	if path != "":
		return path.get_file().get_basename()
	return String(prop.name).trim_prefix("@").get_slice("@", 0) if not String(prop.name).begins_with("@") else "Detail"


## Saves with `owner`: every node made in code (owner none) under `node`;
## the insides of instanced scenes keep their own.
func _own(node: Node, owner_node: Node) -> void:
	if node.owner == null:
		node.owner = owner_node
	var counts := {}
	for child in node.get_children():
		# Names made up by the engine ("@MeshInstance3D@12", "_Collision..."):
		# what it is, numbered.
		var label := String(child.name)
		if label.begins_with("@") or label.begins_with("_"):
			var kind := child.get_class()
			counts[kind] = counts.get(kind, 0) + 1
			child.name = kind if counts[kind] == 1 else "%s%d" % [kind, counts[kind]]
		_own(child, owner_node)
