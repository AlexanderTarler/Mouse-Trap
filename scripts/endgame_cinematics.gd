extends Node3D

## EndgameCinematics: the ending cutscenes, directed in code so they play
## wherever things are (the player can die anywhere, the van and the totem
## are 200 m apart).
##
##   Death, "The Drag" (play_death): after the jumpscare the player comes to,
##     dragged through the dirt by the Entity towards the weeping willow (its
##     totem). Under the branches it turns round and swings the player up past
##     itself, back first against the trunk, onto a branch; the player looks
##     down at it reaching up. The first death plays it in full, later ones a
##     short version; any key skips it.
##   Mediocre escape, "It Follows": the van drives off down the road at night
##     to hopeful music. In its tail lights the Entity stands in the road,
##     then it runs, leaps onto the roof and rides along into the fog.
##   Good escape, "Dawn": sunrise and birdsong, the van pulls away past the
##     camera; then the dead ground where the totem stood, ash drifting up.
##
## EndgameManager awaits play_ending_cinematic(); JumpscareManager awaits
## play_death(). Every cutscene ends on a black screen: the caller covers it
## with its own fade and then calls clear_overlay().

const ECHOES := "res://assets/audio/Echoes - Audio Super Kit/OGG (recommended)/"
# Placeholder sounds until the real ones are found (planning/endings_review.txt).
const DRAG_SOUNDS: Array[String] = [ECHOES + "SFX/Misc/slide_1.ogg", ECHOES + "SFX/Misc/slide_2.ogg", ECHOES + "SFX/Misc/slide_4.ogg"]
const BREATHING_SOUND := "res://assets/audio/player/Breathing_slow.wav"
const IMPALE_SOUNDS: Array[String] = [ECHOES + "SFX/Player/Misc/bones_breaking_1.ogg", ECHOES + "SFX/Impacts/impact_1.ogg"]
const STINGER_SOUND := ECHOES + "Bonus/Pure Horror/One-shots/stinger_ph_2.ogg"
const VAN_SOUNDS := "res://assets/audio/objects/van/"
const DOOR_CLOSE_SOUND := VAN_SOUNDS + "Car_Door_Close.ogg"
const ENGINE_START_SOUND := VAN_SOUNDS + "Car_Engine_Start_Up.ogg"
const ENGINE_SOUND := VAN_SOUNDS + "Car_Engine_Loop.ogg"
const ACCELERATION_SOUND := VAN_SOUNDS + "Car_Acceleration.ogg"
const ROOF_THUD_SOUND := ECHOES + "SFX/Impacts/impact_2.ogg"
const ESCAPE_MUSIC := ECHOES + "Soundtracks/hope (complete track).ogg"

## Above the HUD (200), below the jumpscare fade (300) and death screen (400).
const OVERLAY_LAYER := 290
## Where the sun is in the good ending (GameTime progress: 0 is sunrise).
const DAWN_PROGRESS := 0.02
const DRAG_SPEED := 1.25
const VAN_TOP_SPEED := 13.0
const VAN_ACCEL := 2.6

enum VanCam { NONE, DRONE, DRONE_HIGH, REAR, STAY, TRIPOD }
enum EntityMode { NONE, STAND, CHASE, LEAP, ROOF }

@export var death_cam: Camera3D
@export var mediocre_cam: Camera3D
@export var good_cam: Camera3D

@export_group("Escape road")
## Where the van sets off from (on the dirt road; y is ignored).
@export var road_start := Vector3(-4.0, 0.0, -92.0)
## The way the road leads out of the map.
@export var road_direction := Vector3(1.0, 0.0, 0.0)

@export_group("Death")
## Where the drag ends, relative to the willow (the totem tree).
@export var drag_end_offset := Vector3(-4.5, 0.0, 0.0)
## The direction it drags the player in.
@export var drag_direction := Vector3(1.0, 0.0, 0.0)
## How high it hoists the player into the tree (m).
@export var hoist_height := 4.0
## How far from the middle of the trunk the player ends up (m), if the
## trunk isn't found (it's looked for: the player ends up HOIST_CLEARANCE
## off its surface, so the camera never goes into the bark).
@export var hoist_trunk_distance := 1.2
const HOIST_CLEARANCE := 0.5
## The camera's height above the ground while dragged (m), and how far it
## looks up.
const DRAG_EYE_HEIGHT := 0.4
const DRAG_PITCH := 8.0

var _overlay: CanvasLayer
var _black: ColorRect
var _vignette: ColorRect
var _bars: Array[ColorRect] = []
var _running := false
var _skippable := false
var _skipped := false
var _skip_hint: Label = null
var _clock := 0.0
var _shot := Callable()
var _shake := 0.0
var _cam: Camera3D
var _temp: Array[Node] = []
var _tweens: Array[Tween] = []
var _on_end: Array[Callable] = []
## The escapes leave their last shot up behind the ending screen.
var _keep_scene := false

# The drag.
var _d_entity: Node3D
var _d_pos := Vector3.ZERO
var _d_dir := Vector3.FORWARD
var _d_speed := 0.0
var _d_pitch := 0.0
var _d_roll := 0.0
var _d_roll_target := 0.0
var _d_bounce := 0.0
var _d_bounce_target := 0.0
var _d_bump_left := 0.0
var _d_scrape_left := 0.0
var _d_hoist := 0.0
var _d_hoisting := false
var _d_lair := Vector3.ZERO
var _d_entity_spot := Vector3.ZERO
var _d_turn_start := 0.0
var _d_hoist_from := Vector3.ZERO
var _d_hoist_to := Vector3.ZERO
var _d_drop := 0.0

