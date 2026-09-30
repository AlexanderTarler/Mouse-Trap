extends SceneTree
## Smaller fixes:
##   - The ground fog is erased everywhere inside the cabin, down to the floor.
##   - The Entity's feet touch the ground in every animation, not only walking.
##   - Searching outdoors it speeds up exponentially, capped below a sprint.
##   - Indoors its head stays under the ceiling (it poked through the floor
##     above); outdoors it is full size.
##   - Charging indoors it shrieks, from its own head.
##   - Its distortion field (visual distortion + whispers) only works close
##     by, while the player looks at it AND it sees the player.
##   - Stalking, being watched slows it but never holds it off.
##
## Run: godot --headless --path . --fixed-fps 60 --script res://tests/fixes_test.gd

var _failures := 0


func _initialize() -> void:
	_run()


func _check(label: String, ok: bool, detail: String = "") -> void:
	if not ok:
		_failures += 1
	print("[FIXES TEST] %s  %s%s" % ["PASS" if ok else "FAIL", label, ("  (" + detail + ")") if detail != "" else ""])


func _run() -> void:
	var scene: Node = load("res://scenes/cottage_horror.tscn").instantiate()
	scene.get_node("Player").start_in_dev_mode = false
	root.add_child(scene)
	current_scene = scene
	for i in 70:
		await physics_frame

	_test_fog(scene)
	await _test_fog_reprojection()
	await _test_feet()
	await _test_search_speed()
	await _test_headroom()
	await _test_indoor_shriek()
	await _test_distortion_field()
	await _test_stalk_watched()

	print("[FIXES TEST] %s" % ("ALL PASSED" if _failures == 0 else "%d FAILED" % _failures))
	scene.queue_free()
	await process_frame
	quit(1 if _failures > 0 else 0)


func _box(center: Vector3, size: Vector3) -> AABB:
	return AABB(center - size / 2.0, size)


func _test_fog(scene: Node) -> void:
	var erasers: Array[AABB] = []
	var hard := true
	for v in scene.get_node("WorldEnvironment").get_children():
		if v is FogVolume and v.material and v.material.density < 0.0:
			erasers.append(_box(v.global_position, v.size))
			hard = hard and is_zero_approx(v.material.edge_fade)
	var uncovered: Array[String] = []
	for area in get_nodes_in_group("Cabin_Interior"):
		if not area is Area3D:
			continue
		for s in area.find_children("*", "CollisionShape3D", true, false):
			if not s.shape is BoxShape3D:
				continue
			var room := _box(s.global_position, s.shape.size)
			# Every corner of the room, pushed out a little, and down to below the floor.
			for corner in 8:
				var p := room.get_endpoint(corner)
				p += (p - room.get_center()).sign() * Vector3(0.2, 0.0, 0.2)
				p.y = minf(p.y, room.position.y) - 0.2 if corner % 2 == 0 else p.y
				if not erasers.any(func(box: AABB): return box.has_point(p)):
					uncovered.append("%s %s" % [area.name, p.snapped(Vector3.ONE * 0.01)])
	_check("fog: the erasers cover every room, past the walls and below the floors, with hard edges",
		uncovered.is_empty() and hard, ", ".join(uncovered.slice(0, 4)) + ("" if hard else " soft edges"))


func _lowest_limb(skeleton: Skeleton3D) -> float:
	var low := INF
	for b in skeleton.get_bone_count():
		var n := skeleton.get_bone_name(b).to_lower()
		if "hand" in n or "finger" in n or "foot" in n or "toe" in n or "thumb" in n:
			low = minf(low, (skeleton.global_transform * skeleton.get_bone_global_pose(b)).origin.y)
	return low


func _test_feet() -> void:
	var entity = get_first_node_in_group("entity")
	var skeleton: Skeleton3D = entity.find_children("*", "Skeleton3D", true, false)[0]
	var spot := Vector3(20.0, 0.03, 4.0)
	var lows := {}
	for anim in [&"Stalk", &"Idle", &"running_crawl", &"entity_in_light", &"AttackWindow"]:
		var low := INF
		for f in 150:
			entity.cinematic_pose(Transform3D(Basis.IDENTITY, spot), anim)
			await process_frame
			if f > 60:
				low = minf(low, _lowest_limb(skeleton) - spot.y)
		lows[anim] = low
	var walk: float = lows[&"Stalk"]
	var floating: Array = lows.keys().filter(func(a): return absf(lows[a] - walk) > 0.08)
	_check("feet: its feet reach the ground in every animation, as when walking", floating.is_empty(),
		", ".join(lows.keys().map(func(a): return "%s %.2f" % [a, lows[a]])))
	entity.deactivate()


