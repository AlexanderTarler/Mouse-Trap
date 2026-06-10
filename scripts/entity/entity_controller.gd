extends CharacterBody3D

## "The Entity" — the main antagonist.
## Systemic Hunting Paradigm: The Entity uses vision cones and audio pings to track the player.
##
## Orchestrator node that delegates to sub-modules:
##   - entity_ai.gd        → FSM state behaviors
##   - entity_sensory.gd   → Vision cone, flashlight detection, audio hearing
##   - entity_navigation.gd → Vantage point selection, outside detection
##
## NOTE: The State enum is now defined in entity_ai.gd.
## Reference states as EntityAI.State.X from this script.
const EntityAI := preload("entity_ai.gd")

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
var _chase_exit_grunt_cooldown: float = 0.0
const CHASE_EXIT_GRUNT_COOLDOWN_DURATION: float = 5.0
const CHASE_EXIT_GRUNT_PATH: String = "res://assets/audio/Entity/Entity_grunt_long.ogg"

# Grunt sound when Entity is repelled by light sanctuary (one-shot, higher pitch)
var _light_sanctuary_grunt_player: AudioStreamPlayer = null

## Debounce flag for the light sanctuary grunt sound.
## Prevents the frustrated grunt from repeating every frame while the player
## remains in a lit room. Set to true when the sound plays, reset to false
## when the Entity fades/relocates or resets exposure.
var _has_played_light_sound: bool = false

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
@onready var _confidence: Node = $EntityConfidence if has_node("EntityConfidence") else null

var _anim_state_machine: AnimationNodeStateMachinePlayback = null
var _entity_step_timer: float = 0.0
var _entity_step_interval: float = 0.5

var _player: Node3D = null
var _state: EntityAI.State = EntityAI.State.DORMANT
var _is_active: bool = false
var _path_timer: float = 0.0
var _stuck_timer: float = 0.0
var _game_time: float = 0.0

# Cached NightManager reference — resolved once in _initialize_entity().
# Sub-modules access this via get_night_manager() instead of polling
# get_node_or_null("/root/NightManager") every frame.
var _night_manager: Node = null

# Cached portable trap reference — resolved via group lookup in _ready().
# Sub-modules access this via get_portable_trap() instead of calling
# get_tree().get_first_node_in_group("portable_trap") every frame.
# Updated by _refresh_portable_trap() when the trap is deployed/undeployed.
var _portable_trap: Node = null

# Cached array of CabinLight nodes — resolved via group lookup in _ready().
# Sub-modules access this via get_cabin_lights() instead of calling
# get_tree().get_nodes_in_group("CabinLights") every frame.
# Updated by _refresh_cabin_lights() when lights are added/removed.
var _cabin_lights: Array[Node] = []

# --- BLACKBOARD: Sensory Data (written by external scripts, read by Director) ---
## Whether the Entity is currently illuminated by the player's flashlight beam.
## Written by on_player_stare(). Read by the Master Director (entity_director.gd).
var is_illuminated: bool = false

## How long the player has been staring at the Entity with the flashlight on.
## Written by on_player_stare(). Read by the Master Director (entity_director.gd).
## Range: 0.0 to 2.0+. 1.5+ triggers CHARGE if player is outside.
var player_stare_timer: float = 0.0

# --- BLACKBOARD: State Lock (prevents Director from overriding mid-execution) ---
## When true, the Master Director MUST return the current state, preventing
## transitions until the state handler unlocks it.
## Set to true by state handlers on entry, set to false on completion.
## This prevents "State Flapping" where the Director and FSM fight over
## the state variable every frame.
var state_locked: bool = false

# --- BLACKBOARD: State Completion Flags (written by FSM handlers, read by Director) ---
## Set to true by _approach_window_state() when the Entity arrives at the target window.
## The Director checks this flag and transitions to WINDOW_PEEK.
var is_approach_finished: bool = false

## Set to true by _window_peek_state() when the window is unbarricaded and siege timer
## has elapsed. The Director checks this flag and transitions to INDOOR_SEARCH.
var is_window_unbarricaded: bool = false

## Set to true by _climb_wall_state() when the vertical ascent completes.
## The Director checks this flag and transitions to WINDOW_PEEK.
var is_climb_finished: bool = false

## Set to true by _retreat_state() when the Entity arrives at the farthest treeline
## vantage point. The Director checks this flag and transitions to OBSERVE_FROM_TREELINE.
var is_retreat_arrived: bool = false

## Set to true by _flinch_state() when the lateral sprint completes.
## The Director checks this flag and transitions to RELOCATE.
var is_flinch_finished: bool = false

## Set to true by _observe_from_treeline_state() or _window_peek_state() when the
## stare timer expires. The Director checks this flag, calls fade_and_relocate()
## for the setup work, and transitions to OBSERVE_FROM_TREELINE.
var is_observe_finished: bool = false

## ─── INDOOR RETREAT FLAG ──────────────────────────────────────────────────────
## Set to true by the Director (Tier 0) when the Entity is illuminated while in
## INDOOR_SEARCH state. The RETREAT handler reads this flag to know it should
## pathfind to the breach window (instead of the farthest treeline), teleport
## outside, and perform a 5-second flinch before transitioning to OBSERVE.
## Reset to false by the RETREAT handler when the indoor retreat completes.
var is_indoor_retreat: bool = false

# --- SENSORY & HUNTING VARIABLES ---
var _last_known_position: Vector3 = Vector3.ZERO
var _current_interest_level: float = 0.0
var _is_hunting: bool = false
var _vision_cone_angle: float = deg_to_rad(70.0) # 140-degree field of view
var _interest_decay_rate: float = 2.5 # How fast it loses interest

# --- STATE TRACKING ---
var _last_logged_state: EntityAI.State = EntityAI.State.DORMANT
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

## The world-space landing position the Entity vaults toward during INDOOR_SEARCH
## Phase A (vault entry). Set by the breach window's landing marker when the
## Entity breaks through. Used by entity_ai.gd's _indoor_search_state() to
## navigate the Entity to the correct interior position before Phase B begins.
var _indoor_landing_position: Vector3 = Vector3.ZERO

## Sound cooldown registry — a single Dictionary replacing 80+ individual
## cooldown variables for WINDOW_PEEK atmospheric sounds.
##
## Keys are lowercase snake_case strings (e.g., "footstep", "window_rattle").
## Values are float cooldown timers that count down each frame.
## When a cooldown reaches <= 0.0, the corresponding sound can play.
##
## This eliminates the need for 80+ individual _xxx_cooldown variables in
## the controller, keeping the state surface minimal and the code DRY.
var _sound_cooldowns: Dictionary = {}

## Index into the Cabin_Patrol_Waypoints group for indoor search patrol looping.
var _indoor_patrol_index: int = 0

# --- WALL CLIMB STATE ---
## Claw-scraping audio player (3D, positioned on the exterior wall).
## Plays a scraping sound as the Entity climbs up the wooden siding.
var _claw_scrape_player: AudioStreamPlayer3D = null

## 3D spatial audio player for the Entity's voice (talking, searching, angry).
## Programmatically created in _ready() with inverse-square distance attenuation.
var _voice_player: AudioStreamPlayer3D = null

## Audio streams for the voice state machine.
## Loaded safely using ResourceLoader.exists() guards.
var _voice_talking_1: AudioStream = null
var _voice_talking_2: AudioStream = null
var _voice_searching: AudioStream = null
var _voice_angry: AudioStream = null

## Harassment audio player (3D, positioned at the window during HARASS state).
## Plays intimate sounds (breathing, tapping, rattling) to psychologically
## pressure the player. Created programmatically in _ready().
var _harass_audio: AudioStreamPlayer3D = null

## Paths to the Entity voice audio assets.
const VOICE_TALKING_1_PATH: String = "res://assets/audio/Entity/entity_talking_1.ogg"
const VOICE_TALKING_2_PATH: String = "res://assets/audio/Entity/entity_talking_2.ogg"
const VOICE_SEARCHING_PATH: String = "res://assets/audio/Entity/entity_searching.ogg"
const VOICE_ANGRY_PATH: String = "res://assets/audio/Entity/entity_angry.ogg"

## Whether the angry voice has been played this charge instance.
## Set to true when entity_angry.ogg fires during CHARGE/CHASE entry.
## Reset to false when the Entity leaves CHARGE/CHASE state.
var _voice_angry_played_this_charge: bool = false

## Tracks whether the voice player was in a "talking" state (OBSERVE_FROM_TREELINE/PATROL)
## on the previous frame. Used by the AI's voice management to detect transitions
## between talking and non-talking states for the interchangeable track cycling.
var _voice_was_talking: bool = false

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

