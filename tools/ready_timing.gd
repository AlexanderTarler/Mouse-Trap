extends SceneTree
## Which of the level's top nodes take long to get ready: adds them one by one
## (in order) and times each. (Approximate: a node that needs a later sibling
## at its _ready() may complain.)
## Run: godot --headless --path . --script res://tools/ready_timing.gd [-- <node path>]


func _initialize() -> void:
	_run()


func _run() -> void:
	await process_frame
	var scene := (load("res://scenes/cottage_horror.tscn") as PackedScene).instantiate()
	# (A path in the level: its children instead: -- "Details/Outside Cabin")
	var args := OS.get_cmdline_user_args()
	var parent: Node = scene.get_node(args[0]) if args.size() > 0 else scene
	var children := parent.get_children()
	var owners := {}
	for child in children:
		_remember_owners(child, scene, owners)
		parent.remove_child(child)
	root.add_child(scene)
	current_scene = scene
	var times := []
	for child in children:
		var t := Time.get_ticks_usec()
		parent.add_child(child)
		for node in owners:
			if node == child or child.is_ancestor_of(node):
				node.owner = scene
		times.append([(Time.get_ticks_usec() - t) / 1000.0, child.name])
	times.sort_custom(func(a, b): return a[0] > b[0])
	for entry in times.slice(0, 15):
		print("[READY TIMING] %7.1f ms  %s" % [entry[0], entry[1]])
	var t2 := Time.get_ticks_usec()
	await process_frame
	print("[READY TIMING] first frame %.1f ms" % ((Time.get_ticks_usec() - t2) / 1000.0))
	quit()


func _remember_owners(node: Node, scene: Node, owners: Dictionary) -> void:
	if node.owner == scene:
		owners[node] = true
	for child in node.get_children():
		_remember_owners(child, scene, owners)
