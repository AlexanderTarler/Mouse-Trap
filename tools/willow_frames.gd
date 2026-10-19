extends SceneTree
## Walks the player up to the willow (by day, then by night) and prints every
## frame that took long (with how far from the tree it was), to find what
## freezes the game there. Renders, so run WITHOUT --headless.
##   godot --path . --resolution 1280x720 --script res://tools/willow_frames.gd

const WILLOW := Vector3(103.0, 0.0, 85.3)
const FROM := Vector3(70.0, 0.0, 60.0)
const SLOW_MS := 60.0


func _initialize() -> void:
	_go()


func _go() -> void:
	var s = load("res://scenes/cottage_horror.tscn").instantiate()
	s.get_node("Player").start_in_dev_mode = false
	s.get_node("Player").dev_start = DevStart.Start.DAY_1   # (no opening)
	root.add_child(s)
	current_scene = s
	for i in 90:
		await process_frame
	var gt = root.get_node("GameTime")
	var player: CharacterBody3D = get_first_node_in_group("player")
	for e in get_nodes_in_group("entity"):
		e.can_kill = false
	for run in [["day", 0.3], ["night", 0.75]]:
		gt.is_time_paused = true
		gt.cycle_progress = run[1]
		gt._elapsed = run[1] * gt.cycle_duration
		gt.is_day = run[1] < 0.5
		gt.time_changed.emit(run[1])
		var ec = get_first_node_in_group("environment_controller")
		ec._on_game_time_changed(run[1], true)
		if run[0] == "night":
			root.get_node("NightManager").start_night(3)
		player.global_position = FROM + Vector3.UP
		for i in 30:
			await process_frame
		# Walking (holding W), facing the tree, from 30 m out.
		var start := WILLOW + (FROM - WILLOW).normalized() * 30.0
		start.y = 1.0
		player.global_position = start
		var to_tree := WILLOW - start
		player.rotation.y = atan2(-to_tree.x, -to_tree.z)
		await process_frame
		var key := InputEventKey.new()
		key.keycode = KEY_W
		key.physical_keycode = KEY_W
		key.pressed = true
		Input.parse_input_event(key)
		var last := Time.get_ticks_usec()
		var worst := 0.0
		for i in 60 * 14:
			await process_frame
			var now := Time.get_ticks_usec()
			var ms := (now - last) / 1000.0
			last = now
			worst = maxf(worst, ms)
			var at := player.global_position
			# (If the key doesn't move it, walk it: 3 m/s towards the tree.)
			if i > 30 and Vector2(player.velocity.x, player.velocity.z).length() < 0.5:
				player.global_position += Vector3(to_tree.x, 0.0, to_tree.z).normalized() * 3.0 / 60.0
			if ms > SLOW_MS:
				print("[WILLOW %s] %.0f ms at %.1f m from the tree" % [run[0], ms, Vector2(at.x - WILLOW.x, at.z - WILLOW.z).length()])
			if Vector2(at.x - WILLOW.x, at.z - WILLOW.z).length() < 1.5:
				break
		key = key.duplicate()
		key.pressed = false
		Input.parse_input_event(key)
		print("[WILLOW %s] reached %.1f m from the tree" % [run[0], Vector2(player.global_position.x - WILLOW.x, player.global_position.z - WILLOW.z).length()])
		print("[WILLOW %s] worst frame %.0f ms" % [run[0], worst])
		player.global_position = Vector3(10.0, 1.0, 0.0)
		for i in 60:
			await process_frame
	quit()
