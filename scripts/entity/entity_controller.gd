extends CharacterBody3D

## "The Entity" — the main antagonist.
## Systemic Hunting Paradigm: The Entity uses vision cones and audio pings to track the player.
##
## Orchestrator node that delegates to sub-modules:
##   - entity_ai.gd        → FSM state behaviors
##   - entity_sensory.gd   → Vision cone, flashlight detection, audio hearing
##   - entity_navigation.gd → Vantage point selection, outside detection

enum State {
	DORMANT,
	OBSERVE_FROM_TREELINE,  # Night 1 & 2 (Passive Voyeurism)
	PATROL,                 # Wandering the map looking for clues
	CHASE,                  # Active pursuit (Line of sight established)
	RETREAT,                # Physically running away to deep woods
	APPROACH_WINDOW,        # Night 3+ (Moving to glass)
	WINDOW_PEEK,            # Night 2+ (Staring inside)
	RELOCATE,               # Fading out and teleporting to a new position
	STANDOFF,               # Player is staring at Entity with flashlight — frozen in place
	FLINCH,                 # Player inside, Entity outside — lateral sprint to evade flashlight
	CHARGE,                 # Player stared too long — Entity sprints at 3x speed
	INDOOR_SEARCH,          # Entity has breached a window and is hunting inside the cabin
	CLIMB_WALL,             # Entity is climbing the exterior wall to a second-story window
}

@export var speed: float = 4.0
@export var catch_distance: float = 2.5
@export var relocate_radius: float = 20.0
@export var path_update_interval: float = 0.3
@export var stuck_timeout: float = 1.5
@export var fade_duration: float = 0.5
@export var shadow_material: Material = null

@onready var _nav_agent: NavigationAgent3D = $NavigationAgent3D
@onready var _collision_shape: CollisionShape3D = $CollisionShape3D
@onready var _monster_model: Node3D = $MonsterModel if has_node("MonsterModel") else null
@onready var _anim_tree: AnimationTree = $AnimationTree if has_node("AnimationTree") else null
@onready var _growl_audio: AudioStreamPlayer3D = $GrowlAudio if has_node("GrowlAudio") else null
@onready var _footstep_audio: AudioStreamPlayer3D = $FootstepAudio if has_node("FootstepAudio") else null

# Catch Area — a wide overlap zone that detects the player before physics
# collision pushback prevents the distance check from triggering.
var _catch_area: Area3D = null

# Chase music — 2D (non-positional) soundtrack that plays during active pursuit
var _chase_music_player: AudioStreamPlayer = null
var _chase_music_was_playing: bool = false
const CHASE_MUSIC_PATH: String = "res://assets/audio/Echoes - Audio Super Kit/OGG (recommended)/Ambiences/ambience_d6_loop.ogg"
const CHASE_MUSIC_FADE_SPEED: float = 2.0  # Seconds to fade in/out
const CHASE_MUSIC_VOLUME_DB: float = -8.0

# Grunt sound when leaving CHASE state
var _chase_exit_grunt_player: AudioStreamPlayer = null
var _was_chasing: bool = false
const CHASE_EXIT_GRUNT_PATH: String = "res://assets/audio/Entity/Entity_grunt_long.ogg"

# Grunt sound when Entity is repelled by light sanctuary (one-shot, higher pitch)
var _light_sanctuary_grunt_player: AudioStreamPlayer = null


# Night ambience — 2D background soundtrack that plays during non-chase night hours
var _night_ambience_player: AudioStreamPlayer = null
var _night_ambience_was_playing: bool = false
const NIGHT_AMBIENCE_PATH: String = "res://assets/audio/Echoes - Audio Super Kit/OGG (recommended)/Ambiences/ambience_d1_loop.ogg"
const NIGHT_AMBIENCE_FADE_SPEED: float = 3.0  # Seconds to fade in/out
const NIGHT_AMBIENCE_VOLUME_DB: float = -18.0

# Sub-modules
@onready var _ai: Node = $EntityAI if has_node("EntityAI") else null
@onready var _sensory: Node = $EntitySensory if has_node("EntitySensory") else null
@onready var _navigation: Node = $EntityNavigation if has_node("EntityNavigation") else null

var _anim_state_machine: AnimationNodeStateMachinePlayback = null
var _entity_step_timer: float = 0.0
var _entity_step_interval: float = 0.5

var _player: Node3D = null
var _state: State = State.DORMANT
var _is_active: bool = false
var _path_timer: float = 0.0
var _stuck_timer: float = 0.0
var _game_time: float = 0.0

# --- SENSORY & HUNTING VARIABLES ---
var _last_known_position: Vector3 = Vector3.ZERO
var _current_interest_level: float = 0.0
var _is_hunting: bool = false
var _vision_cone_angle: float = deg_to_rad(70.0) # 140-degree field of view
var _interest_decay_rate: float = 2.5 # How fast it loses interest

# --- STATE TRACKING ---
var _last_logged_state: State = State.DORMANT
var _ai_debug_timer: float = 0.0
var _has_logged_sight: bool = false
var _is_at_vantage_point: bool = false

# --- RELOCATION / FADE STATE ---
var _relocate_cooldown: float = 0.0
var _is_fading: bool = false
var _is_fleeing: bool = false
var _flee_angle: float = 0.0
var _flee_direction: int = 1

# --- NIGHT DIFFICULTY (set by entity_ai.gd) ---
var current_night: int = 1
var window_peek_chance: float = 0.60
var current_stalk_speed: float = 4.0
var current_relocate_cooldown: float = 2.5

# --- FLINCH STATE (Flashlight Evasion) ---
## Whether flinching is enabled for the current night.
## Set to false on Night 5 — the Entity never flinches, it immediately sieges.
var _flinch_enabled: bool = true

## Timer counting down the flinch sprint duration (default 1.5 seconds).
var _flinched_timer: float = 0.0

## The world-space position the Entity sprints toward during the flinch.
## Calculated as a lateral vector perpendicular to the player's camera view.
var _flinch_target_pos: Vector3 = Vector3.ZERO

# --- WINDOW PEEK STATE ---
var _window_peek_timer: float = 0.0
var _window_peek_duration: float = 12.0
var _window_peek_marker: Node3D = null
var _window_peek_spotted: bool = false
var _window_peek_vanish_timer: float = 0.0
var _window_peek_vanish_delay: float = 1.0
var _window_peek_staging_pos: Vector3 = Vector3.ZERO
var _retreat_timer: float = 0.0
var _current_window_target: Node3D = null
var _stare_timer: float = 0.0
var _outside_log_timer: float = 0.0
var _visited_markers: Array[Node3D] = []
var _last_vantage_point: Node3D = null
var cabin_center: Vector3 = Vector3(0.0, 0.0, 14.88)

