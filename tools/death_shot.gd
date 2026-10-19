extends SceneTree
## Screenshots of the death cutscene (EndgameCinematics.play_death, the full
## one) at night, to tune its camera by eye, and the cutscene's camera
## checked against the world each frame: anything solid within 0.25 m of it
## (the willow's trunk...) is printed. Renders, so run WITHOUT --headless.
##   godot --path . --resolution 1280x720 --script res://tools/death_shot.gd -- <out_prefix>
## Writes <out_prefix>_<seconds>.png.

const SHOTS := [2.5, 4.5, 6.5, 7.4, 7.8, 8.1, 8.4, 8.7, 9.0, 9.6]


func _initialize() -> void:
	_go()


func _go() -> void:
	var out: String = OS.get_cmdline_user_args()[0] if OS.get_cmdline_user_args().size() > 0 else "user://death"
	var s = load("res://scenes/cottage_horror.tscn").instantiate()
	s.get_node("Player").start_in_dev_mode = false
	s.get_node("Player").dev_start = DevStart.Start.DAY_1   # (no opening)
	root.add_child(s)
	current_scene = s
	for i in 60:
		await process_frame
	var gt = root.get_node("GameTime")
	var nm = root.get_node("NightManager")
	var ec = get_first_node_in_group("environment_controller")
	nm.current_night = 3
	gt.is_time_paused = true
	gt.cycle_progress = 0.75
	gt._elapsed = 0.75 * gt.cycle_duration
	gt.is_day = false
	gt.time_changed.emit(0.75)
	ec._on_game_time_changed(0.75, true)
	for i in 30:
		await process_frame
	var cinematics: Node = get_first_node_in_group("cinematics")
	root.get_node("EndgameManager").death_cutscenes_seen = 0
	cinematics.play_death()
	var space: PhysicsDirectSpaceState3D = s.get_world_3d().direct_space_state
	var probe := PhysicsShapeQueryParameters3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 0.25
	probe.shape = sphere
	probe.collision_mask = 1
	var player: Node3D = get_first_node_in_group("player")
	probe.exclude = [player.get_rid()]
	var next := 0
	var last_hit := ""
	var frames_left := 60 * 60
	while cinematics.is_playing() and next < SHOTS.size() and frames_left > 0:
		frames_left -= 1
		await process_frame
		var cam: Camera3D = root.get_viewport().get_camera_3d()
		probe.transform = Transform3D(Basis.IDENTITY, cam.global_position)
		var hits := space.intersect_shape(probe, 8)
		var names := ", ".join(hits.map(func(h): return str(h.collider.name)))
		if names != last_hit:
			print("[DEATH SHOT] %.2f s  camera %s  touching: %s" % [cinematics._clock, cam.global_position.snapped(Vector3.ONE * 0.01), names if names != "" else "nothing"])
			last_hit = names
		if cinematics._clock >= SHOTS[next]:
			var path := "%s_%.1f.png" % [out, SHOTS[next]]
			root.get_viewport().get_texture().get_image().save_png(path)
			print("[DEATH SHOT] %s  (camera %s, ground %.2f below)" % [path, cam.global_position.snapped(Vector3.ONE * 0.01), cam.global_position.y - cinematics._ground_y(cam.global_position)])
			next += 1
	quit()
