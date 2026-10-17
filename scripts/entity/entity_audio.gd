class_name EntityAudio
extends Node3D

## The Entity's sounds. Design rule: sparse and positional. No looping voice
## lines that give its position away; short cues with cooldowns, and silence
## in between. Chase music only plays while it is actually charging (or in the
## scripted van chase). Night ambience is HorrorSoundManager's job.

const VOICE_STREAMS := {
	"murmur": [
		preload("res://assets/audio/Entity/Entity Talking.ogg"),
		preload("res://assets/audio/Entity/Entity Talking 2.ogg"),
	],
	"search": [preload("res://assets/audio/Entity/Entity Searching.ogg")],
	"angry": [preload("res://assets/audio/Entity/Entity Angry.ogg")],
}
const GRUNT_STREAM := preload("res://assets/audio/Entity/Entity_grunt_long.ogg")

const ECHOES := "res://assets/audio/Echoes - Audio Super Kit/OGG (recommended)/"
const HORROR_SFX := "res://assets/audio/horror_sfx_vol_1/"
## Growls: winding up to charge, turned away by a lit window.
const GROWL_PATTERN := HORROR_SFX + "Monster Growl/Monster Growl (%d).mp3"
const GROWL_COUNT := 12
const OBJECTS := "res://assets/audio/objects/"
## Claws dragging on the logs while it climbs.
const SCRAPE_PATHS: Array[String] = [OBJECTS + "Climb Scrape.ogg"]
## Hitting the ground when it drops off a wall.
const THUD_PATHS: Array[String] = [OBJECTS + "Drop Thud.ogg"]
## Old boards under its weight.
const CREAK_PATHS: Array[String] = [OBJECTS + "Floor Creak.ogg"]
## Knocking on the glass while it peeks in at a window.
const WINDOW_KNOCK := preload("res://assets/audio/objects/Window Knock.ogg")
## The ambush tell: a breath, close by in the dark.
const TELL_STREAM := preload("res://assets/audio/Entity/Monster_breath.wav")
## Knuckles on the door.
const KNOCK_PATHS: Array[String] = [ECHOES + "SFX/Misc/hit_1.ogg", ECHOES + "SFX/Misc/hit_2.ogg", ECHOES + "SFX/Misc/hit_4.ogg"]
## Extra low murmurs for the "murmur" voice.
## Its charge shriek: monster roars pitched up.
const SHRIEK_PATHS: Array[String] = [
	ECHOES + "SFX/Creatures/Monster/monster_roar_1.ogg", ECHOES + "SFX/Creatures/Monster/monster_roar_2.ogg",
	ECHOES + "SFX/Creatures/Monster/monster_roar_3.ogg", ECHOES + "SFX/Creatures/Monster/monster_roar_4.ogg",
	ECHOES + "SFX/Creatures/Monster/monster_roar_5.ogg", ECHOES + "SFX/Creatures/Monster/monster_roar_6.ogg",
	ECHOES + "SFX/Creatures/Monster/monster_roar_7.ogg",
]
const MURMUR_PATHS: Array[String] = [
	ECHOES + "SFX/Creatures/Monster/monster_talking_1.ogg",
	ECHOES + "SFX/Creatures/Monster/monster_talking_2.ogg",
	ECHOES + "SFX/Creatures/Monster/monster_talking_3.ogg",
]

## Floor creaks: only heard from the other floor, within this distance (m),
## every CREAK_INTERVAL seconds or so while it walks.
const CREAK_DISTANCE := 9.0
const CREAK_INTERVAL_MIN := 1.4
const CREAK_INTERVAL_MAX := 3.0
## Murmurs when it is this close but out of sight, at most this often (s).
const MURMUR_DISTANCE := 12.0
const MURMUR_INTERVAL_MIN := 25.0
const MURMUR_INTERVAL_MAX := 45.0
const MURMUR_STATES := [Entity.State.HUNT, Entity.State.SEARCH, Entity.State.STALK, Entity.State.PEEK]

const VOICE_COOLDOWN := 10.0
## Its copies of the player's own sounds (update_mimicry).
const SWITCH_STREAM := preload("res://assets/audio/objects/light_switch.wav")
const NOTEBOOK_STREAM := preload("res://assets/audio/objects/Toggle Journal.ogg")
const MIMIC_KINDS := ["steps", "steps", "switch", "notebook", "knock"]
const MIMIC_STATES := [Entity.State.HUNT, Entity.State.OBSERVE, Entity.State.STALK,
		Entity.State.SEARCH, Entity.State.APPROACH, Entity.State.PEEK]