# --- INDOOR BREACH STATE ---
## Reference to the CabinWindow that the Entity broke through to enter the cabin.
## Used by INDOOR_SEARCH to know which window to retreat back through when
## repelled by a light sanctuary.
var _indoor_breach_window: CabinWindow = null


## Index into the Cabin_Patrol_Waypoints group for indoor search patrol looping.
var _indoor_patrol_index: int = 0

# --- WALL CLIMB STATE ---
## Claw-scraping audio player (3D, positioned on the exterior wall).
## Plays a scraping sound as the Entity climbs up the wooden siding.
var _claw_scrape_player: AudioStreamPlayer3D = null

# --- WINDOW BLUFF STATE ---
## When true, the Entity is performing a fake window approach (bluff).
## The Entity moves toward a window, stops short, then backs away to
## create tension and uncertainty for the player.
var _window_bluff_active: bool = false

## Timer for the window bluff sequence.
## Counts down the approach phase, pause phase, and retreat phase.
var _window_bluff_timer: float = 0.0

## The position the Entity retreats to after a bluff.
## Set to the Entity's starting position when the bluff began.
var _window_bluff_retreat_pos: Vector3 = Vector3.ZERO

## Cooldown timer preventing back-to-back bluffs.
## Set to a random value between 8-15 seconds after each bluff completes.
var _window_bluff_cooldown: float = 0.0

# --- LIGHT SABOTAGE STATE ---
## Cooldown timer for light sabotage.
## The Entity can only sabotage one light every 30 seconds to prevent
## the mechanic from being too oppressive.
var _light_sabotage_cooldown: float = 0.0

## Path to the claw scrape audio asset. If the file doesn't exist at this path,
## a programmatic fallback is used: the door creak/grunt asset loaded at pitch 0.4,
## looped, with a randomized stutter effect to simulate nails dragging on wood.
const CLAW_SCRAPE_PATH: String = "res://assets/audio/Entity/claw_scrape_loop.ogg"
const CLAW_SCRAPE_FALLBACK_PATH: String = "res://assets/audio/Entity/Entity_grunt_long.ogg"


func _ready() -> void:
	add_to_group("entity")
	_find_player()
	
	# Set up chase music player (2D, non-positional soundtrack)
	_chase_music_player = AudioStreamPlayer.new()
	_chase_music_player.bus = "Music"
	_chase_music_player.volume_db = -80.0  # Start silent (fade in on chase)
	var chase_stream = load(CHASE_MUSIC_PATH) as AudioStream
	if chase_stream:
		if chase_stream is AudioStreamOggVorbis:
			chase_stream.loop = true
		_chase_music_player.stream = chase_stream
	add_child(_chase_music_player)
	
	# Set up night ambience player (2D, background soundtrack during non-chase night hours)
	_night_ambience_player = AudioStreamPlayer.new()
	_night_ambience_player.bus = "Music"
	_night_ambience_player.volume_db = -80.0  # Start silent (fade in when night starts)
	var ambience_stream = load(NIGHT_AMBIENCE_PATH) as AudioStream
	if ambience_stream:
		if ambience_stream is AudioStreamOggVorbis:
			ambience_stream.loop = true
		_night_ambience_player.stream = ambience_stream
	add_child(_night_ambience_player)
	
	# Set up chase exit grunt player (2D, plays when leaving CHASE state)
	_chase_exit_grunt_player = AudioStreamPlayer.new()
	_chase_exit_grunt_player.bus = "Entity"
	_chase_exit_grunt_player.volume_db = -6.0
	var grunt_stream = load(CHASE_EXIT_GRUNT_PATH) as AudioStream
	if grunt_stream:
		# Explicitly disable looping — the OGG file may have loop=true in its
		# import settings, which would cause this one-shot sound to loop forever.
		if grunt_stream is AudioStreamOggVorbis:
			grunt_stream.loop = false
		_chase_exit_grunt_player.stream = grunt_stream
	add_child(_chase_exit_grunt_player)
	
	# Set up light sanctuary grunt player (2D, one-shot when Entity is repelled by light)
	_light_sanctuary_grunt_player = AudioStreamPlayer.new()
	_light_sanctuary_grunt_player.bus = "Entity"
	_light_sanctuary_grunt_player.volume_db = -3.0  # Slightly louder than chase exit
	_light_sanctuary_grunt_player.pitch_scale = 1.3  # Higher pitch = frustrated/angry
	var sanctuary_stream = load(CHASE_EXIT_GRUNT_PATH) as AudioStream
	if sanctuary_stream:
		# Explicitly disable looping — this is a one-shot frustration sound
		if sanctuary_stream is AudioStreamOggVorbis:
			sanctuary_stream.loop = false
		_light_sanctuary_grunt_player.stream = sanctuary_stream
	add_child(_light_sanctuary_grunt_player)

	
	# Set up claw scrape audio player (3D, positioned on the exterior wall during climbs)
	_claw_scrape_player = AudioStreamPlayer3D.new()
	_claw_scrape_player.bus = "Entity"
	_claw_scrape_player.max_distance = 30.0  # Audible from anywhere near the cabin
	_claw_scrape_player.volume_db = -6.0
	var scrape_stream: AudioStream = null
	if ResourceLoader.exists(CLAW_SCRAPE_PATH):
		scrape_stream = load(CLAW_SCRAPE_PATH) as AudioStream
	if not scrape_stream:
		# Programmatic fallback: load the grunt sound, lower pitch to 0.4, loop it
		print("[Entity] Claw scrape audio not found at ", CLAW_SCRAPE_PATH, ". Using fallback.")
		if ResourceLoader.exists(CLAW_SCRAPE_FALLBACK_PATH):
			scrape_stream = load(CLAW_SCRAPE_FALLBACK_PATH) as AudioStream
		if scrape_stream:
			if scrape_stream is AudioStreamOggVorbis:
				scrape_stream.loop = true
			# The pitch will be set to 0.4 when the climb starts
	if scrape_stream:
		_claw_scrape_player.stream = scrape_stream
	add_child(_claw_scrape_player)
	
	# Set up sub-modules
	if _ai and _ai.has_method("setup"):
		_ai.setup(self)
	if _sensory and _sensory.has_method("setup"):
		_sensory.setup(self)
	if _navigation and _navigation.has_method("setup"):
		_navigation.setup(self)
	
	_nav_agent.path_desired_distance = 2.0
	_nav_agent.target_desired_distance = 2.0
	
	# Validate Model setup
	var active_player: AnimationPlayer = null
	if _monster_model:
		if _monster_model.has_node("AnimationPlayer"):
			active_player = _monster_model.get_node("AnimationPlayer") as AnimationPlayer
	
	if _anim_tree and active_player:
		_anim_tree.anim_player = _anim_tree.get_path_to(active_player)
		_anim_state_machine = _anim_tree.get("parameters/playback")
	
	axis_lock_angular_x = true
	axis_lock_angular_z = true
	floor_constant_speed = true
	floor_snap_length = 0.5
	floor_max_angle = deg_to_rad(60.0)
	
	# Set up the catch area — a wide overlap zone that detects the player
	# before physics collision pushback prevents the distance check from triggering.
	# This ensures the Entity can actually catch the player during a chase.
	_catch_area = Area3D.new()
	_catch_area.name = "CatchArea"
	var catch_shape = CollisionShape3D.new()
	var sphere = SphereShape3D.new()
	sphere.radius = catch_distance
	catch_shape.shape = sphere
	_catch_area.add_child(catch_shape)
	_catch_area.body_entered.connect(_on_catch_area_body_entered)
	add_child(_catch_area)
	
	visible = false
	_set_visuals_visible(false)
	call_deferred("_initialize_entity")