# --- LAMP ATTACK TIMING ---
## Timer counting up to 3.0 seconds between Entity strikes on the portable
## high-voltage lamp trap. Incremented by delta each frame while the Entity
## is within hitting distance of an active, deployed lamp. When it reaches
## 3.0, the Entity calls take_physical_hit() on the lamp and resets.
var _lamp_attack_timer: float = 0.0

# --- OVERLOAD STUN STATE ---
## Timer counting down the stun duration (seconds remaining).
## Set by trigger_overload_stun() and decremented each frame during STUNNED.
## When it reaches 0.0, the Entity is released from the stun.
var _stun_timer: float = 0.0


## ─── PENDING STATE OVERRIDE ──────────────────────────────────────────────
## When set to a valid State value (>= 0), the Master Director will read this
## at the START of evaluate_master_state() and apply it immediately, then
## clear it to -1. This is the ONLY mechanism by which external events (stun,
## blackout, debug, activation) can request a state change.
##
## THE GOLDEN RULE:
##   NO script is allowed to call set_state() except the Director.
##   External scripts must use request_state() which sets this flag.
##   The Director picks it up next frame, applies it, and clears it.
var _pending_state: int = -1

## Whether the Entity has been enraged by a blackout this night.
## Once set to true, the Entity's movement speed is permanently boosted
## by 1.5x for the rest of the night. Reset to false when the night ends.
var _is_enraged: bool = false

## Tracks whether the player was staring at the Entity with the flashlight
## on the previous frame. Used by the confidence modification system to
## detect the transition from "staring" to "not staring" and apply the
## one-time +8.0 confidence boost exactly once when line of sight breaks.
var _confidence_stare_was_active: bool = false

## Whether the player is standing on wood flooring (inside the cabin).
## Updated every frame in _physics_process() via floor raycast.
## Used by the floor material safety guard to prevent the Entity from
## charging through walls when the player is safely inside.
var _player_is_on_wood_floor: bool = false

## The original stalk speed before the enrage multiplier was applied.

## Used to restore the speed if the enrage is ever reset.
var _original_stalk_speed: float = 0.0


## Path to the claw scrape audio asset. If the file doesn't exist at this path,
## a programmatic fallback is used: the door creak/grunt asset loaded at pitch 0.4,
## looped, with a randomized stutter effect to simulate nails dragging on wood.
const CLAW_SCRAPE_PATH: String = "res://assets/audio/Entity/claw_scrape_loop.ogg"
const CLAW_SCRAPE_FALLBACK_PATH: String = "res://assets/audio/Entity/Entity_grunt_long.ogg"

# ─── "CREEPING GHOST" COLLISION LAYER SYSTEM ──────────────────────────────────
# When the Entity is traveling outside through dense woods (OBSERVE_FROM_TREELINE,
# PATROL), it programmatically disables hard physics collisions with tree/rock
# environmental layers. This allows the Entity to phase through foliage while
# still following the NavigationAgent3D path for steering.
#
# Full physics body collision masks are re-enabled the moment the Entity
# transitions into CHASE, APPROACH_WINDOW, or enters the cabin porch zone,
# ensuring it cannot phase through doors or window frames during an attack.
#
# Collision layers are defined in the project settings (project.godot).
# These constants map to the layer indices used in the physics layer names.
# Adjust these values to match the project's actual layer assignments.
const COLLISION_LAYER_TREE: int = 3   # Layer 3: Trees / large foliage
const COLLISION_LAYER_ROCK: int = 4   # Layer 4: Rocks / boulders / terrain obstacles
const COLLISION_LAYER_CABIN: int = 1  # Layer 1: Cabin geometry (walls, doors, windows)
const COLLISION_LAYER_PLAYER: int = 2 # Layer 2: Player body

## Stores the original collision mask before "Creeping Ghost" modifications.
## Restored when the Entity transitions to an aggressive state.
var _saved_collision_mask: int = 0

# ─── CONTEXT-STEERING RAYCAST ARRAY ──────────────────────────────────────────
# Three RayCast3D nodes used for obstacle avoidance when the Entity is stalking
# with tree/rock collisions disabled (OBSERVE_FROM_TREELINE, PATROL).
# Programmatically instantiated in _ready().
var _ray_center: RayCast3D = null
var _ray_left: RayCast3D = null
var _ray_right: RayCast3D = null


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
	
	# Set up chase exit grunt player (2D, plays ONCE when leaving CHASE state).
	# Uses duplicate() to create an independent copy of the audio stream so that
	# modifying its properties (e.g., loop = false) does NOT affect the shared
	# resource used by the light sanctuary grunt player below.
	_chase_exit_grunt_player = AudioStreamPlayer.new()
	_chase_exit_grunt_player.bus = "Entity"
	_chase_exit_grunt_player.volume_db = -6.0
	var grunt_stream = load(CHASE_EXIT_GRUNT_PATH) as AudioStream
	if grunt_stream:
		grunt_stream = grunt_stream.duplicate()
		if grunt_stream is AudioStreamOggVorbis:
			grunt_stream.loop = false
		_chase_exit_grunt_player.stream = grunt_stream
	add_child(_chase_exit_grunt_player)
	
	# Set up light sanctuary grunt player (2D, one-shot when Entity is repelled by light).
	# Uses duplicate() to create an independent copy so it doesn't interfere with
	# the chase exit grunt's stream settings.
	_light_sanctuary_grunt_player = AudioStreamPlayer.new()
	_light_sanctuary_grunt_player.bus = "Entity"
	_light_sanctuary_grunt_player.volume_db = -3.0  # Slightly louder than chase exit
	_light_sanctuary_grunt_player.pitch_scale = 1.3  # Higher pitch = frustrated/angry
	var sanctuary_stream = load(CHASE_EXIT_GRUNT_PATH) as AudioStream
	if sanctuary_stream:
		sanctuary_stream = sanctuary_stream.duplicate()
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
	
	# ─── 3D SPATIAL VOICE PLAYER ──────────────────────────────────
	# Programmatically create an AudioStreamPlayer3D for the Entity's voice.
	# Configured with inverse-square distance attenuation for realistic spatial
	# audio — the voice gets quieter as the player moves away from the Entity.
	# The voice is routed by entity_ai.gd's _manage_spatial_voice() based on
	# the current FSM state (talking, searching, angry).
	_voice_player = AudioStreamPlayer3D.new()
	_voice_player.name = "VoicePlayer"
	_voice_player.bus = "Entity"
	_voice_player.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_SQUARE_DISTANCE
	_voice_player.unit_size = 4.0
	_voice_player.max_distance = 40.0
	_voice_player.pitch_scale = 0.8  # Deep, guttural tone
	add_child(_voice_player)
	
	# ─── HARASSMENT AUDIO PLAYER ──────────────────────────────────
	# Programmatically create an AudioStreamPlayer3D for the HARASS state.
	# Plays intimate sounds (breathing, tapping, rattling) at the window
	# to psychologically pressure the player.
	# Configured with inverse-square attenuation and a short max distance
	# (15.0m) so the sounds are only audible when the player is near the
	# window being harassed.
	_harass_audio = AudioStreamPlayer3D.new()
	_harass_audio.name = "HarassAudio"
	_harass_audio.bus = "Entity"
	_harass_audio.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_SQUARE_DISTANCE
	_harass_audio.unit_size = 2.0
	_harass_audio.max_distance = 15.0
	add_child(_harass_audio)
	
	# ─── SAFE AUDIO LOADING ───────────────────────────────────────
	# Load the 4 voice audio streams using ResourceLoader.exists() guards
	# to avoid engine warnings when the files don't exist yet.
	if ResourceLoader.exists(VOICE_TALKING_1_PATH):
		_voice_talking_1 = load(VOICE_TALKING_1_PATH) as AudioStream
	if ResourceLoader.exists(VOICE_TALKING_2_PATH):
		_voice_talking_2 = load(VOICE_TALKING_2_PATH) as AudioStream
	if ResourceLoader.exists(VOICE_SEARCHING_PATH):
		_voice_searching = load(VOICE_SEARCHING_PATH) as AudioStream
	if ResourceLoader.exists(VOICE_ANGRY_PATH):
		_voice_angry = load(VOICE_ANGRY_PATH) as AudioStream
	
	# ─── CONTEXT-STEERING RAYCAST ARRAY ────────────────────────────
	# Three RayCast3D nodes used for obstacle avoidance when the Entity is
	# stalking with tree/rock collisions disabled (OBSERVE_FROM_TREELINE, PATROL).
	# The center ray is 3.5m long, left/right rays are 2.5m long at 30° angles.
	# Collision mask is set to scan static obstacles (cabin walls, porch posts).
	_ray_center = RayCast3D.new()
	_ray_center.name = "RayCastCenter"
	_ray_center.target_position = Vector3(0.0, 0.0, -3.5)
	_ray_center.collision_mask = (1 << (COLLISION_LAYER_CABIN - 1))  # Layer 1: Cabin
	_ray_center.hit_from_inside = false
	add_child(_ray_center)
	
	_ray_left = RayCast3D.new()
	_ray_left.name = "RayCastLeft"
	_ray_left.target_position = Vector3(0.0, 0.0, -2.5).rotated(Vector3.UP, deg_to_rad(30.0))
	_ray_left.collision_mask = (1 << (COLLISION_LAYER_CABIN - 1))  # Layer 1: Cabin
	_ray_left.hit_from_inside = false
	add_child(_ray_left)
	
	_ray_right = RayCast3D.new()
	_ray_right.name = "RayCastRight"
	_ray_right.target_position = Vector3(0.0, 0.0, -2.5).rotated(Vector3.UP, deg_to_rad(-30.0))
	_ray_right.collision_mask = (1 << (COLLISION_LAYER_CABIN - 1))  # Layer 1: Cabin
	_ray_right.hit_from_inside = false
	add_child(_ray_right)
	
	# Set up sub-modules
	if _ai and _ai.has_method("setup"):
		_ai.setup(self)
	if _sensory and _sensory.has_method("setup"):
		_sensory.setup(self)
	if _navigation and _navigation.has_method("setup"):
		_navigation.setup(self)
	
	# ─── CONFIDENCE SYSTEM ─────────────────────────────────────────
	# Create the EntityConfidence node as a child of the Entity.
	# This module tracks the Entity's boldness (0.0–100.0) and provides
	# the F3 debug overlay for real-time confidence visualization.
	#
	# CRITICAL: add_child() MUST be called immediately after new().
	# Without it, the EntityConfidence node is an orphan — its CanvasLayer
	# cannot render (F3 menu invisible) and its _process(delta) never fires
	# (confidence value freezes and never decays).
	if not _confidence:
		_confidence = EntityConfidence.new()
		_confidence.name = "EntityConfidence"
		add_child(_confidence)  # <-- REQUIRED: attaches to SceneTree
	if _confidence and _confidence.has_method("setup"):
		_confidence.setup(self)
	
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
	_night_manager = get_node_or_null("/root/NightManager")
	if _night_manager:
		_night_manager.night_started.connect(_on_night_started)
		_night_manager.night_ended.connect(_on_night_ended)
		_night_manager.first_chase_started.connect(_on_first_chase_started)
		if _night_manager.is_night_active:
			# Night 1 exception: Entity stays hidden for the car alarm narrative
			if _night_manager.current_night == 1:
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
	
	# Check if the Entity has been manually disabled via the debug console.
	# The debug console sets a meta flag "debug_disabled" when the player
	# toggles it off. If set, we skip activation so the Entity stays dormant
	# even when a new night starts.
	if has_meta("debug_disabled") and get_meta("debug_disabled"):
		print("[Entity] Night %d: Debug-disabled via console. Skipping activation." % night)
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
	request_state(EntityAI.State.CHASE)
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





