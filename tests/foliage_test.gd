extends SceneTree
## Rustling plants (FoliageRustle), and Day 1 starting at minute 3:
##   - the bushes, ferns, grass clumps, thistles... are found, of each kind;
##   - walking into one rustles; standing still in it, or walking where
##     there are none, doesn't;
##   - the day begins 3:00 into the 5-minute day.
##
## Run: godot --headless --path . --fixed-fps 60 --script res://tests/foliage_test.gd

var _failures := 0
var _scene: Node


func _initialize() -> void:
	_run()


func _check(label: String, ok: bool, detail: String = "") -> void:
	if not ok:
		_failures += 1
	print("[FOLIAGE TEST] %s  %s%s" % ["PASS" if ok else "FAIL", label, ("  (" + detail + ")") if detail != "" else ""])


func _frames(n: int) -> void:
	for i in n:
		await physics_frame


func _run() -> void:
	_scene = load("res://scenes/cottage_horror.tscn").instantiate()
	_scene.get_node("Player").start_in_dev_mode = false
	root.add_child(_scene)
	current_scene = _scene
	await _frames(150)
	var gt: Node = root.get_node("GameTime")
	_check("Day 1 starts 3 minutes into the day (progress %.2f)" % gt.cycle_progress, absf(gt.cycle_progress - 0.3) < 0.01)

	var rustle: Node = _scene.find_child("FoliageRustle", true, false)
	_check("plants that rustle are found: %s" % str(rustle.counts),
		rustle.ready_to_play and rustle.count > 5000 and rustle.counts.get("leafy", 0) > 0
		and rustle.counts.get("twiggy", 0) > 0 and rustle.counts.get("grassy", 0) > 0)

	# A plant with nothing else around it to walk into.
	var target: Array = []
	for cell in rustle._grid:
		for plant in rustle._grid[cell]:
			if plant[2] == "leafy" and rustle.plants_at(plant[0] + Vector3(3.0, 0, 0)).is_empty() \
					and rustle.plants_at(plant[0] + Vector3(1.5, 0, 0)).size() <= 1:
				target = plant
				break
		if not target.is_empty():
			break
	var at: Vector3 = target[0]
	rustle.last_rustle = []
	rustle._inside = []
	# Walk into it at walking speed, from 3 m away.
	for i in 90:
		rustle.step(at + Vector3(3.0 - i * 2.0 / 60.0, 1.0, 0), 2.0, false, 1.0 / 60.0)
		if not rustle.last_rustle.is_empty():
			break
	_check("walking into a plant rustles", not rustle.last_rustle.is_empty(),
		str(rustle.last_rustle))
	rustle.last_rustle = []
	for i in 60:
		rustle.step(at + Vector3(0, 1.0, 0), 0.0, false, 1.0 / 60.0)
	_check("standing still in it is silent", rustle.last_rustle.is_empty())
	# Out in the open (the cabin yard is kept clear).
	rustle._inside = []
	var yard := Vector3(9.0, 1.0, 14.0)
	var any_here: bool = not rustle.plants_at(yard).is_empty()
	for i in 30:
		rustle.step(yard + Vector3(i * 0.05, 0, 0), 3.0, false, 1.0 / 60.0)
	_check("walking where there are no plants is silent", not any_here and rustle.last_rustle.is_empty(), str(rustle.last_rustle))

	await _test_cover(rustle, at)

	print("[FOLIAGE TEST] %s" % ("ALL PASSED" if _failures == 0 else "%d FAILED" % _failures))
	_scene.queue_free()
	await _frames(2)
	quit(1 if _failures > 0 else 0)


## Crouched in a bush: hidden from afar, flashlight on: not; pushing through
## is heard close by.
func _test_cover(rustle: Node, _unused: Vector3) -> void:
	var player := get_first_node_in_group("player") as CharacterBody3D
	var entity: Node = get_first_node_in_group("entity")
	var perception: Node = entity.perception
	entity.activate()
	# A tall plant to hide in.
	var bush: Array = []
	for cell in rustle._grid:
		for plant in rustle._grid[cell]:
			if plant[3] >= 1.0 and plant[1] >= 0.4:
				bush = plant
				break
		if not bush.is_empty():
			break
	player.set_physics_process(false)
	player.global_position = bush[0] + Vector3(0, 0.9, 0)
	player._is_crouching = true
	var hidden: bool = perception.player_in_cover()
	var sight: float = perception.vision_range()
	var flashlight: Node = player._flashlight
	var was_on: bool = flashlight.is_on
	var had: bool = player._has_flashlight
	player._has_flashlight = true
	flashlight.is_on = true
	var lit_hidden: bool = perception.player_in_cover()
	flashlight.is_on = was_on
	player._has_flashlight = had
	player._is_crouching = false
	var standing_hidden: bool = perception.player_in_cover()
	_check("crouched in a bush: seen only within %.0f m (range now %.1f m); standing or with a flashlight, no cover" % [entity.config.bush_cover_range, sight],
		hidden and sight <= entity.config.bush_cover_range and not lit_hidden and not standing_hidden)

	# The rustle is a noise: close by it's heard, further off (crouched) not.
	entity.global_position = bush[0] + Vector3(4.0, 0, 0)
	rustle._inside = []
	rustle._repeat = 0.0
	perception.last_noise = {}
	rustle.step(bush[0] + Vector3(0, 0.9, 0), 1.5, true, 0.1)
	var near: Dictionary = perception.last_noise.duplicate()
	entity.global_position = bush[0] + Vector3(9.0, 0, 0)
	rustle._inside = []
	perception.last_noise = {}
	rustle.step(bush[0] + Vector3(0, 0.9, 0), 1.5, true, 0.1)
	var far: Dictionary = perception.last_noise.duplicate()
	_check("crouching through a bush is heard 4 m away, not 9 m away",
		near.get("kind") == &"rustle_crouch" and near.get("heard", false) and far.get("kind") == &"rustle_crouch" and not far.get("heard", true),
		"near %s, far %s" % [near.get("heard"), far.get("heard")])
	entity.deactivate()
	player.set_physics_process(true)
