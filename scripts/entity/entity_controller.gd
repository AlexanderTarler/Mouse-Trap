extends CharacterBody3D

## "The Entity" — the main antagonist.
## Systemic Hunting Paradigm: The Entity uses vision cones and audio pings to track the player.
##
## Orchestrator node that delegates to sub-modules:
##   - entity_ai.gd        → FSM state behaviors
##   - entity_sensory.gd   → Vision cone, flashlight detection, audio hearing
##   - entity_navigation.gd → Vantage point selection, outside detection
##
## NOTE: The State enum is now defined in entity_ai.gd (class_name EntityAI).
## Reference states as EntityAI.State.X from this script.
## NO preload needed — class_name EntityAI registers it globally.

# Pre-cached enum keys — avoids repeated .keys() heap allocations on each
# state transition. EntityAI.State.keys() allocates a new Array every call
# in Godot 4, and set_state() was calling it 3× per transition.
# Initialized in _ready() since const can't call methods at compile-time.
var STATE_KEYS: Array = []

@export var speed: float = 4.0
## Distance (in meters) the Entity must be from the player to catch them.
## Reduced from 2.5 to 0.5 so the Entity physically closes to melee range
## before attacking. The STALK state now has a direct approach override
## that bypasses the NavigationAgent3D within 2.0m to reach this distance.
## Distance (in meters) the Entity must be from the player to catch them.
## Set to 1.5m — physically achievable given collision body radii (~0.9-1.0m
## center-to-center minimum) while close enough to feel like melee range.
## The tightened nav distances (path_desired_distance=0.3, reduced jitter)
## ensure the Entity visually closes to this range.
@export var catch_distance: float = 1.5
@export var relocate_radius: float = 20.0
@export var path_update_interval: float = 0.3
@export var stuck_timeout: float = 1.5
## Extended stuck timeout (in seconds) when the Entity is within proximity of
## a door or window. This gives the Entity extra time to navigate through tight
## doorframes and window openings without triggering a premature fade_and_relocate().
## The standard stuck_timeout (1.5s) is too aggressive for doorway navigation,
## where the Entity may briefly pause while the NavigationAgent3D recalculates
## a path through the narrow NavMesh edge.
@export var stuck_timeout_near_door: float = 4.0
@export var fade_duration: float = 0.5
@export var shadow_material: Material = null

## Cached reference to the FuseBox node. Assign in the Inspector or it will
## be resolved automatically in _initialize_entity() via a one-time lookup.
## This replaces the expensive get_fuse_box_node() scene tree traversal that
## was called every frame during SABOTAGE_FUSE / FUSE_SABOTAGE states.
@export var fuse_box_node: Node = null

## Cached reference to the Door node. Assign in the Inspector or it will
## be resolved automatically in _initialize_entity() via a one-time lookup.
## This replaces the expensive get_tree().get_first_node_in_group("Door")
## calls that were made every frame during APPROACH_WINDOW / INDOOR_SEARCH.
@export var door_node: Node = null

## Cached reference to the DoorBreachWaypoint Marker3D (the interior waypoint
## past the doorway threshold). Assign in the Inspector or it will be resolved
## automatically in _initialize_entity() via a one-time lookup.
## This replaces the expensive child-node search that was called every frame
## during APPROACH_WINDOW Phase 2 and INDOOR_SEARCH Phase A door entry.
@export var door_breach_waypoint: Node3D = null

## Cached reference to the FuseBox waypoint Marker3D (the exterior waypoint
## near the Fuse Box that the Entity pathfinds to). Assign in the Inspector or
## it will be resolved automatically in _initialize_entity() via a one-time
## lookup. This replaces the expensive per-frame child iteration that was
## called every frame during SABOTAGE_FUSE to find the waypoint.
@export var fuse_waypoint: Marker3D = null

## Cached reference to the Door's exterior waypoint Marker3D (the
## EntityDoorWaypoint that the Entity pathfinds to when approaching the door).
## Assign in the Inspector or it will be resolved automatically in
## _initialize_entity() via a one-time lookup. This replaces the expensive
## per-frame duck-typing checks that were called every frame during
## APPROACH_WINDOW to determine if the target is a door.
@export var door_waypoint_marker: Node3D = null

# PERFORMANCE: Cached autoload references (avoid per-frame get_node_or_null traversal)
var _room_light_detector: Node = null

@onready var _nav_agent: NavigationAgent3D = $NavigationAgent3D
@onready var _collision_shape: CollisionShape3D = $CollisionShape3D
@onready var _monster_model: Node3D = $MonsterModel if has_node("MonsterModel") else null
@onready var _anim_tree: AnimationTree = $AnimationTree if has_node("AnimationTree") else null
@onready var _growl_audio: AudioStreamPlayer3D = $GrowlAudio if has_node("GrowlAudio") else null
@onready var _footstep_audio: AudioStreamPlayer3D = $FootstepAudio if has_node("FootstepAudio") else null

# Footstep audio exports — surface sounds and timing
@export var wood_footsteps: Array[AudioStream] = []
@export var grass_footsteps: Array[AudioStream] = []
@export var footstep_interval_normal: float = 0.5
@export var footstep_interval_charge: float = 0.25
@export var footstep_pitch_min: float = 0.7
@export var footstep_pitch_max: float = 0.95

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

## Tracks the previous state for detecting transitions in set_state().
## Used by the state transition debug log to print what triggered the change.
var _last_state: EntityAI.State = EntityAI.State.DORMANT

## Returns the previous state before the last state transition.
## Used by the Director's hysteresis tracking in evaluate_master_state().
func get_previous_state() -> int:
	return _last_state

## ─── STATE PERSISTENCE TIMER ──────────────────────────────────────────────
## Counts down each frame while the Entity is in an active state (FLINCH,
## CHARGE, etc.). When > 0.0, the Director's State Persistence
## Guard returns the current state, preventing Tier 3–8 evaluations from
## overriding the state mid-execution.
##
## Set by state handlers on entry (e.g., _flinch_state sets this to 1.5s).
## Decremented by delta each frame in _physics_process().
## When it reaches 0.0, the Director is free to re-evaluate.
var _state_timer: float = 0.0
var _is_active: bool = false
var _path_timer: float = 0.0
var _stuck_timer: float = 0.0
var _game_time: float = 0.0

# ─── POSITION-BASED STUCK DETECTION ──────────────────────────────────────────
## Tracks the Entity's position over time to detect "treadmilling" — where the
## Entity has non-zero velocity but is NOT making progress toward its target
## (e.g., pushing against an invisible wall, stuck on a door threshold, or
## pathfinding to an unreachable NavMesh edge).
##
## Unlike the velocity-based stuck detector (which checks get_real_velocity()),
## this detector compares the Entity's actual position frame-over-frame. If the
## position hasn't changed by more than 0.1m for 2+ seconds while the nav agent
## is active, it logs a detailed diagnostic including:
##   - Where the Entity is (current position)
##   - Where it's trying to go (nav target position)
##   - What it's colliding with (last slide collision)
##
## This is specifically designed to catch the "doorway treadmill" bug where the
## Entity has velocity (~0.5 m/s) but is sliding along a wall/doorframe instead
## of moving toward the IndoorBreachWaypoint.
var _pos_stuck_timer: float = 0.0
var _last_stuck_position: Vector3 = Vector3.ZERO
var _pos_stuck_logged: bool = false  # Prevents spam-logging every frame after first detection
const POS_STUCK_TIMEOUT: float = 2.0  # Seconds before logging the diagnostic
const POS_STUCK_THRESHOLD: float = 0.1  # Meters — minimum movement to reset the timer


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

# ─── THE BLACKBOARD ──────────────────────────────────────────────────────────
# Shared state variables read/written by the Director, AI, and Sensory modules.
# Organized into groups for clarity in the Godot Inspector.

@export_group("Blackboard - State Flags")

## When true, the Master Director MUST return the current state, preventing
## transitions until the state handler unlocks it.
## Set to true by state handlers on entry, set to false on completion.
## This prevents "State Flapping" where the Director and FSM fight over
## the state variable every frame.
var state_locked: bool = false

## ─── BREACH LOCK ──────────────────────────────────────────────────────────────
## When true, the Sensory System and Director Tier logic must NOT be allowed
## to override the state. This prevents the Entity from aborting its door/window
## breach due to sensory interference (hearing the player outside, seeing the
## player outside, etc.).
##
## Set to true by _indoor_search_state() when Door Phase A begins.
## Set to false when Door Phase A completes (arrival at IndoorBreachWaypoint).
## Automatically force-unlocked after 5 seconds via the timeout in _physics_process().
##
## This is the "Breach Lock" — the Entity commits to the doorway and ignores
## all outside noise until fully inside.
var is_breach_locked: bool = false

## Timer tracking how long is_breach_locked has been active.
## Used by the 5-second timeout in _physics_process() to force-unlock
## if the breach takes too long.
var _breach_lock_timer: float = 0.0

## ─── DOOR BREACH COOLDOWN ────────────────────────────────────────────────────
## Timestamp (in seconds from Time.get_ticks_msec() / 1000.0) of the last
## successful door breach. Used by the Director's Tier 7 to enforce a 15-second
## cooldown on APPROACH_WINDOW after a door breach, preventing the looping bug
## where the Entity breaches → Director sees player inside → triggers
## APPROACH_WINDOW again → Entity jitters/teleports back to the door.
## Set to -999.0 initially so the cooldown check always passes on first breach.
var last_door_breach_time: float = -999.0

## Set to true by _approach_window_state() when the Entity arrives at the target window.
## The Director checks this flag and transitions to WINDOW_PEEK.
var is_approach_finished: bool = false

## Set to true by _window_peek_state() when the window is unbarricaded and siege timer
## has elapsed. The Director checks this flag and transitions to INDOOR_SEARCH.
var is_window_unbarricaded: bool = false

var is_climb_finished: bool = false  # Deprecated — kept for API compatibility, no longer used

## Set to true by the Director when transitioning to INDOOR_SEARCH from a door
## approach (rather than a window breach). The _indoor_search_state() handler
## checks this flag to bypass Phase A (vault animation + teleport math) and
## go straight to Phase B (indoor patrol pathfinding).
## Reset to false by _indoor_search_state() after consuming the flag.
var was_door_entry: bool = false

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

## Set to true by the Director (Tier 0) when the Entity is illuminated while in
## INDOOR_SEARCH state. The RETREAT handler reads this flag to know it should
## pathfind to the breach window (instead of the farthest treeline), teleport
## outside, and perform a 5-second flinch before transitioning to OBSERVE.
## Reset to false by the RETREAT handler when the indoor retreat completes.
var is_indoor_retreat: bool = false

## ─── PHYSICS SUSPENSION FLAG ──────────────────────────────────────────────────
## When true, the core physics calculations (gravity, ground snapping, and
## move_and_slide()) are bypassed in _physics_process(). Used by the
## Door Phase A ghost motor to manually lerp the Entity's global_position
## through the doorway without the physics motor fighting back.
## Set to true by entity_ai.gd's _indoor_search_state() on ghost entry.
## Set to false on arrival (restoring normal physics).
var is_physics_suspended: bool = false

@export_group("Blackboard - Sensory Data")

## Whether the Entity is currently illuminated by the player's flashlight beam.
## Written by on_player_stare(). Read by the Master Director (entity_director.gd).
var is_illuminated: bool = false

## Whether the Entity BELIEVES the player is still inside the cabin.
## Defaults to true — the Entity assumes the player is inside until proven
## otherwise through sight, sound, or deductive reasoning (3-waypoint miss rule).
## Written by entity_sensory.gd and entity_ai.gd. Read by entity_director.gd.
var thinks_player_is_inside: bool = true

## Number of consecutive vantage point observations that yielded no sighting
## of the player. When >= 3, the Entity deduces the player escaped (3-waypoint
## miss rule). Incremented by entity_ai.gd's _observe_from_treeline_state().
## Reset to 0 by entity_sensory.gd when the player is seen or heard indoors.
var _consecutive_vantage_misses: int = 0

## How long the player has been staring at the Entity with the flashlight on.
## Written by on_player_stare(). Read by the Master Director (entity_director.gd).
## Range: 0.0 to 2.0+. 1.5+ triggers CHARGE if player is outside.
var player_stare_timer: float = 0.0

## The last world-space position the Entity knows the player was at.
## Written by entity_sensory.gd when the player is seen or heard.
## Read by entity_ai.gd for pathfinding toward the player.
var last_known_position: Vector3 = Vector3.ZERO

## Whether the player is currently within the Entity's line of sight.
## Written by entity_sensory.gd each frame. Read by the Director and AI.
var player_in_sight: bool = false

# --- SENSORY & HUNTING VARIABLES ---
var _last_known_position: Vector3 = Vector3.ZERO
var _current_interest_level: float = 0.0
var _is_hunting: bool = false
var _vision_cone_angle: float = deg_to_rad(70.0) # 140-degree field of view
var _interest_decay_rate: float = 2.5 # How fast it loses interest

## The name of the room the Entity last heard the player in (indoor search).
## Updated by on_player_noise() when the Entity is in INDOOR_SEARCH state.
## Used by entity_ai.gd's _indoor_search_state() to patrol toward the correct room.
var last_known_room_name: String = ""

## The exact world-space position of the last noise the Entity heard.
## Updated by hear_noise() whenever the Entity is within the noise radius.
## Used by entity_ai.gd's _indoor_search_state() to pathfind toward the exact
## noise coordinate instead of the room center, giving the Entity precise
## acoustic awareness without visual line-of-sight.
var _last_heard_exact_position: Vector3 = Vector3.ZERO

## ─── BLACKBOARD: Charge Triggered Flag ──────────────────────────────────────
## Set to true by entity_ai.gd's _indoor_search_state() when the Entity hears
## the player (acoustic detection) and should CHARGE instead of STALK.
## The Director reads this flag in a new Tier 3.5 and transitions to CHARGE.
## Reset to false by the Director after consuming the flag.
var is_charge_triggered: bool = false

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