# The van.
var _van: Node3D
var _v_basis := Basis.IDENTITY
var _v_origin := Vector3.ZERO
var _v_dir := Vector3.RIGHT
var _v_side := Vector3.BACK
## Following the gravel road (GravelRoad): where along it the van set off,
## how far right of its centre line it drives, and the van's heading then.
## _road_from < 0: no road, straight along road_direction.
var _road_from := -1.0
var _road_offset := 0.0
var _v_dir0 := Vector3.RIGHT
var _v_half_length := 3.0
var _v_roof := 3.0
var _v_speed := 0.0
var _v_top_speed := VAN_TOP_SPEED
var _v_distance := 0.0
var _v_moving := false
var _v_cam := VanCam.NONE
var _v_cam_snap := true
var _v_tripod := Vector3.ZERO
var _v_engine: AudioStreamPlayer3D
## The engine's loop is on (after the start-up).
var _v_engine_running := false
var _e_mode := EntityMode.NONE
var _e_pos := Vector3.ZERO
var _e_leap_from := Vector3.ZERO
var _e_leap_start := 0.0
## How high its lowest hand/foot sits above its origin in the frozen roof
## pose (measured once it's frozen; INF = not yet).
var _e_roof_lift := INF
var _e_roof_frames := 0

# The empty ground.
var _t_from := Vector3.ZERO
var _t_to := Vector3.ZERO
var _t_look := Vector3.ZERO
var _t_start := 0.0


# ─── Public ─────────────────────────────────────────────────────────────────

## Plays the cutscene for an EndgameManager.Ending (0 death, 1 mediocre,
## 2 good). Await it.
func play_ending_cinematic(ending: int) -> void:
	match ending:
		1:
			await _run(_escape_mediocre)
		2:
			await _run(_escape_good)
		_:
			await play_death()


## The death cutscene, full the first time, short after that. Await it.
func play_death() -> void:
	var full := true
	var em := get_node_or_null("/root/EndgameManager")
	if em and "death_cutscenes_seen" in em:
		full = em.death_cutscenes_seen == 0
		em.death_cutscenes_seen += 1
	_skippable = true
	await _run(_death.bind(full))


## Blacks the screen out right away (before a cutscene takes over).
func cover() -> void:
	_ensure_overlay()
	_black.color = Color(0, 0, 0, 1)


## Takes the cutscene's own black screen away, once the caller's fade is up.
func clear_overlay() -> void:
	if not _overlay:
		return
	_black.color.a = 0.0
	_set_vignette(0.0)
	for bar in _bars:
		bar.visible = false


func is_playing() -> bool:
	return _running


# ─── Running a cutscene ─────────────────────────────────────────────────────

func _run(cutscene: Callable) -> void:
	if _running:
		return
	_ensure_overlay()
	_running = true
	_skipped = false
	_clock = 0.0
	_shake = 0.0
	if _skip_hint:
		_skip_hint.visible = _skippable
		_skip_hint.modulate.a = 0.0
		if _skippable:
			var hint_in := create_tween()
			hint_in.tween_interval(0.6)
			hint_in.tween_property(_skip_hint, "modulate:a", 1.0, 0.8)
	# The player's interaction prompt ("[E] Examine the van") has no place
	# in a cutscene.
	var player := get_tree().get_first_node_in_group("player")
	var grab: Node = player.find_child("PhysicalGrab", true, false) if player else null
	var prompt: Label = grab.get("_prompt_label") if grab else null
	if prompt and prompt.get_parent() is CanvasLayer:
		var layer := prompt.get_parent() as CanvasLayer
		_on_end.append(layer.set.bind("visible", layer.visible))
		layer.visible = false

	await cutscene.call()

	# Done or skipped: end on black and put everything back.
	for tween in _tweens:
		if tween and tween.is_valid():
			tween.kill()
	_tweens.clear()
	_black.color = Color(0, 0, 0, 1)
	_set_vignette(0.0)
	_shot = Callable()
	_shake = 0.0
	if _cam:
		_cam.h_offset = 0.0
		_cam.v_offset = 0.0
	for node in _temp:
		if is_instance_valid(node) and (not _keep_scene or node is AudioStreamPlayer or node is AudioStreamPlayer3D):
			node.queue_free()
	_temp.clear()
	_keep_scene = false
	for restore in _on_end:
		if restore.is_valid():
			restore.call()
	_on_end.clear()
	_running = false
	_skippable = false
	if _skip_hint:
		_skip_hint.visible = false


func _process(delta: float) -> void:
	if not _running:
		return
	_clock += delta
	if _shot.is_valid():
		_shot.call(delta)
	if _cam:
		_cam.h_offset = randf_range(-_shake, _shake) * GameSettings.shake()
		_cam.v_offset = randf_range(-_shake, _shake) * GameSettings.shake()


func _input(event: InputEvent) -> void:
	if not _running or not _skippable or _skipped or _clock < 0.5:
		return
	if (event is InputEventKey or event is InputEventMouseButton or event is InputEventJoypadButton) and event.pressed:
		_skipped = true
		get_viewport().set_input_as_handled()


## Waits `seconds` of cutscene time; returns at once once it is skipped.
func _wait(seconds: float) -> void:
	var end := _clock + seconds
	while _running and not _skipped and _clock < end:
		await get_tree().process_frame


func _tween() -> Tween:
	var tween := create_tween()
	_tweens.append(tween)
	return tween


