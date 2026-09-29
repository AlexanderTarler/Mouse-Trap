extends SceneTree
## Navigation split check. Run headless from the project folder:
##   godot --headless --path . --script res://tests/nav_split_test.gd -- --bake
## (--bake rebakes both navmeshes in memory first; omit it to test the saved bake.)
##
## Bakes both navmeshes IN MEMORY (nothing is saved) and verifies that the
## cabin interior is only reachable through ENABLED entry links:
##   - door locked + windows intact  -> interior unreachable
##   - door unlocked                 -> reachable through the door
##   - a window breached             -> reachable through that window
##   - that window boarded again     -> unreachable
##   - paths near the cabin don't cut through layer-1 obstacles (the trees
##     and props the Entity collides with are baked into the navmesh)
## Prints "[NAV TEST] PASS"/"FAIL" per scenario and a final "ALL PASSED" or
## "N FAILED" line. Read that line: headless shutdown currently segfaults in
## game teardown, so the process exit code is not reliable.

const OUTSIDE := Vector3(20.0, 0.4, 4.0)       # yard, east of the porch
const INSIDE_HALL := Vector3(6.5, 0.9, 11.0)   # hall floor
const INSIDE_BACK := Vector3(12.0, 0.9, 17.5)  # computer room floor
const REACH_TOLERANCE := 1.0

var _failures := 0
var _outer: NavigationRegion3D
var _inner: NavigationRegion3D


# NOTE: no class_name references (CabinWindow, CabinEntryLink) in this file:
# in --script mode they would be compiled before the autoloads they depend on.
const LINK_GROUP := "cabin_entry_links"
const LINK_KINDS := ["DOOR", "WINDOW"]


func _initialize() -> void:
	_run()


func _frames(n: int) -> void:
	for i in n:
		await physics_frame


func _run() -> void:
	var scene: Node = load("res://scenes/cottage_horror.tscn").instantiate()
	root.add_child(scene)
	await _frames(3)

	_outer = scene.get_node("NavigationRegion3D")
	_inner = scene.get_node("NavigationRegion3D/Cabin/NavigationRegion3D")
	# Rebuild the map synchronously: with async iterations an in-memory rebake
	# may not reach the query map in headless runs.
	var nav_map := _outer.get_navigation_map()
	NavigationServer3D.map_set_use_async_iterations(nav_map, false)
	NavigationServer3D.region_set_use_async_iterations(_outer.get_region_rid(), false)
	NavigationServer3D.region_set_use_async_iterations(_inner.get_region_rid(), false)
	if "--bake" in OS.get_cmdline_user_args() or _inner.navigation_mesh.get_polygon_count() == 0:
		_inner.bake_navigation_mesh(false)
		_outer.bake_navigation_mesh(false)
		print("[NAV TEST] baked in memory: interior %d polygons, exterior %d polygons" % [
			_inner.navigation_mesh.get_polygon_count(), _outer.navigation_mesh.get_polygon_count()])

	var door = scene.get_node("NavigationRegion3D/Cabin/Door")
	var windows := get_nodes_in_group("BottomFloorWindows").filter(func(n): return n.has_method("is_passable"))
	var map := _outer.get_navigation_map()
	await _frames(5)

	var links := get_nodes_in_group(LINK_GROUP)
	print("[NAV TEST] entry links: %d (door + %d windows expected)" % [links.size(), windows.size()])
	for l in links:
		print("[NAV TEST]   %s %s start=%s end=%s" % [LINK_KINDS[l.kind], l.entry.name, l.start_position.snapped(Vector3.ONE * 0.01), l.end_position.snapped(Vector3.ONE * 0.01)])

	# Any other NavigationLink3D that crosses the cabin wall bypasses the
	# lock/breach rules entirely. Report it as a failure, then disable it so
	# the scenarios below test the entry links on their own.
	for node in scene.find_children("*", "NavigationLink3D", true, false):
		if node.is_in_group(LINK_GROUP):
			continue
		var a: Vector3 = node.global_transform * node.start_position
		var b: Vector3 = node.global_transform * node.end_position
		if _in_cabin(a) != _in_cabin(b):
			_failures += 1
			print("[NAV TEST] FAIL  stray link crosses the cabin wall: %s (%s -> %s). Delete it; CabinEntryLink handles entries." % [
				scene.get_path_to(node), a.snapped(Vector3.ONE * 0.01), b.snapped(Vector3.ONE * 0.01)])
			node.enabled = false

	door.is_locked = true
	for w in windows:
		w.is_glass_shattered = false
		w.is_boarded = false
	await _frames(3)
	_expect(map, "door locked, windows intact", false)

	# Query right away: the game's day routine may lock the door again on the
	# next frame (the link correctly follows it).
	door.is_locked = false
	_expect(map, "door unlocked", true)

	door.is_locked = true
	var lw = windows.filter(func(n): return n.window_id == "LivingRoom_Right").front()
	lw.is_glass_shattered = true
	await _frames(3)
	_expect(map, "LivingRoom window breached", true)

	lw.is_boarded = true
	await _frames(3)
	_expect(map, "LivingRoom window re-boarded", false)

	_check_obstacle_clearance(scene, map)
	_check_link_connections(map)
	_check_each_window_usable(windows, door, map)

	print("[NAV TEST] %s" % ("ALL PASSED" if _failures == 0 else "%d FAILED" % _failures))
	# Free the level before quitting; tearing it down during engine shutdown
	# crashes some game scripts in headless mode and masks the exit code.
	scene.queue_free()
	await _frames(2)
	quit(1 if _failures > 0 else 0)


