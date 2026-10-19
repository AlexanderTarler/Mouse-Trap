extends SceneTree
## Daytime screenshots from given viewpoints (to look at the level by eye).
## Renders, so run WITHOUT --headless.
##   godot --path . --resolution 1280x720 --script res://tools/view_shot.gd -- <views.json> <out_prefix> [time 0..1]
## views.json: [["name", [eye x, y, z], [look x, y, z], (ortho size)], ...]
## (with a size: orthographic, straight down from the eye: a floor plan).
## Writes
## <out_prefix>_<name>.png, and <out_prefix>_sheet<n>.png: six at a time,
## in order, three to a row. The game's UI is hidden, the Entity kept away.


func _initialize() -> void:
	_go()


func _go() -> void:
	var args := OS.get_cmdline_user_args()
	var views: Array = JSON.parse_string(FileAccess.get_file_as_string(args[0]))
	var out: String = args[1]
	var time: float = float(args[2]) if args.size() > 2 else 0.3
	var s = load("res://scenes/cottage_horror.tscn").instantiate()
	s.get_node("Player").start_in_dev_mode = false
	s.get_node("Player").dev_start = DevStart.Start.DAY_1   # (no opening)
	root.add_child(s)
	current_scene = s
	for i in 60:
		await process_frame
	var gt = root.get_node("GameTime")
	var ec = get_first_node_in_group("environment_controller")
	gt.is_time_paused = true
	gt.cycle_progress = time
	gt._elapsed = time * gt.cycle_duration
	gt.time_changed.emit(time)
	ec._on_game_time_changed(time, true)
	for e in get_nodes_in_group("entity"):
		e.deactivate()
	var player: Node3D = get_first_node_in_group("player")
	player.set_physics_process(false)
	player.visible = false
	var cam := Camera3D.new()
	cam.fov = float(OS.get_environment("VIEW_FOV")) if OS.get_environment("VIEW_FOV") != "" else 75.0
	cam.near = 0.05
	s.add_child(cam)
	cam.current = true
	var shots: Array[Image] = []
	for view in views:
		cam.global_position = Vector3(view[1][0], view[1][1], view[1][2])
		if view.size() > 3:
			cam.projection = Camera3D.PROJECTION_ORTHOGONAL
			cam.size = float(view[3])
			cam.global_basis = Basis.looking_at(Vector3.DOWN, Vector3.FORWARD)
		else:
			cam.projection = Camera3D.PROJECTION_PERSPECTIVE
			cam.look_at(Vector3(view[2][0], view[2][1], view[2][2]))
		# (VIEW_KEEP_PLAYER: leave the player where they are, e.g. not to
		# scare the crows off.)
		if OS.get_environment("VIEW_KEEP_PLAYER") == "":
			player.global_position = cam.global_position + Vector3.DOWN * 1.6
		for layer in root.find_children("*", "CanvasLayer", true, false):
			layer.visible = false
		for i in 40:
			await process_frame
		var path := "%s_%s.png" % [out, view[0]]
		var image := root.get_viewport().get_texture().get_image()
		image.save_png(path)
		shots.append(image)
		print("[VIEW] %s" % path)
	for first in range(0, shots.size(), 6):
		var sheet := Image.create(640 * 3, 360 * 2, false, Image.FORMAT_RGB8)
		for i in range(first, mini(first + 6, shots.size())):
			var small: Image = shots[i].duplicate()
			small.convert(Image.FORMAT_RGB8)
			small.resize(640, 360)
			var k := i - first
			sheet.blit_rect(small, Rect2i(0, 0, 640, 360), Vector2i((k % 3) * 640, (k / 3) * 360))
		sheet.save_png("%s_sheet%d.png" % [out, first / 6 + 1])
	quit()