func _test_search_speed() -> void:
	var entity = get_first_node_in_group("entity")
	var player: Node3D = get_first_node_in_group("player")
	player.global_position = Vector3(40.0, 0.5, -20.0)
	entity.activate()
	entity._teleport(Vector3(20.0, 0.1, 4.0))
	entity.request_state(entity.State.SEARCH, {"target": Vector3(30.0, 0.1, 10.0)})
	var state = entity.brain.current
	var speeds := []
	for t in [0.0, 5.0, 10.0, 30.0]:
		state.time = t
		speeds.append(state.current_speed())
	var config = entity.config
	var doubled: bool = absf(speeds[2] - config.search_speed * 2.0) < 0.05
	var capped: bool = absf(speeds[3] - config.search_speed_max) < 0.01 and config.search_speed_max < 6.5
	_check("search: outdoors it speeds up exponentially (doubling every %.0f s), capped below a sprint" % config.search_speed_doubling_time,
		speeds[1] > speeds[0] and doubled and capped,
		"%s m/s at 0, 5, 10, 30 s" % [speeds.map(func(s): return snappedf(s, 0.01))])
	# Moving: its real speed follows.
	state.time = 12.0
	var moved := 0.0
	var last: Vector3 = entity.global_position
	for i in 30:
		await physics_frame
		moved += Vector2(entity.global_position.x - last.x, entity.global_position.z - last.z).length()
		last = entity.global_position
	_check("search: and it actually moves that fast", moved / 0.5 > config.search_speed * 1.6,
		"%.1f m/s" % (moved / 0.5))
	entity.deactivate()


func _highest_bone(skeleton: Skeleton3D) -> float:
	var top := -INF
	for b in skeleton.get_bone_count():
		top = maxf(top, (skeleton.global_transform * skeleton.get_bone_global_pose(b)).origin.y)
	return top


func _test_headroom() -> void:
	var entity = get_first_node_in_group("entity")
	var skeleton: Skeleton3D = entity.find_children("*", "Skeleton3D", true, false)[0]
	var space = entity.get_world_3d().direct_space_state
	entity.activate()
	entity.request_state(entity.State.STUNNED)
	var hall := Vector3(6.5, 0.73, 11.0)
	var ceiling: Dictionary = space.intersect_ray(PhysicsRayQueryParameters3D.create(hall + Vector3.UP * 0.3, hall + Vector3.UP * 5.0, 1))
	var top := -INF
	for f in 150:
		entity.cinematic_pose(Transform3D(Basis.IDENTITY, hall), &"Stalk")
		entity.perception.entity_inside = true
		await process_frame
		if f > 60:
			top = maxf(top, _highest_bone(skeleton))
	# The eyes are its highest bone; the top of the skull is ~0.15 m above them.
	var clear: bool = not ceiling.is_empty() and top + 0.15 < ceiling.position.y
	_check("headroom: walking the ground floor its head stays under the ceiling", clear,
		"head top ~%.2f, ceiling %.2f, size %.2f" % [top + 0.15, ceiling.position.y if ceiling else NAN, entity._size])
	for f in 90:
		entity.cinematic_pose(Transform3D(Basis.IDENTITY, Vector3(20.0, 0.03, 4.0)), &"Stalk")
		entity.perception.entity_inside = false
		await process_frame
	_check("headroom: outdoors it is back to full size", entity._size > 0.98, "size %.2f" % entity._size)
	entity.deactivate()


func _test_indoor_shriek() -> void:
	var entity = get_first_node_in_group("entity")
	var player: Node3D = get_first_node_in_group("player")
	player.global_position = Vector3(6.5, 0.8, 17.0)
	entity.activate()
	entity._teleport(Vector3(6.5, 0.8, 11.0))
	entity.request_state(entity.State.STUNNED)
	for i in 5:
		await physics_frame
	entity.request_state(entity.State.CHARGE)
	var shriek: AudioStreamPlayer3D = entity.audio._shriek
	var on_it: bool = shriek != null and shriek.global_position.distance_to(entity.global_position + Vector3.UP * entity.config.eye_height) < 0.3
	_check("shriek: charging indoors it shrieks, from its own head",
		shriek != null and shriek.playing and on_it and entity.perception.entity_inside,
		"playing=%s, at its head=%s, inside=%s" % [shriek.playing if shriek else false, on_it, entity.perception.entity_inside])
	entity.deactivate()