## Whether a new relocate target (vantage point) has been set for the current
## observation cycle. Used by entity_ai.gd's _observe_from_treeline_state() to
## avoid calling pick_next_vantage_point() every frame — the Entity only needs
## one target per cycle. Reset to false when the Entity arrives at the vantage
## point or when the observation cycle completes.
var _relocate_target_set: bool = false

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
const VOICE_TALKING_1_PATH: String = "res://assets/audio/Entity/Entity Talking.ogg"
const VOICE_TALKING_2_PATH: String = "res://assets/audio/Entity/Entity Talking 2.ogg"
const VOICE_SEARCHING_PATH: String = "res://assets/audio/Entity/Entity Searching.ogg"
const VOICE_ANGRY_PATH: String = "res://assets/audio/Entity/Entity Angry.ogg"

## Whether the angry voice has been played this charge instance.
## Set to true when entity_angry.ogg fires during CHARGE/CHASE entry.
## Reset to false when the Entity leaves CHARGE/CHASE state.
var _voice_angry_played_this_charge: bool = false

## ─── CAN KILL TOGGLE (Debug Console) ──────────────────────────────────────
## When false, the Entity will CHARGE the player but NOT capture/kill them.
## The Entity will stop short and transition back to CHASE/OBSERVE instead.
## This is useful for testing chase behavior without triggering death scenes.
## Toggled via the Debug Console's "Toggle Can Kill" button.
## Default: true (Entity can capture the player).
var can_kill: bool = true

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

# --- FUSE SABOTAGE TIMING ---
## Timer counting up to 2.0 seconds between Entity strikes on the Fuse Box.
## Incremented by delta each frame while the Entity is within hitting distance
## of the Fuse Box. When it reaches 2.0, the Entity calls take_damage() on
## the Fuse Box and resets.
var _fuse_sabotage_timer: float = 0.0

## ─── BLACKBOARD: Fuse Sabotage Completion Flag ──────────────────────────────
## Set to true by _fuse_sabotage_state() when the Fuse Box is destroyed.
## The Director checks this flag and transitions to the next appropriate state.
## After consuming the flag, the Director resets it to false.
var is_fuse_sabotaged: bool = false

# ─── TREE GHOST MODE (Van Chase Stuck Prevention) ─────────────────────────
## When the Entity gets stuck on a tree during the van chase (STALK state),
## this timer counts down from 2.0 seconds while "Creeping Ghost" mode
## (no tree/rock collision) is active. When the timer expires, full
## collision is restored. This gives the Entity 2 seconds to phase through
## blocking foliage, then re-enables physics.
var _tree_ghost_timer: float = 0.0

## Whether tree ghost mode is currently active.
var _tree_ghost_active: bool = false

## The collision mask saved before entering tree ghost mode.
var _saved_tree_ghost_mask: int = 0

# --- OVERLOAD STUN STATE ---
## Timer counting down the stun duration (seconds remaining).
## Set by trigger_overload_stun() and decremented each frame during STUNNED.
## When it reaches 0.0, the Entity is released from the stun.
var _stun_timer: float = 0.0

## ─── MOTOR LOCK ──────────────────────────────────────────────────────────────
## When true, the motor is locked and set_motor_velocity() will NOT apply
## velocity changes. Used by the STUNNED state to freeze the Entity in place.
## Set by lock_motor_for_stun(), cleared by unlock_motor().
var _is_motor_locked: bool = false

## ─── LAST BREACHED WINDOW (Tactical Retreat) ─────────────────────────────────
## Permanently stores the root CabinWindow node that the Entity used to enter
## the cabin. Set when the Entity breaches a window (INDOOR_SEARCH entry).
## Used by the RETREAT handler to pathfind back to this window when the Entity
## is repelled by a light sanctuary or flashlight while indoors.
## Persists until the Entity breaches a different window.
var last_breached_window: Node = null

## ─── FLINCH FAILED WINDOW BLACKLIST ─────────────────────────────────────────
## Array of window IDs (String) that the Entity was repelled from via FLINCH
## while in APPROACH_WINDOW or WINDOW_PEEK state. When the Entity transitions
## to the next APPROACH_WINDOW cycle, pick_tactical_window() will skip any
## window whose ID appears in this list.
##
## Append: When the Director transitions to FLINCH from APPROACH_WINDOW or
##   WINDOW_PEEK (Tier 0), the current window target's ID is appended here.
##
## Clear: The entire array is cleared when:
##   1. The Entity successfully completes an OBSERVE_FROM_TREELINE relocation
##      cycle (fade_and_relocate() is called by the Director).
##   2. The Entity enters DORMANT state.
##   3. The Entity successfully breaches a DIFFERENT window (INDOOR_SEARCH).
##
## This prevents rapid ping-ponging between two guarded windows.
var _flinch_blacklisted_windows: Array[String] = []

## ─── DOOR APPROACH COOLDOWN ──────────────────────────────────────────────
## Cooldown timer preventing the Entity from immediately re-attempting the
## door after finding it locked. Set to 30.0 seconds when the Entity tries
## the door and finds it locked. Decremented each frame. While > 0.0, the
## door is excluded from pick_tactical_window() candidates.
var _door_approach_cooldown: float = 0.0

## ─── DOOR LOCKED FLAG ────────────────────────────────────────────────────
## Set to true by _approach_window_state() when the Entity arrives at the
## door and finds it locked. The Director reads this flag in Tier 5 and
## transitions to OBSERVE_FROM_TREELINE instead of INDOOR_SEARCH.
## Reset to false by the Director after consuming the flag.
var is_door_locked: bool = false

## ─── DOOR TARGET FLAG ────────────────────────────────────────────────────
## Set to true by _approach_window_state() when the current window target
## is detected as a door (not a window). The Director reads this flag in
## Tier 5 to distinguish between a window approach (→ WINDOW_PEEK) and a
## door approach (→ INDOOR_SEARCH if unlocked, OBSERVE if locked).
## Reset to false by the Director after consuming the flag.
var is_door_target: bool = false

## ─── DOOR PHASE TIMER ────────────────────────────────────────────────────
## Counts down the 2-second pause when the Entity arrives at a closed or
## locked door. Used by _approach_window_state() to manage the multi-phase
## door entry sequence:
##   Phase 0: Not started (standard approach)
##   Phase 1: Arrived at door — handling door state (locked/closed/open)
##   Phase 2: Walking through doorway to interior waypoint
var _door_phase: int = 0

## Timer for the door phase. Counts down from 2.0 seconds for locked/closed
## door pauses. Decremented each frame in _approach_window_state().
var _door_phase_timer: float = 0.0

## ─── DOOR PHASE 2 TIMER ──────────────────────────────────────────────────
## Timer that counts UP while the Entity is in Phase 2 (walking through the
## doorway). If the Entity has been in Phase 2 for more than 5.0 seconds
## without reaching the interior waypoint, the failsafe triggers a teleport
## to the interior waypoint to prevent the Entity from getting stuck.
## Reset to 0.0 when Phase 2 starts or when the Entity completes Phase 2.
var _door_phase_2_timer: float = 0.0

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

## Cooldown timer for the flashlight stare break confidence boost.
## Prevents the +8.0 boost from firing repeatedly when the flashlight beam
## rapidly oscillates across the Entity (e.g., player toggling the flashlight
## on/off). The boost can only fire once per 2.0 seconds.
## Set to 2.0 each time the boost fires. Decremented by delta each frame.
## If > 0.0, the boost is blocked.
var _confidence_stare_break_cooldown: float = 0.0
const CONFIDENCE_STARE_BREAK_COOLDOWN: float = 2.0

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
const COLLISION_LAYER_ENTITY: int = 5 # Layer 5: Dedicated entity body layer

## Stores the original collision layer before "Creeping Ghost" modifications.
var _saved_collision_layer: int = 5

## Stores the original collision mask before "Creeping Ghost" modifications.
## Restored when the Entity transitions to an aggressive state.
var _saved_collision_mask: int = 0

## ─── GHOST MODE ──────────────────────────────────────────────────────────────
## When enabled, the Entity disables ALL physics interactions (collision layers
## and masks) so it can pass through geometry without snagging. Used during the
## Door Phase A cinematic interpolation to prevent the Entity from getting stuck
## on the doorframe, porch stairs, or threshold colliders.
##
## IMPORTANT: Ghost mode also disables gravity by zeroing out the Y velocity
## each frame. The caller MUST call set_ghost_mode(false) when the interpolation
## completes, otherwise the Entity will fall through the floor.
var _ghost_mode: bool = false

## The target position for the Ghost Motor's manual position interpolation.
## Captured ONCE when ghost mode is enabled (from _ai._landing_position or
## from the DoorBreachWaypoint during APPROACH_WINDOW Phase 2) so the Ghost
## Motor moves consistently toward the target without the AI overwriting it
## each frame. Prevents the "Entity gets stuck mid-door" bug where the Ghost
## Motor and AI's Door Phase A fought over the target.
var _ghost_target: Vector3 = Vector3.ZERO

## Flag indicating that the ghost motor is being used for APPROACH_WINDOW
## Phase 2 (walking through the doorway). When true, the controller's
## _physics_process() handles the lerp and arrival check, and signals
## completion via is_approach_finished when the Entity reaches the
## IndoorBreachWaypoint.
var _ghost_door_phase_2: bool = false

# ─── CONTEXT-STEERING RAYCAST ARRAY ──────────────────────────────────────────
# Three RayCast3D nodes used for obstacle avoidance when the Entity is stalking
# with tree/rock collisions disabled (OBSERVE_FROM_TREELINE, PATROL).
# Programmatically instantiated in _ready().
var _ray_center: RayCast3D = null
var _ray_left: RayCast3D = null
var _ray_right: RayCast3D = null

# ─── FLOOR RAYCAST (Floating Sphere Ground Snapping) ──────────────────────────
# RayCast3D that projects 3.0m downward to detect the floor beneath the Entity.
# Used in _physics_process() to hover the floating sphere above terrain and snap
# the visual model to the actual ground surface.
var _floor_ray: RayCast3D = null

## When true, the Floor RayCast ground snapping is temporarily disabled.
## Used during Door Phase 2 (walking through the doorway) to allow the Entity
## to use standard physics to walk up the stairs. Without this, the ground
## snapping hovers the Entity above the stair treads, preventing it from
## climbing to the interior waypoint.
var _floor_snap_disabled: bool = false

# ─── DEBUG: Position Logging Timer ────────────────────────────────────────────
# Counts up each frame. Every 2 seconds, logs the Entity's global_position
# (especially Y) and what the floor raycast is colliding with.
var _debug_pos_log_timer: float = 0.0


func _ready() -> void:
	# Initialize the cached state keys array (must be done at runtime since
	# EntityAI.State.keys() cannot be called in a const context).
	STATE_KEYS = EntityAI.State.keys()

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
	_chase_exit_grunt_player.volume_db = -1.0
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
	_light_sanctuary_grunt_player.volume_db = 2.0  # 50% louder than original
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
	_claw_scrape_player.volume_db = -1.0
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
	_voice_player.unit_size = 6.0
	_voice_player.max_distance = 40.0
	_voice_player.volume_db = 2.0  # Boosted volume for immediate audibility during CHARGE
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
	_harass_audio.unit_size = 3.0
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
	
	# ─── FLOOR RAYCAST (Floating Sphere Ground Snapping) ──────────────
	# Projects 4.0m downward to detect the floor beneath the Entity.
	# Used in _physics_process() to hover the floating sphere above terrain
	# and snap the visual model to the actual ground surface.
	# Collision mask covers all physics layers that the Entity can walk on:
	#   Layer 1: Cabin geometry (walls, interior floors, foundation)
	#   Layer 2: Player (in case Entity stands on the player or vice versa)
	#   Layer 3: Trees / large foliage
	#   Layer 4: Rocks / terrain obstacles
	_floor_ray = RayCast3D.new()
	_floor_ray.name = "FloorRayCast"
	_floor_ray.target_position = Vector3(0, -4.0, 0)
	_floor_ray.collision_mask = 0
	_floor_ray.collision_mask |= (1 << (COLLISION_LAYER_CABIN - 1))   # Layer 1: Cabin
	_floor_ray.collision_mask |= (1 << (COLLISION_LAYER_PLAYER - 1))  # Layer 2: Player
	_floor_ray.collision_mask |= (1 << (COLLISION_LAYER_TREE - 1))    # Layer 3: Trees
	_floor_ray.collision_mask |= (1 << (COLLISION_LAYER_ROCK - 1))    # Layer 4: Rocks
	_floor_ray.hit_from_inside = true
	add_child(_floor_ray)
	
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
	
	# ─── NAVIGATION AGENT TUNING ──────────────────────────────────────
	# These values prevent the Entity from trying to hit waypoints too
	# precisely in tight interior spaces, and disable RVO avoidance which
	# fights the physics engine in narrow corridors (cabin doorframes).
	_nav_agent.path_desired_distance = 1.0
	_nav_agent.target_desired_distance = 1.5
	_nav_agent.radius = 0.4  # Reduced from default 0.5 by 20% for tighter pathfinding
	_nav_agent.avoidance_enabled = false  # RVO avoidance fights physics in tight spaces
	
	# ─── PHYSICS PROPERTY TWEAKS ──────────────────────────────────────
	# These prevent the Entity from snagging on door thresholds and
	# invisible wall edges in tight interior spaces.
	axis_lock_angular_x = true
	axis_lock_angular_z = true
	
	# Validate Model setup
	var active_player: AnimationPlayer = null
	if _monster_model:
		if _monster_model.has_node("AnimationPlayer"):
			active_player = _monster_model.get_node("AnimationPlayer") as AnimationPlayer
	
	if _anim_tree and active_player:
		_anim_tree.anim_player = _anim_tree.get_path_to(active_player)
		_anim_state_machine = _anim_tree.get("parameters/playback")
	
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


