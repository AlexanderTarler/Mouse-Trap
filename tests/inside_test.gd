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
	await _test_ambush()
	await _test_fake_departure()
	await _test_breach_rhythm()
	await _test_quiet_entry()

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


## Round B, 3.3: from Night 3, after checking a room it may lie in wait:
## hidden, silent, still; close up it breathes (the tell), then lunges.
func _test_ambush() -> void:
	_player.global_position = COMPUTER_ROOM
	await _frames(5)
	_entity._teleport(_entity.world.snap_to_navmesh(HALL))
	await _frames(3)
	var hunt = _hunt_by_hand()
	var p = _entity.perception
	p.player_watching = false
	p.in_player_view = false
	p.can_see_player = false
	p.distance_to_player = 12.0
	var chance: float = _entity.config.ambush_chance
	_entity.config.ambush_chance = 1.0
	hunt._ambush_cooldown = 0.0
	hunt._maybe_ambush()
	_entity.config.ambush_chance = chance
	var spot: Vector3 = hunt._ambush
	_check("ambush: it lies in wait in a spot the player can't see",
		hunt.is_ambushing() and not p.is_in_player_view(spot + Vector3.UP * 1.2), "spot %s" % spot.snapped(Vector3.ONE * 0.1))
	p.distance_to_player = 20.0
	_check("ambush: not a sound on the way there (no footsteps even far off, no murmurs, no creaks)",
		_entity.audio._closeness_quiet() == 1.0 and _entity.audio.is_lying_in_wait())
	var waiting := true
	for i in 30:
		hunt.update(0.1)
		hunt.next_state()
		waiting = waiting and hunt.is_ambushing() and _entity.get_state() == _entity.State.HUNT
	_check("ambush: it keeps waiting (no giving up, no patrol) while nothing comes", waiting)

	# The player walks right up to it.
	_entity._teleport(spot)
	_player.global_position = spot + Vector3(2.0, 0.0, 0.0)
	await _frames(2)
	p.distance_to_player = 2.0
	p.can_see_player = true
	hunt.update(0.1)
	var told: bool = hunt._tell_left > 0.0 and not hunt.is_ambushing()
	hunt.update(0.5)
	var still_waits: bool = hunt.next_state() == -1 and _entity.get_state() == _entity.State.HUNT
	for i in 8:
		hunt.update(0.1)
		hunt.next_state()
	var charge = _entity.brain.current
	_check("ambush: close up it breathes (the tell), waits a second, then lunges, without the roar",
		told and still_waits and _entity.get_state() == _entity.State.CHARGE and is_equal_approx(charge._max_time, _entity.config.charge_max_time),
		"tell=%s waited=%s state=%s" % [told, still_waits, _entity.State.keys()[_entity.get_state()]])
	p.can_see_player = false
	_entity._is_active = true
	_entity.deactivate()


## Round B, 3.5: giving up, once a night, it sounds like it leaves but stays.
func _test_fake_departure() -> void:
	var door = get_nodes_in_group("BottomFloorWindows").filter(func(n): return n.has_method("is_passable")).front()
	door.is_glass_shattered = true   # an open way out to "leave" by
	door.is_boarded = false
	_player.global_position = COMPUTER_ROOM
	await _frames(5)
	_entity._teleport(_entity.world.snap_to_navmesh(HALL))
	await _frames(3)
	var hunt = _hunt_by_hand()
	var p = _entity.perception
	p.player_watching = false
	p.in_player_view = false
	p.can_see_player = false
	p.distance_to_player = 12.0
	var chance: float = _entity.config.fake_departure_chance
	_entity.config.fake_departure_chance = 1.0
	hunt._faked_night = -1
	hunt._since_contact = _entity.config.hunt_give_up_time + 1.0
	hunt.next_state()
	var faked: bool = _entity.get_state() == _entity.State.HUNT and hunt.is_ambushing() and hunt._leave_after_ambush
	var sounds: bool = _entity.audio._decoy_tween != null and _entity.audio._decoy_tween.is_valid()
	_check("fake departure: it sounds like it leaves (window, thud, yard) but waits inside in ambush",
		faked and sounds and _entity.world.is_inside_cabin(hunt._ambush), "faked=%s sounds=%s" % [faked, sounds])
	hunt._ambush_left = 0.0
	hunt.update(0.1)
	hunt.next_state()
	_check("fake departure: nothing came, so it really leaves (quietly)", _entity.get_state() == _entity.State.FLEE)
	var hunt2 = _hunt_by_hand()
	hunt2._since_contact = _entity.config.hunt_give_up_time + 1.0
	hunt2.next_state()
	_check("fake departure: only once a night", _entity.get_state() == _entity.State.FLEE and not hunt2.is_ambushing())
	_entity.config.fake_departure_chance = chance
	_entity._is_active = true
	_entity.deactivate()


## Round B, 3.6: the blows don't keep time, and it may stop halfway.
func _test_breach_rhythm() -> void:
	var breach = _entity.brain.get_state(_entity.State.BREACH)
	var rush := 0
	var long := 0
	for i in 200:
		var wait: float = breach._next_interval()
		if wait < 1.0:
			rush += 1
		elif wait >= 3.5:
			long += 1
	_check("breach: blows in rushes and long silences, not a steady beat", rush > 20 and long > 20,
		"%d rushes, %d silences of 200" % [rush, long])
	var window = get_nodes_in_group("BottomFloorWindows").filter(func(n): return n.has_method("is_passable")).back()
	var link = null
	for l in _entity.world.entries():
		if l.entry == window:
			link = l
	breach._entry = link
	breach._paused = false
	breach._paused_time = 0.0
	breach._start_pause()
	var aside: bool = breach._aside.distance_to(link.start_position) > 1.0
	breach.time = _entity.config.breach_max_time + 5.0
	breach._paused_time = 10.0
	_check("breach: it may stop halfway and step aside, quiet (the pause doesn't count against it)",
		breach.is_pausing() and aside and breach._paused and _entity.config.breach_pause_chance > 0.0)


## Round B, 3.6: an unboarded window of another room, eased open quietly.
func _test_quiet_entry() -> void:
	var windows := get_nodes_in_group("BottomFloorWindows").filter(func(n): return n.has_method("quiet_break") and not n.is_glass_shattered)
	var window = windows.back()
	window.is_boarded = false
	var crunch: AudioStreamPlayer3D = window._glass_crunch_sound
	window.quiet_break()
	var quiet: bool = crunch == null or not crunch.playing
	_check("quiet entry: the glass is out (the way in is open) without the crash",
		window.is_glass_shattered and window.is_passable() and quiet and window._glass_crunch_sound == crunch)
	var approach = _entity.brain.get_state(_entity.State.APPROACH)
	var link = null
	for l in _entity.world.entries():
		if l.entry == windows.front():
			link = l
	approach._entry = link
	approach._quiet = true
	_player.global_position = link.end_position + Vector3.UP * 0.2
	await _frames(3)
	_entity.perception.in_player_view = false
	var own_room: bool = approach._can_enter_quietly()
	_player.global_position = COMPUTER_ROOM
	await _frames(3)
	_entity.perception.in_player_view = false
	_entity.perception.can_see_player = false
	var other_room: bool = link.climb or approach._can_enter_quietly() or _entity.world.player_sees_entry(link)
	_check("quiet entry: only into a room the player isn't in", not own_room and other_room,
		"own room %s, other room %s" % [own_room, other_room])
