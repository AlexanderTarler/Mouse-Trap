extends SceneTree
## The Entity's Mixamo animations (tools/process_entity_anims.gd), each at
## its moment:
##   - Roar: standing its ground before a charge (none for the totem
##     defence), and when a blackout breaks the stun;
##   - HitReact, then the writhing, when the lamp's light strikes it;
##   - LookAround while it searches; Crouch watching from the treeline;
##   - LowCrawl / Crouch for its low gait (stalking while watched);
##   - Punch at the fuse box;
##   - NeckBite when it catches the player;
##   - Dying when the totem burns, then it is gone;
##   - DropLand when it drops off a wall.
##
## Run: godot --headless --path . --fixed-fps 60 --script res://tests/entity_anim_test.gd

const YARD := Vector3(20.0, 0.3, 4.0)

var _failures := 0
var _scene: Node
var _entity
var _player: Node3D


func _initialize() -> void:
	_run()


func _check(label: String, ok: bool, detail: String = "") -> void:
	if not ok:
		_failures += 1
	print("[ANIM TEST] %s  %s%s" % ["PASS" if ok else "FAIL", label, ("  (" + detail + ")") if detail != "" else ""])


func _frames(n: int) -> void:
	for i in n:
		await physics_frame


func _anim() -> String:
	return str(_entity._anim_playback.get_current_node())


func _run() -> void:
	_scene = load("res://scenes/cottage_horror.tscn").instantiate()
	_scene.get_node("Player").start_in_dev_mode = false
	root.add_child(_scene)
	current_scene = _scene
	await _frames(60)
	_entity = get_first_node_in_group("entity")
	_player = get_first_node_in_group("player")
	_entity.can_kill = false
	_player.global_position = YARD

	_test_library()
	await _test_roar()
	await _test_stun()
	await _test_search_and_watch()
	await _test_crawl()
	await _test_punch()
	await _test_drop()
	await _test_bite()
	await _test_dying()

	print("[ANIM TEST] %s" % ("ALL PASSED" if _failures == 0 else "%d FAILED" % _failures))
	_scene.queue_free()
	await _frames(2)
	quit(1 if _failures > 0 else 0)


func _start(at: Vector3) -> void:
	_entity.activate()
	_entity._teleport(at)


func _test_library() -> void:
	var tree: AnimationTree = _entity.get_node("AnimationTree")
	var machine: AnimationNodeStateMachine = tree.tree_root
	var missing: Array[String] = []
	for state in ["Crouch", "LookAround", "LowCrawl", "Roar", "Dying", "NeckBite", "Punch", "HitReact", "DropLand"]:
		if not machine.has_node(state) or not _entity.ANIM_GROUND_OFFSET.has(StringName(state)):
			missing.append(state)
	_check("the nine new animations are states of the Entity's tree, each with a ground offset", missing.is_empty(), str(missing))


func _test_roar() -> void:
	_start(YARD + Vector3(12.0, 0.0, 0.0))
	await _frames(5)
	var from: Vector3 = _entity.global_position
	_entity.request_state(_entity.State.CHARGE)
	await _frames(int(60 * _entity.ROAR_TIME * 0.6))
	var roaring: bool = _anim() == "Roar" and _entity.global_position.distance_to(from) < 0.3
	await _frames(int(60 * (_entity.ROAR_TIME * 0.4 + 0.8)))
	var lunged: bool = _entity.global_position.distance_to(from) > 2.0
	_check("charge: it roars, standing its ground, then lunges", roaring and lunged, "anim %s" % _anim())
	_entity.deactivate()

	_start(YARD + Vector3(12.0, 0.0, 0.0))
	await _frames(5)
	_entity.defend_totem(YARD + Vector3(10.0, 0.0, 0.0))
	await _frames(10)
	_check("totem defence: no roar, straight at the player", _anim() != "Roar" and not _entity.is_playing_oneshot(), _anim())
	_entity.deactivate()

	_start(YARD + Vector3(12.0, 0.0, 0.0))
	await _frames(5)
	_entity.request_state(_entity.State.STUNNED, {"duration": 30.0})
	await _frames(30)
	_entity.on_generator_blackout()
	await _frames(20)
	_check("blackout: the stun breaks and it roars", _anim() == "Roar", _anim())
	_entity.deactivate()