func _set_visuals_visible(v: bool) -> void:
	if _monster_model:
		_monster_model.visible = v


func _initialize_entity() -> void:
	var nm = get_node_or_null("/root/NightManager")
	if nm:
		nm.night_started.connect(_on_night_started)
		nm.night_ended.connect(_on_night_ended)
		nm.first_chase_started.connect(_on_first_chase_started)
		if nm.is_night_active:
			# Night 1 exception: Entity stays hidden for the car alarm narrative
			if nm.current_night == 1:
				print("[Entity] Night 1 at startup: Staying hidden for car alarm narrative.")
			else:
				activate()
				_relocate_behind_player()
	else:
		call_deferred("_initialize_entity")


func _on_night_started(night: int) -> void:
	if _ai and _ai.has_method("on_night_started"):
		_ai.on_night_started(night) # AI updates its speed/chance stats
	
	# Night 1 exception: Entity stays hidden for the car alarm narrative event.
	# The Entity only appears when the player interacts with the van.
	if night == 1:
		print("[Entity] Night 1: Staying hidden for car alarm narrative.")
		return
	
	activate() # Controller handles visibility
	_relocate_behind_player() # Controller handles physical placement


func _on_night_ended(night: int) -> void:
	if _ai and _ai.has_method("on_night_ended"):
		_ai.on_night_ended(night)


## Called when NightManager emits first_chase_started (Night 1 narrative event).
## The Entity makes its cinematic arrival: spawns at the EntityVanSpawn marker,
## then immediately begins chasing the player.
func _on_first_chase_started() -> void:
	print("[Entity] First chase triggered! Making cinematic arrival.")
	
	# Search for the EntityVanSpawn marker in the scene tree.
	# This marker is placed by the level designer at a specific position
	# near the van where the Entity should appear for maximum dramatic impact.
	var spawn_marker: Node3D = null
	var spawn_markers = get_tree().get_nodes_in_group("EntityVanSpawn")
	if not spawn_markers.is_empty():
		spawn_marker = spawn_markers[0] as Node3D
	else:
		# Fallback: try to find a node explicitly named "EntityVanSpawn"
		spawn_marker = get_node_or_null("/root/CottageHorror/EntityVanSpawn")
		if not spawn_marker:
			spawn_marker = get_node_or_null("/root/Main/EntityVanSpawn")
	
	if spawn_marker:
		# Place the Entity exactly at the marker's position
		global_position = spawn_marker.global_position
		_nav_agent.target_position = spawn_marker.global_position
		print("[Entity] Spawned at EntityVanSpawn marker: ", spawn_marker.global_position)
	else:
		# Ultimate fallback: 15 units behind the player
		var behind_dir = -_player.global_transform.basis.z
		var fallback_pos = _player.global_position + behind_dir * 15.0
		fallback_pos.y = 0.0
		global_position = fallback_pos
		_nav_agent.target_position = fallback_pos
		print("[Entity] WARNING: No EntityVanSpawn marker found! Using fallback position.")
	
	# Activate the Entity (make visible) and immediately begin chasing
	activate()
	_state = State.CHASE
	print("[Entity] Cinematic arrival complete! Now chasing the player.")
	
	# ─── SYSTEMIC TIME CRUNCH ──────────────────────────────────────
	# The moment the Entity spawns, the clock is forced to exactly
	# 60 seconds before dawn (cycle_progress ≈ 0.9 for a 600s cycle).
	# The night phase spans 0.5-1.0, and dawn is at cycle_progress 1.0.
	# So 1.0 - (60/600) = 0.9 gives ~60 seconds before dawn.
	# This gives the player exactly 60 seconds to survive.
	# IMPORTANT: Use set_progress() instead of directly assigning cycle_progress
	# so that the internal _elapsed timer stays in sync. Without this, _process()
	# recalculates cycle_progress from the stale _elapsed value and snaps back
	# to daytime.
	var gt = get_node_or_null("/root/GameTime")
	if gt:
		var seconds_before_dawn = 60.0
		var dawn_progress = 1.0 - (seconds_before_dawn / gt.cycle_duration)
		gt.set_progress(dawn_progress)
		gt.is_time_paused = false  # Unpause the clock!
		print("[Entity] Time crunch activated! ", seconds_before_dawn, \
			  " seconds until dawn at cycle_progress ", dawn_progress)





func _find_player() -> void:
	var players = get_tree().get_nodes_in_group("player")
	if players.size() > 0:
		_player = players[0] as Node3D


func activate() -> void:
	_is_active = true
	visible = true
	_state = State.OBSERVE_FROM_TREELINE
	_set_visuals_visible(true)


func deactivate() -> void:
	_is_active = false
	velocity = Vector3.ZERO
	visible = false
	_state = State.DORMANT
	_set_visuals_visible(false)
	
	# ─── STOP ALL AUDIO ────────────────────────────────────────────
	# Immediately stop all looping audio players so no sounds continue
	# playing after the Entity deactivates (e.g., at dawn).
	# The fade-out system in _physics_process() is too slow for a hard
	# deactivation — the audio would keep looping for several seconds.
	if _chase_music_player:
		_chase_music_player.stop()
		_chase_music_player.volume_db = -80.0
		_chase_music_was_playing = false
	if _night_ambience_player:
		_night_ambience_player.stop()
		_night_ambience_player.volume_db = -80.0
		_night_ambience_was_playing = false
	if _chase_exit_grunt_player and _chase_exit_grunt_player.playing:
		_chase_exit_grunt_player.stop()
	if _light_sanctuary_grunt_player and _light_sanctuary_grunt_player.playing:
		_light_sanctuary_grunt_player.stop()
	if _growl_audio and _growl_audio.playing:
		_growl_audio.stop()
	if _claw_scrape_player and _claw_scrape_player.playing:
		_claw_scrape_player.stop()



