extends SceneTree
## The Entity indoors, round A (planning/entity_inside_review.txt):
##   3.1 no lamp on its head: a glint around the eyes, flaring for a charge;
##   3.4 creeping up unseen it goes quiet (silent within 6 m), heard far off,
##       and not hushed while charging or watched;
##   3.2 watched from too far to lunge, it slips into cover out of sight;
##       with the player in a lit room it lurks in the dark out of view.
##
## Run: godot --headless --path . --fixed-fps 60 --script res://tests/inside_test.gd

const HALL := Vector3(6.5, 0.8, 11.0)
const COMPUTER_ROOM := Vector3(12.5, 1.0, 17.5)

var _failures := 0
var _scene: Node
var _entity
var _player: Node3D


func _initialize() -> void:
	_run()


func _frames(n: int) -> void:
	for i in n:
		await physics_frame


func _check(label: String, ok: bool, detail: String = "") -> void:
	if not ok:
		_failures += 1
	print("[INSIDE TEST] %s  %s%s" % ["PASS" if ok else "FAIL", label, ("  (" + detail + ")") if detail != "" else ""])


func _run() -> void:
	_scene = load("res://scenes/cottage_horror.tscn").instantiate()
	_scene.get_node("Player").start_in_dev_mode = false
	root.add_child(_scene)
	current_scene = _scene
	await _frames(60)
	_entity = get_first_node_in_group("entity")
	_player = get_first_node_in_group("player")
	_entity.can_kill = false
	var nm: Node = root.get_node("NightManager")
	nm.is_time_paused = true
	nm.current_night = 3

	_test_glow()
	await _test_footsteps()
	await _test_cover()
	await _test_siege()

	print("[INSIDE TEST] %s" % ("ALL PASSED" if _failures == 0 else "%d FAILED" % _failures))
	_scene.queue_free()
	await _frames(2)
	quit(1 if _failures > 0 else 0)


func _test_glow() -> void:
	var glow: OmniLight3D = _entity.get_node("ProfileGlow")
	var normal: float = glow.omni_range
	_entity.set_eye_glow(6.0)
	var flared: float = glow.omni_range
	_entity.set_eye_glow(1.0)
	_check("glow: a glint around the eyes, not a lamp; it flares for a charge",
		normal <= 1.0 and flared > normal * 2.0 and is_equal_approx(glow.omni_range, normal),
		"%.2f m, flared %.2f m" % [normal, flared])


func _test_footsteps() -> void:
	_entity.activate()
	_player.global_position = COMPUTER_ROOM
	_entity._teleport(_entity.world.snap_to_navmesh(COMPUTER_ROOM + Vector3(-4.0, 0.0, 0.0)))
	await _frames(5)
	var p = _entity.perception
	var audio = _entity.audio
	p.in_player_view = false
	p.distance_to_player = 4.0
	var near: float = audio._closeness_quiet()
	p.distance_to_player = 20.0
	var far: float = audio._closeness_quiet()
	p.distance_to_player = 4.0
	p.in_player_view = true
	var watched: float = audio._closeness_quiet()
	_check("footsteps: silent creeping up unseen within 6 m, heard far off, never hushed when watched",
		near == 1.0 and far == 0.0 and watched == 0.0, "near %.2f, far %.2f, watched %.2f" % [near, far, watched])
	_entity.deactivate()


## Freezes the brain (the test drives HUNT by hand).
func _hunt_by_hand() -> Object:
	_entity.activate()
	_entity.request_state(_entity.State.HUNT)
	_entity._is_active = false
	return _entity.brain.current


func _test_cover() -> void:
	_player.global_position = COMPUTER_ROOM
	await _frames(5)
	_entity._teleport(_entity.world.snap_to_navmesh(HALL))
	await _frames(3)
	var hunt = _hunt_by_hand()
	var p = _entity.perception
	p.player_watching = true
	p.distance_to_player = 12.0
	hunt.update(0.1)
	var hiding: bool = hunt.is_hiding()
	var cover: Vector3 = hunt._cover
	var unseen: bool = hiding and not p.is_in_player_view(cover + Vector3.UP * 1.2)
	_check("watched from too far to lunge: it slips into cover the player can't see",
		hiding and unseen and _entity.world.is_inside_cabin(cover), "cover %s" % cover.snapped(Vector3.ONE * 0.1))
	p.player_watching = false
	_entity._is_active = true
	_entity.deactivate()


func _test_siege() -> void:
	var nm: Node = root.get_node("NightManager")
	var light: Node = _scene.get_node("Cabin Lights/CabinLightHall")
	var was_on: bool = light.is_switched_on
	var power: bool = nm.is_generator_on
	nm.is_generator_on = true
	light.is_switched_on = true
	_player.global_position = HALL
	await _frames(5)
	_entity._teleport(_entity.world.snap_to_navmesh(COMPUTER_ROOM))
	await _frames(3)
	var hunt = _hunt_by_hand()
	var p = _entity.perception
	p.last_seen_position = _player.global_position
	p._last_seen_clock = p._clock
	p.player_watching = false
	hunt.update(0.1)
	var lit: bool = hunt._player_in_lit_room(_player)
	var cover: Vector3 = hunt._cover
	var lurking: bool = hunt.is_hiding() and not p.is_in_player_view(cover + Vector3.UP * 1.2)
	_check("player in a lit room: it lurks in the dark nearby, out of view (not staring in the open)",
		lit and lurking and cover.distance_to(_player.global_position) < 9.0,
		"lit=%s, cover %.1f m from the player" % [lit, cover.distance_to(_player.global_position) if cover != Vector3.INF else -1.0])
	light.is_switched_on = was_on
	nm.is_generator_on = power
	_entity._is_active = true
	_entity.deactivate()
