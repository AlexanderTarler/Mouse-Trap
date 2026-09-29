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

	door.is_locked = false
	await _frames(3)
	_expect(map, "door unlocked", true)

	door.is_locked = true
	var lw = windows.filter(func(n): return n.window_id == "LivingRoom_Right").front()
	lw.is_glass_shattered = true
	await _frames(3)
	_expect(map, "LivingRoom window breached", true)

	lw.is_boarded = true
	await _frames(3)
	_expect(map, "LivingRoom window re-boarded", false)

	print("[NAV TEST] %s" % ("ALL PASSED" if _failures == 0 else "%d FAILED" % _failures))
	# Free the level before quitting; tearing it down during engine shutdown
	# crashes some game scripts in headless mode and masks the exit code.
	scene.queue_free()
	await _frames(2)
	quit(1 if _failures > 0 else 0)


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
