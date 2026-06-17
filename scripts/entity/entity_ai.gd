extends Node
class_name EntityAI

## Entity AI — Finite State Machine behaviors for the Entity (The Brain Hub).
## Receives a reference to the parent entity_controller to read/write shared state.
## Called from entity_controller._physics_process() each frame.
##
## ARCHITECTURE:
##   entity_controller.gd (Motor Hub) calls process_state_logic(delta) every frame,
##   then reads get_calculated_velocity() and applies it via move_and_slide().
##   All state decisions, velocity calculations, animation travel() calls, and
##   difficulty multipliers live here.
##
## NOTE: The State enum lives here. Reference as EntityAI.State.X from other scripts.
##
## ─── @EXPORT TUNING KNOBS ─────────────────────────────────────────────────────
## These exported variables replace hardcoded magic numbers throughout the AI.
## They can be tuned from the Inspector without modifying code.
## All values have sensible defaults for the current game balance.

## Duration of the EnterWindow vault animation in seconds.
## The animation is ~1.5 seconds long. The Entity must play this animation
## for its full duration before teleporting inside, ensuring the visual
## effect of vaulting through the window frame is fully visible.
@export var enter_window_anim_duration: float = 1.5

## Duration (in seconds) from the start of the AttackWindow animation to the
## moment of impact where the glass should shatter. This should match the
## animation's keyframe timing. The AttackWindow animation is ~1.5s long,
## with the impact occurring at approximately the 0.5s mark (the swing
## connects with the glass).
@export var glass_shatter_impact_delay: float = 0.5

## Minimum duration (in seconds) the Entity must spend pathfinding in
## APPROACH_WINDOW before it can signal completion. Prevents instant
## arrival when the NavigationAgent finishes prematurely.
@export var approach_min_duration: float = 2.0

## Failsafe timeout (in seconds) for APPROACH_WINDOW. If the Entity has
## been pathfinding for this long without arriving, force a completion
## signal to prevent permanent soft-locks.
@export var approach_failsafe_timeout: float = 15.0

## Debug log interval (in seconds) for APPROACH_WINDOW and WINDOW_PEEK.
## Prints Entity and window coordinates at this interval to help debug
## pathfinding issues.
@export var approach_debug_interval: float = 2.0

## Breach delay (in seconds) before the Entity starts attempting to breach
## a window after arriving at it. Gives the player a brief window to react.
@export var breach_delay: float = 10.0

## Maximum number of entries in _recently_visited_windows.
@export var max_recent_windows: int = 3

## Siege duration (in seconds) — forces the Entity to stay in WINDOW_PEEK
## for a minimum duration before it can exit via the stare timer.
@export var siege_min_duration: float = 5.0

## Barricade damage interval (in seconds) — how often the Entity strikes
## a boarded window during WINDOW_PEEK.
@export var barricade_damage_interval: float = 2.0

## Barricade animation lock duration (in seconds) — how long the AttackWindow
## animation is forced to play after each barricade hit.
@export var barricade_anim_lock_duration: float = 1.5

## Pending damage delay (in seconds) — delay from swing start to damage
## application, syncing the health subtraction with the visual impact frame.
@export var pending_damage_delay: float = 0.6

## Desperation passive timer threshold (in seconds) — how long the Entity
## must be in OBSERVE_FROM_TREELINE before the desperation modifier kicks in.
@export var desperation_threshold: float = 45.0

## Desperation confidence modifier rate (confidence per second).
@export var desperation_modifier_rate: float = 0.5

## Indoor retreat sprint multiplier — how fast the Entity sprints toward
## the breach window when caught inside by the flashlight.
@export var indoor_retreat_sprint_multiplier: float = 1.5

## Flinch sprint multiplier — how fast the Entity sprints laterally during FLINCH.
@export var flinch_sprint_multiplier: float = 1.5

## Flinch duration (in seconds) — how long the lateral sprint lasts.
## NOTE: This export is overridden at runtime by entity_controller.gd's
## _start_flinch() which uses randf_range(3.0, 5.0). This export is kept
## as a tuning reference but the actual duration is randomized 3-5 seconds
## for all flinch scenarios (both outdoor window defense and indoor retreat).
@export var flinch_duration: float = 4.0

## Flinch distance (in meters) — how far the Entity sprints laterally.
@export var flinch_distance: float = 8.0

## Charge speed multiplier — how fast the Entity charges at the player (3x default).
@export var charge_speed_multiplier: float = 3.0

## Wall climb speed multiplier — vertical ascent speed factor.
@export var wall_climb_speed_multiplier: float = 0.5

## Wall climb height (in meters) — how high the Entity climbs during CLIMB_WALL.
@export var wall_climb_height: float = 4.0

## Lamp attack interval (in seconds) — how often the Entity strikes the portable lamp.
@export var lamp_attack_interval: float = 3.0

## Lamp attack range (in meters) — how close the Entity must be to strike the lamp.
@export var lamp_attack_range: float = 3.0

## Fuse sabotage interval (in seconds) — how often the Entity strikes the Fuse Box.
@export var fuse_sabotage_interval: float = 2.0

## Fuse sabotage range (in meters) — how close the Entity must be to strike the Fuse Box.
@export var fuse_sabotage_range: float = 2.5

## Approach arrival distance (in meters) — 2D distance threshold for arriving at a window.
@export var approach_arrival_distance: float = 2.5

## Window peek stare timer range (min, max) in seconds.
@export var window_peek_stare_min: float = 8.0
@export var window_peek_stare_max: float = 15.0

## Observe wait time range (min, max) in seconds for high confidence (>= 40).
@export var observe_wait_high_min: float = 2.0
@export var observe_wait_high_max: float = 4.5

## Observe wait time range (min, max) in seconds for low confidence (< 40).
@export var observe_wait_low_min: float = 4.0
@export var observe_wait_low_max: float = 8.0

## Retreat teleport distance (in meters) outside the breach window.
@export var retreat_teleport_distance: float = 2.0

## Stare grace threshold (in seconds) — if stare timer is above this after
## anti-flap cooldown expires, extend the cooldown.
@export var stare_grace_threshold: float = 0.5

## Anti-flap cooldown duration (in seconds) — prevents immediate re-entry
## into the same state after completion.
@export var anti_flap_cooldown_duration: float = 0.5

## Confidence penalty on FLINCH completion — how much confidence is lost.
@export var flinch_confidence_penalty: float = 20.0

## Indoor retreat confidence drop — what confidence is set to when caught inside.
@export var indoor_retreat_confidence: float = 20.0

## Confidence threshold for CLIMB_WALL escalation.
@export var confidence_climb_threshold: float = 65.0

## Confidence threshold for APPROACH_WINDOW escalation.
@export var confidence_approach_threshold: float = 40.0

## Stare time threshold (in seconds) for CHARGE transition.
@export var charge_stare_threshold: float = 1.5

## Confidence boost when player breaks flashlight stare.
@export var stare_break_confidence_boost: float = 8.0

## Confidence drain rate while being stared at (per second).
@export var stare_confidence_drain: float = 2.0

## Window recency penalty for the utility scorer.
@export var window_recency_penalty: float = 30.0

## Room avoidance penalty for the utility scorer.
@export var room_avoidance_penalty: float = 500.0

enum State {
	DORMANT,
	OBSERVE_FROM_TREELINE,  # Night 1 & 2 (Passive Voyeurism) — DEFAULT BASELINE
	SEARCH,                 # Player believed outside — actively searching for them
	RETREAT,                # Indoor escape only — Entity flees through nearest broken/unboarded window
	APPROACH_WINDOW,        # Night 3+ (Moving to glass)
	WINDOW_PEEK,            # Night 2+ (Staring inside)
	STANDOFF,               # Player is staring at Entity with flashlight — frozen in place
	FLINCH,                 # Player inside, Entity outside — lateral sprint to evade flashlight
	STALK,                  # Outdoor slow pursuit — both Entity and player outside
	CHARGE,                 # Player stared too long — Entity sprints at 3x speed
	INDOOR_SEARCH,          # Entity has breached a window and is hunting inside the cabin
	CLIMB_WALL_UP,          # Entity is climbing the exterior wall UP to a second-story window
	CLIMB_WALL_DOWN,        # Entity is climbing the exterior wall DOWN from a second-story window
	STUNNED,                # Entity is paralyzed by the porch light overload trap
	ENRAGED,                # Blackout release — permanent 1.5x speed boost for rest of night
	ATTACK_LAMP,            # Entity is physically approaching and striking the portable high-voltage lamp
	HARASS,                 # Entity stands at a window performing psychological harassment (breathing, tapping, rattling)
	FUSE_SABOTAGE,          # Entity is physically approaching and striking the Fuse Box to break it
	ENTER_THROUGH_DOOR,     # Entity walks to the front door, opens it, and enters the cabin
}

## ─── STATE CATEGORIES ──────────────────────────────────────────────────────
## These constant arrays group states by behavior category for use by the
## Director (entity_director.gd) and Controller (entity_controller.gd).
## Using `state in EntityAI.UNINTERRUPTIBLE_STATES` is cleaner and safer
## than maintaining brittle `if state == X or state == Y` chains.

## States that are highly active and should NOT be interrupted by the
## Director's fallback confidence escalation (Tier 7). The Entity is
## already engaged in a meaningful behavior and should not be redirected.
const UNINTERRUPTIBLE_STATES: Array = [
	State.INDOOR_SEARCH,
	State.CHARGE,
	State.STALK,
	State.FLINCH,
	State.RETREAT,
	State.FUSE_SABOTAGE,
	State.ATTACK_LAMP
]

var entity: CharacterBody3D = null

## The Master Behavior Director — the SINGLE source of truth for state transitions.
## NO script is allowed to call set_state() except this Director.
## External scripts may ONLY write data to the Entity's Blackboard.
var _director = null  # EntityDirector — typed via setup() to avoid cyclic preload

## The velocity vector computed by the current state's logic.
## Read by entity_controller.gd after process_state_logic() completes.
var _calculated_velocity: Vector3 = Vector3.ZERO

## Timer for damaging window barricades (accumulates delta while at a boarded window)
var _barricade_damage_timer: float = 0.0

## Whether the Entity has arrived at the indoor breach landing position.
## Used by INDOOR_SEARCH to distinguish Phase A (vault entry) from Phase B (patrol).
var _has_arrived_indoor: bool = false

## Timer for the EnterWindow vault animation in INDOOR_SEARCH Phase A.
## Counts down from ENTER_WINDOW_ANIM_DURATION to 0.0 while the Entity
## plays the vault animation. When it reaches 0.0, the Entity teleports
## to the indoor landing position and transitions to Phase B (patrol).
## This ensures the full vault animation plays out before the teleport,
## creating a seamless visual effect of the Entity climbing through the
## window frame.
var _enter_window_anim_timer: float = 0.0

## The world-space landing position for the Door Phase A cinematic breach.
## Set to the IndoorBreachWaypoint's global_position when the door entry
## begins. The Entity interpolates toward this position each frame.
var _landing_position: Vector3 = Vector3.ZERO

## Frame counter for the Door Phase A breach protocol.
## Incremented each frame during Door Phase A to prevent the "instant breach"
## bug. The arrival check (distance < 1.5m) is gated by requiring at least
## 5 frames to pass before it can trigger. This gives the Entity time to
## actually move through the doorway visually.
var _breach_frame_count: int = 0

## Breach lock flag — set to true during Door Phase A of INDOOR_SEARCH.
## Prevents the stuck detector in entity_controller.gd from firing while
## the Entity is walking toward the IndoorBreachWaypoint. The NavMesh may
## not cover the cabin interior, making the Entity appear "stranded" even
## though it's actively pathfinding through the doorway.
var _breach_in_progress: bool = false

## NOTE: The indoor search persistence timer has been REMOVED from this module.
## The Director (entity_director.gd) is now the SINGLE source of truth for
## how long the Entity must stay inside after breaching. The Director's
## _indoor_search_persistence_timer (30.0s) controls this duration.
## The AI module no longer makes "give up" decisions — that's the Director's job.
## See entity_director.gd's Tier 8 for the persistence guard logic.

## Duration of the EnterWindow vault animation in seconds.
## The animation is ~1.5 seconds long. The Entity must play this animation
## for its full duration before teleporting inside, ensuring the visual
## effect of vaulting through the window frame is fully visible.
## NOTE: This is now an @export variable (enter_window_anim_duration).
## The const is kept as a fallback for the initial value.
const ENTER_WINDOW_ANIM_DURATION: float = 1.5

## ─── INDOOR ROOM GRAPH ──────────────────────────────────────────────────────
## Adjacency graph of all cabin rooms. Used by BFS pathfinding to compute the
## shortest room-to-room path during INDOOR_SEARCH Phase B.
## Each key is a room name, and the value is an array of directly connected
## neighbor room names.
const INDOOR_ROOM_GRAPH: Dictionary = {
	"HallRoom": ["LivingRoom", "Stairs"],
	"LivingRoom": ["HallRoom", "ComputerRoom"],
	"ComputerRoom": ["LivingRoom"],
	"Stairs": ["HallRoom", "UpperHallRoom"],
	"UpperHallRoom": ["Stairs", "OfficeRoom", "BedRoom"],
	"OfficeRoom": ["UpperHallRoom"],
	"BedRoom": ["UpperHallRoom"]
}

## Animation lock timer for barricade hits.
## When > 0.0, the "AttackWindow" animation is forced to play.
## Set to 1.5 seconds on each barricade hit, decremented by delta each frame.
## This ensures the animation plays for its full duration even if the next
## hit is 2 seconds away. Read by entity_controller.gd's _update_animations().
var _barricade_anim_lock: float = 0.0

## Pending damage delay timer. When > 0.0, the Entity has swung its arm
## (AttackWindow animation started) but the damage hasn't been applied yet.
## Counts down to 0.0, then calls damage_barricade() to subtract plank health.
## This syncs the health subtraction with the visual impact frame of the
## AttackWindow animation. Set to 0.6s on each swing, decremented by delta.
var _pending_damage_delay: float = 0.0

## Whether a damage hit is pending (swing started, impact not yet applied).
## Set to true when the 2.0s barricade timer ticks over and the swing begins.
## Set to false when _pending_damage_delay reaches 0.0 and damage is applied.
var _has_pending_damage: bool = false

## ─── GLASS SHATTER ANIMATION SYNC ──────────────────────────────────────────
## When the window is glass-only (unbarricaded), the Entity must play the
## "AttackWindow" animation and delay the actual glass shatter until the
## impact frame. These variables manage that timing.
##
## _glass_shatter_pending: When true, the Entity has started the AttackWindow
##   swing but the glass hasn't shattered yet. Set to true when the breach
##   delay expires on an unbarricaded window. Set to false when the impact
##   timer fires and shatter_window() is called.
var _glass_shatter_pending: bool = false

## _glass_shatter_impact_timer: Counts down from GLASS_SHATTER_IMPACT_DELAY
##   to 0.0. When it reaches 0.0, the glass shatter is applied. This syncs
##   the visual destruction with the impact frame of the AttackWindow animation.
##   Set to GLASS_SHATTER_IMPACT_DELAY when _glass_shatter_pending becomes true.
var _glass_shatter_impact_timer: float = 0.0

## Duration (in seconds) from the start of the AttackWindow animation to the
## moment of impact where the glass should shatter. This should match the
## animation's keyframe timing. The AttackWindow animation is ~1.5s long,
## with the impact occurring at approximately the 0.5s mark (the swing
## connects with the glass).
const GLASS_SHATTER_IMPACT_DELAY: float = 0.5

## Current patrol waypoint for INDOOR_SEARCH Phase B dark room patrolling.
## When the player is in a dark room, the Entity picks random waypoints from
## the Cabin_Patrol_Waypoints group and paces between them instead of standing
## still at a single waypoint. Reset to Vector3.ZERO when a new waypoint is needed.
var _current_patrol_waypoint: Vector3 = Vector3.ZERO

## Whether a retreat target has been set for physical RETREAT pathfinding.
## Reset after the Entity reaches the exit point and fades out.
var _retreat_target_set: bool = false

## Debug frame counter for INDOOR_SEARCH Phase B logging.
## Incremented each frame in _indoor_search_state(). Used to throttle debug
## prints to every 30 frames (~0.5s at 60fps) to avoid console flooding.
var _indoor_search_debug_counter: int = 0

## Charge countdown timer for the STANDOFF state.
## Accumulates delta while the player holds the flashlight beam on the Entity.
## When it reaches 1.5 seconds (or 0.75s if confidence > THRESHOLD_CLIMAX),
## the Entity transitions to CHARGE.
## Reset to 0.0 if the player breaks line of sight or turns off the flashlight.
var _charge_countdown: float = 0.0

## Whether the Entity is in Phase 2 of wall climbing (vertical ascent).
var _wall_climb_phase_2: bool = false

## The Y-coordinate the Entity is climbing toward during CLIMB_WALL.
var _wall_climb_target_y: float = 0.0

## Siege duration timer — forces the Entity to stay in WINDOW_PEEK for a
## minimum duration (5 seconds) before it can exit via the stare timer.
## This prevents premature exit after the glass shatters, ensuring the
## full attack animation plays out and all barricade hits are delivered.
## Reset to 0.0 when transitioning into WINDOW_PEEK.
var _siege_duration_timer: float = 0.0

## Debug frame counter for WINDOW_PEEK state logging.
## Incremented each frame in _window_peek_state(). Used to throttle debug
## prints to every 30 frames (0.5s at 60fps) to avoid console flooding.
var _window_peek_debug_counter: int = 0

## Whether the peek assessment has been performed for the current WINDOW_PEEK
## session. Set to true after the first assessment decision (opportunity breach
## or abort). Prevents re-evaluation on subsequent frames, ensuring the Entity
## commits to its choice rather than oscillating between decisions.
var _peek_assessment_done: bool = false

## One-shot guard flag for the STANDOFF → RETREAT confidence gate.
## Set to true when the AI forces RETREAT due to low confidence (< 40).
## Reset to false when the Entity exits STANDOFF state.
## Prevents the oscillation loop: Controller sets STANDOFF → AI forces
## RETREAT → AI completes retreat (fade_and_relocate → OBSERVE) →
## Controller sets STANDOFF again.
var _standoff_retreat_triggered: bool = false

## ─── DESPERATION MECHANIC ──────────────────────────────────────────────
## Tracks how long the Entity has been in the OBSERVE_FROM_TREELINE state
## without transitioning to a more aggressive state. If this timer exceeds
## 45 seconds, a temporary "+0.5 confidence/s" modifier is injected into
## the confidence system, forcing the Entity to become bolder over time.
## The timer resets to 0.0 whenever the Entity transitions OUT of
## OBSERVE_FROM_TREELINE (handled in process_state_logic).
var _observe_passive_timer: float = 0.0

