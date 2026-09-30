extends SceneTree
## Two-floor cabin checks:
##   - the interior navmesh joins the ground floor and the upper floor via the
##     stair ramp, and has no stray patches above the upper floor
##   - the exterior navmesh has no islands on the roof, eaves or ledges
##   - the Entity walks up the stairs, around the upper floor and back down
##     without getting stuck
##   - the player walks up the stairs holding W
##
## Run: godot --headless --path . --fixed-fps 60 --script res://tests/two_floor_test.gd
## Add `-- --bake` to test a fresh in-memory bake instead of the saved one.

const HALL := Vector3(6.5, 0.95, 11.0)
const UPPER_ROOMS := {
	"upper back-left room": Vector3(5.0, 3.95, 17.5),
	"upper hall": Vector3(6.5, 3.95, 10.5),
	"upper computer room": Vector3(12.5, 3.95, 17.5),
}
const STAIR_FOOT := Vector3(3.575, 1.0, 9.9)
const UPPER_FLOOR_Y := 3.73
## World-space box around the cabin, eaves included.
const CABIN_MIN := Vector2(1.7, 6.7)
const CABIN_MAX := Vector2(16.9, 21.7)

## Stand-in brain: walks toward `goal` and counts stuck events instead of
## running the default recovery (which would teleport and hide a failure).
## Compiled at runtime because Entity scripts reference autoloads that don't
## exist yet when this test script is compiled.
const WALK_BRAIN_SOURCE := """
extends EntityBrain

class Walk extends EntityState:
	var stuck_events := 0
	func on_stuck() -> void:
		stuck_events += 1

var goal := Vector3.ZERO

func _init() -> void:
	current = Walk.new()

func tick(_delta: float) -> void:
	entity.move_to(goal, 2.5)
"""

var _failures := 0


func _initialize() -> void:
	_run()


func _frames(n: int) -> void:
	for i in n:
		await physics_frame


func _check(label: String, ok: bool, detail: String = "") -> void:
	if not ok:
		_failures += 1
	print("[TWO FLOOR TEST] %s  %s%s" % ["PASS" if ok else "FAIL", label, ("  (" + detail + ")") if detail != "" else ""])


func _run() -> void:
	var scene: Node = load("res://scenes/cottage_horror.tscn").instantiate()
	# These checks follow the normal game rules: ignore the level's dev-mode
	# toggle (dev mode unlocks the door and lifts the Entity's night limits).
	scene.get_node("Player").start_in_dev_mode = false
	root.add_child(scene)
	await _frames(3)

	var outer: NavigationRegion3D = scene.get_node("NavigationRegion3D")
	var inner: NavigationRegion3D = scene.get_node("NavigationRegion3D/Cabin/NavigationRegion3D")
	# Rebuild the map synchronously: with async iterations an in-memory rebake
	# may not reach the query map in headless runs.
	var map := outer.get_navigation_map()
	NavigationServer3D.map_set_use_async_iterations(map, false)
	NavigationServer3D.region_set_use_async_iterations(outer.get_region_rid(), false)
	NavigationServer3D.region_set_use_async_iterations(inner.get_region_rid(), false)
	await _frames(3)
	if "--bake" in OS.get_cmdline_user_args():
		inner.bake_navigation_mesh(false)
		outer.bake_navigation_mesh(false)
		print("[TWO FLOOR TEST] baked in memory: interior %d polygons, exterior %d polygons" % [
			inner.navigation_mesh.get_polygon_count(), outer.navigation_mesh.get_polygon_count()])
	await _frames(10)

	var nm := root.get_node("NightManager")
	nm.is_time_paused = true
	var game_time := root.get_node_or_null("GameTime")
	if game_time:
		game_time.is_time_paused = true

	_test_navmesh(map, inner, outer)
	await _test_rooms()
	_test_upstairs_windows()
	await _test_room_lights(scene)
	await _test_entity_walk(scene)
	await _test_player_climb(scene)

	print("[TWO FLOOR TEST] %s" % ("ALL PASSED" if _failures == 0 else "%d FAILED" % _failures))
	quit(1 if _failures > 0 else 0)


