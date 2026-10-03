extends SceneTree
## Writes SiteDresser's props into the level scene, so they can be seen and
## edited in the editor: everything it places in the barn, the wreck yard,
## the tunnel and the willow's clearing goes under a "Sites" node (with its
## colliders), the barn's doors are moved onto the doorway and opened, and
## the drums and traffic barriers that had no collider get one. From then
## on SiteDresser doesn't place anything at runtime (WorldDetails skips it
## when the level has a "Sites" node).
##
## The level is run once to let SiteDresser place everything (it needs
## physics to land things); what it did is written out (SITES_OUT: a folder)
## as sites.tscn (the new nodes) and fixes.json (the doors, the colliders
## for what's there), and tools/merge_sites.py appends them to the level's
## .tscn as text, leaving the rest of the file exactly as it was.
##
## Run: SITES_OUT=<folder> godot --headless --path . --fixed-fps 60 --script res://tools/bake_sites.gd
##      python tools/merge_sites.py <folder>
## Close (or save) the level in the editor first; reopen it afterwards.

const SCENE := "res://scenes/cottage_horror.tscn"


func _initialize() -> void:
	_run()


func _run() -> void:
	var packed: PackedScene = load(SCENE)
	if packed.instantiate().get_node_or_null("Sites"):
		print("[SITES] The level already has a \"Sites\" node: nothing to do.")
		quit(0)
		return

	# Pass 1: run it, record.
	var live: Node = packed.instantiate()
	live.get_node("Player").start_in_dev_mode = false
	root.add_child(live)
	current_scene = live
	var dresser: Node = null
	for i in 300:
		await physics_frame
		dresser = live.find_child("SiteDresser", true, false)
		if dresser and dresser.built:
			break
	if not dresser or not dresser.built:
		push_error("[SITES] SiteDresser didn't run")
		quit(1)
		return
	var props: Array = []
	for prop in dresser.get_children():
		if prop is Node3D and prop.scene_file_path != "":
			props.append({"scene": prop.scene_file_path, "xform": prop.global_transform, "name": String(prop.name),
				"colliders": _colliders_of(prop, prop)})
	var barn: Node3D = live.get_node(SiteDresser.BARN)
	var doors: Array = []
	for door_name in ["SM_EC_Barn_Door_04", "SM_EC_Barn_Door_05"]:
		var door := barn.get_node(door_name) as Node3D
		doors.append({"name": door_name, "local": barn.global_transform.affine_inverse() * door.global_transform,
			"colliders": _colliders_of(door, door)})
	var fixed: Array = []
	for body in live.find_children("SiteCollider", "StaticBody3D", true, false):
		var owner_node := body.get_parent()
		if dresser.is_ancestor_of(owner_node) or owner_node == dresser:
			continue
		fixed.append({"path": live.get_path_to(owner_node), "colliders": _colliders_of(owner_node, owner_node)})
	print("[SITES] Recorded %d props, 2 doors, %d existing props' colliders." % [props.size(), fixed.size()])
	live.queue_free()
	current_scene = null
	await process_frame

	# Pass 2: the new nodes as a scene of their own (merged into the level's
	# text by tools/merge_sites.py, so nothing else in it is touched), and
	# the fixes to what's in the level as JSON.
	var sites := Node3D.new()
	sites.name = "Sites"
	sites.add_to_group("navmesh_source", true)
	var used_names := {}
	for entry in props:
		var instance := (load(entry.scene) as PackedScene).instantiate() as Node3D
		var base: String = String(entry.scene).get_file().get_basename()
		used_names[base] = used_names.get(base, 0) + 1
		instance.name = base if used_names[base] == 1 else "%s_%d" % [base, used_names[base]]
		sites.add_child(instance)
		instance.owner = sites
		instance.transform = entry.xform
		_add_colliders(instance, entry.colliders, sites)
	var out := PackedScene.new()
	var err := out.pack(sites)
	var out_dir := OS.get_environment("SITES_OUT")
	if err == OK:
		err = ResourceSaver.save(out, out_dir.path_join("sites.tscn"))
	var fixes := {"doors": [], "colliders": []}
	for entry in doors:
		fixes.doors.append({"name": entry.name, "transform": _t(entry.local), "colliders": _boxes(entry.colliders)})
	for entry in fixed:
		fixes.colliders.append({"path": String(entry.path), "colliders": _boxes(entry.colliders)})
	var file := FileAccess.open(out_dir.path_join("fixes.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(fixes, "  "))
	file.close()
	print("[SITES] Wrote %d props and the fixes to %s (%s)." % [props.size(), out_dir, error_string(err)])
	sites.free()
	quit(0 if err == OK else 1)


## A Transform3D as the 12 numbers a .tscn writes (the basis row by row).
func _t(x: Transform3D) -> Array:
	var b := x.basis
	return [b.x.x, b.y.x, b.z.x, b.x.y, b.y.y, b.z.y, b.x.z, b.y.z, b.z.z, x.origin.x, x.origin.y, x.origin.z]


func _boxes(colliders: Array) -> Array:
	var out: Array = []
	for c in colliders:
		out.append({"body": c.body, "transform": _t(c.xform), "size": [c.size.x, c.size.y, c.size.z]})
	return out


## The box colliders SiteDresser added under `node`: [{xform (relative to
## `node`), size}].
func _colliders_of(node: Node, relative_to: Node) -> Array:
	var found: Array = []
	for body in node.find_children("*", "StaticBody3D", true, false):
		if body.name != "SiteCollider" and body.name != "DoorCollider":
			continue
		for shape in body.find_children("*", "CollisionShape3D", false, false):
			var box := (shape as CollisionShape3D).shape as BoxShape3D
			if box:
				found.append({"xform": (relative_to as Node3D).global_transform.affine_inverse() * (shape as Node3D).global_transform,
					"size": box.size, "body": String(body.name)})
	return found


func _add_colliders(node: Node, colliders: Array, level: Node) -> void:
	for entry in colliders:
		var body := StaticBody3D.new()
		body.name = entry.body
		node.add_child(body)
		body.owner = level
		var shape := CollisionShape3D.new()
		shape.name = "CollisionShape3D"
		var box := BoxShape3D.new()
		box.size = entry.size
		shape.shape = box
		shape.transform = entry.xform
		body.add_child(shape)
		shape.owner = level