## Whether the desperation modifier is currently active. Prevents duplicate
## modifier registrations and redundant print spam.
var _desperation_modifier_active: bool = false

# ─── INVESTIGATION CONFUSION STATE ──────────────────────────────────────────
## Whether the Entity is currently in the Investigation sub-state (INDOOR_SEARCH).
## When true, the Entity has arrived at the last_known_position but cannot see
## the player. It freezes, plays a searching animation, and waits 4 seconds
## before giving up and transitioning to OBSERVE_FROM_TREELINE.
var _is_investigating: bool = false

## Timer for the Investigation sub-state (in seconds).
## Counts down from 4.0 to 0.0 while the Entity searches for the player.
## If the player is seen or heard during this window, the Entity resumes chase.
## If the timer reaches 0.0, the Entity gives up and transitions to OBSERVE.
var _investigation_timer: float = 0.0

# ─── ROOM-CENTER SCAN STATE ────────────────────────────────────────────────────
## When the Entity arrives at a room center (distance < 1.0m) during indoor
## search, it enters a scanning sub-state. The Entity rotates slowly in place
## for 4 seconds, looking for the player. If the player is spotted during the
## scan, the Entity immediately resumes the chase. If the scan timer expires
## without finding the player, the Entity returns to patrol.
var _scan_timer: float = 0.0

## Whether the Entity is currently in the scanning sub-state.
## When true, the Entity rotates slowly in place, looking for the player.
## Set to true when the Entity arrives at a room center during indoor search.
## Set to false when the scan timer expires or the player is spotted.
var _is_scanning: bool = false

# ─── ZERO-ANIMATION STUN / STARE ENRAGE ───────────────────────────────────────
## Timer that accumulates while the player is staring at the Entity.
## Resets to 0.0 if the player looks away (is_being_stared_at becomes false).
## If this timer reaches 1.5 seconds, the Entity becomes enraged
## (entity.is_enraged = true), triggering a permanent speed boost.
var _stare_timer: float = 0.0

## Whether the Entity is currently being stared at by the player's flashlight.
## Set by entity_controller.gd's on_player_stare() each frame.
## Used by process_state_logic() to apply the Zero-Animation Stun.
var _is_being_stared_at: bool = false

# ─── PHASE 3: WINDOW SHOPPING UTILITY SCORER ────────────────────────────────
## Array of recently visited windows (max 3 entries).
## Each entry is the window's NodePath or unique identifier string.
## Used by _score_window() to apply a recency malus (-30.0 penalty).
var _recently_visited_windows: Array[String] = []

## Maximum number of entries in _recently_visited_windows.
const MAX_RECENT_WINDOWS: int = 3

## ─── INDOOR ROOM NAVIGATION ────────────────────────────────────────────────
## BFS-computed room path for INDOOR_SEARCH Phase B room-to-room navigation.
## When the Entity is inside the cabin, it navigates through rooms by following
## doorway markers. _room_path contains the ordered list of room names to
## traverse, and _current_room_index tracks progress through the path.
var _room_path: Array[String] = []
var _current_room_index: int = 0

## Throttle timer for re-checking the player's current room during indoor search.
## Updated every 1.0 seconds to avoid expensive RoomLightDetector lookups.
var _room_path_recheck_timer: float = 0.0

## Pathfinding throttle timer (in seconds).
## Accumulates delta each frame. When <= 0.0, the next target_position update
## is allowed. After updating, the timer is reset to PATH_UPDATE_INTERVAL.
## This prevents calling NavigationAgent3D.target_position = ... every physics
## frame, which causes FPS drops due to path recalculation overhead.
var _path_timer: float = 0.0

## Minimum interval (in seconds) between NavigationAgent3D target_position updates.
## Setting target_position triggers a path recalculation which is expensive.
## Throttling to 300ms reduces pathfinding overhead by ~95% while maintaining
## responsive pursuit behavior.
const PATH_UPDATE_INTERVAL: float = 0.3

func setup(parent: CharacterBody3D) -> void:
	entity = parent
	
	# Initialize the Master Behavior Director
	# Use load() instead of preload() to avoid cyclic dependency with entity_director.gd
	# (entity_director.gd preloads entity_ai.gd, so entity_ai.gd cannot preload entity_director.gd)
	var DirectorClass = load("res://scripts/entity/entity_director.gd")
	if DirectorClass:
		_director = DirectorClass.new()
		if _director:
			print("[Entity AI] Master Behavior Director initialized.")


# ─── TYPED ACCESSORS (for entity_controller.gd cross-module reads) ──────────
# These replace fragile dynamic string lookups like "_barricade_anim_lock" in _ai
# with typed method calls. Renaming a variable in this file will produce a
# compile-time error if the accessor isn't updated, rather than silently breaking.

## Returns true if the barricade animation lock is active (> 0.0).
## Used by entity_controller.gd's _update_animations() to decide whether
## to play the AttackWindow animation.
func is_barricade_anim_locked() -> bool:
	return _barricade_anim_lock > 0.0

## Returns true if the Entity has arrived at the indoor breach landing position.
## Used by entity_controller.gd's _update_animations() to decide whether to
## play the EnterWindow animation (Phase A) or running_crawl (Phase B).
func has_arrived_indoor() -> bool:
	return _has_arrived_indoor

## Sets whether the Entity has arrived at the indoor breach landing position.
## Called by entity_controller.gd's ghost motor when the Entity reaches the
## IndoorBreachWaypoint during Door Phase A ghost movement.
func set_has_arrived_indoor(value: bool) -> void:
	_has_arrived_indoor = value

## Resets the barricade damage, siege timers, and glass shatter state to 0.0.
## Called by entity_controller.gd's _debug_attack_window() when F2 forces
## the Entity into WINDOW_PEEK state.
func reset_barricade_timers() -> void:
	_barricade_damage_timer = 0.0
	_siege_duration_timer = 0.0
	_glass_shatter_pending = false
	_glass_shatter_impact_timer = 0.0

## Resets the retreat target flag so the next RETREAT state re-selects
## a target position. Called by the Director after consuming the
## is_retreat_arrived completion flag.
func reset_retreat_target() -> void:
	_retreat_target_set = false

## Returns the velocity vector computed by the current state's logic.
## Called by entity_controller.gd after process_state_logic() completes
## to apply the velocity via move_and_slide().
func get_calculated_velocity() -> Vector3:
	return _calculated_velocity


## Returns whether the Entity is currently in the Door Phase A breach protocol.
## Used by entity_controller.gd's stuck detector to skip stuck detection
## while the Entity is walking toward the IndoorBreachWaypoint. The NavMesh
## may not cover the cabin interior, making the Entity appear "stranded"
## even though it's actively pathfinding through the doorway.
func is_breach_in_progress() -> bool:
	return _breach_in_progress


## Returns the current all-windows-lit frustration value.
## Used by the Director (Tier 1 Sabotage) to check if the Entity has been
## frustrated by all windows being lit for too long, without relying on
## magic number hacks (9999.0) on the fuse sabotage timer.
func get_all_lit_frustration() -> float:
	return _all_lit_frustration


## Returns the frustration threshold for FUSE_SABOTAGE escalation.
## Used by the Director to compare against get_all_lit_frustration().
func get_frustration_threshold() -> float:
	return ALL_LIT_FRUSTRATION_THRESHOLD


## Public API: Called by entity_controller.gd (Motor Hub) every physics frame.
## Processes the current state's logic and stores the result in _calculated_velocity.
## The Motor Hub then reads get_calculated_velocity() and applies it via move_and_slide().
func process_state_logic(delta: float) -> void:
	# ─── 5-NIGHT SIEGE PROGRESSION: NIGHT RULES EVALUATION ──────────────
	# Every decision cycle, evaluate the current night to enforce
	# night-specific infiltration capabilities. This runs BEFORE the
	# state dispatcher so that night rules can override state transitions.
	_evaluate_night_rules(delta)
	
	# ─── MASTER DIRECTOR: SINGLE SOURCE OF TRUTH FOR STATE TRANSITIONS ──
	# The Director evaluates the Blackboard data (is_illuminated,
	# player_stare_timer, confidence, player_inside) from top-to-bottom
	# priority and returns the one true state for this frame.
	#
	# THE GOLDEN RULE:
	#   NO script is allowed to call set_state() except the Director.
	#   External scripts (Player, sensory, etc.) may ONLY write data to
	#   the Entity's Blackboard (entity_controller.gd).
	#
	# STATE LOCK GUARD:
	#   If state_locked is true, the state handler is mid-execution and
	#   the Director MUST NOT override the state. This prevents "State
	#   Flapping" where the Director and FSM fight over the state variable
	#   every frame. State handlers set state_locked = true on entry and
	#   state_locked = false on completion.
	#
	# This eliminates the "Two Masters" problem where the Player script
	# and entity_ai.gd fought for control, causing the 60fps FLINCH/CHARGE
	# oscillation loop. The Director's sequential evaluation makes the
	# FLINCH/CHARGE loop mathematically impossible — Tier 1 evaluates
	# is_illuminated + is_player_inside first, and returns exactly one state.
	if _director:
		# STATE LOCK: If the state handler is mid-execution, skip the
		# Director's state transition entirely. The handler will unlock
		# when it completes its work.
		if entity.state_locked:
			# Director still evaluates for logging/debugging, but does NOT
			# apply the transition. The current state handler retains control.
			var _debug_intended = _director.evaluate_master_state(entity)
		else:
			var intended_state = _director.evaluate_master_state(entity)
			
			# Apply the Director's decision
			if entity.get_state() != intended_state:
				# [TRACE] Log state transitions during INDOOR_SEARCH
				var current_state = entity.get_state()
				if current_state == EntityAI.State.INDOOR_SEARCH or intended_state == EntityAI.State.INDOOR_SEARCH:
					print("[TRACE_STATE] Director transition: %s → %s" % [EntityAI.State.keys()[current_state], EntityAI.State.keys()[intended_state]])
				entity.set_state(intended_state)

	
	# ─── ANTI-FLAP COOLDOWN ─────────────────────────────────────────────
	# Decrement the anti-flap cooldown timer each frame. When the cooldown
	# reaches 0.0, the Director can once again force FLINCH (or other locked
	# states) in response to Blackboard conditions.
	if _director:
		_director.accumulate_anti_flap(delta)
	
	# ─── PERIODIC DEBUG LOG ─────────────────────────────────────────────
	# Every 3 seconds, the Director prints a comprehensive debug dump of all
	# Blackboard data, confidence, sensory info, navigation state, and AI
	# internals to the console. This mirrors the F3 overlay data for
	# post-mortem analysis without needing the overlay to be visible.
	if _director:
		_director.accumulate_debug_log(delta, entity)
	
	# ─── DESPERATION MECHANIC: PASSIVE TIMER RESET ──────────────────────
	# If the Entity is NOT in OBSERVE_FROM_TREELINE, reset the passive timer
	# and remove the desperation modifier if it was active. This ensures the
	# desperation only builds while the Entity is truly idle.
	if entity.get_state() != State.OBSERVE_FROM_TREELINE:
		_observe_passive_timer = 0.0
		if _desperation_modifier_active:
			_desperation_modifier_active = false
			var confidence_module = entity.get_confidence_module()
			if confidence_module and confidence_module.has_method("remove_continuous_modifier"):
				confidence_module.remove_continuous_modifier("desperation_passive")
				print("[Entity AI] Desperation: Removed passive modifier (Entity left OBSERVE state).")
	
	# ─── INDOOR SEARCH PERSISTENCE ─────────────────────────────────────
	# The indoor search persistence timer is managed by the Director
	# (entity_director.gd), NOT by this module. The Director's
	# _indoor_search_persistence_timer (30.0s) is the single source of
	# truth for how long the Entity must stay inside after breaching.
	# The AI module no longer makes "give up" decisions — that's the
	# Director's job. See entity_director.gd's Tier 8 for the guard logic.
	
	# --- STATE DISPATCHER ---
	# Execute Movement/Physics for the current state.
	# These functions ONLY contain movement, animation, and pathfinding code.
	# ALL transition logic has been moved to the Master Director above.
	match entity.get_state():

		State.DORMANT:
			_calculated_velocity = Vector3.ZERO
		State.OBSERVE_FROM_TREELINE:
			_observe_from_treeline_state(delta)
		State.SEARCH:
			# ─── OUTDOOR SEARCH ──────────────────────────────────────────
			# The Entity believes the player is outside (thinks_player_is_inside=false)
			# but cannot see them. It checks its sensory module for a last_heard_position.
			# If a position exists, it pathfinds to it. If no position exists, it waits
			# for a random interval (2-3s) before transitioning to OBSERVE_FROM_TREELINE
			# to "reset" its view.
			_search_state(delta)
		State.RETREAT:
			_retreat_state(delta)
		State.APPROACH_WINDOW:
			_approach_window_state(delta)
		State.WINDOW_PEEK:
			_window_peek_state(delta)
		State.STALK:
			_stalk_state(delta)
		State.CHARGE:
			_charge_state(delta)
		State.FLINCH:
			_flinch_state(delta)
		State.HARASS:
			_harass_state(delta)
		State.INDOOR_SEARCH:
			_indoor_search_state(delta)
		State.CLIMB_WALL_UP:
			_climb_wall_up_state(delta)
		State.CLIMB_WALL_DOWN:
			_climb_wall_down_state(delta)
		State.STANDOFF:
			# ─── FLASHLIGHT STANDOFF ──────────────────────────────────────
			# The Entity freezes in place while the player shines the flashlight
			# beam on it. The Director handles all state transitions from STANDOFF.
			# This function only handles movement (freeze) and the charge countdown
			# for the Director to read via the Blackboard.
			_calculated_velocity = Vector3.ZERO
			
			# Accumulate charge countdown on the Blackboard for the Director to read
			# The Director evaluates stare_time >= 1.5 to trigger CHARGE.
			# This countdown is managed by the controller's on_player_stare().
		State.ATTACK_LAMP:
			_attack_lamp_state(delta)
		State.FUSE_SABOTAGE:
			_fuse_sabotage_state(delta)
		_:
			_calculated_velocity = Vector3.ZERO
	
	# ─── ZERO-ANIMATION STUN ─────────────────────────────────────────────
	# If the player is staring at the Entity with the flashlight, apply the
	# Zero-Animation Stun: freeze velocity, force Idle animation, and
	# accumulate the stare timer for the enrage mechanic.
	#
	# The _is_being_stared_at flag is set by entity_controller.gd's
	# on_player_stare() each frame. It reflects whether the player's
	# flashlight beam is currently on the Entity.
	#
	# STUN RULES:
	#   - If state is CHARGE or RETREAT, the Entity is immune to the stun
	#     (it's already committed to an action).
	#   - If state is any other state AND the player is staring, force
	#     velocity to zero and play the Idle animation.
	#   - The _stare_timer accumulates while the player stares. If the
	#     player looks away, the timer resets to 0.0.
	#   - If _stare_timer reaches 1.5 seconds, the Entity becomes enraged
	#     (entity.is_enraged = true), triggering a permanent speed boost.
	var current_state = entity.get_state()
	if _is_being_stared_at and current_state != State.CHARGE and current_state != State.RETREAT:
		# ─── FREEZE VELOCITY ────────────────────────────────────────────
		# Override the calculated velocity to zero, preventing the Entity
		# from moving while being stared at.
		_calculated_velocity = Vector3.ZERO
		
		# ─── FORCE IDLE ANIMATION ──────────────────────────────────────
		# Travel to the Idle animation in the state machine so the Entity
		# doesn't play a "walk-in-place" animation while stunned.
		var anim_sm = entity.get_anim_state_machine()
		if anim_sm:
			anim_sm.travel("Idle")
		
		# ─── ACCUMULATE STARE TIMER ────────────────────────────────────
		# Count up while the player stares. If the timer reaches 1.5s,
		# trigger the enrage mechanic.
		_stare_timer += delta
		if _stare_timer >= 1.5 and not entity.is_enraged:
			entity.is_enraged = true
			print("[Entity AI] STARE ENRAGE: Player stared for 1.5s! Entity is now ENRAGED!")
	else:
		# ─── RESET STARE TIMER ──────────────────────────────────────────
		# If the player is not staring (or the Entity is in CHARGE/RETREAT),
		# reset the stare timer so it doesn't accumulate across multiple
		# stare sessions.
		if _stare_timer > 0.0:
			_stare_timer = 0.0
	
	# ─── SPATIAL VOICE MANAGEMENT ────────────────────────────────────────
	# After the state dispatcher runs, manage the Entity's spatial voice
	# audio based on the current state. This plays the appropriate voice
	# line (angry, talking, searching) for each state.
	_manage_spatial_voice(delta)
	
	

# ─── SPATIAL VOICE MANAGEMENT ──────────────────────────────────────────────
## Manages the Entity's spatial 3D voice audio based on the current FSM state.
## Called every frame from process_state_logic() after the state dispatcher.
##
## VOICE RULES:
##   - CHARGE: Plays Entity_Angry.ogg ONCE (one-shot, not looping).
##             Uses _voice_angry_played_this_charge flag to prevent re-triggering.
##             Reset when the Entity leaves CHARGE state.
##   - WINDOW_PEEK: Plays Entity_Talking_1.ogg or Entity_Talking_2.ogg randomly
##                  (looping). Picks a random track on state entry.
##   - OBSERVE_FROM_TREELINE: Plays Entity_Searching.ogg (looping).
##   - All other states: Stop the voice player.
##
## TRANSITION DETECTION:
##   Tracks the previous state (_last_voice_state) to detect when the Entity
##   enters or leaves a voice-active state. On entry, the appropriate voice
##   line is started. On exit, the voice is stopped.
var _last_voice_state: int = -1

## The audio stream currently loaded on the voice player.
## Used to detect whether the voice player needs a stream swap.
var _current_voice_stream: AudioStream = null

