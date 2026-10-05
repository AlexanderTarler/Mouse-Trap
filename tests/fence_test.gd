extends SceneTree
## The barn yard's fence ("Barn Fence") and its gate ("Barn Gate"):
##   - the fence has colliders all the way round, its only opening the gate,
##     and the navmesh is baked from it;
##   - no tree stands in the fence line (ForestDresser clears it);
##   - the gate opens and shuts with E, and blocks the way when shut;
##   - on the navmesh the only way into the yard is through the gate;
##   - the Entity bursts a shut gate open when it comes to it.
##
## Run: godot --headless --path . --fixed-fps 60 --script res://tests/fence_test.gd

const CORNERS := [Vector2(11.2, -86.9), Vector2(62.26, -86.9), Vector2(62.26, -60.12), Vector2(11.2, -60.12)]
const GATE_X := Vector2(31.65, 35.05)
const SOUTH_Z := -86.9

var _failures := 0
var _scene: Node
var _space: PhysicsDirectSpaceState3D


func _initialize() -> void:
	_run()


func _check(label: String, ok: bool, detail: String = "") -> void:
	if not ok:
		_failures += 1
	print("[FENCE TEST] %s  %s%s" % ["PASS" if ok else "FAIL", label, ("  (" + detail + ")") if detail != "" else ""])


func _frames(n: int) -> void:
	for i in n:
		await physics_frame


func _run() -> void:
	_scene = load("res://scenes/cottage_horror.tscn").instantiate()
	_scene.get_node("Player").start_in_dev_mode = false
	root.add_child(_scene)
	current_scene = _scene
	await _frames(240)
	_space = _scene.get_world_3d().direct_space_state

	_test_fence()
	_test_trees()
	await _test_gate()
	_test_navigation()
	await _test_entity_opens_gate()

	print("[FENCE TEST] %s" % ("ALL PASSED" if _failures == 0 else "%d FAILED" % _failures))
	_scene.queue_free()
	await _frames(2)
	quit(1 if _failures > 0 else 0)


func _blocked_at(p: Vector3, by: Array) -> bool:
	var box := BoxShape3D.new()
	box.size = Vector3(0.4, 1.0, 0.4)
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = box
	query.transform = Transform3D(Basis(), p)
	for hit in _space.intersect_shape(query, 16):
		if hit.collider in by:
			return true
	return false


func _test_fence() -> void:
	var fence: Node = _scene.get_node("Barn Fence")
	var body: Node = fence.get_node("Colliders")
	var gate: Node = _scene.get_node("Barn Gate")
	var holes: Array[String] = []
	for i in 4:
		var a: Vector2 = CORNERS[i]
		var b: Vector2 = CORNERS[(i + 1) % 4]
		var steps := int(a.distance_to(b) / 0.5)
		for s in steps + 1:
			var p := a.lerp(b, float(s) / steps)
			var in_gate := absf(p.y - SOUTH_Z) < 0.01 and p.x > GATE_X.x + 0.2 and p.x < GATE_X.y - 0.2
			var fenced := _blocked_at(Vector3(p.x, 0.9, p.y), [body])
			if in_gate == fenced or (in_gate and not _blocked_at(Vector3(p.x, 0.9, p.y), [gate])):
				holes.append("%.1f,%.1f" % [p.x, p.y])
	_check("fence: colliders all the way round; the gate (shut) is the only gap in them",
		body is StaticBody3D and holes.is_empty() and fence.is_in_group("navmesh_source"), str(holes))
	var pieces: int = fence.get_node("Meshes").get_child_count()
	_check("fence: north and west sides added, the doubled pieces gone (%d pieces)" % pieces, pieces == 23)


func _test_trees() -> void:
	var near: Array[String] = []
	for shape in _scene.find_children("*", "CollisionShape3D", true, false):
		if shape.disabled or not str(shape.get_path()).contains("Group of Trees"):
			continue
		var p: Vector3 = shape.global_position
		if ForestDresser.near_fence(p, 0.7):
			near.append("%.1f,%.1f" % [p.x, p.z])
	_check("no tree trunk stands in the fence line", near.is_empty(), str(near))


func _test_gate() -> void:
	var gate: Node = _scene.get_node("Barn Gate")
	var through := PhysicsRayQueryParameters3D.create(Vector3(33.4, 0.8, -88.5), Vector3(33.4, 0.8, -85.0))
	var shut_hit: Dictionary = _space.intersect_ray(through)
	var closed_text: String = gate.get_interact_text()
	gate.interact()
	await _frames(int(60 * (gate.swing_time + 0.3)))
	var open_hit: Dictionary = _space.intersect_ray(through)
	var opened: bool = gate.is_open and absf(rad_to_deg(gate.rotation.y) - gate.open_angle) < 1.0
	var open_text: String = gate.get_interact_text()
	gate.interact()
	await _frames(int(60 * (gate.swing_time + 0.3)))
	_check("gate: E opens it (and the way through), E shuts it again",
		shut_hit.get("collider") == gate and opened and open_hit.is_empty() and not gate.is_open
			and absf(gate.rotation.y) < 0.02 and closed_text == "[E] Open Gate" and open_text == "[E] Close Gate",
		"shut hit %s, open hit %s, opened %s" % [shut_hit.get("collider"), open_hit.get("collider"), opened])
	_check("gate: on the interactable layer, and the player collides with it",
		gate.collision_layer & 2 != 0 and gate.collision_layer & 1 != 0 and gate.is_in_group("interactable"))


## Every crossing of the fence on a navmesh path is at the gate.
func _test_navigation() -> void:
	var map: RID = _scene.get_world_3d().navigation_map
	var routes := [[Vector3(33.4, 0.1, -92.0), Vector3(40.0, 0.1, -76.0)],
		[Vector3(4.0, 0.1, -75.0), Vector3(20.0, 0.1, -75.0)],
		[Vector3(45.0, 0.1, -50.0), Vector3(50.0, 0.1, -70.0)],
		[Vector3(70.0, 0.1, -75.0), Vector3(55.0, 0.1, -75.0)]]
	var bad: Array[String] = []
	for route in routes:
		var path := NavigationServer3D.map_get_path(map, route[0], route[1], true)
		if path.is_empty() or Vector2(path[-1].x - route[1].x, path[-1].z - route[1].z).length() > 1.5:
			bad.append("no path to %s" % route[1])
			continue
		for i in path.size() - 1:
			var a := Vector2(path[i].x, path[i].z)
			var b := Vector2(path[i + 1].x, path[i + 1].z)
			for c in 4:
				var hit = Geometry2D.segment_intersects_segment(a, b, CORNERS[c], CORNERS[(c + 1) % 4])
				if hit != null and not (c == 0 and hit.x > GATE_X.x and hit.x < GATE_X.y):
					bad.append("crosses at %.1f,%.1f" % [hit.x, hit.y])
	_check("navmesh: into the yard from every side, and only through the gate", bad.is_empty(), str(bad))


func _test_entity_opens_gate() -> void:
	var gate: Node = _scene.get_node("Barn Gate")
	var entity = get_first_node_in_group("entity")
	entity.can_kill = false
	entity.activate()
	entity._teleport(Vector3(33.4, 0.1, -89.0))
	await _frames(10)
	_check("the Entity bursts the shut gate open when it comes to it", gate.is_open)
	entity.deactivate()
	entity.can_kill = true