func _physics_process(delta: float) -> void:
	# ─── EARLY EXIT: Dormant Entity ─────────────────────────────────
	# If the Entity is not active or the player reference is missing,
	# skip ALL processing — no cooldowns, no F2 checks, no logging.
	# This prevents wasted CPU cycles when the Entity is hidden during
	# daytime or Night 1 narrative setup.
	if not _is_active or not _player:
		_game_time += delta
		return
	
	_game_time += delta
	
	if _relocate_cooldown > 0.0:
		_relocate_cooldown -= delta
	
	# F2 debug cooldown decrement
	if _debug_f2_cooldown > 0.0:
		_debug_f2_cooldown -= delta
	
	# Window bluff cooldown decrement
	if _window_bluff_cooldown > 0.0:
		_window_bluff_cooldown -= delta
	
	# Light sabotage cooldown decrement
	if _light_sabotage_cooldown > 0.0:
		_light_sabotage_cooldown -= delta
	
	# ─── DEBUG: F2 — Window Siege Stress Test ──────────────────────────────
	# Development-only shortcut to stress-test the outside-to-inside sequential
	# window destruction system (glass shatter → plank damage → breach → INDOOR_SEARCH).
	# Forces the Entity into APPROACH_WINDOW state with real pathfinding to the
	# first CabinWindow in the "WindowMarkers" group.
	if Input.is_key_pressed(KEY_F2):
		_debug_attack_window()
	
	# --- STATE TRANSITION LOGGING ---
	if _state != _last_logged_state:
		print("[Entity FSM] Transitioned from %s to %s" % [State.keys()[_last_logged_state], State.keys()[_state]])
		_last_logged_state = _state
	
	# --- PERIODIC POSITION LOG (every 2 seconds, unconditional) ---
	# Logs the Entity's current position, state, and distance to the player
	# every 2 seconds. This runs regardless of _debug_logging_enabled so we
	# always have a breadcrumb trail during siege debugging.
	_ai_debug_timer += delta
	if _ai_debug_timer >= 2.0:
		_ai_debug_timer = 0.0
		var dist_to_player = global_position.distance_to(_player.global_position)
		var nav_target = _nav_agent.target_position if _nav_agent else Vector3.ZERO
		var dist_to_nav_target = nav_target.distance_to(global_position)
		print("[Entity PosLog] State=%s | Pos=(%.1f, %.1f, %.1f) | DistToPlayer=%.1f | NavTarget=(%.1f, %.1f, %.1f) | DistToNav=%.1f" % [
			State.keys()[_state],
			global_position.x, global_position.y, global_position.z,
			dist_to_player,
			nav_target.x, nav_target.y, nav_target.z,
			dist_to_nav_target
		])
	
	# --- BACKGROUND SENSE PROCESSING (runs every frame regardless of state) ---
	if _sensory:
		_sensory.can_entity_see_player()
	if _current_interest_level > 0:
		_current_interest_level -= _interest_decay_rate * delta
	
	# --- FLASHLIGHT SPOTTING: Position-Aware Response ---
	# Replaces the legacy "exposure tolerance" system.
	# Checks every frame if the player is shining the flashlight on the Entity.
	# Redirects to one of two behaviors based on player position:
	#
	#   BEHAVIOR 1 (Cowardly Outside Flinch):
	#     Player is INSIDE the cabin, Entity is OUTSIDE.
	#     Entity flinches and sprints laterally to evade the flashlight beam.
	#
	#   BEHAVIOR 2 (Lethal Outside Interception):
	#     Player is OUTSIDE, Entity is OUTSIDE.
	#     Entity immediately charges at 3x speed — no standoff, no flinch.
	#
	#   Night 5 Exception:
	#     Entity never flinches. If spotted while player is inside, it
	#     immediately sieges the nearest window instead.
	#
	# ─── DEBUG MARCH LOCK ──────────────────────────────────────────
	# When the debug march is active, skip ALL flashlight-based state
	# overrides. The developer tool has absolute priority over player
	# inputs during the pathfinding stress test.
	#
	# ─── WINDOW PEEK LOCK ──────────────────────────────────────────
	# When the Entity is actively sieging a window (WINDOW_PEEK state),
	# skip ALL flashlight-based state overrides. The Entity is committed
	# to the siege — the player cannot interrupt it by shining the
	# flashlight at the window. This prevents premature exit from the
	# barricade damage sequence.
	if _state != State.WINDOW_PEEK and _sensory and _sensory.is_player_spotting_entity():
		var player_outside = _navigation.is_player_outside() if _navigation else false
		
		if player_outside:
			# BEHAVIOR 2: Both outside → IMMEDIATE CHARGE (ALL NIGHTS)
			# No standoff freeze, no exposure timer, no fade.
			# The Entity screeches and sprints directly at the player.
			if _state != State.CHARGE and _state != State.FLINCH:
				_state = State.CHARGE
				_nav_agent.target_position = _player.global_position
				print("[Entity] Player spotted Entity outside! IMMEDIATE CHARGE!")
		else:
			# Player inside, Entity outside
			if not _flinch_enabled:
				# --- NIGHT 5 EXCEPTION ---
				# Skip the flinch entirely. The Entity is relentless.
				# Immediately accelerate into a window breach or door siege.
				if _state != State.CHARGE and _state != State.APPROACH_WINDOW and _state != State.WINDOW_PEEK:
					_state = State.APPROACH_WINDOW
					_current_window_target = null
					print("[Entity] Night 5: No flinch! Immediately sieging nearest window!")
			else:
				# BEHAVIOR 1: Cowardly Outside Flinch (Nights 1-4)
				# Entity flinches and sprints laterally to evade the flashlight.
				if _state != State.FLINCH and _state != State.CHARGE:
					_start_flinch()
	
	# --- CHASE MUSIC (ambience_d6_loop) ---
	# Fade in when entering CHASE state, fade out when leaving.
	var is_chasing = _state == State.CHASE
	if is_chasing and not _chase_music_was_playing:
		# Entering chase — start playing and fade in
		if _chase_music_player and _chase_music_player.stream:
			_chase_music_player.play()
		_chase_music_was_playing = true
	elif not is_chasing and _chase_music_was_playing:
		# Leaving chase — begin fade out
		_chase_music_was_playing = false
	
	# --- CHASE EXIT GRUNT ---
	# Play the Entity_grunt_long.ogg sound when the Entity leaves CHASE state.
	# This provides an audio cue that the chase has ended.
	if _was_chasing and not is_chasing:
		if _chase_exit_grunt_player and _chase_exit_grunt_player.stream:
			_chase_exit_grunt_player.play()
			print("[Entity] Playing chase exit grunt.")
	_was_chasing = is_chasing
	
	# Smooth volume interpolation for chase music
	_fade_audio_player(_chase_music_player, is_chasing, CHASE_MUSIC_VOLUME_DB, CHASE_MUSIC_FADE_SPEED, delta)
	
	# --- NIGHT AMBIENCE (ambience_d1_loop) ---
	# Plays during active night hours but ducks out during CHASE so the chase
	# music takes over. Fades in/out smoothly to avoid abrupt audio cuts.
	var should_play_ambience = _is_active and not is_chasing
	if should_play_ambience and not _night_ambience_was_playing:
		# Start playing night ambience
		if _night_ambience_player and _night_ambience_player.stream:
			_night_ambience_player.play()
		_night_ambience_was_playing = true
	elif not should_play_ambience and _night_ambience_was_playing:
		# Begin fade out
		_night_ambience_was_playing = false
	
	# Smooth volume interpolation for night ambience
	_fade_audio_player(_night_ambience_player, should_play_ambience, NIGHT_AMBIENCE_VOLUME_DB, NIGHT_AMBIENCE_FADE_SPEED, delta)
	
	# --- WINDOW BLUFF HANDLER ---
	# When the Entity is bluffing, it moves toward the window for 2 seconds
	# (Phase 1), pauses for 1.5 seconds (Phase 2), then retreats to its
	# starting position (Phase 3). This creates tension and uncertainty.
	if _window_bluff_active:
		_window_bluff_timer -= delta
		
		if _window_bluff_timer > 0.0:
			# Phase 1: Approach — move toward the window
			if _nav_agent.is_navigation_finished():
				velocity = Vector3.ZERO
			else:
				var next_pos = _nav_agent.get_next_path_position()
				var dir_2d := Vector2(next_pos.x - global_position.x, next_pos.z - global_position.z).normalized()
				velocity.x = dir_2d.x * current_stalk_speed
				velocity.z = dir_2d.y * current_stalk_speed
		else:
			# Phase 2 & 3: Pause then retreat
			# After the approach timer expires, stop and stare for 1.5 seconds,
			# then retreat back to the starting position.
			if _window_bluff_timer > -1.5:
				# Phase 2: Pause — stop and stare at the window
				velocity = Vector3.ZERO
			else:
				# Phase 3: Retreat — move back to starting position
				var retreat_dir = (_window_bluff_retreat_pos - global_position).normalized()
				var dist_to_retreat = global_position.distance_to(_window_bluff_retreat_pos)
				if dist_to_retreat < 1.0:
					# Bluff complete — reset and return to normal behavior
					_window_bluff_active = false
					_window_bluff_cooldown = randf_range(8.0, 15.0)
					_current_window_target = null
					_state = State.OBSERVE_FROM_TREELINE
					velocity = Vector3.ZERO
					print("[Entity] Window Bluff complete! Retreating to treeline.")
				else:
					velocity.x = retreat_dir.x * current_stalk_speed * 0.7
					velocity.z = retreat_dir.z * current_stalk_speed * 0.7
		
		move_and_slide()
		_update_animations(delta)
		return
	
	# --- TRANSITION LOCK: RETREAT / RELOCATE / STANDOFF ---
	# During fade/teleport sequences, force velocity to zero and skip movement
	# processing, but STILL execute the AI update tick so that _retreat_state()
	# can call fade_and_relocate(). Without this, the early return would create
	# a deadlock where the AI never runs and the transition never completes.
	# STANDOFF also locks movement — the Entity freezes in place while stared at.
	if _state == State.RETREAT or _state == State.RELOCATE or _state == State.STANDOFF:
		velocity = Vector3.ZERO
		if _ai and _ai.has_method("update"):
			_ai.update(delta)
		_update_animations(delta)
		return
	
	# --- STANDARD ACTIVE NAVIGATION ---
	# Gravity is bypassed during CLIMB_WALL (vertical ascent), WINDOW_PEEK
	# (Entity is stationary at the window frame), and FLINCH (lateral sprint
	# — the Entity stays at its current Y to avoid dropping into terrain).
	if not is_on_floor() and _state != State.WINDOW_PEEK and _state != State.CLIMB_WALL and _state != State.FLINCH:
		velocity += get_gravity() * delta
	
	if _ai and _ai.has_method("update"):
		_ai.update(delta)
	else:
		velocity = Vector3.ZERO
	
	move_and_slide()
	
	var flat_vel = Vector2(velocity.x, velocity.z)
	if flat_vel.length_squared() > 0.05 and _monster_model:
		var target_angle = atan2(flat_vel.x, flat_vel.y)
		_monster_model.rotation.y = lerp_angle(_monster_model.rotation.y, target_angle, delta * 10.0)
	
	_update_animations(delta)