## ─── INPUT PASSTHROUGH ──────────────────────────────────────────────────────
## Routes input events to sub-modules that need them.
## Currently forwards F3 to the EntityConfidence debug overlay toggle.
func _input(event: InputEvent) -> void:
	if _confidence and _confidence.has_method("_input"):
		_confidence._input(event)


func _find_player() -> void:
	var players = get_tree().get_nodes_in_group("player")
	if players.size() > 0:
		_player = players[0] as Node3D


func activate() -> void:
	_is_active = true
	visible = true
	request_state(EntityAI.State.OBSERVE_FROM_TREELINE)
	_set_visuals_visible(true)


func deactivate() -> void:
	_is_active = false
	velocity = Vector3.ZERO
	visible = false
	request_state(EntityAI.State.DORMANT)
	_set_visuals_visible(false)
	
	# Reset enrage state so the Entity starts fresh next night
	_is_enraged = false
	_original_stalk_speed = 0.0

	
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
	
	# Chase exit grunt cooldown decrement
	if _chase_exit_grunt_cooldown > 0.0:
		_chase_exit_grunt_cooldown -= delta
	
	# ─── DEBUG: F2 — Window Siege Stress Test ──────────────────────────────
	# Development-only shortcut to stress-test the outside-to-inside sequential
	# window destruction system (glass shatter → plank damage → breach → INDOOR_SEARCH).
	# Forces the Entity into APPROACH_WINDOW state with real pathfinding to the
	# first CabinWindow in the "WindowMarkers" group.
	if Input.is_key_pressed(KEY_F2):
		_debug_attack_window()
	
	# --- STATE TRANSITION LOGGING ---
	if _state != _last_logged_state:
		_last_logged_state = _state
		
		# ─── "CREEPING GHOST" COLLISION LAYER UPDATE ─────────────────
		# Every time the state changes, update the collision mask to match
		# the new state's requirements. This ensures the Entity phases through
		# tree/rock collision when stalking outside (OBSERVE_FROM_TREELINE,
		# PATROL) and has full collision when attacking (CHASE, APPROACH_WINDOW).
		_update_collision_layers()
	
	# ─── STUCK DETECTION ──────────────────────────────────────────────────────
	# Monitors whether the Entity has stopped making progress toward its
	# navigation target. If the Entity's velocity is near zero while the
	# NavigationAgent3D still has an active path (not finished), it means
	# the Entity is physically blocked by an obstacle (cabin wall, porch
	# post, rock formation, etc.).
	#
	# After stuck_timeout (1.5s) seconds of zero progress, the Entity
	# triggers a fade_and_relocate() to teleport to a new vantage point.
	# This prevents the Entity from freezing in place indefinitely when
	# the NavMesh path is blocked by geometry that the "Creeping Ghost"
	# collision system cannot phase through (cabin layer 1).
	#
	# NOTE: Stuck detection is disabled during CHASE and CHARGE — the
	# Entity should never teleport away while actively pursuing the player.
	var is_nav_active: bool = not _nav_agent.is_navigation_finished()
	var is_moving: bool = velocity.length_squared() > 0.01
	var is_attack_state: bool = (
		_state == EntityAI.State.CHASE or
		_state == EntityAI.State.CHARGE or
		_state == EntityAI.State.FLINCH or
		_state == EntityAI.State.CLIMB_WALL or
		_state == EntityAI.State.INDOOR_SEARCH or
		_state == EntityAI.State.STUNNED
	)
	
	if is_nav_active and not is_moving and not is_attack_state:
		_stuck_timer += delta
		if _stuck_timer >= stuck_timeout:
			print("[Entity] STUCK DETECTED! No movement for %.1fs while nav is active. Relocating." % stuck_timeout)
			fade_and_relocate()
			_stuck_timer = 0.0
	else:
		_stuck_timer = 0.0
	
	# --- BACKGROUND SENSE PROCESSING (runs every frame regardless of state) ---
	if _sensory:
		_sensory.can_entity_see_player()
	if _current_interest_level > 0:
		_current_interest_level -= _interest_decay_rate * delta
	
	# ─── CONFIDENCE MODIFICATION: FLASHLIGHT STARE ──────────────────────
	# While the player is staring at the Entity with the flashlight beam,
	# continuously drain confidence at 2.0 units per second. This makes the
	# Entity more timid the longer it is exposed to the light.
	#
	# When the player breaks line of sight (stops staring), grant a one-time
	# +8.0 instant confidence boost. This represents the Entity's relief at
	# escaping the light and encourages it to try again.
	#
	# The _confidence_stare_was_active flag tracks whether the player was
	# staring on the previous frame, so we can detect the transition from
	# "staring" to "not staring" and apply the one-time boost exactly once.
	var _confidence_stare_active: bool = _sensory and _sensory.is_player_spotting_entity()
	
	if _confidence_stare_active:
		# Continuous drain: -2.0 confidence per second while stared at
		if _confidence and _confidence.has_method("modify"):
			_confidence.modify(-2.0 * delta, "flashlight_stare")
	elif _confidence_stare_was_active and not _confidence_stare_active:
		# One-time boost: +8.0 confidence when the player breaks line of sight
		if _confidence and _confidence.has_method("modify"):
			_confidence.modify(8.0, "flashlight_stare_break")
			print("[Entity Controller] Confidence boost: +8.0 (player broke flashlight stare)")
	
	_confidence_stare_was_active = _confidence_stare_active
	
	# Reset the light sanctuary grunt debounce when the player stops
	# shining the flashlight on the Entity. This allows the grunt to
	# play again on the next spotting cycle.
	if _has_played_light_sound and not (_sensory and _sensory.is_player_spotting_entity()):
		_has_played_light_sound = false
	
	# --- CHASE MUSIC (ambience_d6_loop) ---
	# Fade in when entering CHASE state, fade out when leaving.
	var is_chasing = _state == EntityAI.State.CHASE
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
	#
	# COOLDOWN GUARD:
	# The _chase_exit_grunt_cooldown prevents the grunt from repeating every
	# time the Entity rapidly enters/exits CHASE (e.g., when the player runs
	# between lit and dark rooms). The cooldown is set to 5 seconds each time
	# the grunt plays, ensuring it can only play once every 5 seconds at most.
	if _was_chasing and not is_chasing and _chase_exit_grunt_cooldown <= 0.0:
		if _chase_exit_grunt_player and _chase_exit_grunt_player.stream:
			_chase_exit_grunt_player.play()
			_chase_exit_grunt_cooldown = CHASE_EXIT_GRUNT_COOLDOWN_DURATION
			print("[Entity] Playing chase exit grunt. _state=", _state, " is_player_outside=", _navigation.is_player_outside() if _navigation else "NO_NAV")
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
					request_state(EntityAI.State.OBSERVE_FROM_TREELINE)
					velocity = Vector3.ZERO
					print("[Entity] Window Bluff complete! Retreating to treeline.")
				else:
					velocity.x = retreat_dir.x * current_stalk_speed * 0.7
					velocity.z = retreat_dir.z * current_stalk_speed * 0.7
		
		move_and_slide()
		_update_animations(delta)
		return
	
	# --- STUNNED STATE (Porch Light Overload Trap) ---
	# The Entity is paralyzed by the blinding porch light. It cannot move,
	# cannot pathfind, and cannot transition to any other state until the
	# stun timer expires or the generator dies (blackout).
	# This gives the player a window to destroy the totem anchor.
	if _state == EntityAI.State.STUNNED:
		# Decrement the stun timer
		_stun_timer -= delta
		
		# Freeze all movement and pathfinding
		velocity = Vector3.ZERO
		_nav_agent.target_position = global_position  # Keep nav target on self
		
		# Play writhing/pained animation (Idle with transparency flicker)
		_update_animations(delta)
		
		# Check if the stun has expired naturally
		if _stun_timer <= 0.0:
			print("[Entity] Stun expired! Entity released from overload paralysis.")
			request_state(EntityAI.State.OBSERVE_FROM_TREELINE)
		
		return
	
	# --- ENRAGED STATE (Blackout Release) ---
	# The generator died while the Entity was stunned. The Entity is now
	# permanently enraged for the rest of the night — 1.5x movement speed.
	# ENRAGED is a modifier flag, not a blocking state — the Entity still
	# uses its normal FSM states (CHASE, PATROL, etc.) but with boosted speed.
	# The _is_enraged flag is checked by the AI speed calculations.
	
	# --- TRANSITION LOCK: RETREAT / STANDOFF / FLINCH ---
	# During RETREAT, force velocity to zero and skip movement processing,
	# but STILL execute the AI update tick so that _retreat_state() can
	# call fade_and_relocate(). Without this, the early return would create
	# a deadlock where the AI never runs and the transition never completes.
	# STANDOFF also locks movement — the Entity freezes in place while stared at.
	# FLINCH is handled by the AI's _flinch_state() which computes the lateral
	# sprint velocity. The controller applies it via move_and_slide() below.
	# NOTE: RELOCATE is NOT included here — it is a safe initialization state only
	# and is never used during active runtime transitions.
	if _state == EntityAI.State.RETREAT or _state == EntityAI.State.STANDOFF:
		velocity = Vector3.ZERO
		if _ai and _ai.has_method("process_state_logic"):
			_ai.process_state_logic(delta)
			velocity = _ai.get_calculated_velocity()
		_update_animations(delta)
		return

	
	# --- STANDARD ACTIVE NAVIGATION ---

	# Gravity is bypassed during CLIMB_WALL (vertical ascent), WINDOW_PEEK
	# (Entity is stationary at the window frame), FLINCH (lateral sprint
	# — the Entity stays at its current Y to avoid dropping into terrain),
	# and ATTACK_LAMP (Entity stands still while striking the lamp).
	if not is_on_floor() and _state != EntityAI.State.WINDOW_PEEK and _state != EntityAI.State.CLIMB_WALL and _state != EntityAI.State.FLINCH and _state != EntityAI.State.ATTACK_LAMP:

		velocity += get_gravity() * delta
	
	if _ai and _ai.has_method("process_state_logic"):
		_ai.process_state_logic(delta)
		velocity = _ai.get_calculated_velocity()
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
			break
	
	# Fallback: if no window_id match found, use the first valid window
	if not final_window_target:
		final_window_target = first_valid
	
	if not final_window_target:
		return
	
	# Store the original state for diagnostic logging
	var original_state = _state
	
	# ─── PART 2: Teleport to Window + Immediate Barricade Damage ───
	# Activate the Entity if it's dormant (e.g. Night 1 before van alarm)
	if not _is_active:
		activate()
	
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
	request_state(EntityAI.State.WINDOW_PEEK)
	_stare_timer = 9999.0  # Stay until barricade is destroyed
	
	# Reset the AI's barricade damage timer so the Entity immediately
	# enters barricade-damage mode on the next physics frame.
	if _ai and _ai.has_method("reset_barricade_timers"):
		_ai.reset_barricade_timers()
	
	print("[F2] Entity state override: ", EntityAI.State.keys()[original_state], " → WINDOW_PEEK")
	print("[F2] Entity teleported directly to window. Barricade damage sequence starting.")
	print("[F2] Window state — glass_shattered: ", final_window_target.is_glass_shattered, ", boarded: ", final_window_target.is_boarded)
	print("==========================================================\n")


