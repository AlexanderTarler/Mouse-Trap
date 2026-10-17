extends SceneTree
## Bakes the forest (ForestBake): loads the level as the game does, lets
## ForestDresser and FoliageBatcher dress it, and saves the result to
## res://scenes/forest_bake.res. Run it again after changing the level's tree
## groups, the template (trees_template.tscn), the painted paths, the road,
## the fence, anything the undergrowth keeps clear of, or ForestDresser. (If
## the bake no longer matches, the game dresses the forest as it starts, as
## before, and warns.)
## Run: godot --headless --path . --script res://tools/bake_forest.gd


func _initialize() -> void:
	_run()


func _run() -> void:
	ForestBake.baking = true
	ForestBake.captured = []
	await process_frame
	# As the game loads it (current_scene set before the level's _ready()s).
	change_scene_to_file("res://scenes/cottage_horror.tscn")
	for i in 10:
		await process_frame
	if ForestBake.captured.is_empty():
		push_error("[BAKE FOREST] nothing captured")
		quit(1)
		return
	# The trunks the dressing changed (by now applied), group by group: off
	# (cleared from a path), or a stump (the clear-cut).
	var trunk_changes := {}
	var groups := 0
	var changed := 0
	for batcher in root.find_children("*", "FoliageBatcher", true, false):
		if not (batcher.template and batcher.dress_forest):
			continue
		groups += 1
		var body := batcher.get_node_or_null("Trunks")
		var made: Array = batcher._template_data().trunks
		var changes := []
		if body:
			for i in body.get_child_count():
				var shape := body.get_child(i) as CollisionShape3D
				if shape.disabled != made[i].disabled or shape.shape != made[i].shape or not shape.transform.is_equal_approx(made[i].transform):
					changes.append({"index": i, "disabled": shape.disabled, "shape": shape.shape if shape.shape != made[i].shape else null, "transform": shape.transform})
		if not changes.is_empty():
			trunk_changes[ForestBake.key_of(batcher)] = changes
			changed += changes.size()
	var bake := ForestBake.capture(trunk_changes)
	var err := ResourceSaver.save(bake, ForestBake.PATH, ResourceSaver.FLAG_COMPRESS)
	var instances := 0
	for entry in bake.entries:
		for cell in entry.cells:
			instances += entry.cells[cell].size() / 12
	print("[BAKE FOREST] %s: %d groups, %d models, %d instances, %d trunks changed; inputs %d" % ["saved " + ForestBake.PATH if err == OK else "FAILED (%d)" % err,
		groups, bake.entries.size(), instances, changed, bake.inputs])
	ForestBake.baking = false
	quit(0 if err == OK else 1)