# ─── DEBUG: F2 — Window Siege Stress Test ────────────────────────────────────
# Development-only shortcut to stress-test the outside-to-inside sequential
# window destruction system (glass shatter → plank damage → breach → INDOOR_SEARCH).
#
# When F2 is pressed, the Entity:
#   1. Locates the CabinWindow with window_id == "Hall_Window" in the "WindowMarkers" group.
#   2. Activates itself if dormant.
#   3. Teleports directly to the window's ground-projected position.
#   4. Forces FSM state to WINDOW_PEEK with barricade damage timer initialized.
#   5. The existing _window_peek_state() in entity_ai.gd immediately begins
#      the barricade damage sequence (glass shatter → plank damage → breach).
#
# This is a TELEPORT shortcut — the Entity skips the long pathfinding march
# through the treeline and goes straight to the barricade damage loop.
var _debug_f2_cooldown: float = 0.0


func _debug_attack_window() -> void:
	# Debounce: only trigger once per press (not every frame while held)
	if _debug_f2_cooldown > 0.0:
		return
	_debug_f2_cooldown = 0.5  # 0.5 second cooldown
	
	print("\n========== DEBUG F2: Window Siege Stress Test ==========")
	
	# ─── PART 1: Window Discovery ───────────────────────────────────
	# Scan the active scene tree for nodes registered under the
	# "WindowMarkers" group. Each marker is a child Marker3D of a
	# CabinWindow instance (or the CabinWindow itself).
	var windows = get_tree().get_nodes_in_group("WindowMarkers")
	
	# ─── DIAGNOSTIC: Dump all WindowMarkers group members ───
	print("[F2 Discovery Debug] Dumping all nodes in 'WindowMarkers' group:")
	for node in get_tree().get_nodes_in_group("WindowMarkers"):
		var script_info = "NO SCRIPT"
		if node.get_script():
			script_info = node.get_script().resource_path
		print("  Name: ", node.name, 
			  " | Type: ", node.get_class(), 
			  " | Path: ", node.get_path(),
			  " | Script: ", script_info)
		# Also print parent info for context
		if node.get_parent():
			var parent_script = "NONE"
			if node.get_parent().get_script():
				parent_script = node.get_parent().get_script().resource_path
			print("    Parent: ", node.get_parent().name, 
				  " (", node.get_parent().get_class(), ")",
				  " | Parent Script: ", parent_script)
	print("[F2 Discovery Debug] End of group dump.")
	
	if windows.is_empty():
		print("[F2] ERROR: No WindowMarkers found in scene tree!")
		print("==========================================================\n")
		return
	
	# ─── SINGLE-PASS SCRIPT-VALIDATION LOOP FILTER ────────────────
	# The "WindowMarkers" group may contain:
	#   - CabinWindow root nodes (script on the node itself)
	#   - WindowMarker Marker3D children (script on the parent)
	#   - An organizational "WindowMarkers" Node3D folder
	# We iterate through ALL group members using has_method("damage_barricade")
	# to positively identify the CabinWindow script container, regardless of
	# which node in the hierarchy owns it.
	#
	# TARGET WINDOW SELECTION:
	# We specifically look for the window with window_id == "Hall_Window".
	# This is the front-facing window on the ground floor near the hall area.
	# The Entity will pathfind to this window and begin the barricade damage
	# sequence. Change the target_id string to target a different window.
	#
	# SINGLE-PASS OPTIMIZATION:
	# One loop tracks both the target_id match AND the first valid fallback,
	# eliminating the redundant second pass over the windows array.
	var target_id: String = "Hall_Window"
	var final_window_target: CabinWindow = null
	var first_valid: CabinWindow = null
	for node in windows:
		var candidate: CabinWindow = null
		if node.has_method("damage_barricade"):
			candidate = node as CabinWindow
		elif node.get_parent() and node.get_parent().has_method("damage_barricade"):
			candidate = node.get_parent() as CabinWindow
		
		if not candidate:
			continue
		
		# Track first valid as fallback
		if not first_valid:
			first_valid = candidate
		
		# Check for target_id match
		if candidate.window_id == target_id:
			final_window_target = candidate
			print("[F2] Found target window '", target_id, "' via window_id match: ", node.name)
			break
	
	# Fallback: if no window_id match found, use the first valid window
	if not final_window_target:
		final_window_target = first_valid
		if final_window_target:
			print("[F2] WARNING: No window with window_id='", target_id, "' found. Falling back to first valid window.")
	
	if not final_window_target:
		print("[F2] ERROR: Could not resolve CabinWindow from any marker!")
		print("  Total markers in group: ", windows.size())
		for node in windows:
			print("    - ", node.name, " (", node.get_class(), ") Path: ", node.get_path())
		print("==========================================================\n")
		return
	
	# Store the original state for diagnostic logging
	var original_state = _state
	
	print("[F2] Target window: ", final_window_target.name, " at ", final_window_target.global_position)
	print("[F2] Window state — glass_shattered: ", final_window_target.is_glass_shattered, ", boarded: ", final_window_target.is_boarded)
	
	# ─── PART 2: Teleport to Window + Immediate Barricade Damage ───
	# Activate the Entity if it's dormant (e.g. Night 1 before van alarm)
	if not _is_active:
		activate()
		print("[F2] Entity was dormant. Activated.")
	
	# Teleport the Entity directly to the window's position.
	# This bypasses the long pathfinding march through the treeline.
	# The Entity is placed at the window's ground-projected X/Z with
	# the Entity's current Y to avoid vertical snapping.
	var teleport_pos = final_window_target.global_position
	teleport_pos.y = global_position.y
	global_position = teleport_pos
	velocity = Vector3.ZERO
	print("[F2] Entity teleported to window position: ", teleport_pos)
	
	# Store the breach window reference so the AI knows which window
	# was breached (used for retreat pathfinding if repelled by light).
	_indoor_breach_window = final_window_target
	
	# Force the FSM state to WINDOW_PEEK and initialize the barricade
	# damage timer so the Entity immediately begins damaging the window.
	# This skips the APPROACH_WINDOW → WINDOW_PEEK transition entirely.
	_state = State.WINDOW_PEEK
	_stare_timer = 9999.0  # Stay until barricade is destroyed
	
	# Reset the AI's barricade damage timer so the Entity immediately
	# enters barricade-damage mode on the next physics frame.
	if _ai and _ai.has_method("reset_barricade_timers"):
		_ai.reset_barricade_timers()
	
	print("[F2] Entity state override: ", State.keys()[original_state], " → WINDOW_PEEK")
	print("[F2] Entity teleported directly to window. Barricade damage sequence starting.")
	print("[F2] Window state — glass_shattered: ", final_window_target.is_glass_shattered, ", boarded: ", final_window_target.is_boarded)
	print("==========================================================\n")


