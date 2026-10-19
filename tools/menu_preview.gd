extends SceneTree
## Renders the main menu (its backdrop) to a PNG, with the visitor showing.
## Run (windowed): godot --path . --rendering-method gl_compatibility --script res://tools/menu_preview.gd -- <out.png> [visit spot] [time of day 0-1]


func _initialize() -> void:
	_run()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var out: String = args[0] if args.size() > 0 else "user://menu_preview.png"
	await process_frame
	var menu: Node = load("res://scenes/ui/main_menu.tscn").instantiate()
	root.add_child(menu)
	current_scene = menu
	for i in 3:
		await process_frame
	var calibration := menu.get_node_or_null("Calibration")
	if calibration:
		calibration.queue_free()
	var backdrop: Node = menu.get_node_or_null("Backdrop")
	if backdrop:
		backdrop.visit(int(args[1]) if args.size() > 1 else -1)
		# A time of day to show (0 afternoon - 1 night), held there.
		if args.size() > 2:
			menu._backdrop = null
			backdrop.time_of_day = float(args[2])
	for i in 90:
		await process_frame
	root.get_texture().get_image().save_png(out)
	print("[MENU PREVIEW] saved ", out, " cam ", root.get_viewport().get_camera_3d().global_position if root.get_viewport().get_camera_3d() else "none", " ", root.get_viewport().get_camera_3d().get_path() if root.get_viewport().get_camera_3d() else "")
	var cam := root.get_viewport().get_camera_3d()
	if backdrop:
		var e: Node3D = backdrop.entity
		print("[MENU PREVIEW] visitor ", e.visible, " ", e.global_position, " ", e.scale, " on screen ", cam.unproject_position(e.global_position + Vector3.UP * 2.0), " meshes ", e.find_children("*", "MeshInstance3D", true, false).size())
	for c in [Vector3(-9,0,-4), Vector3(-10,0,-8), Vector3(-11,0,0), Vector3(-8.5,0,-12), Vector3(9,0,-9), Vector3(-14,0,-14), Vector3(-12.5,0,-6)]:
		print("[MENU PREVIEW] spot ", c, " -> ", cam.unproject_position(c + Vector3.UP * 3.0) / (Vector2(root.get_visible_rect().size) / Vector2(1280, 720)))
	for p in [Vector2(585, 360), Vector2(585, 245), Vector2(372, 440), Vector2(852, 440)]:
		print("[MENU PREVIEW] ", p, " -> ", hit(cam, p * Vector2(root.get_visible_rect().size) / Vector2(1280, 720), 7.0))
	quit()


## Where a screen pixel lands on the plane z = `plane_z` (placing things).
static func hit(cam: Camera3D, pixel: Vector2, plane_z: float) -> Vector3:
	var origin := cam.project_ray_origin(pixel)
	var normal := cam.project_ray_normal(pixel)
	return origin + normal * ((plane_z - origin.z) / normal.z)