## Returns true if the Entity is currently active and should trigger
## hallucination/sanity effects when the player looks at it.
## Returns false if the Entity is hidden (Day 1, early Day 2, or banished).
## Both perception_manager.gd and sanity_controller.gd call this via
## has_method("is_active") + is_active() to gate their effects.
func is_active() -> bool:
	if not visible:
		return false
	if process_mode == PROCESS_MODE_DISABLED:
		return false
	return true


func _initialize_entity() -> void:
	_night_manager = get_node_or_null("/root/NightManager")
	_room_light_detector = get_node_or_null("/root/RoomLightDetector")
	if _night_manager:
		_night_manager.night_started.connect(_on_night_started)
		_night_manager.night_ended.connect(_on_night_ended)
		_night_manager.first_chase_started.connect(_on_first_chase_started)
		if _night_manager.is_night_active:
			# Night 1 & 2 exception: Entity stays hidden for the car alarm narrative.
			# The Entity only appears when the player interacts with the van via
			# _on_first_chase_started().
			if _night_manager.current_night <= 2:
				print("[Entity] Night %d at startup: Staying hidden for car alarm narrative." % _night_manager.current_night)
			else:
				activate()
				_relocate_behind_player()
		
	else:
		call_deferred("_initialize_entity")
		return
	
	# ─── ONE-TIME CACHED REFERENCE INITIALIZATION ──────────────────────
	# Resolve the FuseBox and Door nodes ONCE here instead of every frame.
	# If the exported variables are already assigned (via Inspector), skip
	# the expensive scene tree traversal.
	if not fuse_box_node:
		fuse_box_node = _find_fuse_box_once()
		if fuse_box_node:
			print("[Entity] Cached FuseBox reference: %s" % fuse_box_node.name)
		else:
			print("[Entity] WARNING: Could not find FuseBox node in scene tree.")
	
	if not door_node:
		door_node = _find_door_once()
		if door_node:
			print("[Entity] Cached Door reference: %s" % door_node.name)
		else:
			print("[Entity] WARNING: Could not find Door node in scene tree.")
	
	# Resolve the DoorBreachWaypoint once. If the exported variable is already
	# assigned (via Inspector), skip the expensive child-node search.
	if not door_breach_waypoint:
		door_breach_waypoint = _find_door_breach_waypoint_once()
		if door_breach_waypoint:
			print("[Entity] Cached DoorBreachWaypoint reference: %s" % door_breach_waypoint.name)
		else:
			print("[Entity] WARNING: Could not find DoorBreachWaypoint in scene tree.")
	
	# Resolve the FuseBox waypoint (EntityFuseWaypoint) once.
	# If the exported variable is already assigned (via Inspector), skip the
	# expensive child-node search.
	if not fuse_waypoint:
		fuse_waypoint = _find_fuse_waypoint_once()
		if fuse_waypoint:
			print("[Entity] Cached FuseWaypoint reference: %s" % fuse_waypoint.name)
		else:
			print("[Entity] WARNING: Could not find FuseWaypoint in scene tree.")
	
	# Resolve the Door's exterior waypoint marker (EntityDoorWaypoint) once.
	# If the exported variable is already assigned (via Inspector), skip the
	# expensive group lookup.
	if not door_waypoint_marker:
		door_waypoint_marker = _find_door_waypoint_once()
		if door_waypoint_marker:
			print("[Entity] Cached DoorWaypointMarker reference: %s" % door_waypoint_marker.name)
		else:
			print("[Entity] WARNING: Could not find DoorWaypointMarker in scene tree.")


## Performs a ONE-TIME search for the FuseBox node in the scene tree.
## This replaces the per-frame get_fuse_box_node() scene tree traversal.
## Uses the same logic as the old get_fuse_box_node() but only runs once.
func _find_fuse_box_once() -> Node:
	# First try: Find the FuseBox by class name in the scene tree
	if get_tree().current_scene:
		var candidates = []
		_find_fuse_box_recursive(get_tree().current_scene, candidates)
		if not candidates.is_empty():
			return candidates[0]
	
	# Second try: Find via EntityWaypoints group (FuseBoxWaypoint)
	var waypoints = get_tree().get_nodes_in_group("EntityWaypoints")
	for wp in waypoints:
		if wp.name == "FuseBoxWaypoint":
			var parent = wp.get_parent()
			if parent and parent is FuseBox:
				return parent
			for child in wp.get_children():
				if child is Marker3D:
					return child
	
	# Third try: Find the FuseBox by class name in the interactable group
	var interactables = get_tree().get_nodes_in_group("interactable")
	for node in interactables:
		if node is FuseBox:
			return node
	
	return null


## ─── DOOR/WINDOW PROXIMITY GRACE PERIOD ──────────────────────────────────────
## Returns true if the Entity is within `threshold` meters (2D XZ plane) of
## any door or window marker. Used by the stuck detection logic to extend the
## stuck timeout from 1.5s to 4.0s when the Entity is navigating through tight
## doorframes or window openings.
##
## This prevents the stuck detector from triggering fade_and_relocate() while
## the Entity is legitimately pathfinding through a bottleneck (e.g., walking
## through a doorway, squeezing past a window frame, or turning around a corner
## near a door).
##
## Uses 2D distance (XZ plane) to ignore vertical differences (e.g., the Entity
## is on the ground and the door is on a porch step).
const DOOR_WINDOW_PROXIMITY_THRESHOLD: float = 2.0

func _is_near_door_or_window() -> bool:
	# ─── CHECK DOOR ──────────────────────────────────────────────────────
	# Use the cached door_node reference (resolved once in _initialize_entity()).
	var door = get_door_node()
	if door:
		var my_pos_2d = Vector2(global_position.x, global_position.z)
		var door_pos_2d = Vector2(door.global_position.x, door.global_position.z)
		if my_pos_2d.distance_to(door_pos_2d) <= DOOR_WINDOW_PROXIMITY_THRESHOLD:
			return true
	
	# ─── CHECK CURRENT WINDOW TARGET ─────────────────────────────────────
	# If the Entity has a current window target (set during APPROACH_WINDOW
	# or WINDOW_PEEK), check proximity to that target.
	var window_target = get_current_window_target()
	if window_target:
		var my_pos_2d = Vector2(global_position.x, global_position.z)
		var target_pos_2d = Vector2(window_target.global_position.x, window_target.global_position.z)
		if my_pos_2d.distance_to(target_pos_2d) <= DOOR_WINDOW_PROXIMITY_THRESHOLD:
			return true
	
	# ─── CHECK ALL WINDOW MARKERS ────────────────────────────────────────
	# Use the navigation module's cached _window_markers array to avoid
	# expensive get_tree().get_nodes_in_group() calls in the physics loop.
	if _navigation and _navigation.has_method("get_window_markers"):
		var window_markers = _navigation.get_window_markers()
		if window_markers is Array and not window_markers.is_empty():
			var my_pos_2d = Vector2(global_position.x, global_position.z)
			for marker in window_markers:
				if not marker or not is_instance_valid(marker):
					continue
				var marker_pos_2d = Vector2(marker.global_position.x, marker.global_position.z)
				if my_pos_2d.distance_to(marker_pos_2d) <= DOOR_WINDOW_PROXIMITY_THRESHOLD:
					return true
	
	return false


## Performs a ONE-TIME search for the Door node in the scene tree.
## This replaces the per-frame get_tree().get_first_node_in_group("Door") calls.
func _find_door_once() -> Node:
	var door = get_tree().get_first_node_in_group("Door")
	if door:
		return door
	
	# Fallback: search by class name
	if get_tree().current_scene:
		return _find_node_by_class_recursive(get_tree().current_scene, "Door")
	
	return null


## Performs a ONE-TIME search for the DoorBreachWaypoint Marker3D child of the
## Door node. This replaces the per-frame child-node search that was called
## every frame during APPROACH_WINDOW / INDOOR_SEARCH.
## Uses the same logic as get_door_breach_waypoint() but only runs once.
func _find_door_breach_waypoint_once() -> Node3D:
	var door = get_door_node()
	if not door:
		return null
	
	# Look for a Marker3D child named "DoorBreachWaypoint" directly on the door
	for child in door.get_children():
		if child is Marker3D and child.name == "DoorBreachWaypoint":
			return child
	
	# Fallback: search recursively through children
	for child in door.get_children():
		for grandchild in child.get_children():
			if grandchild is Marker3D and grandchild.name == "DoorBreachWaypoint":
				return grandchild
	
	return null


## Performs a ONE-TIME search for the FuseBox waypoint Marker3D (EntityFuseWaypoint).
## This replaces the per-frame child iteration that was called every frame during
## SABOTAGE_FUSE to find the waypoint.
## Uses the same logic as the old per-frame search but only runs once.
func _find_fuse_waypoint_once() -> Marker3D:
	var fb = get_fuse_box_node()
	if not fb:
		return null
	
	# Look for a Marker3D child named "FuseBoxWaypoint" or any Marker3D child
	for child in fb.get_children():
		if child is Marker3D:
			return child
		if child.name == "FuseBoxWaypoint":
			return child
	
	# Also check grandchildren
	for child in fb.get_children():
		for grandchild in child.get_children():
			if grandchild is Marker3D:
				return grandchild
	
	return null


## Performs a ONE-TIME search for the Door's exterior waypoint Marker3D
## (EntityDoorWaypoint). This replaces the per-frame group lookup that was
## called every frame during APPROACH_WINDOW to find the door waypoint.
func _find_door_waypoint_once() -> Node3D:
	# First try: Find via EntityWaypoints group
	var waypoints = get_tree().get_nodes_in_group("EntityWaypoints")
	for wp in waypoints:
		if wp.name == "EntityDoorWaypoint":
			return wp
	
	# Second try: Find via DoorWaypoints group
	var door_wps = get_tree().get_nodes_in_group("DoorWaypoints")
	if not door_wps.is_empty():
		return door_wps[0] as Node3D
	
	# Third try: Search the Door node's children for a Marker3D named "EntityDoorWaypoint"
	var door = get_door_node()
	if door:
		for child in door.get_children():
			if child is Marker3D and child.name == "EntityDoorWaypoint":
				return child
		for child in door.get_children():
			for grandchild in child.get_children():
				if grandchild is Marker3D and grandchild.name == "EntityDoorWaypoint":
					return grandchild
	
	return null


## Recursively searches the scene tree for a node with the given class name.
func _find_node_by_class_recursive(node: Node, target_class: String) -> Node:
	if node.get_class() == target_class:
		return node
	for child in node.get_children():
		var result = _find_node_by_class_recursive(child, target_class)
		if result:
			return result
	return null


func _on_night_started(night: int) -> void:
	if _ai and _ai.has_method("on_night_started"):
		_ai.on_night_started(night) # AI updates its speed/chance stats
	
	# Night 1 & 2 exception: Entity stays hidden for the car alarm narrative.
	# The Entity only appears when the player interacts with the van via
	# _on_first_chase_started(). Night 1 = eco-survey, Night 2 = car alarm.
	if night <= 2:
		print("[Entity] Night %d: Staying hidden for car alarm narrative. Entity will spawn when player investigates the van." % night)
		return

	
	# Check if the Entity has been manually disabled via the debug console.
	# The debug console sets a meta flag "debug_disabled" when the player
	# toggles it off. If set, we skip activation so the Entity stays dormant
	# even when a new night starts.
	if has_meta("debug_disabled") and get_meta("debug_disabled"):
		print("[Entity] Night %d: Debug-disabled via console. Skipping activation." % night)
		return
	
	activate() # Controller handles visibility (clears stale _pending_state)
	_relocate_behind_player() # Controller handles physical placement
	
	# ─── NIGHT 3+ : ENSURE ENTITY ENTERS HUNTING STATE ──────────────
	# After activate(), the Entity is visible and has physics enabled, but
	# its state machine may still be in DORMANT from the day. The Director
	# will transition it, but only if _pending_state is clear and the
	# Entity is active. We explicitly request OBSERVE_FROM_TREELINE to
	# ensure the Entity immediately enters its baseline hunting behavior
	# for Night 3+ — any night where the Entity should be actively hunting.
	# This fixes the "Night 3+ Entity stuck in DORMANT" bug.
	request_state(EntityAI.State.OBSERVE_FROM_TREELINE)


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
	
	# Activate the Entity (make visible) and immediately begin stalking
	activate()
	request_state(EntityAI.State.STALK)
	print("[Entity] Cinematic arrival complete! Now stalking the player.")
	
	# ─── ISSUE 4 FIX: Remove Time Crunch override ──────────────────
	# Time is now managed exclusively by escape_van.gd, which forces
	# cycle_progress = 0.66 (04:00 AM) and unpauses when the player
	# interacts with the van. The Entity should NOT override GameTime
	# — its only job is to spawn and begin stalking.





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
	# ─── CLEAR STALE PENDING STATE ────────────────────────────────────
	# When deactivate() was called, request_state(DORMANT) was set but the
	# Director never consumed it (the Entity froze before the next frame).
	# On re-activation, this stale DORMANT state would immediately be applied
	# by the Director's Tier 0, keeping the Entity stuck in DORMANT.
	# Clear it so the Director sees a clean slate and evaluates normally.
	_pending_state = -1
	
	# ─── PLAYER REFERENCE CHECK ───────────────────────────────────────
	# If _player is null (e.g., scene was reloaded between nights), find it
	# before proceeding. Without a valid _player, _physics_process() early-exits
	# and the Entity is brain-dead despite _is_active = true.
	if not _player:
		_find_player()
	
	_is_active = true
	visible = true
	_set_visuals_visible(true)
	
	# ─── RESTORE PHYSICS ──────────────────────────────────────────────
	# Mirror the deactivate() disable logic: restore process mode,
	# collision shape, collision layer, and collision mask so the Entity
	# can move and physically interact with the world again.
	process_mode = Node.PROCESS_MODE_INHERIT
	if _collision_shape:
		_collision_shape.disabled = false
	
	collision_layer = (1 << (COLLISION_LAYER_ENTITY - 1))  # Layer 5: Entity
	collision_mask = 0
	collision_mask |= (1 << (COLLISION_LAYER_CABIN - 1))   # Layer 1: Cabin
	collision_mask |= (1 << (COLLISION_LAYER_PLAYER - 1))  # Layer 2: Player
	collision_mask |= (1 << (COLLISION_LAYER_TREE - 1))    # Layer 3: Trees
	collision_mask |= (1 << (COLLISION_LAYER_ROCK - 1))    # Layer 4: Rocks
	
	# NOTE: request_state() is intentionally NOT called here.
	# The caller (escape_van.gd or _on_first_chase_started()) immediately
	# calls request_state(STALK) after activate(). Calling
	# request_state(OBSERVE_FROM_TREELINE) here would race against that
	# STALK request, allowing the Director to consume OBSERVE first and
	# leave the Entity stuck in DORMANT while _pending_state cycles.
	# The caller owns the state transition, not activate().