func _manage_spatial_voice(delta: float) -> void:
	var voice_player = entity.get_voice_player()
	if not voice_player:
		return
	
	var current_state = entity.get_state()
	
	# ─── STATE TRANSITION DETECTION ──────────────────────────────────────
	# If the state changed since the last frame, handle voice transitions.
	if current_state != _last_voice_state:
		# ─── RESET ANGRY FLAG WHEN LEAVING CHARGE ───────────────────────
		# Check BEFORE updating _last_voice_state so we can detect the
		# transition from CHARGE to any other state. If we were in CHARGE
		# and now we're not, reset the angry flag so the next CHARGE can
		# play the angry voice again.
		if _last_voice_state == State.CHARGE and current_state != State.CHARGE:
			entity.set_voice_angry_played_this_charge(false)
		
		# Update the last voice state tracker
		_last_voice_state = current_state
		
		# ─── CHARGE: One-shot angry voice ────────────────────────────────
		if current_state == State.CHARGE:
			var angry_stream = entity.get_voice_angry()
			if angry_stream and not entity.has_voice_angry_played_this_charge():
				# Stop any currently playing voice
				if voice_player.playing:
					voice_player.stop()
				# Load the angry stream (one-shot, not looping)
				voice_player.stream = angry_stream
				voice_player.play()
				entity.set_voice_angry_played_this_charge(true)
				print("[Entity AI] VOICE: Playing Entity_Angry.ogg (CHARGE one-shot)")
		
		# ─── WINDOW_PEEK: Random talking voice (looping) ─────────────────
		elif current_state == State.WINDOW_PEEK:
			var talking_1 = entity.get_voice_talking_1()
			var talking_2 = entity.get_voice_talking_2()
			var selected_stream: AudioStream = null
			
			# Pick randomly between talking_1 and talking_2
			if talking_1 and talking_2:
				selected_stream = talking_1 if randf() < 0.5 else talking_2
			elif talking_1:
				selected_stream = talking_1
			elif talking_2:
				selected_stream = talking_2
			
			if selected_stream:
				# Enable looping for talking streams
				if selected_stream is AudioStreamOggVorbis:
					selected_stream.loop = true
				voice_player.stream = selected_stream
				voice_player.play()
				print("[Entity AI] VOICE: Playing Entity_Talking.ogg (WINDOW_PEEK looping)")
		
		# ─── OBSERVE_FROM_TREELINE: Searching voice (looping) ────────────
		elif current_state == State.OBSERVE_FROM_TREELINE:
			var search_stream = entity.get_voice_searching()
			if search_stream:
				# Enable looping for searching stream
				if search_stream is AudioStreamOggVorbis:
					search_stream.loop = true
				voice_player.stream = search_stream
				voice_player.play()
				print("[Entity AI] VOICE: Playing Entity_Searching.ogg (OBSERVE looping)")
		
		# ─── ALL OTHER STATES: Stop voice ────────────────────────────────
		else:
			if voice_player.playing:
				voice_player.stop()
				voice_player.stream = null


# ---------------------------------------------------------------------------
# STATE: SEARCH — Outdoor search when player is believed outside
# ---------------------------------------------------------------------------
## The Entity believes the player has escaped (thinks_player_is_inside=false)
## but cannot see them. It checks its sensory module for a last_heard_position.
## If a position exists, it pathfinds to it. If no position exists, it waits
## for a random interval (2-3s) before transitioning to OBSERVE_FROM_TREELINE
## to "reset" its view.
##
## This is the "blind search" state — the Entity knows the player escaped but
## doesn't know where they went. It searches the last known location, then
## gives up and returns to treeline observation.
var _search_wait_timer: float = 0.0
var _search_waiting: bool = false

func _search_state(delta: float) -> void:
	# ─── SEARCH STATE REMOVED ───────────────────────────────────────────
	# The SEARCH state has been removed. When the Entity believes the player
	# has escaped (thinks_player_is_inside=false), the Director now waits
	# 5-10 seconds (outside confirmation timer) and then transitions directly
	# to STALK. The Entity pathfinds toward the player's last known position
	# and pursues them through the forest.
	#
	# This function is kept as a stub to prevent runtime errors if the
	# Director somehow transitions to SEARCH. It immediately signals
	# completion to return to OBSERVE_FROM_TREELINE.
	entity.is_observe_finished = true
	entity.state_locked = false
	_calculated_velocity = Vector3.ZERO
	print("[SEARCH] SEARCH state is deprecated. Returning to OBSERVE_FROM_TREELINE.")
	return


# ---------------------------------------------------------------------------
# STATE: OBSERVE_FROM_TREELINE
# ---------------------------------------------------------------------------

## ─── ALL WINDOWS LIT LOOP GUARD ──────────────────────────────────────────────
## When ALL ground-floor windows are secured by light sanctuary, the Entity
## cannot approach any window. This guard prevents the Entity from continuously
## cycling frames (OBSERVE → APPROACH → no windows → OBSERVE → APPROACH → ...).
##
## While all windows are lit, the Entity remains in OBSERVE_FROM_TREELINE for a
## minimum state cooldown (5 seconds). During this cooldown, it accumulates
## frustration at 2.0 * delta per second. If frustration reaches the threshold
## (90.0), the Entity transitions to FUSE_SABOTAGE to break the generator.
##
## The frustration timer resets when ANY window becomes unlit (a light turns off).
var _all_lit_frustration: float = 0.0

## Minimum cooldown (in seconds) the Entity must wait in OBSERVE_FROM_TREELINE
## when all windows are lit before it can attempt to approach again.
const ALL_LIT_MIN_COOLDOWN: float = 5.0

## Timer counting down the ALL_LIT_MIN_COOLDOWN.
## Set to ALL_LIT_MIN_COOLDOWN when all windows are detected as lit.
var _all_lit_cooldown_timer: float = 0.0

## Frustration threshold for FUSE_SABOTAGE escalation.
## When frustration reaches this value, the Entity abandons window approach
## and goes straight to sabotaging the Fuse Box to kill the generator.
const ALL_LIT_FRUSTRATION_THRESHOLD: float = 90.0

## Frustration accumulation rate (per second) while all windows are lit.
const ALL_LIT_FRUSTRATION_RATE: float = 2.0


func _observe_from_treeline_state(delta: float) -> void:
	# --- PORTABLE TRAP ATTRACTION OVERRIDE ---
	# The Director handles the ATTACK_LAMP transition (Tier 3).
	# This function only handles movement and pathfinding.
	
	# ─── ALL WINDOWS LIT LOOP GUARD ──────────────────────────────────────
	# Check if ALL ground-floor windows are secured by light sanctuary.
	# If so, the Entity cannot approach any window and must wait in
	# OBSERVE_FROM_TREELINE until a light turns off.
	var nav_module = entity.get_navigation_module()
	var all_lit: bool = false
	if nav_module and nav_module.has_method("are_all_windows_lit"):
		all_lit = nav_module.are_all_windows_lit()
	
	if all_lit:
		# ─── COOLDOWN: Force minimum wait in OBSERVE ─────────────────────
		# Set the cooldown timer on the first frame all windows are detected
		# as lit. During the cooldown, the Entity cannot signal completion
		# (is_observe_finished stays false), preventing the Director from
		# cycling to APPROACH_WINDOW and back.
		if _all_lit_cooldown_timer <= 0.0:
			_all_lit_cooldown_timer = ALL_LIT_MIN_COOLDOWN
			print("[Entity AI] ALL WINDOWS LIT: All windows secured by light. Cooldown %.1fs started." % ALL_LIT_MIN_COOLDOWN)
		
		# Decrement the cooldown timer
		_all_lit_cooldown_timer -= delta
		if _all_lit_cooldown_timer > 0.0:
			# ─── DURING COOLDOWN: Accumulate frustration ─────────────────
			# While the Entity is forced to wait, it builds frustration at
			# 2.0 * delta per second. This frustration represents the Entity's
			# growing impatience with being unable to approach any window.
			_all_lit_frustration += ALL_LIT_FRUSTRATION_RATE * delta
			
			# ─── FRUSTRATION THRESHOLD: FUSE_SABOTAGE ────────────────────
			# If frustration reaches the threshold, the Entity abandons window
			# approach entirely and goes straight to sabotaging the Fuse Box.
			# This kills the generator, turning off ALL lights at once.
			if _all_lit_frustration >= ALL_LIT_FRUSTRATION_THRESHOLD:
				print("[Entity AI] ALL WINDOWS LIT: Frustration reached %.1f! Escalating to FUSE_SABOTAGE." % _all_lit_frustration)
				_all_lit_frustration = 0.0
				_all_lit_cooldown_timer = 0.0
				entity.is_observe_finished = false
				entity.state_locked = false
				_calculated_velocity = Vector3.ZERO
				# The Director's Tier 1 Sabotage reads _all_lit_frustration
				# directly from the AI module via get_all_lit_frustration().
				# No magic number hack needed — the Director compares the
				# actual frustration value against the threshold.
				return
			
			# ─── FREEZE MOVEMENT DURING COOLDOWN ─────────────────────────
			# The Entity stays at its current vantage point, facing the cabin,
			# accumulating frustration until the cooldown expires or a light
			# turns off.
			_calculated_velocity = Vector3.ZERO
			entity.set_stare_timer(9999.0)  # Prevent stare timer from expiring
			
			# Face the cabin while waiting
			var cabin_target = entity.cabin_center
			var dir_to_cabin = (cabin_target - entity.global_position).normalized()
			var target_cabin_angle = atan2(dir_to_cabin.x, dir_to_cabin.z)
			var model = entity.get_monster_model()
			if model:
				model.rotation.y = lerp_angle(model.rotation.y, target_cabin_angle, 0.05)
			
			# ─── DEBUG LOG ───────────────────────────────────────────────
			if int(_all_lit_cooldown_timer * 10) % 30 == 0:
				print("[Entity AI] ALL WINDOWS LIT: Cooldown=%.1fs, Frustration=%.1f" % [_all_lit_cooldown_timer, _all_lit_frustration])
			return
		else:
			# ─── COOLDOWN EXPIRED: Reset frustration if a light turned off ──
			# If the cooldown has expired AND all windows are still lit,
			# reset the frustration and restart the cooldown cycle.
			# If a light turned off (all_lit is now false), the frustration
			# resets naturally below.
			if all_lit:
				# Still all lit — restart the cooldown cycle
				_all_lit_cooldown_timer = ALL_LIT_MIN_COOLDOWN
				_calculated_velocity = Vector3.ZERO
				return
	else:
		# ─── A LIGHT TURNED OFF: Reset frustration and cooldown ──────────
		# When any window becomes unlit, the Entity can resume normal
		# observation behavior. The frustration and cooldown are reset
		# so the Entity starts fresh.
		if _all_lit_frustration > 0.0 or _all_lit_cooldown_timer > 0.0:
			_all_lit_frustration = 0.0
			_all_lit_cooldown_timer = 0.0
			print("[Entity AI] ALL WINDOWS LIT: A light turned off! Frustration reset.")
	
	# --- PHYSICAL PATHFINDING TO VANTAGE POINT ---
	if not entity.get_nav_agent().is_navigation_finished():
		# ─── NAV TARGET JITTER ──────────────────────────────────────────
		# Add a small random offset (±0.5m) to the nav target so the Entity
		# doesn't try to occupy the exact same coordinate as a tree mesh or
		# treeline marker. This prevents micro-stuttering and collision jitter
		# as the NavigationAgent3D tries to reach an exact point that may
		# overlap with tree colliders.
		entity.set_path_timer(entity.get_path_timer() + delta)
		if entity.get_path_timer() >= entity.path_update_interval:
			entity.set_path_timer(0.0)
			var current_target = entity.get_nav_agent().target_position
			var jitter_offset = Vector3(
				randf_range(-0.5, 0.5),
				0.0,
				randf_range(-0.5, 0.5)
			)
			entity.get_nav_agent().target_position = current_target + jitter_offset
		
		var next_pos = entity.get_nav_agent().get_next_path_position()
		var dir_2d := Vector2(next_pos.x - entity.global_position.x, next_pos.z - entity.global_position.z)
		if dir_2d.length() > 0.01:
			var move_dir_2d = dir_2d.normalized()
			_calculated_velocity.x = move_dir_2d.x * entity.current_stalk_speed
			_calculated_velocity.z = move_dir_2d.y * entity.current_stalk_speed
		return
	else:
		# ─── FIRST ENTRY: No nav target set ──────────────────────────────
		# When the Entity first enters OBSERVE_FROM_TREELINE (e.g., from DORMANT
		# at game start), the NavigationAgent3D has no target set. The Director
		# only calls fade_and_relocate() when is_observe_finished is true, which
		# is false on the first entry. Without a nav target, is_navigation_finished()
		# returns true immediately, and the Entity enters the "ARRIVED" block below.
		# But the stare timer is 0.0 (not >= 9990.0), so the "ARRIVED AT VANTAGE
		# POINT" block never triggers. The Entity just sits there with zero velocity.
		#
		# FIX: If navigation is finished AND the stare timer is NOT in the 9990
		# range (meaning we haven't just arrived), AND we haven't set a relocate
		# target yet, call pick_next_vantage_point() to set an initial target.
		if entity.get_stare_timer() < 9990.0 and not entity.get_relocate_target_set():
			var nav = entity.get_navigation_module()
			if nav and nav.has_method("pick_next_vantage_point"):
				nav.pick_next_vantage_point()
				entity.set_stare_timer(9999.0)  # Mark as "just arrived" so the timer init block fires
				print("[Entity AI] OBSERVE: First entry detected. Picked initial vantage point.")
				return
	
	# --- ARRIVED AT VANTAGE POINT ---
	if entity.get_stare_timer() >= 9990.0:
		# ─── AGGRESSIVE PACING: Dynamic wait time based on confidence ──
		# High confidence (>= 40) = fast relocations (2-4.5s), making the
		# Entity feel elusive and aggressive. Low confidence = slower early-
		# night stalking (4-8s), giving the player breathing room.
		var conf = entity.get_confidence_module().get_confidence()
		var wait_time: float
		if conf >= confidence_approach_threshold:
			wait_time = randf_range(observe_wait_high_min, observe_wait_high_max)
		else:
			wait_time = randf_range(observe_wait_low_min, observe_wait_low_max)
		entity.set_stare_timer(wait_time)
		entity.set_at_vantage_point(true)

	
	_calculated_velocity.x = 0.0
	_calculated_velocity.z = 0.0
	
	# ─── FACE THE CABIN WHILE IDLE ────────────────────────────────────────
	# When the Entity is at a vantage point (not pathfinding), rotate the
	# monster model to face the cabin center. This ensures the Entity is
	# always looking toward the cabin while observing, creating a more
	# menacing and intentional visual presence.
	# The rotation is smoothly interpolated using lerp_angle for natural
	# turning, and only applies when the Entity is stationary (not moving
	# between vantage points).
	var cabin_target = entity.cabin_center
	var dir_to_cabin = (cabin_target - entity.global_position).normalized()
	var target_cabin_angle = atan2(dir_to_cabin.x, dir_to_cabin.z)
	var model = entity.get_monster_model()
	if model:
		model.rotation.y = lerp_angle(model.rotation.y, target_cabin_angle, 0.05)
	
	# ─── DESPERATION MECHANIC: PASSIVE TIMER ──────────────────────────────
	# Accumulate time spent in OBSERVE_FROM_TREELINE while at the vantage
	# point (not pathfinding). If the Entity stays passive for more than 45
	# seconds, inject a temporary "+0.5 confidence/s" modifier until it
	# transitions to a more aggressive state (e.g., APPROACH_WINDOW).
	# This makes the Entity feel like it's "getting fed up" with waiting,
	# forcing it to approach the windows even if the player is hiding.
	_observe_passive_timer += delta
	
	if _observe_passive_timer >= desperation_threshold and not _desperation_modifier_active:
		_desperation_modifier_active = true
		var confidence_module = entity.get_confidence_module()
		if confidence_module and confidence_module.has_method("add_continuous_modifier"):
			confidence_module.add_continuous_modifier(desperation_modifier_rate, "desperation_passive")
			print("[Entity AI] Desperation: Entity has been passive for %.1fs! Injecting +0.5 confidence/s." % _observe_passive_timer)
	
	entity.set_stare_timer(entity.get_stare_timer() - delta)
	if entity.get_stare_timer() <= 0.0:
		# ─── 3-WAYPOINT MISS RULE: Impatience Mechanic ─────────────────
		# The Entity finished observing at a vantage point without spotting
		# the player. Increment the consecutive miss counter. If it reaches
		# 3, the Entity gets IMPATIENT — it boosts its confidence to force
		# a window approach rather than deducing the player escaped.
		#
		# DESIGN INTENT:
		#   The old logic set thinks_player_is_inside=false after 3 misses,
		#   which caused the Director to transition into STALK (outdoor
		#   pursuit) even though the Entity hadn't visually confirmed the
		#   player was outside. This was unfair — the Entity could "blindly"
		#   deduce the player escaped just from staring at the cabin.
		#
		#   NEW LOGIC: After 3 misses, the Entity gets impatient and boosts
		#   confidence by 30 points. This forces the confidence escalation
		#   system (Tier 4) to trigger APPROACH_WINDOW, making the Entity
		#   physically approach the cabin and peek through windows. The
		#   Entity still BELIEVES the player is inside — it just can't see
		#   them and is getting frustrated.
		#
		#   The Entity can ONLY conclude the player escaped if:
		#     1. It hears a noise OUTSIDE (hear_noise() with "Outside" room)
		#     2. It SEES the player outside (can_entity_see_player() with
		#        outdoor room detection)
		entity.increment_consecutive_vantage_misses()
		var misses = entity.get_consecutive_vantage_misses()
		if misses >= 3:
			# ─── IMPATIENCE CONFIDENCE BOOST ──────────────────────────
			# Boost confidence by 30 points to force a window approach.
			# The Entity is getting impatient — it can't see the player
			# but still believes they're inside. This makes the Entity
			# physically approach the cabin and peek through windows.
			var confidence_module = entity.get_confidence_module()
			if confidence_module:
				var current_conf = confidence_module.get_confidence()
				var new_conf = minf(100.0, current_conf + 30.0)
				confidence_module.set_confidence(new_conf)
				print("[Entity AI] 3-WAYPOINT MISS RULE: %d consecutive misses! Impatience boost! Confidence: %.1f → %.1f" % [misses, current_conf, new_conf])
			
			# ─── CONSUME THE MISSES ─────────────────────────────────────
			# Reset the consecutive miss counter after the confidence boost
			# is applied. This prevents the boost from being applied again
			# on the next frame (the stare timer would still be <= 0.0).
			entity.reset_consecutive_vantage_misses()
		else:
			print("[Entity AI] Vantage miss %d/3. Player still believed inside." % misses)
		
		# ─── RESET THE STARE TIMER ──────────────────────────────────────
		# CRITICAL: Reset the stare timer to a new random value so it does
		# NOT fire again on the next frame. Without this, the timer stays
		# at <= 0.0 and the block above fires every frame, incrementing
		# misses 60 times per second instead of once per vantage point.
		# This was the root cause of the "instant 3-miss" bug.
		var conf = entity.get_confidence_module().get_confidence()
		var wait_time: float
		if conf >= confidence_approach_threshold:
			wait_time = randf_range(observe_wait_high_min, observe_wait_high_max)
		else:
			wait_time = randf_range(observe_wait_low_min, observe_wait_low_max)
		entity.set_stare_timer(wait_time)
		
		# ─── RESET RELOCATE TARGET FLAG ─────────────────────────────────
		# CRITICAL: Reset the _relocate_target_set flag so the Entity knows
		# it needs to pick a NEW tree on the next cycle. Without this, the
		# Entity would arrive at the first tree, the Director would consume
		# is_observe_finished and call fade_and_relocate(), but the Entity
		# wouldn't know it needs to move — it would stay at the same tree
		# forever, creating the "paralysis at first tree" bug.
		entity.set_relocate_target_set(false)
		
		# ─── SIGNAL COMPLETION TO THE DIRECTOR ──────────────────────────
		# Instead of calling fade_and_relocate() directly (which would
		# bypass the Director and call request_state()), we set a Blackboard
		# completion flag. The Director will detect this flag in its next
		# evaluation cycle, call fade_and_relocate() for the setup work,
		# and transition to OBSERVE_FROM_TREELINE.
		entity.is_observe_finished = true
		entity.state_locked = false
		_calculated_velocity = Vector3.ZERO
		return