func _fade(alpha: float, seconds: float) -> void:
	_tween().tween_property(_black, "color:a", alpha, seconds)


func _use_camera(preferred: Camera3D, fov: float) -> Camera3D:
	var previous := get_viewport().get_camera_3d()
	_cam = preferred
	if not _cam:
		_cam = Camera3D.new()
		add_child(_cam)
		_temp.append(_cam)
	_cam.fov = fov
	_cam.near = 0.05
	_cam.make_current()
	if previous and previous != _cam and not _keep_scene:
		_on_end.append(func():
			if is_instance_valid(previous):
				previous.make_current())
	return _cam


# ─── Death: "The Drag" ──────────────────────────────────────────────────────

func _death(full: bool) -> void:
	cover()
	_d_entity = get_tree().get_first_node_in_group("entity") as Node3D
	if _d_entity:
		var was := _d_entity.global_transform
		var was_visible := _d_entity.visible
		var entity := _d_entity
		_on_end.append(func():
			if is_instance_valid(entity):
				entity.global_transform = was
				entity.visible = was_visible)
	var hsm := get_node_or_null("/root/HorrorSoundManager")
	if hsm and hsm.has_method("enter_cinematic"):
		hsm.enter_cinematic()
		_on_end.append(hsm.exit_cinematic)
	var hud := get_tree().get_first_node_in_group("hud")
	if hud and "visible" in hud:
		_on_end.append(hud.set.bind("visible", hud.visible))
		hud.visible = false

	# The drag runs along drag_direction and ends under the willow.
	_d_dir = Vector3(drag_direction.x, 0.0, drag_direction.z).normalized()
	var drag_time := 7.0 if full else 3.2
	_d_lair = _lair_position()
	var end := _d_lair + drag_end_offset
	_d_pos = end - _d_dir * DRAG_SPEED * drag_time
	_d_pos.y = _ground_y(_d_pos)
	_d_speed = 0.0
	_d_pitch = deg_to_rad(DRAG_PITCH)
	_d_hoist = 0.0
	_d_hoisting = false
	_d_drop = 0.0
	_d_bump_left = 0.0
	_d_scrape_left = 0.0
	_use_camera(death_cam, 75.0)
	_shot = _drag_shot
	_drag_shot(0.0)

	if not full:
		await _wait(0.5)
		_d_speed = DRAG_SPEED
		_set_vignette(0.4)
		_fade(0.0, 0.8)
		await _wait(2.4)
		_sfx(IMPALE_SOUNDS[0], -2.0)
		_black.color.a = 1.0
		_set_vignette(0.0)
		await _wait(0.9)
		return

	await _wait(1.2)
	var breathing := _loop(BREATHING_SOUND, -8.0, 0.85)
	_d_speed = DRAG_SPEED
	_set_vignette(0.35)
	_fade(0.0, 1.6)
	await _wait(2.4)
	# Drifting in and out.
	var blink := _tween()
	blink.tween_property(_black, "color:a", 1.0, 0.15)
	blink.tween_interval(0.35)
	blink.tween_property(_black, "color:a", 0.0, 0.5)
	await _wait(1.2)
	# Looking up past it: the willow and the totem's glow.
	_tween().tween_property(self, "_d_pitch", deg_to_rad(DRAG_PITCH + 14.0), 2.0)
	await _wait(2.2)

	# It stops, turns round and swings the player up past itself into the
	# branches, back against the trunk.
	_d_speed = 0.0
	if _d_entity and _d_entity.has_method("cinematic_pose"):
		_d_entity.audio.play_growl()
	_d_hoist_from = _drag_camera_position()
	_d_hoist_to = _hoist_spot()
	_d_entity_spot = _d_pos + _d_dir * 1.9
	_d_entity_spot.y = _ground_y(_d_entity_spot)
	_d_turn_start = _clock
	_d_hoisting = true
	await _wait(0.5)
	var hoist := _tween()
	hoist.tween_property(self, "_d_hoist", 1.0, 1.3)
	_shake = 0.015
	await _wait(1.35)

	# Impaled.
	for path in IMPALE_SOUNDS:
		_sfx(path, 0.0)
	_sfx(STINGER_SOUND, -4.0)
	if breathing:
		breathing.stop()
	_add_stake()
	_set_vignette(0.95)
	_tween().tween_property(self, "_d_drop", -0.45, 0.08)
	_shake = 0.07
	_tween().tween_property(self, "_shake", 0.0, 1.4).set_ease(Tween.EASE_OUT)
	await _wait(1.0)
	# The heartbeat slows; the red pulses and fades with it.
	var pulse := _tween()
	for beat in 3:
		pulse.tween_method(_set_vignette, 0.95, 0.6, 0.25 + beat * 0.2)
		pulse.tween_method(_set_vignette, 0.6, 0.95, 0.15)
	_fade(1.0, 1.8)
	await _wait(2.2)