# --- PUBLIC API ---

## Teleports the Entity to a new position behind the player.
## Uses treeline vantage points for ALL nights to prevent the Entity from
## teleporting inside the cabin or right next to the player.
func _relocate_behind_player() -> void:
	if not _player:
		return
	velocity = Vector3.ZERO
	
	# Always pick a treeline vantage point, regardless of night.
	# This prevents the broken "5 units away" fallback that could place
	# the Entity inside the cabin on Night 3+.
	var treeline_markers = get_tree().get_nodes_in_group("Treeline_Vantage_Points")
	if not treeline_markers.is_empty():
		var safe_marker = treeline_markers.pick_random()
		_finalize_relocation(safe_marker.global_position, "Deep Woods Snap")
		return
	
	# Ultimate fallback: teleport far away behind the cabin
	_finalize_relocation(Vector3(9.0, 0.0, 40.0), "Fallback")


func _finalize_relocation(spawn_pos: Vector3, method: String) -> void:
	# Place the Entity directly on the target position.
	# The NavMesh or marker position already defines the correct Y coordinate.
	global_position = spawn_pos
	velocity = Vector3.ZERO
	_stuck_timer = 0.0
	_is_at_vantage_point = false
	_current_window_target = null
	
	# Reset the navigation agent target to the new position so the pathfinder
	# doesn't try to navigate from the new location to a stale old target.
	_nav_agent.target_position = spawn_pos
	
	if current_night <= 2:
		_state = State.OBSERVE_FROM_TREELINE
	elif current_night == 3:
		_state = State.APPROACH_WINDOW
	else:
		_state = State.PATROL


## Initiates a window peek sequence. Sets the state to APPROACH_WINDOW
## and clears the current window target so the AI picks a new one.
func _start_window_peek() -> void:
	if not _is_active or not _player:
		return
	_state = State.APPROACH_WINDOW
	_current_window_target = null
	_nav_agent.target_position = _player.global_position
	print("[Entity] Starting window peek sequence.")


