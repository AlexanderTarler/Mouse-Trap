extends SceneTree
## The barn, the wreck yard, the tunnel and the willow (SiteDresser):
##   - furnished (props placed, each solid one with a collider);
##   - the barn's doors stand open on its doorway, which can be walked
##     through, and the navmesh leads in to its scrap heap;
##   - every scrap heap can still be reached on the navmesh;
##   - drums and traffic barriers that had no collider have one;
##   - the totem keeps its clearing.
##
## Run: godot --headless --path . --fixed-fps 60 --script res://tests/sites_test.gd

var _failures := 0
var _scene: Node


func _initialize() -> void:
	_run()


func _check(label: String, ok: bool, detail: String = "") -> void:
	if not ok:
		_failures += 1
	print("[SITES TEST] %s  %s%s" % ["PASS" if ok else "FAIL", label, ("  (" + detail + ")") if detail != "" else ""])


func _frames(n: int) -> void:
	for i in n:
		await physics_frame


func _run() -> void:
	_scene = load("res://scenes/cottage_horror.tscn").instantiate()
	_scene.get_node("Player").start_in_dev_mode = false
	root.add_child(_scene)
	current_scene = _scene
	await _frames(30)
	# The props are in the level ("Sites", written by tools/bake_sites.gd),
	# so SiteDresser doesn't place them again at runtime (nor the cabin's,
	# its yard's and the trails': tools/bake_details.gd, CabinDetails).
	var sites: Node = _scene.get_node_or_null("Sites")
	var props := sites.get_child_count() if sites else 0
	_check("the four places are furnished, in the level itself (%d props)" % props,
		props >= 100 and _scene.find_child("SiteDresser", true, false) == null and _scene.has_node("CabinDetails"))
	var bare := 0
	for prop in sites.get_children():
		if prop is Node3D and prop.find_children("*", "CollisionShape3D", true, false).is_empty():
			var box := _box(prop)
			if box.size.y > 0.5 and box.size.x > 0.3 and box.size.z > 0.3:
				bare += 1
	_check("every solid prop has a collider", bare == 0, "%d without" % bare)
	_check("the group the navmesh is baked from includes them", sites.is_in_group("navmesh_source"))

	var space: PhysicsDirectSpaceState3D = _scene.get_world_3d().direct_space_state
	var doorway: float = (SiteDresser.BARN_DOORWAY_X.x + SiteDresser.BARN_DOORWAY_X.y) * 0.5
	var through := PhysicsRayQueryParameters3D.create(Vector3(doorway, 1.2, -86.0), Vector3(doorway, 1.2, -78.0))
	var blocked: Dictionary = space.intersect_ray(through)
	var barn: Node = _scene.get_node("SM_EC_Barn_02_Body")
	var leaf := _box(barn.get_node("SM_EC_Barn_Door_05"))
	_check("the barn's doorway is open (walk straight in) and its doors stand open on it",
		blocked.is_empty() and leaf.get_center().x < SiteDresser.BARN_DOORWAY_X.y and leaf.get_center().z < SiteDresser.BARN_NORTH_Z,
		"ray hit %s; door at %s" % [blocked.get("collider").name if blocked.has("collider") else "nothing", leaf.get_center().snapped(Vector3.ONE * 0.1)])

	var map: RID = (_scene.get_node("NavigationRegion3D") as NavigationRegion3D).get_navigation_map()
	await _frames(5)
	for heap in get_nodes_in_group("scrap_heap"):
		var at: Vector3 = (heap as Node3D).global_position
		var start: Vector3 = Vector3(doorway, 0.2, -88.0) if Vector2(at.x - 37.0, at.z + 75.0).length() < 10.0 else at + Vector3(10.0, 0.0, 0.0)
		var path: PackedVector3Array = NavigationServer3D.map_get_path(map, start, at, true)
		var end_gap: float = Vector2(path[-1].x - at.x, path[-1].z - at.z).length() if path.size() > 0 else INF
		_check("the navmesh reaches %s at (%.0f, %.0f)" % [heap.name, at.x, at.z], end_gap < 2.5, "ends %.1f m away" % end_gap)

	var fixed := 0
	for name in ["SM_EC_55L_Drum_09", "SM_EC_55L_Drum_12"]:
		var drum := _scene.get_node_or_null(name)
		if drum and not drum.find_children("*", "CollisionShape3D", true, false).is_empty():
			fixed += 1
	var traffic := _scene.find_child("SM_EC_Traffic_Block_2", true, false)
	_check("the barn's drums and the yard's traffic barrier are solid now",
		fixed == 2 and traffic and not traffic.find_children("*", "CollisionShape3D", true, false).is_empty())

	var crowding := 0
	for prop in sites.get_children():
		if prop is Node3D:
			var p: Vector3 = (prop as Node3D).global_position
			if Vector2(p.x - SiteDresser.TOTEM.x, p.z - SiteDresser.TOTEM.z).length() < SiteDresser.TOTEM_CLEAR - 0.5:
				crowding += 1
	_check("the totem keeps its clearing", crowding == 0, "%d props within %.1f m" % [crowding, SiteDresser.TOTEM_CLEAR])

	print("[SITES TEST] %s" % ("ALL PASSED" if _failures == 0 else "%d FAILED" % _failures))
	_scene.queue_free()
	await _frames(2)
	quit(1 if _failures > 0 else 0)


func _box(node: Node) -> AABB:
	var box := AABB((node as Node3D).global_position, Vector3.ZERO)
	var first := true
	for mesh in node.find_children("*", "MeshInstance3D", true, false) + ([node] if node is MeshInstance3D else []):
		var b: AABB = (mesh as MeshInstance3D).global_transform * (mesh as MeshInstance3D).get_aabb()
		box = b if first else box.merge(b)
		first = false
	return box