const MIMIC_FIRST_MIN := 60.0
const MIMIC_FIRST_MAX := 150.0
const MIMIC_GAP_MIN := 90.0
const MIMIC_GAP_MAX := 200.0
## Copied sounds come from a room at least this far from the player.
const MIMIC_MIN_DISTANCE := 7.0
const FOOTSTEP_PITCH_MIN := 0.7
const FOOTSTEP_PITCH_MAX := 0.95

var entity: Entity
var _voice: AudioStreamPlayer3D
var _sfx: AudioStreamPlayer3D
var _tap: AudioStreamPlayer3D
var _growl: AudioStreamPlayer3D
var _footstep: AudioStreamPlayer3D
var _footstep_db := 0.0   ## its own volume (before hushing)
var _voice_cooldown := 0.0
var _step_timer := 0.0
var _chase_music_on := false
## The hunting music ("too late", HorrorSoundManager.play_stalk_chase) plays
## while it is after the player: stalking them, charging, held off by the
## beam, or searching / prowling the cabin with a fresh trail (seen or
## heard within HUNT_TRAIL_TIME). Never while lying in wait (that silence
## is the point), and not in the Night 2.2 van chase unless
## config.van_chase_music. It lingers HUNT_MUSIC_LINGER s after.
const HUNT_MUSIC_STATES := [Entity.State.STALK, Entity.State.CHARGE, Entity.State.STANDOFF]
const HUNT_TRAIL_STATES := [Entity.State.SEARCH, Entity.State.HUNT]
const HUNT_TRAIL_TIME := 6.0
const HUNT_MUSIC_LINGER := 4.0
var _hunt_linger := 0.0
var _scrape: AudioStreamPlayer3D
var _creak: AudioStreamPlayer3D
var _knock: AudioStreamPlayer3D
var _decoy: AudioStreamPlayer3D
var _decoy_tween: Tween = null
var _shriek: AudioStreamPlayer3D
var _shriek_streams: Array[AudioStream] = []
var _growl_streams: Array[AudioStream] = []
var _scrape_streams: Array[AudioStream] = []
var _thud_streams: Array[AudioStream] = []
var _creak_streams: Array[AudioStream] = []
var _knock_streams: Array[AudioStream] = []
var _murmur_streams: Array[AudioStream] = []
var _creak_left := 0.0
var _murmur_left := 30.0
var _mimic_left := 0.0
var _mimic_night := -1
var _mimics_tonight := 0
var last_mimic := ""   ## The last sound it copied (for tests and the overlay).


func setup(owner_entity: Entity) -> void:
	entity = owner_entity
	position.y = entity.config.eye_height
	_voice = _make_player("Voice", 6.0, 40.0, 2.0)
	_sfx = _make_player("Sfx", 5.0, 35.0, 0.0)
	_tap = _make_player("Tap", 3.0, 18.0, 0.0)
	_tap.top_level = true
	_growl = entity.get_node_or_null("GrowlAudio")
	_footstep = entity.get_node_or_null("FootstepAudio")
	if _footstep:
		_footstep_db = _footstep.volume_db
	_scrape = _make_player("Scrape", 4.0, 30.0, -2.0)
	_scrape.top_level = true
	_creak = _make_player("Creak", 4.0, 20.0, 0.0)
	_creak.top_level = true
	_knock = _make_player("Knock", 5.0, 35.0, 2.0)
	_knock.top_level = true
	# Sounds placed away from it (the fake departure).
	_decoy = _make_player("Decoy", 5.0, 40.0, 0.0)
	_decoy.top_level = true
	# A child of this node (at its eye height), so it moves with it.
	_shriek = _make_player("Shriek", 8.0, 60.0, 4.0)
	_shriek_streams = _load_paths(SHRIEK_PATHS)
	_growl_streams = _load_pattern(GROWL_PATTERN, GROWL_COUNT)
	_creak_streams = _load_paths(CREAK_PATHS)
	_scrape_streams = _load_paths(SCRAPE_PATHS)
	_thud_streams = _load_paths(THUD_PATHS)
	_knock_streams = _load_paths(KNOCK_PATHS)
	_murmur_streams = _load_paths(MURMUR_PATHS)
	_murmur_streams.append_array(VOICE_STREAMS["murmur"])