## Fog blending (temporal reprojection) smeared outside fog into the rooms
## when the player moved: off indoors, on outdoors.
func _test_fog_reprojection() -> void:
	var player: Node3D = get_first_node_in_group("player")
	var env: Environment = get_first_node_in_group("environment_controller")._environment
	var start := player.global_position
	player.global_position = Vector3(6.5, 0.8, 11.0)
	for i in 30:
		await physics_frame
	var inside: bool = env.volumetric_fog_temporal_reprojection_enabled
	player.global_position = Vector3(20.0, 0.5, 4.0)
	for i in 30:
		await physics_frame
	var outside: bool = env.volumetric_fog_temporal_reprojection_enabled
	player.global_position = start
	for i in 10:
		await physics_frame
	_check("fog: no fog blending indoors (it smeared fog in through the walls), blending outdoors",
		not inside and outside, "indoors %s, outdoors %s" % [inside, outside])


func _seconds(s: float) -> void:
	for i in int(s * 60.0):
		await physics_frame


## Player at `at` looking along +Z (facing_entity) or -Z; the Entity `ahead`
## metres in front, facing the player or turned away (then blind to them).
func _stage(at: Vector3, ahead: float, player_looks: bool, entity_faces: bool) -> void:
	var player: Node3D = get_first_node_in_group("player")
	var entity = get_first_node_in_group("entity")
	player.global_position = at
	player.rotation.y = PI if player_looks else 0.0
	entity.activate()
	entity.request_state(entity.State.STUNNED)
	entity._teleport(at + Vector3(0.0, -0.4, ahead))
	entity.rotation.y = PI if entity_faces else 0.0


func _test_distortion_field() -> void:
	var player: CharacterBody3D = get_first_node_in_group("player")
	var entity = get_first_node_in_group("entity")
	var field = player.find_child("SanityController", true, false)
	var night_manager = root.get_node("NightManager")
	var night: int = night_manager.current_night
	night_manager.current_night = 3
	player.set_physics_process(false)
	var at := Vector3(30.0, 0.5, 0.0)
	var results := {}
	for case in [["near", 8.0, true, true], ["far", 24.0, true, true], ["unseen", 8.0, true, false], ["away", 8.0, false, true]]:
		_stage(at, case[1], case[2], case[3])
		await _seconds(2.5)
		results[case[0]] = [field.level, field._overlay.visible, field._audio.playing, entity.perception.can_see_player]
	var near: Array = results["near"]
	_check("field: close, looked at and seeing the player: the view distorts and it whispers",
		near[0] > 0.4 and near[1] and near[2] and near[3], "strength %.2f, overlay %s, whispers %s, it sees the player %s" % near)
	var quiet: Array[String] = []
	for c in ["far", "unseen", "away"]:
		if results[c][0] > 0.02 or results[c][1] or results[c][2]:
			quiet.append("%s: %.2f" % [c, results[c][0]])
	_check("field: nothing when it is far away (24 m), can't see the player, or isn't looked at",
		quiet.is_empty(), ", ".join(quiet) if not quiet.is_empty() else "far %.2f, unseen %.2f, away %.2f" % [results["far"][0], results["unseen"][0], results["away"][0]])
	_check("field: the camera shake follows the field", is_equal_approx(field.get_gaze_normalized(), clampf(field.level + field.burst * 0.5, 0.0, 1.0)))
	entity.deactivate()
	night_manager.current_night = night
	player.set_physics_process(true)


func _test_stalk_watched() -> void:
	var player: CharacterBody3D = get_first_node_in_group("player")
	var entity = get_first_node_in_group("entity")
	player.set_physics_process(false)
	var at := Vector3(30.0, 0.5, 0.0)
	_stage(at, 10.0, true, true)
	entity.can_kill = false
	await _seconds(0.3)
	entity.perception.last_seen_position = player.global_position
	entity.request_state(entity.State.STALK)
	var closest := INF
	var watched := 0
	var frames := 0
	for i in 60 * 14:
		await physics_frame
		var flat := Vector2(entity.global_position.x - at.x, entity.global_position.z - at.z).length()
		closest = minf(closest, flat)
		# Only the approach counts (up close it is below the player's gaze).
		if flat > 5.0:
			frames += 1
			if entity.perception.player_watching:
				watched += 1
	_check("stalk: watched the whole way, it still walks right up to the player",
		closest < 2.0 and watched > frames * 0.8, "closest %.1f m, watched %d%% of the approach, state %s" % [closest, 100 * watched / maxi(frames, 1), entity.get_state_name()])
	entity.can_kill = true
	entity.deactivate()
	player.set_physics_process(true)