# ---------------------------------------------------------------------------
# STATE: ATTACK_LAMP — Physical approach and strike against the portable lamp
# ---------------------------------------------------------------------------

func _attack_lamp_state(delta: float) -> void:
	var trap = entity.get_portable_trap()
	
	if not trap or not trap.is_deployed or not trap.is_powered:
		# The Director will handle the transition out of ATTACK_LAMP
		# when the trap is no longer valid (Tier 3 check fails).
		# Just reset the attack timer and stop moving.
		entity.set_lamp_attack_timer(0.0)
		_calculated_velocity = Vector3.ZERO
		return
	
	entity.set_path_timer(entity.get_path_timer() + delta)
	if entity.get_path_timer() >= entity.path_update_interval:
		entity.set_path_timer(0.0)
		entity.get_nav_agent().target_position = trap.global_position
	
	var dist_to_trap: float = entity.global_position.distance_to(trap.global_position)
	
	if dist_to_trap < lamp_attack_range:
		entity.set_lamp_attack_timer(entity.get_lamp_attack_timer() + delta)
		
		if entity.get_lamp_attack_timer() >= lamp_attack_interval:
			entity.set_lamp_attack_timer(0.0)
			var hit_dir: Vector3 = (trap.global_position - entity.global_position).normalized()
			if trap.has_method("take_physical_hit"):
				trap.take_physical_hit(hit_dir)
				print("[Entity AI] ATTACK_LAMP: Struck portable lamp at distance %.1f!" % dist_to_trap)
			var anim_sm = entity.get_anim_state_machine()
			if anim_sm:
				anim_sm.travel("AttackWindow")
		
		_calculated_velocity = Vector3.ZERO
	else:
		if entity.get_nav_agent().is_navigation_finished():
			_calculated_velocity.x = 0.0
			_calculated_velocity.z = 0.0
		else:
			var next_pos = entity.get_nav_agent().get_next_path_position()
			var dir_2d := Vector2(next_pos.x - entity.global_position.x, next_pos.z - entity.global_position.z)
			if dir_2d.length() > 0.01:
				var move_dir_2d = dir_2d.normalized()
				_calculated_velocity.x = move_dir_2d.x * entity.current_stalk_speed
				_calculated_velocity.z = move_dir_2d.y * entity.current_stalk_speed



# ---------------------------------------------------------------------------
# STATE: FUSE_SABOTAGE — Physical approach and strike against the Fuse Box
# ---------------------------------------------------------------------------
## The Entity pathfinds to the Fuse Box and strikes it repeatedly to break it.
## Once the Fuse Box is destroyed, the Entity signals completion to the
## Director, which transitions to the next appropriate state.
func _fuse_sabotage_state(delta: float) -> void:
	var fuse_box = entity.get_fuse_box_node()
	
	if not fuse_box or not is_instance_valid(fuse_box):
		# Fuse Box doesn't exist or was destroyed — signal completion
		entity.is_fuse_sabotaged = true
		_calculated_velocity = Vector3.ZERO
		return
	
	# Check if the Fuse Box is already destroyed
	if fuse_box.has_method("is_destroyed") and fuse_box.is_destroyed():
		entity.is_fuse_sabotaged = true
		_calculated_velocity = Vector3.ZERO
		return
	
	# Pathfind toward the Fuse Box
	entity.set_path_timer(entity.get_path_timer() + delta)
	if entity.get_path_timer() >= entity.path_update_interval:
		entity.set_path_timer(0.0)
		entity.get_nav_agent().target_position = fuse_box.global_position
	
	var dist_to_fuse: float = entity.global_position.distance_to(fuse_box.global_position)
	
	if dist_to_fuse < fuse_sabotage_range:
		# In range — accumulate damage timer
		entity.set_fuse_sabotage_timer(entity.get_fuse_sabotage_timer() + delta)
		
		if entity.get_fuse_sabotage_timer() >= fuse_sabotage_interval:
			entity.set_fuse_sabotage_timer(0.0)
			# Apply damage to the Fuse Box
			if fuse_box.has_method("take_damage"):
				fuse_box.take_damage(1)
				print("[Entity AI] FUSE_SABOTAGE: Struck Fuse Box!")
			# Play attack animation
			var anim_sm = entity.get_anim_state_machine()
			if anim_sm:
				anim_sm.travel("AttackWindow")
		
		_calculated_velocity = Vector3.ZERO
	else:
		# Pathfinding toward the Fuse Box
		if entity.get_nav_agent().is_navigation_finished():
			_calculated_velocity.x = 0.0
			_calculated_velocity.z = 0.0
		else:
			var next_pos = entity.get_nav_agent().get_next_path_position()
			var dir_2d := Vector2(next_pos.x - entity.global_position.x, next_pos.z - entity.global_position.z)
			if dir_2d.length() > 0.01:
				var move_dir_2d = dir_2d.normalized()
				_calculated_velocity.x = move_dir_2d.x * entity.current_stalk_speed
				_calculated_velocity.z = move_dir_2d.y * entity.current_stalk_speed


# ---------------------------------------------------------------------------
# STATE: STALK (CHASE / PATROL)
# ---------------------------------------------------------------------------

func _stalk_state(delta: float) -> void:
	# ─── CHASE BREAKER: Player Reached Safety ──────────────────────────
	# The Director handles the state transition when the player reaches
	# safety (Tier 2: CHASE → OBSERVE_FROM_TREELINE if player is inside).
	# This function only handles movement and pathfinding.
	
	# ─── PORTABLE TRAP ATTRACTION ──────────────────────────────────────
	# The Director handles the ATTACK_LAMP transition. This function only
	# handles movement toward the trap once the state is set.
	
	var player = entity.get_player()
	if not player:
		return
	
	# ─── LIGHT SWITCH RETREAT CHECK (CHASE) ────────────────────────────
	# If the Entity is inside a lit room during CHASE (e.g., it chased the
	# player inside and the player flipped the light switch), force immediate
	# RETREAT. This check runs every frame for instant response.
	if RoomLightDetector.is_entity_in_lit_room():
		entity.is_indoor_retreat = true
		entity.state_locked = false
		_calculated_velocity = Vector3.ZERO
		return
	
	# ─── PATHFINDING & MOVEMENT ───────────────────────────────────────
	# Throttle NavigationAgent3D target_position updates to prevent FPS drops.
	# Setting target_position triggers an expensive path recalculation.
	# Updating every frame (60fps) causes significant lag. We throttle to
	# PATH_UPDATE_INTERVAL (300ms), reducing pathfinding overhead by ~95%.
	#
	# The _path_timer is reset to 0.0 on state transitions so that pathfinding
	# initiates immediately when the Entity enters a new state.
	_path_timer -= delta
	if _path_timer <= 0.0:
		_path_timer = PATH_UPDATE_INTERVAL
		
		# ─── NAV TARGET JITTER ──────────────────────────────────────────
		# Add a small random offset (±0.5m) to the nav target so the Entity
		# doesn't converge on the player's exact pixel coordinate. This creates
		# more organic-looking pursuit and prevents the Entity from micro-stuttering
		# as the NavigationAgent3D tries to reach an exact point that the player
		# has already moved away from.
		var jitter_offset = Vector3(
			randf_range(-0.5, 0.5),
			0.0,
			randf_range(-0.5, 0.5)
		)
		entity.get_nav_agent().target_position = player.global_position + jitter_offset
	
	# ─── CATCH CHECK ──────────────────────────────────────────────────
	# If the Entity is close enough to the player, catch them.
	if entity.global_position.distance_to(player.global_position) <= entity.catch_distance:
		entity._on_caught_player()
		return
	
	# ─── UNIVERSAL FRUSTRATION: LIT ROOM BLOCK ───────────────────────
	# If the player is in a lit room and the Entity is outside (CHASE) or
	# inside (INDOOR_SEARCH), accumulate frustration. The Entity can't
	# reach the player through the light sanctuary, so it gets frustrated.
	# When frustration reaches the threshold, the Director's Tier 1 Sabotage
	# will transition to FUSE_SABOTAGE to kill the generator.
	#
	# This prevents the Entity from endlessly chasing the player through
	# lit rooms without any adaptive response.
	if entity.get_navigation_module().has_method("is_player_in_lit_room"):
		var player_in_lit = entity.get_navigation_module().is_player_in_lit_room()
		if player_in_lit:
			_all_lit_frustration += ALL_LIT_FRUSTRATION_RATE * delta
			_all_lit_frustration = minf(_all_lit_frustration, ALL_LIT_FRUSTRATION_THRESHOLD)
	
	# ─── INVESTIGATION CONFUSION (CHASE) ──────────────────────────────
	# When the Entity reaches the last_known_position and cannot see the
	# player, enter an Investigation sub-state. The Entity freezes for 4
	# seconds (playing a searching animation). If the player is seen or
	# heard during this pause, the Entity immediately resumes the chase.
	# If the timer expires and it finds nothing, it drops confidence and
	# returns to OBSERVE_FROM_TREELINE.
	if _is_investigating:
		# Already investigating — count down the timer
		_investigation_timer -= delta
		
		# Freeze movement during investigation
		_calculated_velocity = Vector3.ZERO
		
		# Check if player is spotted during investigation
		var sensory = entity.get_sensory_module()
		if sensory and sensory.has_method("can_entity_see_player") and sensory.can_entity_see_player():
			_is_investigating = false
			_investigation_timer = 0.0
		elif entity.is_hunting() and entity.get_current_interest_level() > 50.0:
			# Player was heard (acoustic detection) during investigation
			_is_investigating = false
			_investigation_timer = 0.0
		
		if _investigation_timer <= 0.0:
			# Investigation complete — give up and transition to OBSERVE
			_is_investigating = false
			entity.is_observe_finished = true
			entity.state_locked = false
			_calculated_velocity = Vector3.ZERO
			return
		else:
			# Still investigating — freeze and wait
			return
	
	# ─── CHECK IF WE'VE ARRIVED AT LAST_KNOWN_POSITION ───────────────
	# If the nav agent finished AND we can't see the player, start investigating.
	var lkp = entity.get_last_known_position()
	var dist_to_lkp = entity.global_position.distance_to(lkp)
	var nav_finished = entity.get_nav_agent().is_navigation_finished()
	
	if (nav_finished or dist_to_lkp <= 3.0) and not _is_investigating:
		var sensory = entity.get_sensory_module()
		var can_see_player = false
		if sensory and sensory.has_method("can_entity_see_player"):
			can_see_player = sensory.can_entity_see_player()
		
		if not can_see_player:
			# Start investigation
			_is_investigating = true
			_investigation_timer = 4.0
			_calculated_velocity = Vector3.ZERO
			return
	
	# ─── MOVEMENT ─────────────────────────────────────────────────────
	# Follow the navigation path toward the player.
	if entity.get_nav_agent().is_navigation_finished():
		_calculated_velocity.x = 0.0
		_calculated_velocity.z = 0.0
	else:
		var next_pos = entity.get_nav_agent().get_next_path_position()
		var dir_2d := Vector2(next_pos.x - entity.global_position.x, next_pos.z - entity.global_position.z)
		if dir_2d.length() > 0.01:
			var move_dir_2d = dir_2d.normalized()
			_calculated_velocity.x = move_dir_2d.x * entity.current_stalk_speed
			_calculated_velocity.z = move_dir_2d.y * entity.current_stalk_speed

# ---------------------------------------------------------------------------
# STATE: CHARGE (3x speed sprint at the player)
# ---------------------------------------------------------------------------

func _charge_state(delta: float) -> void:
	var charge_speed = entity.current_stalk_speed * charge_speed_multiplier
	
	var player = entity.get_player()
	if not player:
		return
	
	entity.set_path_timer(entity.get_path_timer() + delta)
	if entity.get_path_timer() >= entity.path_update_interval:
		entity.set_path_timer(0.0)
		entity.get_nav_agent().target_position = player.global_position
	
	if entity.global_position.distance_to(player.global_position) <= entity.catch_distance:
		entity._on_caught_player()
		return
	
	if entity.get_nav_agent().is_navigation_finished():
		_calculated_velocity.x = 0.0
		_calculated_velocity.z = 0.0
	else:
		var next_pos = entity.get_nav_agent().get_next_path_position()
		var dir_2d := Vector2(next_pos.x - entity.global_position.x, next_pos.z - entity.global_position.z)
		if dir_2d.length() > 0.01:
			var move_dir_2d = dir_2d.normalized()
			_calculated_velocity.x = move_dir_2d.x * charge_speed
			_calculated_velocity.z = move_dir_2d.y * charge_speed


# ---------------------------------------------------------------------------
# STATE: ENTER_THROUGH_DOOR — Walk to the front door, open it, and enter the cabin
# ---------------------------------------------------------------------------
## The Entity pathfinds to the EntityDoorWaypoint marker, opens the door if
## closed, checks if the HallRoom light ("CabinLightHall") is on, and if so,
## pauses 2 seconds before turning it off. Then it signals completion to the
## Director, which transitions to INDOOR_SEARCH.
##
## PHASES:
##   1. Pathfind to EntityDoorWaypoint
##   2. Arrive at door → open if closed
##   3. Check HallRoom light → if on, pause 2s then toggle off
##   4. Signal completion (is_approach_finished = true)
var _hall_light_pending_toggle: bool = false

func _enter_through_door_state(delta: float) -> void:
	# ─── HANDLE HALLROOM LIGHT TOGGLE DELAY ──────────────────────────
	# If we're waiting for the 2-second pause before toggling the light,
	# check if the timer has expired.
	if _hall_light_pending_toggle:
		if entity.get_state_timer() <= 0.0:
			_hall_light_pending_toggle = false
			var hall_light = _find_hall_light()
			if hall_light and hall_light.has_method("toggle_light"):
				hall_light.toggle_light()
				print("[ENTER_THROUGH_DOOR] HallRoom light toggled OFF after 2s pause.")
			entity.is_approach_finished = true
			_calculated_velocity = Vector3.ZERO
			return
		else:
			# Still waiting — freeze and count down
			_calculated_velocity = Vector3.ZERO
			return
	
	# ─── PHASE 1: Find the EntityDoorWaypoint ─────────────────────────
	var waypoints = get_tree().get_nodes_in_group("EntityWaypoints")
	var door_wp: Node3D = null
	for wp in waypoints:
		if wp.name == "EntityDoorWaypoint":
			door_wp = wp
			break
	
	if not door_wp:
		# Fallback: no waypoint found, just go to INDOOR_SEARCH
		print("[ENTER_THROUGH_DOOR] No EntityDoorWaypoint found. Signaling completion.")
		entity.is_approach_finished = true
		_calculated_velocity = Vector3.ZERO
		return
	
	# ─── PHASE 2: Pathfinding toward the door waypoint ────────────────
	_path_timer -= delta
	if _path_timer <= 0.0:
		_path_timer = PATH_UPDATE_INTERVAL
		entity.get_nav_agent().target_position = door_wp.global_position
	
	var dist_to_wp = entity.global_position.distance_to(door_wp.global_position)
	
	# ─── PHASE 3: Arrived at door ─────────────────────────────────────
	if dist_to_wp <= 2.5:
		# 3a. Open the door if it's closed
		var door = get_tree().get_first_node_in_group("Door")
		if door and door.has_method("interact") and not door.is_open:
			door.interact()
			print("[ENTER_THROUGH_DOOR] Door was closed. Opened it.")
		
		# 3b. Check HallRoom light ("CabinLightHall")
		var hall_light = _find_hall_light()
		if hall_light and hall_light.is_switched_on and hall_light.is_generator_running():
			# Light is on — pause 2 seconds, then toggle it off
			entity.set_state_timer(2.0)
			_hall_light_pending_toggle = true
			_calculated_velocity = Vector3.ZERO
			print("[ENTER_THROUGH_DOOR] HallRoom light is ON. Pausing 2s before toggling off.")
			return
		
		# 3c. No light to toggle — enter immediately
		entity.is_approach_finished = true
		_calculated_velocity = Vector3.ZERO
		print("[ENTER_THROUGH_DOOR] Arrived at door. Signaling completion (no light to toggle).")
		return
	
	# ─── PHASE 4: Movement toward waypoint ────────────────────────────
	if entity.get_nav_agent().is_navigation_finished():
		_calculated_velocity = Vector3.ZERO
	else:
		var next_pos = entity.get_nav_agent().get_next_path_position()
		var dir_2d := Vector2(next_pos.x - entity.global_position.x, next_pos.z - entity.global_position.z)
		if dir_2d.length() > 0.01:
			var move_dir_2d = dir_2d.normalized()
			_calculated_velocity.x = move_dir_2d.x * entity.current_stalk_speed
			_calculated_velocity.z = move_dir_2d.y * entity.current_stalk_speed


## Finds the HallRoom cabin light ("CabinLightHall") in the scene.
## Returns the CabinLight node, or null if not found.
func _find_hall_light() -> Node:
	var lights = get_tree().get_nodes_in_group("CabinLights")
	for light in lights:
		if "light_name" in light and light.light_name == "CabinLightHall":
			return light
	return null


# ─── NIGHT RULES EVALUATION ──────────────────────────────────────────────────