func _test_navmesh(map: RID, inner: NavigationRegion3D, outer: NavigationRegion3D) -> void:
	for room in UPPER_ROOMS:
		var goal: Vector3 = UPPER_ROOMS[room]
		var snapped := NavigationServer3D.map_get_closest_point(map, goal)
		var up := NavigationServer3D.map_get_path(map, HALL, snapped, true)
		var down := NavigationServer3D.map_get_path(map, snapped, HALL, true)
		var ok := not up.is_empty() and up[-1].distance_to(snapped) < 0.3 \
			and not down.is_empty() and down[-1].distance_to(HALL) < 0.5
		_check("navmesh: hall <-> %s" % room, ok and snapped.y > UPPER_FLOOR_Y,
			"goal snaps to %s, path %d / %d points" % [snapped.snapped(Vector3.ONE * 0.01), up.size(), down.size()])

	var highest := Vector3(0, -INF, 0)
	for v in inner.navigation_mesh.get_vertices():
		var w := inner.global_transform * v
		if w.y > highest.y:
			highest = w
	_check("navmesh: nothing above the upper floor inside", highest.y < UPPER_FLOOR_Y + 0.6,
		"highest interior vertex at %s" % highest.snapped(Vector3.ONE * 0.01))

	var stray := 0
	for v in outer.navigation_mesh.get_vertices():
		var w := outer.global_transform * v
		if w.y > 2.0 and w.x > CABIN_MIN.x and w.x < CABIN_MAX.x and w.z > CABIN_MIN.y and w.z < CABIN_MAX.y:
			stray += 1
			if stray <= 6:
				print("[TWO FLOOR TEST]   stray exterior vertex at %s" % w.snapped(Vector3.ONE * 0.01))
	_check("navmesh: no exterior islands on the roof, eaves or ledges", stray == 0,
		"%d exterior vertices above 2 m over the cabin" % stray)


## Each spot must be reported as the right room, both by the player's own
## check (body overlap, drives the HUD and the routine) and by the
## RoomLightDetector (point query, used by the Entity).
func _test_rooms() -> void:
	var player := get_first_node_in_group("player") as CharacterBody3D
	player.set_physics_process(false)
	var spots := [
		["Hallroom", Vector3(6.7, 0.75, 11.5)],
		["Hallroom", Vector3(3.7, 0.75, 13.5)],          # the alcove under the stairs
		["Livingroom", Vector3(6.0, 0.75, 17.4)],
		["ComputerRoom", Vector3(12.2, 0.75, 17.4)],
		["Stairs", Vector3(3.575, 0.9, 9.6)],            # foot of the stairs
		["Stairs", Vector3(3.575, 2.3, 11.9)],           # halfway up
		["Stairs", Vector3(3.575, UPPER_FLOOR_Y, 14.2)], # top step
		["UpperHall", Vector3(6.7, UPPER_FLOOR_Y, 11.5)],
		["Landing", Vector3(6.0, UPPER_FLOOR_Y, 17.4)],
		["Bedroom", Vector3(12.2, UPPER_FLOOR_Y, 17.4)],
		["Outside", Vector3(20.0, 0.3, 4.0)],
	]
	var detector := root.get_node("RoomLightDetector")
	for spot in spots:
		var floor_pos: Vector3 = spot[1]
		# The player's origin sits 0.25 m below its feet.
		player.global_position = floor_pos + Vector3.DOWN * 0.25
		await _frames(3)
		var hud_room: String = player.get_player_room()
		var point_room: String = detector.get_room_name_at(floor_pos + Vector3.UP)
		_check("rooms: %s at %s" % [spot[0], floor_pos], hud_room == spot[0] and point_room == spot[0],
			"player reports '%s', detector reports '%s'" % [hud_room, point_room])


func _test_upstairs_windows() -> void:
	var windows := get_nodes_in_group("TopFloorWindows")
	var upstairs := windows.filter(func(w): return w.is_upstairs_window and w.global_position.y > UPPER_FLOOR_Y)
	_check("windows: four upstairs windows, flagged and at upper-floor height", windows.size() == 4 and upstairs.size() == 4,
		"%d in TopFloorWindows, %d flagged upstairs" % [windows.size(), upstairs.size()])
	var links := get_nodes_in_group(CabinEntryLink.GROUP).filter(func(l): return l.entry in windows)
	_check("windows: no Entity entry links through upstairs windows (climbing not built yet)", links.is_empty(),
		"%d links" % links.size())