func deactivate() -> void:
	_is_active = false
	velocity = Vector3.ZERO
	visible = false
	
	# ─── CLEAR FLINCH BLACKLIST ON DORMANT ENTRY ────────────────────────
	# When the Entity despawns (daytime/reset), clear all flinch-blacklisted
	# windows so the Entity starts fresh on the next night (Correction 3).
	if not _flinch_blacklisted_windows.is_empty():
		print("[FLINCH BLACKLIST] Cleared %d blacklisted windows on deactivation." % _flinch_blacklisted_windows.size())
		_flinch_blacklisted_windows.clear()
	
	request_state(EntityAI.State.DORMANT)
	_set_visuals_visible(false)
	
	# Reset enrage state so the Entity starts fresh next night
	_is_enraged = false
	_original_stalk_speed = 0.0
	
	# ─── PHYSICS DISABLE (Daytime Ghost Collider Fix) ─────────────
	# Disable the CollisionShape3D so the player doesn't collide with
	# an invisible, immovable physics body.
	# NOTE: We do NOT set process_mode to PROCESS_MODE_DISABLED here.
	# Setting DISABLED on the Entity root prevents ALL children (including
	# EntityConfidence with the F3 debug overlay) from processing, even
	# if they have PROCESS_MODE_ALWAYS. The Entity's _physics_process()
	# already early-exits via the _is_active guard, and _process() on
	# children with PROCESS_MODE_ALWAYS will continue to run correctly.
	if _collision_shape:
		_collision_shape.disabled = true

	
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
	
	# ─── DEBUG: Position Log (every 2 seconds, ALL active states) ──────
	# PERFORMANCE: Only runs in debug builds. In production builds, this
	# entire block (RoomLightDetector query, string formatting, print() calls)
	# is skipped to avoid recurring frame spikes and console I/O overhead.
	if OS.is_debug_build():
		_debug_pos_log_timer += delta
		if _debug_pos_log_timer >= 2.0:
			_debug_pos_log_timer = 0.0
			var ray_hit = _floor_ray.is_colliding()
			var hit_info = ""
			if ray_hit:
				var hit_point = _floor_ray.get_collision_point()
				var hit_normal = _floor_ray.get_collision_normal()
				var collider = _floor_ray.get_collider()
				var collider_name = collider.name if collider else "null"
				# ─── GROUND NOISE FILTER ──────────────────────────────────
				# The floor raycast ALWAYS hits the ground (it's pointing down).
				# "GroundFloorCollision" is the cabin floor — it's not useful info.
				# Filter it out so the debug log only shows non-ground collisions
				# (e.g., stairs, furniture, door thresholds).
				if collider_name.contains("Ground") or collider_name.contains("Floor"):
					hit_info = "collider=Ground hit_y=%.3f normal=%s" % [hit_point.y, hit_normal]
				else:
					hit_info = "collider=%s hit_y=%.3f normal=%s" % [collider_name, hit_point.y, hit_normal]
			else:
				hit_info = "NO_HIT"
			var _state_name = STATE_KEYS[_state] if _state >= 0 and _state < STATE_KEYS.size() else "UNKNOWN"
			var _shape_d = _collision_shape.disabled if _collision_shape else "N/A"
			var _room_name = RoomLightDetector.get_room_name_at(global_position)
			print("[Entity DEBUG] pos=(%.3f, %.3f, %.3f) room=%s state=%s layer=%d mask=%d shape_disabled=%s floor_ray=%s" % [global_position.x, global_position.y, global_position.z, _room_name, _state_name, collision_layer, collision_mask, _shape_d, hit_info])
			
			# ─── TIME DIAGNOSTIC: NightManager vs GameTime ────────────────
			var nm = _night_manager
			var gt = get_node_or_null("/root/GameTime")
			if nm and gt:
				print("[TIME DIAGNOSTIC] NightManager: current_night=%d, is_night_active=%s, is_time_paused=%s" % [nm.current_night, nm.is_night_active, nm.is_time_paused])
				print("[TIME DIAGNOSTIC] GameTime:     cycle_progress=%.4f, is_day=%s, is_time_paused=%s" % [gt.cycle_progress, gt.is_day, gt.is_time_paused])

	
	_game_time += delta
	
	# ─── TREE GHOST TIMER DECREMENT ────────────────────────────────────
	# When tree ghost mode is active, decrement the timer each frame.
	# When the timer expires, restore the full collision mask so the
	# Entity can collide with trees/rocks again.
	if _tree_ghost_active:
		_tree_ghost_timer -= delta
		if _tree_ghost_timer <= 0.0:
			_tree_ghost_active = false
			# Restore the full collision mask saved when ghost mode was activated
			if _saved_tree_ghost_mask != 0:
				collision_mask = _saved_tree_ghost_mask
				_saved_tree_ghost_mask = 0
				print("[Entity] Tree ghost mode expired. Full collision restored.")
	
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
	
	# Door approach cooldown decrement (locked door retry timer)
	if _door_approach_cooldown > 0.0:
		_door_approach_cooldown -= delta
	
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
	#
	# STATE AWARENESS GUARD: Stuck detection is also DISABLED during the
	# following states where the Entity is INTENTIONALLY stationary:
	#   - DORMANT: Entity is despawned/hidden (handled separately above)
	#   - WINDOW_PEEK: Entity stares through window for 8-15 seconds
	#   - STANDOFF: Entity frozen in place (flashlight stare)
	#   - OBSERVE_FROM_TREELINE: Entity waits at treeline vantage point
	#   - STUNNED: Entity paralyzed by overload trap
	#   - HARASS: Entity performing psychological harassment at window
	# Without this guard, the stuck detector fires during these intentional
	# stationary periods and triggers unnecessary fade_and_relocate() calls.
	var _state_exempt: bool = (
		_state == EntityAI.State.WINDOW_PEEK or
		_state == EntityAI.State.STANDOFF or
		_state == EntityAI.State.HARASS or
		_state == EntityAI.State.STUNNED
	)
	var is_nav_active: bool = not _nav_agent.is_navigation_finished()
	var is_moving: bool = get_real_velocity().length_squared() > 0.01
	var is_attack_state: bool = (
		_state == EntityAI.State.STALK or
		_state == EntityAI.State.CHARGE or
		_state == EntityAI.State.FLINCH or
		_state == EntityAI.State.STUNNED
	)
	
	# ─── STUCK DETECTOR STATE-AWARENESS ────────────────────────────
	# When in exempt states (WINDOW_PEEK, STANDOFF, HARASS, STUNNED),
	# the stuck detectors must NOT fire — the Entity is intentionally
	# stationary. We reset the timers each frame so they never trigger
	# a false-positive fade_and_relocate().
	#
	# IMPORTANT: We do NOT return early here. The rest of the physics
	# process (AI state logic, sensor processing, move_and_slide, and
	# Director evaluation) must still run every frame, otherwise the
	# Entity freezes — the AI never processes state transitions, the
	# Director never checks flashlight reactions (FLINCH), and the
	# WINDOW_PEEK siege timer never advances.
	if _state_exempt:
		_stuck_timer = 0.0
		_pos_stuck_timer = 0.0
		_pos_stuck_logged = false
	
	# ─── DORMANT STATE GUARD ────────────────────────────────────────────────
	# When the Entity is in DORMANT (intentionally despawned/hidden), the stuck
	# detector must NOT run. The Entity is supposed to be motionless — it's
	# either daytime, hidden during Night 1 narrative, or has been deactivated.
	# Without this guard, the stuck detector sees zero velocity + active nav
	# and triggers fade_and_relocate(), which forces the Entity out of DORMANT
	# and creates a 60fps DORMANT↔fade_and_relocate loop.
	#
	# DORMANT also means the NavigationAgent3D may have a stale target position
	# from the previous active night. The Entity should not attempt to pathfind
	# while hidden.
	if _state == EntityAI.State.DORMANT:
		_stuck_timer = 0.0
		_pos_stuck_timer = 0.0
		_pos_stuck_logged = false
		# Halt the NavigationAgent3D to prevent residual nav data.
		_nav_agent.target_position = global_position
		return
	
	# ─── STALK TREE GHOST MODE (Van Chase Stuck Prevention) ──────────────
	# When the Entity is in STALK state during the van chase and gets stuck
	# on a tree for 2+ seconds, temporarily disable tree/rock collision to
	# let it phase through foliage. The timer counts down from 2.0 seconds
	# and restores full collision when it expires.
	if _state == EntityAI.State.STALK and not _tree_ghost_active:
		var _is_stuck: bool = _stuck_timer >= 2.0 or (is_nav_active and not is_moving and _stuck_timer >= 2.0)
		if _is_stuck:
			# Save the current mask and switch to "Creeping Ghost" mode
			_saved_tree_ghost_mask = collision_mask
			collision_mask = 0
			collision_mask |= (1 << (COLLISION_LAYER_CABIN - 1))  # Layer 1: Cabin
			collision_mask |= (1 << (COLLISION_LAYER_PLAYER - 1)) # Layer 2: Player
			_tree_ghost_active = true
			_tree_ghost_timer = 2.0
			print("[Entity] TREE STUCK! Activating tree ghost mode for 2.0 seconds to phase through foliage.")
	
	# ─── SMART STUCK DETECTION ──────────────────────────────────────────────
	# Detects when the Entity is stuck (not moving while nav is active) and
	# triggers a fade_and_relocate() to teleport to a new vantage point.
	#
	# INDOOR_SEARCH SPECIAL HANDLING:
	#   The NavMesh may not cover the cabin interior. When the NavigationAgent3D
	#   can't find a path, is_navigation_finished() returns true immediately,
	#   making is_nav_active = false. We detect this "stranded" state by checking
	#   if the nav is "finished" but the Entity is still far from the target.
	#   If stranded for 3+ seconds, teleport directly to the indoor breach
	#   waypoint to kickstart the AI.
	#
	# ATTACK STATE GUARD:
	#   Stuck detection is disabled during CHASE, CHARGE, FLINCH,
	#   and STUNNED — the Entity should never teleport away while actively
	#   pursuing the player or performing a scripted action.
	#
	# BARRICADE AWARENESS:
	#   If the Entity is stuck near a boarded window, it should NOT relocate.
	#   Instead, it should attempt to damage the barricade. The barricade
	#   damage logic is handled by the WINDOW_PEEK state handler — the stuck
	#   detector simply avoids triggering relocation when the Entity is near
	#   a window target.
	
	# Detect if the nav agent thinks it's "finished", but we are still far
	# from the player (stranded — NavMesh doesn't cover the interior).
	var dist_to_target = global_position.distance_to(_nav_agent.target_position)
	var is_stranded = not is_nav_active and dist_to_target > 1.0
	
	if _state == EntityAI.State.INDOOR_SEARCH:
			# ─── BREACH LOCK GUARD ──────────────────────────────────────────
		# If the Entity is in Door Phase A (breach in progress), do NOT
		# trigger stuck detection. The Entity is walking toward the
		# IndoorBreachWaypoint and may appear "stranded" because the NavMesh
		# doesn't cover the cabin interior. The breach frame-count gate in
		# entity_ai.gd's _indoor_search_state() handles the arrival timing.
		# Without this guard, the stuck detector fires at 3 seconds and
		# teleports the Entity to the breach waypoint, bypassing the frame-
		# count gate and causing the "instant breach" bug.
		if _ai and _ai.has_method("is_breach_in_progress") and _ai.is_breach_in_progress():
			_stuck_timer = 0.0
			return
		
		# ─── BREACH LOCK TIMEOUT ──────────────────────────────────────────
		# If is_breach_locked has been active for more than 5.0 seconds,
		# force-unlock it and teleport the Entity to the indoor breach waypoint.
		# This prevents the Entity from getting permanently stuck in the breach
		# lock if the pathfinding fails to reach the IndoorBreachWaypoint.
		if is_breach_locked:
			_breach_lock_timer += delta
			if _breach_lock_timer > 5.0:
				print("[BREACH_LOCK] TIMEOUT! Breach lock active for %.1f seconds. Force-unlocking and teleporting to indoor waypoint." % _breach_lock_timer)
				is_breach_locked = false
				_breach_lock_timer = 0.0
				# Teleport to the indoor breach waypoint
				if _ai and _ai.has_method("get_indoor_breach_waypoint"):
					global_position = _ai.get_indoor_breach_waypoint()
					print("[BREACH_LOCK] Teleported to indoor breach waypoint via timeout.")
		else:
			_breach_lock_timer = 0.0

		
		# [TRACE] Log stuck detection state for INDOOR_SEARCH
		var real_vel_stuck = get_real_velocity()
		if is_stranded or (is_nav_active and not is_moving):
			_stuck_timer += delta
			if _stuck_timer > 3.0:
				# ─── BARRICADE AWARENESS CHECK ──────────────────────────
				# DOOR ENTRY GUARD: If the Entity entered through a door
				# (was_door_entry == true), the _current_window_target is the
				# Door's WindowMarker, which is right next to the Entity.
				# Checking dist_to_window <= 5.0 would ALWAYS be true,
				# creating an infinite reset loop that prevents
				# fade_and_relocate() from ever firing.
				# Only apply the barricade awareness check for WINDOW entries.
				# DO NOT rely on the transient was_door_entry flag — it gets consumed
				# by the early arrival check in entity_ai.gd's _indoor_search_state()
				# on the first frame, making it false for all subsequent frames.
				# Instead, dynamically check if the _current_window_target's parent
				# belongs to the "Door" group. If it's a door, skip the barricade
				# reset so the stuck timer can reach 3.0s and trigger the failsafe
				# teleport to the indoor breach waypoint.
				var window_target = get_current_window_target()
				if window_target:
					# Check if the target is actually a door marker (not a window)
					var is_door = false
					var parent = window_target.get_parent()
					if parent and parent.is_in_group("Door"):
						is_door = true
					
					# Only reset the timer if it's an actual window, NOT a door!
					if not is_door:
						var dist_to_window = global_position.distance_to(window_target.global_position)
						if dist_to_window <= 5.0:
							
							_stuck_timer = 0.0
							return

				
				# ─── FAILSAFE: Teleport to indoor breach waypoint ──────
				# If stranded indoors (NavMesh can't reach the player),
				# teleport directly to the indoor breach waypoint to
				# kickstart the AI. This prevents the Entity from standing
				# still forever at the doorway.
				if _ai and _ai.has_method("get_indoor_breach_waypoint"):
					global_position = _ai.get_indoor_breach_waypoint()
					print("[Entity] INDOOR STRANDED! Teleported to indoor breach waypoint.")
				else:
					print("[Entity] INDOOR STUCK DETECTED! No movement for 3.0s while inside. Relocating.")
					fade_and_relocate()
				_stuck_timer = 0.0
		else:
			if _stuck_timer > 0.0:
				print("[TRACE_STUCK] INDOOR_SEARCH: Unstuck! Resetting timer. is_stranded=%s, is_nav_active=%s, is_moving=%s" % [is_stranded, is_nav_active, is_moving])
			_stuck_timer = 0.0
	elif is_nav_active and not is_moving and not is_attack_state:
		# ─── STUCK GRACE PERIOD (negative timer) ─────────────────────────
		# When _stuck_timer is negative (set by escape_van.gd during Entity
		# van spawn), it acts as a grace period. The NavigationAgent3D needs
		# 2-3 seconds to generate a valid path around the van's collision
		# mesh. During this grace period, we increment the timer toward 0
		# but do NOT trigger the stuck failsafe.
		if _stuck_timer < 0.0:
			_stuck_timer += delta
			return
		
		# ─── DOOR PHASE GUARD ──────────────────────────────────────────
		# During APPROACH_WINDOW, the Entity intentionally pauses at the
		# door for 2 seconds (Door Phase 1) while the AI checks if the door
		# is locked, opens it, etc. During this pause, velocity is zero and
		# the nav agent is still active (not finished). Without this guard,
		# the stuck detector fires after 1.5s and triggers fade_and_relocate(),
		# teleporting the Entity away from the door it just arrived at.
		#
		# We detect this by checking if the Entity is in APPROACH_WINDOW
		# state AND the door phase is active (_door_phase > 0). If so,
		# we skip the stuck detection entirely — the Entity is intentionally
		# waiting, not stuck.
		var is_door_phase_active = (_state == EntityAI.State.APPROACH_WINDOW and _door_phase > 0)
		
		if not is_door_phase_active:
			# ─── PROXIMITY GRACE PERIOD ──────────────────────────────────────
			# If the Entity is within 2.0m of a door or window, use the extended
			# stuck timeout (stuck_timeout_near_door = 4.0s) instead of the
			# standard 1.5s. This prevents the stuck detector from triggering
			# fade_and_relocate() while the Entity is legitimately pathfinding
			# through a doorway or window opening — the NavigationAgent3D may
			# briefly pause to recalculate the path through the narrow NavMesh
			# edge, or the Entity may be sliding along the doorframe while the
			# Floating Sphere ground snapping adjusts its Y position.
			var effective_timeout = stuck_timeout_near_door if _is_near_door_or_window() else stuck_timeout
			_stuck_timer += delta
			if _stuck_timer >= effective_timeout:
				var real_vel := get_real_velocity()
				print("[Entity] STUCK DETECTED! No movement for %.1fs while nav is active. real_vel=(%.3f, %.3f, %.3f) len=%.3f. Relocating." % [effective_timeout, real_vel.x, real_vel.y, real_vel.z, real_vel.length()])
				fade_and_relocate()
				_stuck_timer = 0.0
		else:
			# Reset the stuck timer while waiting at the door
			_stuck_timer = 0.0
	else:
		_stuck_timer = 0.0

	
	# ─── POSITION-BASED STUCK DETECTION ──────────────────────────────────────
	# Tracks whether the Entity has been at the same coordinates for 2+ seconds
	# while the nav agent is active. This catches "treadmilling" — where the
	# Entity has non-zero velocity but is NOT making progress toward its target
	# (e.g., pushing against an invisible wall, stuck on a door threshold, or
	# pathfinding to an unreachable NavMesh edge).
	#
	# Unlike the velocity-based stuck detector above (which checks
	# get_real_velocity().length_squared() > 0.01), this detector compares the
	# Entity's actual position frame-over-frame. If the position hasn't changed
	# by more than POS_STUCK_THRESHOLD (0.1m) for POS_STUCK_TIMEOUT (2.0s)
	# while the nav agent is active, it logs a detailed diagnostic.
	#
	# The diagnostic includes:
	#   - Where the Entity is (current global_position)
	#   - Where it's trying to go (nav target_position)
	#   - What it's colliding with (last slide collision collider name)
	#
	# This is specifically designed to catch the "doorway treadmill" bug where
	# the Entity has velocity (~0.5 m/s) but is sliding along a wall/doorframe
	# instead of moving toward the IndoorBreachWaypoint.
	#
	# ATTACK STATE GUARD:
	#   Position-based stuck detection is disabled during CHASE, CHARGE, FLINCH,
	#   and STUNNED — same as the velocity-based detector.
	#
	# INDOOR_SEARCH GUARD:
	#   Position-based stuck detection is also disabled during INDOOR_SEARCH
	#   because the NavMesh may not cover the cabin interior, causing the
	#   Entity to appear "stuck" when it's actually stranded. The INDOOR_SEARCH
	#   state has its own dedicated stuck detection logic above.
	#
	# STATIONARY STATE GUARD:
	#   Position-based stuck detection is also disabled during WINDOW_PEEK,
	#   STANDOFF, STUNNED, and HARASS — the Entity is intentionally stationary
	#   during these states (staring through a window, frozen by flashlight,
	#   paralyzed by overload trap, or performing harassment). Without this
	#   guard, the position-based detector fires after 2.0 seconds and logs
	#   a confusing "Entity stuck" diagnostic even though the Entity is behaving
	#   correctly.
	if not is_attack_state and _state != EntityAI.State.INDOOR_SEARCH and not _state_exempt:
		var current_pos = global_position
		var pos_changed = current_pos.distance_squared_to(_last_stuck_position) > POS_STUCK_THRESHOLD * POS_STUCK_THRESHOLD
		
		if is_nav_active and not pos_changed:
			_pos_stuck_timer += delta
			if _pos_stuck_timer >= POS_STUCK_TIMEOUT and not _pos_stuck_logged:
				_pos_stuck_logged = true
				
				# ─── BUILD DIAGNOSTIC ──────────────────────────────────
				# Gather information about what the Entity is colliding with
				# by checking ALL slide collisions from move_and_slide().
				# We iterate through ALL collisions and filter out the ground
				# ("GroundFloorCollision") so we only see the actual obstacle
				# blocking the Entity (e.g., doorframe, ramp, wall).
				#
				# GROUND NOISE FILTER:
				# The Entity is always colliding with the ground (it walks on it).
				# "GroundFloorCollision" is the name of the cabin's floor StaticBody3D.
				# We skip it because it's not the thing blocking the Entity — it's
				# the thing the Entity is standing on. Without this filter, the log
				# always says "GroundFloorCollision" and never reveals the actual
				# obstacle (doorframe, ramp edge, porch post, etc.).
				var collision_info = "none"
				var slide_count = get_slide_collision_count()
				for i in range(slide_count):
					var collision = get_slide_collision(i)
					if not collision:
						continue
					var collider = collision.get_collider()
					if not collider:
						continue
					var collider_name = collider.name if collider else "null"
					var collider_class = collider.get_class() if collider else "null"
					
					# ─── GROUND NOISE FILTER ──────────────────────────
					# Skip "GroundFloorCollision" — it's the floor, not an obstacle.
					# Also skip any collider whose name contains "Ground" or "Floor"
					# to catch variations (GroundCollision, FloorMesh, etc.).
					if collider_name.contains("Ground") or collider_name.contains("Floor"):
						continue
					
					collision_info = "%s (%s)" % [collider_name, collider_class]
					break  # Use the first non-ground collision found
				
				var nav_target = _nav_agent.target_position
				var real_vel = get_real_velocity()
				var state_name = STATE_KEYS[_state] if _state >= 0 and _state < STATE_KEYS.size() else "UNKNOWN"
				
				print("[POS_STUCK] Entity stuck at same position for %.1fs!" % _pos_stuck_timer)
				print("[POS_STUCK]   Position:      (%.3f, %.3f, %.3f)" % [current_pos.x, current_pos.y, current_pos.z])
				print("[POS_STUCK]   Nav Target:    (%.3f, %.3f, %.3f)" % [nav_target.x, nav_target.y, nav_target.z])
				print("[POS_STUCK]   Dist to Target: %.2fm" % current_pos.distance_to(nav_target))
				print("[POS_STUCK]   State:         %s" % state_name)
				print("[POS_STUCK]   Real Velocity: (%.3f, %.3f, %.3f) len=%.3f" % [real_vel.x, real_vel.y, real_vel.z, real_vel.length()])
				print("[POS_STUCK]   Last Collision: %s" % collision_info)
				print("[POS_STUCK]   Nav Finished:  %s" % _nav_agent.is_navigation_finished())

		else:
			# Reset the timer and log flag if the Entity moved or nav finished
			if pos_changed or not is_nav_active:
				_pos_stuck_timer = 0.0
				_pos_stuck_logged = false
				_last_stuck_position = current_pos
	else:
		# Reset for attack states and INDOOR_SEARCH
		_pos_stuck_timer = 0.0
		_pos_stuck_logged = false
		_last_stuck_position = global_position
	
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
	# ─── STARE BREAK COOLDOWN DECAY ─────────────────────────────────
	# Decrement the cooldown timer each frame. When it reaches 0.0, the
	# +8.0 confidence boost can trigger again on the next stare break.
	# This prevents the "flashlight pump" where rapidly toggling the
	# flashlight fires the +8.0 boost every toggle, reaching 40+ in
	# ~3 seconds.
	if _confidence_stare_break_cooldown > 0.0:
		_confidence_stare_break_cooldown -= delta
	
	# ─── STARE BREAK CONFIDENCE BOOST ────────────────────────────────
	# One-time boost: +8.0 confidence when the player breaks line of sight.
	# Gated by a 2-second cooldown to prevent rapid-fire pumping when the
	# flashlight beam rapidly oscillates across the Entity.
	if _confidence_stare_was_active and not _confidence_stare_active and _confidence_stare_break_cooldown <= 0.0:
		if _confidence and _confidence.has_method("modify"):
			_confidence.modify(8.0, "flashlight_stare_break")
			_confidence_stare_break_cooldown = CONFIDENCE_STARE_BREAK_COOLDOWN
			print("[Entity Controller] Confidence boost: +8.0 (player broke flashlight stare). Cooldown set to %.1fs." % CONFIDENCE_STARE_BREAK_COOLDOWN)
	
	_confidence_stare_was_active = _confidence_stare_active
	
	# Reset the light sanctuary grunt debounce when the player stops
	# shining the flashlight on the Entity. This allows the grunt to
	# play again on the next spotting cycle.
	if _has_played_light_sound and not (_sensory and _sensory.is_player_spotting_entity()):
		_has_played_light_sound = false
	
	# --- CHASE MUSIC (ambience_d6_loop) ---
	# Fade in when entering CHASE state, fade out when leaving.
	var is_chasing = _state == EntityAI.State.STALK or _state == EntityAI.State.CHARGE
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
	
	# --- ENRAGED STATE (Blackout Release) ---
	# The generator died while the Entity was stunned. The Entity is now
	# permanently enraged for the rest of the night — 1.5x movement speed.
	# ENRAGED is a modifier flag, not a blocking state — the Entity still
	# uses its normal FSM states (CHASE, PATROL, etc.) but with boosted speed.
	# The _is_enraged flag is checked by the AI speed calculations.
	
	# ─── GHOST MOTOR: APPROACH_WINDOW PHASE 2 ──────────────────────────────
	# When _ghost_door_phase_2 is true, the Entity is walking through the
	# doorway via manual position interpolation (ghost mode). The AI's
	# _approach_window_state() sets up the ghost target and enables this flag.
	# The controller handles the lerp and arrival check here, then signals
	# completion via is_approach_finished.
	#
	# This MUST run BEFORE the AI state logic below, because the ghost motor
	# directly manipulates global_position and should NOT be overridden by
	# the AI's calculated velocity.
	if _ghost_door_phase_2:
		# ─── FAILSAFE TIMEOUT ─────────────────────────────────────────────
		_door_phase_2_timer += delta
		if _door_phase_2_timer >= 5.0:
			print("[Entity] APPROACH_WINDOW Phase 2 GHOST MOTOR FAILSAFE! %ds elapsed. Force-teleporting inside." % _door_phase_2_timer)
			var breach_wp = get_door_breach_waypoint()
			if breach_wp:
				global_position = breach_wp.global_position
				# ─── POST-TELEPORT VALIDATION ──────────────────────────────
				# Verify the Entity is actually inside a valid cabin room after
				# teleporting. If the IndoorBreachWaypoint is misconfigured or
				# positioned outside the cabin, the Entity would go into
				# INDOOR_SEARCH while still physically outside.
				var room_name = RoomLightDetector.get_room_name_at(global_position)
				print("[Entity] GHOST MOTOR FAILSAFE: Position after teleport = (%.2f, %.2f, %.2f) | Room = '%s'" % [global_position.x, global_position.y, global_position.z, room_name])
				if _ai and _ai.has_method("_is_position_inside_cabin") and not _ai._is_position_inside_cabin(global_position):
					# Still outside! Try the fallback interior position.
					var fallback = _ai._get_fallback_indoor_position()
					print("[Entity] GHOST MOTOR FAILSAFE: Entity STILL OUTSIDE (room='%s')! Teleporting to fallback position." % room_name)
					global_position = fallback
					room_name = RoomLightDetector.get_room_name_at(global_position)
					print("[Entity] GHOST MOTOR FAILSAFE: Fallback position: (%.2f, %.2f, %.2f) | Room = '%s'" % [fallback.x, fallback.y, fallback.z, room_name])
			_ghost_door_phase_2 = false
			_ghost_mode = false
			is_breach_locked = false
			was_door_entry = true
			is_approach_finished = true
			state_locked = false
			_door_phase = 0
			_door_phase_2_timer = 0.0
			# Notify AI that the Entity has physically arrived indoors
			if _ai and _ai.has_method("set_has_arrived_indoor"):
				_ai.set_has_arrived_indoor(true)
			# Prime the indoor search persistence timer NOW (before the Director
			# evaluates on the next frame). Without this, the persistence timer
			# is 0.0 when the Director runs, causing it to fall through to
			# OBSERVE_FROM_TREELINE and re-enter APPROACH_WINDOW.
			if _ai and _ai.has_method("reset_indoor_search_persistence"):
				_ai.reset_indoor_search_persistence()
			# Record door breach timestamp for Director's Tier 8 persistence check
			last_door_breach_time = Time.get_ticks_msec() / 1000.0
			# Restore physics
			set_collision_mask_value(1, true)
			if has_method("get_collision_shape"):
				get_collision_shape().disabled = false
			is_physics_suspended = false
			velocity = Vector3.ZERO
			_update_animations(delta)
			return
		
		# ─── VELOCITY-BASED GHOST MOVEMENT (Physics-Resolved) ────────
		# Convert the old manual global_position lerp to a calculated velocity
		# vector applied via the motor and move_and_slide(). This allows Godot's
		# physics engine to resolve collision against doorframes — the Entity
		# pushes through the doorway naturally rather than phasing through
		# geometry, which prevented the engine from resolving the collision
		# and caused the "jitter into floor/wall" bug.
		#
		# Unlike the old ghost mode (which disabled collision entirely),
		# we now keep FULL collision enabled so the physics engine can
		# react to doorframe interference. The failsafe timeout (5s) still
		# force-teleports if the Entity is truly stuck.
		var ghost_dir = (_ghost_target - global_position).normalized()
		ghost_dir.y = 0.0  # Stay on ground plane
		var ghost_speed = current_stalk_speed * 1.0  # Normal walk speed
		velocity = ghost_dir * ghost_speed
		# Re-enable collision so the physics engine resolves doorframe contacts
		set_collision_mask_value(1, true)
		if has_method("get_collision_shape"):
			get_collision_shape().disabled = false
		is_physics_suspended = false
		move_and_slide()
		
		# ─── ARRIVAL CHECK ────────────────────────────────────────────────
		var ghost_dist = global_position.distance_to(_ghost_target)
		if ghost_dist <= 0.02:
			print("[Entity] APPROACH_WINDOW Phase 2 GHOST MOTOR: Arrived at IndoorBreachWaypoint (dist=%.2f). Signaling completion." % ghost_dist)
			_ghost_door_phase_2 = false
			_ghost_mode = false
			is_breach_locked = false
			was_door_entry = true
			is_approach_finished = true
			state_locked = false
			_door_phase = 0
			_door_phase_2_timer = 0.0
			# Notify AI that the Entity has physically arrived indoors
			if _ai and _ai.has_method("set_has_arrived_indoor"):
				_ai.set_has_arrived_indoor(true)
			# Prime the indoor search persistence timer NOW (before the Director
			# evaluates on the next frame). Without this, the persistence timer
			# is 0.0 when the Director runs, causing it to fall through to
			# OBSERVE_FROM_TREELINE and re-enter APPROACH_WINDOW.
			if _ai and _ai.has_method("reset_indoor_search_persistence"):
				_ai.reset_indoor_search_persistence()
			# Record door breach timestamp for Director's Tier 8 persistence check
			last_door_breach_time = Time.get_ticks_msec() / 1000.0
			# Restore physics
			set_collision_mask_value(1, true)
			if has_method("get_collision_shape"):
				get_collision_shape().disabled = false
			is_physics_suspended = false
			velocity = Vector3.ZERO
		
		# Play Stalk animation during ghost movement
		if _anim_state_machine:
			_anim_state_machine.travel("Stalk")
		
		_update_animations(delta)
		return
	
	# --- TRANSITION LOCK: RETREAT / STANDOFF / STUNNED ---
	# During RETREAT, the AI computes the escape velocity (pathfinding to the
	# breach window or treeline). We MUST call move_and_slide() to physically
	# apply this velocity — without it, the Entity freezes in place and the
	# stuck detector fires after 1.5 seconds, creating an infinite relocation
	# loop.
	# STANDOFF also locks movement — the Entity freezes in place while stared at.
	# STUNNED is handled by the AI's _stunned_state() which locks the motor
	# and decrements the stun timer. The controller applies the frozen velocity
	# via move_and_slide() below.
	# FLINCH is handled by the AI's _flinch_state() which computes the lateral
	# sprint velocity. The controller applies it via move_and_slide() below.
	# NOTE: RELOCATE is NOT included here — it is a safe initialization state only
	# and is never used during active runtime transitions.
	if _state == EntityAI.State.RETREAT or _state == EntityAI.State.STANDOFF or _state == EntityAI.State.STUNNED:
		velocity = Vector3.ZERO
		if _ai and _ai.has_method("process_state_logic"):
			_ai.process_state_logic(delta)
			velocity = _ai.get_calculated_velocity()
		move_and_slide()
		_update_animations(delta)
		return

	
	# ─── AI STATE LOGIC (runs regardless of physics suspension) ──────────
	# The AI state machine must continue running even when physics is
	# suspended (Door Phase A Ghost Climb). The _indoor_search_state()
	# manually lerps the Entity's global_position and does not need
	# move_and_slide() — but it still needs to be called every frame to
	# progress the lerp toward the END waypoint.
	if _ai and _ai.has_method("process_state_logic"):
		_ai.process_state_logic(delta)
		if not is_physics_suspended:
			set_motor_velocity(_ai.get_calculated_velocity())
	else:
		velocity = Vector3.ZERO
	
	# ─── PHYSICS SUSPENSION GUARD ─────────────────────────────────────────
	# When is_physics_suspended is true (Door Phase A Ghost Climb),
	# the core physics calculations (gravity, ground snapping, and
	# move_and_slide()) are bypassed. The AI's _indoor_search_state()
	# manually lerps the Entity's global_position instead.
	#
	# State updates, sensory pulses, and animation updates still run — only
	# the physical movement calculations are bypassed.
	if not is_physics_suspended:
		# --- STANDARD ACTIVE NAVIGATION ---
		# NOTE: Native CharacterBody3D gravity is REMOVED. The Entity uses a
		# SphereShape3D with Floating motion mode. Y-axis elevation is handled
		# entirely by the Floor RayCast ground-snapping system below, which
		# prevents the Entity from snagging on stairs, rocks, or door thresholds.
		# Ghost Mode is also REMOVED — the Breach Protocol uses standard NavMesh
		# pathfinding with 2D-flattened velocity, and the Floating Sphere handles
		# Y-axis elevation automatically.

		move_and_slide()
		
		# ─── GROUND CONTACT (move_and_slide handles this) ─────────────
		# CharacterBody3D's move_and_slide() natively resolves ground contact
		# — no manual Y override is needed or safe. The old "Floating Sphere
		# Ground Snapping" system used lerp() to forcibly hover the Entity
		# 0.3m above the floor every frame, which fought against the physics
		# engine: move_and_slide() pushed the Entity down → ground snapping
		# pushed it back up → repeat every frame, creating a perpetual ~1.7cm
		# Y oscillation visible as the Entity "shaking" at all times.
		#
		# The monster model's visual offset (_monster_model.position.y = -0.95
		# in _update_animations()) handles the "hover" look independently.
		# No Y-position overrides on the physics body are required.
		#
		# DISABLE GUARD: When _floor_snap_disabled is true (Door Phase 2),
		# skip the gravity fallback. During indoor search ghosting, skip too.
		var is_ghosting = false
		if _state == EntityAI.State.INDOOR_SEARCH and _ai and _ai.has_method("has_arrived_indoor"):
			is_ghosting = not _ai.has_arrived_indoor()
		
		if not is_ghosting and not _floor_snap_disabled:
			if not _floor_ray.is_colliding():
				# Fallback gravity: only applies when the raycast misses
				# entirely (Entity airborne or above a NavMesh gap).
				velocity += get_gravity() * delta
			else:
				# ─── HOVER & FREEZE FIX ────────────────────────────────────
				# The floor ray HITS the floor below, but the Entity may still be
				# hovering well above it (e.g. after a window-breach teleport to
				# the NavMesh Y, which can be baked ~1.5m above the physical
				# cabin floor). This body has NO CollisionShape3D (see the
				# "Node not found: CollisionShape3D" error at _ready), so
				# move_and_slide() cannot resolve floor contact and the branch
				# above only applies gravity when the ray MISSES. A hovering
				# Entity (ray hitting) therefore never falls and floats frozen.
				#
				# Fix: if the Entity's feet are well above the floor surface the
				# ray hit, snap it straight down onto the floor. The threshold
				# accounts for the resting height (~0.5m, matching the player) so
				# a grounded Entity is not re-snapped. This is a one-shot snap,
				# not a per-frame lerp, so it does not cause the Y oscillation the
				# old Floating-Sphere system produced.
				var floor_y = _floor_ray.get_collision_point().y
				if global_position.y > floor_y + 0.6:
					global_position.y = floor_y + 0.5
					velocity.y = 0.0
		
		var flat_vel = Vector2(velocity.x, velocity.z)
		if flat_vel.length_squared() > 0.05 and _monster_model:
			var target_angle = atan2(flat_vel.x, flat_vel.y)
			_monster_model.rotation.y = lerp_angle(_monster_model.rotation.y, target_angle, delta * 10.0)
		
		# ─── ENTITY FOOTSTEP AUDIO ──────────────────────────────────────
		# Plays surface-appropriate footstep sounds while the Entity is moving.
		# Uses get_real_velocity() instead of velocity (post-move_and_slide remaining)
		# to get the actual movement speed. Uses _floor_ray.is_colliding() instead of
		# is_on_floor() because the Floating Sphere ground snapping system adjusts Y
		# after move_and_slide(), so the physics engine may not register floor contact.
		# During CHARGE state, footsteps play at 2x speed (footstep_interval_charge).
		var real_horz_vel := Vector2(get_real_velocity().x, get_real_velocity().z).length()
		if _floor_ray.is_colliding() and real_horz_vel > 0.5:
			var interval = footstep_interval_charge if _state == EntityAI.State.CHARGE else footstep_interval_normal
			_entity_step_timer -= delta
			if _entity_step_timer <= 0.0:
				_play_entity_footstep()
				_entity_step_timer = interval
		else:
			_entity_step_timer = 0.0
	
	# ─── Y-AXIS DEBUG: Floor clipping diagnostic ──────────────────
	_y_debug_frame_counter += 1
	if _y_debug_frame_counter >= 60 and is_physically_inside():
		_y_debug_frame_counter = 0
		var ray_hit = _floor_ray.is_colliding()
		var hit_name = _floor_ray.get_collider().name if ray_hit else "None"
		var hit_y = _floor_ray.get_collision_point().y if ray_hit else -999.0
		var ray_mask = _floor_ray.collision_mask
		var landing_y = _indoor_landing_position.y
		print("[Y-AXIS DEBUG] Inside Cabin | Entity Y: ", global_position.y,
		      " | RayCast hit: ", hit_name,
		      " | hit_y: ", hit_y,
		      " | Ray mask: ", ray_mask,
		      " | Landing Y: ", landing_y,
		      " | Velocity.y: ", velocity.y,
		      " | Physics suspended: ", is_physics_suspended)
	
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
	
	print("[F2] Entity state override: ", STATE_KEYS[original_state], " → WINDOW_PEEK")
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

