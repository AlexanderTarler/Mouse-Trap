extends SceneTree
## planning/tasks.txt round 7, round B (planning/tasks_plan_r7.txt):
##   9  the fog: none by day or at dusk; over the first 30 s of the night it
##      comes in, over the last 30 s before dawn it goes; the night's colour
##      all the way (no daytime tint)
##   5  the gravel road is seen (its strip faces up: it was culled before),
##      from the van to the road_ending marker
##   20 no stone through a tree trunk (the forest's pebbles, the trails'
##      rocks and logs)
##   12 the notebook pages by what fits (checked rendered by
##      tools/journal_pages.gd; here: the measuring pieces are there)
##
## Run: godot --headless --path . --fixed-fps 60 --script res://tests/regression/tasks14_test.gd

var _failures := 0
var _scene: Node


func _initialize() -> void:
	_run()


func _frames(n: int) -> void:
	for i in n:
		await physics_frame


func _check(label: String, ok: bool, detail: String = "") -> void:
	if not ok:
		_failures += 1
	print("[TASKS14 TEST] %s  %s%s" % ["PASS" if ok else "FAIL", label, ("  (" + detail + ")") if detail != "" else ""])


func _run() -> void:
	await _frames(2)
	_scene = load("res://scenes/cottage_horror.tscn").instantiate()
	_scene.get_node("Player").start_in_dev_mode = false
	root.add_child(_scene)
	current_scene = _scene
	await _frames(120)

	_test_fog()
	_test_road()
	await _test_stones()
	_test_notebook()

	print("[TASKS14 TEST] %s" % ("ALL PASSED" if _failures == 0 else "%d FAILED" % _failures))
	_scene.queue_free()
	await _frames(2)
	quit(1 if _failures > 0 else 0)


func _test_fog() -> void:
	var ec: Node = get_first_node_in_group("environment_controller")
	var gt: Node = root.get_node("GameTime")
	var cycle: float = gt.cycle_duration
	var at := func(progress: float) -> float:
		ec.cycle_progress = progress
		return ec.night_fog_amount()
	var noon: float = at.call(0.25)
	var dusk: float = at.call(0.49)
	var in_15: float = at.call(0.5 + 15.0 / cycle)
	var in_30: float = at.call(0.5 + 30.0 / cycle)
	var mid: float = at.call(0.75)
	var dawn_15: float = at.call(1.0 - 15.0 / cycle)
	_check("9: no fog by day or at dusk; half 15 s into the night, full by 30 s, full mid-night, half 15 s before dawn",
		noon == 0.0 and dusk == 0.0 and is_equal_approx(in_15, 0.5) and is_equal_approx(in_30, 1.0) and mid == 1.0 and is_equal_approx(dawn_15, 0.5),
		"noon %.2f dusk %.2f +15 s %.2f +30 s %.2f mid %.2f dawn-15 s %.2f" % [noon, dusk, in_15, in_30, mid, dawn_15])
	# Applied: thin fog early in the night is still the night's colour.
	ec._on_game_time_changed(0.5 + 5.0 / cycle, true)
	var env: Environment = ec._environment
	var night_colour: Color = ec.compat_ground_fog_color if ec._compat else ec.night_fog_color
	_check("9: thin fog early in the night is the night's colour (no daytime tint)",
		env.fog_enabled and env.fog_light_color.is_equal_approx(night_colour), str(env.fog_light_color))
	ec._on_game_time_changed(0.3, true)


func _test_road() -> void:
	var road: Node3D = _scene.get_node("GravelRoad")
	var mesh_instance: MeshInstance3D = road.get_children(true).filter(func(c): return c is MeshInstance3D)[0]
	var arrays := mesh_instance.mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var facing_down := 0
	for t in range(0, indices.size(), 3):
		var a := verts[indices[t]]
		var b := verts[indices[t + 1]]
		var c := verts[indices[t + 2]]
		# Godot's front faces are clockwise as seen: their normal is (c-a)x(b-a).
		# (Zero-area slivers where the line doubles back at its ends don't count.)
		if (c - a).cross(b - a).y < 0.0:
			facing_down += 1
	var shader: Shader = (mesh_instance.material_override as ShaderMaterial).shader
	var first: Vector3 = verts[0]
	var last: Vector3 = verts[verts.size() - 1]
	var marker: Node3D = _scene.get_node("road_ending")
	_check("5: the road's strip faces up (seen from above, not culled): %d of %d triangles face down" % [facing_down, indices.size() / 3],
		facing_down == 0 and "cull_back" in shader.code)
	_check("5: it runs from the van to the road_ending marker",
		Vector2(first.x, first.z).distance_to(Vector2(-24.0, -90.6)) < 5.0 and Vector2(last.x, last.z).distance_to(Vector2(marker.global_position.x, marker.global_position.z)) < 5.0)


func _test_stones() -> void:
	var stones: Array = ForestDresser.stone_spots
	var through := 0
	for s: Vector4 in stones:
		if ForestDresser.near_trunk(Vector3(s.x, s.y, s.z), 0.5 * s.w):
			through += 1
	_check("20: the forest's pebbles keep off the trunks (%d of %d too close)" % [through, stones.size()], stones.size() > 50 and through == 0)
	var trail_through := 0
	for prop in _details():
		if not prop is Node3D or (prop as Node3D).global_position.distance_to(Vector3(9.0, 0.0, 15.0)) < 25.0:
			continue
		var box: AABB = _box(prop)
		if box.size.y > 1.5:
			continue
		if ForestDresser.near_trunk(box.get_center(), 0.45):
			trail_through += 1
	_check("20: no trail rock or log through a trunk (%d)" % trail_through, trail_through == 0)


## The details in the level (tools/bake_details.gd: CabinDetails,
## ForestDetails).
func _details() -> Array:
	var found: Array = []
	for group in ["CabinDetails", "ForestDetails"]:
		var node := _scene.get_node_or_null(group)
		if node:
			found.append_array(node.get_children())
	return found


## A node's meshes' bounds, in world space.
func _box(node: Node3D) -> AABB:
	var box := AABB(node.global_position, Vector3.ZERO)
	var first := true
	for mesh: MeshInstance3D in node.find_children("*", "MeshInstance3D", true, false):
		var b := mesh.global_transform * mesh.get_aabb()
		box = b if first else box.merge(b)
		first = false
	return box


func _test_notebook() -> void:
	var nb: Node = get_first_node_in_group("notebook_ui")
	_check("12: the notebook pages by what fits once it's laid out (and by characters before)",
		nb.has_method("_page_size") and nb.has_method("_longest_fit") and nb.has_method("_split_by_chars")
		and nb._split_by_chars("word ".repeat(600)).size() >= 3)