## Initiates the FLINCH state — a lateral sprint to evade the player's flashlight.
##
## BEHAVIOR 1 (Cowardly Outside Flinch):
## Called when the player is INSIDE the cabin and shines the flashlight at the
## Entity while it is OUTSIDE. The Entity does NOT fade/teleport — it sprints
## laterally (perpendicular to the player's camera view) at 1.5x speed for
## 1.5 seconds, then transitions to RELOCATE to pick a new vantage point.
##
## DOT PRODUCT ZERO GUARD:
## If the Entity is dead-center in the flashlight beam, the dot product of
## the lateral vector and the direction-to-entity could be exactly 0, making
## sign() return 0 and cancelling the movement entirely. We default to
## side = 1.0 (always slide right) when abs(dot) <= 0.001.
func _start_flinch() -> void:
	if not _player or not _sensory:
		return
	
	var cam = get_viewport().get_camera_3d()
	if not cam:
		return
	
	# Calculate the lateral vector perpendicular to the player's camera view
	var cam_forward = -cam.global_transform.basis.z
	cam_forward.y = 0.0
	cam_forward = cam_forward.normalized()
	
	var to_entity = (global_position - cam.global_position)
	to_entity.y = 0.0
	to_entity = to_entity.normalized()
	
	# Perpendicular vector (left/right relative to camera view)
	var up = Vector3.UP
	var lateral = cam_forward.cross(up).normalized()
	
	# --- DOT PRODUCT ZERO GUARD ---
	# If the Entity is dead-center in the flashlight beam, the dot product
	# of lateral and to_entity could be exactly 0, making sign() return 0
	# and cancelling the movement entirely. Default to sliding RIGHT.
	var dot_lateral = lateral.dot(to_entity)
	var side = 1.0  # Default: always slide right
	if abs(dot_lateral) > 0.001:
		side = sign(dot_lateral)
	
	# Sprint 8 meters laterally to clear the window's line-of-sight
	_flinch_target_pos = global_position + lateral * side * 8.0
	_flinched_timer = 1.5
	_state = State.FLINCH
	print("[Entity] FLINCH! Sprinting laterally to evade flashlight!")


func _on_caught_player() -> void:
	_is_active = false
	velocity = Vector3.ZERO
	if _growl_audio:
		_growl_audio.play()
	var nm = get_node_or_null("/root/NightManager")
	if nm:
		nm.horror_event.emit("entity_caught_player")


## Called when the player enters the Entity's catch area (Area3D overlap zone).
## This provides a reliable catch trigger even when physics collision pushback
## prevents the distance-based check in _stalk_state() from reaching catch_distance.
func _on_catch_area_body_entered(body: Node) -> void:
	if not _is_active:
		return
	if body == _player and _state == State.CHASE:
		print("[Entity] Player entered catch area during chase! Catching player.")
		_on_caught_player()


## Called by the player controller every frame while the player is staring at
## the Entity with the flashlight on. look_timer ranges from 0.0 to 2.0+.
##
## When look_timer > 0.1: Force the Entity into STANDOFF state — frozen in place,
##   oriented to face the player directly.
## When look_timer >= 1.5: Force the Entity into CHARGE state — 3x speed sprint
##   directly at the player with a terrifying screech.
## When look_timer decays back to 0: Return to previous state.
func on_player_stare(look_timer: float) -> void:
	if not _is_active:
		return
	
	# Don't override CHARGE — once charging, the Entity commits
	if _state == State.CHARGE:
		# During CHARGE, continuously update target to the player's current position
		_nav_agent.target_position = _player.global_position
		return
	
	if look_timer >= 1.5 and _state != State.CHARGE:
		# --- TRIGGER CHARGE ---
		_state = State.CHARGE
		_nav_agent.target_position = _player.global_position
		print("[Entity] CHARGE! Player stared too long! Sprinting at 3x speed!")
		
		# Play terrifying screech sound
		if _growl_audio:
			_growl_audio.pitch_scale = 1.5  # Higher pitch for screech
			_growl_audio.play()
		
		return
	
	if look_timer > 0.1:
		# --- STANDOFF STATE ---
		if _state != State.STANDOFF:
			_state = State.STANDOFF
			print("[Entity] STANDOFF! Player is staring at the Entity.")
		
		# Orient the Entity's model to face the player directly
		if _monster_model and _player:
			var dir_to_player = (_player.global_position - global_position).normalized()
			var target_angle = atan2(dir_to_player.x, dir_to_player.z)
			_monster_model.rotation.y = lerp_angle(_monster_model.rotation.y, target_angle, 0.1)
		
		# Freeze velocity
		velocity = Vector3.ZERO
		
	elif _state == State.STANDOFF:
		# Player looked away — return to previous state
		print("[Entity] Player looked away. Exiting STANDOFF.")
		if current_night <= 2:
			_state = State.OBSERVE_FROM_TREELINE
		elif current_night == 3:
			_state = State.APPROACH_WINDOW
		else:
			_state = State.PATROL


## Smoothly fades the Entity out, teleports to a new location, then reappears.
## Uses Godot 4's Tween to animate transparency on all GeometryInstance3D children.
func fade_and_relocate() -> void:
	if _is_fading:
		return
	print("[FadeDebug] fade_and_relocate() called! Current state: ", State.keys()[_state])
	_is_fading = true
	_state = State.RELOCATE
	
	# Force-reset animation to Idle before the fade begins.
	# This kills any "Running" or "Stalk" animation loop so the monster
	# doesn't appear to be mid-stride while turning transparent.
	if _anim_state_machine:
		_anim_state_machine.travel("Idle")
	
	# 1. Smooth Fade Out
	if _monster_model:
		var tween = create_tween()
		# Find all mesh instances within the model
		var meshes = _monster_model.find_children("*", "GeometryInstance3D", true, false)
		for mesh in meshes:
			# 0.0 is opaque, 1.0 is fully transparent
			tween.parallel().tween_property(mesh, "transparency", 1.0, fade_duration)
		
		await tween.finished
		_monster_model.visible = false
		
		# Reset transparency so it is solid when it reappears
		for mesh in meshes:
			mesh.transparency = 0.0
	
	# 2. Wait in the void
	await get_tree().create_timer(randf_range(3.0, 6.0)).timeout
	
	# 3. Pick a new node and teleport
	# For ALL nights, pick a fresh vantage point so the Entity never
	# reappears at a stale coordinate. On Night 3+, the AI state will
	# transition to APPROACH_WINDOW or PATROL after relocation anyway.
	_navigation.pick_next_vantage_point()
	
	# Place the Entity directly on the NavMesh target position.
	# The NavMesh already defines the perfect Y coordinate for the ground,
	# so no vertical buffer is needed. This prevents the entity from
	# appearing to "fall from the sky" when it reappears.
	global_position = _nav_agent.target_position
	
	# 4. Reappear instantly in the new location
	if _monster_model:
		_monster_model.visible = true
	
	_is_fading = false
	_state = State.OBSERVE_FROM_TREELINE
	if _ai and _ai.has_method("reset_exposure"):
		_ai.reset_exposure()