## Returns the state persistence timer value.
## Used by the Director's State Persistence Guard to check if the Entity
## is mid-execution in an active state (FLINCH, CHARGE, etc.).
## When > 0.0, the Director skips Tier 3–8 evaluations.
func get_state_timer() -> float:
	return _state_timer

## Sets the state persistence timer value.
## Called by state handlers on entry to set the duration of the state.
func set_state_timer(value: float) -> void:
	_state_timer = value

## Sets the current FSM state.
## NOTE: This should ONLY be called by the Master Director (entity_director.gd).
## All other code MUST use request_state() instead.
func set_state(new_state: EntityAI.State) -> void:
	# ─── STATE TRANSITION DEBUG LOG ──────────────────────────────────
	# Logs every state transition with the previous state, new state,
	# and the trigger context (what Blackboard conditions caused it).
	# This helps debug unexpected state changes during gameplay.
	if _state != new_state:
		var old_name = STATE_KEYS[_state] if _state >= 0 and _state < STATE_KEYS.size() else "UNKNOWN"
		var new_name = STATE_KEYS[new_state] if new_state >= 0 and new_state < STATE_KEYS.size() else "UNKNOWN"
		
		# Build a trigger context string from Blackboard conditions
		var triggers: Array[String] = []
		if is_illuminated:
			triggers.append("illuminated=%.2f" % player_stare_timer)
		if state_locked:
			triggers.append("state_locked")
		if is_indoor_retreat:
			triggers.append("indoor_retreat")
		if is_approach_finished:
			triggers.append("approach_finished")
		if is_window_unbarricaded:
			triggers.append("window_unbarricaded")
		if is_flinch_finished:
			triggers.append("flinch_finished")
		if is_retreat_arrived:
			triggers.append("retreat_arrived")
		if is_observe_finished:
			triggers.append("observe_finished")
		if is_fuse_sabotaged:
			triggers.append("fuse_sabotaged")
		if _navigation:
			triggers.append("player_inside=%s" % _navigation.is_player_inside())
		
		var trigger_str = ", ".join(triggers) if triggers else "director_evaluation"
		print("[STATE TRANSITION] %s → %s | trigger: %s" % [old_name, new_name, trigger_str])
	
	_state = new_state