func _load_paths(paths: Array[String]) -> Array[AudioStream]:
	var streams: Array[AudioStream] = []
	for path in paths:
		if ResourceLoader.exists(path):
			streams.append(load(path) as AudioStream)
	return streams


func _load_pattern(pattern: String, count: int) -> Array[AudioStream]:
	var paths: Array[String] = []
	for i in range(1, count + 1):
		paths.append(pattern % i)
	return _load_paths(paths)


func _make_player(player_name: String, unit_size: float, max_distance: float, volume_db: float) -> AudioStreamPlayer3D:
	var player := AudioStreamPlayer3D.new()
	player.name = player_name
	player.bus = &"Entity"
	player.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_SQUARE_DISTANCE
	player.unit_size = unit_size
	player.max_distance = max_distance
	player.volume_db = volume_db
	add_child(player)
	return player


func _process(delta: float) -> void:
	_voice_cooldown = maxf(_voice_cooldown - delta, 0.0)


## A short voice cue ("murmur", "search", "angry"). Skipped while on cooldown
## unless `force` is set.
func play_voice(kind: String, force: bool = false) -> void:
	if (_voice_cooldown > 0.0 and not force) or not VOICE_STREAMS.has(kind):
		return
	var streams: Array = _murmur_streams if kind == "murmur" and not _murmur_streams.is_empty() else VOICE_STREAMS[kind]
	_voice.stream = streams.pick_random()
	_voice.pitch_scale = randf_range(0.75, 0.9)
	_voice.play()
	_voice_cooldown = VOICE_COOLDOWN


func play_roar() -> void:
	Caption.at(self, "a roar", entity.global_position)
	if _growl:
		_growl.pitch_scale = randf_range(0.85, 1.0)
		_growl.play()


## The shriek as it charges, from its head, wherever it is (indoors too).
func play_shriek() -> void:
	Caption.at(self, "a shriek", entity.global_position)
	if not _shriek or _shriek_streams.is_empty():
		return
	_shriek.stream = _shriek_streams.pick_random()
	_shriek.pitch_scale = randf_range(1.15, 1.3)
	_shriek.play()


## Pained reaction (overcharge beam, stun).
func play_scream() -> void:
	if _growl:
		_growl.pitch_scale = 1.8
		_growl.play()


## Frustrated, low grunt (blocked by light, giving up).
func play_grunt(pitch: float = 1.0) -> void:
	_sfx.stream = GRUNT_STREAM
	_sfx.pitch_scale = pitch
	_sfx.play()


func play_vault() -> void:
	play_grunt(0.7)


## A deep growl (winding up to charge, turned away by a lit window).
func play_growl() -> void:
	if _growl_streams.is_empty():
		play_grunt(0.7)
		return
	_sfx.stream = _growl_streams.pick_random()
	_sfx.pitch_scale = randf_range(0.85, 1.0)
	_sfx.play()


## Claws dragging on the logs as it climbs.
func play_climb_scrape(world_position: Vector3) -> void:
	Caption.at(self, "claws on the wall", world_position)
	if _scrape_streams.is_empty():
		play_tap_at(world_position)
		return
	_scrape.global_position = world_position
	_scrape.stream = _scrape_streams.pick_random()
	_scrape.pitch_scale = randf_range(0.9, 1.1)
	_scrape.play()


## Hitting the ground after dropping off a wall.
func play_drop_thud() -> void:
	if not _thud_streams.is_empty():
		_scrape.global_position = entity.global_position
		_scrape.stream = _thud_streams.pick_random()
		_scrape.pitch_scale = randf_range(0.9, 1.05)
		_scrape.play()
	play_grunt(0.55)


## Three slow knocks on the door at `world_position`.
func play_knocks(world_position: Vector3) -> void:
	Caption.at(self, "knocking", world_position)
	if _knock_streams.is_empty():
		return
	_knock.global_position = world_position
	var tween := create_tween()
	for i in 3:
		tween.tween_callback(_knock_once)
		tween.tween_interval(randf_range(0.55, 0.8))


func _knock_once() -> void:
	_knock.stream = _knock_streams.pick_random()
	_knock.pitch_scale = randf_range(0.65, 0.75)
	_knock.play()