# ─── PUBLIC ACCESSORS (Interface Contract) ────────────────────────────────────
# These typed accessors replace direct private variable access from sub-modules.
# Sub-modules MUST use these instead of entity._player, entity._nav_agent, etc.
# This creates a compile-time contract — renaming a private variable produces
# a compile error if the accessor isn't updated.

## Returns the cached player reference.
func get_player() -> Node3D:
	return _player

## Returns the cached NightManager reference.
## Sub-modules MUST use this instead of polling get_node_or_null("/root/NightManager") every frame.
func get_night_manager() -> Node:
	return _night_manager

## Returns the cached portable trap reference.
## Sub-modules MUST use this instead of calling
## get_tree().get_first_node_in_group("portable_trap") every frame.
func get_portable_trap() -> Node:
	return _portable_trap

## Returns the cached array of CabinLight nodes.
## Sub-modules MUST use this instead of calling
## get_tree().get_nodes_in_group("CabinLights") every frame.
func get_cabin_lights() -> Array[Node]:
	return _cabin_lights

## Refreshes the cached portable trap and cabin lights references.
## Called from _ready() and should be called whenever a new portable trap
## is deployed or a cabin light is added/removed from the scene.
func _refresh_cached_references() -> void:
	_portable_trap = get_tree().get_first_node_in_group("portable_trap")
	_cabin_lights = get_tree().get_nodes_in_group("CabinLights")

## Returns the NavigationAgent3D used for pathfinding.
func get_nav_agent() -> NavigationAgent3D:
	return _nav_agent

## Returns the current FSM state.
func get_state() -> EntityAI.State:
	return _state

## Sets the current FSM state.
## NOTE: This should ONLY be called by the Master Director (entity_director.gd).
## All other code MUST use request_state() instead.
func set_state(new_state: EntityAI.State) -> void:
	_state = new_state

## Requests a state change via the _pending_state override mechanism.
## This is the ONLY method external code should use to request a state change.
## The Master Director reads _pending_state at the start of evaluate_master_state()
## and applies it immediately, then clears it to -1.
##
## This prevents the "Two Masters" problem by funneling ALL state changes
## through the Director's single evaluation point.
func request_state(new_state: EntityAI.State) -> void:
	_pending_state = new_state