## Opening a single window at a time, the yard must connect to the inside of
## that window (catches links that attach to a cut-off navmesh island).
func _check_each_window_usable(windows: Array, door, map: RID) -> void:
	door.is_locked = true
	for w in windows:
		for other in windows:
			other.is_glass_shattered = other == w
			other.is_boarded = false
		NavigationServer3D.map_force_update(map)
		var link = null
		for l in get_nodes_in_group(LINK_GROUP):
			if l.entry == w:
				link = l
		var path := NavigationServer3D.map_get_path(map, OUTSIDE, link.end_position, true)
		var end: Vector3 = path[path.size() - 1] if path.size() > 0 else Vector3.INF
		var ok := end.distance_to(link.end_position) < REACH_TOLERANCE
		if not ok:
			_failures += 1
		print("[NAV TEST] %s  only %-24s open -> yard reaches inside: %s (path ends %.2f m away)" % [
			"PASS" if ok else "FAIL", w.name, ok, end.distance_to(link.end_position)])


## Every entry link must have walkable navmesh within reach of both ends,
## or paths through that window/door silently fail.
func _check_link_connections(map: RID) -> void:
	var radius := NavigationServer3D.map_get_link_connection_radius(map)
	for link in get_nodes_in_group(LINK_GROUP):
		var outside := NavigationServer3D.map_get_closest_point(map, link.start_position)
		var inside := NavigationServer3D.region_get_closest_point(_inner.get_region_rid(), link.end_position)
		var d_out := outside.distance_to(link.start_position)
		var d_in := inside.distance_to(link.end_position)
		var ok := d_out <= radius and d_in <= radius
		if not ok:
			_failures += 1
		print("[NAV TEST] %s  link %-24s outside end %.2f m from navmesh, inside end %.2f m (limit %.2f)" % [
			"PASS" if ok else "FAIL", link.entry.name, d_out, d_in, radius])


## 300 random paths within ~40 m of the cabin must not pass through the
## trees and props the Entity physically collides with (layer 1).
func _check_obstacle_clearance(scene: Node, map: RID) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var space := _outer.get_world_3d().direct_space_state
	var blocked := 0
	var example := ""
	for i in 300:
		var a := Vector3(rng.randf_range(-30.0, 50.0), 0.4, rng.randf_range(-30.0, 50.0))
		var b := Vector3(rng.randf_range(-30.0, 50.0), 0.4, rng.randf_range(-30.0, 50.0))
		var path := NavigationServer3D.map_get_path(map, a, b, true)
		for k in range(1, path.size()):
			var q := PhysicsRayQueryParameters3D.create(path[k - 1] + Vector3.UP * 0.6, path[k] + Vector3.UP * 0.6, 1)
			var hit := space.intersect_ray(q)
			if not hit.is_empty() and str(scene.get_path_to(hit.collider)).begins_with("Details/Outside Cabin"):
				blocked += 1
				if example == "":
					example = str(scene.get_path_to(hit.collider))
				break
	var ok := blocked == 0
	if not ok:
		_failures += 1
	print("[NAV TEST] %s  paths clear of layer-1 trees/props: %d of 300 blocked%s" % [
		"PASS" if ok else "FAIL", blocked, (" (e.g. " + example + ")") if example != "" else ""])


## Rough cabin floor footprint in world space (hall wing + back wing).
func _in_cabin(p: Vector3) -> bool:
	var in_hall := p.x > 2.6 and p.x < 10.0 and p.z > 7.6 and p.z < 14.0
	var in_back := p.x > 2.6 and p.x < 15.6 and p.z > 14.0 and p.z < 20.7
	return in_hall or in_back


func _expect(map: RID, label: String, should_reach: bool) -> void:
	NavigationServer3D.map_force_update(map)
	for target in [INSIDE_HALL, INSIDE_BACK]:
		var path := NavigationServer3D.map_get_path(map, OUTSIDE, target, true)
		var end: Vector3 = path[path.size() - 1] if path.size() > 0 else Vector3.INF
		var reached := end.distance_to(target) < REACH_TOLERANCE
		var ok := reached == should_reach
		if not ok:
			_failures += 1
		print("[NAV TEST] %s  %-30s -> %s reached=%s (expected %s)" % ["PASS" if ok else "FAIL", label, target, reached, should_reach])
		if not ok:
			for link_rid in NavigationServer3D.map_get_links(map):
				if NavigationServer3D.link_get_enabled(link_rid):
					print("[NAV TEST]      ENABLED link on map: %s -> %s" % [
						NavigationServer3D.link_get_start_position(link_rid).snapped(Vector3.ONE * 0.01),
						NavigationServer3D.link_get_end_position(link_rid).snapped(Vector3.ONE * 0.01)])
			for region_rid in NavigationServer3D.map_get_regions(map):
				print("[NAV TEST]      region %s edge_connections=%s bounds=%s" % [
					"interior" if region_rid == _inner.get_rid() else ("exterior" if region_rid == _outer.get_rid() else str(region_rid)),
					NavigationServer3D.region_get_use_edge_connections(region_rid),
					NavigationServer3D.region_get_bounds(region_rid)])
			for p in path:
				var owner_rid := NavigationServer3D.map_get_closest_point_owner(map, p)
				var owner_name := "interior" if owner_rid == _inner.get_rid() else ("exterior" if owner_rid == _outer.get_rid() else "link/other")
				print("[NAV TEST]      %s  %s" % [p.snapped(Vector3.ONE * 0.01), owner_name])
