extends SceneTree
## A carried or dropped item never ends up through a wall, a door or the
## floor (DropGuard): a move stops at what is in its way, and an item that
## ever falls out of the world is put back where it last rested.
##
## Run: godot --headless --path . --fixed-fps 60 --script res://tests/drop_guard_test.gd

var _failures := 0


func _initialize() -> void:
	_run()


func _frames(n: int) -> void:
	for i in n:
		await physics_frame


func _check(label: String, ok: bool, detail: String = "") -> void:
	if not ok:
		_failures += 1
	print("[DROP GUARD TEST] %s  %s%s" % ["PASS" if ok else "FAIL", label, ("  (" + detail + ")") if detail != "" and not ok else ""])


func _run() -> void:
	var scene := Node3D.new()
	root.add_child(scene)
	# A thin wall (a door's thickness) across x = 5.
	var wall := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.07, 3.0, 4.0)
	shape.shape = box
	wall.add_child(shape)
	wall.position = Vector3(5, 1.5, 0)
	scene.add_child(wall)
	await _frames(3)
	var world := scene.get_world_3d()

	var stopped := DropGuard.sweep(world, Vector3(2, 1, 0), Vector3(8, 1, 0))
	_check("a move into a wall stops this side of it", stopped.x < 5.0 and stopped.x > 4.5, str(stopped))
	var clear := DropGuard.sweep(world, Vector3(2, 1, 0), Vector3(4, 1, 0))
	_check("a clear move goes all the way", clear.is_equal_approx(Vector3(4, 1, 0)), str(clear))
	var none := DropGuard.sweep(world, Vector3(2, 1, 0), Vector3(2, 1, 0))
	_check("no move, no change", none.is_equal_approx(Vector3(2, 1, 0)))

	# An item that falls out of the world comes back.
	var floor_body := StaticBody3D.new()
	var floor_shape := CollisionShape3D.new()
	var floor_box := BoxShape3D.new()
	floor_box.size = Vector3(20, 0.2, 20)
	floor_shape.shape = floor_box
	floor_body.add_child(floor_shape)
	floor_body.position = Vector3(0, -0.1, 10)
	scene.add_child(floor_body)
	var item := RigidBody3D.new()
	var item_shape := CollisionShape3D.new()
	var item_box := BoxShape3D.new()
	item_box.size = Vector3(0.1, 0.1, 0.1)
	item_shape.shape = item_box
	item.add_child(item_shape)
	item.position = Vector3(0, 0.3, 10)
	scene.add_child(item)
	DropGuard.watch(item)
	DropGuard.watch(item)
	_check("one guard per item, and continuous collision on",
		item.get_children().filter(func(c): return c is DropGuard).size() == 1 and item.continuous_cd)
	await _frames(120)
	var rested := item.global_position
	# Through the floor (as if the floor had let it go).
	floor_body.queue_free()
	await _frames(240)
	_check("an item that falls out of the world is put back where it rested",
		item.global_position.y > -1.0 and item.global_position.distance_to(rested) < 1.0,
		"rested %s, now %s" % [rested, item.global_position])

	print("[DROP GUARD TEST] %s" % ("ALL PASSED" if _failures == 0 else "%d FAILED" % _failures))
	quit(1 if _failures > 0 else 0)