## Evaluates night-specific infiltration capabilities and enforces
## night-based state restrictions. Called every decision cycle BEFORE
## the state dispatcher so that night rules can override state transitions.
##
## Night 1: Entity can only observe from treeline (no window approach).
## Night 2: Entity can approach windows and peek inside.
## Night 3+: Entity can breach windows
func _evaluate_night_rules(delta: float) -> void:
	# Get the current night from the NightManager singleton.
	# NOTE: We read from NightManager, NOT GameTime. GameTime manages the
	# day/night cycle (time of day), while NightManager tracks which narrative
	# night the player is on (1-5). The debug console sets the night via
	# NightManager.start_night(night), so reading from NightManager ensures
	# the debug override is respected.
	var night_manager = entity.get_node_or_null("/root/NightManager")
	if not night_manager:
		return
	
	var current_night: int = night_manager.current_night if "current_night" in night_manager else 1
	
	# Night 1: Restrict to OBSERVE_FROM_TREELINE only
	# The Director handles the Night 1 restriction (Tier 0).
	# This function only handles the stare timer reset for the transition.
	if current_night == 1:
		var state = entity.get_state()
		if state != State.DORMANT and state != State.OBSERVE_FROM_TREELINE and state != State.RETREAT:
			entity.set_stare_timer(9999.0)
			# Room detection is logged by the Chase Breaker debug system
	
	# Night 2: Allow window approach and peek, but no breaching
	# (Breaching is handled by the window's barricade health system)
	
	# Night 3+: Full aggression unlocked (no restrictions)
	# The confidence system and individual state handlers manage the rest.
	
	# Note: Night-specific speed multipliers and confidence drift are
	# handled in entity_controller.gd and entity_confidence.gd respectively.


# ---------------------------------------------------------------------------
# STATE: RETREAT — Physical pathfinding to a distant treeline vantage point
# ---------------------------------------------------------------------------
## The Entity retreats to the farthest treeline vantage point from its
## current position. Once it arrives, it fades out and relocates to a
## random vantage point, transitioning back to OBSERVE_FROM_TREELINE.
##
## INDOOR RETREAT MODE:
## When entity.is_indoor_retreat is true, the Entity was caught inside the
## cabin by the player's flashlight. It must:
##   Phase 1: Pathfind to the breach window's indoor landing position
##   Phase 2: Teleport outside (to the window's exterior), then transition
##            to FLINCH state for lateral evasion
##
## The is_indoor_retreat flag is set by the Director (Tier 0) when the Entity
## is illuminated while in INDOOR_SEARCH or CHASE state. Confidence is dropped
## to 20%. After Phase 2 teleport, the state is set to FLINCH and locked so
## the FLINCH handler can complete its 1.5-second lateral sprint before the
## Director re-evaluates.
var _indoor_retreat_phase: int = 0  # 0=not started, 1=pathfind to window, 2=teleport outside → FLINCH

## Phase 3 dedicated timer and flag for the indoor retreat flinch sequence.
## Decoupled from the flinch timer system to avoid animation blending conflicts
## with the RETREAT→Idle hard clamp in entity_controller.gd.
var _retreat_indoor_phase_3: bool = false
var _retreat_indoor_phase_3_timer: float = 0.0
var _retreat_indoor_phase_3_triggered: bool = false

func _retreat_state(delta: float) -> void:
	# Lock the state — the Director must not override while we're mid-retreat
	entity.state_locked = true
	
	# ─── INDOOR RETREAT MODE ──────────────────────────────────────────────
	# The Entity was caught inside the cabin by the player's flashlight.
	# It must escape back through the breach window, then perform a 5-second
	# flinch before transitioning to OBSERVE_FROM_TREELINE.
	if entity.is_indoor_retreat:
		_indoor_retreat_handler(delta)
		return
	
	# ─── STANDARD OUTDOOR RETREAT ─────────────────────────────────────────
	# Normal retreat to the farthest treeline vantage point.
	if not _retreat_target_set:
		_retreat_target_set = true
		var treeline_markers: Array[Node] = entity.get_tree().get_nodes_in_group("Treeline_Vantage_Points")
		if not treeline_markers.is_empty():
			var farthest_marker: Node3D = treeline_markers[0] as Node3D
			var farthest_dist: float = 0.0
			for marker in treeline_markers:
				var m: Node3D = marker as Node3D
				if m:
					var d: float = entity.global_position.distance_to(m.global_position)
					if d > farthest_dist:
						farthest_dist = d
						farthest_marker = m
			entity.get_nav_agent().target_position = farthest_marker.global_position
		else:
			entity.get_nav_agent().target_position = Vector3(9.0, 0.0, 40.0)
	
	if entity.get_nav_agent().is_navigation_finished():
		# Arrived at retreat target — signal completion to the Director
		entity.is_retreat_arrived = true
		entity.state_locked = false
		_calculated_velocity = Vector3.ZERO
	else:
		var next_pos = entity.get_nav_agent().get_next_path_position()
		var dir_2d := Vector2(next_pos.x - entity.global_position.x, next_pos.z - entity.global_position.z)
		if dir_2d.length() > 0.01:
			var move_dir_2d = dir_2d.normalized()
			_calculated_velocity.x = move_dir_2d.x * entity.current_stalk_speed
			_calculated_velocity.z = move_dir_2d.y * entity.current_stalk_speed


## Handles the indoor retreat sequence when the Entity is caught inside the
## cabin by the player's flashlight. Three-phase escape:
##
##   Phase 1: Pathfind to the breach window's indoor landing position
##   Phase 2: Teleport outside (to the window's exterior), then pathfind to
##            the farthest treeline vantage point
##   Phase 3: Perform a 5-second flinch (lateral sprint) before signaling
##            completion to the Director
##
## The is_indoor_retreat flag is reset to false when the sequence completes.
func _indoor_retreat_handler(delta: float) -> void:
	var breach_window = entity.last_breached_window
	
	# ─── PHASE 1: Pathfind to the breach window's indoor landing position ──
	if _indoor_retreat_phase == 0:
		if breach_window and breach_window.has_method("get_indoor_landing_position"):
			var landing_pos = breach_window.get_indoor_landing_position()
			entity.get_nav_agent().target_position = landing_pos
			_indoor_retreat_phase = 1
			print("[INDOOR RETREAT] Phase 1: Pathfinding to breach window indoor landing position.")
		else:
			# No breach window — skip directly to Phase 3 (flinch)
			_indoor_retreat_phase = 3
			entity.set_flinched_timer(5.0)
			print("[INDOOR RETREAT] No breach window found. Skipping to Phase 3 (flinch).")
	
	if _indoor_retreat_phase == 1:
		# Pathfind toward the indoor landing position
		if entity.get_nav_agent().is_navigation_finished():
			# Arrived at the window — advance to Phase 2 (teleport outside)
			_indoor_retreat_phase = 2
			print("[INDOOR RETREAT] Phase 1 complete. Advancing to Phase 2 (teleport outside).")
		else:
			var next_pos = entity.get_nav_agent().get_next_path_position()
			var dir_2d := Vector2(next_pos.x - entity.global_position.x, next_pos.z - entity.global_position.z)
			if dir_2d.length() > 0.01:
				var move_dir_2d = dir_2d.normalized()
				_calculated_velocity.x = move_dir_2d.x * entity.current_stalk_speed * 1.5  # Sprint to escape
				_calculated_velocity.z = move_dir_2d.y * entity.current_stalk_speed * 1.5
			return
	
	# ─── PHASE 2: Teleport outside the breach window ──────────────────────
	if _indoor_retreat_phase == 2:
		if breach_window:
			# Teleport to the window's exterior position (2m outside the window)
			var window_pos = breach_window.global_position
			var window_basis = breach_window.global_transform.basis
			# Move 2m in the -Z direction (outside) from the window's facing
			var outside_pos = window_pos - window_basis.z * 2.0
			outside_pos.y = entity.global_position.y  # Keep current Y to avoid vertical snapping
			entity.global_position = outside_pos
			entity.velocity = Vector3.ZERO
			print("[INDOOR RETREAT] Phase 2: Teleported outside to (%.2f, %.2f, %.2f)" % [outside_pos.x, outside_pos.y, outside_pos.z])
		
		# ─── TRANSITION TO FLINCH ──────────────────────────────────────────
		# The Entity has successfully escaped outside through the breach window.
		# Now it must enter the FLINCH state to laterally evade the flashlight
		# beam. We set the state to FLINCH directly and lock it so the FLINCH
		# handler can complete its 1.5-second lateral sprint before the Director
		# re-evaluates.
		#
		# The Director's Tier 0 has a special exception: if the state is FLINCH
		# and state_locked is true, it preserves the lock instead of breaking it.
		# This ensures the FLINCH handler runs to completion uninterrupted.
		#
		# The _start_flinch() call is handled by the FLINCH state handler on
		# its first frame (it checks if timer <= 0.0 and initializes).
		_indoor_retreat_phase = 0
		entity.is_indoor_retreat = false
		entity.set_state(EntityAI.State.FLINCH)
		entity.state_locked = true
		_calculated_velocity = Vector3.ZERO
		print("[INDOOR RETREAT] Phase 2 complete! Teleported outside. Transitioning to FLINCH state.")
		return
	
	# ─── PHASE 3: Flinch (lateral sprint) before signaling completion ─────
	# The Entity has escaped outside and must perform a 5-second flinch
	# (lateral sprint) before signaling completion to the Director.
	# This phase uses a dedicated timer and flag (_retreat_indoor_phase_3)
	# decoupled from the flinch timer system to avoid animation blending
	# conflicts with the RETREAT→Idle hard clamp in entity_controller.gd.
	if _indoor_retreat_phase == 3:
		if not _retreat_indoor_phase_3_triggered:
			_retreat_indoor_phase_3 = true
			_retreat_indoor_phase_3_timer = 5.0
			_retreat_indoor_phase_3_triggered = true
			print("[INDOOR RETREAT] Phase 3: Starting 5-second flinch (lateral sprint).")
		
		# Travel to Flinch animation via the state machine
		var anim_sm = entity.get_anim_state_machine()
		if anim_sm:
			anim_sm.travel("Flinch")
		
		# Decrement the dedicated phase 3 timer
		_retreat_indoor_phase_3_timer -= delta
		
		if _retreat_indoor_phase_3_timer <= 0.0:
			# Phase 3 complete — signal completion to the Director
			# Use is_retreat_arrived (the existing Blackboard property) instead of
			# is_retreat_finished (which doesn't exist on entity_controller.gd).
			# The Director checks is_retreat_arrived in Tier 0 to transition to
			# OBSERVE_FROM_TREELINE after a retreat completes.
			entity.is_retreat_arrived = true
			entity.state_locked = false
			_retreat_indoor_phase_3_triggered = false
			_retreat_indoor_phase_3 = false
			_calculated_velocity = Vector3.ZERO
			print("[INDOOR RETREAT] Phase 3 complete! Flinch finished. Signaling completion to Director.")
			return


# ---------------------------------------------------------------------------
# STATE: APPROACH_WINDOW — Pathfinding toward a selected window
# ---------------------------------------------------------------------------
## The Entity selects a window target using a utility scorer and navigates
## toward it. Once within range, transitions to WINDOW_PEEK.
##
## UTILITY SCORING ("Smart Stalker"):
##   The scorer evaluates every available window and assigns a score based on:
##     - Proximity bonus: closer windows score higher (inverse distance)
##     - Room avoidance penalty: -500 if the player is standing in the same
##       room as the window (Entity avoids the exact room the player is in)
##     - Recency malus: -30 if the window was visited recently
##     - Light path penalty: penalizes windows that require crossing lit areas
##
##   The highest-scoring window is selected as the target. This makes the
##   Entity feel like a "Smart Stalker" that baits the player by tapping on
##   adjacent windows rather than the one in the player's current room.
##
## ANTI-OSCILLATION: Minimum approach timer
##   Prevents the Entity from signaling completion instantly when the
##   NavigationAgent finishes prematurely (e.g., NavMesh can't reach the
##   exact window coordinate). The Entity must spend at least 2.0 seconds
##   pathfinding before it can signal completion. This prevents the
##   APPROACH_WINDOW ↔ OBSERVE_FROM_TREELINE 60fps oscillation loop.
var _approach_min_timer: float = 0.0
const APPROACH_MIN_DURATION: float = 2.0

## ─── APPROACH FAILSAFE TIMEOUT ──────────────────────────────────────────────
## If the Entity has been in APPROACH_WINDOW for more than 15 seconds without
## arriving at the window, force a completion signal to prevent permanent
## soft-locks. This can happen when the NavMesh can't reach the window
## (e.g., the cabin wall blocks pathfinding) and the Entity stutters at the
## edge of the NavMesh indefinitely.
var _approach_failsafe_timer: float = 0.0
const APPROACH_FAILSAFE_TIMEOUT: float = 15.0

## ─── APPROACH DEBUG LOG TIMER ───────────────────────────────────────────────
## Prints Entity and window coordinates every 2 seconds during APPROACH_WINDOW
## to help debug pathfinding issues (e.g., Entity not moving toward the window,
## NavMesh can't reach the target, or the Entity is stuck at the cabin wall).
var _approach_debug_timer: float = 0.0
const APPROACH_DEBUG_INTERVAL: float = 2.0