func _drag_shot(delta: float) -> void:
	_d_pos += _d_dir * _d_speed * delta
	_d_pos.y = lerpf(_d_pos.y, _ground_y(_d_pos), clampf(delta * 8.0, 0.0, 1.0))
	if _d_speed > 0.0:
		# The bumps of being dragged: roll and bounce towards new targets.
		_d_bump_left -= delta
		if _d_bump_left <= 0.0:
			_d_bump_left = 0.3
			_d_roll_target = deg_to_rad(randf_range(-4.0, 4.0))
			_d_bounce_target = randf_range(0.0, 0.07)
		_d_scrape_left -= delta
		if _d_scrape_left <= 0.0:
			_d_scrape_left = randf_range(0.6, 0.9)
			_sfx(DRAG_SOUNDS.pick_random(), -6.0, randf_range(0.7, 0.9))
	else:
		_d_roll_target = 0.0
		_d_bounce_target = 0.0
	_d_roll = lerpf(_d_roll, _d_roll_target, clampf(delta * 10.0, 0.0, 1.0))
	_d_bounce = lerpf(_d_bounce, _d_bounce_target, clampf(delta * 12.0, 0.0, 1.0))

	# Head resting sideways in the dirt. Hoisted, the player is swung round
	# (half a turn) past it to the trunk, ending up looking down at it.
	var h := clampf(_d_hoist, 0.0, 1.0)
	var pitch := lerpf(_d_pitch, deg_to_rad(-52.0), _d_hoist)
	var roll := deg_to_rad(-9.0) * (1.0 - h) + _d_roll + sin(_clock * 9.0) * deg_to_rad(6.0) * h * (1.0 - h) * 4.0
	var looking := _d_dir.rotated(Vector3.UP, PI * h)
	var pos := _drag_camera_position()
	if _d_hoisting:
		# Up first (over its head), then across, round it on one side rather
		# than through it, and slammed into the trunk at the end.
		var across := h * h * h
		var rise := 1.0 - (1.0 - h) * (1.0 - h)
		pos = _d_hoist_from.lerp(_d_hoist_to, across) + _d_dir.cross(Vector3.UP) * sin(PI * across) * 1.3
		pos.y = lerpf(_d_hoist_from.y, _d_hoist_to.y, rise)
	pos.y += _d_drop
	pos.y = maxf(pos.y, _ground_y(pos) + 0.15)
	var basis := Basis.looking_at(looking, Vector3.UP) * Basis(Vector3.RIGHT, pitch) * Basis(Vector3.BACK, roll)
	_cam.global_transform = Transform3D(basis, pos)

	if _d_entity and _d_entity.has_method("cinematic_pose"):
		if _d_hoisting:
			# It turns round as it lifts, and ends up below the branches
			# facing the trunk, reaching up at the player.
			# First it turns to face the player (0.4 s), then carries on
			# round as it swings them up.
			var turn := clampf((_clock - _d_turn_start) / 0.4, 0.0, 1.0)
			var facing := _d_dir.rotated(Vector3.UP, PI * (turn + h))
			_d_entity.cinematic_pose(Transform3D(_facing(facing), _d_entity_spot), &"AttackWindow")
		else:
			# Ahead, walking away with the player's ankle.
			var spot := _d_pos + _d_dir * 1.9
			spot.y = _ground_y(spot)
			var walking := _d_speed > 0.0
			_d_entity.cinematic_pose(Transform3D(_facing(_d_dir), spot), &"Stalk" if walking else &"Idle", 0.55 if walking else 1.0)


func _drag_camera_position() -> Vector3:
	return _d_pos + Vector3.UP * (DRAG_EYE_HEIGHT + _d_bounce)


## Where the player ends up against the willow: hoist_height up, on the
## side the drag came from, HOIST_CLEARANCE off the trunk's surface (found
## with a ray along the drag at that height; the impaling drop below it is
## allowed for).
func _hoist_spot() -> Vector3:
	var level := _d_lair + Vector3.UP * hoist_height
	var fallback := level - _d_dir * hoist_trunk_distance
	var space := get_viewport().world_3d.direct_space_state if get_viewport() else null
	if space == null:
		return fallback
	var nearest := INF
	# The trunk at the camera's height, and where the drop takes it.
	for drop in [0.0, -0.45]:
		var at: Vector3 = level + Vector3.UP * drop
		var query := PhysicsRayQueryParameters3D.create(at - _d_dir * 6.0, at, 1)
		if _d_entity:
			query.exclude = [_d_entity.get_rid()]
		var player := get_tree().get_first_node_in_group("player") as CollisionObject3D
		if player:
			query.exclude += [player.get_rid()]
		var hit := space.intersect_ray(query)
		if hit:
			nearest = minf(nearest, (hit.position - (at - _d_dir * 6.0)).dot(_d_dir))
	if nearest == INF:
		return fallback
	return level - _d_dir * (6.0 - nearest + HOIST_CLEARANCE)


## The weeping willow the Entity is anchored to (or somewhere near the
## player if there is none).
func _lair_position() -> Vector3:
	var totem := get_tree().get_first_node_in_group("totem_anchor") as Node3D
	if totem:
		var spot := totem.global_position
		spot.y = _ground_y(spot)
		return spot
	var player := get_tree().get_first_node_in_group("player") as Node3D
	return player.global_position if player else global_position


## A sharp, bloodied branch jutting up into the bottom of the frame.
func _add_stake() -> void:
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color(0.16, 0.1, 0.06)
	wood.roughness = 1.0
	var blood := StandardMaterial3D.new()
	blood.albedo_color = Color(0.3, 0.0, 0.0)
	blood.roughness = 0.25
	var stake := MeshInstance3D.new()
	var shaft := CylinderMesh.new()
	shaft.top_radius = 0.018
	shaft.bottom_radius = 0.07
	shaft.height = 1.2
	shaft.radial_segments = 6
	shaft.material = wood
	stake.mesh = shaft
	var tip := MeshInstance3D.new()
	var point := CylinderMesh.new()
	point.top_radius = 0.0
	point.bottom_radius = 0.02
	point.height = 0.25
	point.radial_segments = 6
	point.material = blood
	tip.mesh = point
	tip.position.y = 0.72
	stake.add_child(tip)
	_cam.add_child(stake)
	stake.position = Vector3(0.1, -0.55, -0.7)
	stake.rotation = Vector3(deg_to_rad(-50.0), 0.0, deg_to_rad(-8.0))
	_temp.append(stake)


