extends SceneTree
## Frame time, GPU and CPU render time, draw calls and triangles at a few
## viewpoints, day and night (vsync off). Opens a window (it renders).
##
## Run: godot --path . --script res://tests/perf_benchmark.gd
var _cam: Camera3D
func _initialize() -> void:
	_run()
func _frames(n: int) -> void:
	for i in n:
		if _cam: _cam.make_current()
		await process_frame
func _measure(label: String) -> void:
	await _frames(60)
	var t0 := Time.get_ticks_usec()
	var n := 120
	var draws := 0.0
	var objects := 0.0
	var prims := 0.0
	for i in n:
		if _cam: _cam.make_current()
		await process_frame
		draws += Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
		objects += Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)
		prims += Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)
	var ms := (Time.get_ticks_usec() - t0) / 1000.0 / n
	var vp := root.get_viewport().get_viewport_rid()
	var gpu := RenderingServer.viewport_get_measured_render_time_gpu(vp)
	var cpu := RenderingServer.viewport_get_measured_render_time_cpu(vp) + RenderingServer.get_frame_setup_time_cpu()
	print("PERF %-24s %6.2f ms/frame (%5.1f fps)  draw calls %6d  objects %6d  primitives %5.2fM  GPU %.2f ms  render CPU %.2f ms" % [label, ms, 1000.0 / ms, draws / n, objects / n, prims / n / 1e6, gpu, cpu])
func _look(from: Vector3, to: Vector3) -> void:
	_cam.global_transform = Transform3D(Basis.looking_at(to - from, Vector3.UP), from)
func _run() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	var t_load := Time.get_ticks_msec()
	var scene = load("res://scenes/cottage_horror.tscn").instantiate()
	scene.get_node("Player").start_in_dev_mode = false
	root.add_child(scene)
	current_scene = scene
	print("LOAD+instantiate %d ms" % (Time.get_ticks_msec() - t_load))
	await _frames(90)
	RenderingServer.viewport_set_measure_render_time(root.get_viewport().get_viewport_rid(), true)
	Engine.max_fps = 0
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED, DisplayServer.MAIN_WINDOW_ID)
	print("VSYNC mode now ", DisplayServer.window_get_vsync_mode())
	var hud = get_first_node_in_group("hud")
	if hud: hud.visible = false
	var p = get_first_node_in_group("player")
	p.set_physics_process(false)
	p.set_process(false)
	_cam = Camera3D.new()
	_cam.fov = 75.0
	scene.add_child(_cam)
	var gt = root.get_node("GameTime")
	gt.pause()
	var spots := {
		"yard->forest": [Vector3(20, 1.7, 4), Vector3(60, 1.5, 40)],
		"yard->cabin": [Vector3(20, 1.7, 0), Vector3(8, 2, 14)],
		"forest deep": [Vector3(60, 1.7, -40), Vector3(100, 1.5, -40)],
		"inside hall": [Vector3(6.5, 2.2, 9.0), Vector3(6.5, 1.2, 18)],
		"upstairs window": [Vector3(8.0, 5.3, 15.0), Vector3(8.0, 4.5, 40)],
	}
	for phase in ["day", "night"]:
		gt.set_progress(0.25 if phase == "day" else 0.75)
		gt.pause()
		await _frames(30)
		for s in spots:
			_look(spots[s][0], spots[s][1])
			await _measure(phase + " " + s)
	quit()