func _approach_window_state(delta: float) -> void:
	# Lock the state — the Director must not override while we're mid-approach
	entity.state_locked = true
	
	# ─── MINIMUM APPROACH TIMER ──────────────────────────────────────────
	# Accumulate time spent in APPROACH_WINDOW. The Entity must spend at
	# least 2.0 seconds pathfinding before it can signal completion.
	# This prevents instant arrival when the NavigationAgent finishes
	# prematurely (e.g., NavMesh can't reach the exact window coordinate).
	_approach_min_timer += delta
	_approach_failsafe_timer += delta
	
	# ─── FAILSAFE TIMEOUT ──────────────────────────────────────────────────
	# If the Entity has been pathfinding for more than 15 seconds without
	# arriving, force a completion signal. This prevents permanent soft-locks
	# when the NavMesh can't reach the window (e.g., the cabin wall blocks
	# pathfinding) and the Entity stutters at the edge of the NavMesh.
	if _approach_failsafe_timer >= approach_failsafe_timeout:
		print("[Entity AI] APPROACH_WINDOW FAILSAFE: %ds elapsed without arrival. Forcing completion." % approach_failsafe_timeout)
		_calculated_velocity = Vector3.ZERO
		entity.is_approach_finished = true
		entity.state_locked = false
		_approach_min_timer = 0.0
		_approach_failsafe_timer = 0.0
		return
	
	var window_target = entity.get_current_window_target()
	if not window_target:
		# ─── TACTICAL FLANKING: Use navigation module's pick_tactical_window() ──
		# This gathers all windows within 15m of the player and picks one at random,
		# simulating intelligent flanking rather than a beeline to the nearest window.
		# Falls back to the absolute closest window if none are within range.
		var nav_module = entity.get_navigation_module()
		var best_window: Node3D = null
		if nav_module and nav_module.has_method("pick_tactical_window"):
			best_window = nav_module.pick_tactical_window(entity.get_player())
		
		if best_window:
			entity.set_current_window_target(best_window)
			# ─── FLATTEN Y-AXIS: Force ground-level pathfinding ──────────
			# Second-story windows have Y ≈ 3.0m. The NavMesh is at ground
			# level (Y ≈ 0.0). Setting target_position to the window's raw
			# 3D coordinate causes the NavigationAgent3D to fail — it can't
			# find a path to a point 3m above the NavMesh surface.
			# By flattening Y to the Entity's current Y, we force ground-
			# level pathfinding to the window's XZ position.
			var flat_target = best_window.global_position
			flat_target.y = entity.global_position.y
			entity.get_nav_agent().target_position = flat_target
			window_target = best_window
			
			# ─── DEBUG PRINT ─────────────────────────────────────────────
			var selected_id: String = ""
			if best_window.has_method("get_window_id"):
				selected_id = best_window.get_window_id()
			elif "window_id" in best_window:
				selected_id = best_window.window_id
			print("[Entity AI] Tactical window selected: %s" % selected_id)
		else:
			# ─── NO WINDOWS AVAILABLE: Signal completion to break the loop ──
			# When pick_tactical_window() returns null (no windows within 15m
			# of the player), the handler must signal completion to the Director
			# so it can transition to OBSERVE_FROM_TREELINE. Without this, the
			# Director would re-enter APPROACH_WINDOW on the next frame because
			# confidence >= 40, creating a 60fps oscillation loop.
			_calculated_velocity = Vector3.ZERO
			entity.is_approach_finished = true
			entity.state_locked = false
			_approach_min_timer = 0.0
			_approach_failsafe_timer = 0.0
			return
	
	if window_target:
		# ─── PERIODIC DEBUG LOG (every 2 seconds) ────────────────────────
		# Prints Entity and window coordinates to help debug pathfinding
		# issues during APPROACH_WINDOW. This is especially useful for
		# diagnosing NavMesh reachability problems where the Entity gets
		# stuck at the edge of the NavMesh near the cabin wall.
		_approach_debug_timer += delta
		if _approach_debug_timer >= approach_debug_interval:
			_approach_debug_timer = 0.0
			var window_id_str: String = ""
			if window_target.has_method("get_window_id"):
				window_id_str = window_target.get_window_id()
			elif "window_id" in window_target:
				window_id_str = str(window_target.window_id)
			var entity_pos = entity.global_position
			var window_pos = window_target.global_position
			var nav_target = entity.get_nav_agent().target_position
			var nav_finished = entity.get_nav_agent().is_navigation_finished()
			print("[APPROACH DEBUG] Entity=(%.2f, %.2f, %.2f) | Window '%s'=(%.2f, %.2f, %.2f) | NavTarget=(%.2f, %.2f, %.2f) | NavFinished=%s | dist_2d=%.2f" % [
				entity_pos.x, entity_pos.y, entity_pos.z,
				window_id_str, window_pos.x, window_pos.y, window_pos.z,
				nav_target.x, nav_target.y, nav_target.z,
				nav_finished,
				Vector2(entity_pos.x, entity_pos.z).distance_to(Vector2(nav_target.x, nav_target.z))
			])
		
			# ─── 2D DISTANCE CHECK: Ignore vertical height differences ──────
		# The NavMesh is at ground level (Y ≈ 0.0). The window target may be
		# at Y ≈ 3.0m (second story). Using 3D distance would include the
		# vertical component, making the Entity think it's farther away than
		# it actually is. We project both positions to 2D (XZ plane) for an
		# accurate ground-level distance check.
		var my_pos_2d = Vector2(entity.global_position.x, entity.global_position.z)
		var target_pos_2d = Vector2(entity.get_nav_agent().target_position.x, entity.get_nav_agent().target_position.z)
		var dist_2d = my_pos_2d.distance_to(target_pos_2d)
		
		# ─── ARRIVAL CHECK: 2D distance threshold (generous 2.5m) ──────
		# The Entity must be within 2.5m of the window target AND have spent
		# at least 2.0 seconds pathfinding before signaling completion.
		# The 2.5m threshold is generous enough that the Entity registers an
		# arrival even if it has to stop at the edge of the NavMesh just
		# outside the cabin wall (the NavMesh may not reach the exact window
		# coordinate — the wall blocks further pathfinding).
		#
		# NOTE: We do NOT use is_navigation_finished() as a completion signal.
		# The NavMesh may not reach the exact window coordinate (e.g., the
		# cabin wall blocks further pathfinding). In that case, the Entity
		# gets as close as the NavMesh allows and then is_navigation_finished()
		# fires. But the Entity is still 3.6m away from the window — not close
		# enough to peek inside. We rely solely on the 2D distance check.
		var nav_finished = entity.get_nav_agent().is_navigation_finished()
		if dist_2d <= approach_arrival_distance and _approach_min_timer >= approach_min_duration:
			# ─── DETECT IF TARGET IS A DOOR ──────────────────────────────
			# Check if the current window target is actually the front door.
			# The door is identified by checking if the target is a Door node
			# (has "is_open" property) or if the target's parent is a Door.
			# If it's a door, we handle door-specific arrival logic instead of
			# the standard window arrival (which transitions to WINDOW_PEEK).
			var is_door_target: bool = false
			print("[DOOR DEBUG] Checking if target is door. window_target.name='%s', window_target.class='%s'" % [window_target.name, window_target.get_class()])
			if window_target.has_method("is_in_group") and window_target.is_in_group("Door"):
				is_door_target = true
				print("[DOOR DEBUG] Target IS in Door group.")
			elif window_target.get_parent() and window_target.get_parent().has_method("is_in_group") and window_target.get_parent().is_in_group("Door"):
				is_door_target = true
				print("[DOOR DEBUG] Target's parent IS in Door group. Parent name='%s'" % window_target.get_parent().name)
			elif "is_open" in window_target:
				is_door_target = true
				print("[DOOR DEBUG] Target has 'is_open' property.")
			elif "name" in window_target and window_target.name == "EntityDoorWaypoint":
				is_door_target = true
				print("[DOOR DEBUG] Target name IS EntityDoorWaypoint.")
			else:
				print("[DOOR DEBUG] Target is NOT a door. Checking parent... parent=%s" % [window_target.get_parent().name if window_target.get_parent() else "null"])
			
			if is_door_target:
				# ─── SET DOOR TARGET FLAG ──────────────────────────────────
				# Set the Blackboard flag so the Director knows this was a door
				# approach (not a window approach). The Director reads this flag
				# in Tier 5 to determine the correct transition:
				#   - Window approach → WINDOW_PEEK
				#   - Door approach (unlocked) → INDOOR_SEARCH
				#   - Door approach (locked) → OBSERVE
				entity.is_door_target = true
				
				# ─── DOOR ARRIVAL (Multi-Phase) ───────────────────────────
				# The Entity has arrived at the door. Handle door-specific logic
				# with a multi-phase sequence:
				#
				#   Phase 0: Not started (standard approach pathfinding)
				#   Phase 1: Arrived at door — handle door state:
				#     - Locked:   Pause 2 seconds, then return to OBSERVE
				#     - Closed:   Pause 2 seconds, open door, advance to Phase 2
				#     - Open:     Skip pause, advance to Phase 2
				#   Phase 2: Walk through doorway to interior waypoint
				#   Phase 3: Arrived inside — signal completion → INDOOR_SEARCH
				#
				print("[Entity AI] APPROACH_WINDOW: Arrived at DOOR! dist_2d=%.2f, min_timer=%.2f. Door phase=%d." % [dist_2d, _approach_min_timer, entity._door_phase])
				
				# Get the actual Door node
				var door_node = window_target
				if door_node.has_method("is_in_group") and not door_node.is_in_group("Door"):
					door_node = door_node.get_parent()
				
				# ─── PHASE 1: Handle door state ───────────────────────────
				if entity._door_phase == 0:
					# Initialize Phase 1 — arrived at door
					entity._door_phase = 1
					entity._door_phase_timer = 2.0  # 2-second pause
					
					# Check if door is locked
					if door_node and "is_locked" in door_node and door_node.is_locked:
						# Door is locked — play rattle sound, set cooldown
						print("[Entity AI] APPROACH_WINDOW: Door is LOCKED! Playing rattle sound.")
						if door_node.has_method("interact"):
							door_node.interact()  # Plays the locked rattle sound
						entity.is_door_locked = true
						entity._door_approach_cooldown = 30.0
					
					# Check if door is already open — skip the pause
					if door_node and "is_open" in door_node and door_node.is_open:
						entity._door_phase_timer = 0.0  # Skip pause
						print("[Entity AI] APPROACH_WINDOW: Door already open. Skipping pause.")
					
					_calculated_velocity = Vector3.ZERO
					return
				
				if entity._door_phase == 1:
					# Count down the pause timer
					entity._door_phase_timer -= delta
					_calculated_velocity = Vector3.ZERO
					
					if entity._door_phase_timer > 0.0:
						return  # Still waiting
					
					# ─── LOCKED DOOR: Return to OBSERVE ───────────────────
					if entity.is_door_locked:
						print("[Entity AI] APPROACH_WINDOW: Door locked pause complete. Returning to OBSERVE.")
						entity.is_approach_finished = true
						entity.state_locked = false
						entity._door_phase = 0
						_approach_min_timer = 0.0
						_approach_failsafe_timer = 0.0
						_calculated_velocity = Vector3.ZERO
						return
					
					# ─── CLOSED DOOR: Open it ─────────────────────────────
					if door_node and door_node.has_method("interact") and "is_open" in door_node and not door_node.is_open:
						door_node.interact()
						print("[Entity AI] APPROACH_WINDOW: Door was closed. Opened it after 2s pause.")
						# ─── DEBUG: Log Entity position at door open ──────────────
						print("[Entity AI] APPROACH_WINDOW: Entity position at door open: (%.2f, %.2f, %.2f)" % [entity.global_position.x, entity.global_position.y, entity.global_position.z])
						if door_node:
							print("[Entity AI] APPROACH_WINDOW: Door position: (%.2f, %.2f, %.2f)" % [door_node.global_position.x, door_node.global_position.y, door_node.global_position.z])
					
					# Check HallRoom light and toggle it off if on
					var hall_light = _find_hall_light()
					if hall_light and "is_switched_on" in hall_light and hall_light.is_switched_on:
						if hall_light.has_method("is_generator_running") and hall_light.is_generator_running():
							if hall_light.has_method("toggle_light"):
								hall_light.toggle_light()
								print("[Entity AI] APPROACH_WINDOW: HallRoom light toggled OFF.")
					
					# Advance to Phase 2 — walk through doorway
					entity._door_phase = 2
					
					# ─── RESET FAILSAFE TIMER ──────────────────────────────────
					# CRITICAL: Reset the approach failsafe timer when Phase 2
					# begins. The failsafe timer starts counting from the moment
					# the Entity enters APPROACH_WINDOW (line ~1822). By the time
					# the Entity has pathfound to the door, waited 2 seconds, and
					# opened it, ~14 seconds may have elapsed. Without this reset,
					# the 15-second failsafe fires almost immediately after Phase 2
					# starts, causing the Director to transition to INDOOR_SEARCH
					# before the Entity has walked through the doorway.
					_approach_failsafe_timer = 0.0
					
					# ─── PHASE 2: Walk through doorway ────────────────────────
					# The Entity walks through the doorway using standard 2D-flattened
					# NavMesh pathfinding. The controller's move_and_slide() + Floor
					# RayCast handles Y-axis elevation (stairs, threshold) automatically.
					#
					# CRITICAL: We do NOT teleport the Entity to the IndoorBreachWaypoint
					# here. That is the sole responsibility of INDOOR_SEARCH Door Phase A.
					# APPROACH_WINDOW only gets the Entity to the door — INDOOR_SEARCH
					# handles the interior teleport. This prevents the "instant breach"
					# bug where the Entity arrives inside before INDOOR_SEARCH even starts.
					#
					# The Entity walks to the EntityDoorWaypoint (just outside the door),
					# NOT the interior waypoint. The NavMesh covers the exterior, so
					# pathfinding works reliably. Once the Entity arrives at the door,
					# we signal completion and let INDOOR_SEARCH handle the interior.
					
					# ─── SIGNAL COMPLETION ──────────────────────────────────
					# The Entity has arrived at the door. Set was_door_entry = true
					# so INDOOR_SEARCH knows to enter Door Phase A (walk to the
					# IndoorBreachWaypoint). No teleport — the Entity stays at the
					# door and INDOOR_SEARCH handles the interior navigation.
					entity.was_door_entry = true
					entity.is_approach_finished = true
					entity.state_locked = false
					entity._door_phase = 0
					entity._door_phase_2_timer = 0.0
					_approach_min_timer = 0.0
					_approach_failsafe_timer = 0.0
					_calculated_velocity = Vector3.ZERO
					print("[Entity AI] APPROACH_WINDOW: Door Phase 1 complete. Signaling completion. INDOOR_SEARCH will handle interior teleport.")
					return
			else:
				# ─── WINDOW ARRIVAL (existing behavior) ──────────────────
				print("[Entity AI] APPROACH_WINDOW: Arrived at window! dist_2d=%.2f, min_timer=%.2f. Setting is_approach_finished=true" % [dist_2d, _approach_min_timer])
				entity.is_approach_finished = true
				entity.state_locked = false  # Unlock — Director can now transition
				_approach_min_timer = 0.0
				_approach_failsafe_timer = 0.0
				_calculated_velocity = Vector3.ZERO
				return
		
		entity.set_path_timer(entity.get_path_timer() + delta)
		if entity.get_path_timer() >= entity.path_update_interval:
			entity.set_path_timer(0.0)
			# ─── FLATTEN Y-AXIS on path update too ───────────────────────
			# Every time we refresh the path, ensure the target is at ground
			# level so the NavigationAgent3D can find a valid path.
			var flat_target = window_target.global_position
			flat_target.y = entity.global_position.y
			entity.get_nav_agent().target_position = flat_target
		
		if nav_finished:
			_calculated_velocity.x = 0.0
			_calculated_velocity.z = 0.0
		else:
			var next_pos = entity.get_nav_agent().get_next_path_position()
			var dir_2d := Vector2(next_pos.x - entity.global_position.x, next_pos.z - entity.global_position.z)
			if dir_2d.length() > 0.01:
				var move_dir_2d = dir_2d.normalized()
				_calculated_velocity.x = move_dir_2d.x * entity.current_stalk_speed
				_calculated_velocity.z = move_dir_2d.y * entity.current_stalk_speed



# ---------------------------------------------------------------------------
# STATE: WINDOW_PEEK — Standing at a window, staring inside
# ---------------------------------------------------------------------------
## The Entity stands at a window and stares inside. After a minimum siege
## duration (5 seconds), it can exit via the stare timer or transition to
## INDOOR_SEARCH if the window is unbarricaded.
func _window_peek_state(delta: float) -> void:
	# Lock the state — the Director must not override while we're mid-peek
	entity.state_locked = true
	
	_calculated_velocity = Vector3.ZERO
	
	# ─── RESET PEEK ASSESSMENT ON FRESH ENTRY ────────────────────────────
	# When the Entity first enters WINDOW_PEEK (siege timer is 0.0), reset
	# the _peek_assessment_done flag so the peek assessment runs again.
	# Without this reset, if the Entity aborted a previous peek (e.g., room
	# was lit) and later re-enters WINDOW_PEEK at a different window, the
	# stale _peek_assessment_done = true would prevent re-evaluation.
	if _siege_duration_timer <= 0.0:
		_peek_assessment_done = false
	
	_siege_duration_timer += delta
	
	# ─── NIGHT 2 BARRICADE GUARD ──────────────────────────────────────────
	# On Night 2, the Entity can peek through windows but CANNOT breach
	# boarded windows. If the window is boarded, we skip the barricade
	# damage entirely — the Entity just stares and leaves after the siege
	# timer expires. Boarded windows are immune until Night 3.
	#
	# However, if the Entity has been staring for 10+ seconds without
	# breaching, it will start trying to damage the barricade anyway.
	# This gives the player a window of safety but not infinite safety.
	#
	# NOTE: We read current_night from NightManager, NOT GameTime.
	# GameTime manages the day/night cycle (time of day), while NightManager
	# tracks which narrative night the player is on (1-5). The debug console
	# sets the night via NightManager.start_night(night), so reading from
	# NightManager ensures the debug override is respected.
	var current_night: int = 1
	var night_manager = entity.get_node_or_null("/root/NightManager")
	if night_manager and "current_night" in night_manager:
		current_night = night_manager.current_night
	
	var window_target = entity.get_current_window_target()
	
	# ─── NULL WINDOW TARGET GUARD ──────────────────────────────────────────
	# If the window target was cleared (e.g., by FLINCH completion), the
	# Entity has no window to peek at. Signal completion to the Director
	# so it transitions to OBSERVE_FROM_TREELINE. The Director will
	# re-select a window on the next confidence escalation cycle.
	if not window_target:
		entity.is_observe_finished = true
		entity.state_locked = false
		_calculated_velocity = Vector3.ZERO
		return
	
	# ─── APPROACH DEBUG LOG (every 2 seconds, continues from APPROACH_WINDOW) ──
	# Prints Entity and window coordinates every 2 seconds during WINDOW_PEEK,
	# continuing the same debug log pattern from APPROACH_WINDOW state.
	# This provides continuous coordinate tracking from window selection through
	# to breach, helping diagnose pathfinding and positioning issues.
	_approach_debug_timer += delta
	if _approach_debug_timer >= APPROACH_DEBUG_INTERVAL:
		_approach_debug_timer = 0.0
		var window_id_str: String = ""
		if window_target.has_method("get_window_id"):
			window_id_str = window_target.get_window_id()
		elif "window_id" in window_target:
			window_id_str = str(window_target.window_id)
		var entity_pos = entity.global_position
		var window_pos = window_target.global_position
		var nav_target = entity.get_nav_agent().target_position
		var nav_finished = entity.get_nav_agent().is_navigation_finished()
		print("[APPROACH DEBUG] Entity=(%.2f, %.2f, %.2f) | Window '%s'=(%.2f, %.2f, %.2f) | NavTarget=(%.2f, %.2f, %.2f) | NavFinished=%s | dist_2d=%.2f" % [
			entity_pos.x, entity_pos.y, entity_pos.z,
			window_id_str, window_pos.x, window_pos.y, window_pos.z,
			nav_target.x, nav_target.y, nav_target.z,
			nav_finished,
			Vector2(entity_pos.x, entity_pos.z).distance_to(Vector2(nav_target.x, nav_target.z))
		])
	
	# ─── BREACH TIMER: breach_delay seconds before attempting breach ─────
	# After breach_delay seconds of staring, the Entity starts trying to
	# damage the barricade (if boarded) or transitions to INDOOR_SEARCH
	# (if unboarded). This gives the player a brief window to react before
	# the Entity acts. Configurable via @export breach_delay.
	# NOTE: The @export breach_delay variable is used in place of this const.
	# The const is kept as a fallback for the initial value.
	
	# ─── DEBUG: Log every 30 frames during WINDOW_PEEK ──────────────────
	# Uses a member variable (_window_peek_debug_counter) that persists
	# across frames to throttle debug prints to every 30 frames (0.5s at
	# 60fps). This avoids console flooding while still providing enough
	# granularity to trace the siege timer progression.
	if _window_peek_debug_counter % 30 == 0:
		var is_window_boarded: bool = "is_boarded" in window_target and window_target.is_boarded
		var has_damage_method: bool = window_target.has_method("damage_barricade")
		print("[WINDOW_PEEK DEBUG] siege=%.1fs/%ds | boarded=%s | has_damage=%s | night=%d | state_locked=%s" % [
			_siege_duration_timer, breach_delay, is_window_boarded, has_damage_method, current_night, entity.state_locked])
	_window_peek_debug_counter += 1
	
	# ─── PEEK ASSESSMENT: Opportunistic Breach Logic ─────────────────────
	# During the peek, the Entity assesses the window's viability as a breach
	# point. Two conditions determine the outcome:
	#
	#   CONDITION A: The room is UNLIT (dark) AND the player is NOT visible.
	#     → OPPORTUNITY! The Entity sees a chance to breach undetected.
	#       Accelerate the siege timer drastically so the breach happens fast.
	#
	#   CONDITION B: The room is LIT OR the player IS visible looking at it.
	#     → BAD BREACH POINT! The Entity realizes it's a bad angle and aborts.
	#       Set is_observe_finished to tell the Director to fall back to
	#       OBSERVE_FROM_TREELINE and try a different angle later.
	#
	# This replaces the old static "siege timer" approach with a dynamic,
	# context-aware assessment that rewards stealth (dark rooms) and punishes
	# detection (lit rooms or direct line-of-sight).
	#
	# NOTE: We only perform this assessment once per peek session. The
	# _peek_assessment_done flag prevents re-evaluation after the first
	# decision, ensuring the Entity commits to its choice.
	if not _peek_assessment_done:
		# ─── IDENTIFY THE ROOM ──────────────────────────────────────────
		# Use RoomLightDetector to determine which room this window belongs to.
		# The window's global position is used to resolve the room name.
		var window_pos: Vector3 = window_target.global_position
		var room_detector = entity.get_node_or_null("/root/RoomLightDetector")
		var window_room_lit: bool = false
		var player_visible: bool = false
		
		if room_detector:
			window_room_lit = room_detector.is_position_in_lit_room(window_pos)
		
		# ─── CHECK IF PLAYER IS VISIBLE ────────────────────────────────
		# Use the sensory module's can_entity_see_player() to determine if
		# the player is currently visible to the Entity through this window.
		var sensory = entity.get_sensory_module()
		if sensory and sensory.has_method("can_entity_see_player"):
			player_visible = sensory.can_entity_see_player()
		
		# ─── ASSESSMENT DECISION ────────────────────────────────────────
		if not window_room_lit and not player_visible:
			# ─── OPPORTUNITY: Dark room, player not visible ─────────────
			# The Entity sees an opportunity to breach undetected.
			# Accelerate the siege timer to breach_delay + 0.1 so the
			# breach check (_siege_duration_timer >= breach_delay) passes
			# on the very next frame. The +0.1 buffer ensures the timer
			# is strictly greater than breach_delay, preventing any
			# floating-point edge case where the timer equals but doesn't
			# exceed the threshold.
			print("[WINDOW_PEEK] OPPORTUNITY! Room is DARK and player NOT visible. Accelerating breach!")
			_siege_duration_timer = breach_delay + 0.1  # Immediate breach on next frame
			_peek_assessment_done = true
		else:
			# ─── BAD BREACH POINT: Room is lit OR player is visible ─────
			# The Entity realizes this is a bad breach point. Abort!
			# Set the completion flag so the Director falls back to
			# OBSERVE_FROM_TREELINE and tries a different angle later.
			var reason: String = "room is LIT" if window_room_lit else ""
			if player_visible:
				reason += " and " if reason != "" else ""
				reason += "player IS visible"
			print("[WINDOW_PEEK] ABORT! Bad breach point (%s). Falling back to treeline observation." % reason)
			entity.is_observe_finished = true
			entity.state_locked = false
			_calculated_velocity = Vector3.ZERO
			_peek_assessment_done = true
			return
	
	# Check if the window is unbarricaded (glass-only) — if so, the Entity
	# must play the AttackWindow animation and shatter the glass at the
	# impact frame BEFORE transitioning to INDOOR_SEARCH.
	# CabinWindow uses `is_boarded` (variable) to track barricade state.
	# If is_boarded is false, the window is glass-only and can be breached.
	var is_window_boarded: bool = "is_boarded" in window_target and window_target.is_boarded
	if not is_window_boarded:
		if _siege_duration_timer >= breach_delay:
			if not _glass_shatter_pending:
				# ─── START THE ATTACK ANIMATION ──────────────────────────
				# The breach delay has expired. Instead of instantly
				# transitioning to INDOOR_SEARCH, we initiate the AttackWindow
				# animation and set a timer for the impact frame.
				# The glass shatter will be applied when the timer fires.
				_glass_shatter_pending = true
				_glass_shatter_impact_timer = glass_shatter_impact_delay
				_barricade_anim_lock = barricade_anim_lock_duration  # Force AttackWindow animation
				print("[WINDOW_PEEK DEBUG] *** GLASS SHATTER INITIATED! Playing AttackWindow animation. Impact in %.1fs." % glass_shatter_impact_delay)
			
			# ─── COUNTDOWN TO IMPACT ────────────────────────────────────
			# Decrement the impact timer each frame. When it reaches 0.0,
			# the glass shatters and we signal completion to the Director.
			if _glass_shatter_pending:
				_glass_shatter_impact_timer -= delta
				_barricade_anim_lock -= delta  # Keep anim lock in sync
				if _barricade_anim_lock < 0.0:
					_barricade_anim_lock = 0.0
				
				if _glass_shatter_impact_timer <= 0.0:
					# ─── IMPACT FRAME: Breach the target ────────────────
					_glass_shatter_pending = false
					_glass_shatter_impact_timer = 0.0
					
					# ─── SAFE TYPE-CHECK: Door vs Window Breach ──────────
					# The Entity can approach both windows (CabinWindow) and
					# doors (AnimatableBody3D with Door script). Each has a
					# different breach method:
					#   - Window: shatter_window() — destroys glass panes
					#   - Door:   break_door() — forces the door open
					# Use duck-typing (has_method) to safely dispatch to the
					# correct breach method without hard type-casting.
					if window_target.has_method("shatter_window"):
						window_target.shatter_window()
						print("[WINDOW_PEEK] Glass shattered at impact frame! Transitioning to INDOOR_SEARCH.")
					elif window_target.has_method("break_door"):
						window_target.break_door()
						print("[WINDOW_PEEK] Door forced open at impact frame! Transitioning to INDOOR_SEARCH.")
					else:
						print("[WINDOW_PEEK] WARNING: Target has no breach method! window_target=%s (class=%s)" % [window_target.name, window_target.get_class()])

					
					# ─── MARK WINDOW AS BREACHED ──────────────────────────
					# Register this window on the breach cooldown system so
					# the Entity will NOT select it for approach/breach again
					# for 60 seconds. This prevents the infinite re-breach loop.
					if window_target.has_method("get_window_id"):
						var window_id = window_target.get_window_id()
						var nav = entity.get_navigation_module()
						if nav and nav.has_method("mark_window_breached"):
							nav.mark_window_breached(window_id)
					
					# ─── RESET INDOOR SEARCH PERSISTENCE TIMER ──────────────
					# Reset the 30-second indoor search persistence timer so the
					# Director forces the Entity to stay in INDOOR_SEARCH for at
					# least 30 seconds after breaching. This prevents the
					# "Breach → Search → Give Up → Breach again" loop.
					if _director and _director.has_method("reset_indoor_search_persistence"):
						_director.reset_indoor_search_persistence()
					
					# Signal completion to the Director
					entity.is_window_unbarricaded = true
					entity.state_locked = false  # Unlock — Director can now transition
					_has_arrived_indoor = false
					return
				else:
					# Animation still playing — freeze movement and wait
					_calculated_velocity = Vector3.ZERO
					return
		else:
			if _window_peek_debug_counter % 30 == 0:
				print("[WINDOW_PEEK DEBUG] Window is unbarricaded but siege=%.1fs < %ds. Waiting..." % [_siege_duration_timer, breach_delay])
	
	# Night 2 boarded window guard: if boarded, wait for breach delay then
	# start damaging the barricade anyway (just slower).
	if current_night == 2 and is_window_boarded:
		# Boarded window on Night 2 — wait for breach delay before attacking
		if _siege_duration_timer < breach_delay:
			# Just stare — the player has a window of safety
			if _window_peek_debug_counter % 30 == 0:
				print("[WINDOW_PEEK DEBUG] Boarded window, siege=%.1fs < %ds. Staring..." % [_siege_duration_timer, breach_delay])
			pass  # Fall through to stare timer logic below
		else:
			# Breach delay has passed — start damaging the barricade
			if _window_peek_debug_counter % 30 == 0:
				print("[WINDOW_PEEK DEBUG] *** BARRICADE ATTACK! siege=%.1fs >= %ds. Damaging barricade..." % [_siege_duration_timer, breach_delay])
			_barricade_damage_timer += delta
			if _barricade_damage_timer >= barricade_damage_interval:
				_barricade_damage_timer = 0.0
				_barricade_anim_lock = barricade_anim_lock_duration
				_pending_damage_delay = pending_damage_delay
				_has_pending_damage = true
				if window_target.has_method("damage_barricade"):
					window_target.damage_barricade()
					print("[Entity AI] WINDOW_PEEK: Damaged barricade on Night 2! (siege=%.1fs)" % _siege_duration_timer)
			# Stay in WINDOW_PEEK — don't fall through to stare timer exit
			# The Entity keeps attacking until the barricade breaks or the
			# player shines the flashlight at it.
			return

	
	# Stare timer management
	if entity.get_stare_timer() >= 9990.0:
		entity.set_stare_timer(randf_range(window_peek_stare_min, window_peek_stare_max))
	
	entity.set_stare_timer(entity.get_stare_timer() - delta)
	if entity.get_stare_timer() <= 0.0 and _siege_duration_timer >= siege_min_duration:
		# ─── SIGNAL COMPLETION TO THE DIRECTOR ──────────────────────────
		# Instead of calling fade_and_relocate() directly (which would
		# bypass the Director and call request_state()), we set a Blackboard
		# completion flag. The Director will detect this flag in its next
		# evaluation cycle, call fade_and_relocate() for the setup work,
		# and transition to OBSERVE_FROM_TREELINE.
		entity.is_observe_finished = true
		entity.state_locked = false  # Unlock — Director can now transition
		_calculated_velocity = Vector3.ZERO
		return