## Resets all state completion flags and unlocks the state lock.
## Called by the Master Director when it needs to force-clear the
## Blackboard for a clean state transition (e.g., after a pending
## state override or when entering a new night).
##
## This ensures that stale completion flags from a previous state
## (e.g., is_flinch_finished = true from a FLINCH that was interrupted
## by a pending state override) don't cause the Director to immediately
## transition out of the new state on the next frame.
func reset_locks() -> void:
	state_locked = false
	is_flinch_finished = false
	is_approach_finished = false
	is_window_unbarricaded = false
	is_climb_finished = false
	is_retreat_arrived = false
	is_observe_finished = false


## Returns the EntityNavigation sub-module.
func get_navigation_module() -> Node:
	return _navigation

## Returns the EntitySensory sub-module.
func get_sensory_module() -> Node:
	return _sensory

## Returns the EntityConfidence sub-module.
func get_confidence_module() -> Node:
	return _confidence

## Returns the EntityAI sub-module.
func get_ai_module() -> Node:
	return _ai

## Returns the current game time in seconds.
func get_game_time() -> float:
	return _game_time

## Returns the monster model Node3D (visual representation).
func get_monster_model() -> Node3D:
	return _monster_model

## Returns the AnimationStateMachinePlayback for animation control.
func get_anim_state_machine():
	return _anim_state_machine

## Returns the growl audio player (3D spatial).
func get_growl_audio() -> AudioStreamPlayer3D:
	return _growl_audio

## Returns the harassment audio player (3D spatial).
func get_harass_audio() -> AudioStreamPlayer3D:
	return _harass_audio

## Returns the current window target for approach/peek states.
func get_current_window_target() -> Node3D:
	return _current_window_target

## Returns the FuseBox node for the FUSE_SABOTAGE state.
## Looks up the FuseBoxWaypoint from the "EntityWaypoints" group, then finds
## the Marker3D child inside it. The Marker3D's parent is the FuseBox itself.
## Falls back to finding the FuseBox by class name in the scene tree.
func get_fuse_box_node():
	# First try: Find via EntityWaypoints group (FuseBoxWaypoint)
	var waypoints = get_tree().get_nodes_in_group("EntityWaypoints")
	for wp in waypoints:
		if wp.name == "FuseBoxWaypoint":
			# The waypoint's parent should be the FuseBox
			var parent = wp.get_parent()
			if parent and parent is FuseBox:
				return parent
			# Or the Marker3D child points to the FuseBox position
			for child in wp.get_children():
				if child is Marker3D:
					return child
	
	# Second try: Find the FuseBox by class name in the scene tree
	var fuse_box = get_tree().get_first_node_in_group("interactable")
	if fuse_box and fuse_box is FuseBox:
		return fuse_box
	
	# Third try: Search the entire scene tree for a FuseBox node
	if get_tree().current_scene:
		return get_tree().current_scene.find_child("FuseBox", true, false)
	
	return null

## Sets the current window target.
func set_current_window_target(target: Node3D) -> void:
	_current_window_target = target

## Returns the stare timer value.
func get_stare_timer() -> float:
	return _stare_timer

## Sets the stare timer value.
func set_stare_timer(value: float) -> void:
	_stare_timer = value

## Returns whether the Entity is at a vantage point.
func is_at_vantage_point() -> bool:
	return _is_at_vantage_point

## Sets whether the Entity is at a vantage point.
func set_at_vantage_point(value: bool) -> void:
	_is_at_vantage_point = value

## Returns the last visited vantage point.
func get_last_vantage_point() -> Node3D:
	return _last_vantage_point

## Sets the last visited vantage point.
func set_last_vantage_point(point: Node3D) -> void:
	_last_vantage_point = point

## Returns the flinch target position.
func get_flinch_target_pos() -> Vector3:
	return _flinch_target_pos

## Sets the flinch target position.
func set_flinch_target_pos(pos: Vector3) -> void:
	_flinch_target_pos = pos

## Returns the flinched timer value.
func get_flinched_timer() -> float:
	return _flinched_timer

## Sets the flinched timer value.
func set_flinched_timer(value: float) -> void:
	_flinched_timer = value

## Returns the window bluff cooldown.
func get_window_bluff_cooldown() -> float:
	return _window_bluff_cooldown

## Sets the window bluff cooldown.
func set_window_bluff_cooldown(value: float) -> void:
	_window_bluff_cooldown = value

## Returns the light sabotage cooldown.
func get_light_sabotage_cooldown() -> float:
	return _light_sabotage_cooldown

## Sets the light sabotage cooldown.
func set_light_sabotage_cooldown(value: float) -> void:
	_light_sabotage_cooldown = value

## Returns the lamp attack timer.
func get_lamp_attack_timer() -> float:
	return _lamp_attack_timer

## Sets the lamp attack timer.
func set_lamp_attack_timer(value: float) -> void:
	_lamp_attack_timer = value

## Returns the indoor breach window reference.
func get_indoor_breach_window():
	return _indoor_breach_window

## Sets the indoor breach window reference.
func set_indoor_breach_window(window) -> void:
	_indoor_breach_window = window

## Returns the indoor landing position for INDOOR_SEARCH Phase A vault entry.
func get_indoor_landing_position() -> Vector3:
	return _indoor_landing_position

## Sets the indoor landing position for INDOOR_SEARCH Phase A vault entry.
func set_indoor_landing_position(pos: Vector3) -> void:
	_indoor_landing_position = pos

## Returns the cooldown value for a named sound key from the sound cooldown registry.
## Returns 0.0 if the key doesn't exist (sound is ready to play).
func get_sound_cooldown(sound_key: String) -> float:
	return _sound_cooldowns.get(sound_key, 0.0)

## Sets the cooldown value for a named sound key in the sound cooldown registry.
## After setting, the sound will not play again until the cooldown counts down to <= 0.0.
func set_sound_cooldown(sound_key: String, value: float) -> void:
	_sound_cooldowns[sound_key] = value

## Convenience accessor for the "footstep" sound cooldown.
## Delegates to the Dictionary-based sound cooldown registry.
## Plays the indoor footstep sound effect.
## Called by entity_ai.gd's _window_peek_state() and _retreat_state().
## Uses the _footstep_audio AudioStreamPlayer3D if available.
func _play_indoor_footstep() -> void:
	if _footstep_audio and _footstep_audio.stream:
		_footstep_audio.pitch_scale = randf_range(0.8, 1.2)
		_footstep_audio.play()


func get_footstep_cooldown() -> float:
	return get_sound_cooldown("footstep")

## Convenience mutator for the "footstep" sound cooldown.
## Delegates to the Dictionary-based sound cooldown registry.
func set_footstep_cooldown(value: float) -> void:
	set_sound_cooldown("footstep", value)

## Returns whether a window bluff is active.
func is_window_bluff_active() -> bool:
	return _window_bluff_active

## Sets whether a window bluff is active.
func set_window_bluff_active(value: bool) -> void:
	_window_bluff_active = value

## Returns the window bluff timer.
func get_window_bluff_timer() -> float:
	return _window_bluff_timer

## Sets the window bluff timer.
func set_window_bluff_timer(value: float) -> void:
	_window_bluff_timer = value

## Returns the window bluff retreat position.
func get_window_bluff_retreat_pos() -> Vector3:
	return _window_bluff_retreat_pos

## Sets the window bluff retreat position.
func set_window_bluff_retreat_pos(pos: Vector3) -> void:
	_window_bluff_retreat_pos = pos

## Returns whether the light sanctuary grunt has been played.
func has_played_light_sound() -> bool:
	return _has_played_light_sound

## Sets whether the light sanctuary grunt has been played.
func set_has_played_light_sound(value: bool) -> void:
	_has_played_light_sound = value

## Returns whether the Entity is currently fading.
func is_fading() -> bool:
	return _is_fading

## Sets whether the Entity is currently fading.
func set_is_fading(value: bool) -> void:
	_is_fading = value

## Returns whether the Entity is enraged.
func is_enraged() -> bool:
	return _is_enraged

## Sets whether the Entity is enraged.
func set_is_enraged(value: bool) -> void:
	_is_enraged = value

## Returns the original stalk speed before enrage.
func get_original_stalk_speed() -> float:
	return _original_stalk_speed

## Sets the original stalk speed before enrage.
func set_original_stalk_speed(value: float) -> void:
	_original_stalk_speed = value

## Returns whether the confidence stare was active on the previous frame.
func was_confidence_stare_active() -> bool:
	return _confidence_stare_was_active

## Sets whether the confidence stare was active on the previous frame.
func set_confidence_stare_active(value: bool) -> void:
	_confidence_stare_was_active = value

## Returns whether sight has been logged.
func has_logged_sight() -> bool:
	return _has_logged_sight

## Sets whether sight has been logged.
func set_has_logged_sight(value: bool) -> void:
	_has_logged_sight = value