## Requests a state change via the _pending_state override mechanism.
## This is the ONLY method external code should use to request a state change.
## The Master Director reads _pending_state at the start of evaluate_master_state()
## and applies it immediately, then clears it to -1.
##
## This prevents the "Two Masters" problem by funneling ALL state changes
## through the Director's single evaluation point.
##
## DORMANT DEADLOCK BREAKER:
## When the Entity is in DORMANT state, the AI's process_state_logic() returns
## early without calling the Director's evaluate_master_state(). This means
## _pending_state (e.g., STALK from escape_van.gd) sits unread forever — the
## Director never fires, and the Entity is stuck in DORMANT forever despite
## _is_active = true.
##
## To break this deadlock, if the current state is DORMANT, we force the
## transition directly via set_state() and clear _pending_state. This is safe
## because DORMANT has no active state handler, no state_locked flag, and no
## animation playing — there is nothing to interrupt.
func request_state(new_state: EntityAI.State) -> void:
	if _state == EntityAI.State.DORMANT:
		set_state(new_state)
		_pending_state = -1
	else:
		_pending_state = new_state

## Returns the pending state override value, or -1 if no override is pending.
## Called by the Master Director (entity_director.gd) at the start of
## evaluate_master_state() to check for external state change requests.
func get_pending_state() -> int:
	return _pending_state

