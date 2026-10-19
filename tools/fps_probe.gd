extends SceneTree
## Frame rate in the level by day and at night (a rough check; not headless).
## Run: godot --path . [--rendering-method gl_compatibility] --script res://tools/fps_probe.gd
func _initialize():
	_go()
func _go():
	SaveGame.path = "user://fps_probe_save.dat"
	var scene: Node = load("res://scenes/cottage_horror.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	for i in 240:
		await process_frame
	for o in get_nodes_in_group("opening"):
		o.queue_free()
	var player := get_first_node_in_group("player") as Node3D
	var out := ""
	for spot in [["yard, day", Vector3(9, 1, -2), 0.3], ["forest, day", Vector3(-30, 1, -40), 0.3], ["yard, night", Vector3(9, 1, -2), 0.75], ["inside, night", Vector3(6.9, 1.5, 16), 0.75]]:
		player.global_position = spot[1]
		root.get_node("GameTime").cycle_progress = spot[2]
		for i in 90:
			await process_frame
		var t := Time.get_ticks_usec()
		var frames := 0
		var worst := 0
		var last := t
		while Time.get_ticks_usec() - t < 3000000:
			await process_frame
			var now := Time.get_ticks_usec()
			worst = maxi(worst, now - last)
			last = now
			frames += 1
		out += "%s: %.0f fps (worst frame %d ms)   " % [spot[0], frames / 3.0, worst / 1000]
	print("[FPS] ", RenderingServer.get_video_adapter_name(), " | ", out)
	SaveGame.delete()
	quit()