## Returns whether the Entity is hunting.
func is_hunting() -> bool:
	return _is_hunting

## Sets whether the Entity is hunting.
func set_is_hunting(value: bool) -> void:
	_is_hunting = value

## Returns the current interest level.
func get_current_interest_level() -> float:
	return _current_interest_level

## Sets the current interest level.
func set_current_interest_level(value: float) -> void:
	_current_interest_level = value

## Returns the interest decay rate.
func get_interest_decay_rate() -> float:
	return _interest_decay_rate

## Returns the vision cone angle in radians.
func get_vision_cone_angle() -> float:
	return _vision_cone_angle

## Returns the last known player position.
func get_last_known_position() -> Vector3:
	return _last_known_position

## Sets the last known player position.
func set_last_known_position(pos: Vector3) -> void:
	_last_known_position = pos

## Returns the path timer.
func get_path_timer() -> float:
	return _path_timer

## Sets the path timer.
func set_path_timer(value: float) -> void:
	_path_timer = value

## Returns the stuck timer.
func get_stuck_timer() -> float:
	return _stuck_timer

## Sets the stuck timer.
func set_stuck_timer(value: float) -> void:
	_stuck_timer = value

## Returns the relocate cooldown.
func get_relocate_cooldown() -> float:
	return _relocate_cooldown

## Sets the relocate cooldown.
func set_relocate_cooldown(value: float) -> void:
	_relocate_cooldown = value

## Returns the debug F2 cooldown.
func get_debug_f2_cooldown() -> float:
	return _debug_f2_cooldown

## Sets the debug F2 cooldown.
func set_debug_f2_cooldown(value: float) -> void:
	_debug_f2_cooldown = value

## Returns the chase exit grunt cooldown.
func get_chase_exit_grunt_cooldown() -> float:
	return _chase_exit_grunt_cooldown

## Sets the chase exit grunt cooldown.
func set_chase_exit_grunt_cooldown(value: float) -> void:
	_chase_exit_grunt_cooldown = value

## Returns the window peek timer.
func get_window_peek_timer() -> float:
	return _window_peek_timer

## Sets the window peek timer.
func set_window_peek_timer(value: float) -> void:
	_window_peek_timer = value

## Returns the window peek duration.
func get_window_peek_duration() -> float:
	return _window_peek_duration

## Returns the window peek marker.
func get_window_peek_marker() -> Node3D:
	return _window_peek_marker

## Sets the window peek marker.
func set_window_peek_marker(marker: Node3D) -> void:
	_window_peek_marker = marker

## Returns whether the window peek spotted the player.
func is_window_peek_spotted() -> bool:
	return _window_peek_spotted

## Sets whether the window peek spotted the player.
func set_window_peek_spotted(value: bool) -> void:
	_window_peek_spotted = value

## Returns the window peek vanish timer.
func get_window_peek_vanish_timer() -> float:
	return _window_peek_vanish_timer

## Sets the window peek vanish timer.
func set_window_peek_vanish_timer(value: float) -> void:
	_window_peek_vanish_timer = value

## Returns the window peek vanish delay.
func get_window_peek_vanish_delay() -> float:
	return _window_peek_vanish_delay

## Returns the window peek staging position.
func get_window_peek_staging_pos() -> Vector3:
	return _window_peek_staging_pos

## Sets the window peek staging position.
func set_window_peek_staging_pos(pos: Vector3) -> void:
	_window_peek_staging_pos = pos

## Returns the retreat timer.
func get_retreat_timer() -> float:
	return _retreat_timer

## Sets the retreat timer.
func set_retreat_timer(value: float) -> void:
	_retreat_timer = value

## Returns the outside log timer.
func get_outside_log_timer() -> float:
	return _outside_log_timer

## Sets the outside log timer.
func set_outside_log_timer(value: float) -> void:
	_outside_log_timer = value

## Returns the visited markers array.
func get_visited_markers() -> Array[Node3D]:
	return _visited_markers

## Returns the indoor patrol index.
func get_indoor_patrol_index() -> int:
	return _indoor_patrol_index

## Sets the indoor patrol index.
func set_indoor_patrol_index(value: int) -> void:
	_indoor_patrol_index = value

## Returns the claw scrape audio player.
func get_claw_scrape_player() -> AudioStreamPlayer3D:
	return _claw_scrape_player

## Returns the voice audio player.
func get_voice_player() -> AudioStreamPlayer3D:
	return _voice_player

## Returns the voice talking 1 audio stream.
func get_voice_talking_1() -> AudioStream:
	return _voice_talking_1

## Returns the voice talking 2 audio stream.
func get_voice_talking_2() -> AudioStream:
	return _voice_talking_2

## Returns the voice searching audio stream.
func get_voice_searching() -> AudioStream:
	return _voice_searching

## Returns the voice angry audio stream.
func get_voice_angry() -> AudioStream:
	return _voice_angry

## Returns whether the angry voice has been played this charge.
func has_voice_angry_played_this_charge() -> bool:
	return _voice_angry_played_this_charge

## Sets whether the angry voice has been played this charge.
func set_voice_angry_played_this_charge(value: bool) -> void:
	_voice_angry_played_this_charge = value

## Returns whether the voice was in a talking state.
func was_voice_talking() -> bool:
	return _voice_was_talking

## Sets whether the voice was in a talking state.
func set_voice_was_talking(value: bool) -> void:
	_voice_was_talking = value

## Returns the center context-steering raycast.
func get_ray_center() -> RayCast3D:
	return _ray_center

## Returns the left context-steering raycast.
func get_ray_left() -> RayCast3D:
	return _ray_left

## Returns the right context-steering raycast.
func get_ray_right() -> RayCast3D:
	return _ray_right

## Returns the saved collision mask.
func get_saved_collision_mask() -> int:
	return _saved_collision_mask

## Sets the saved collision mask.
func set_saved_collision_mask(value: int) -> void:
	_saved_collision_mask = value

## Returns the catch area.
func get_catch_area() -> Area3D:
	return _catch_area

## Returns the chase music player.
func get_chase_music_player() -> AudioStreamPlayer:
	return _chase_music_player

## Returns whether chase music was playing.
func was_chase_music_playing() -> bool:
	return _chase_music_was_playing

## Sets whether chase music was playing.
func set_chase_music_playing(value: bool) -> void:
	_chase_music_was_playing = value

## Returns the night ambience player.
func get_night_ambience_player() -> AudioStreamPlayer:
	return _night_ambience_player

## Returns whether night ambience was playing.
func was_night_ambience_playing() -> bool:
	return _night_ambience_was_playing

## Sets whether night ambience was playing.
func set_night_ambience_playing(value: bool) -> void:
	_night_ambience_was_playing = value

## Returns the chase exit grunt player.
func get_chase_exit_grunt_player() -> AudioStreamPlayer:
	return _chase_exit_grunt_player

## Returns the light sanctuary grunt player.
func get_light_sanctuary_grunt_player() -> AudioStreamPlayer:
	return _light_sanctuary_grunt_player

## Returns whether the Entity was chasing on the previous frame.
func was_chasing() -> bool:
	return _was_chasing

## Sets whether the Entity was chasing on the previous frame.
func set_was_chasing(value: bool) -> void:
	_was_chasing = value

## Returns whether the player is on wood flooring (inside the cabin).
func is_player_on_wood_floor() -> bool:
	return _player_is_on_wood_floor

## Sets whether the player is on wood flooring.
func set_player_on_wood_floor(value: bool) -> void:
	_player_is_on_wood_floor = value

## Returns whether the Entity is fleeing.
func is_fleeing() -> bool:
	return _is_fleeing

## Sets whether the Entity is fleeing.
func set_is_fleeing(value: bool) -> void:
	_is_fleeing = value

## Returns the flee angle.
func get_flee_angle() -> float:
	return _flee_angle

## Sets the flee angle.
func set_flee_angle(value: float) -> void:
	_flee_angle = value

## Returns the flee direction.
func get_flee_direction() -> int:
	return _flee_direction

## Sets the flee direction.
func set_flee_direction(value: int) -> void:
	_flee_direction = value


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
	
	# NOTE: State transition is handled by the Master Director (entity_director.gd).
	# The Director evaluates confidence, player position, and night rules to
	# determine the correct state. This function ONLY handles physical placement.
	# Set a neutral baseline state — the Director will override it next frame.
	request_state(EntityAI.State.OBSERVE_FROM_TREELINE)