## Clears the pending state override back to -1.
## Called by the Master Director after consuming the pending state value.
func clear_pending_state() -> void:
	_pending_state = -1

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

## Returns the CollisionShape3D node for the Entity's physics body.
## Used by the Door Phase A ghost motor to disable/re-enable the collision
## shape during the ghost climb phase, preventing the Entity from
## colliding with doorway geometry while lerping between waypoints.
func get_collision_shape() -> CollisionShape3D:
	return _collision_shape

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

## Returns the cached FuseBox waypoint Marker3D (EntityFuseWaypoint).
## Uses the @export fuse_waypoint reference (set in Inspector or resolved
## once in _initialize_entity()). This replaces the expensive per-frame
## child iteration that was called every frame during SABOTAGE_FUSE.
func get_fuse_waypoint() -> Marker3D:
	return fuse_waypoint

## Returns the cached Door's exterior waypoint Marker3D (EntityDoorWaypoint).
## Uses the @export door_waypoint_marker reference (set in Inspector or
## resolved once in _initialize_entity()). This replaces the expensive
## per-frame duck-typing checks that were called every frame during
## APPROACH_WINDOW to determine if the target is a door.
func get_door_waypoint_marker() -> Node3D:
	return door_waypoint_marker

## Returns the FuseBox node for the FUSE_SABOTAGE state.
## Uses the cached @export fuse_box_node reference (set in Inspector or
## resolved once in _initialize_entity()). Falls back to the expensive
## scene tree traversal only if the cached reference is null.
func get_fuse_box_node():
	if fuse_box_node:
		return fuse_box_node
	
	# Fallback: expensive scene tree traversal (should rarely happen)
	print("[Entity] WARNING: get_fuse_box_node() called but fuse_box_node is null! Performing fallback search.")
	if get_tree().current_scene:
		var candidates = []
		_find_fuse_box_recursive(get_tree().current_scene, candidates)
		if not candidates.is_empty():
			return candidates[0]
	
	var waypoints = get_tree().get_nodes_in_group("EntityWaypoints")
	for wp in waypoints:
		if wp.name == "FuseBoxWaypoint":
			var parent = wp.get_parent()
			if parent and parent is FuseBox:
				return parent
			for child in wp.get_children():
				if child is Marker3D:
					return child
	
	var interactables = get_tree().get_nodes_in_group("interactable")
	for node in interactables:
		if node is FuseBox:
			return node
	
	return null


## Returns the Door node for the APPROACH_WINDOW / INDOOR_SEARCH states.
## Uses the cached @export door_node reference (set in Inspector or
## resolved once in _initialize_entity()). Falls back to the expensive
## group lookup only if the cached reference is null.
func get_door_node():
	if door_node:
		return door_node
	
	# Fallback: expensive group lookup (should rarely happen)
	print("[Entity] WARNING: get_door_node() called but door_node is null! Performing fallback search.")
	return get_tree().get_first_node_in_group("Door")


## Returns the DoorBreachWaypoint Marker3D child of the Door node.
## Uses the cached @export door_breach_waypoint reference (set in Inspector or
## resolved once in _initialize_entity()). Falls back to searching the Door's
## children only if the cached reference is null.
## This replaces expensive child-node searches that were called every frame
## during APPROACH_WINDOW / INDOOR_SEARCH.
## Returns null if no waypoint is found.
func get_door_breach_waypoint() -> Node3D:
	if door_breach_waypoint:
		return door_breach_waypoint
	
	# Fallback: search through the Door node's children (should rarely happen)
	print("[Entity] WARNING: get_door_breach_waypoint() called but door_breach_waypoint is null! Performing fallback search.")
	var door = get_door_node()
	if not door:
		return null
	
	# Look for a Marker3D child named "DoorBreachWaypoint" directly on the door
	for child in door.get_children():
		if child is Marker3D and child.name == "DoorBreachWaypoint":
			return child
	
	# Fallback: search recursively through children
	for child in door.get_children():
		for grandchild in child.get_children():
			if grandchild is Marker3D and grandchild.name == "DoorBreachWaypoint":
				return grandchild
	
	return null


## Recursively searches the scene tree for a node that is a FuseBox.
func _find_fuse_box_recursive(node: Node, results: Array) -> void:
	if node is FuseBox:
		results.append(node)
		return
	for child in node.get_children():
		_find_fuse_box_recursive(child, results)


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

## Returns the fuse sabotage timer.
func get_fuse_sabotage_timer() -> float:
	return _fuse_sabotage_timer

## Sets the fuse sabotage timer.
func set_fuse_sabotage_timer(value: float) -> void:
	_fuse_sabotage_timer = value

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

## Returns the exact position of the last noise the Entity heard.
## Used by entity_ai.gd's _indoor_search_state() to pathfind toward the exact
## noise coordinate instead of the room center.
func get_last_heard_exact_position() -> Vector3:
	return _last_heard_exact_position


## Returns true if the Entity is physically inside the cabin's interior volume.
## Uses RoomLightDetector.get_room_name_at() to resolve the Entity's position
## to a room name. Returns true if the room is "HallRoom", "LivingRoom", or
## "ComputerRoom" (the VALID_INDOOR_ROOMS in entity_ai.gd).
##
## This is the Director's single source of truth for location-awareness.
## Unlike the Entity's belief system (thinks_player_is_inside), this is a
## physical fact based on the Entity's actual global_position.
func is_physically_inside() -> bool:
	# ─── BUG FIX (INDOOR_SEARCH -> APPROACH_WINDOW): Height-independent ──
	# RoomLightDetector.get_room_name_at() uses room.contains_point(), which
	# checks a 3D volume. If the Entity is hovering above the cabin floor
	# (e.g. mid-breach or the NavMesh-Y landing bug), the room volume may not
	# extend to that height, so get_room_name_at() returns "Outside" and the
	# Director's Tier 8 guard falls through to OBSERVE_FROM_TREELINE ->
	# APPROACH_WINDOW while the Entity is still physically inside. Fix: sample
	# the room at the floor beneath the Entity (via the floor ray) instead of
	# the Entity's own Y, so the check is robust to vertical offset.
	var check_pos = global_position
	if _floor_ray and _floor_ray.is_colliding():
		check_pos.y = _floor_ray.get_collision_point().y + 0.5
	var room_name = RoomLightDetector.get_room_name_at(check_pos)
	return room_name in ["HallRoom", "LivingRoom", "ComputerRoom"]


## ─── BELIEF SYSTEM ACCESSORS ──────────────────────────────────────────────────
## These accessors provide read/write access to the Entity's belief about the
## player's location. The Director reads thinks_player_is_inside to determine
## whether the player is inside or outside. The sensory and AI modules write
## to these based on sight, sound, and deductive reasoning.

## Returns whether the Entity BELIEVES the player is still inside the cabin.
## Defaults to true. Set to false when the Entity deduces the player escaped.
func get_thinks_player_is_inside() -> bool:
	return thinks_player_is_inside

## Sets whether the Entity believes the player is inside the cabin.
## Called by entity_sensory.gd (sight/sound) and entity_ai.gd (3-waypoint miss rule).
func set_thinks_player_is_inside(value: bool) -> void:
	thinks_player_is_inside = value

## Returns whether a new relocate target has been set.
func get_relocate_target_set() -> bool:
	return _relocate_target_set

## Sets whether a new relocate target has been set.
func set_relocate_target_set(value: bool) -> void:
	_relocate_target_set = value

## Returns the number of consecutive vantage point observations that yielded
## no sighting of the player. When >= 3, the Entity deduces the player escaped.
func get_consecutive_vantage_misses() -> int:
	return _consecutive_vantage_misses

## Sets the consecutive vantage misses counter.
func set_consecutive_vantage_misses(value: int) -> void:
	_consecutive_vantage_misses = value

## Increments the consecutive vantage misses counter by 1.
## Called by entity_ai.gd's _observe_from_treeline_state() each time the Entity
## finishes observing at a vantage point without spotting the player.
func increment_consecutive_vantage_misses() -> void:
	_consecutive_vantage_misses += 1

## Resets the consecutive vantage misses counter to 0.
## Called by entity_sensory.gd when the Entity hears or sees the player indoors.
func reset_consecutive_vantage_misses() -> void:
	_consecutive_vantage_misses = 0


## ─── FLINCH BLACKLIST ACCESSORS ──────────────────────────────────────────────
## Returns the array of window IDs the Entity was repelled from via FLINCH.
func get_flinch_blacklisted_windows() -> Array[String]:
	return _flinch_blacklisted_windows

## Appends a window ID to the flinch blacklist. Called by the Director when
## transitioning to FLINCH from APPROACH_WINDOW or WINDOW_PEEK. Prevents the
## Entity from re-selecting this window on the next approach cycle.
func add_flinch_blacklisted_window(window_id: String) -> void:
	if not window_id.is_empty() and not _flinch_blacklisted_windows.has(window_id):
		_flinch_blacklisted_windows.append(window_id)
		print("[FLINCH BLACKLIST] Added window '%s' to flinch blacklist. Total: %d" % [window_id, _flinch_blacklisted_windows.size()])

## Clears the entire flinch blacklist. Called when:
##   1. The Entity completes an OBSERVE relocation cycle (fade_and_relocate).
##   2. The Entity enters DORMANT state.
##   3. The Entity successfully breaches a DIFFERENT window.
func clear_flinch_blacklist() -> void:
	if not _flinch_blacklisted_windows.is_empty():
		print("[FLINCH BLACKLIST] Cleared %d blacklisted windows." % _flinch_blacklisted_windows.size())
		_flinch_blacklisted_windows.clear()


# ─── ACOUSTIC DETECTION ──────────────────────────────────────────────────────
## Called by player_controller.gd's make_noise() when the player emits a sound.
##
## The player emits noise with a radius based on movement state:
##   - Sprinting: 20m radius (loud footsteps, heavy breathing)
##   - Walking:   10m radius (periodic footstep sounds)
##   - Crouching: 0m (silent movement)
##   - Jumping:   15m radius (landing thud)
##
## If the Entity is within the noise radius, it instantly updates its
## last_known_position to the noise source and enters hunting mode.
## This is the Entity's "hearing" — it does NOT need line-of-sight to
## detect the player through sound.
func hear_noise(noise_position: Vector3, radius: float, intensity: float = 1.0) -> void:
	# Calculate distance from Entity to the noise source
	var dist = global_position.distance_to(noise_position)
	
	# If the Entity is within the noise radius, it hears the player
	if dist <= radius:
		# Update memory with the noise source position
		_last_known_position = noise_position
		_last_heard_exact_position = noise_position
		_is_hunting = true
		_current_interest_level = 100.0
		
		# ─── INDOOR ROOM-LEVEL TRACKING ──────────────────────────────
		# When inside the cabin, resolve the noise position to a room name.
		# This gives the Entity room-level awareness without exact position.
		if _state == EntityAI.State.INDOOR_SEARCH:
			if _room_light_detector and _room_light_detector.has_method("get_room_name_at"):
				last_known_room_name = _room_light_detector.get_room_name_at(noise_position)
				print("[Entity Hears] Indoor noise tracked to room: %s" % last_known_room_name)
		
		# ─── INDOOR/OUTDOOR NOISE DETECTION ──────────────────────────
		# Use RoomLightDetector to determine if the noise source is inside
		# or outside the cabin. This is the Entity's ONLY way to deduce
		# the player has escaped via acoustic intelligence.
		#
		# INDOOR NOISE: The player is still inside the cabin. Reset the
		#   miss counter so the 3-waypoint miss rule doesn't falsely
		#   deduce an escape. The Entity has fresh evidence the player
		#   is still indoors.
		#
		# OUTDOOR NOISE: The player has escaped! The Entity hears the
		#   player outside the cabin (e.g., snapping twigs in the yard).
		#   Immediately update the belief system — the Entity now KNOWS
		#   the player is outside. This is the ONLY way the Entity can
		#   conclude the player escaped via hearing alone.
		if _room_light_detector and _room_light_detector.has_method("get_room_name_at"):
			var room_name = _room_light_detector.get_room_name_at(noise_position)
			if room_name != "Outside":
				# ─── INDOOR NOISE: Player is still inside! ──────────────
				# The Entity hears the player inside the cabin. This is
				# definitive acoustic evidence that the player is indoors.
				# Update the belief system immediately so the Director
				# knows the player is inside and does NOT transition to
				# STALK (outdoor pursuit).
				_consecutive_vantage_misses = 0
				thinks_player_is_inside = true
			else:
				# ─── OUTDOOR NOISE: Player has escaped! ──────────────
				# The Entity hears the player outside the cabin. This is
				# definitive acoustic evidence that the player is no longer
				# inside. Update the belief system immediately so the
				# Director can transition to STALK (outdoor pursuit).
				thinks_player_is_inside = false
		
		


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

