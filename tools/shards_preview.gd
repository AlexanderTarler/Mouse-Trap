extends SceneTree
## Renders the glass on the floor under a broken window (the one broken from
## the start), from inside the room, and prints where the shards lie.
## Run (windowed): godot --path . --rendering-method gl_compatibility --script res://tools/shards_preview.gd -- <out.png>


func _initialize() -> void:
	_run()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var out: String = args[0] if args.size() > 0 else "user://shards.png"
	SaveGame.path = "user://shards_preview_save.dat"
	var scene: Node = load("res://scenes/cottage_horror.tscn").instantiate()
	scene.get_node("Player").start_in_dev_mode = false
	root.add_child(scene)
	current_scene = scene
	for i in 120:
		await physics_frame
	var window: Node3D = null
	for w in get_nodes_in_group("WindowMarkers"):
		if "start_broken" in w and w.start_broken:
			window = w
	var shards: MeshInstance3D = window.get_node_or_null("FloorShards")
	print("[SHARDS] window %s at %s, shards %s, aabb %s" % [window.name, window.global_position, shards != null, shards.global_transform * shards.get_aabb() if shards else ""])
	for opening in get_nodes_in_group("opening"):
		opening.queue_free()
	# Daylight in the room, the camera inside looking down at the sill.
	var player := get_first_node_in_group("player") as Node3D
	player.set_physics_process(false)
	player.set_process(false)
	var cam := Camera3D.new()
	scene.add_child(cam)
	var inward := window.global_basis.z.normalized()
	var floor_at := window.global_position + inward * 0.4
	floor_at.y = (shards.global_transform * shards.get_aabb()).position.y if shards else window.global_position.y - 1.7
	cam.look_at_from_position(floor_at + inward * 1.6 + Vector3.UP * 1.2, floor_at)
	cam.current = true
	cam.fov = 60.0
	for i in 30:
		await process_frame
	root.get_texture().get_image().save_png(out)
	print("[SHARDS] saved ", out)
	quit()