# ---------------------------------------------------------------------------
# STATE: FLINCH — Phantom Evasion (lateral sprint into darkness)
# ---------------------------------------------------------------------------
## The Entity slides laterally into the darkness to evade the player's
## flashlight beam. Uses a smooth lerp toward a dark position (treeline
## vantage point) with visual alpha fade-out for disorienting effect.
func _flinch_state(delta: float) -> void:
	# Lock the state — the Director must not override while we're mid-flinch
	entity.state_locked = true
	
	# ─── FIRST ENTRY: Initialize the flinch ──────────────────────────────
	# The Director just transitioned to FLINCH. The flinch timer is 0.0
	# because _start_flinch() was never called. We call it now to set up
	# the lateral sprint target position and 1.5s timer.
	# This is the ONLY place _start_flinch() is called — the Director
	# handles state transitions, and the state handler handles setup.
	var timer = entity.get_flinched_timer()
	if timer <= 0.0:
		entity._start_flinch()
		timer = entity.get_flinched_timer()
		# If timer is still 0.0 after _start_flinch, something went wrong
		# (e.g., no player or camera). Signal completion immediately.
		if timer <= 0.0:
			entity.is_flinch_finished = true
			entity.state_locked = false
			_calculated_velocity = Vector3.ZERO
			return
		
		# ─── START THE VISUAL FADE ────────────────────────────────────────
		# Trigger the alpha fade tween on the monster model so the Entity
		# visually fades into darkness as it sprints laterally. This creates
		# a disorienting "phantom" effect that sells the supernatural evasion.
		# The fade takes 1.5 seconds — the same duration as the flinch sprint.
		entity._start_flinch_fade()
	
	# Decrement the flinch timer — _start_flinch() set it to 1.5 seconds.
	# When it reaches 0.0, signal completion to the Director via the
	# Blackboard completion flag.
	timer -= delta
	entity.set_flinched_timer(timer)
	
	if timer <= 0.0:
		# Flinch complete — signal completion to the Director
		entity.is_flinch_finished = true
		entity.state_locked = false  # Unlock — Director can now transition
		_calculated_velocity = Vector3.ZERO
		return
	
	# Move toward the flinch target position
	var target_pos = entity.get_flinch_target_pos()
	var dir = (target_pos - entity.global_position).normalized()
	dir.y = 0.0
	
	if dir.length() > 0.01:
		_calculated_velocity = dir * entity.current_stalk_speed * flinch_sprint_multiplier
	else:
		_calculated_velocity = Vector3.ZERO


# ---------------------------------------------------------------------------
# STATE: HARASS — Psychological harassment at a window
# ---------------------------------------------------------------------------
## The Entity stands at a window performing psychological harassment
## (breathing, tapping, rattling). No movement — purely atmospheric.
func _harass_state(delta: float) -> void:
	_calculated_velocity = Vector3.ZERO
	# Harassment sounds and animations are handled by the controller


# ─── INDOOR ROOM NAVIGATION HELPERS ──────────────────────────────────────────

## BFS (Breadth-First Search) through the INDOOR_ROOM_GRAPH to find the
## shortest path from start_room to target_room.
## Returns an Array[String] of room names in order, or an empty array if
## no path exists.
func _find_room_path(start_room: String, target_room: String) -> Array[String]:
	if start_room == target_room:
		return [start_room]
	
	var visited: Dictionary = {}
	var queue: Array = []  # Each element is [room_name, path_so_far]
	queue.append([start_room, [start_room]])
	visited[start_room] = true
	
	while queue.size() > 0:
		var entry = queue.pop_front()
		var current_room: String = entry[0]
		var path: Array = entry[1]  # Untyped Array — will be cast to Array[String] at the call site
		
		var neighbors: Array = INDOOR_ROOM_GRAPH.get(current_room, [])
		for neighbor in neighbors:
			if visited.has(neighbor):
				continue
			visited[neighbor] = true
			var new_path = path.duplicate()
			new_path.append(neighbor)
			if neighbor == target_room:
				return new_path
			queue.append([neighbor, new_path])
	
	# No path found — return empty array
	return []


## Finds the world-space position of the doorway between two adjacent rooms.
## Scans the scene for DoorwayPosition markers (children of CabinRoom nodes)
## that have the appropriate "from_room" and "to_room" metadata.
## Returns Vector3.ZERO if no doorway is found.
func _get_doorway_position(from_room: String, to_room: String) -> Vector3:
	# Search for DoorwayPosition markers in the scene
	var doorway_markers = get_tree().get_nodes_in_group("DoorwayPositions")
	for marker in doorway_markers:
		if marker.has_meta("from_room") and marker.has_meta("to_room"):
			var marker_from: String = marker.get_meta("from_room")
			var marker_to: String = marker.get_meta("to_room")
			# Check both directions (doorways are bidirectional)
			if (marker_from == from_room and marker_to == to_room) or \
			   (marker_from == to_room and marker_to == from_room):
				return marker.global_position
	
	# Fallback: no doorway marker found — return zero vector
	return Vector3.ZERO


