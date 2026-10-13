extends SceneTree
## Day 1's key under the bucket by the porch:
##   - the bucket is a loose prop (lifted and moved with the grab);
##   - the key lies under it, out of reach until the bucket is moved;
##   - trying the locked door brings up the "move objects" hint, learned by
##     lifting something;
##   - the opening's phone says where the key is (lore_test checks the text).
##
## Run: godot --headless --path . --fixed-fps 60 --script res://tests/bucket_test.gd

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
	print("[BUCKET TEST] %s  %s%s" % ["PASS" if ok else "FAIL", label, ("  (" + detail + ")") if detail != "" else ""])


func _run() -> void:
	_scene = load("res://scenes/cottage_horror.tscn").instantiate()
	_scene.get_node("Player").start_in_dev_mode = false
	root.add_child(_scene)
	current_scene = _scene
	await _frames(120)   # settled

	var bucket: RigidBody3D = _scene.get_node("Bucket")
	var key: RigidBody3D = _scene.get_node("Key")
	var player: Node3D = get_first_node_in_group("player")
	var tm: Node = root.get_node("TutorialManager")
	var rm: Node = root.get_node("RoutineManager")
	_check("the bucket is a loose prop with a collider", bucket is KnockableProp and bucket.find_children("*", "CollisionShape3D", false, false).size() == 1)
	var flat := Vector2(key.global_position.x - bucket.global_position.x, key.global_position.z - bucket.global_position.z)
	_check("the key is still under the bucket once things settle (%.2f m off centre, key y %.3f)" % [flat.length(), key.global_position.y],
		flat.length() < 0.15 and key.global_position.y < bucket.global_position.y)

	# Standing by it, looking at the key: the bucket is in the way.
	var space := player.get_world_3d().direct_space_state
	var eye := bucket.global_position + Vector3(1.0, 1.6, 0.4)
	var query := PhysicsRayQueryParameters3D.create(eye, key.global_position + Vector3.UP * 0.01)
	query.exclude = [player.get_rid()]
	var hit: Dictionary = space.intersect_ray(query)
	_check("looking at the key, the bucket is what you'd reach (%s)" % (hit.collider.name if hit else "nothing"), hit and hit.collider == bucket)

	# Trying the door: the hint.
	# (Another hint on screen at that moment: it waits for it to go.)
	rm.phase1_tried_door = false
	rm.on_door_tried_locked()
	await _frames(5)
	var waited: bool = not tm._shown.has("move_objects")
	tm.mark_learned(tm.visible_hint())
	await _frames(int(2.5 * 60))
	_check("blocked by another hint, it waits and comes up after it", waited)
	_check("trying the locked door brings up the lift-and-move hint (\"%s\")" % tm.visible_hint(),
		tm.visible_hint() == "move_objects" or tm._shown_at.has("move_objects"))

	# The grab's ray only sees the Interactable layer (2): the bucket must be
	# on it (it wasn't, and couldn't be lifted). Then lift it (as PhysicalGrab
	# does) and set it down aside.
	var grab: Node = get_first_node_in_group("physical_grab")
	_check("the bucket is on the layer the grab looks for (Interactable)",
		bucket.get_collision_layer_value(2) and (grab.INTERACTABLE_LAYER_MASK & bucket.collision_layer) != 0)
	grab._grab_object(bucket)
	bucket.global_position += Vector3(0.0, 0.5, 0.8)
	await _frames(2)
	grab._drop_object()
	await _frames(60)
	_check("lifting it counts as learning the hint", tm.is_learned("move_objects"))
	hit = space.intersect_ray(query)
	_check("bucket moved: the key is reachable (%s)" % (hit.collider.name if hit else "nothing"), hit and hit.collider == key)
	key.interact()
	await _frames(3)
	_check("and taken: \"%s\"" % rm.get_current_objective(), rm._player_has_item("Cabin Key"))

	print("[BUCKET TEST] %s" % ("ALL PASSED" if _failures == 0 else "%d FAILED" % _failures))
	_scene.queue_free()
	await _frames(2)
	quit(1 if _failures > 0 else 0)