## Initiates a window peek sequence. Sets the state to APPROACH_WINDOW
## and clears the current window target so the AI picks a new one.
func _start_window_peek() -> void:
	if not _is_active or not _player:
		return
	request_state(EntityAI.State.APPROACH_WINDOW)
	_current_window_target = null
	_nav_agent.target_position = _player.global_position
	print("[Entity] Starting window peek sequence.")


## Starts a visual alpha fade Tween on the Entity's monster model.
## The model fades from opaque (alpha 1.0) to transparent (alpha 0.0)
## over 1.5 seconds, creating a "phantom" effect as the Entity slides
## into the darkness during the FLINCH state.
##
## Called from _flinch_state() in entity_ai.gd on first entry.
##
## SAFETY GUARD: Only tweens modulate if the monster model is a CanvasItem
## (Sprite3D, MeshInstance3D with StandardMaterial3D, etc.). Plain Node3D
## instances do not have a modulate property — attempting to tween it would
## throw "Invalid access to property or key 'modulate' on a base object of
## type 'Node3D'". In that case, we simply hide the model instead.
func _start_flinch_fade() -> void:
	if not _monster_model:
		return
	if not is_inside_tree():
		return
	
	var tree = get_tree()
	if not tree:
		return
	
	# Kill any existing tweens on the monster model to prevent conflicts
	var existing_tween = tree.create_tween()
	if existing_tween:
		existing_tween.kill()
	
	# Check if the monster model supports modulate (CanvasItem-based types).
	# Node3D does NOT have modulate — only GeometryInstance3D subclasses with
	# material overrides or CanvasItem-based nodes do. If modulate is not
	# available, fall back to hiding the model directly.
	if "modulate" in _monster_model:
		var fade_tween = tree.create_tween()
		if fade_tween:
			var property_tweener = fade_tween.tween_property(_monster_model, "modulate:a", 0.0, 1.5)
			if property_tweener:
				property_tweener.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_SINE)
	else:
		# Fallback: hide the model directly since modulate is not available
		_monster_model.visible = false


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
	# NOTE: State transition is handled by the Master Director (entity_director.gd).
	# The Director evaluates is_illuminated + is_player_inside and returns FLINCH.
	# This function ONLY sets up the flinch target position and timer.
	print("[Entity] FLINCH setup complete! Sprinting laterally to evade flashlight!")


func _on_caught_player() -> void:
	_is_active = false
	velocity = Vector3.ZERO
	if _growl_audio:
		_growl_audio.play()
	if _night_manager:
		_night_manager.horror_event.emit("entity_caught_player")
	# Unpause the game tree in case it was paused by a previous jumpscare
	if get_tree().paused:
		get_tree().paused = false


## Called when the player enters the Entity's catch area (Area3D overlap zone).
## This provides a reliable catch trigger even when physics collision pushback
## prevents the distance-based check in _stalk_state() from reaching catch_distance.
func _on_catch_area_body_entered(body: Node) -> void:
	if not _is_active:
		return
	if body == _player and _state == EntityAI.State.CHASE:
		print("[Entity] Player entered catch area during chase! Catching player.")
		_on_caught_player()


## Called by the player controller every frame while the player is staring at
## the Entity with the flashlight on. look_timer ranges from 0.0 to 2.0+.
##
## BLACKBOARD-ONLY METHOD:
## This method ONLY writes sensory data to the Blackboard (is_illuminated,
## player_stare_timer). It NEVER calls set_state() — state transitions are
## the exclusive domain of the Master Director (entity_director.gd).
##
## The Director reads these Blackboard values once per frame and evaluates
## the correct state from top-to-bottom priority.
func on_player_stare(time: float) -> void:
	if not _is_active:
		return
	
	# Update the Blackboard — the Director will read these next frame
	player_stare_timer = time
	is_illuminated = (time > 0.0)
	
	# During CHARGE, continuously update nav target to the player's current position
	# This is movement/pathfinding logic, NOT state transition logic.
	if _state == EntityAI.State.CHARGE and _player:
		_nav_agent.target_position = _player.global_position
		return
	
	# Orient the Entity's model to face the player directly when illuminated
	# This is visual/orientation logic, NOT state transition logic.
	if is_illuminated and _monster_model and _player:
		var dir_to_player = (_player.global_position - global_position).normalized()
		var target_angle = atan2(dir_to_player.x, dir_to_player.z)
		_monster_model.rotation.y = lerp_angle(_monster_model.rotation.y, target_angle, 0.1)
		
		# Freeze velocity while illuminated — the Director handles the state
		velocity = Vector3.ZERO


## Physically stalks to a new vantage point using NavigationAgent3D pathfinding.
## Replaces the old fade-out + teleport system. The Entity now physically sneaks
## between trees using the "Stalk" or "running_crawl" locomotion animation.
##
## BEHAVIOR:
##   1. Picks a new vantage point via entity_navigation.pick_next_vantage_point()
##   2. Sets the NavigationAgent3D target to that position
##   3. Transitions to a physical movement phase (EntityAI.State.OBSERVE_FROM_TREELINE)
##      where the Entity moves at stalk speed along the computed path
##   4. The "Creeping Ghost" collision layer is active during this movement,
##      allowing the Entity to phase through tree/rock collision while still
##      following the NavMesh path for steering
##   5. Once the path is complete, the Entity resumes normal observation
##
## Called from entity_ai.gd when the Entity needs to change spots (e.g., the
## player stared at it, its observation timer expired, or it was repelled by
## a light sanctuary).
func fade_and_relocate() -> void:
	if _is_fading:
		return
	print("[Entity] fade_and_relocate() called! Current state: ", EntityAI.State.keys()[_state])
	_is_fading = true
	
	# Pick a new vantage point via the navigation system.
	# This sets _nav_agent.target_position to the new coordinate.
	_navigation.pick_next_vantage_point()
	
	# Transition to OBSERVE_FROM_TREELINE — the AI will handle the physical
	# movement toward the new vantage point via _observe_from_treeline_state().
	# The NavigationAgent3D pathfinding naturally avoids the cabin and other
	# obstacles by following the navigation mesh. The "Creeping Ghost" collision
	# layer is automatically applied by _update_collision_layers() each frame
	# for this state, allowing the Entity to phase through tree/rock collision
	# while still steering around the cabin geometry.
	request_state(EntityAI.State.OBSERVE_FROM_TREELINE)
	
	# Reset the stare timer so the Entity doesn't immediately try to
	# relocate again upon arrival. The AI will set a new timer once
	# the Entity reaches the vantage point.
	_stare_timer = 9999.0  # Effectively infinite — the AI resets it on arrival
	
	# Reset the light sanctuary grunt debounce flag so the Entity can
	# play the frustrated sound again the next time it is repelled.
	_has_played_light_sound = false
	
	if _ai and _ai.has_method("reset_exposure"):
		_ai.reset_exposure()
	
	_is_fading = false
	print("[Entity] Physical relocation in progress. Stalking to new vantage point.")


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
##
## DEBOUNCE GUARD:
## The _has_played_light_sound flag prevents this sound from repeating every
## frame while the player remains in a lit room. The flag is set to true when
## the sound plays, and is reset to false when the Entity fades/relocates
## (see fade_and_relocate()) or resets exposure.
func _play_light_sanctuary_grunt() -> void:
	if _has_played_light_sound:
		return
	if _light_sanctuary_grunt_player and _light_sanctuary_grunt_player.stream:
		_light_sanctuary_grunt_player.play()
		_has_played_light_sound = true
		print("[Entity] Playing light sanctuary grunt — frustrated by the light! _state=", _state, " is_player_outside=", _navigation.is_player_outside() if _navigation else "NO_NAV")


## ─────────────────────────────────────────────────────────────────────────────
## OVERLOAD STUN — Portable High-Voltage Lamp Trap
## ─────────────────────────────────────────────────────────────────────────────