# ---------------------------------------------------------------------------
# STATE: INDOOR_SEARCH — Entity has breached and is hunting inside the cabin
# ---------------------------------------------------------------------------
## Phase A: Vault entry animation (EnterWindow plays for 1.5s, then teleport).
## Phase B: Indoor patrol (searching for the player).
##
## ANIMATION-FIRST APPROACH:
##   When INDOOR_SEARCH begins, the Entity does NOT teleport immediately.
##   Instead, it stays at the window position and plays the "EnterWindow"
##   vault animation for ENTER_WINDOW_ANIM_DURATION (1.5 seconds). During
##   this time, _has_arrived_indoor is false, so entity_controller.gd's
##   _update_animations() forces the "EnterWindow" animation.
##
##   After the timer expires, the Entity teleports to the indoor landing
##   position, performs a floor-snap raycast to normalize its ground level,
##   and transitions to Phase B (patrol). This creates a seamless visual
##   effect of the Entity vaulting through the window frame.
func _indoor_search_state(delta: float) -> void:
	# [TRACE_BREACH] Function entered
	print("[TRACE_BREACH] _indoor_search_state() ENTERED. _has_arrived_indoor=%s, _enter_window_anim_timer=%.3f, was_door_entry=%s, state_locked=%s" % [_has_arrived_indoor, _enter_window_anim_timer, entity.was_door_entry if entity else "NO_ENTITY", entity.state_locked if entity else "NO_ENTITY"])
	
	# ─── DOOR ENTRY: Phase A (velocity-based walk to IndoorBreachWaypoint) ──
	# ─── DOOR ENTRY: THE BREACH PROTOCOL ─────────────────────────────────────
	# When the Entity enters through the front door (was_door_entry == true),
	# we use standard NavMesh pathfinding to walk through the doorway. No Ghost
	# Mode is needed — the Floating Sphere + Floor RayCast system handles Y-axis
	# elevation (stairs, threshold) automatically, and the SphereShape3D's
	# rounded shape prevents snagging on doorframe geometry.
	#
	# The Entity sets its nav target to the IndoorBreachWaypoint (just inside
	# the door) and walks there using standard 2D-flattened pathfinding. The
	# controller's move_and_slide() + Floor RayCast handles the rest.
	#
	# WINDOW ENTRIES (was_door_entry == false) are handled below in the
	# standard Phase A block (EnterWindow animation + teleport).
	if entity.was_door_entry:
		# ─── DOOR PHASE A: Walk to IndoorBreachWaypoint ────────────────────
		# The Entity walks through the doorway using standard 2D-flattened
		# NavMesh pathfinding. The controller's move_and_slide() + Floor RayCast
		# handles Y-axis elevation (stairs, threshold) automatically.
		#
		# CRITICAL: There is NO "early arrival" shortcut here. Even if the Entity
		# is already close to the IndoorBreachWaypoint (because APPROACH_WINDOW
		# Phase 2 walked it to the EntityDoorInteriorWaypoint), we ALWAYS go
		# through the standard pathfinding loop. This ensures the Breach Protocol
		# takes at least a few frames of actual movement, preventing the "instant
		# breach" bug where _has_arrived_indoor is set to true on the very first
		# frame without any visual movement through the doorway.
		#
		# The CSG threshold pop (Y+0.2 lift) is applied every frame during
		# Door Phase A to help the physics engine clear the door threshold lip.
		var door_waypoint = entity.get_current_window_target()
		
		# ─── STATE LOCK + NAV TARGET SETUP (first frame only) ─────────────
		if not entity.state_locked:
			entity.state_locked = true
			
			# ─── BREACH LOCK ──────────────────────────────────────────────
			# Set the breach lock flag to prevent the stuck detector in
			# entity_controller.gd from firing while the Entity is walking
			# toward the IndoorBreachWaypoint. The NavMesh may not cover the
			# cabin interior, making the Entity appear "stranded" even though
			# it's actively pathfinding through the doorway.
			#
			# Also set is_breach_locked on the controller so the Director's
			# evaluate_master_state() can block sensory-driven state overrides
			# (Tiers 2-8) while the Entity is mid-breach. This prevents the
			# "Sensory Interference" bug where the Entity sees the player
			# outside during Door Phase A and aborts the search.
			_breach_in_progress = true
			entity.is_breach_locked = true
			print("[TRACE_BREACH] BREACH LOCK: is_breach_locked=true, _breach_in_progress=true")

			
			# ─── SET NAV TARGET TO BREACH WAYPOINT ─────────────────────────
			# Find the IndoorBreachWaypoint from the current window target (the door)
			# and set it as the NavigationAgent3D target. The standard 2D-flattened
			# pathfinding loop below handles movement toward this waypoint.
			if door_waypoint and door_waypoint.get_parent():
				var door_node = door_waypoint.get_parent()
				var indoor_waypoint = door_node.get_node_or_null("IndoorBreachWaypoint")
				if indoor_waypoint:
					_landing_position = indoor_waypoint.global_position
					entity.get_nav_agent().target_position = _landing_position
					print("[INDOOR_SEARCH] Breach Protocol: Nav target set to IndoorBreachWaypoint at (%.2f, %.2f, %.2f)" % [_landing_position.x, _landing_position.y, _landing_position.z])
				else:
					# Fallback: no IndoorBreachWaypoint found — use cabin center
					_landing_position = entity.cabin_center
					_landing_position.y = entity.global_position.y
					entity.get_nav_agent().target_position = _landing_position
					print("[INDOOR_SEARCH] Breach Protocol: No IndoorBreachWaypoint found. Using cabin center fallback.")
			else:
				# Fallback: no door target — use cabin center
				_landing_position = entity.cabin_center
				_landing_position.y = entity.global_position.y
				entity.get_nav_agent().target_position = _landing_position
				print("[INDOOR_SEARCH] Breach Protocol: No door target found. Using cabin center fallback.")
		
		# ─── GHOST BREACH ─────────────────────────────────────────────────
		# Absolute override: No lerps, no navigation, no physics.
		# Kill physics entirely, teleport to the waypoint immediately,
		# and clear the breach lock. This bypasses the trimesh snag on the
		# threshold entirely.
		entity.velocity = Vector3.ZERO
		_calculated_velocity = Vector3.ZERO
		
		# TELEPORT to the waypoint immediately
		entity.global_position = _landing_position
		
		# Mark arrival
		_has_arrived_indoor = true
		
		# Finalize Breach
		entity.state_locked = false
		entity.was_door_entry = false
		_breach_frame_count = 0
		_breach_in_progress = false
		entity.is_breach_locked = false
		
		# ─── INDOOR SEARCH PERSISTENCE TIMER ──────────────────────────────
		# Reset the 30-second indoor search persistence timer so the Director's
		# INDOOR_SEARCH preservation guard keeps the Entity inside for at least
		# 30 seconds. Without this, the Director immediately returns
		# OBSERVE_FROM_TREELINE on the next frame, creating an infinite loop:
		#   APPROACH_WINDOW → INDOOR_SEARCH → OBSERVE → APPROACH_WINDOW → ...
		if _director and _director.has_method("reset_indoor_search_persistence"):
			_director.reset_indoor_search_persistence()
		
		# ─── DOOR BREACH TIMESTAMP ────────────────────────────────────────
		# Record the current time so the Director's Tier 7 can enforce a
		# 15-second cooldown on APPROACH_WINDOW after a successful door breach.
		# This prevents the looping bug where the Entity breaches → Director
		# sees player inside → triggers APPROACH_WINDOW again → Entity jitters.
		entity.last_door_breach_time = Time.get_ticks_msec() / 1000.0
		print("[INDOOR_SEARCH] Door breach timestamp set: %.3f" % entity.last_door_breach_time)
		
		# Force nav target to player position to begin hunt
		var player = entity.get_player()
		if player:
			entity.get_nav_agent().target_position = player.global_position
		
		print("[INDOOR_SEARCH] GHOST BREACH: Teleported to interior waypoint. Physics ignored.")
		return
	
	# ─── STATE LOCK: Prevent Director from overriding during Phase A ──
	# The EnterWindow animation must play for the full 1.5s duration
	# before the Entity teleports inside. Without this lock, the Director's
	# Tier 7 (fallback confidence) can force APPROACH_WINDOW, creating an
	# infinite WINDOW_PEEK → INDOOR_SEARCH → APPROACH_WINDOW → WINDOW_PEEK loop.
	if not _has_arrived_indoor:
		entity.state_locked = true
	
	if not _has_arrived_indoor:
		# ─── PHASE A: Vault Entry Animation ──────────────────────────────
		# On the first frame, initialize the animation timer.
		# The Entity stays at the window position and plays the EnterWindow
		# vault animation for the full duration.
		if _enter_window_anim_timer <= 0.0:
			_enter_window_anim_timer = ENTER_WINDOW_ANIM_DURATION
			
			# ─── STORE THE BREACH WINDOW ─────────────────────────────────
			# Permanently store the window the Entity is breaching so the
			# indoor retreat handler knows which window to flee back through
			# when the player shines the flashlight at the Entity inside.
			# Uses last_breached_window which persists until a different
			# window is breached.
			var window_target = entity.get_current_window_target()
			if window_target and window_target is CabinWindow:
				entity.last_breached_window = window_target
				var window_id_str: String = ""
				if window_target.has_method("get_window_id"):
					window_id_str = window_target.get_window_id()
				elif "window_id" in window_target:
					window_id_str = str(window_target.window_id)
				print("[INDOOR_SEARCH] Breach window stored in last_breached_window: %s" % window_id_str)
			
			print("[INDOOR_SEARCH] Phase A: Playing EnterWindow animation for %.1f seconds." % ENTER_WINDOW_ANIM_DURATION)
		
		# Decrement the animation timer
		_enter_window_anim_timer -= delta
		
		# Freeze movement during the vault animation — the Entity stays
		# at the window position while the animation plays out.
		_calculated_velocity = Vector3.ZERO
		
		# ─── TIMER EXPIRED: Teleport to indoor landing position ──────────
		if _enter_window_anim_timer <= 0.0:
			var window_target = entity.get_current_window_target()
			var landing_pos: Vector3
			var has_landing: bool = false
			
			if window_target and window_target.has_method("get_indoor_landing_position"):
				landing_pos = window_target.get_indoor_landing_position()
				has_landing = true
			elif window_target:
				# Fallback: estimate a position 1.5m behind the window facing inward.
				# CRITICAL: Flatten Y to ground level (0.0). The window's Y may be at
				# 5.72m (upper floor) or 0.0m (ground floor). The NavMesh is at ground
				# level, and the Entity can only pathfind on the ground floor. If we
				# keep the window's Y, the Entity would teleport to the upper floor
				# (attic) where there's no NavMesh and no valid pathfinding.
				landing_pos = window_target.global_position + window_target.global_transform.basis.z * 1.5
				landing_pos.y = 0.0  # Force ground level
				has_landing = true
			
			if has_landing:
				# ─── DEBUG: Log breach details BEFORE teleport ─────────────
				var window_id_str: String = ""
				if window_target and window_target.has_method("get_window_id"):
					window_id_str = window_target.get_window_id()
				elif window_target and "window_id" in window_target:
					window_id_str = str(window_target.window_id)
				else:
					window_id_str = "unknown"
				
				var entity_pos_before = entity.global_position
				print("==========================================================")
				print("[BREACH DEBUG] Window breached: %s" % window_id_str)
				print("[BREACH DEBUG] Window global_position: (%.2f, %.2f, %.2f)" % [window_target.global_position.x, window_target.global_position.y, window_target.global_position.z])
				print("[BREACH DEBUG] Entity position BEFORE teleport: (%.2f, %.2f, %.2f)" % [entity_pos_before.x, entity_pos_before.y, entity_pos_before.z])
				print("[BREACH DEBUG] Landing position: (%.2f, %.2f, %.2f)" % [landing_pos.x, landing_pos.y, landing_pos.z])
				
				# ─── TELEPORT TO LANDING POSITION ──────────────────────────
				entity.global_position = landing_pos
				entity.velocity = Vector3.ZERO
				
				# ─── FLOOR SNAP: Raycast downward to find the actual floor ─
				var space_state = entity.get_world_3d().direct_space_state
				var ray_params = PhysicsRayQueryParameters3D.new()
				var ray_from = landing_pos + Vector3.UP * 2.0
				var ray_to = landing_pos + Vector3.DOWN * 2.0
				ray_params.from = ray_from
				ray_params.to = ray_to
				ray_params.collision_mask = 1  # Layer 1: Cabin/floor geometry
				ray_params.exclude = [entity]
				var ray_result = space_state.intersect_ray(ray_params)
				
				if ray_result and ray_result.has("position"):
					var floor_y = ray_result.position.y
					var collision_shape = entity.get_node_or_null("CollisionShape3D")
					var center_to_feet: float = 0.5
					if collision_shape and collision_shape.shape:
						if collision_shape.shape is CapsuleShape3D:
							var capsule: CapsuleShape3D = collision_shape.shape
							center_to_feet = capsule.height * 0.5 + capsule.radius
						elif collision_shape.shape is CylinderShape3D:
							center_to_feet = collision_shape.shape.height * 0.5
						elif collision_shape.shape is BoxShape3D:
							center_to_feet = collision_shape.shape.size.y * 0.5
					entity.global_position.y = floor_y + center_to_feet
					print("[BREACH DEBUG] Floor raycast hit at Y=%.2f (center_to_feet=%.2f)" % [floor_y, center_to_feet])
				else:
					print("[BREACH DEBUG] WARNING — No floor found below landing position! Entity may float.")
				
				# ─── DEBUG: Log Entity position AFTER teleport + floor snap ─
				var entity_pos_after = entity.global_position
				print("[BREACH DEBUG] Entity position AFTER teleport: (%.2f, %.2f, %.2f)" % [entity_pos_after.x, entity_pos_after.y, entity_pos_after.z])
				print("==========================================================")
				
				entity.get_nav_agent().target_position = landing_pos
			
			# Mark Phase A as complete — the EnterWindow animation played
			# for the full 1.5s duration before the teleport.
			_has_arrived_indoor = true
			_enter_window_anim_timer = 0.0
			_calculated_velocity = Vector3.ZERO
			
			# ─── INDOOR SEARCH PERSISTENCE ─────────────────────────────────
			# The Director's _indoor_search_persistence_timer (30.0s) is the
			# single source of truth for how long the Entity must stay inside.
			# The AI module no longer makes "give up" decisions — that's the
			# Director's job. The persistence timer was already reset above
			# via _director.reset_indoor_search_persistence() (called from
			# the WINDOW_PEEK state handler when the glass shatters).
			return
		else:
			# Animation still playing — freeze movement
			_calculated_velocity = Vector3.ZERO
			return
	
	# ─── PHASE B: Room-Graph BFS Patrol ─────────────────────────────────────
	# The Entity navigates through the cabin using the INDOOR_ROOM_GRAPH and
	# DoorwayPosition markers. Instead of pathfinding directly to the player
	# (which the NavMesh may not support indoors), the Entity computes a
	# room-to-room path using BFS and navigates through doorway markers.
	#
	# FLOW:
	#   1. Every 1.0s, re-check the player's current room via RoomLightDetector
	#   2. Compute a BFS room path from the Entity's current room to the
	#      player's room using INDOOR_ROOM_GRAPH
	#   3. Navigate to the next doorway marker on the path
	#   4. When the Entity arrives at a doorway, advance to the next room
	#   5. When the Entity arrives at the player's room, switch to direct
	#      player pursuit (last resort)
	#
	# This replaces the old NavMesh-based direct player pursuit which failed
	# indoors because the cabin interior may not have NavMesh coverage.
	if _has_arrived_indoor:
		var nav = entity.get_nav_agent()
		var player = entity.get_player()
		
		# ─── CATCH CHECK ──────────────────────────────────────────────────
		# If the Entity is close enough to the player, catch them.
		# This check runs EVERY frame, regardless of navigation state,
		# so the Entity can catch the player even when standing still
		# (nav finished) right next to them.
		if player and entity.global_position.distance_to(player.global_position) <= entity.catch_distance:
			entity._on_caught_player()
			_calculated_velocity = Vector3.ZERO
			return
		
		# ─── ROOM PATH RECHECK (every 1.0s) ───────────────────────────────
		# Throttle the room path re-evaluation to avoid expensive
		# RoomLightDetector lookups every frame. Every 1.0 seconds, we
		# re-check the player's current room and recompute the BFS path.
		_room_path_recheck_timer += delta
		if _room_path_recheck_timer >= 1.0:
			_room_path_recheck_timer = 0.0
			
			# Determine the Entity's current room
			var room_detector = entity.get_node_or_null("/root/RoomLightDetector")
			var entity_room: String = ""
			var player_room: String = ""
			
			if room_detector:
				entity_room = room_detector.get_room_name_at(entity.global_position)
				if player:
					player_room = room_detector.get_room_name_at(player.global_position)
			
			# Compute BFS room path if both rooms are valid
			if entity_room != "" and player_room != "":
				_room_path = _find_room_path(entity_room, player_room) as Array[String]
				_current_room_index = 0
				
				if _room_path.size() > 0:
					print("[INDOOR_SEARCH] Room path: %s → %s (path: %s)" % [entity_room, player_room, " → ".join(_room_path)])
				else:
					print("[INDOOR_SEARCH] No room path found from '%s' to '%s'. Using direct player pursuit." % [entity_room, player_room])
		
		# ─── ROOM PATH NAVIGATION ─────────────────────────────────────────
		# If we have a valid room path with at least 2 rooms (meaning we need
		# to traverse at least one doorway), navigate toward the next doorway.
		if _room_path.size() >= 2 and _current_room_index < _room_path.size() - 1:
			var from_room = _room_path[_current_room_index]
			var to_room = _room_path[_current_room_index + 1]
			var doorway_pos = _get_doorway_position(from_room, to_room)
			
			if doorway_pos != Vector3.ZERO:
				# Set the nav target to the doorway position
				_path_timer += delta
				if _path_timer >= entity.path_update_interval:
					_path_timer = 0.0
					nav.target_position = doorway_pos
				
				# Check if we've arrived at the doorway
				var dist_to_doorway = entity.global_position.distance_to(doorway_pos)
				if dist_to_doorway <= 1.5:
					# Arrived at doorway — advance to the next room
					_current_room_index += 1
					print("[INDOOR_SEARCH] Arrived at doorway %s→%s. Advancing to room %s." % [from_room, to_room, to_room])
					
					# If we've reached the player's room, clear the room path
					# so the Entity switches to direct player pursuit
					if _current_room_index >= _room_path.size() - 1:
						_room_path = []
						_current_room_index = 0
						print("[INDOOR_SEARCH] Reached player's room. Switching to direct pursuit.")
				
				# Move toward the doorway
				if nav.is_navigation_finished():
					# NavMesh finished but we haven't arrived — use direct movement
					var dir_to_doorway = (doorway_pos - entity.global_position)
					dir_to_doorway.y = 0.0
					if dir_to_doorway.length() > 0.01:
						var move_dir = dir_to_doorway.normalized()
						_calculated_velocity.x = move_dir.x * entity.current_stalk_speed
						_calculated_velocity.z = move_dir.z * entity.current_stalk_speed
					else:
						_calculated_velocity = Vector3.ZERO
				else:
					var next_pos = nav.get_next_path_position()
					var dir_2d := Vector2(next_pos.x - entity.global_position.x, next_pos.z - entity.global_position.z)
					if dir_2d.length() > 0.01:
						var move_dir_2d = dir_2d.normalized()
						_calculated_velocity.x = move_dir_2d.x * entity.current_stalk_speed
						_calculated_velocity.z = move_dir_2d.y * entity.current_stalk_speed
					else:
						_calculated_velocity = Vector3.ZERO
				return
		
		# ─── DIRECT PLAYER PURSUIT (fallback) ─────────────────────────────
		# If no room path is available (e.g., Entity and player are in the
		# same room, or the room detector failed), fall back to direct
		# NavMesh-based pursuit toward the player's position.
		if player:
			_path_timer += delta
			if _path_timer >= entity.path_update_interval:
				_path_timer = 0.0
				nav.target_position = player.global_position
			
			if nav.is_navigation_finished():
				_calculated_velocity = Vector3.ZERO
			else:
				var next_pos = nav.get_next_path_position()
				var dir_2d := Vector2(next_pos.x - entity.global_position.x, next_pos.z - entity.global_position.z)
				if dir_2d.length() > 0.01:
					var move_dir_2d = dir_2d.normalized()
					_calculated_velocity.x = move_dir_2d.x * entity.current_stalk_speed
					_calculated_velocity.z = move_dir_2d.y * entity.current_stalk_speed
				else:
					_calculated_velocity = Vector3.ZERO
		else:
			_calculated_velocity = Vector3.ZERO

# ---------------------------------------------------------------------------
# STATE: CLIMB_WALL_UP — Exterior wall climbing UP to a second-story window
# ---------------------------------------------------------------------------
## Phase 1: Pathfinding to the base of the wall.
## Phase 2: Vertical ascent (Y-axis movement) toward the target window.
func _climb_wall_up_state(delta: float) -> void:
	# Lock the state — the Director must not override while we're mid-climb
	entity.state_locked = true
	
	if not _wall_climb_phase_2:
		# Phase 1: Pathfind to wall base
		var wall_base = entity.get_node_or_null("WallBasePosition")
		if wall_base:
			entity.get_nav_agent().target_position = wall_base.global_position
			var dist_to_wall_base: float = entity.global_position.distance_to(wall_base.global_position)
			var nav_finished = entity.get_nav_agent().is_navigation_finished()
			# ─── ARRIVAL CHECK: Distance threshold OR navigation finished ──
			# The NavMesh may not reach the exact wall base coordinate (e.g.,
			# the cabin wall blocks further pathfinding). Use a 3.0m tolerance
			# to gracefully finish Phase 1 even if the raw target is unreachable.
			if nav_finished or dist_to_wall_base <= 3.0:
				_wall_climb_phase_2 = true
				_wall_climb_target_y = entity.global_position.y + wall_climb_height
				_calculated_velocity = Vector3.ZERO
				return
			var next_pos = entity.get_nav_agent().get_next_path_position()
			var dir_2d := Vector2(next_pos.x - entity.global_position.x, next_pos.z - entity.global_position.z)
			if dir_2d.length() > 0.01:
				var move_dir_2d = dir_2d.normalized()
				_calculated_velocity.x = move_dir_2d.x * entity.current_stalk_speed
				_calculated_velocity.z = move_dir_2d.y * entity.current_stalk_speed
		else:
			# ─── NO WALL BASE NODE: Signal completion to break the loop ──
			entity.is_climb_finished = true
			entity.state_locked = false
			_wall_climb_phase_2 = false
			_calculated_velocity = Vector3.ZERO
			return
	else:
		# Phase 2: Vertical ascent
		if entity.global_position.y < _wall_climb_target_y:
			_calculated_velocity = Vector3(0.0, entity.current_stalk_speed * wall_climb_speed_multiplier, 0.0)
		else:
			# Climb complete — signal completion to the Director
			entity.is_climb_finished = true
			entity.state_locked = false  # Unlock — Director can now transition
			_calculated_velocity = Vector3.ZERO
			_wall_climb_phase_2 = false
			_siege_duration_timer = 0.0


# ---------------------------------------------------------------------------
# STATE: CLIMB_WALL_DOWN — Exterior wall climbing DOWN from a second-story window
# ---------------------------------------------------------------------------
## Phase 1: Vertical descent (Y-axis movement) from the window position.
## Phase 2: Pathfinding away from the wall base after landing.
func _climb_wall_down_state(delta: float) -> void:
	# Lock the state — the Director must not override while we're mid-climb
	entity.state_locked = true
	
	if not _wall_climb_phase_2:
		# Phase 1: Vertical descent
		var ground_y = 0.0  # Ground level
		if entity.global_position.y > ground_y + 0.5:
			# Descend at the same speed as ascent
			_calculated_velocity = Vector3(0.0, -entity.current_stalk_speed * wall_climb_speed_multiplier, 0.0)
			return
		else:
			# Reached ground — advance to Phase 2
			_wall_climb_phase_2 = true
			_calculated_velocity = Vector3.ZERO
			return
	else:
		# Phase 2: Pathfind away from the wall to a treeline vantage point
		if not _retreat_target_set:
			_retreat_target_set = true
			var treeline_markers: Array[Node] = entity.get_tree().get_nodes_in_group("Treeline_Vantage_Points")
			if not treeline_markers.is_empty():
				var farthest_marker: Node3D = treeline_markers[0] as Node3D
				var farthest_dist: float = 0.0
				for marker in treeline_markers:
					var m: Node3D = marker as Node3D
					if m:
						var d: float = entity.global_position.distance_to(m.global_position)
						if d > farthest_dist:
							farthest_dist = d
							farthest_marker = m
				entity.get_nav_agent().target_position = farthest_marker.global_position
			else:
				entity.get_nav_agent().target_position = Vector3(9.0, 0.0, 40.0)
		
		if entity.get_nav_agent().is_navigation_finished():
			# Arrived at retreat target — signal completion
			entity.is_climb_finished = true
			entity.state_locked = false
			_retreat_target_set = false
			_wall_climb_phase_2 = false
			_calculated_velocity = Vector3.ZERO
		else:
			var next_pos = entity.get_nav_agent().get_next_path_position()
			var dir_2d := Vector2(next_pos.x - entity.global_position.x, next_pos.z - entity.global_position.z)
			if dir_2d.length() > 0.01:
				var move_dir_2d = dir_2d.normalized()
				_calculated_velocity.x = move_dir_2d.x * entity.current_stalk_speed
				_calculated_velocity.z = move_dir_2d.y * entity.current_stalk_speed
