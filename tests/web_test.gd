extends SceneTree
## The web build's renderer (Compatibility) fallbacks, forced on here (the
## tests run headless):
##   - no volumetric fog: the night gets its ambient light and a height fog
##     instead (EnvironmentController._compat);
##   - no decals: the Entity's marks are quads laid on the surface they'd
##     have projected onto (EntityTraces.compat).
## The desktop path stays as it was.
##
## Run: godot --headless --path . --fixed-fps 60 --script res://tests/web_test.gd

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
	print("[WEB TEST] %s  %s%s" % ["PASS" if ok else "FAIL", label, ("  (" + detail + ")") if detail != "" else ""])


func _run() -> void:
	_scene = load("res://scenes/cottage_horror.tscn").instantiate()
	_scene.get_node("Player").start_in_dev_mode = false
	root.add_child(_scene)
	current_scene = _scene
	await _frames(60)
	await _test_night()
	await _test_marks()
	print("[WEB TEST] %s" % ("ALL PASSED" if _failures == 0 else "%d FAILED" % _failures))
	_scene.queue_free()
	await _frames(2)
	quit(1 if _failures > 0 else 0)


func _test_night() -> void:
	var ec: Node = get_first_node_in_group("environment_controller")
	var env: Environment = ec._environment
	var gt: Node = root.get_node("GameTime")
	var nm: Node = root.get_node("NightManager")
	gt.is_time_paused = true
	nm.is_time_paused = true
	nm.current_night = 3
	await _frames(60)   # (a new night number restarts the clock at dusk first)
	gt.is_time_paused = true
	gt.cycle_progress = 0.75
	gt._elapsed = 0.75 * gt.cycle_duration
	ec._on_game_time_changed(0.75, true)
	await _frames(5)
	var desk_height_fog: float = env.fog_height_density
	ec._compat = true
	ec._cached_fog_color = Color(-1, -1, -1)
	ec._on_game_time_changed(0.75, true)
	_check("the web night has its own ambient light (%.2f x %s)" % [env.ambient_light_energy, env.ambient_light_color],
		is_equal_approx(env.ambient_light_energy, ec.compat_night_ambient_energy) and env.ambient_light_color.is_equal_approx(ec.compat_night_ambient_color))
	_check("the web night has a ground (height) fog instead of the fog volume (%.2f, desktop %.2f)" % [env.fog_height_density, desk_height_fog],
		env.fog_height_density > 0.05 and is_equal_approx(env.fog_height, ec.compat_ground_fog_height))
	ec._compat = false
	ec._cached_fog_color = Color(-1, -1, -1)
	ec._on_game_time_changed(0.75, true)
	_check("the desktop night is as it was (%.2f x %s)" % [env.ambient_light_energy, env.ambient_light_color],
		is_equal_approx(env.ambient_light_energy, ec.night_ambient_energy) and env.ambient_light_color.is_equal_approx(ec.night_ambient_color))


func _test_marks() -> void:
	var entity = get_first_node_in_group("entity")
	var traces = entity.traces
	traces.compat = true
	var hall := Vector3(6.5, 0.8, 11.0)
	var space: PhysicsDirectSpaceState3D = entity.get_world_3d().direct_space_state
	var floor_hit: Dictionary = space.intersect_ray(PhysicsRayQueryParameters3D.create(hall + Vector3.UP * 0.5, hall + Vector3.DOWN * 3.0))
	traces._leave_footprint(floor_hit.position)
	await _frames(3)
	var mark: Node3D = traces._footprints.back()
	var quad := mark.get_child(0) as MeshInstance3D
	_check("a web footprint is a quad on the floor (%.2f m above it)" % (quad.global_position.y - floor_hit.position.y),
		not (mark is Decal) and quad != null and absf(quad.global_position.y - floor_hit.position.y) < 0.05)
	var link = null
	for l in entity.world.entries():
		if l.kind == CabinEntryLink.Kind.WINDOW and not l.climb:
			link = l
			break
	traces.scratch_window(link)
	await _frames(3)
	var gouge: Node3D = traces._scratches.back()
	var on_wall := (gouge.get_child(0) as Node3D).global_position
	var inward: Vector3 = (link.end_position - link.start_position)
	inward.y = 0.0
	var wall_hit: Dictionary = space.intersect_ray(PhysicsRayQueryParameters3D.create(on_wall - inward.normalized() * 0.5, on_wall + inward.normalized() * 0.5))
	_check("a web claw mark sits on the wall under the window (%.2f m off it)" % (on_wall.distance_to(wall_hit.position) if wall_hit else -1.0),
		not wall_hit.is_empty() and on_wall.distance_to(wall_hit.position) < 0.05)
	traces.compat = false
	traces._leave_footprint(floor_hit.position)
	await _frames(2)
	_check("the desktop keeps real decals", traces._footprints.back() is Decal)
	traces.clear_all()