## Boards creaking under it, heard from the other floor of the cabin: only
## when the player is inside on the floor below (or above) and close.
func update_floor_creaks(delta: float, horizontal_speed: float) -> void:
	if horizontal_speed < 0.5 or _creak_streams.is_empty() or not entity.perception.entity_inside \
			or not entity.perception.player_inside or is_lying_in_wait():
		return
	var player := entity.get_player()
	var rise := absf(player.global_position.y - entity.global_position.y)
	if rise < Entity.FLOOR_GAP or Entity._flat_distance(player.global_position, entity.global_position) > CREAK_DISTANCE:
		return
	_creak_left -= delta
	if _creak_left > 0.0:
		return
	_creak_left = randf_range(CREAK_INTERVAL_MIN, CREAK_INTERVAL_MAX)
	_creak.global_position = entity.global_position + Vector3.UP * 0.2
	_creak.stream = _creak_streams.pick_random()
	_creak.pitch_scale = randf_range(0.85, 1.05)
	_creak.play()


## Now and then, when it is close but the player can't see it, a murmur.
func update_murmurs(delta: float) -> void:
	_murmur_left -= delta
	if _murmur_left > 0.0:
		return
	_murmur_left = randf_range(MURMUR_INTERVAL_MIN, MURMUR_INTERVAL_MAX)
	if entity.get_state() in MURMUR_STATES and not entity.perception.in_player_view \
			and entity.perception.distance_to_player < MURMUR_DISTANCE and not is_lying_in_wait():
		play_voice("murmur", true)


## Waiting in ambush (HUNT): it makes no sound at all.
func is_lying_in_wait() -> bool:
	var state = entity.brain.current if entity.brain else null
	return state != null and state.has_method("is_ambushing") and state.is_ambushing()


## The tell before it springs from an ambush: a low breath, close by.
func play_tell() -> void:
	EntityJournal.learn(entity, "ambush")
	Caption.at(self, "a breath", entity.global_position)
	_sfx.stream = TELL_STREAM
	_sfx.pitch_scale = randf_range(0.85, 0.95)
	_sfx.play()


## The sound of it leaving through `link` (while it stays inside): claws on
## the frame, a thud on the ground outside, then a growl out in the yard.
func play_departure(link: CabinEntryLink, yard: Vector3) -> void:
	if _decoy_tween and _decoy_tween.is_valid():
		_decoy_tween.kill()
	var frame := link.entry.global_position + Vector3.UP * 0.8
	var outside := link.start_position + Vector3.UP * 0.3
	_decoy_tween = create_tween()
	_decoy_tween.tween_callback(_decoy_play.bind(frame, _scrape_streams, 1.0))
	_decoy_tween.tween_interval(1.4)
	_decoy_tween.tween_callback(_decoy_play.bind(outside, _thud_streams, 0.95))
	_decoy_tween.tween_interval(randf_range(3.5, 5.0))
	_decoy_tween.tween_callback(_decoy_play.bind(yard + Vector3.UP, _growl_streams, 0.9))


func _decoy_play(at: Vector3, streams: Array, pitch: float) -> void:
	if streams.is_empty():
		return
	_decoy.global_position = at
	_decoy.stream = streams.pick_random()
	_decoy.pitch_scale = pitch * randf_range(0.95, 1.05)
	_decoy.play()


## One dull crack at a window: the glass eased out of its frame.
func play_crack(world_position: Vector3) -> void:
	Caption.at(self, "a dull crack", world_position)
	_tap.global_position = world_position
	_tap.stream = WINDOW_KNOCK
	_tap.pitch_scale = 0.55
	_tap.play()


## Something knocked over: a thud where it fell.
func play_thud_at(world_position: Vector3) -> void:
	_decoy_play(world_position, _thud_streams, 1.15)


## Now and then (Night 3, at most config.mimic_per_night times) it makes the
## player's own sounds somewhere else in the house: their footsteps in
## another room, the notebook, a light switch, a knock on the front door.
## Only while the player is inside and can't see it, and not right after
## another of its tricks (EntityWorld.trick_ready).
func update_mimicry(delta: float) -> void:
	var night := entity.current_night()
	if night != _mimic_night:
		_mimic_night = night
		_mimics_tonight = 0
		_voices_tonight = 0
		_mimic_left = randf_range(MIMIC_FIRST_MIN, MIMIC_FIRST_MAX)
	_mimic_left -= delta
	if _mimic_left > 0.0 or not can_mimic():
		return
	_mimic_left = randf_range(MIMIC_GAP_MIN, MIMIC_GAP_MAX)
	mimic()