## ─── MOTOR LOCK API ──────────────────────────────────────────────────────────
## These methods control the motor lock system. When the motor is locked,
## set_motor_velocity() will NOT apply velocity changes, effectively freezing
## the Entity in place. Used by the STUNNED state.

## Sets the Entity's velocity. If the motor is locked (STUNNED state), this
## call is silently ignored — the Entity remains frozen in place.
## Called by entity_ai.gd's process_state_logic() to apply computed velocities.
func set_motor_velocity(vel: Vector3) -> void:
	if _is_motor_locked:
		return
	velocity = vel

## Locks the motor, preventing set_motor_velocity() from applying any velocity
## changes. Called by the STUNNED state handler to freeze the Entity in place.
func lock_motor_for_stun() -> void:
	_is_motor_locked = true
	velocity = Vector3.ZERO

## Unlocks the motor, allowing set_motor_velocity() to apply velocity changes
## again. Called when the stun expires or the Entity is released by a blackout.
func unlock_motor() -> void:
	_is_motor_locked = false


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
	
	# Kill any existing tweens on the monster model to prevent conflicts.
	# In Godot 4, we use the SceneTreeTween approach: create a new tween
	# which automatically handles cleanup of previous tweens on the same node.
	# Tween.kill_tweens_on() is not a valid static method in Godot 4.
	
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
			# Restore visibility after the fade completes so the model
			# reappears when the Entity transitions out of FLINCH state.
			# Without this, the model stays invisible forever after a
			# FLINCH that follows an indoor RETREAT.
			fade_tween.tween_callback(_restore_model_visibility)
	else:
		# Fallback: hide the model directly since modulate is not available.
		# Schedule a delayed restoration so the model reappears after the
		# flinch duration (1.5s) completes.
		_monster_model.visible = false
		var restore_tween = tree.create_tween()
		if restore_tween:
			restore_tween.tween_interval(1.5)
			restore_tween.tween_callback(_restore_model_visibility)


## Restores the monster model's visibility after a flinch fade-out.
## Called by _start_flinch_fade() via tween callback to ensure the model
## reappears after the flinch completes. Without this, the model stays
## invisible forever if the modulate fallback hid it.
func _restore_model_visibility() -> void:
	if not _monster_model:
		return
	# Only restore visibility if the Entity is still active (not deactivated).
	# If the Entity was deactivated during the flinch, the deactivate() call
	# already handles visibility.
	if _is_active:
		_monster_model.visible = true
		# Also reset modulate alpha in case the tween left it at 0.0
		if "modulate" in _monster_model:
			_monster_model.modulate.a = 1.0


## Initiates the FLINCH state — a lateral sprint to evade the player's flashlight.
##
## BEHAVIOR 1 (Cowardly Outside Flinch):
## Called when the player is INSIDE the cabin and shines the flashlight at the
## Entity while it is OUTSIDE. The Entity does NOT fade/teleport — it sprints
## laterally (perpendicular to the player's camera view) at 1.5x speed for
## 3.0-5.0 seconds (randomized), then transitions to RELOCATE to pick a new
## vantage point.
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
	# Randomized flinch duration: 3.0-5.0 seconds for all flinch scenarios
	# (both outdoor window defense and indoor retreat escapes).
	_flinched_timer = randf_range(3.0, 5.0)
	# NOTE: State transition is handled by the Master Director (entity_director.gd).
	# The Director evaluates is_illuminated + is_player_inside and returns FLINCH.
	# This function ONLY sets up the flinch target position and timer.


func _on_caught_player() -> void:
	# ─── CAN KILL GUARD ──────────────────────────────────────────────────
	# When can_kill is false (toggled via Debug Console), the Entity will
	# CHARGE the player but NOT capture/kill them. Instead, it stops short
	# and transitions back to CHASE/OBSERVE. This is useful for testing
	# chase behavior without triggering death scenes.
	if not can_kill:
		request_state(EntityAI.State.STALK)
		return
	
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
	if body == _player and _state == EntityAI.State.STALK:
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
		
		# ─── VELOCITY FREEZE GUARD ──────────────────────────────────────
		# Only zero velocity if the Entity is in a state that should freeze
		# when illuminated (STANDOFF, OBSERVE_FROM_TREELINE, PATROL).
		# Do NOT zero velocity during RETREAT — the Entity needs to sprint
		# away from the flashlight. The Director handles the state transition
		# to RETREAT, and the RETREAT handler computes the escape velocity.
		# Zeroing velocity here would override the escape velocity every frame,
		# causing the Entity to freeze mid-retreat.
		if _state != EntityAI.State.RETREAT:
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
	
	# ─── GHOST MODE SAFETY GUARD ──────────────────────────────────────────
	# Prevent fade_and_relocate() from being called while ghost mode is active.
	# During Door Phase A, the Entity is intentionally phasing through geometry
	# and should NOT be relocated. Without this guard, the stuck detector or
	# Director could trigger a relocation while the Entity is mid-entry,
	# breaking the AI loop and teleporting the Entity back outside.
	if _ghost_mode:
		print("[Entity] fade_and_relocate() BLOCKED — ghost mode is active. Entity is mid-entry.")
		return
	
	print("[Entity] fade_and_relocate() called! Current state: ", STATE_KEYS[_state])
	_is_fading = true

	
	# Pick a new vantage point via the navigation system.
	# This sets _nav_agent.target_position to the new coordinate.
	_navigation.pick_next_vantage_point()
	
	# ─── RELOCATE TARGET SET ────────────────────────────────────────────
	# Mark that a new relocate target has been set. This flag is consumed
	# by the _observe_from_treeline_state() timer expiration block, which
	# resets it to false so the Entity knows to pick a NEW tree on the
	# next cycle (rather than looping at the current one).
	# This prevents the "paralysis at first tree" bug.
	_relocate_target_set = true
	
	# ─── NAV TARGET JITTER ──────────────────────────────────────────────
	# Add a small random offset (±1.0m) to the nav target so the Entity
	# doesn't arrive at the exact same spot every time. This creates more
	# organic-looking movement and prevents the Entity from converging on
	# a single pixel-perfect coordinate, which can cause micro-stuttering
	# as the NavigationAgent3D tries to reach an exact point.
	var jitter_offset = Vector3(
		randf_range(-1.0, 1.0),
		0.0,
		randf_range(-1.0, 1.0)
	)
	_nav_agent.target_position += jitter_offset
	
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
	request_state(EntityAI.State.STALK)
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


## ─── GHOST MODE ──────────────────────────────────────────────────────────────
## Toggles "Ghost Mode" on/off. When enabled, the Entity disables ALL physics
## interactions (collision layers and masks) so it can pass through geometry
## without snagging. Used during the Door Phase A cinematic interpolation to
## prevent the Entity from getting stuck on the doorframe, porch stairs, or
## threshold colliders.
##
## Ghost mode also disables gravity by zeroing out the Y velocity each frame
## in _physics_process(). The caller MUST call set_ghost_mode(false) when the
## interpolation completes, otherwise the Entity will fall through the floor.
func set_ghost_mode(enabled: bool) -> void:
	_ghost_mode = enabled
	if enabled:
		# Save the current collision layer and mask so we can restore them later
		_saved_collision_layer = collision_layer
		_saved_collision_mask = collision_mask
		# Disable ALL collision layers and masks — the Entity phases through everything
		collision_layer = 0
		collision_mask = 0
		# Disable gravity by zeroing velocity
		velocity = Vector3.ZERO
		# Capture the AI's landing position ONCE so the Ghost Motor moves
		# consistently toward the IndoorBreachWaypoint without the AI
		# overwriting it each frame. This prevents the "Entity gets stuck
		# mid-door" bug where the Ghost Motor and AI's Door Phase A fought
		# over the target position every frame.
		if _ai and "_landing_position" in _ai:
			_ghost_target = _ai._landing_position
			print("[Entity] Ghost Motor: Captured target position (%.2f, %.2f, %.2f)" % [_ghost_target.x, _ghost_target.y, _ghost_target.z])
		else:
			_ghost_target = Vector3.ZERO
		print("[Entity] GHOST MODE ENABLED — Collision disabled. Entity will phase through geometry.")
	else:
		# Restore the saved collision mask
		collision_mask = _saved_collision_mask
		# Restore the collision layer to the dedicated entity layer
		collision_layer = _saved_collision_layer
		velocity = Vector3.ZERO
		print("[Entity] GHOST MODE DISABLED — Collision restored.")


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
		EntityAI.State.OBSERVE_FROM_TREELINE, EntityAI.State.SEARCH:
			# "Creeping Ghost" mode: Disable tree/rock collision layers.
			# The Entity phases through foliage while stalking outside.
			# Only cabin geometry (layer 1) and player (layer 2) remain active.
			# This prevents the Entity from getting stuck on trees while
			# physically pathfinding between vantage points.
			# SEARCH uses the same collision mode as OBSERVE_FROM_TREELINE
			# since both are outdoor wandering states.
			collision_mask = 0
			collision_mask |= (1 << (COLLISION_LAYER_CABIN - 1))  # Layer 1: Cabin
			collision_mask |= (1 << (COLLISION_LAYER_PLAYER - 1)) # Layer 2: Player
			# NOTE: Layers 3 (Tree) and 4 (Rock) are intentionally excluded.
			
		EntityAI.State.STALK, EntityAI.State.CHARGE, EntityAI.State.APPROACH_WINDOW, EntityAI.State.WINDOW_PEEK, EntityAI.State.INDOOR_SEARCH, EntityAI.State.FLINCH, EntityAI.State.ATTACK_LAMP, EntityAI.State.RETREAT:
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


## Plays a surface-appropriate footstep sound based on the Entity's current room.
## Uses RoomLightDetector to determine if the Entity is inside (wood footsteps)
## or outside (grass footsteps). The pitch range is lowered (0.7–0.95) compared
## to the player's (0.85–1.15) to make the Entity's footsteps sound heavier.
func _play_entity_footstep() -> void:
	if not _footstep_audio:
		return
	
	var room := RoomLightDetector.get_room_name_at(global_position)
	var array: Array[AudioStream]
	
	if room == "Outside":
		array = grass_footsteps
	else:
		array = wood_footsteps
	
	if array.size() > 0:
		_footstep_audio.stream = array.pick_random()
		_footstep_audio.pitch_scale = randf_range(footstep_pitch_min, footstep_pitch_max)
		_footstep_audio.play()


## Frame counter for throttled Y-axis debug logging.
## Incremented each frame in _physics_process(). When it reaches 60,
## the [Y-AXIS DEBUG] print fires and the counter resets to 0.
## This prevents console flooding while still providing 1 Hz logging.
var _y_debug_frame_counter: int = 0


func _update_animations(_delta: float) -> void:
	if not _anim_state_machine:
		return
	
	# Strictly enforce model grounding offset across ALL frames
	if _monster_model:
		_monster_model.position = Vector3(0.0, -0.95, 0.0)
	
	# Flinch Override (RETREAT Phase 3)
	# When the Entity is in RETREAT state AND the indoor retreat Phase 3
	# flinch is active, we MUST play the "Flinch" animation instead of "Idle".
	# This override MUST be placed BEFORE the RETREAT→Idle hard clamp below,
	# otherwise "Idle" would smother the Flinch animation, causing the Entity
	# to get permanently stuck in the RETREAT state (the Phase 3 timer would
	# expire but the animation blending conflict would prevent the state from
	# completing).
	if _state == EntityAI.State.RETREAT and _ai and _ai.get("_retreat_indoor_phase_3") == true:
		_anim_state_machine.travel("Flinch")
		return
	
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
		if _ai and _ai.is_barricade_anim_locked():
			_anim_state_machine.travel("AttackWindow")
			return
	
	# EnterWindow: Vault or Door entry animation (INDOOR_SEARCH Phase A)
	if _state == EntityAI.State.INDOOR_SEARCH:
		if _ai and _ai.get("_has_arrived_indoor") == false:
			# Door entry: play the Stalk (walking) animation instead of vaulting
			if was_door_entry:
				_anim_state_machine.travel("Stalk")
			else:
				_anim_state_machine.travel("EnterWindow")
			return
	
	# ─── STANDARD LOCOMOTION BLENDING ────────────────────────────────
	# Base animation selection on horizontal velocity and a posture flag.
	# This replaces the bloated match statement that redundantly mapped
	# each state to the same walk/crawl/idle animations.
	
	# Vertical movement (ClimbUp / ClimbDown) takes priority over horizontal
	# GUARD: Only play ClimbUp/ClimbDown if the Entity is actually in a climbing
	# state. The Floating Sphere Ground Snapping system uses lerp() to hover the
	# Entity above terrain, which can create upward velocity (real_vel.y > 0.8)
	# when moving over slopes or uneven ground. Without this guard, the Entity
	# would play the ClimbUp animation every time it drifts upward over a hill.
	# Determine posture based on state
	var crawling_states: Array = [
		EntityAI.State.CHARGE,
		EntityAI.State.FLINCH,
	]
	var is_crawling: bool = _state in crawling_states
	# INDOOR_SEARCH uses running_crawl only after Phase A (vault/door entry) completes
	if not is_crawling and _state == EntityAI.State.INDOOR_SEARCH:
		is_crawling = _ai and _ai.get("_has_arrived_indoor") == true
	
	if horz_speed > 0.2:
		_anim_state_machine.travel("running_crawl" if is_crawling else "Stalk")
	else:
		_anim_state_machine.travel("Idle")
