extends SceneTree
## Screenshots of the night, to tune its darkness by eye (Night 2 and 3, the
## yard and the cabin): renders, so run WITHOUT --headless. Writes
## <out_prefix>_n<night>_<view>.png and prints each one's mean luminance.
##   godot --path . --resolution 1280x720 --script res://tools/night_shot.gd -- <out_prefix>
## Env overrides for trying values: NIGHT_DENSITY (ground fog density),
## NIGHT_FOG_LIGHT (distance fog colour), EC_SET="name=value;..." (any
## EnvironmentController number). Add --rendering-method gl_compatibility
## to see the web build's renderer. Night 2 comes out at dusk (the
## NightManager restarts that night at 00:00); Night 3 is the one to look at.
func _initialize() -> void:
	_go()
func _go() -> void:
	var out: String = OS.get_cmdline_user_args()[0] if OS.get_cmdline_user_args().size() > 0 else "user://night"
	var s = load("res://scenes/cottage_horror.tscn").instantiate()
	s.get_node("Player").start_in_dev_mode = false
	root.add_child(s)
	current_scene = s
	for i in 30:
		await process_frame
	var gt = root.get_node("GameTime")
	var nm = root.get_node("NightManager")
	var ec = get_first_node_in_group("environment_controller")
	for e in get_nodes_in_group("entity"):
		e.deactivate()
	var player: Node3D = get_first_node_in_group("player")
	player.set_physics_process(false)
	for night in [2, 3]:
		nm.current_night = night
		for i in 60:
			await process_frame
		gt.is_time_paused = true
		gt.cycle_progress = 0.75
		gt._elapsed = 0.75 * gt.cycle_duration
		gt.is_day = false
		gt.time_changed.emit(0.75)
		ec._on_game_time_changed(0.75, true)
		for view in [["yard", Vector3(9.0, 1.0, 26.0), Vector3(9.0, 1.6, 60.0)], ["cabin", Vector3(20.0, 1.0, 34.0), Vector3(9.0, 2.0, 14.0)]]:
			player.global_position = view[1]
			var cam: Camera3D = player.get_node("CameraHolder/Camera3D")
			for i in 20:
				await process_frame
			cam.look_at(view[2])
			ec._on_game_time_changed(0.75, true)
			var dens: String = OS.get_environment("NIGHT_DENSITY")
			if dens != "":
				ec.night_ground_fog_density = float(dens)
				ec._cached_vfog_density = -1.0
			var flc: String = OS.get_environment("NIGHT_FOG_LIGHT")
			if flc != "":
				ec.night_fog_color = Color(float(flc), float(flc), float(flc) * 1.46)
				ec._cached_fog_color = Color(-1, -1, -1)
			# EC_SET="name=value;name=value": EnvironmentController values to try.
			for pair in OS.get_environment("EC_SET").split(";", false):
				var kv := pair.split("=")
				var parts := kv[1].split(",")
				ec.set(kv[0], float(kv[1]) if parts.size() == 1 else Color(float(parts[0]), float(parts[1]), float(parts[2])))
			ec._cached_fog_color = Color(-1, -1, -1)
			ec._cached_vfog_density = -1.0
			ec._on_game_time_changed(0.75, true)
			for layer in root.find_children("*", "CanvasLayer", true, false):
				layer.visible = false
			ec._night_fog_base = 1.0
			ec._fog_noise_time = 0.0
			for i in 90:
				await process_frame
				cam.look_at(view[2])
			var img := root.get_viewport().get_texture().get_image()
			var path := "%s_n%d_%s.png" % [out, night, view[0]]
			img.save_png(path)
			var lum := 0.0
			var n := 0
			for y in range(0, img.get_height(), 8):
				for x in range(0, img.get_width(), 8):
					lum += img.get_pixel(x, y).get_luminance()
					n += 1
			var fm = ec.ground_fog.material
			print("[SHOT] %s mean luminance %.4f  (time %.2f, fog density %.3f, fog light %s, ambient %.3f %s, exposure %.2f, compat %s)" % [path, lum / n, gt.cycle_progress, fm.density, ec._environment.fog_light_color, ec._environment.ambient_light_energy, ec._environment.ambient_light_color, ec._environment.tonemap_exposure, ec._compat])
	quit()