# ─── Mediocre escape: "It Follows" ──────────────────────────────────────────

func _escape_mediocre() -> void:
	cover()
	_keep_scene = true
	if not _setup_van():
		await _wait(1.0)
		return
	var hsm := get_node_or_null("/root/HorrorSoundManager")
	if hsm and hsm.has_method("enter_cinematic"):
		hsm.enter_cinematic()
	var entity := get_tree().get_first_node_in_group("entity") as Node3D
	_add_van_lights(true)
	_letterbox(true)
	_use_camera(mediocre_cam, 60.0)
	_v_top_speed = VAN_TOP_SPEED
	_v_cam = VanCam.DRONE
	_e_mode = EntityMode.NONE
	_shot = _van_shot.bind(entity)
	_van_shot(0.0, entity)
	_start_engine()
	var music := _music(ESCAPE_MUSIC)

	await _wait(1.2)
	_v_moving = true
	_engine_sound(ACCELERATION_SOUND, -2.0)
	_fade(0.0, 1.4)
	await _wait(3.1)

	# The rear view: something standing in the road behind, in the red light.
	_v_cam = VanCam.REAR
	_e_mode = EntityMode.STAND
	_e_pos = _van_position() - _v_dir * (_v_half_length + 3.0)
	_e_pos.y = _ground_y(_e_pos)
	await _wait(0.3)
	_sfx(STINGER_SOUND, -3.0)
	await _wait(0.6)
	# It runs after the van, gaining on it: it stays in the red light.
	_e_mode = EntityMode.CHASE
	await _wait(1.6)

	# From above again: it lands on the roof.
	_v_cam = VanCam.DRONE_HIGH
	_v_cam_snap = true
	_e_leap_from = _van_position() - _v_dir * (_v_half_length + 6.0)
	_e_leap_from.y = _ground_y(_e_leap_from)
	_e_leap_start = _clock
	_e_roof_lift = INF
	_e_roof_frames = 0
	_e_mode = EntityMode.LEAP
	await _wait(0.7)
	_e_mode = EntityMode.ROOF
	_sfx(ROOF_THUD_SOUND, 0.0, 0.7)
	_shake = 0.04
	_tween().tween_property(self, "_shake", 0.0, 0.5)
	await _wait(1.8)
	# The van drives on into the fog, unaware.
	_v_cam = VanCam.STAY
	await _wait(2.5)
	_fade(1.0, 1.6)
	if music:
		_tween().tween_property(music, "volume_db", -40.0, 2.0)
	await _wait(1.9)


# ─── Good escape: "Dawn" ────────────────────────────────────────────────────

func _escape_good() -> void:
	cover()
	_keep_scene = true
	var hsm := get_node_or_null("/root/HorrorSoundManager")
	if hsm and hsm.has_method("enter_cinematic"):
		hsm.enter_cinematic(true)
	_set_dawn()
	_letterbox(true)
	_use_camera(good_cam, 55.0)
	var music := _music(ESCAPE_MUSIC)
	if _setup_van():
		_v_top_speed = 9.0
		var tripod := road_start + _v_dir * 16.0 + _v_side * 7.0
		tripod.y = _ground_y(tripod) + 1.6
		_v_tripod = tripod
		_v_cam = VanCam.TRIPOD
		_shot = _van_shot.bind(null)
		_van_shot(0.0, null)
		_start_engine()
		await _wait(0.8)
		_fade(0.0, 2.0)
		await _wait(0.7)
		_v_moving = true
		await _wait(5.5)
		_fade(1.0, 0.8)
		await _wait(0.9)

	# Where the totem stood: dead ground, ash rising.
	var totem := get_tree().get_first_node_in_group("totem_anchor") as Node3D
	if totem:
		var ground := totem.global_position
		ground.y = _ground_y(ground)
		_add_dead_ground(ground)
		_t_look = ground + Vector3.UP * 0.4
		_t_from = ground + Vector3(-7.0, 1.8, -5.0)
		_t_to = ground + Vector3(-5.0, 1.4, -3.5)
		_t_start = _clock
		_v_cam = VanCam.NONE
		_shot = _totem_shot
		_totem_shot(0.0)
		_fade(0.0, 1.2)
		await _wait(3.6)
	# Into the light, then black.
	_black.color = Color(1.0, 0.95, 0.85, _black.color.a)
	_fade(1.0, 2.0)
	await _wait(2.2)
	_tween().tween_property(_black, "color", Color(0, 0, 0, 1), 1.0)
	if music:
		_tween().tween_property(music, "volume_db", -40.0, 1.5)
	await _wait(1.1)


func _totem_shot(_delta: float) -> void:
	var t := clampf((_clock - _t_start) / 5.5, 0.0, 1.0)
	var pos := _t_from.lerp(_t_to, t * t * (3.0 - 2.0 * t))
	_cam.global_transform = Transform3D(Basis.looking_at(_t_look - pos, Vector3.UP), pos)


