extends SceneTree
## A fingerprint of the forest as the level builds it: the undergrowth and
## stones placed, the trees cleared, the batches drawn (count, instances, a
## hash of every instance's mesh and transform), and the tree trunks' colliders
## (where, on or off). Compare before and after a change that must leave the
## forest as it was. Also times loading and readying the level.
## Run: godot --headless --path . --script res://tools/forest_fingerprint.gd [-- dressed] [<batch list file>]


func _initialize() -> void:
	_run()


func _run() -> void:
	await process_frame
	var args := OS.get_cmdline_user_args()
	# "dressed": the forest dressed as the level starts, even with a bake.
	ForestBake.baking = args.has("dressed")
	var t := Time.get_ticks_msec()
	var packed := load("res://scenes/cottage_horror.tscn") as PackedScene
	var t_load := Time.get_ticks_msec() - t
	t = Time.get_ticks_msec()
	var scene := packed.instantiate()
	var t_inst := Time.get_ticks_msec() - t
	t = Time.get_ticks_msec()
	# (As the game does: the level is the current scene before it's ready.)
	root.add_child(scene)
	current_scene = scene
	var t_ready := Time.get_ticks_msec() - t
	t = Time.get_ticks_msec()
	await process_frame
	var t_frame := Time.get_ticks_msec() - t
	for i in 3:
		await process_frame
	var h := 0
	for p in ForestDresser.undergrowth_spots:
		h = hash([h, p.snapped(Vector3.ONE * 0.001)])
	for p in ForestDresser.stone_spots:
		h = hash([h, p.snapped(Vector4.ONE * 0.001)])
	# The forest's batches (by name: model and cell), instance by instance.
	var batches := 0
	var instances := 0
	var batch_hash := 0
	var holder := scene.find_child("ForestBatches", true, false)
	var names := []
	var lines := []
	# (Not by name: names that clash get numbers that depend on how many
	# nodes were made before.)
	var cell_hashes := []
	if holder:
		for b in holder.get_children():
			names.append(b.name)
		names.sort()
		for n in names:
			var mmi := holder.get_node(NodePath(n)) as MultiMeshInstance3D
			batches += 1
			instances += mmi.multimesh.instance_count
			var cell_hash := hash([mmi.position.snapped(Vector3.ONE * 0.001), mmi.multimesh.instance_count, mmi.cast_shadow, mmi.visibility_range_end, mmi.multimesh.mesh.get_surface_count()])
			for i in mmi.multimesh.instance_count:
				var x := mmi.multimesh.get_instance_transform(i)
				cell_hash = hash([cell_hash, x.origin.snapped(Vector3.ONE * 0.001), x.basis.x.snapped(Vector3.ONE * 0.001), x.basis.y.snapped(Vector3.ONE * 0.001)])
			cell_hashes.append(cell_hash)
			lines.append("%s %d %d %.1f %s %d" % [n, mmi.multimesh.instance_count, mmi.cast_shadow, mmi.visibility_range_end, mmi.multimesh.mesh.resource_name, cell_hash])
	cell_hashes.sort()
	batch_hash = hash(cell_hashes)
	# The trunks.
	var trunks := []
	for group in scene.find_children("Group of Trees*", "", true, false):
		for shape in group.find_children("*", "CollisionShape3D", true, false):
			var at := (shape as Node3D).global_transform
			trunks.append("%s %s %s %d" % [at.origin.snapped(Vector3.ONE * 0.001), at.basis.get_scale().snapped(Vector3.ONE * 0.001), (shape as CollisionShape3D).disabled, (shape.get_parent() as CollisionObject3D).collision_layer])
	trunks.sort()
	var other := 0
	for group in scene.find_children("Group of Trees*", "", true, false):
		other += group.find_children("*", "MultiMeshInstance3D", true, false).size()
	var dump := Array(args).filter(func(a): return a != "dressed")
	if dump.size() > 0:
		var file := FileAccess.open(dump[0], FileAccess.WRITE)
		file.store_string("
".join(lines))
		file.close()
	print("[FOREST] undergrowth %d stones %d cleared %d spots hash %d" % [ForestDresser.undergrowth_spots.size(), ForestDresser.stone_spots.size(), ForestDresser.trees_cleared, h])
	print("[FOREST] batches %d instances %d batch hash %d" % [batches, instances, batch_hash])
	print("[FOREST] trunks %d (off %d) hash %d; grass multimeshes in groups %d" % [trunks.size(), trunks.filter(func(s): return " true " in s).size(), hash(trunks), other])
	print("[FOREST] baked forest used: %s" % ForestBake.last_used)
	print("[FOREST] load %d ms, instantiate %d ms, ready %d ms, first frame %d ms; nodes in the level %d" % [t_load, t_inst, t_ready, t_frame, scene.find_children("*", "", true, false).size()])
	scene.queue_free()
	await process_frame
	quit()