func _test_stun() -> void:
	_start(YARD + Vector3(12.0, 0.0, 0.0))
	await _frames(5)
	_entity.request_state(_entity.State.STUNNED, {"duration": 30.0})
	await _frames(20)
	var hit: String = _anim()
	await _frames(int(60 * 1.2))
	_check("stun: struck (HitReact), then writhing", hit == "HitReact" and _anim() == "entity_in_light", "%s -> %s" % [hit, _anim()])
	_entity.deactivate()


func _test_search_and_watch() -> void:
	_start(YARD + Vector3(12.0, 0.0, 0.0))
	await _frames(5)
	_entity.request_state(_entity.State.SEARCH, {"target": _entity.global_position})
	var looked := false
	for i in 400:
		await physics_frame
		if _anim() == "LookAround":
			looked = true
			break
	_check("search: it looks around where it listens", looked, _anim())
	_entity.deactivate()

	_player.global_position = Vector3(6.5, 0.8, 11.0)   # in the cabin
	_start(YARD + Vector3(14.0, 0.0, -6.0))
	await _frames(5)
	_entity.request_state(_entity.State.OBSERVE)
	await _frames(2)
	# Already at its vantage point: it settles to watch.
	var observe = _entity.brain.current
	observe._spot = _entity.global_position
	observe._start_watching()
	observe._watch_left = 30.0
	await _frames(30)
	var crouched: bool = _entity.get_state() == _entity.State.OBSERVE and _anim() == "Crouch"
	_check("treeline: it watches crouched", crouched, _anim())
	_entity.deactivate()
	_player.global_position = YARD


func _test_crawl() -> void:
	_start(YARD + Vector3(12.0, 0.0, 0.0))
	_entity.request_state(_entity.State.DORMANT)
	await _frames(5)
	# Stand still low, then crawl.
	_entity._is_active = false
	for i in 20:
		_entity._gait = &"crawl"
		_entity._anim_override = &""
		_entity._update_animation(1.0 / 60.0)
		await physics_frame
	var still: String = _anim()
	for i in 20:
		_entity.velocity = Vector3(1.5, 0.0, 0.0)
		_entity.move_and_slide()
		_entity._gait = &"crawl"
		_entity._update_animation(1.0 / 60.0)
		await physics_frame
	var moving: String = _anim()
	_entity.velocity = Vector3.ZERO
	_check("low gait: Crouch standing still, LowCrawl moving", still == "Crouch" and moving == "LowCrawl",
		"%s / %s" % [still, moving])
	_entity.deactivate()


func _test_punch() -> void:
	var box: Node = _entity.world.fuse_box()
	var at: Vector3 = _entity.world.fuse_position()
	_start(at)
	await _frames(5)
	_entity.request_state(_entity.State.SABOTAGE)
	var punching := false
	for i in 300:
		await physics_frame
		if _anim() == "Punch":
			punching = true
			break
	_check("fuse box: it punches it", punching and box != null, _anim())
	_entity.deactivate()


func _test_drop() -> void:
	var src := FileAccess.get_file_as_string("res://scripts/entity/entity.gd")
	_check("drop off a wall: Falling To Landing, landing before it moves on",
		"_set_traversal_anim.bind(&\"DropLand\")" in src and "tween_interval(DROP_LAND_TIME)" in src)


func _test_bite() -> void:
	_start(YARD + Vector3(2.0, 0.0, 0.0))
	await _frames(5)
	var nm: Node = root.get_node("NightManager")
	var jumpscare: Node = root.get_node("JumpscareManager")
	jumpscare.set_process(false)
	# Not the jumpscare and death scene: only the catch itself.
	var caught := [false]
	nm.horror_event.connect(func(event): caught[0] = caught[0] or event == "entity_caught_player", CONNECT_ONE_SHOT)
	jumpscare.is_jumping = true
	_entity._catch()
	await _frames(20)
	_check("caught: it goes for the throat (NeckBite)", _anim() == "NeckBite", _anim())
	jumpscare.is_jumping = false
	jumpscare.set_process(true)
	_entity.deactivate()


func _test_dying() -> void:
	_entity.process_mode = Node.PROCESS_MODE_INHERIT
	_start(YARD + Vector3(8.0, 0.0, 0.0))
	await _frames(5)
	_entity.die()
	await _frames(20)
	var dying: bool = _anim() == "Dying" and _entity.visible
	await _frames(int(60 * (_entity.DYING_TIME + 0.3)))
	_check("totem burnt: it dies where it stands, then is gone",
		dying and not _entity.visible and _entity.process_mode == Node.PROCESS_MODE_DISABLED, "dying=%s" % dying)