func can_mimic() -> bool:
	var p := entity.perception
	return entity.can_break_planks() and _mimics_tonight < entity.config.mimic_per_night \
			and p.player_inside and not p.in_player_view and entity.get_state() in MIMIC_STATES \
			and entity.world.trick_ready()


## Plays one of the player's own sounds (`kind`, or any) in a room away
## from them. False if there is nowhere to put it.
func mimic(kind: String = "") -> bool:
	var player := entity.get_player()
	if player == null:
		player = get_tree().get_first_node_in_group("player") as Node3D
	if player == null:
		return false
	var spot := _mimic_spot(player.global_position)
	if spot == Vector3.INF:
		return false
	if kind == "":
		kind = MIMIC_KINDS.pick_random()
		# Their own voice, now and then (the microphone: PlayerVoice).
		if _voice_clip() and entity.current_night() >= VOICE_FROM_NIGHT and _voices_tonight < 1 and randf() < VOICE_CHANCE:
			kind = "voice"
	var door := _front_door()
	if kind == "knock" and door == null:
		kind = "switch"
	# (Captioned as the player would take it: their own sounds.)
	Caption.at(self, {"steps": "footsteps", "switch": "a light switch", "notebook": "pages turning", "knock": "knocking", "voice": "a voice"}.get(kind, "a sound"),
		door.entry.global_position if kind == "knock" and door else spot)
	match kind:
		"steps":
			_mimic_steps(spot, player)
		"switch":
			_decoy_play(spot + Vector3.UP * 1.3, [SWITCH_STREAM], MIMIC_PITCH)
		"notebook":
			_decoy_play(spot + Vector3.UP, [NOTEBOOK_STREAM], MIMIC_PITCH)
		"knock":
			play_knocks(door.entry.global_position + Vector3.UP * 1.2)
		"voice":
			_voices_tonight += 1
			_decoy_play(spot + Vector3.UP * 1.4, [_voice_clip()], MIMIC_PITCH)
	_mimics_tonight += 1
	last_mimic = kind
	entity.world.note_trick()
	# Written once it's sunk in (a few seconds on).
	get_tree().create_timer(4.0).timeout.connect(func(): EntityJournal.learn(entity, "mimicry"))
	return true


## A room centre far enough from the player (preferably on the other floor).
func _mimic_spot(player_position: Vector3) -> Vector3:
	var far: Array[Vector3] = []
	var other_floor: Array[Vector3] = []
	for center in entity.world.room_centers():
		if center.distance_to(player_position) < MIMIC_MIN_DISTANCE:
			continue
		far.append(center)
		if absf(center.y - player_position.y) >= Entity.FLOOR_GAP:
			other_floor.append(center)
	if not other_floor.is_empty():
		return other_floor.pick_random()
	return far.pick_random() if not far.is_empty() else Vector3.INF


## Five of the player's own footsteps, crossing a room.
## What it copies comes back slightly wrong, as Nest Gamma's copies do (the
## nest teaches it): a little low (MIMIC_PITCH, times _decoy_play's own
## +-5%, so never the player's own pitch), and a walk of MIMIC_STEPS with
## one step MIMIC_LATE seconds late.
const MIMIC_PITCH := 0.89
## The player's voice played back (the microphone): from this night, at most
## once a night, this likely when it copies something.
const VOICE_FROM_NIGHT := 2
const VOICE_CHANCE := 0.5
var _voices_tonight := 0


## The player's last loud moment (PlayerVoice), or null.
func _voice_clip() -> AudioStream:
	var voice := get_tree().get_first_node_in_group("player").get_node_or_null("PlayerVoice") if get_tree().get_first_node_in_group("player") else null
	return voice.loud_clip if voice else null
const MIMIC_STEPS := 4
const MIMIC_LATE := 0.35


func _mimic_steps(spot: Vector3, player: Node) -> void:
	var streams: Array = player.get("wood_footsteps") if player.get("wood_footsteps") else []
	if streams.is_empty():
		streams = _creak_streams
	if _decoy_tween and _decoy_tween.is_valid():
		_decoy_tween.kill()
	var heading := Vector3.FORWARD.rotated(Vector3.UP, randf() * TAU)
	_decoy_tween = create_tween()
	# Four, a little low, and one of them late: almost the player's walk.
	var late := randi_range(1, MIMIC_STEPS - 1)
	for i in MIMIC_STEPS:
		_decoy_tween.tween_callback(_decoy_play.bind(spot + heading * (i * 0.6) + Vector3.UP * 0.1, streams, MIMIC_PITCH))
		_decoy_tween.tween_interval(randf_range(0.45, 0.55) + (MIMIC_LATE if i == late - 1 else 0.0))