func _add_dead_ground(ground: Vector3) -> void:
	var patch := MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = 3.2
	disc.bottom_radius = 3.2
	disc.height = 0.04
	var ash := StandardMaterial3D.new()
	ash.albedo_color = Color(0.08, 0.075, 0.07)
	ash.roughness = 1.0
	disc.material = ash
	patch.mesh = disc
	add_child(patch)
	patch.global_position = ground + Vector3.UP * 0.02
	_temp.append(patch)

	var particles := GPUParticles3D.new()
	particles.amount = 60
	particles.lifetime = 5.0
	particles.preprocess = 3.0
	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	process.emission_box_extents = Vector3(2.5, 0.1, 2.5)
	process.direction = Vector3.UP
	process.spread = 25.0
	process.initial_velocity_min = 0.1
	process.initial_velocity_max = 0.35
	process.gravity = Vector3(0.05, 0.12, 0.0)
	particles.process_material = process
	var flake := QuadMesh.new()
	flake.size = Vector2(0.04, 0.04)
	var flake_material := StandardMaterial3D.new()
	flake_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	flake_material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	flake_material.albedo_color = Color(0.55, 0.53, 0.5)
	flake.material = flake_material
	particles.draw_pass_1 = flake
	add_child(particles)
	particles.global_position = ground + Vector3.UP * 0.1
	_temp.append(particles)


## Morning: the clock stops just after sunrise and the sky follows.
func _set_dawn() -> void:
	var game_time := get_node_or_null("/root/GameTime")
	if game_time and game_time.has_method("pause"):
		game_time.pause()
	var environment := get_tree().get_first_node_in_group("environment_controller")
	if environment:
		if environment.has_method("restore_cycle"):
			environment.restore_cycle()
		if environment.has_method("_on_game_time_changed"):
			environment._on_game_time_changed(DAWN_PROGRESS, true)


# ─── The van ────────────────────────────────────────────────────────────────

## Finds the van and puts it at the start of the road, facing out of the
## map (it's parked facing the trees). The player is in it.
func _setup_van() -> bool:
	var scene := get_tree().current_scene
	_van = scene.find_child("EscapeVan", true, false) as Node3D if scene else null
	if not _van:
		return false
	var player := get_tree().get_first_node_in_group("player") as Node3D
	if player:
		player.visible = false

	_v_dir = Vector3(road_direction.x, 0.0, road_direction.z).normalized()
	_v_side = _v_dir.cross(Vector3.UP).normalized()
	# The model's front: from the rear wheels to the front ones.
	var front := Vector3.ZERO
	var rear := Vector3.ZERO
	var box := AABB()
	var first := true
	for mesh: MeshInstance3D in _van.find_children("*", "MeshInstance3D", true, false):
		var bounds := mesh.global_transform * mesh.get_aabb()
		box = bounds if first else box.merge(bounds)
		first = false
		if "wheel_f" in mesh.name:
			front += bounds.get_center()
		elif "wheel_r" in mesh.name:
			rear += bounds.get_center()
	var facing := front - rear
	facing.y = 0.0
	if facing.length_squared() < 0.01:
		facing = -_van.global_basis.z
	var turn := facing.normalized().signed_angle_to(_v_dir, Vector3.UP)
	_v_basis = Basis(Vector3.UP, turn) * _van.global_basis
	_v_half_length = maxf(box.size.x, box.size.z) * 0.47
	_v_roof = box.end.y - _van.global_position.y
	_v_origin = Vector3(road_start.x, _van.global_position.y, road_start.z)
	_v_dir0 = _v_dir
	# On the gravel road it follows the road's bends (in its lane).
	_road_from = -1.0
	if scene.get_node_or_null("GravelRoad") is GravelRoad:
		_road_from = GravelRoad.project(road_start)
		var at: Dictionary = GravelRoad.sample(_road_from)
		var normal := Vector2(-at.direction.y, at.direction.x)
		_road_offset = (Vector2(road_start.x, road_start.z) - at.position).dot(normal)
	_v_distance = 0.0
	_v_speed = 0.0
	_v_moving = false
	_v_cam_snap = true
	_van.global_transform = Transform3D(_v_basis, _v_origin)
	# Where it lands: the visible roof there (the body's highest point is
	# higher, at the front, so the box top left it hovering).
	var roof := _roof_at(_v_origin - _v_dir * 0.8)
	if roof > -INF:
		_v_roof = roof - _van.global_position.y
	return true


## The van's visible top (its body's triangles) right above `at`, or -INF.
func _roof_at(at: Vector3) -> float:
	var best := -INF
	for mesh: MeshInstance3D in _van.find_children("*", "MeshInstance3D", true, false):
		if mesh.mesh == null or "wheel" in mesh.name:
			continue
		var faces := mesh.mesh.get_faces()
		var xform := mesh.global_transform
		for i in range(0, faces.size(), 3):
			var hit = Geometry3D.ray_intersects_triangle(at + Vector3.UP * 10.0, Vector3.DOWN,
					xform * faces[i], xform * faces[i + 1], xform * faces[i + 2])
			if hit != null:
				best = maxf(best, hit.y)
	return best


func _van_position() -> Vector3:
	if _road_from < 0.0:
		return _v_origin + _v_dir * _v_distance
	var at: Dictionary = GravelRoad.sample(_road_from + _v_distance)
	var p: Vector2 = at.position + Vector2(-at.direction.y, at.direction.x) * _road_offset
	return Vector3(p.x, _v_origin.y, p.y)