## Each new switch turns its room's light on and off: the room then counts as
## lit for the Entity, and the room's windows follow the same light.
func _test_room_lights(scene: Node) -> void:
	var detector := root.get_node("RoomLightDetector")
	var nm := root.get_node("NightManager")
	var had_power: bool = nm.is_generator_on
	nm.is_generator_on = true
	var rooms := {
		"UpperHall": Vector3(6.7, UPPER_FLOOR_Y, 11.5),
		"Landing": Vector3(6.0, UPPER_FLOOR_Y, 17.4),
		"Bedroom": Vector3(12.2, UPPER_FLOOR_Y, 17.4),
		"Stairs": Vector3(3.575, 2.3, 11.9),
	}
	for room in rooms:
		var light: CabinLight = scene.get_node("Cabin Lights/CabinLight" + room)
		var trigger: Node = scene.get_node("Lightswitches/LightSwitch%s/InteractionArea" % room)
		var point: Vector3 = rooms[room] + Vector3.UP
		var windows := get_nodes_in_group("TopFloorWindows").filter(
			func(w): return detector.get_room_name_at(w.global_position + (w.global_transform.basis.z * 1.0)) == room)
		var start_lit := light.is_room_lit()
		trigger.interact()
		await _frames(2)
		var on_ok: bool = light.is_room_lit() != start_lit and detector.is_position_in_lit_room(point) == light.is_room_lit()
		var windows_ok := windows.all(func(w): return w.room_light == light)
		trigger.interact()
		await _frames(2)
		var off_ok: bool = light.is_room_lit() == start_lit and detector.is_position_in_lit_room(point) == start_lit
		_check("lights: %s switch toggles its light and the room follows" % room, on_ok and off_ok and windows_ok,
			"starts %s, windows linked %s" % ["on" if start_lit else "off", windows_ok])
	nm.is_generator_on = had_power


func _test_entity_walk(scene: Node) -> void:
	var player := get_first_node_in_group("player") as CharacterBody3D
	player.set_physics_process(false)
	player.global_position = Vector3(40.0, 0.5, -20.0)
	var entity = get_first_node_in_group("entity")
	entity.can_kill = false
	entity.activate()

	var script := GDScript.new()
	script.source_code = WALK_BRAIN_SOURCE
	script.reload()
	var walker = script.new()
	walker.entity = entity
	var real_brain = entity.brain
	entity.brain = walker
	entity._teleport(HALL)
	await _frames(30)

	var legs: Array = []
	for room in UPPER_ROOMS:
		legs.append([room, UPPER_ROOMS[room]])
	legs.append(["the hall (back downstairs)", HALL])
	for leg in legs:
		var goal: Vector3 = leg[1]
		walker.goal = goal
		var arrived := false
		var frames := 0
		while frames < 60 * 25:
			await physics_frame
			frames += 1
			if entity.global_position.distance_to(goal) < 1.0:
				arrived = true
				break
			if frames == 240:
				var path: PackedVector3Array = entity.nav_agent.get_current_navigation_path()
				print("[TWO FLOOR TEST]   after 4 s at %s, next %s, path %s" % [entity.global_position.snapped(Vector3.ONE * 0.01),
					entity.nav_agent.get_next_path_position().snapped(Vector3.ONE * 0.01), Array(path).map(func(p): return p.snapped(Vector3.ONE * 0.1))])
		_check("entity: walks to %s" % leg[0], arrived and walker.current.stuck_events == 0,
			"%s after %.1f s at %s, %d stuck events" % ["arrived" if arrived else "gave up", frames / 60.0,
			entity.global_position.snapped(Vector3.ONE * 0.01), walker.current.stuck_events])
		walker.current.stuck_events = 0

	entity.brain = real_brain
	entity.deactivate()
	walker.free()


func _test_player_climb(scene: Node) -> void:
	var player := get_first_node_in_group("player") as CharacterBody3D
	player.set_physics_process(true)
	player.global_position = STAIR_FOOT
	player.velocity = Vector3.ZERO
	player.rotation.y = PI   # facing +Z, up the stairs
	await _frames(20)
	# The player's origin isn't at its feet: measure the climb from where it
	# stands at the foot of the stairs.
	var start_y := player.global_position.y
	_press(KEY_W, true)
	var top := false
	for i in 60 * 6:
		await physics_frame
		if player.global_position.y - start_y > UPPER_FLOOR_Y - 0.9 and player.global_position.z > 14.3:
			top = true
			break
	_press(KEY_W, false)
	_check("player: walks up the stairs holding W", top,
		"started at y %.2f, ended at %s" % [start_y, player.global_position.snapped(Vector3.ONE * 0.01)])


func _press(key: Key, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = key
	event.physical_keycode = key
	event.pressed = pressed
	Input.parse_input_event(event)
