extends SceneTree
## The tree groups made from their template, and the forest baked ahead of
## time (FoliageBatcher, ForestBake, tools/bake_forest.gd).
##   - a group is one node in the level; its trees come from
##     trees_template.tscn: trunks (one body), the log's collider, its grass
##   - the level draws its forest from the bake when the bake matches it
##   - the bake stops matching (and the forest is dressed as the level starts)
##     when what it was made from changes: a group moved, say
##
## Run: godot --headless --path . --fixed-fps 60 --script res://tests/forest_bake_test.gd

var _failures := 0


func _initialize() -> void:
	_run()


func _frames(n: int) -> void:
	for i in n:
		await physics_frame


func _check(label: String, ok: bool, detail: String = "") -> void:
	if not ok:
		_failures += 1
	print("[FOREST TEST] %s  %s%s" % ["PASS" if ok else "FAIL", label, ("  (" + detail + ")") if detail != "" else ""])


func _run() -> void:
	await _frames(2)
	var group_scene := load("res://scenes/trees.tscn") as PackedScene
	var state := group_scene.get_state()
	_check("a tree group is one node in the level, its trees in the template", state.get_node_count() == 1 and ResourceLoader.exists("res://scenes/trees_template.tscn"), "%d nodes" % state.get_node_count())

	var scene: Node = load("res://scenes/cottage_horror.tscn").instantiate()
	scene.get_node("Player").start_in_dev_mode = false
	root.add_child(scene)
	current_scene = scene
	await _frames(10)
	var groups := scene.find_children("Group of Trees*", "", true, false)
	var group: Node = groups[0]
	var trunks: Node = group.get_node_or_null("Trunks")
	var props: Node = group.get_node_or_null("Props")
	var grass := group.find_children("*", "MultiMeshInstance3D", false, false)
	_check("each group gets its trunks (one body), the log's collider and its grass from the template",
		groups.size() == 147 and trunks is StaticBody3D and trunks.get_child_count() == 69 and props != null and props.get_child_count() == 1 and grass.size() == 2,
		"%d groups, %d trunks, grass %d" % [groups.size(), trunks.get_child_count() if trunks else 0, grass.size()])
	var off := 0
	for g in groups:
		for shape in g.get_node("Trunks").get_children():
			if shape.disabled:
				off += 1
	_check("the forest came from the bake: batches, undergrowth, the trunks cleared off the paths (%d)" % off,
		ForestBake.last_used and scene.find_child("ForestBatches", true, false) != null and ForestDresser.undergrowth_spots.size() > 10000
		and off == ForestDresser.trees_cleared and off > 0)
	# What it was made from, changed: no longer matches.
	var before := ForestBake.inputs_hash(group)
	(group as Node3D).position.x += 1.0
	var moved := ForestBake.inputs_hash(group)
	(group as Node3D).position.x -= 1.0
	var back := ForestBake.inputs_hash(group)
	# (Matched as the level started: used above. Things lying about have
	# settled since, so only the change is compared here.)
	_check("the bake stops matching when a group moves", moved != before and back == before)

	print("[FOREST TEST] %s" % ("ALL PASSED" if _failures == 0 else "%d FAILED" % _failures))
	scene.queue_free()
	await _frames(2)
	quit(1 if _failures > 0 else 0)