func _van_shot(delta: float, entity: Node3D) -> void:
	if not is_instance_valid(_van):
		return
	if _v_moving:
		_v_speed = minf(_v_speed + VAN_ACCEL * delta, _v_top_speed)
	_v_distance += _v_speed * delta
	var pos := _van_position()
	var turn := Basis.IDENTITY
	if _road_from >= 0.0:
		# Turning with the road: a little ahead, so it steers into bends.
		var ahead: Dictionary = GravelRoad.sample(_road_from + _v_distance + 2.0)
		_v_dir = Vector3(ahead.direction.x, 0.0, ahead.direction.y).normalized()
		_v_side = _v_dir.cross(Vector3.UP).normalized()
		turn = Basis(Vector3.UP, _v_dir0.signed_angle_to(_v_dir, Vector3.UP))
	_van.global_transform = Transform3D(turn * _v_basis, pos)
	if _v_engine and _v_engine_running:
		_v_engine.pitch_scale = 0.85 + _v_speed / VAN_TOP_SPEED * 0.45

	var smooth := 1.0 if _v_cam_snap else clampf(delta * 3.0, 0.0, 1.0)
	var look := pos + Vector3.UP * 1.0
	match _v_cam:
		VanCam.DRONE, VanCam.DRONE_HIGH:
			var high := _v_cam == VanCam.DRONE_HIGH
			var target := pos - _v_dir * (13.0 if high else 9.0) + Vector3.UP * (9.0 if high else 6.5) + _v_side * (3.0 if high else 2.5)
			var cam_pos := _cam.global_position.lerp(target, smooth)
			look += _v_dir * 4.0
			_cam.global_transform = Transform3D(Basis.looking_at(look - cam_pos, Vector3.UP), cam_pos)
		VanCam.REAR:
			# Mounted on the back, looking down the road behind.
			var cam_pos := pos - _v_dir * (_v_half_length + 0.3) + Vector3.UP * 1.3
			_cam.global_transform = Transform3D(Basis.looking_at(-_v_dir + Vector3.DOWN * 0.08, Vector3.UP), cam_pos)
		VanCam.STAY:
			var forward := -_cam.global_basis.z
			var wanted := (look - _cam.global_position).normalized()
			_cam.global_transform = Transform3D(Basis.looking_at(forward.slerp(wanted, clampf(delta * 3.0, 0.0, 1.0)), Vector3.UP), _cam.global_position)
		VanCam.TRIPOD:
			var forward := -_cam.global_basis.z if not _v_cam_snap else (look - _v_tripod).normalized()
			var wanted := (look - _v_tripod).normalized()
			_cam.global_transform = Transform3D(Basis.looking_at(forward.slerp(wanted, smooth), Vector3.UP), _v_tripod)
	_v_cam_snap = false

	if not entity or not entity.has_method("cinematic_pose"):
		return
	match _e_mode:
		EntityMode.STAND:
			entity.cinematic_pose(Transform3D(_facing(_v_dir), _e_pos), &"Idle")
		EntityMode.CHASE:
			_e_pos += _v_dir * (_v_speed + 4.0) * delta
			_e_pos.y = _ground_y(_e_pos)
			entity.cinematic_pose(Transform3D(_facing(_v_dir), _e_pos), &"running_crawl", 2.0)
		EntityMode.LEAP:
			var t := clampf((_clock - _e_leap_start) / 0.7, 0.0, 1.0)
			var roof := pos - _v_dir * 0.8 + Vector3.UP * _v_roof
			var arc := _e_leap_from.lerp(roof, t) + Vector3.UP * sin(t * PI) * 2.0
			entity.cinematic_pose(Transform3D(_facing(_v_dir), arc), &"running_crawl", 2.0)
		EntityMode.ROOF:
			var roof := pos - _v_dir * 0.8 + Vector3.UP * _v_roof
			# Crouched on the roof in the charge crawl, frozen mid-stride
			# (anim speed 0 stops its AnimationTree), lowered so its lowest
			# hand or foot rests on the roof (measured once the pose holds).
			_e_roof_frames += 1
			if _e_roof_lift == INF and _e_roof_frames == 3:
				_e_roof_lift = _lowest_contact(entity) - entity.global_position.y
			var lift := _e_roof_lift if _e_roof_lift != INF else 0.0
			entity.cinematic_pose(Transform3D(_facing(_v_dir), roof - Vector3.UP * lift), &"running_crawl", 0.0)


## The height of the Entity's lowest hand or foot (bones), or its origin.
func _lowest_contact(entity: Node3D) -> float:
	var low := entity.global_position.y
	var found := false
	for skeleton in entity.find_children("*", "Skeleton3D", true, false):
		var skel := skeleton as Skeleton3D
		for i in skel.get_bone_count():
			var bone := skel.get_bone_name(i)
			if not ("Hand" in bone or "Toe" in bone or "Foot" in bone):
				continue
			var y := (skel.global_transform * skel.get_bone_global_pose(i)).origin.y
			low = y if not found else minf(low, y)
			found = true
	return low


## Headlights (and red tail lights, which light the road behind).
func _add_van_lights(tail: bool) -> void:
	var pos := _van_position()
	for side in [-1.0, 1.0]:
		var head := SpotLight3D.new()
		head.light_color = Color(1.0, 0.95, 0.8)
		head.light_energy = 6.0
		head.spot_range = 35.0
		head.spot_angle = 28.0
		head.shadow_enabled = true
		_van.add_child(head)
		head.global_position = pos + _v_dir * _v_half_length + Vector3.UP * 1.0 + _v_side * side * 0.75
		head.look_at(head.global_position + _v_dir * 10.0 + Vector3.DOWN * 1.2, Vector3.UP)
		_temp.append(head)
		if tail:
			var back := OmniLight3D.new()
			back.light_color = Color(1.0, 0.05, 0.02)
			back.light_energy = 2.5
			back.omni_range = 16.0
			back.omni_attenuation = 1.6
			_van.add_child(back)
			back.global_position = pos - _v_dir * _v_half_length + Vector3.UP * 1.0 + _v_side * side * 0.75
			_temp.append(back)