func _front_door() -> CabinEntryLink:
	for link in entity.world.entries():
		if link.kind == CabinEntryLink.Kind.DOOR:
			return link
	return null


## Knocking on the glass at a world position (a window).
func play_tap_at(world_position: Vector3) -> void:
	Caption.at(self, "tapping on glass", world_position)
	_tap.global_position = world_position
	_tap.stream = WINDOW_KNOCK
	_tap.pitch_scale = randf_range(0.9, 1.1)
	_tap.play()


## Its footsteps. Far off it is heard (that's the tension); creeping up
## unseen it goes quiet: fading from SILENCE_FADE m, silent within
## SILENCE_DISTANCE. Charging, it pounds.
const SILENCE_DISTANCE := 6.0
const SILENCE_FADE := 11.0


func update_footsteps(delta: float, horizontal_speed: float) -> void:
	if horizontal_speed < 0.5 or not _footstep:
		_step_timer = 0.0
		return
	var quiet := _closeness_quiet()
	if quiet >= 1.0:
		_step_timer = 0.0
		return
	_step_timer -= delta
	if _step_timer > 0.0:
		return
	_step_timer = clampf(1.1 - horizontal_speed * 0.12, 0.22, 0.8)
	var inside := entity.perception.entity_inside
	var streams: Array[AudioStream] = entity.wood_footsteps if inside else entity.grass_footsteps
	if streams.is_empty():
		return
	_footstep.stream = streams.pick_random()
	_footstep.pitch_scale = randf_range(FOOTSTEP_PITCH_MIN, FOOTSTEP_PITCH_MAX)
	# Heard but not seen: worth a caption (it repeats at most every few seconds).
	if not entity.perception.in_player_view:
		Caption.at(self, "heavy footsteps", entity.global_position)
	_footstep.volume_db = _footstep_db + linear_to_db(maxf(1.0 - quiet, 0.001))
	_footstep.play()


## 0 (heard as normal) .. 1 (silent): how much it hushes its steps, creeping
## close to the player unseen. Not while charging or being watched.
func _closeness_quiet() -> float:
	var p := entity.perception
	if entity.get_state() == Entity.State.CHARGE or p.in_player_view:
		return 0.0
	# Creeping to an ambush (or after the fake departure): not a sound.
	if is_lying_in_wait():
		return 1.0
	return clampf(inverse_lerp(SILENCE_FADE, SILENCE_DISTANCE, p.distance_to_player), 0.0, 1.0)


## Whether it is hunting the player right now (see HUNT_MUSIC_STATES).
func is_hunting_player() -> bool:
	if not entity.is_active() or is_lying_in_wait():
		return false
	if entity.van_chase_active and not entity.config.van_chase_music:
		return false
	var state := entity.get_state()
	if state in HUNT_MUSIC_STATES:
		return true
	var p := entity.perception
	return state in HUNT_TRAIL_STATES and (p.has_fresh_sighting(HUNT_TRAIL_TIME) or p.has_fresh_noise(HUNT_TRAIL_TIME))


func update_hunt_music(delta: float) -> void:
	if is_hunting_player():
		_hunt_linger = HUNT_MUSIC_LINGER
		start_chase_music()
	elif _chase_music_on:
		_hunt_linger -= delta
		if _hunt_linger <= 0.0:
			stop_chase_music()


func start_chase_music() -> void:
	if entity.van_chase_active and not entity.config.van_chase_music:
		return
	var hsm := get_node_or_null("/root/HorrorSoundManager")
	if hsm and not _chase_music_on:
		hsm.play_stalk_chase()
		_chase_music_on = true


func stop_chase_music() -> void:
	var hsm := get_node_or_null("/root/HorrorSoundManager")
	if hsm and _chase_music_on:
		hsm.stop_stalk_chase()
	_chase_music_on = false


func stop_all() -> void:
	for player in [_voice, _sfx, _tap, _growl, _footstep, _scrape, _creak, _knock, _shriek, _decoy]:
		if player:
			player.stop()
	if _decoy_tween and _decoy_tween.is_valid():
		_decoy_tween.kill()
	stop_chase_music()