## Initiates a Window Bluff — the Entity fakes an approach toward a window,
## stops short, pauses, then retreats. This creates tension and uncertainty
## for the player, who must guess whether the Entity is actually sieging.
##
## The bluff sequence has three phases:
##   Phase 1 (Approach): Entity moves toward the target window for ~2 seconds.
##   Phase 2 (Pause):    Entity stops and stares at the window for ~1.5 seconds.
##   Phase 3 (Retreat):  Entity backs away to its starting position.
##
## Called from _approach_window_state() in entity_ai.gd when the Entity
## selects a window but decides to bluff instead of commit.
func _start_window_bluff(target_window: Node3D) -> void:
	if _window_bluff_active or _window_bluff_cooldown > 0.0:
		return
	
	_window_bluff_active = true
	_window_bluff_timer = 2.0  # Phase 1: Approach for 2 seconds
	_window_bluff_retreat_pos = global_position
	
	# Set the nav target to the window's position
	_nav_agent.target_position = target_window.global_position
	print("[Entity] Window Bluff started! Approaching window: ", target_window.name)


## Sabotages a CabinLight near the target window by switching it off.
## The Entity reaches through the window frame or uses its supernatural
## influence to flick the light switch, plunging the room into darkness.
##
## This removes the light sanctuary protection from the window, making it
## vulnerable to siege. The player must re-light the room to restore protection.
##
## Called from _approach_window_state() in entity_ai.gd when the Entity
## selects a window that is secured by light.
##
## Cooldown: 30 seconds between sabotages to prevent the mechanic from
## being too oppressive.
func _sabotage_light(target_window: CabinWindow) -> void:
	if _light_sabotage_cooldown > 0.0:
		return
	if not target_window or not target_window.room_light:
		return
	
	# Switch off the room light
	target_window.room_light.switch_off()
	_light_sabotage_cooldown = 30.0
	
	print("[Entity] Light sabotaged! Switched off light for window: ", target_window.window_id)


## Plays a one-shot frustrated grunt when the Entity is repelled by a light
## sanctuary. Uses the dedicated _light_sanctuary_grunt_player with a higher
## pitch (1.3) and slightly louder volume (-3.0 dB) to differentiate it from
## the chase exit grunt. This gives the player clear audio feedback that
## they've successfully escaped into a lit room.
func _play_light_sanctuary_grunt() -> void:
	if _light_sanctuary_grunt_player and _light_sanctuary_grunt_player.stream:
		_light_sanctuary_grunt_player.play()
		print("[Entity] Playing light sanctuary grunt — frustrated by the light!")


## Smoothly fades an AudioStreamPlayer's volume toward a target value.
## Stops playback once fully silent to save resources.
## Used by both chase music and night ambience to avoid code duplication.
func _fade_audio_player(player: AudioStreamPlayer, active: bool, target_vol: float, fade_speed: float, delta: float) -> void:

	if not player:
		return
	var vol_target = target_vol if active else -80.0
	player.volume_db = move_toward(player.volume_db, vol_target, (80.0 / fade_speed) * delta)
	if not active and player.volume_db <= -79.0 and player.playing:
		player.stop()


func _update_animations(_delta: float) -> void:
	if not _anim_state_machine:
		return
	
	# Strictly enforce model grounding offset across ALL frames
	if _monster_model:
		_monster_model.position = Vector3(0.0, -0.95, 0.0)
	
	# Hard clamp animations to Idle if we are fading, relocating, or in a
	# frozen standoff. This prevents the animation state machine from caching
	# and continuously looping the previous sprinting animation during
	# supernatural transitions or while the Entity is locked in place.
	if _state == State.RETREAT or _state == State.RELOCATE or _state == State.DORMANT or _state == State.STANDOFF:
		_anim_state_machine.travel("Idle")
		return
	
	var real_vel := get_real_velocity()
	var horz_speed := Vector2(real_vel.x, real_vel.z).length()
	
	match _state:
		State.CHARGE:
			# Use the running_crawl animation during CHARGE for a terrifying sprint
			_anim_state_machine.travel("running_crawl")
		State.STANDOFF:
			# Drop into Idle while maintaining eye contact with the player
			_anim_state_machine.travel("Idle")
		State.WINDOW_PEEK:
			# If the animation lock timer is active, play the AttackWindow
			# animation. The lock is set to 1.5 seconds by entity_ai.gd's
			# _window_peek_state() each time damage_barricade() is called
			# (every 2.0s). The lock decrements by delta each frame, ensuring
			# the animation plays for its full duration even if the next hit
			# is 2 seconds away.
			if _ai and _ai.has_method("is_barricade_anim_locked") and _ai.is_barricade_anim_locked():
				_anim_state_machine.travel("AttackWindow")
			else:
				_anim_state_machine.travel("Idle")
		State.INDOOR_SEARCH:
			# Phase A (Vault Entry): Entity is climbing through the window frame.
			# Play the EnterWindow animation until the indoor landing is reached.
			if _ai and _ai.has_method("has_arrived_indoor") and not _ai.has_arrived_indoor():
				_anim_state_machine.travel("EnterWindow")
			# Phase B (Stalk Patrol): Low, creeping locomotion while hunting inside.
			elif horz_speed > 0.2:
				_anim_state_machine.travel("running_crawl")
			else:
				_anim_state_machine.travel("Idle")
		State.CLIMB_WALL:
			# Use running_crawl during wall climb for a spider-like ascent
			if horz_speed > 0.2:
				_anim_state_machine.travel("running_crawl")
			else:
				_anim_state_machine.travel("Idle")
		State.FLINCH:
			# Use running_crawl during the lateral sprint flinch
			_anim_state_machine.travel("running_crawl")
		State.CHASE, State.APPROACH_WINDOW, State.OBSERVE_FROM_TREELINE, State.PATROL:
			if real_vel.y > 0.8:
				_anim_state_machine.travel("ClimbUp")
			elif real_vel.y < -0.8 and not is_on_floor():
				_anim_state_machine.travel("ClimbDown")
			elif horz_speed > 0.2:
				_anim_state_machine.travel("Stalk")
			else:
				_anim_state_machine.travel("Idle")
		_:
			_anim_state_machine.travel("Idle")