## The door shuts, the engine turns over, then runs (looping, its pitch
## following the van's speed).
func _start_engine() -> void:
	if not ResourceLoader.exists(ENGINE_SOUND):
		return
	_engine_sound(DOOR_CLOSE_SOUND, -4.0)
	_v_engine_running = false
	_v_engine = _engine_sound(ENGINE_START_SOUND, -4.0)
	_v_engine.stop()
	_tween().tween_callback(_v_engine.play).set_delay(0.35)
	_v_engine.finished.connect(_engine_running, CONNECT_ONE_SHOT)


func _engine_running() -> void:
	if not is_instance_valid(_v_engine):
		return
	var stream := (load(ENGINE_SOUND) as AudioStream).duplicate()
	if "loop" in stream:
		stream.loop = true
	_v_engine.stream = stream
	_v_engine_running = true
	_v_engine.play()


## A sound from the van (it moves with it).
func _engine_sound(path: String, volume_db: float) -> AudioStreamPlayer3D:
	var player := AudioStreamPlayer3D.new()
	if ResourceLoader.exists(path):
		player.stream = load(path)
	player.bus = &"SFX"
	player.volume_db = volume_db
	player.unit_size = 8.0
	player.max_distance = 90.0
	_van.add_child(player)
	player.position = Vector3.UP
	player.play()
	_temp.append(player)
	return player


# ─── Helpers ────────────────────────────────────────────────────────────────

## A basis whose +Z (the Entity's front) points along `direction`.
func _facing(direction: Vector3) -> Basis:
	var flat := Vector3(direction.x, 0.0, direction.z)
	if flat.length_squared() < 0.0001:
		return Basis.IDENTITY
	return Basis.looking_at(-flat.normalized(), Vector3.UP)


func _ground_y(at: Vector3) -> float:
	var query := PhysicsRayQueryParameters3D.create(Vector3(at.x, at.y + 1.5, at.z), Vector3(at.x, at.y - 20.0, at.z), 1)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	return hit.position.y if hit else at.y


func _sfx(path: String, volume_db: float, pitch: float = 1.0) -> AudioStreamPlayer:
	if _skipped or not ResourceLoader.exists(path):
		return null
	var player := AudioStreamPlayer.new()
	player.stream = load(path)
	player.bus = &"SFX"
	player.volume_db = volume_db
	player.pitch_scale = pitch
	add_child(player)
	player.play()
	player.finished.connect(player.queue_free)
	_temp.append(player)
	return player


func _loop(path: String, volume_db: float, pitch: float = 1.0) -> AudioStreamPlayer:
	var player := _sfx(path, volume_db, pitch)
	if player:
		player.finished.disconnect(player.queue_free)
		player.finished.connect(player.play)
	return player


func _music(path: String) -> AudioStreamPlayer:
	var player := _sfx(path, -30.0)
	if player:
		player.bus = &"Master"
		_tween().tween_property(player, "volume_db", -9.0, 3.0)
	return player


func _ensure_overlay() -> void:
	if _overlay:
		return
	_overlay = CanvasLayer.new()
	_overlay.name = "CinematicOverlay"
	_overlay.layer = OVERLAY_LAYER
	add_child(_overlay)

	_vignette = ColorRect.new()
	_vignette.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var shader := Shader.new()
	shader.code = """
shader_type canvas_item;
uniform float amount = 0.0;
void fragment() {
	float edge = smoothstep(0.2, 0.75, length(UV - vec2(0.5)) * 1.3);
	COLOR = vec4(0.4, 0.0, 0.0, clamp(edge * amount + amount * 0.3, 0.0, 1.0));
}
"""
	var material := ShaderMaterial.new()
	material.shader = shader
	_vignette.material = material
	_overlay.add_child(_vignette)

	for top in [true, false]:
		var bar := ColorRect.new()
		bar.color = Color.BLACK
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bar.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE if top else Control.PRESET_BOTTOM_WIDE)
		bar.anchor_bottom = 0.1 if top else 1.0
		bar.anchor_top = 0.0 if top else 0.9
		bar.offset_top = 0.0
		bar.offset_bottom = 0.0
		bar.visible = false
		_overlay.add_child(bar)
		_bars.append(bar)

	_black = ColorRect.new()
	_black.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_black.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_black.color = Color(0, 0, 0, 0)
	_overlay.add_child(_black)
	_set_vignette(0.0)

	# "Press any key to skip", for the skippable ones (the death scene).
	_skip_hint = Label.new()
	_skip_hint.text = "Press any key to skip"
	_skip_hint.add_theme_font_size_override("font_size", 16)
	_skip_hint.add_theme_color_override("font_color", Color(1, 1, 1, 0.55))
	_skip_hint.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	_skip_hint.add_theme_constant_override("outline_size", 4)
	_skip_hint.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	_skip_hint.offset_left = -260.0
	_skip_hint.offset_top = -48.0
	_skip_hint.offset_right = -24.0
	_skip_hint.offset_bottom = -20.0
	_skip_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_skip_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_skip_hint.visible = false
	_overlay.add_child(_skip_hint)


func _set_vignette(amount: float) -> void:
	if _vignette:
		(_vignette.material as ShaderMaterial).set_shader_parameter("amount", amount)
		_vignette.visible = amount > 0.0


func _letterbox(on: bool) -> void:
	for bar in _bars:
		bar.visible = on