## Public API: Triggers the overload stun on the Entity.
##
## Called by PortableLamp.trigger_overload() when the player executes the
## "EXECUTE OVERLOAD" command from the computer terminal.
##
## The Entity must be within 25 units of the portable trap position for the
## stun to take effect. If the Entity is too far away (e.g., patrolling the
## treeline), the stun is ignored and the overload only burns fuel.
##
## Effects:
##   1. Checks distance to the portable trap (must be < 25.0 units)
##   2. Forces state to STUNNED — freezes all movement and pathfinding
##   3. Sets _stun_timer to the provided duration (default 30.0 seconds)
##   4. Plays a high-priority pained scream via HorrorSoundManager
##   5. Logs the stun event for debugging
func trigger_overload_stun(trap_position: Vector3, duration: float = 30.0) -> void:
	if not _is_active:
		print("[Entity] Overload stun ignored — Entity is not active.")
		return
	
	if _state == EntityAI.State.STUNNED:
		print("[Entity] Overload stun ignored — Entity is already stunned.")
		return
	
	# Distance check: Entity must be within 25 units of the portable trap
	var dist_to_trap: float = global_position.distance_to(trap_position)
	if dist_to_trap > 25.0:
		print("[Entity] Overload stun ignored — Entity is too far from portable trap (%.1f units > 25.0)." % dist_to_trap)
		return
	
	print("[Entity] ⚡ OVERLOAD STUN TRIGGERED! Distance to trap: %.1f units. Stun duration: %.1f seconds." % [dist_to_trap, duration])
	
	# Force the Entity into STUNNED state
	request_state(EntityAI.State.STUNNED)
	_stun_timer = duration
	
	# Freeze all movement immediately
	velocity = Vector3.ZERO
	_nav_agent.target_position = global_position
	
	# Play a high-priority pained scream via HorrorSoundManager
	var hsm = get_node_or_null("/root/HorrorSoundManager")
	if hsm and hsm.has_method("play_distant_monster"):
		hsm.play_distant_monster()
	
	# Also play a local growl at higher pitch for the pained reaction
	if _growl_audio:
		_growl_audio.pitch_scale = 1.8  # Higher pitch = pained scream
		_growl_audio.play()
	
	print("[Entity] Entity is STUNNED! Paralyzed by the blinding portable lamp for %.1f seconds." % duration)



## Called when the generator runs out of fuel (blackout) while the Entity
## is in the STUNNED state. Instantly transitions the Entity to ENRAGED.
##
## ENRAGED permanently boosts the Entity's movement speed by 1.5x for the
## rest of the night. The Entity is released from the stun and immediately
## begins hunting the player with enhanced aggression.
##
## If the Entity is NOT stunned when the blackout hits, this function does
## nothing — the Entity continues its normal behavior.
func on_generator_blackout() -> void:
	if _state != EntityAI.State.STUNNED:
		return
	
	print("[Entity] ⚡ BLACKOUT RELEASE! Generator died while Entity was stunned. ENRAGED!")
	
	# Save the original stalk speed if not already saved
	if not _is_enraged:
		_original_stalk_speed = current_stalk_speed
		_is_enraged = true
		
		# Permanently boost movement speed by 1.5x for the rest of the night
		current_stalk_speed = _original_stalk_speed * 1.5
		print("[Entity] ENRAGED! Stalk speed permanently boosted from %.1f to %.1f (1.5x)." % [_original_stalk_speed, current_stalk_speed])
	
	# Release from stun — immediately begin hunting the player
	request_state(EntityAI.State.CHASE)
	_stun_timer = 0.0
	
	# Update nav target to the player's current position
	if _player:
		_nav_agent.target_position = _player.global_position
	
	# Play an enraged roar
	if _growl_audio:
		_growl_audio.pitch_scale = 1.2
		_growl_audio.play()
	
	# Play the distant monster sound as a telegraph
	var hsm = get_node_or_null("/root/HorrorSoundManager")
	if hsm and hsm.has_method("play_distant_monster"):
		hsm.play_distant_monster()


## ─── "CREEPING GHOST" COLLISION LAYER SYSTEM ──────────────────────────────────
## Updates the Entity's collision mask based on the current state.
##
## When the Entity is traveling outside through dense woods (OBSERVE_FROM_TREELINE,
## PATROL), it disables hard physics collisions with tree/rock environmental layers
## (layers 3 and 4). This allows the Entity to phase through foliage while still
## following the NavigationAgent3D path for steering.
##
## Full physics body collision masks are re-enabled the moment the Entity
## transitions into CHASE, APPROACH_WINDOW, or enters the cabin porch zone,
## ensuring it cannot phase through doors or window frames during an attack.
##
## Called automatically every time the state changes (see _physics_process).
func _update_collision_layers() -> void:
	match _state:
		EntityAI.State.OBSERVE_FROM_TREELINE, EntityAI.State.PATROL:
			# "Creeping Ghost" mode: Disable tree/rock collision layers.
			# The Entity phases through foliage while stalking outside.
			# Only cabin geometry (layer 1) and player (layer 2) remain active.
			# This prevents the Entity from getting stuck on trees while
			# physically pathfinding between vantage points.
			collision_mask = 0
			collision_mask |= (1 << (COLLISION_LAYER_CABIN - 1))  # Layer 1: Cabin
			collision_mask |= (1 << (COLLISION_LAYER_PLAYER - 1)) # Layer 2: Player
			# NOTE: Layers 3 (Tree) and 4 (Rock) are intentionally excluded.
			
		EntityAI.State.CHASE, EntityAI.State.CHARGE, EntityAI.State.APPROACH_WINDOW, EntityAI.State.WINDOW_PEEK, EntityAI.State.INDOOR_SEARCH, EntityAI.State.CLIMB_WALL, EntityAI.State.FLINCH, EntityAI.State.ATTACK_LAMP, EntityAI.State.RETREAT:
			# Full collision mode: Re-enable ALL collision layers.
			# The Entity must collide with everything during aggressive states
			# to prevent phasing through doors, window frames, or cabin walls.
			collision_mask = 0
			collision_mask |= (1 << (COLLISION_LAYER_CABIN - 1))  # Layer 1: Cabin
			collision_mask |= (1 << (COLLISION_LAYER_PLAYER - 1)) # Layer 2: Player
			collision_mask |= (1 << (COLLISION_LAYER_TREE - 1))   # Layer 3: Trees
			collision_mask |= (1 << (COLLISION_LAYER_ROCK - 1))   # Layer 4: Rocks
			
		_:
			# Default: Full collision mask for all other states (DORMANT, STANDOFF, STUNNED, etc.)
			collision_mask = 0
			collision_mask |= (1 << (COLLISION_LAYER_CABIN - 1))
			collision_mask |= (1 << (COLLISION_LAYER_PLAYER - 1))
			collision_mask |= (1 << (COLLISION_LAYER_TREE - 1))
			collision_mask |= (1 << (COLLISION_LAYER_ROCK - 1))


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
	
	# Hard clamp animations to Idle if we are retreating, dormant, or in a
	# frozen standoff. This prevents the animation state machine from caching
	# and continuously looping the previous sprinting animation during
	# supernatural transitions or while the Entity is locked in place.
	if _state == EntityAI.State.RETREAT or _state == EntityAI.State.DORMANT or _state == EntityAI.State.STANDOFF:
		_anim_state_machine.travel("Idle")
		return
	
	var real_vel := get_real_velocity()
	var horz_speed := Vector2(real_vel.x, real_vel.z).length()
	
	# ─── ACTION-LOCK OVERRIDES (non-movement animations) ─────────────
	# These are distinct action animations that must play regardless of
	# velocity. They take priority over standard locomotion blending.
	
	# AttackWindow: Barricade damage swing (WINDOW_PEEK)
	if _state == EntityAI.State.WINDOW_PEEK:
		if _ai and _ai.has_method("is_barricade_anim_locked") and _ai.is_barricade_anim_locked():
			_anim_state_machine.travel("AttackWindow")
			return
	
	# EnterWindow: Vault entry animation (INDOOR_SEARCH Phase A)
	if _state == EntityAI.State.INDOOR_SEARCH:
		if _ai and _ai.has_method("has_arrived_indoor") and not _ai.has_arrived_indoor():
			_anim_state_machine.travel("EnterWindow")
			return
	
	# ─── STANDARD LOCOMOTION BLENDING ────────────────────────────────
	# Base animation selection on horizontal velocity and a posture flag.
	# This replaces the bloated match statement that redundantly mapped
	# each state to the same walk/crawl/idle animations.
	
	# Vertical movement (ClimbUp / ClimbDown) takes priority over horizontal
	if real_vel.y > 0.8:
		_anim_state_machine.travel("ClimbUp")
		return
	elif real_vel.y < -0.8 and not is_on_floor():
		_anim_state_machine.travel("ClimbDown")
		return
	
	# Determine posture based on state
	var is_crawling: bool = (
		_state == EntityAI.State.CHARGE or
		_state == EntityAI.State.FLINCH or
		_state == EntityAI.State.CLIMB_WALL or
		(_state == EntityAI.State.INDOOR_SEARCH and _ai and _ai.has_method("has_arrived_indoor") and _ai.has_arrived_indoor())
	)
	
	if horz_speed > 0.2:
		_anim_state_machine.travel("running_crawl" if is_crawling else "Stalk")
	else:
		_anim_state_machine.travel("Idle")
