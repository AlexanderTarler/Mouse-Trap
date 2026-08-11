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
## ─── CONFIGURATION ─────────────────────────────────────────────────────────
## Tuning knobs are loaded from entity_config.tres (a centralized Resource).
## Local variable declarations below serve as the bridge — they are initialized
## with default values, then overwritten from config.tres at setup() time.
## See resources/entity_config.tres for the canonical source of truth.
##
## Usage: config.charge_speed_multiplier instead of charge_speed_multiplier
##
## Config resource path — loads from the .tres file once in setup().
const CONFIG_PATH: String = "res://resources/entity_config.tres"
var config: Resource = null

# ─── CONFIG ALIAS BRIDGE (read from config.tres after setup) ──────────────
# These local aliases let the existing ~3000 lines of state handler code
# continue reading tuning variables directly (e.g. charge_speed_multiplier)
# while the canonical values live in entity_config.tres. Phase 2 will
# refactor handlers to use config.X directly, eliminating these aliases.

# Animation
var enter_window_anim_duration: float = 1.5
var glass_shatter_impact_delay: float = 1.5

# Approach
var approach_min_duration: float = 2.0
var approach_failsafe_timeout: float = 8.0
var approach_debug_interval: float = 2.0
var approach_arrival_distance: float = 4.0

# ─── TASK 1.1: STUN-LOCK FIX STATE ─────────────────────────────────────
## Cooldown (in seconds) after FLINCH completion during which the Entity
## cannot re-enter APPROACH_WINDOW. Prevents the 1-frame approach → flinch
## oscillation caused by stale is_illuminated / is_overcharged booleans that
## are never cleared by the FLINCH handler.
var _flinch_exit_cooldown: float = 0.0

## Duration (in seconds) of the post-flinch re-entry cooldown.
## ISSUE 3 FIX: Raised from 3 frames (50ms) to 0.5s so the perception system
## has ample time to re-detect the player's overcharge beam before the Entity
## is allowed to re-enter APPROACH_WINDOW. The old 50ms window was shorter
## than the perception update interval, causing the Entity to occasionally
## "ignore" the overcharge beam on re-entry.
const FLINCH_EXIT_COOLDOWN_DURATION: float = 0.5

# ─── TASK 1.2: INTERRUPTED WINDOW BAN ─────────────────────────────────────
## Room ID of the window the Entity was interrupted at by an overcharged
## flashlight (FLINCH entry during APPROACH_WINDOW / WINDOW_PEEK). While set,
## windows belonging to this room are heavily penalized by pick_tactical_window()
## so the Entity cannot re-target the same room. Cleared when a window in a
## different room is successfully targeted.
var _banned_room: String = ""

# Door
var door_phase_2_arrival_distance: float = 0.5
var door_phase_2_failsafe_timeout: float = 5.0
var interaction_radius: float = 2.5

# Breach
var breach_delay: float = 5.0
var max_recent_windows: int = 3

# Siege
var siege_min_duration: float = 5.0
var siege_max_duration: float = 30.0

# Barricade
var barricade_damage_interval: float = 2.0
var barricade_anim_lock_duration: float = 1.5
var pending_damage_delay: float = 0.6

# Desperation
var desperation_threshold: float = 45.0
var desperation_modifier_rate: float = 0.5

# Speed multipliers
var charge_speed_multiplier: float = 3.0
var flinch_sprint_multiplier: float = 1.5
var indoor_retreat_sprint_multiplier: float = 1.5

# Flinch
var flinch_duration: float = 4.0
var flinch_distance: float = 8.0

# Lamp / Fuse
var lamp_attack_interval: float = 3.0
var lamp_attack_range: float = 3.0
var fuse_sabotage_interval: float = 2.0
var fuse_sabotage_range: float = 2.5
var fuse_sabotage_stuck_timeout: float = 4.0

# Window peek
var window_peek_stare_min: float = 8.0
var window_peek_stare_max: float = 15.0

# Observe wait
var observe_wait_high_min: float = 2.0
var observe_wait_high_max: float = 4.5
var observe_wait_low_min: float = 4.0
var observe_wait_low_max: float = 8.0

# Retreat
var retreat_teleport_distance: float = 2.0

# Stare
var stare_grace_threshold: float = 0.5
var anti_flap_cooldown_duration: float = 0.5

# Confidence
var flinch_confidence_penalty: float = 20.0
var indoor_retreat_confidence: float = 20.0
var confidence_approach_threshold: float = 40.0
var charge_stare_threshold: float = 1.5
var stare_break_confidence_boost: float = 8.0
var stare_confidence_drain: float = 2.0

# STALK behavior
var stalk_min_distance: float = 3.0
var stalk_max_distance: float = 10.0
## TUNED: Raised from 0.3 to 0.85. At close range (0-3m) the Entity now moves
## at ~85% speed (5.1 m/s at the 6.0 base) — still slightly faster than the
## player's 3.5 m/s walk, so the player can no longer casually walk away.
## The old 0.3 dropped the Entity to 1.8 m/s (half the player's walk), which
## let players escape without sprinting.
var stalk_close_speed_mult: float = 0.85
var flanking_enabled: bool = true
var flank_interval: float = 8.0
var flank_offset_distance: float = 8.0
## TUNED: Raised from 0.5 to 0.9. When LOS breaks for 1s+, the Entity drops
## to 90% speed (5.4 m/s) instead of 50% (2.4 m/s — below the player's walk).
## This keeps the search slowdown meaningful without letting a walk-away escape.
var stalk_search_speed_mult: float = 0.9

# Utility scorer
var window_recency_penalty: float = 30.0
var room_avoidance_penalty: float = 500.0

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
	STUNNED,                # Entity is paralyzed by the porch light overload trap
	ENRAGED,                # Blackout release — permanent 1.5x speed boost for rest of night
	ATTACK_LAMP,            # Entity is physically approaching and striking the portable high-voltage lamp
	HARASS,                 # Entity stands at a window performing psychological harassment (breathing, tapping, rattling)
	FUSE_SABOTAGE,          # Entity is physically approaching and striking the Fuse Box to break it (frustration-based)
	SABOTAGE_FUSE,          # Entity pathfinds to EntityFuseWaypoint and breaks the Fuse Box (door-prerequisite)
	ENTER_THROUGH_DOOR,     # Entity walks to the front door, opens it, and enters the cabin
}

# PERFORMANCE: Cached State names array — avoids per-frame heap allocations from State.keys()
var _state_names_cache: Array = []
func _get_state_name(state: int) -> String:
	if _state_names_cache.is_empty():
		_state_names_cache = State.keys()
	return _state_names_cache[state] if state < _state_names_cache.size() else "UNKNOWN"

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
	State.SABOTAGE_FUSE,
	State.ATTACK_LAMP,
]

var entity: CharacterBody3D = null

## The Master Behavior Director — the SINGLE source of truth for state transitions.
## NO script is allowed to call set_state() except this Director.
## External scripts may ONLY write data to the Entity's Blackboard.
var _director = null  # EntityDirector — typed via setup() to avoid cyclic preload

# PERFORMANCE: Cached autoload references (avoid per-frame get_node_or_null traversal)
@onready var night_manager: Node = get_node_or_null("/root/NightManager")

# ─── PERFORMANCE: has_method() capability cache ─────────────────────────────
# Pre-computed booleans for duck-typing checks that would otherwise call
# has_method() dozens of times per frame. Initialized once in _ready().
# This eliminates ~48 per-frame method name hash lookups.
var _director_can_reset_indoor: bool = false
var _cap_nav_pick_vantage: bool = false
var _cap_nav_get_player_room: bool = false
var _cap_nav_is_lit_room: bool = false
var _cap_nav_pick_tactical: bool = false
var _cap_nav_get_window_markers: bool = false
var _cap_sensory_can_see: bool = false
var _cap_sensory_get_heard_room: bool = false
var _cap_sensory_is_looking_window: bool = false
var _cap_fuse_take_damage: bool = false
var _cap_door_interact: bool = false
var _cap_entity_collision_shape: bool = false
var _cap_hall_light_toggle: bool = false
var _cap_hall_light_generator: bool = false

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
## Prevents the stuck detector in entity_controller.gd from firing while the
## Entity is walking toward the IndoorBreachWaypoint. The NavMesh may not
## cover the cabin interior, making the Entity appear "stranded" even
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

## ─── INDOOR ROOM GRAPH (single-story, flat layout) ───────────────────────
## Adjacency graph of all cabin rooms. Used by BFS pathfinding to compute the
## shortest room-to-room path during INDOOR_SEARCH Phase B.
const INDOOR_ROOM_GRAPH: Dictionary = {
	"HallRoom": ["LivingRoom"],
	"LivingRoom": ["HallRoom", "ComputerRoom"],
	"ComputerRoom": ["LivingRoom"],
}

## ─── VALID INDOOR CABIN ROOMS ──────────────────────────────────────────────
## The set of room names that count as "inside the cabin" for breach validation.
## The Entity is only considered to have successfully breached if it ends up
## in one of these rooms after the door/window breach sequence completes.
const VALID_INDOOR_ROOMS: Array[String] = ["HallRoom", "LivingRoom", "ComputerRoom"]

## Returns true if the given world position is inside a valid cabin room
## (HallRoom, LivingRoom, or ComputerRoom) as determined by the
## RoomLightDetector's Cabin_Interior Area3D containment check.
## Returns false if the position is outside or in an unrecognized room.
func _is_position_inside_cabin(pos: Vector3) -> bool:
	var room_name = RoomLightDetector.get_room_name_at(pos)
	return room_name in VALID_INDOOR_ROOMS

## Returns a known-safe interior fallback position for the Entity to teleport to
## when a breach failsafe fires and the Entity is still outside. Returns the
## IndoorBreachWaypoint position if available, otherwise a hardcoded cabin center.
func _get_fallback_indoor_position() -> Vector3:
	var breach_wp = entity.get_door_breach_waypoint()
	if breach_wp:
		return breach_wp.global_position
	# Last resort: hardcoded cabin interior center
	entity.push_error("CRITICAL: No IndoorBreachWaypoint found! Teleporting to hardcoded fallback.")
	return Vector3(0.0, 0.0, 14.88)

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

## The total duration of the current FLINCH sprint (randomized 6-8s).
## Set when the flinch timer is initialized. Used to compute elapsed time
## for the early-abort guard — a hardcoded 8.0 would incorrectly report
## elapsed > 1.5s on frame 1 when the duration was rolled as 6.0s.
var _flinch_total_duration: float = 0.0

## ─── NIGHT 2.2 VAN SEQUENCE FLINCH → DORMANT ─────────────────────────────
## Armed by _evaluate_night_rules() when the car-alarm sequence is active and
## the player is inside the cabin. When the current FLINCH completes, the
## handler checks this flag and hard-overrides the state to DORMANT (hiding
## the Entity completely). Reset to false once consumed.
var _van_sequence_flinch_armed: bool = false

## Whether a retreat target has been set for physical RETREAT pathfinding.
## Reset after the Entity reaches the exit point and fades out.
var _retreat_target_set: bool = false

## Guard flag for the STALK state's target_desired_distance assignment.
var _stalk_target_distance_set: bool = false

## Navigation hysteresis band to smooth is_navigation_finished() oscillation.
var _nav_has_arrived: bool = false
const NAV_ARRIVE_DISTANCE: float = 1.3
const NAV_DEPART_DISTANCE: float = 2.0

func _check_nav_arrived(entity_node: CharacterBody3D) -> bool:
	var agent = entity_node.get_nav_agent() if entity_node.has_method("get_nav_agent") else null
	if not agent:
		return true
	var dist_to_target = entity_node.global_position.distance_to(agent.target_position)
	if not _nav_has_arrived:
		if dist_to_target <= NAV_ARRIVE_DISTANCE:
			_nav_has_arrived = true
			return true
		return false
	else:
		if dist_to_target > NAV_DEPART_DISTANCE:
			_nav_has_arrived = false
			return false
		return true

## STALK state: timer counting toward the next flank maneuver.
var _stalk_flank_timer: float = 0.0

## STALK state: whether a flank maneuver is currently active.
var _stalk_is_flanking: bool = false

## STALK state: the flank waypoint the Entity is pathing toward.
var _stalk_flank_target: Vector3 = Vector3.ZERO

## STALK state: LOS break timer. Accumulates delta when player is not visible.
## When this exceeds a threshold, speed is reduced to stalk_search_speed.
var _stalk_los_break_timer: float = 0.0

## STALK state: duration (seconds) of LOS break before speed reduction kicks in.
const STALK_LOS_BREAK_THRESHOLD: float = 1.0

## STALK state: current speed multiplier (computed each frame from distance + LOS state).
var _stalk_current_speed_mult: float = 1.0

## ─── TASK 4: STALK TIME-BASED ACCELERATION ──────────────────────────────
## Tracks how long the Entity has been continuously STALKing. Resets to 0.0
## when the Entity exits STALK for any reason. After the grace period (10s),
## the Entity's movement speed begins ramping toward the 200% cap.
var _stalk_duration_timer: float = 0.0

## Current acceleration multiplier applied to STALK speed (1.0 = base,
## 2.0 = 200% cap). Ramps linearly from 1.0 to 2.0 over
## STALK_ACCEL_RAMP_TIME seconds after the grace period expires.
var _stalk_accel_mult: float = 1.0

## Seconds of continuous STALK before acceleration begins.
## TUNED: Reduced from 10.0 to 3.0 — acceleration now kicks in quickly.
const STALK_ACCEL_GRACE_PERIOD: float = 3.0

## Seconds from the grace-period end to the 200% speed cap.
## TUNED: Reduced from 15.0 to 10.0 — the Entity ramps to 200% in 10 seconds
## (reaching the cap at 13s of continuous STALK), then holds 200% until exit.
const STALK_ACCEL_RAMP_TIME: float = 10.0

## Hard cap for the acceleration multiplier (200% of base speed).
const STALK_ACCEL_CAP: float = 2.0

## ─── TASK 5: STALK RUBBERBAND COOLDOWN ─────────────────────────────────
## Minimum seconds between rubberband teleports. Prevents the Entity from
## teleporting every frame while the player stays beyond 40m.
const STALK_RUBBERBAND_COOLDOWN: float = 3.0
var _stalk_rubberband_cooldown_timer: float = 0.0

## ─── STALK FREEZE FIX: RUBBERBAND NAV GRACE PERIOD ─────────────────────
## Godot's NavigationAgent3D computes paths asynchronously. After a
## rubberband teleport we re-target the NavAgent; is_navigation_finished()
## returns TRUE for a few frames until the new path is computed, which
## zeroes the velocity and causes a micro-freeze. This grace timer prevents
## is_navigation_finished() from being evaluated for 0.3s after a teleport.
var _stalk_rubberband_nav_grace: float = 0.0
const STALK_RUBBERBAND_NAV_GRACE_TIME: float = 0.3

## ─── STALK FREEZE FIX: STALK NAV GRACE PERIOD (async path) ─────────────
## The SAME async problem as rubberbanding also affects EVERY path update
## in STALK. When target_position is (re)assigned, the NavAgent computes
## paths asynchronously and is_navigation_finished() returns true for a
## few frames until the route is ready. The movement block interprets
## "no path yet" as "arrived" and zeroes the velocity — freezing the
## Entity in place during pursuit. Armed to STALK_NAV_GRACE on STALK
## entry (target distance set) and on every path-update tick.
var _stalk_nav_grace: float = 0.0
const STALK_NAV_GRACE_TIME: float = 0.35

## Debug frame counter for INDOOR_SEARCH Phase B logging.
## Incremented each frame in _indoor_search_state(). Used to throttle debug
## prints to every 30 frames (~0.5s at 60fps) to avoid console flooding.
var _indoor_search_debug_counter: int = 0

## Timer for Y-coordinate comparison debugging during INDOOR_SEARCH.
## Decremented by delta each frame. When <= 0.0, prints Entity Y vs Player Y
## and resets to 1.0 (1Hz throttle). Only fires when the Entity is physically
## inside the cabin (is_physically_inside() returns true).
var _y_debug_timer: float = 0.0

## Charge countdown timer for the STANDOFF state.
## Accumulates delta while the player holds the flashlight beam on the Entity.
## When it reaches 1.5 seconds (or 0.75s if confidence > THRESHOLD_CLIMAX),
## the Entity transitions to CHARGE.
## Reset to 0.0 if the player breaks line of sight or turns off the flashlight.
var _charge_countdown: float = 0.0

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

## ─── BUG 1/2 FIX: DIRECT INTERIOR MOVEMENT TARGET ────────────────────────────
## The world-space position the Entity moves DIRECTLY toward during
## INDOOR_SEARCH Phase B and indoor RETREAT. The cabin interior is NOT
## covered by the NavMesh (documented limitation), so the NavigationAgent
## snaps both the Entity and the target to the nearest OUTDOOR NavMesh
## points, producing a path that routes OUT through the front door and back
## in — the "doorway detour" bug. Since the Entity ignores cabin wall
## collisions while inside (collision mask = Player only), a straight line
## to the target is always valid. Vector3.ZERO means "no direct target —
## fall back to legacy NavAgent following."
var _indoor_direct_target: Vector3 = Vector3.ZERO

## Throttle timer for re-checking the player's current room during indoor search.
## Updated every 1.0 seconds to avoid expensive RoomLightDetector lookups.
var _room_path_recheck_timer: float = 0.0

## Director evaluation throttle timer (in seconds).
## Accumulates delta each frame. When >= DIRECTOR_EVAL_INTERVAL, the Director's
## evaluate_master_state() is called and the timer resets to 0.0.
## This throttles the full 8-tier Director evaluation from 60+ Hz to ~5 Hz,
## reducing CPU spikes from raycasting and sensory checks without affecting
## the smoothness of state handler movement (which runs every physics frame).
const DIRECTOR_EVAL_INTERVAL: float = 0.2
var _director_eval_timer: float = 0.0

## Cached intended state from the Director's last evaluation cycle.
## The Director evaluates evaluate_master_state() every DIRECTOR_EVAL_INTERVAL
## seconds (0.2s). Between evaluations, _cached_intended_state is used for
## state transitions instead of calling the Director every frame.
## This ensures the state dispatcher always has the latest valid state,
## even when the Director is not actively re-evaluating.
var _cached_intended_state: int = -1

## Pathfinding throttle timer (in seconds).
## Accumulates delta each frame. When <= 0.0, the next target_position update
## is allowed. After updating, the timer is reset to PATH_UPDATE_INTERVAL.
## This prevents calling NavigationAgent3D.target_position = ... every physics
## frame, which causes FPS drops due to path recalculation overhead.
var _path_timer: float = 0.0

## Stuck timer for SABOTAGE_FUSE state. Accumulates delta while the Entity is
## within 5m of the EntityFuseWaypoint but hasn't reached the 2.5m arrival
## threshold. If this timer exceeds fuse_sabotage_stuck_timeout (4.0s), the
## Entity teleports directly to the waypoint to prevent soft-locks from
## geometry blocking (e.g., crates blocking the last 0.07m of the path).
var _sabotage_stuck_timer: float = 0.0

## ─── BUG 3 FIX: DISTANCE-LATCHED STUCK DETECTION ───────────────────────────
## The previous velocity-based stuck detection failed when the Entity
## oscillated against a NavMesh edge: it jitters back and forth with non-zero
## velocity, so the stuck timer never accumulated and the Entity was paralyzed
## forever. These variables track distance-to-waypoint over time instead,
## plus a global failsafe that covers ALL branches.
var _sabotage_last_dist: float = 0.0          # distance at last check interval
var _sabotage_dist_check_timer: float = 0.0   # accumulates toward the check interval
var _sabotage_elapsed: float = 0.0            # total time spent in SABOTAGE_FUSE

## ─── FIX 5: SELF-CONTAINED FRESH-ENTRY SNAPSHOT ─────────────────────────
## The state value that last (successfully) called _sabotage_fuse_state().
## Previously this handler relied on entity.get_previous_state() to detect
## a fresh entry — but _last_state in entity_controller.gd was NEVER updated
## by set_state(), so get_previous_state() returned DORMANT for the entire
## game lifetime and the `if entity.get_state() != entity.get_previous_state()`
## check evaluated TRUE every frame, resetting the stuck trackers to 0.0
## every frame. Neither the 4s stuck timeout NOR the 15s global failsafe
## could ever fire → a NavAgent that couldn't path deadlocked the Entity
## forever (total paralysis). This snapshot is self-contained inside the AI
## module and does not depend on external state tracking at all.
var _last_sabotage_call_state: int = -1

## How often (seconds) to compare the current distance to the latched
## distance for progress detection.
const SABOTAGE_PROGRESS_CHECK_INTERVAL: float = 2.0

## Minimum distance DECREASE (meters) required over each check interval to
## consider the Entity "making progress" toward the waypoint.
const SABOTAGE_PROGRESS_EPSILON: float = 0.5

## Global failsafe: if the Entity remains in SABOTAGE_FUSE for this many
## seconds without completing, force-teleport to the waypoint and break the
## fuse box. Covers ALL branches (including the no-waypoint fallback that
## previously had no stuck timeout at all).
const SABOTAGE_GLOBAL_FAILSAFE: float = 15.0

## ─── FIX 3: NAVAGENT FRAME-1 GRACE PERIOD ──────────────────────────────
## Godot 4's NavigationAgent3D computes paths ASYNCHRONOUSLY on the physics
## frame. On the very first frame after setting target_position, the agent
## has no path loaded and is_navigation_finished() returns true — which the
## movement code interprets as "arrived" and zeroes the velocity. Combined
## with the (previously unconditional) state_locked = true, this deadlocked
## the Entity in place: velocity zeroed every frame, and neither the stuck
## timeout nor the global failsafe could fire. This grace timer prevents
## is_navigation_finished() from being evaluated for the first few frames
## after a target update, giving the agent time to compute its path.
var _sabotage_nav_grace_timer: float = 0.0

## How long (seconds) to keep the grace period active after setting a new
## NavigationAgent3D target. Slightly longer than one physics frame to
## accommodate async path computation on slower machines.
const SABOTAGE_NAV_GRACE: float = 0.35

## Minimum interval (in seconds) between NavigationAgent3D target_position updates.
## Setting target_position triggers a path recalculation which is expensive.
## Throttling to 300ms reduces pathfinding overhead by ~95% while maintaining
## responsive pursuit behavior.
const PATH_UPDATE_INTERVAL: float = 0.3

func setup(parent: CharacterBody3D) -> void:
	entity = parent
	
	# ─── LOAD CONFIG FROM RESOURCE ───────────────────────────────────
	# Load the centralized tuning configuration from entity_config.tres.
	# All @export variables that were previously defined in this file have
	# been migrated to the config resource for single-point-of-truth tuning.
	# The code below creates local aliases that read from config at runtime,
	# so existing state handler code (thousands of lines) continues to work
	# unchanged while all tuning values come from the centralized .tres.
	#
	# Usage: config.charge_speed_multiplier instead of charge_speed_multiplier
	# To add a new tuning variable: add @export to entity_config.gd, then
	# add an alias below.
	var loaded_config = load(CONFIG_PATH)
	if loaded_config:
		config = loaded_config
		print("[Entity AI] Configuration loaded from ", CONFIG_PATH)
	else:
		push_error("[Entity AI] CRITICAL: Failed to load config from ", CONFIG_PATH, "! Using hardcoded fallbacks.")
	
	# ─── CONFIG ALIAS BRIDGE ────────────────────────────────────────
	# These aliases preserve backwards compatibility with the existing
	# ~3000 lines of state handler code that references variables like
	# charge_speed_multiplier, stalk_min_distance, etc. directly.
	# This is a NON-BREAKING migration — the .tres file is the canonical
	# source of truth, and local variables are just typed aliases.
	# Phase 2 of this migration will refactor the handlers to use config.X
	# directly, eliminating these aliases.
	
	# Initialize the Master Behavior Director
	# Use load() instead of preload() to avoid cyclic dependency with entity_director.gd
	# (entity_director.gd preloads entity_ai.gd, so entity_ai.gd cannot preload entity_director.gd)
	var DirectorClass = load("res://scripts/entity/entity_director.gd")
	if DirectorClass:
		_director = DirectorClass.new()
		if _director:
			print("[Entity AI] Master Behavior Director initialized.")
	
	# ─── PERFORMANCE: Pre-compute has_method() capability cache ────────
	# Cache whether specific methods exist on key modules, so the ~48
	# per-frame duck-typing checks become simple boolean reads instead
	# of method-name hash lookups and virtual dispatch.
	if _director:
		_director_can_reset_indoor = _director.has_method("reset_indoor_search_persistence")
	if entity:
		_cap_entity_collision_shape = entity.has_method("get_collision_shape")
	var nav = entity.get_node_or_null("EntityNavigation") if entity else null
	if nav:
		_cap_nav_pick_vantage = nav.has_method("pick_next_vantage_point")
		_cap_nav_get_player_room = nav.has_method("get_player_room")
		_cap_nav_is_lit_room = nav.has_method("is_player_in_lit_room")
		_cap_nav_pick_tactical = nav.has_method("pick_tactical_window")
		_cap_nav_get_window_markers = nav.has_method("get_window_markers")
	var sensory = entity.get_node_or_null("EntitySensory") if entity else null
	if sensory:
		_cap_sensory_can_see = sensory.has_method("can_entity_see_player")
		_cap_sensory_get_heard_room = sensory.has_method("get_last_heard_room")
		_cap_sensory_is_looking_window = sensory.has_method("is_player_looking_at_window")
	# Cache door/fuse methods
	# NOTE: Window capability caching (_cap_window_shatter, etc.) has been REMOVED.
	# The old cache sampled only the first WindowMarker in the group, which could
	# be a non-CabinWindow node (e.g., a Door marker mistakenly added to the group).
	# Instead, state handlers now use direct `is CabinWindow` and `has_method()` checks
	# on the actual target_node at runtime. This is safer and more reliable.
	var door_node = entity.get_node_or_null("../NavigationRegion3D/Cabin/Door") if entity else null
	if door_node:
		_cap_door_interact = door_node.has_method("interact")
	# Cache hall light methods
	_cap_hall_light_toggle = false
	_cap_hall_light_generator = false
	# Cache fuse box methods
	if _director and _director.has_method("get_fuse_box"):
		var fuse_box = _director.get_fuse_box()
		if fuse_box:
			_cap_fuse_take_damage = fuse_box.has_method("take_damage")


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


## Public passthrough to the Director's reset_indoor_search_persistence().
## Called by entity_controller.gd's ghost motor arrival to prime the
## indoor search persistence timer BEFORE the next frame's Director
## evaluation. Without this, the persistence timer is 0.0 when the
## Director evaluates, causing it to fall through to OBSERVE_FROM_TREELINE.
func reset_indoor_search_persistence() -> void:
	if _director and _director.has_method("reset_indoor_search_persistence"):
		_director.reset_indoor_search_persistence()

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
		# ─── FIX 2: RESET CACHED STATE ON STATE CHANGE ────────────────
		# When the Entity transitions to a new state (e.g., FLINCH → OBSERVE),
		# the _cached_intended_state from the Director's previous evaluation
		# may still hold the OLD evaluation result (e.g., APPROACH_WINDOW).
		# If the Director throttle timer hasn't fired yet, the stale cache
		# would be applied, causing a one-frame state reversion. Reset to -1
		# so the next frame forces an immediate Director evaluation.
		if entity.get_state() != entity.get_previous_state():
			_cached_intended_state = -1
		
		# ─── DIRECTOR EVALUATION THROTTLE ────────────────────────────
		# The Director evaluates evaluate_master_state() at a throttled
		# rate (every DIRECTOR_EVAL_INTERVAL = 0.2s ≈ 5 Hz) instead of
		# every physics frame (60+ Hz). This reduces CPU spikes from
		# raycasting, sensory checks, and room queries.
		#
		# BETWEEN EVALUATIONS: The _cached_intended_state from the last
		# evaluation is used for state transitions. The state dispatcher
		# still runs every physics frame for smooth movement, but the
		# expensive Director evaluation is throttled.
		#
		# CRITICAL EXCEPTION: The Tier 0 Override Gate below bypasses
		# the throttle when the Entity is state-locked and needs an
		# immediate reaction (FLINCH, RETREAT, STANDOFF, CHARGE).
		# These must not be delayed by 0.2s.
		
		# STATE LOCK: If the state handler is mid-execution, skip the
		# Director's state transition entirely. The handler will unlock
		# when it completes its work.
		if entity.state_locked:
			# ─── TIER 0 OVERRIDE GATE (UNTHROTTLED) ──────────────────
			# Even when locked, critical reactions (FLINCH, RETREAT,
			# STANDOFF, CHARGE) must break the lock immediately. The Entity
			# cannot stay locked in WINDOW_PEEK while being blinded.
			# This evaluation bypasses the throttle for instant response.
			#
			# FLINCH LOCK INTEGRITY FIX:
			# The lock is ONLY cleared when the Director returns a GENUINELY
			# DIFFERENT state. If the Director returns the CURRENT state
			# (e.g., FLINCH while the 5-second flinch timer is active), the
			# result is a no-op — clearing state_locked would let the throttled
			# path re-evaluate on the next frame and break the Entity out of
			# FLINCH (e.g., dropping from overcharge to the standard beam
			# immediately re-enters STANDOFF outdoors). Preserving the lock
			# guarantees the full 5-second flinch is uninterruptible.
			var _debug_intended = _director.evaluate_master_state(entity)
			if _debug_intended == State.FLINCH or _debug_intended == State.RETREAT or _debug_intended == State.STANDOFF or _debug_intended == State.CHARGE:
				if entity.get_state() != _debug_intended:
					entity.state_locked = false
					print("[TRACE_STATE] TIER 0 OVERRIDE: Breaking state lock! %s → %s" % [_get_state_name(entity.get_state()), _get_state_name(_debug_intended)])
					entity.set_state(_debug_intended)
		else:
			# ─── OVERCHARGE UNTHROTTLED EVALUATION ────────────────────
			# During an indoor overcharge standoff, the Director MUST evaluate
			# EVERY frame so the 1.5s stare timer transitions to STANDOFF →
			# RETREAT with zero throttle lag. The 0.2s DIRECTOR_EVAL_INTERVAL
			# would otherwise delay the stagger start/end by up to 200ms,
			# making the precision standoff feel unresponsive and unfair.
			#
			# The is_overcharged flag is written by entity_controller.gd's
			# on_player_stare() each frame — it is only true while the player
			# actively holds the overcharge beam on the Entity. When it clears,
			# this branch is skipped and normal throttling resumes.
			if entity.is_overcharged:
				_cached_intended_state = _director.evaluate_master_state(entity)
				_director_eval_timer = 0.0
			else:
				# ─── THROTTLED EVALUATION ────────────────────────────────
				# Accumulate delta on the eval timer. Only re-evaluate the
				# Director's full 8-tier decision tree when the timer exceeds
				# the interval. Between evaluations, _cached_intended_state
				# holds the last valid decision.
				_director_eval_timer += delta
				if _director_eval_timer >= DIRECTOR_EVAL_INTERVAL:
					_director_eval_timer = 0.0
					_cached_intended_state = _director.evaluate_master_state(entity)
			
			# Apply the cached intended state (or the latest evaluation)
			var intended_state = _cached_intended_state
			if intended_state == -1:
				# Fallback: if no cached state yet, evaluate immediately
				intended_state = _director.evaluate_master_state(entity)
				_cached_intended_state = intended_state
				_director_eval_timer = 0.0
			
			# Apply the Director's decision
			if entity.get_state() != intended_state:
				# [TRACE] Log state transitions during INDOOR_SEARCH
				var current_state = entity.get_state()
				if current_state == EntityAI.State.INDOOR_SEARCH or intended_state == EntityAI.State.INDOOR_SEARCH:
					print("[TRACE_STATE] Director transition: %s → %s" % [_get_state_name(current_state), _get_state_name(intended_state)])
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
	
	# ─── INDOOR SEARCH PERSISTENCE ──────────────────────────────────────
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
			# ─── OUTDOOR SEARCH ──────────────────────────────────────────────
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
		State.STANDOFF:
			# ─── FLASHLIGHT STANDOFF ─────────────────────────────────────────
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
		State.SABOTAGE_FUSE:
			_sabotage_fuse_state(delta)
		State.ENTER_THROUGH_DOOR:
			_enter_through_door_state(delta)
		_:
			_calculated_velocity = Vector3.ZERO
	
	# ─── ZERO-ANIMATION STUN / STARE ENRAGE ─────────────────────────────
	# If the player is staring at the Entity with the flashlight, apply the
	# Zero-Animation Stun: freeze velocity, force Idle animation, and
	# accumulate the stare timer for the enrage mechanic.
	#
	# The _is_being_stared_at flag is set by entity_controller.gd's
	# on_player_stare() each frame. It reflects whether the player's
	# flashlight beam is currently on the Entity.
	#
	# STUN RULES:
	#   - If state is CHARGE, RETREAT, FLINCH, SABOTAGE_FUSE, or
	#     FUSE_SABOTAGE, the Entity is immune to the stun (it's already
	#     committed to an action — the post-retreat FLINCH sprint must
	#     play out so the Entity flees the window, and the sabotage
	#     walk-in must not be interrupted by a flashlight beam).
	#   - If state is any other state AND the player is staring, force
	#     velocity to zero and play the Idle animation.
	#   - The _stare_timer accumulates while the player stares. If the
	#     player looks away, the timer resets to 0.0.
	#   - If _stare_timer reaches 1.5 seconds, the Entity becomes enraged
	#     (entity.is_enraged = true), triggering a permanent speed boost.
	var current_state = entity.get_state()
	# ─── STALK STATE ENTRY FLAGS RESET ─────────────────────────
	# When leaving STALK, reset the _stalk_target_distance_set flag so the
	# next STALK entry re-applies the tight target_desired_distance = 0.3.
	# Also restore the default target_desired_distance (1.5) for other states.
	if current_state != State.STALK and _stalk_target_distance_set:
		_stalk_target_distance_set = false
		entity.get_nav_agent().target_desired_distance = 1.5
		entity.get_nav_agent().path_desired_distance = 1.0
		# ─── TASK 4: RESET ACCELERATION ON STALK EXIT ────────────────
		# The speed multiplier must be COMPLETELY reset whenever the Entity
		# leaves STALK for any reason (Director override, player entered the
		# cabin, flashlight reaction, etc.).
		_stalk_duration_timer = 0.0
		_stalk_accel_mult = 1.0
		# ─── TASK 2: STOP CHASE AUDIO ON STALK EXIT ───────────────────
		# Cleanly fade out and stop the chase music whenever the Entity
		# leaves STALK for any reason.
		var stalk_exit_audio = get_node_or_null("/root/HorrorSoundManager")
		if stalk_exit_audio and stalk_exit_audio.has_method("stop_stalk_chase"):
			stalk_exit_audio.stop_stalk_chase()
	
	if _is_being_stared_at and current_state != State.CHARGE and current_state != State.RETREAT and current_state != State.FLINCH and current_state != State.SABOTAGE_FUSE and current_state != State.FUSE_SABOTAGE:
		# ─── FREEZE VELOCITY ────────────────────────────────────────────────
		# Override the calculated velocity to zero, preventing the Entity
		# from moving while being stared at.
		_calculated_velocity = Vector3.ZERO
		
		# ─── FORCE IDLE ANIMATION ───────────────────────────────────────────
		# Travel to the Idle animation in the state machine so the Entity
		# doesn't play a "walk-in-place" animation while stunned.
		var anim_sm = entity.get_anim_state_machine()
		if anim_sm:
			anim_sm.travel("Idle")
		
		# ─── ACCUMULATE STARE TIMER ─────────────────────────────────────────
		# Count up while the player stares. If the timer reaches 1.5s,
		# trigger the enrage mechanic.
		_stare_timer += delta
		if _stare_timer >= 1.5 and not entity.is_enraged:
			entity.is_enraged = true
	else:
		# ─── RESET STARE TIMER ──────────────────────────────────────────────
		# If the player is not staring (or the Entity is in CHARGE/RETREAT),
		# reset the stare timer so it doesn't accumulate across multiple
		# stare sessions.
		if _stare_timer > 0.0:
			_stare_timer = 0.0
	
	# ─── SPATIAL VOICE MANAGEMENT ───────────────────────────────────────
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
	
	# ─── STATE TRANSITION DETECTION ─────────────────────────────────────
	# If the state changed since the last frame, handle voice transitions.
	if current_state != _last_voice_state:
		# ─── RESET ANGRY FLAG WHEN LEAVING CHARGE ──────────────────────────
		# Check BEFORE updating _last_voice_state so we can detect the
		# transition from CHARGE to any other state. If we were in CHARGE
		# and now we're not, reset the angry flag so the next CHARGE can
		# play the angry voice again.
		if _last_voice_state == State.CHARGE and current_state != State.CHARGE:
			entity.set_voice_angry_played_this_charge(false)
		
		# Update the last voice state tracker
		_last_voice_state = current_state
		
		# ─── CHARGE: One-shot angry voice ──────────────────────────────────
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
		
		# ─── WINDOW_PEEK: Random talking voice (looping) ───────────────────
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
		
		# ─── OBSERVE_FROM_TREELINE: Searching voice (looping) ──────────────
		elif current_state == State.OBSERVE_FROM_TREELINE:
			var search_stream = entity.get_voice_searching()
			if search_stream:
				# Enable looping for searching stream
				if search_stream is AudioStreamOggVorbis:
					search_stream.loop = true
				voice_player.stream = search_stream
				voice_player.play()
		
		# ─── ALL OTHER STATES: Stop voice ──────────────────────────────────
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
	return


# ---------------------------------------------------------------------------
# STATE: OBSERVE_FROM_TREELINE
# ---------------------------------------------------------------------------

## ─── ALL WINDOWS LIT LOOP GUARD ────────────────────────────────────────────
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
	
	# ─── ALL WINDOWS LIT LOOP GUARD ─────────────────────────────────────
	# Check if ALL ground-floor windows are secured by light sanctuary.
	# If so, the Entity cannot approach any window and must wait in
	# OBSERVE_FROM_TREELINE until a light turns off.
	var nav_module = entity.get_navigation_module()
	var all_lit: bool = false
	if nav_module and nav_module.has_method("are_all_windows_lit"):
		all_lit = nav_module.are_all_windows_lit()
	
	if all_lit:
		# ─── COOLDOWN: Force minimum wait in OBSERVE ───────────────────────
		# Set the cooldown timer on the first frame all windows are detected
		# as lit. During the cooldown, the Entity cannot signal completion
		# (is_observe_finished stays false), preventing the Director from
		# cycling to APPROACH_WINDOW and back.
		if _all_lit_cooldown_timer <= 0.0:
			_all_lit_cooldown_timer = ALL_LIT_MIN_COOLDOWN

		
		# Decrement the cooldown timer
		_all_lit_cooldown_timer -= delta
		if _all_lit_cooldown_timer > 0.0:
			# ─── DURING COOLDOWN: Accumulate frustration ────────────────────
			# While the Entity is forced to wait, it builds frustration at
			# 2.0 * delta per second. This frustration represents the Entity's
			# growing impatience with being unable to approach any window.
			_all_lit_frustration += ALL_LIT_FRUSTRATION_RATE * delta
			
			# ─── FRUSTRATION THRESHOLD: FUSE_SABOTAGE ──────────────────────
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
			
			# ─── FREEZE MOVEMENT DURING COOLDOWN ───────────────────────────
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
			
			# ─── DEBUG LOG ─────────────────────────────────────────────────
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
			_all_lit_cooldown_timer = 0.0
			print("[Entity AI] ALL WINDOWS LIT: A light turned off! Frustration reset.")
	
	# --- PHYSICAL PATHFINDING TO VANTAGE POINT ---
	if not entity.get_nav_agent().is_navigation_finished():
		# ─── NAV TARGET JITTER ─────────────────────────────────────────────
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
		# ─── FIRST ENTRY: No nav target set ────────────────────────────────
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
		# ─── AGGRESSIVE PACING: Dynamic wait time based on confidence ──────
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
	
	# ─── FACE THE CABIN WHILE IDLE ──────────────────────────────────────
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
	
	# ─── DESPERATION MECHANIC: PASSIVE TIMER ────────────────────────────
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
		# ─── 3-WAYPOINT MISS RULE: Impatience Mechanic ─────────────────────
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
			# ─── IMPATIENCE CONFIDENCE BOOST ───────────────────────────────
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
			
			# ─── CONSUME THE MISSES ────────────────────────────────────────
			# Reset the consecutive miss counter after the confidence boost
			# is applied. This prevents the boost from being applied again
			# on the next frame (the stare timer would still be <= 0.0).
			entity.reset_consecutive_vantage_misses()
		else:
			print("[Entity AI] Vantage miss %d/3. Player still believed inside." % misses)
		
		# ─── RESET THE STARE TIMER ─────────────────────────────────────────
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
		
		# ─── RESET RELOCATE TARGET FLAG ────────────────────────────────────
		# CRITICAL: Reset the _relocate_target_set flag so the Entity knows
		# it needs to pick a NEW tree on the next cycle. Without this, the
		# Entity would arrive at the first tree, the Director would consume
		# is_observe_finished and call fade_and_relocate(), but the Entity
		# wouldn't know it needs to move — it would stay at the same tree
		# forever, creating the "paralysis at first tree" bug.
		entity.set_relocate_target_set(false)
		
		# ─── SIGNAL COMPLETION TO THE DIRECTOR ─────────────────────────────
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
	
	# TASK 1: The `is_on` gate ensures the Entity also aborts ATTACK_LAMP
	# mid-approach if the lamp's light is switched off (e.g. via the computer
	# terminal or wall switch). The Director only re-enters ATTACK_LAMP when
	# the lamp is deployed, powered, AND actively shining.
	if not trap or not trap.is_deployed or not trap.is_powered or not trap.is_on:
		# The Director will handle the transition out of ATTACK_LAMP
		# when the trap is no longer valid (Tier 3 check fails).
		# Just reset the attack timer and stop moving.
		entity.set_lamp_attack_timer(0.0)
		_calculated_velocity = Vector3.ZERO
		return
	
	# Pathfind toward the trap's position
	var nav_agent = entity.get_nav_agent()
	if nav_agent:
		# Throttle path updates to every 300ms
		entity.set_path_timer(entity.get_path_timer() + delta)
		if entity.get_path_timer() >= entity.path_update_interval:
			entity.set_path_timer(0.0)
			nav_agent.target_position = trap.global_position
	
	# Check distance to trap
	var dist = entity.global_position.distance_to(trap.global_position)
	
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
	# Use the cached @export fuse_box_node reference (resolved once in
	# _initialize_entity()). This avoids the expensive scene tree traversal
	# that was previously called every frame via get_fuse_box_node().
	var fuse_box = entity.fuse_box_node
	
	if not fuse_box or not is_instance_valid(fuse_box):
		# Fuse Box doesn't exist or was destroyed — signal completion
		entity.is_fuse_sabotaged = true
		_calculated_velocity = Vector3.ZERO
		return
	
	# Check if the Fuse Box is already destroyed
	# Use direct property access instead of duck-typing has_method() checks.
	if fuse_box.is_destroyed():
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
# STATE: SABOTAGE_FUSE — Door-prerequisite sabotage of the Fuse Box
# ---------------------------------------------------------------------------
## The Entity pathfinds to the EntityFuseWaypoint marker and breaks the
## Fuse Box. This is triggered by the Director's Tier 1 when the Entity
## wants to approach the door but the porch light is on (generator powered).
##
## Unlike FUSE_SABOTAGE (frustration-based brute-force attack), this state
## is a "surgical" one-shot: the Entity walks to the waypoint, calls
## break_fuse() directly, and signals completion immediately.
##
## The EntityFuseWaypoint is a Marker3D node tagged with the "EntityFuseWaypoint"
## group, placed near the Fuse Box so the Entity can pathfind to it.
func _sabotage_fuse_state(delta: float) -> void:
	# NOTE: The Fuse Box (and its EntityFuseWaypoint) sit OUTSIDE the cabin.
	# The Entity must NOT clip through cabin walls — it keeps the FULL
	# outdoor collision mask (Cabin/Player/Trees/Rocks) and pathfinds
	# AROUND the cabin via the NavigationAgent. No collision-mask change.
	
	# ─── FIX 5: ROBUST FRESH-ENTRY DETECTION (self-contained snapshot) ──
	# Compares the current state against the state that LAST called this
	# handler. Does NOT depend on entity.get_previous_state() (which was
	# broken — see _last_sabotage_call_state docs) or any external state
	# tracking. Fires exactly once per SABOTAGE_FUSE entry, resetting all
	# distance-latch trackers, the elapsed failsafe, AND the nav grace timer.
	if entity.get_state() != _last_sabotage_call_state:
		_last_sabotage_call_state = entity.get_state()
		_sabotage_last_dist = 0.0
		_sabotage_dist_check_timer = 0.0
		_sabotage_stuck_timer = 0.0
		_sabotage_elapsed = 0.0
		_sabotage_nav_grace_timer = SABOTAGE_NAV_GRACE
		print("[SABOTAGE_FUSE] Fresh entry detected. Trackers + nav grace reset.")
	
	# ─── FIX 1: LOCK ONLY AFTER NULL-CHECKS PASS ────────────────────────
	# Previously `entity.state_locked = true` was set unconditionally on the
	# FIRST line. If fuse_box was null/invalid/already broken, the early-exit
	# branches had to manually unlock. Worse, the unconditional lock combined
	# with the frame-1 NavAgent deadlock meant the Director could not rescue
	# the Entity for the entire state duration — total paralysis. The lock is
	# now set AFTER all early-exit guard clauses pass, so an invalid target
	# aborts and returns to OBSERVE without ever locking.
	
	# Use the cached @export fuse_box_node reference (resolved once in
	# _initialize_entity()). This avoids the expensive scene tree traversal
	# that was previously called every frame via get_fuse_box_node().
	var fuse_box = entity.fuse_box_node
	
	if not fuse_box or not is_instance_valid(fuse_box):
		# Fuse Box doesn't exist or was destroyed — signal completion
		entity.is_fuse_sabotaged = true
		_calculated_velocity = Vector3.ZERO
		return
	
	# Check if the Fuse Box is already destroyed
	# Use direct property access instead of duck-typing has_method() checks.
	# The cached fuse_box_node is typed as FuseBox, so is_powered is guaranteed.
	if not fuse_box.is_powered():
		# Already broken — signal completion
		entity.is_fuse_sabotaged = true
		_calculated_velocity = Vector3.ZERO
		print("[SABOTAGE_FUSE] Fuse Box already broken. Signaling completion.")
		return
	
	# All guard clauses passed — this is a legitimate sabotage attempt.
	# Lock the state NOW so the Director doesn't override mid-sabotage.
	entity.state_locked = true
	
	# ─── GET THE CACHED FUSE WAYPOINT ────────────────────────────────────
	# Use the cached @export fuse_waypoint reference (set in Inspector or
	# resolved once in _initialize_entity()). This replaces the expensive
	# per-frame child iteration that was called every frame during SABOTAGE_FUSE
	# to find the waypoint.
	var fuse_waypoint: Node3D = entity.get_fuse_waypoint()
	
	if not fuse_waypoint:
		# Fallback: no waypoint found, pathfind directly to the Fuse Box
		print("[SABOTAGE_FUSE] No cached FuseWaypoint found. Pathfinding directly to Fuse Box.")
		_path_timer -= delta
		if _path_timer <= 0.0:
			_path_timer = PATH_UPDATE_INTERVAL
			entity.get_nav_agent().target_position = fuse_box.global_position
		
		var dist_to_fuse = entity.global_position.distance_to(fuse_box.global_position)
		if dist_to_fuse <= fuse_sabotage_range:
			# In range — break the fuse box immediately
			fuse_box.break_fuse()
			entity.is_fuse_sabotaged = true
			entity.state_locked = false
			_sabotage_nav_grace_timer = 0.0
			_calculated_velocity = Vector3.ZERO
			print("[SABOTAGE_FUSE] Fuse Box broken! Signaling completion.")
			return
		
		# Pathfinding toward the Fuse Box (NavAgent routes around the cabin)
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
		return
	
	# ─── BUG 3 FIX: GLOBAL FAILSAFE ────────────────────────────────────
	# Track total elapsed time in SABOTAGE_FUSE. If the Entity remains in
	# this state for longer than SABOTAGE_GLOBAL_FAILSAFE (15s) without
	# completing through ANY branch (including the no-waypoint fallback
	# above, which previously had no stuck timeout at all), force-teleport
	# to the waypoint, break the fuse box, and relocate to the treeline.
	_sabotage_elapsed += delta
	if _sabotage_elapsed >= SABOTAGE_GLOBAL_FAILSAFE:
		print("[SABOTAGE_FUSE] GLOBAL FAILSAFE (%.1fs elapsed, dist=%.2f)! Forcing completion." % [_sabotage_elapsed, entity.global_position.distance_to(fuse_waypoint.global_position)])
		entity.global_position = fuse_waypoint.global_position
		entity.velocity = Vector3.ZERO
		_sabotage_stuck_timer = 0.0
		_sabotage_dist_check_timer = 0.0
		_sabotage_elapsed = 0.0
		_sabotage_nav_grace_timer = 0.0
		fuse_box.break_fuse()
		entity.is_fuse_sabotaged = true
		entity.state_locked = false
		_calculated_velocity = Vector3.ZERO
		_relocate_to_treeline_after_sabotage()
		print("[SABOTAGE_FUSE] Global failsafe fired. Fuse Box broken! Relocated to treeline. Signaling completion.")
		return
	
	# ─── PATHFIND TOWARD THE FUSE WAYPOINT ──────────────────────────────
	_path_timer -= delta
	if _path_timer <= 0.0:
		_path_timer = PATH_UPDATE_INTERVAL
		entity.get_nav_agent().target_position = fuse_waypoint.global_position
		# ─── FIX 3: ARM NAV GRACE PERIOD ────────────────────────────────
		# A fresh target_position was just set. Godot's NavAgent computes
		# the path asynchronously; is_navigation_finished() returns true
		# until the path is ready. Arm the grace timer so the movement
		# block does not treat "no path yet" as "arrived."
		_sabotage_nav_grace_timer = SABOTAGE_NAV_GRACE
	
	var dist_to_wp = entity.global_position.distance_to(fuse_waypoint.global_position)
	
	# ─── STUCK DETECTION (BUG 3 FIX: DISTANCE-LATCHED) ──────────────────
	# If the Entity is NOT yet at the waypoint (> 2.5m), accumulate the
	# stuck timer based on PHYSICAL PROGRESS toward the waypoint.
	#
	# WHY THE OLD VELOCITY CHECK FAILED: The previous condition treated
	# "non-zero velocity" as progress. But when the Entity oscillates
	# against a NavMesh-edge / cabin-exterior collider, it jitters back
	# and forth with non-zero velocity — so the stuck timer never
	# accumulated and the Entity was paralyzed forever.
	#
	# NEW APPROACH: Latch the distance to the waypoint every check interval
	# (2s). If the distance hasn't decreased by at least 0.5m over the
	# interval, the Entity is NOT making progress (whether it is frozen or
	# jittering) and the stuck timer accumulates. On timeout, teleport to
	# the waypoint, break the fuse box, and relocate to avoid a soft-lock.
	#
	# The global stuck detector in entity_controller.gd previously rescued
	# this, but with SABOTAGE_FUSE now exempt (so it doesn't teleport away
	# mid-sabotage), this per-state timer must handle ALL distances.
	if dist_to_wp > 2.5:
		if _sabotage_last_dist <= 0.0:
			# First frame in this branch — latch the initial distance.
			_sabotage_last_dist = dist_to_wp
			_sabotage_dist_check_timer = 0.0
		else:
			_sabotage_dist_check_timer += delta
			if _sabotage_dist_check_timer >= SABOTAGE_PROGRESS_CHECK_INTERVAL:
				_sabotage_dist_check_timer = 0.0
				var dist_decrease = _sabotage_last_dist - dist_to_wp
				_sabotage_last_dist = dist_to_wp
				if dist_decrease >= SABOTAGE_PROGRESS_EPSILON:
					# Genuinely made progress — reset the stuck timer.
					_sabotage_stuck_timer = 0.0
				else:
					# No meaningful progress (frozen OR oscillating jitter).
					_sabotage_stuck_timer += SABOTAGE_PROGRESS_CHECK_INTERVAL
		
		if _sabotage_stuck_timer >= fuse_sabotage_stuck_timeout:
			print("[SABOTAGE_FUSE] STUCK TIMEOUT! Entity stuck at dist=%.2f for %.1fs. Teleporting to waypoint." % [dist_to_wp, _sabotage_stuck_timer])
			entity.global_position = fuse_waypoint.global_position
			entity.velocity = Vector3.ZERO
			_sabotage_stuck_timer = 0.0
			_sabotage_dist_check_timer = 0.0
			_sabotage_elapsed = 0.0
			_sabotage_nav_grace_timer = 0.0
			# Now check arrival immediately
			fuse_box.break_fuse()
			entity.is_fuse_sabotaged = true
			entity.state_locked = false
			_calculated_velocity = Vector3.ZERO
			# ─── RELOCATE TO TREELINE VANTAGE POINT ──────────────────────────
			# After teleporting to the EntityFuseWaypoint, the Entity is at
			# (1.154, 0.172, 16.596) — inside the cabin area near the fuse box.
			# The NavMesh cannot find a path from this position to any window,
			# causing the APPROACH_WINDOW state to fail (15s timeout) and the
			# Entity to get stuck. Relocate to a treeline vantage point so the
			# next APPROACH_WINDOW starts from a valid NavMesh position.
			_relocate_to_treeline_after_sabotage()
			print("[SABOTAGE_FUSE] Teleported to EntityFuseWaypoint. Fuse Box broken! Relocated to treeline. Signaling completion.")
			return
	elif dist_to_wp <= 2.5:
		# Arrived at the waypoint — reset all trackers and break the fuse box
		_sabotage_stuck_timer = 0.0
		_sabotage_dist_check_timer = 0.0
		_sabotage_last_dist = 0.0
		_sabotage_elapsed = 0.0
		_sabotage_nav_grace_timer = 0.0
		fuse_box.break_fuse()
		entity.is_fuse_sabotaged = true
		entity.state_locked = false
		_calculated_velocity = Vector3.ZERO
		# ─── RELOCATE TO TREELINE VANTAGE POINT ──────────────────────────
		# After breaking the fuse box, the Entity is at the EntityFuseWaypoint
		# position (inside the cabin area). Relocate to a treeline vantage point
		# so the next APPROACH_WINDOW starts from a valid NavMesh position.
		_relocate_to_treeline_after_sabotage()
		print("[SABOTAGE_FUSE] Arrived at EntityFuseWaypoint (dist=%.2f). Fuse Box broken! Relocated to treeline. Signaling completion." % dist_to_wp)
		return
	
	# ─── MOVEMENT TOWARD WAYPOINT (NavAgent — routes around the cabin) ──
	# The Fuse Box and its EntityFuseWaypoint are OUTSIDE the cabin,
	# reachable via the NavMesh. The Entity MUST NOT clip through cabin
	# walls, so it follows the NavigationAgent's path — which naturally
	# routes AROUND the cabin exterior — instead of a blind straight
	# line that could cut through the interior.
	if _sabotage_nav_grace_timer > 0.0:
		# ─── FIX 3: NAV GRACE PERIOD ACTIVE ─────────────────────────────
		# The NavAgent just received a new target_position and has not yet
		# computed a path. is_navigation_finished() currently returns TRUE
		# (async path computation), so evaluating it now would zero the
		# velocity and deadlock the Entity. Hold at zero velocity and count
		# down the grace timer; when it expires, the NavAgent has a path
		# and the normal branch below takes over.
		_sabotage_nav_grace_timer -= delta
		_calculated_velocity.x = 0.0
		_calculated_velocity.z = 0.0
	elif entity.get_nav_agent().is_navigation_finished():
		_calculated_velocity.x = 0.0
		_calculated_velocity.z = 0.0
	else:
		var next_pos = entity.get_nav_agent().get_next_path_position()
		var dir_2d := Vector2(next_pos.x - entity.global_position.x, next_pos.z - entity.global_position.z)
		if dir_2d.length() > 0.01:
			var move_dir_2d = dir_2d.normalized()
			_calculated_velocity.x = move_dir_2d.x * entity.current_stalk_speed
			_calculated_velocity.z = move_dir_2d.y * entity.current_stalk_speed


## ─── SABOTAGE RELOCATION HELPER ──────────────────────────────────────────
## After the Entity breaks the Fuse Box (SABOTAGE_FUSE), it is at the
## EntityFuseWaypoint position (1.154, 0.172, 16.596) — inside the cabin area
## near the fuse box. The NavMesh cannot find a path from this position to any
## window, causing the APPROACH_WINDOW state to fail (15s timeout) and the
## Entity to get stuck.
##
## This function relocates the Entity to a random treeline vantage point so
## the next APPROACH_WINDOW starts from a valid NavMesh position.
func _relocate_to_treeline_after_sabotage() -> void:
	# The Fuse Box (and its EntityFuseWaypoint) sit OUTSIDE the cabin, so
	# SABOTAGE_FUSE never alters the collision mask — the Entity stays on
	# the full outdoor mask and pathfinds AROUND the cabin walls via the
	# NavMesh. No mask manipulation is needed here.
	var nav = entity.get_navigation_module()
	if nav and nav.has_method("pick_next_vantage_point"):
		nav.pick_next_vantage_point()
	
	# Get the new nav target position and teleport there
	var nav_agent = entity.get_nav_agent()
	if nav_agent:
		var target_pos = nav_agent.target_position
		# Only teleport if the target is valid (not zero) and far enough away
		if target_pos != Vector3.ZERO and target_pos.distance_to(entity.global_position) > 5.0:
			# ─── SNAP TO NAVMESH FLOOR ────────────────────────────────────────
			# The treeline vantage point's Y coordinate may be above the NavMesh
			# surface (e.g., floating in the air at Y ≈ 1.0+). Use Godot's
			# NavigationServer3D.map_get_closest_point() to project the target
			# position onto the NavMesh floor, ensuring the Entity lands on solid
			# ground instead of floating in mid-air.
			var nav_map = entity.get_world_3d().navigation_map
			var snapped_pos = NavigationServer3D.map_get_closest_point(nav_map, target_pos)
			# Preserve the target's XZ but use the NavMesh-snapped Y
			snapped_pos.x = target_pos.x
			snapped_pos.z = target_pos.z
			entity.global_position = snapped_pos
			entity.velocity = Vector3.ZERO
			print("[SABOTAGE_RELOCATE] Teleported to treeline vantage point at (%.2f, %.2f, %.2f) [snapped to NavMesh Y=%.2f]" % [target_pos.x, target_pos.y, target_pos.z, snapped_pos.y])
		else:
			# Fallback: try to find a treeline marker directly
			var treeline_markers = entity.get_tree().get_nodes_in_group("Treeline_Vantage_Points")
			if not treeline_markers.is_empty():
				var marker = treeline_markers[randi() % treeline_markers.size()] as Node3D
				if marker:
					# ─── SNAP TO NAVMESH FLOOR ────────────────────────────────
					# Same NavMesh snapping for the fallback marker position.
					var nav_map = entity.get_world_3d().navigation_map
					var snapped_pos = NavigationServer3D.map_get_closest_point(nav_map, marker.global_position)
					snapped_pos.x = marker.global_position.x
					snapped_pos.z = marker.global_position.z
					entity.global_position = snapped_pos
					entity.velocity = Vector3.ZERO
					nav_agent.target_position = marker.global_position
					print("[SABOTAGE_RELOCATE] Fallback: Teleported to treeline marker at (%.2f, %.2f, %.2f) [snapped to NavMesh Y=%.2f]" % [marker.global_position.x, marker.global_position.y, marker.global_position.z, snapped_pos.y])


# ---------------------------------------------------------------------------
# STATE: STALK (CHASE / PATROL) — Enhanced with distance-range, LOS speed, and flanking
# ---------------------------------------------------------------------------

## ─── STALK FREEZE FIX: NAVMESH Y-FLATTEN HELPER ─────────────────────
## Projects a world-space target onto the NavMesh floor (preserve XZ,
## use NavMesh Y). The player's Y can dip below the NavMesh surface
## (e.g. walking on slightly-lower terrain); targets below the NavMesh
## are unreachable — is_navigation_finished() returns true permanently
## and the Entity freezes forever. Refactored as a class-level method
## because GDScript does not support nested func declarations.
func _snap_to_navmesh(target: Vector3) -> Vector3:
	var nav_map = entity.get_world_3d().navigation_map
	var snapped = NavigationServer3D.map_get_closest_point(nav_map, target)
	snapped.x = target.x
	snapped.z = target.z
	return snapped

func _stalk_state(delta: float) -> void:
	# ─── TIGHTEN NAV TARGET DISTANCE (ONCE ON ENTRY) ─────────────────
	var nav_agent = entity.get_nav_agent()
	if not _stalk_target_distance_set:
		_stalk_target_distance_set = true
		nav_agent.target_desired_distance = 1.0
		nav_agent.path_desired_distance = 1.0
		# Reset flank timer on state entry
		_stalk_flank_timer = 0.0
		_stalk_is_flanking = false
		_stalk_los_break_timer = 0.0
		_stalk_current_speed_mult = 1.0
		# ─── STALK FREEZE FIX: ARM NAV GRACE ON ENTRY ──────────────────
		# The NavAgent has no path yet on fresh STALK entry and reports
		# is_navigation_finished() == true. Without a grace period the
		# movement block zeroes the velocity and freezes the Entity.
		_stalk_nav_grace = STALK_NAV_GRACE_TIME
	
	# ─── HALLROOM / INDOOR EXIT GUARD ──────────────────────────
	var nav = entity.get_navigation_module()
	if nav and nav.has_method("get_player_room"):
		var player_room = nav.get_player_room()
		if player_room != "Outside" and player_room != "":
			if player_room == "Hallroom":
				print("[Entity AI] STALK: Player entered Hallroom. Force-exiting STALK.")
				# ─── TASK 12: SILENCE STALK-INTERRUPT SOUND ──────────────
				# Instantly stop the spatial voice so no audio cue plays
				# when the player entering the cabin interrupts STALK.
				var stalk_voice = entity.get_voice_player()
				if stalk_voice and stalk_voice.playing:
					stalk_voice.stop()
					stalk_voice.stream = null
				entity.is_observe_finished = true
				entity.state_locked = false
				entity.request_state(EntityAI.State.OBSERVE_FROM_TREELINE)
				_calculated_velocity = Vector3.ZERO
				return
			elif night_manager and night_manager.is_van_sequence_active:
				pass
			else:
				print("[Entity AI] STALK: Player entered '%s'. Force-exiting STALK." % player_room)
				# ─── TASK 12: SILENCE STALK-INTERRUPT SOUND ──────────────
				# Instantly stop the spatial voice so no audio cue plays
				# when the player entering the cabin interrupts STALK.
				var stalk_voice2 = entity.get_voice_player()
				if stalk_voice2 and stalk_voice2.playing:
					stalk_voice2.stop()
					stalk_voice2.stream = null
				entity.is_observe_finished = true
				entity.state_locked = false
				entity.request_state(EntityAI.State.OBSERVE_FROM_TREELINE)
				_calculated_velocity = Vector3.ZERO
				return
	
	var player = entity.get_player()
	if not player:
		return
	
	# ─── LIGHT SWITCH RETREAT CHECK ─────────────────────────────
	if RoomLightDetector.is_entity_in_lit_room():
		entity.is_indoor_retreat = true
		entity.state_locked = false
		_calculated_velocity = Vector3.ZERO
		return
	
	# ─── CATCH CHECK ────────────────────────────────────────────
	var dist_to_player := entity.global_position.distance_to(player.global_position)
	if dist_to_player <= entity.catch_distance:
		entity._on_caught_player()
		return
	
	# ─── TASK 2: STALK CHASE AUDIO (distance-gated, 30m) ────────
	# The chase music only plays while the Entity is STALKing AND the player
	# is within 30 meters. If the player outruns that distance, the track
	# fades out cleanly; re-entering the 30m boundary resumes it without
	# restarting from the beginning (play_stalk_chase is a no-op while the
	# track is already active, and stop_stalk_chase uses a 0.5s tween).
	var stalk_audio = get_node_or_null("/root/HorrorSoundManager")
	if stalk_audio and stalk_audio.has_method("play_stalk_chase"):
		if dist_to_player < 30.0:
			stalk_audio.play_stalk_chase()
		else:
			stalk_audio.stop_stalk_chase()
	
	# ─── TASK 5: STALK RUBBERBANDING (40m max distance) ─────────────────
	# If the player manages to outrun the Entity by more than 40 meters
	# while it is STALKing, teleport the Entity to the closest StalkWaypoint
	# to the player and immediately resume pursuit. This maintains tension
	# and bypasses the Director's Tier evaluations entirely (the Entity
	# stays in STALK — only its position changes).
	#
	# The waypoints are in the "StalkWaypoints" group (a node that sits as
	# a child under "EntityWaypoints"). The original STALK rubberband logic
	# searched this group correctly, but was later diagnosed incorrectly as
	# "EntityStalkWaypoints" — this version uses the canonical group name.
	# It adds a 3-second cooldown to prevent per-frame teleport spam, forces
	# the NavigationAgent to discard its stale pre-teleport path, and resets
	# any active flank maneuver so the Entity resumes a clean direct pursuit.
	_stalk_rubberband_cooldown_timer -= delta
	if dist_to_player > 40.0 and _stalk_rubberband_cooldown_timer <= 0.0:
		_stalk_rubberband_cooldown_timer = STALK_RUBBERBAND_COOLDOWN
		
		# The canonical group for the stalk waypoints.
		var stalk_wps := get_tree().get_nodes_in_group("StalkWaypoints")
		
		var best_wp: Node3D = null
		var best_wp_dist: float = INF
		for wp in stalk_wps:
			if wp is Marker3D:
				var wp_d = player.global_position.distance_to(wp.global_position)
				if wp_d < best_wp_dist:
					best_wp_dist = wp_d
					best_wp = wp
		if best_wp:
			# Snap to NavMesh floor (preserve XZ, use NavMesh Y) to avoid
			# floating mid-air after the teleport. Also prevents spawning
			# inside geometry — map_get_closest_point returns the nearest
			# walkable NavMesh point to the marker.
			var rb_nav_map = entity.get_world_3d().navigation_map
			var rb_snapped = NavigationServer3D.map_get_closest_point(rb_nav_map, best_wp.global_position)
			rb_snapped.x = best_wp.global_position.x
			rb_snapped.z = best_wp.global_position.z
			entity.global_position = rb_snapped
			entity.velocity = Vector3.ZERO
			
			# ─── FORCE NAV PATH RESET ──────────────────────────────────────
			# Setting target_position to the Entity's CURRENT position first
			# forces the NavigationAgent to discard its stale pre-teleport
			# path and recompute from scratch. Then immediately re-target
			# the player so pursuit resumes on the next frame.
			entity.get_nav_agent().target_position = entity.global_position
			entity.get_nav_agent().target_position = player.global_position
			
			# ─── ARM NAV GRACE PERIOD (STALK FREEZE FIX) ─────────────
			# The NavAgent computes paths asynchronously — is_navigation_finished()
			# returns TRUE until the new path is ready. Arm the grace timer so
			# the movement block does not interpret "no path yet" as "arrived"
			# and zero the velocity (the micro-freeze after each teleport).
			_stalk_rubberband_nav_grace = STALK_RUBBERBAND_NAV_GRACE_TIME
			
			# ─── RESET FLANK STATE ─────────────────────────────────────────
			# A teleport invalidates any in-progress flank maneuver — the
			# Entity's new position may be on the wrong side of the flank
			# offset. Reset to a clean direct pursuit.
			_stalk_is_flanking = false
			_stalk_flank_target = Vector3.ZERO
			
			print("[STALK RUBBERBAND] Player exceeded 40m (dist=%.1f). Teleported Entity to closest StalkWaypoint (%.2f, %.2f, %.2f)." % [dist_to_player, rb_snapped.x, rb_snapped.y, rb_snapped.z])
	
	# ─── FEATURE 3B: LOS-AWARE SPEED MODULATION ────────────────
	# Check if the Entity can see the player via sensory module.
	# Accumulate LOS break time when the player is not visible.
	# After STALK_LOS_BREAK_THRESHOLD seconds without LOS, slow down.
	var sensory = entity.get_sensory_module()
	var has_los: bool = false
	if sensory and sensory.has_method("can_entity_see_player"):
		has_los = sensory.can_entity_see_player()
	
	if has_los:
		_stalk_los_break_timer = 0.0
	else:
		_stalk_los_break_timer += delta
	
	var los_speed_mult: float = 1.0
	if _stalk_los_break_timer >= STALK_LOS_BREAK_THRESHOLD:
		los_speed_mult = stalk_search_speed_mult
	
	# ─── FEATURE 3A: MAINTAIN-DISTANCE RANGE ───────────────────
	# Compute distance-based speed multiplier using stalk_min_distance
	# and stalk_max_distance. When close, slow to stalk_close_speed_mult.
	# When far, use full speed. In-between, lerp proportionally.
	var dist_speed_mult: float = 1.0
	if dist_to_player < stalk_min_distance:
		# Too close — slow to minimum approach speed
		dist_speed_mult = stalk_close_speed_mult
	elif dist_to_player > stalk_max_distance:
		# Too far — full speed
		dist_speed_mult = 1.0
	else:
		# In between — lerp proportionally
		var t = (dist_to_player - stalk_min_distance) / (stalk_max_distance - stalk_min_distance)
		dist_speed_mult = stalk_close_speed_mult + (1.0 - stalk_close_speed_mult) * t
	
	# Combine both multipliers (LOS takes priority when active)
	_stalk_current_speed_mult = dist_speed_mult * los_speed_mult
	
	# ─── TASK 4: TIME-BASED ACCELERATION ─────────────────────────
	# Accumulate the STALK duration timer. After the 10-second grace
	# period, ramp the acceleration multiplier from 1.0x toward the
	# 200% cap over STALK_ACCEL_RAMP_TIME seconds. The Entity becomes
	# increasingly aggressive during a long chase.
	_stalk_duration_timer += delta
	if _stalk_duration_timer > STALK_ACCEL_GRACE_PERIOD:
		var accel_elapsed := _stalk_duration_timer - STALK_ACCEL_GRACE_PERIOD
		_stalk_accel_mult = lerpf(1.0, STALK_ACCEL_CAP, minf(accel_elapsed / STALK_ACCEL_RAMP_TIME, 1.0))
	else:
		_stalk_accel_mult = 1.0
	
	# ─── FEATURE 3C: FLANKING BEHAVIOR ─────────────────────────
	# Periodically navigate to a flanking offset position instead of
	# pathing directly toward the player.
	if flanking_enabled and has_los and not _stalk_is_flanking:
		_stalk_flank_timer += delta
		if _stalk_flank_timer >= flank_interval:
			_stalk_flank_timer = 0.0
			_stalk_is_flanking = true
			
			# Calculate flank target: perpendicular offset from Entity→Player direction
			var dir_to_player = (player.global_position - entity.global_position).normalized()
			var perp = Vector3(-dir_to_player.z, 0.0, dir_to_player.x)  # Left perpendicular
			if randf() < 0.5:
				perp = Vector3(dir_to_player.z, 0.0, -dir_to_player.x)  # Right perpendicular
			
			# Flank point: offset perpendicular to the player's position
			_stalk_flank_target = player.global_position + perp * flank_offset_distance
			
			# Snap the flank target Y to the Entity's current Y (ground level)
			_stalk_flank_target.y = entity.global_position.y
			
			print("[Entity AI] STALK: Flanking! Setting offset target.")
	
	# ─── PATHFINDING & MOVEMENT ────────────────────────────────
	_path_timer -= delta
	if _path_timer <= 0.0:
		_path_timer = PATH_UPDATE_INTERVAL
		
		# ─── STALK FREEZE FIX: ARM NAV GRACE ON PATH UPDATE ──────────
		# Every target_position assignment triggers an async path
		# computation. During that window is_navigation_finished()
		# returns true, which would zero the velocity. The grace timer
		# prevents the movement block from misinterpreting "no path yet"
		# as "arrived" after every 0.3s path refresh.
		_stalk_nav_grace = STALK_NAV_GRACE_TIME
		
		if _stalk_is_flanking:
			# Navigate toward the flank target
			var dist_to_flank = entity.global_position.distance_to(_stalk_flank_target)
			if dist_to_flank <= 2.0:
				# Reached flank point — resume direct chase
				_stalk_is_flanking = false
				_stalk_flank_target = Vector3.ZERO
				# Set nav target to player (flattened to NavMesh Y)
				var jitter = Vector3(randf_range(-0.1, 0.1), 0.0, randf_range(-0.1, 0.1))
				entity.get_nav_agent().target_position = _snap_to_navmesh(player.global_position + jitter)
			else:
				# Flatten the flank target Y to the NavMesh surface too.
				entity.get_nav_agent().target_position = _snap_to_navmesh(_stalk_flank_target)
		else:
			# Normal chase: direct pursuit with jitter (flattened to NavMesh Y)
			var jitter_offset = Vector3(randf_range(-0.1, 0.1), 0.0, randf_range(-0.1, 0.1))
			entity.get_nav_agent().target_position = _snap_to_navmesh(player.global_position + jitter_offset)
	
	# ─── INVESTIGATION CONFUSION ────────────────────────────────
	if _is_investigating:
		_investigation_timer -= delta
		_calculated_velocity = Vector3.ZERO
		
		if sensory and sensory.has_method("can_entity_see_player") and sensory.can_entity_see_player():
			_is_investigating = false
			_investigation_timer = 0.0
		elif entity.is_hunting() and entity.get_current_interest_level() > 50.0:
			_is_investigating = false
			_investigation_timer = 0.0
		
		if _investigation_timer <= 0.0:
			_is_investigating = false
			entity.is_observe_finished = true
			entity.state_locked = false
			_calculated_velocity = Vector3.ZERO
			return
		else:
			return
	
	# ─── ARRIVED AT LAST_KNOWN_POSITION ─────────────────────────
	var lkp = entity.get_last_known_position()
	var dist_to_lkp = entity.global_position.distance_to(lkp)
	var nav_finished = entity.get_nav_agent().is_navigation_finished()
	
	# ─── STALK FREEZE FIX: STALE LKP + LIVE-PURSUIT GUARD ──────────
	# If last_known_position is Vector3.ZERO (the default), the Entity never
	# actually heard or saw the player — it was pathfinding toward world
	# origin. The nav agent reports "finished" immediately, and the check
	# below would enter the 4-second Investigation freeze while the player
	# is still being chased. Skip investigation for a default position so
	# the Entity keeps pursuing the player's live position instead.
	#
	# GRASS PATCH PARALYSIS ROOT CAUSE (diagnosed via STALK_DIAG logs):
	# The LKP is the last KNOWN position, but in STALK the NavAgent's
	# target_position is the PLAYER'S LIVE position (refreshed every 0.3s).
	# Getting within 3m of the stale LKP mid-pursuit + losing LOS for one
	# frame entered the 4-second Investigation freeze. After the 4s expired
	# the condition was still true, so it re-entered forever — paralysis.
	# Investigation must ONLY fire when the player has genuinely escaped:
	#   a) NavAgent finished / within 3m of the LKP
	#   b) Player not visible
	#   c) Player BEYOND the stalk chase radius (escaped the pursuit)
	#   d) NavAgent is NOT still aimed at the player's live position
	if (nav_finished or dist_to_lkp <= 3.0) and not _is_investigating and lkp != Vector3.ZERO:
		var can_see_player = false
		if sensory and sensory.has_method("can_entity_see_player"):
			can_see_player = sensory.can_entity_see_player()
		
		# The NavAgent target is refreshed to the player's live position
		# every PATH_UPDATE_INTERVAL. If it is still aimed near the player,
		# the Entity is mid-chase — never freeze.
		var chase_target_pos: Vector3 = entity.get_nav_agent().target_position
		var player_live_pos: Vector3 = player.global_position
		var still_chasing_player: bool = chase_target_pos.distance_to(player_live_pos) < 2.0
		var player_escaped_chase: bool = dist_to_player > (stalk_max_distance + 4.0)
		
		if not can_see_player and player_escaped_chase and not still_chasing_player:
			_is_investigating = true
			_investigation_timer = 4.0
			_calculated_velocity = Vector3.ZERO
			return
	
	# ─── APPLY SPEED WITH ALL MULTIPLIERS ───────────────────────
	# TASK 4: Multiply by the time-based acceleration multiplier so a long
	# chase makes the Entity progressively faster (capped at 200% base).
	var final_speed = entity.current_stalk_speed * _stalk_current_speed_mult * _stalk_accel_mult
	
	# ─── STALK FREEZE FIX: NAV GRACE GATING ─────────────────────────
	# Decay the rubberband grace timer each frame. While it is active
	# (0.3s after a teleport), do NOT trust is_navigation_finished() —
	# the async path computation hasn't delivered a route yet, and
	# treating "no path" as "arrived" zeroes the velocity.
	_stalk_rubberband_nav_grace = maxf(_stalk_rubberband_nav_grace - delta, 0.0)
	_stalk_nav_grace = maxf(_stalk_nav_grace - delta, 0.0)
	if entity.get_nav_agent().is_navigation_finished() and _stalk_rubberband_nav_grace <= 0.0 and _stalk_nav_grace <= 0.0:
		_calculated_velocity.x = 0.0
		_calculated_velocity.z = 0.0
	else:
		var next_pos = entity.get_nav_agent().get_next_path_position()
		var dir_2d := Vector2(next_pos.x - entity.global_position.x, next_pos.z - entity.global_position.z)
		if dir_2d.length() > 0.01:
			var move_dir_2d = dir_2d.normalized()
			_calculated_velocity.x = move_dir_2d.x * final_speed
			_calculated_velocity.z = move_dir_2d.y * final_speed

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
	# ─── HANDLE HALLROOM LIGHT TOGGLE DELAY ────────────────────────────
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
	
	# ─── PHASE 1: Find the EntityDoorWaypoint ───────────────────────────
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
	
	# ─── PHASE 2: Pathfinding toward the door waypoint ──────────────────
	_path_timer -= delta
	if _path_timer <= 0.0:
		_path_timer = PATH_UPDATE_INTERVAL
		entity.get_nav_agent().target_position = door_wp.global_position
	
	var dist_to_wp = entity.global_position.distance_to(door_wp.global_position)
	
	# ─── PHASE 3: Arrived at door ───────────────────────────────────────
	# Use the @export interaction_radius (default 2.5m) as the arrival
	# threshold. The Entity must be within this distance of the door waypoint
	# before it can open the door or trigger the breach animation. This
	# prevents "Bluetooth Door Opening" where the Entity triggers the breach
	# while still physically distant from the door.
	if dist_to_wp <= interaction_radius:
		# 3a. Open the door if it's closed
		var door = entity.get_door_node()
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
	
	# ─── PHASE 4: Movement toward waypoint ──────────────────────────────
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
	var night_manager_ref = night_manager
	if not night_manager_ref:
		return
	
	var current_night: int = night_manager_ref.current_night if "current_night" in night_manager_ref else 1
	
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
	
	# ─── NIGHT 2.2 VAN SEQUENCE: CABIN ENTRY FORCE FLINCH ────────────────
	# When the car-alarm sequence is active AND the player is inside the cabin
	# (escaping from the van chase), hard-override the Entity into FLINCH.
	# The FLINCH completion handler then immediately transitions to DORMANT
	# and hides the mesh (see _flinch_state). This hard-override only applies
	# during the Night 2.2 van sequence — never during normal gameplay.
	if night_manager_ref and "is_van_sequence_active" in night_manager_ref and night_manager_ref.is_van_sequence_active:
		# ─── PLAYER-INSIDE DETECTION (BUG FIX) ──────────────────────────
		# Previously this only armed FLINCH when entity.thinks_player_is_inside
		# was true. But when the player reaches the cabin from outside while the
		# Entity is STALKing them, that flag is false (the Entity still thinks
		# the player is outside). This caused the van-sequence override to never
		# fire, leaving the Entity stuck in a STALK/transition switching loop.
		# Now we also detect the player's actual room via the navigation module,
		# so the FLINCH → DORMANT sequence triggers the moment the player is
		# anywhere inside the cabin during the van sequence.
		var player_is_inside_cabin: bool = entity.thinks_player_is_inside
		var nav_mod = entity.get_navigation_module() if entity.has_method("get_navigation_module") else null
		if nav_mod and nav_mod.has_method("get_player_room"):
			var van_player_room = nav_mod.get_player_room()
			if van_player_room != "Outside" and van_player_room != "":
				player_is_inside_cabin = true
		
		var entity_in_van_state: int = entity.get_state()
		if entity_in_van_state != State.FLINCH and entity_in_van_state != State.DORMANT:
			if player_is_inside_cabin:
				entity.thinks_player_is_inside = true
				_van_sequence_flinch_armed = true
				entity.set_state(State.FLINCH)
				entity.state_locked = true
				_calculated_velocity = Vector3.ZERO
				print("[VAN SEQ] Player inside cabin during Night 2.2. Forcing Entity into FLINCH → DORMANT.")
	
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

## Counts down the "EnterWindow" vault-out animation during the indoor retreat.
## When the Entity reaches the breach window in Phase 1, this timer is set to
## enter_window_anim_duration (1.5s). The Entity plays the EnterWindow animation
## (reversed vault-out through the window frame) while this timer counts down.
## When it reaches 0.0, Phase 3 teleports the Entity outside. The controller's
## _update_animations() plays "EnterWindow" while this timer > 0 and the
## _indoor_retreat_phase == 2.
var _retreat_vault_timer: float = 0.0

func _retreat_state(delta: float) -> void:
	# Lock the state — the Director must not override while we're mid-retreat
	entity.state_locked = true
	
	# ─── INDOOR RETREAT MODE ────────────────────────────────────────────
	# The Entity was caught inside the cabin by the player's flashlight.
	# It must escape back through the breach window, then perform a 5-second
	# flinch before transitioning to OBSERVE_FROM_TREELINE.
	if entity.is_indoor_retreat:
		_indoor_retreat_handler(delta)
		return
	
	# ─── STANDARD OUTDOOR RETREAT ───────────────────────────────────────
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
## Whether the current indoor retreat is escaping through a WINDOW (true) or
## the DOOR (false). Set in Phase 0. Phase 2 teleports outside using the
## appropriate exit.
var _retreat_exit_was_window: bool = true

## The world-space position the Entity pathfinds to during Phase 1 before the
## Phase 2 outside-teleport. For window entries this is the indoor landing
## position; for door entries it is the door's interior position.
var _retreat_exit_pos: Vector3 = Vector3.ZERO

## Timer enforcing a MINIMUM sprint duration in Phase 1 before the proximity
## gate can advance to Phase 2 (teleport outside). Without this, an Entity
## already standing near the breach point (e.g. it breached the window the
## player is currently overcharging) completes Phase 1 on the FIRST frame and
## teleports outside instantly — skipping the visible sprint-to-exit escape.
## Measured in seconds. Reset to 0.0 in Phase 0. Gate fires when >= 1.5.
var _retreat_indoor_phase_1_timer: float = 0.0

## Minimum duration (seconds) the Entity must sprint toward the exit in
## Phase 1 before the proximity check can advance to Phase 2. This guarantees
## the player SEES the Entity physically escape toward the breach point,
## even when it is already within the 2m proximity gate.
const RETREAT_PHASE_1_MIN_DURATION: float = 1.5

func _indoor_retreat_handler(delta: float) -> void:
	var breach_window = entity.last_breached_window
	
	# ─── PHASE 0: Select escape target (window OR door) ────────────────
	if _indoor_retreat_phase == 0:
		# Reset the Phase 1 minimum sprint timer — a new escape sequence is beginning.
		_retreat_indoor_phase_1_timer = 0.0
		# ─── FLUSH STALE NAV PATH (BUG 2 FIX) ─────────────────────────
		# The NavigationAgent may still hold the previous INDOOR_SEARCH
		# patrol path (often ending near the door). Setting target_position
		# to the Entity's CURRENT position first forces the agent to discard
		# that stale path and recompute from scratch, so the first sprint
		# frame heads toward the breach window, not the doorway.
		entity.get_nav_agent().target_position = entity.global_position
		if breach_window and breach_window.has_method("get_indoor_landing_position"):
			# WINDOW ENTRY — escape back through the same window.
			_retreat_exit_was_window = true
			_retreat_exit_pos = breach_window.get_indoor_landing_position()
			entity.get_nav_agent().target_position = _retreat_exit_pos
			_indoor_retreat_phase = 1
			print("[INDOOR RETREAT] Phase 0: Window entry — pathfinding to breach window indoor landing position.")
		else:
			# DOOR ENTRY (or no breach window recorded) — escape through the
			# door the Entity came in through. Pathfind to the door's interior
			# position, then teleport to the exterior door waypoint in Phase 2.
			# This fixes the "Entity goes into FLINCH and never leaves the
			# cabin" bug for door entries.
			_retreat_exit_was_window = false
			var door_breach_wp = entity.get_door_breach_waypoint()
			if door_breach_wp:
				_retreat_exit_pos = door_breach_wp.global_position
			else:
				var door_node = entity.get_door_node()
				if door_node:
					_retreat_exit_pos = door_node.global_position
				else:
					_retreat_exit_pos = entity.global_position + Vector3(0, 0, 2.0)  # Fallback: toward door
			entity.get_nav_agent().target_position = _retreat_exit_pos
			_indoor_retreat_phase = 1
			print("[INDOOR RETREAT] Phase 0: Door entry — pathfinding to door interior position.")
	
	# ─── PHASE 1: Pathfind toward the escape point ─────────────────────
	if _indoor_retreat_phase == 1:
		# CRITICAL FIX: is_navigation_finished() alone is NOT sufficient to
		# advance to Phase 2. If the NavMesh doesn't cover the cabin interior
		# (documented limitation), the agent reports "finished" immediately
		# and the Entity advances to Phase 2 without ever moving toward the
		# exit — then teleports from wherever it is, which can leave it stuck
		# inside the cabin ("Entity runs around inside but never leaves").
		#
		# Fix: require physical proximity to the chosen exit point AND (nav
		# finished OR close enough via 2D distance).
		#
		# MINIMUM SPRINT WINDOW: Accumulate the Phase 1 timer. The proximity
		# gate below is NOT allowed to fire until the Entity has sprinted for
		# at least RETREAT_PHASE_1_MIN_DURATION (1.5s). Without this, an Entity
		# already standing at the breach point (the window the player is
		# overcharging) would complete Phase 1 on the FIRST frame and teleport
		# outside instantly — skipping the dramatic visible escape.
		_retreat_indoor_phase_1_timer += delta
		var exit_2d := Vector2(_retreat_exit_pos.x, _retreat_exit_pos.z)
		var ent_2d := Vector2(entity.global_position.x, entity.global_position.z)
		var dist_to_exit_2d: float = ent_2d.distance_to(exit_2d)
		var nav_finished_r = entity.get_nav_agent().is_navigation_finished()
		
		if _retreat_indoor_phase_1_timer >= RETREAT_PHASE_1_MIN_DURATION and (dist_to_exit_2d <= 2.0 or (nav_finished_r and dist_to_exit_2d <= 4.0)):
			# Physically at (or very near) the exit point — advance to Phase 2.
			_indoor_retreat_phase = 2
			print("[INDOOR RETREAT] Phase 1 complete. At exit (dist=%.2f). Advancing to Phase 2 (teleport outside)." % dist_to_exit_2d)
		else:
			# Still not close enough — keep sprinting toward the exit.
			# BUG 2 FIX (REVISED): Sprint DIRECTLY at the exit position. The
			# cabin interior is NOT covered by the NavMesh (documented
			# limitation), so following the NavigationAgent's path snaps both
			# the Entity and the exit target to outdoor NavMesh points and
			# routes through the front doorway — the "doorway detour" bug.
			# The Entity ignores cabin wall collisions during indoor retreat
			# (the interior is open-plan), so the straight line to the breach
			# window is always the correct escape vector. NavAgent following
			# is retained only as a last-resort safeguard if the direct line
			# degenerates (zero-length direction).
			var direct_exit = (_retreat_exit_pos - entity.global_position)
			direct_exit.y = 0.0
			if direct_exit.length() > 0.01:
				var direct_dir = direct_exit.normalized()
				_calculated_velocity.x = direct_dir.x * entity.current_stalk_speed * 1.5
				_calculated_velocity.z = direct_dir.z * entity.current_stalk_speed * 1.5
				# ─── FACE MOVEMENT DIRECTION (issue 2 fix) ─────────────
				# The sprint sets velocity directly, but nothing rotates the
				# monster model — so during the indoor retreat sprint it kept
				# the last INDOOR_SEARCH orientation (often 180° away from
				# the direction of travel, toward the cabin). Rotate the model
				# smoothly toward the escape heading every sprint frame.
				var retreat_model = entity.get_monster_model()
				if retreat_model:
					var retreat_angle = atan2(direct_dir.x, direct_dir.z)
					retreat_model.rotation.y = lerp_angle(retreat_model.rotation.y, retreat_angle, 0.15)
			else:
				var next_pos_r = entity.get_nav_agent().get_next_path_position()
				var dir_2d_r := Vector2(next_pos_r.x - entity.global_position.x, next_pos_r.z - entity.global_position.z)
				if dir_2d_r.length() > 0.01:
					var move_dir_2d_r = dir_2d_r.normalized()
					_calculated_velocity.x = move_dir_2d_r.x * entity.current_stalk_speed * 1.5
					_calculated_velocity.z = move_dir_2d_r.y * entity.current_stalk_speed * 1.5
			return
	
	# ─── PHASE 2: Teleport outside the exit ─────────────────────────────
	if _indoor_retreat_phase == 2:
		if _retreat_exit_was_window and breach_window:
			# WINDOW EXIT — teleport to the window's EXTERIOR.
			# Prefer the WindowMarker child (guaranteed to face outward),
			# falling back to the raw CabinWindow position with an offset
			# along its -Z basis (the exterior-facing side).
			var outside_pos: Vector3
			if breach_window.has_node("WindowMarker"):
				var marker: Node3D = breach_window.get_node("WindowMarker")
				outside_pos = marker.global_position
			else:
				var window_pos = breach_window.global_position
				var window_basis = breach_window.global_transform.basis
				outside_pos = window_pos - window_basis.z * 2.5
			outside_pos.y = entity.global_position.y  # Keep current Y to avoid vertical snapping
			entity.global_position = outside_pos
			entity.velocity = Vector3.ZERO
			# ─── RESTORE OUTDOOR COLLISION MASK (issue 1 fix) ─────────
			# During INDOOR_SEARCH the Entity's collision mask is forced to
			# Player-only (Cabin geometry ignored). After the teleport the
			# Entity is OUTSIDE — restore the full outdoor mask (Cabin /
			# Player / Trees / Rocks) so the flashlight LOS raycast and
			# physics interactions with the environment work normally again.
			entity.collision_mask = 0
			entity.collision_mask |= (1 << (1 - 1))  # Layer 1: Cabin
			entity.collision_mask |= (1 << (2 - 1))  # Layer 2: Player
			entity.collision_mask |= (1 << (3 - 1))  # Layer 3: Trees
			entity.collision_mask |= (1 << (4 - 1))  # Layer 4: Rocks
			# ─── FACE OUTWARD (issue 1 fix) ───────────────────────────
			# The Entity lands at the WindowMarker looking INWARD toward the
			# cabin. Rotate the monster model to face AWAY from the window
			# (out into the forest) so the FLINCH sprint direction is correct
			# and the Entity is not staring into the window it just left.
			var retreat_out_model = entity.get_monster_model()
			if retreat_out_model and breach_window:
				var outward = (entity.global_position - breach_window.global_position)
				outward.y = 0.0
				if outward.length() > 0.01:
					var outward_dir = outward.normalized()
					retreat_out_model.rotation.y = atan2(outward_dir.x, outward_dir.z)
			print("[INDOOR RETREAT] Phase 2: Teleported outside via WINDOW to (%.2f, %.2f, %.2f)" % [outside_pos.x, outside_pos.y, outside_pos.z])
			
			# SAFETY: verify the teleport actually landed OUTSIDE. If the
			# window was oriented away from the cabin, the offset may still
			# be inside — fall back to a NavMesh-snapped far point.
			if entity.has_method("is_physically_inside") and entity.is_physically_inside():
				var nav_map_r = entity.get_world_3d().navigation_map
				var fallback_r = breach_window.global_position - (breach_window.global_transform.basis.z * 6.0)
				fallback_r.y = entity.global_position.y
				var snapped_r = NavigationServer3D.map_get_closest_point(nav_map_r, fallback_r)
				snapped_r.x = fallback_r.x
				snapped_r.z = fallback_r.z
				entity.global_position = snapped_r
				entity.velocity = Vector3.ZERO
				print("[INDOOR RETREAT] SAFETY: Teleport was still inside! Forced to NavMesh point (%.2f, %.2f, %.2f)" % [snapped_r.x, snapped_r.y, snapped_r.z])
		else:
			# DOOR EXIT — teleport to the door's exterior waypoint (or the
			# door position if no exterior marker exists).
			var outside_pos: Vector3
			var door_wp = entity.get_door_waypoint_marker()
			if door_wp:
				outside_pos = door_wp.global_position
			else:
				var door_node = entity.get_door_node()
				if door_node:
					var door_basis = door_node.global_transform.basis
					outside_pos = door_node.global_position - door_basis.z * 2.0
				else:
					outside_pos = entity.global_position + Vector3(0, 0, -2.0)
			outside_pos.y = entity.global_position.y  # Keep current Y to avoid vertical snapping
			entity.global_position = outside_pos
			entity.velocity = Vector3.ZERO
			print("[INDOOR RETREAT] Phase 2: Teleported outside via DOOR to (%.2f, %.2f, %.2f)" % [outside_pos.x, outside_pos.y, outside_pos.z])
		
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
		# ─── CLEAR PERSISTENT RETREAT COMMITMENT ─────────────────────
		# The Entity has physically escaped outside through the window/door.
		# Clear the commitment flag so the Director can evaluate normally —
		# the Entity is now OUTSIDE, so the outdoor flashlight matrix (FLINCH,
		# STANDOFF, CHARGE) applies again for the 5-second flinch sprint.
		entity.is_indoor_retreat_pending = false
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
##   APPROACH_WINDOW → OBSERVE_FROM_TREELINE 60fps oscillation loop.
var _approach_min_timer: float = 0.0
const APPROACH_MIN_DURATION: float = 2.0

## ─── APPROACH FAILSAFE TIMEOUT ──────────────────────────────────────────────
## If the Entity has been in APPROACH_WINDOW for more than 15 seconds without
## arriving at the window, force a completion signal to prevent permanent
## soft-locks. This can happen when the NavMesh can't reach the window
## (e.g., the cabin wall blocks pathfinding) and the Entity stutters at the
## edge of the NavMesh indefinitely.
### NOTE: The actual timeout value is set via @export approach_failsafe_timeout.
### The const below is kept as a reference default but the @export
### is the canonical source of truth.
var _approach_failsafe_timer: float = 0.0

## ─── APPROACH DEBUG LOG TIMER ──────────────────────────────────────────────
## Prints Entity and window coordinates every 2 seconds during APPROACH_WINDOW
## to help debug pathfinding issues (e.g., Entity not moving toward the window,
## NavMesh can't reach the target, or the Entity is stuck at the cabin wall).
var _approach_debug_timer: float = 0.0
const APPROACH_DEBUG_INTERVAL: float = 2.0

## ─── FRESH-ENTRY SNAPSHOT (self-contained state change detection) ──────
## The state value that last (successfully) called _approach_window_state().
## Used to detect a FRESH ENTRY into APPROACH_WINDOW so the failsafe and
## minimum timers are reset to 0.0. Without this, if the Entity was in
## APPROACH_WINDOW for 7 seconds, got interrupted by FLINCH (via the
## flashlight), and later re-entered APPROACH_WINDOW, the stale
## _approach_failsafe_timer (7.0s) would trigger the now-shortened 8s
## failsafe after just 1 more second — causing an instant WINDOW_PEEK or
## OBSERVE transition on a legitimate fresh approach. Does NOT depend on
## entity.get_previous_state() (which is unreliable — see the SABOTAGE_FUSE
## _last_sabotage_call_state pattern).
var _last_approach_call_state: int = -1

func _approach_window_state(delta: float) -> void:
	# ─── FRESH-ENTRY TIMER RESET ──────────────────────────────────────
	# If the state changed since the last call to this handler, this is a
	# fresh APPROACH_WINDOW entry. Reset both the minimum-approach timer and
	# the failsafe timer so stale values from a previous interrupted session
	# cannot fire prematurely. The timers are NOT reset on every frame —
	# only when the state actually changes.
	if entity.get_state() != _last_approach_call_state:
		_last_approach_call_state = entity.get_state()
		_approach_min_timer = 0.0
		_approach_failsafe_timer = 0.0
		_approach_debug_timer = 0.0
		_consecutive_door_failsafe_count = 0
	
	# ─── TASK 1.1: POST-FLINCH RE-ENTRY COOLDOWN ─────────────────────
	# After a FLINCH completes, the stale is_illuminated / is_overcharged
	# booleans may persist for a frame or two (they are cleared by the FLINCH
	# handler, but the Director's throttled evaluation could re-enter
	# APPROACH_WINDOW before the perception system recomputes them). This
	# 3-frame cooldown prevents the 1-frame approach → flinch oscillation
	# that consumed the failsafe timers and made the Entity appear "stuck."
	# ─── ISSUE 3 FIX: DIRECT OVERCHARGE QUERY ─────────────────────────
	# The entity.is_overcharged blackboard bool is written by on_player_stare()
	# only when the player's LOS raycast actually hits the Entity. During the
	# post-flinch window there can be a gap where the bool is stale (false)
	# even though the player is still holding the overcharge beam. Query the
	# player controller's LIVE overcharge state directly and OR it in, so the
	# FLINCH OVERRIDE GATE can never "ignore" a held overcharge beam.
	var _direct_overcharge: bool = entity.is_overcharged
	var _player_ref_gate = entity.get_player()
	if _player_ref_gate and "is_flashlight_overcharged" in _player_ref_gate:
		_direct_overcharge = _direct_overcharge or _player_ref_gate.is_flashlight_overcharged()
	
	# ─── ISSUE 3 FIX: POST-FLINCH RE-ENTRY COOLDOWN (OVERRIDE IMMUNE) ─────
	# This 0.5s cooldown delays NORMAL APPROACH_WINDOW re-entry after a
	# FLINCH so the perception system can catch up, preventing the 1-frame
	# approach → flinch oscillation (Task 1.1). CRITICAL: the cooldown must
	# NEVER block an ACTIVE overcharge beam. If _direct_overcharge is true
	# (player still holding the overcharge), the gate below must re-flinch
	# the Entity immediately rather than let it stand ignoring the light.
	if _flinch_exit_cooldown > 0.0 and not _direct_overcharge:
		_flinch_exit_cooldown -= delta
		_calculated_velocity = Vector3.ZERO
		entity.state_locked = false
		return
	elif _flinch_exit_cooldown > 0.0:
		# Overcharge active during cooldown — keep ticking so it still
		# expires normally for the NEXT re-entry, but do NOT early-return.
		_flinch_exit_cooldown -= delta
	
	# ─── FLINCH OVERRIDE GATE (direct force-transition) ─────────────────
	# If the Entity is illuminated by the player's flashlight while the player
	# is inside, force FLINCH directly instead of waiting for the throttled
	# Director. The old approach tried to unlock state_locked and return early,
	# but the state dispatcher immediately re-enters _approach_window_state on
	# the next frame, which re-locks the state before the 0.2s Director throttle
	# fires. This created a race condition where FLINCH never triggered because
	# the Director always saw state_locked=true.
	#
	# FIX: Set the state directly and lock the NEW state (FLINCH) so the FLINCH
	# handler runs to completion. This mirrors the Tier 0 Override Gate in
	# process_state_logic().
	# NOTE: Access entity.thinks_player_is_inside directly (a public var).
	# DO NOT use has_method("get_thinks_player_is_inside") — plain GDScript
	# vars do NOT auto-generate get_*() methods, so has_method always
	# returns false, silently preventing the FLINCH transition.
	#
	# ISSUE 3 FIX: The OVERRIDE GATE runs BEFORE the post-flinch cooldown
	# check below. The cooldown is meant to delay normal APPROACH_WINDOW
	# re-entry (so the perception system catches up), but it must NEVER
	# block the overcharge reaction — if the player is still holding the
	# overcharge beam when the flinch finishes, the Entity MUST re-flinch
	# immediately rather than stand there ignoring the light.
	
	if entity.is_illuminated and entity.thinks_player_is_inside and _direct_overcharge:
		# ─── INDOOR RETREAT GATE ─────────────────────────────────────
		# The FLINCH OVERRIDE is intended for the Entity approaching a WINDOW
		# from OUTSIDE. If the Entity is physically INSIDE the cabin, this
		# direct set_state(FLINCH) bypasses the Director's unified overcharge
		# dispatch (which correctly returns RETREAT indoors). Gate the FLINCH
		# to outdoor-only so an indoor Entity proceeds to the Director's
		# normal evaluation (which handles the overcharge → RETREAT path).
		#
		# CRITICAL: Also gate on is_overcharged — ONLY the overcharged
		# flashlight beam may force a FLINCH. The standard beam is IGNORED
		# so the Entity keeps approaching the window.
		if not (entity.has_method("is_physically_inside") and entity.is_physically_inside()):
			# ─── TASK 1.2: BAN THE INTERRUPTED ROOM ───────────────────
			# The Entity is being interrupted at this window by an overcharged
			# flashlight. Ban the room this window belongs to so the Entity
			# cannot immediately re-target another window in the same room.
			# The ban is cleared once a window in a DIFFERENT room is
			# successfully targeted (handled in the window selection flow).
			var interrupt_win = entity.get_current_window_target()
			if interrupt_win and _banned_room.is_empty():
				if interrupt_win.has_method("get_room_id"):
					_banned_room = str(interrupt_win.get_room_id())
					print("[TASK 1.2] Window interrupted! Banning room '%s' from window selection." % _banned_room)
				elif "room_id" in interrupt_win:
					_banned_room = str(interrupt_win.room_id)
					print("[TASK 1.2] Window interrupted! Banning room '%s' from window selection." % _banned_room)
				elif interrupt_win.has_method("get_room_name"):
					_banned_room = str(interrupt_win.get_room_name())
					print("[TASK 1.2] Window interrupted! Banning room '%s' from window selection." % _banned_room)
			
			entity.set_state(EntityAI.State.FLINCH)
			entity.state_locked = true  # Lock the new FLINCH state
			_calculated_velocity = Vector3.ZERO
		return
	
	# Lock the state — the Director must not override while we're mid-approach
	entity.state_locked = true
	
	# ─── MINIMUM APPROACH TIMER ─────────────────────────────────────────
	# Accumulate time spent in APPROACH_WINDOW. The Entity must spend at
	# least 2.0 seconds pathfinding before it can signal completion.
	# This prevents instant arrival when the NavigationAgent finishes
	# prematurely (e.g., NavMesh can't reach the exact window coordinate).
	_approach_min_timer += delta
	_approach_failsafe_timer += delta
	
	# ─── FAILSAFE TIMEOUT ───────────────────────────────────────────────
	# If the Entity has been pathfinding for more than 15 seconds without
	# arriving, force a completion signal. This prevents permanent soft-locks
	# when the NavMesh can't reach the window (e.g., the cabin wall blocks
	# pathfinding) and the Entity stutters at the edge of the NavMesh.
	#
	# DOOR HANDLING: If the window_target is a door, the failsafe must
	# teleport the Entity to the IndoorBreachWaypoint (just like Phase 2's
	# failsafe) instead of just signaling completion. Without this, the
	# Entity gets stuck outside the door and the Director transitions to
	# INDOOR_SEARCH with was_door_entry=true but the Entity is still 15m
	# away in the forest — the INDOOR_SEARCH Phase A door entry handler
	# can't pathfind from there, causing a desync.
	if _approach_failsafe_timer >= approach_failsafe_timeout:
		print("[Entity AI] APPROACH_WINDOW FAILSAFE: %ds elapsed without arrival. Forcing completion." % approach_failsafe_timeout)
		
		# ─── CHECK IF TARGET IS A DOOR ────────────────────────────────────
		# Use the cached @export door_waypoint_marker reference to check if
		# the current window target IS the door waypoint. This replaces the
		# expensive per-frame duck-typing checks (has_method("is_in_group"),
		# "is_open" in window_target, etc.) that were called every frame.
		var failsafe_window_target = entity.get_current_window_target()
		var is_door_failsafe: bool = false
		var cached_door_wp = entity.get_door_waypoint_marker()
		if failsafe_window_target and cached_door_wp:
			if failsafe_window_target == cached_door_wp:
				is_door_failsafe = true
			elif failsafe_window_target.get_parent() == cached_door_wp.get_parent():
				is_door_failsafe = true
		
		if is_door_failsafe:
			# ─── DOOR FAILSAFE: Teleport to IndoorBreachWaypoint ──────────
			# The Entity failed to reach the door within 15 seconds. Teleport
			# directly to the IndoorBreachWaypoint so the INDOOR_SEARCH Phase A
			# handler can immediately detect arrival and start Phase B patrol.
			# Use the waypoint's exact Y coordinate to avoid floor clipping.
			#
			# PROXIMITY GUARD: Only teleport if the Entity is within 5.0m of
			# the door waypoint. If the Entity is farther away (e.g., stuck at
			# the NavMesh edge 15m from the door), the failsafe should NOT
			# teleport — it should just signal completion and let the Director
			# fall back to OBSERVE_FROM_TREELINE. Teleporting from 15m away
			# would cause a jarring visual pop and desync the Entity's position
			# from the NavMesh.
			print("[Entity AI] APPROACH_WINDOW FAILSAFE: Door target detected. Teleporting to IndoorBreachWaypoint.")
			var door_node_fs = entity.get_door_node()
			if not door_node_fs:
				door_node_fs = failsafe_window_target
			var breach_wp_fs: Node3D = entity.get_door_breach_waypoint()
			if breach_wp_fs:
				# ─── 2D PROXIMITY CHECK ──────────────────────────────────────
				# Only teleport if the Entity is within 5.0m of the door waypoint.
				# This prevents jarring teleports from across the map.
				var my_pos_2d_fs = Vector2(entity.global_position.x, entity.global_position.z)
				var wp_pos_2d_fs = Vector2(breach_wp_fs.global_position.x, breach_wp_fs.global_position.z)
				var dist_2d_fs = my_pos_2d_fs.distance_to(wp_pos_2d_fs)
				if dist_2d_fs <= 5.0:
					var teleport_pos = breach_wp_fs.global_position
					entity.global_position = teleport_pos
					entity.velocity = Vector3.ZERO
					print("[Entity AI] APPROACH_WINDOW FAILSAFE: Teleported to IndoorBreachWaypoint at ", teleport_pos)
				else:
					# ─── DISTANT DOOR: Re-target a window instead ─────────────
					# The Entity is too far from the door to teleport. Instead of
					# signaling completion (which lets the Director transition to
					# WINDOW_PEEK and trigger a ghost breach), we re-target a
					# reachable window and reset all timers so the Entity stays in
					# APPROACH_WINDOW with a clean slate.
					#
					# This prevents the "ghost breach" bug where the Director
					# transitions to WINDOW_PEEK while the Entity is still 20m
					# away in the forest, causing the breach animation to fire
					# and teleport the Entity inside from across the map.
					print("[Entity AI] APPROACH_WINDOW FAILSAFE: Door target but Entity is %.2fm away (threshold=5.0m). Re-targeting a window." % dist_2d_fs)
					
					# ─── INCREMENT CONSECUTIVE DOOR FAILSAFE COUNTER ──────────
					_consecutive_door_failsafe_count += 1
					print("[Entity AI] APPROACH_WINDOW FAILSAFE: Consecutive door failsafe count: %d/%d" % [_consecutive_door_failsafe_count, MAX_DOOR_FAILSAFE_RETRIES])
					
					# ─── SECONDARY ESCAPE HATCH ───────────────────────────────
					# After MAX_DOOR_FAILSAFE_RETRIES consecutive failures, give
					# up on the door entirely and fall back to OBSERVE_FROM_TREELINE.
					# This prevents infinite re-targeting loops when the NavMesh
					# can never reach the door.
					if _consecutive_door_failsafe_count >= MAX_DOOR_FAILSAFE_RETRIES:
						print("[Entity AI] APPROACH_WINDOW FAILSAFE: Max consecutive door failsafe retries (%d) reached! Giving up on door. Falling back to OBSERVE." % MAX_DOOR_FAILSAFE_RETRIES)
						_consecutive_door_failsafe_count = 0
						entity.was_door_entry = false
						entity.is_door_target = false
						entity.is_approach_finished = true
						entity.state_locked = false
						_approach_min_timer = 0.0
						_approach_failsafe_timer = 0.0
						_calculated_velocity = Vector3.ZERO
						return
					
					# ─── CLEAR DOOR TARGET ────────────────────────────────────
					# Clear the current window target so the Entity re-selects a
					# reachable window on the next frame. The APPROACH_WINDOW
					# handler will call pick_tactical_window() which returns a
					# window (not the door), since the door waypoint was the
					# previous target.
					entity.set_current_window_target(null)
					
					# ─── RESET ALL TIMERS ─────────────────────────────────────
					# Reset the minimum approach timer, failsafe timer, and debug
					# timer so the Entity starts the APPROACH_WINDOW behavior with
					# a clean slate. Without this, the minimum timer would still be
					# high and the Entity might immediately re-trigger the failsafe
					# on the very next frame.
					_approach_min_timer = 0.0
					_approach_failsafe_timer = 0.0
					_approach_debug_timer = 0.0
					
					# ─── RESET DOOR STATE ─────────────────────────────────────
					# Reset all door-related state so the Entity doesn't think it's
					# still in the middle of a door approach. This prevents stale
					# state from contaminating the next window approach.
					entity.was_door_entry = false
					entity.is_door_target = false
					entity._door_phase = 0
					entity._door_phase_timer = 0.0
					entity._door_phase_2_timer = 0.0
					entity._ghost_door_phase_2 = false
					entity._ghost_mode = false
					entity.is_breach_locked = false
					
					# ─── RESTORE PHYSICS ──────────────────────────────────────
					# If the ghost motor was active, restore collision and physics
					# so the Entity can pathfind normally to the new window target.
					entity.set_collision_mask_value(1, true)
					if entity.has_method("get_collision_shape"):
						entity.get_collision_shape().disabled = false
					entity.is_physics_suspended = false
					
					_calculated_velocity = Vector3.ZERO
					return
			else:
				# No breach waypoint found — just signal completion
				print("[Entity AI] APPROACH_WINDOW FAILSAFE: Door target but no breach waypoint found. Signaling completion.")
				entity.is_approach_finished = true
				entity.state_locked = false
				_approach_min_timer = 0.0
				_approach_failsafe_timer = 0.0
				_calculated_velocity = Vector3.ZERO
				return
			
			# ─── RESET CONSECUTIVE COUNTER ON SUCCESSFUL TELEPORT ──────────
			# The Entity successfully teleported to the IndoorBreachWaypoint.
			# Reset the consecutive door failsafe counter so the next door
			# approach starts fresh.
			_consecutive_door_failsafe_count = 0
			
			entity.was_door_entry = true
			entity.is_door_target = true
		else:
			# ─── WINDOW FAILSAFE: Distance-aware completion ─────────────────
			# The 15-second failsafe fired while approaching a WINDOW. We MUST
			# NOT blindly signal completion — if the Entity is still far from
			# the window (e.g. 20m in the forest), transitioning to WINDOW_PEEK
			# would start the siege while far away, and the breach would teleport
			# the Entity inside from across the map.
			#
			# Fix: if the Entity is within a sane arrival band (2.5m) of the
			# WindowMarker, treat as arrived → WINDOW_PEEK. Otherwise, clear the
			# window target so the Director's NULL TARGET GUARD returns
			# OBSERVE_FROM_TREELINE (picking a different window on the next
			# confidence escalation) instead of WINDOW_PEEK.
			_consecutive_door_failsafe_count = 0
			
			var failsafe_entity_pos = entity.global_position
			var failsafe_marker_pos = failsafe_window_target.global_position
			if failsafe_window_target.has_node("WindowMarker"):
				failsafe_marker_pos = failsafe_window_target.get_node("WindowMarker").global_position
			
			var dist_fs_2d := Vector2(failsafe_entity_pos.x, failsafe_entity_pos.z).distance_to(
				Vector2(failsafe_marker_pos.x, failsafe_marker_pos.z))
			
			if dist_fs_2d <= approach_arrival_distance:
				# Close enough — genuine arrival. Keep the target so the
				# Director transitions to WINDOW_PEEK.
				print("[Entity AI] APPROACH_WINDOW FAILSAFE: Window target within %.2f m. Treating as arrived → WINDOW_PEEK." % dist_fs_2d)
			else:
				# Too far — clear target and let the NULL TARGET GUARD
				# fall back to OBSERVE_FROM_TREELINE (next cycle re-picks).
				print("[Entity AI] APPROACH_WINDOW FAILSAFE: Still %.2f m from window. Clearing target → OBSERVE." % dist_fs_2d)
				entity.set_current_window_target(null)
		
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
			print("[DIAG] WINDOW SELECTION: pick_tactical_window() returned '%s' (ID=%s)" % [best_window.name, best_window.get_window_id() if best_window.has_method("get_window_id") else "?"])
			entity.set_current_window_target(best_window)
			
			# ─── TASK 1.2: CLEAR ROOM BAN ON NEW ROOM TARGET ──────────
			# A new window was successfully targeted. If this window belongs
			# to a DIFFERENT room than the currently banned room, the ban is
			# lifted — the Entity has moved on to a new room.
			if not _banned_room.is_empty():
				var new_room_id: String = ""
				if best_window.has_method("get_room_id"):
					new_room_id = str(best_window.get_room_id())
				elif "room_id" in best_window:
					new_room_id = str(best_window.room_id)
				elif best_window.has_method("get_room_name"):
					new_room_id = str(best_window.get_room_name())
				if new_room_id != _banned_room and not new_room_id.is_empty():
					print("[TASK 1.2] New window in room '%s' differs from banned room '%s'. Ban lifted." % [new_room_id, _banned_room])
					_banned_room = ""
			# ─── RESOLVE WINDOW MARKER ────────────────────────────────────────
			# The CabinWindow node is at the window frame (inside the wall).
			# The WindowMarker child is offset outside the window and is the
			# actual position the Entity should pathfind to.
			var approach_target = best_window
			if best_window.has_node("WindowMarker"):
				approach_target = best_window.get_node("WindowMarker") as Node3D
			
			# ─── FLATTEN Y-AXIS: Force ground-level pathfinding ──────────────
			# Second-story windows have Y ≈ 3.0m. The NavMesh is at ground
			# level (Y ≈ 0.0). Setting target_position to the marker's raw
			# 3D coordinate causes the NavigationAgent3D to fail — it can't
			# find a path to a point 3m above the NavMesh surface.
			# By flattening Y to the Entity's current Y, we force ground-
			# level pathfinding to the marker's XZ position.
			var flat_target = approach_target.global_position
			flat_target.y = entity.global_position.y
			entity.get_nav_agent().target_position = flat_target
			window_target = best_window
			
			# ─── DEBUG PRINT ────────────────────────────────────────────────
			var selected_id: String = ""
			if best_window.has_method("get_window_id"):
				selected_id = best_window.get_window_id()
			elif "window_id" in best_window:
				selected_id = best_window.window_id
			print("[Entity AI] Tactical window selected: %s (marker at %.2f, %.2f, %.2f)" % [selected_id, approach_target.global_position.x, approach_target.global_position.y, approach_target.global_position.z])
		else:
			print("[DIAG] WINDOW SELECTION: pick_tactical_window() returned NULL! No windows available within range.")
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
		# ─── PERIODIC DEBUG LOG (every 2 seconds) ──────────────────────────
		# Prints Entity and window coordinates to help debug pathfinding
		# issues during APPROACH_WINDOW. This is especially useful for
		# diagnosing NavMesh reachability problems where the Entity gets
		# stuck at the edge of the NavMesh near the cabin wall.
		# ─── DIAG: Log window selection each cycle ──────────────────────
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
		
		# ─── RESOLVE THE ACTUAL APPROACH TARGET ────────────────────────────
		# The window_target is the CabinWindow node, which is positioned AT
		# the window frame (inside the cabin wall). The Entity cannot pathfind
		# to that position because the wall collision blocks it. Instead, we
		# must target the WindowMarker child, which is intentionally offset
		# outside the window (e.g., Z=-1.45 relative to the CabinWindow).
		# The WindowMarker is the "stand here and peek" position.
		var approach_target: Node3D = window_target
		if window_target.has_node("WindowMarker"):
			approach_target = window_target.get_node("WindowMarker") as Node3D
		
		# ─── SET NAV TARGET TO WINDOW MARKER POSITION ──────────────────────
		# CRITICAL: The NavigationAgent's target_position must be explicitly
		# set to the marker's position every frame (throttled to 300ms).
		# Without this, the target_position retains the stale value from the
		# previous state (e.g., a treeline vantage point from OBSERVE state).
		# The Entity would pathfind to the old treeline marker, the 2D distance
		# check would pass (because it's close to the old target), and the
		# "Arrived at DOOR!" logic would trigger while the Entity is still
		# 25 meters away in the forest.
		#
		# We flatten Y to the Entity's current Y so the NavMesh can find a
		# ground-level path to the marker's XZ position. Second-story windows
		# have Y ≈ 3.0m, but the NavMesh is at ground level (Y ≈ 0.0).
		# Setting target_position to the raw 3D coordinate would cause the
		# NavigationAgent3D to fail — it can't find a path to a point 3m
		# above the NavMesh surface.
		_path_timer -= delta
		if _path_timer <= 0.0:
			_path_timer = PATH_UPDATE_INTERVAL
			var flat_window_pos = approach_target.global_position
			flat_window_pos.y = entity.global_position.y
			entity.get_nav_agent().target_position = flat_window_pos
		
		# ─── 2D DISTANCE CHECK: Ignore vertical height differences ─────────
		# The NavMesh is at ground level (Y ≈ 0.0). The window target may be
		# at Y ≈ 3.0m (second story). Using 3D distance would include the
		# vertical component, making the Entity think it's farther away than
		# it actually is. We project both positions to 2D (XZ plane) for an
		# accurate ground-level distance check.
		#
		# NOTE: We measure distance to the approach_target's XZ position
		# (the WindowMarker, not the CabinWindow). The WindowMarker is the
		# ground truth for arrival detection.
		var my_pos_2d = Vector2(entity.global_position.x, entity.global_position.z)
		var window_pos_2d = Vector2(approach_target.global_position.x, approach_target.global_position.z)
		var dist_2d = my_pos_2d.distance_to(window_pos_2d)
		
		# ─── ARRIVAL CHECK: 2D distance threshold (generous 2.5m) ──────────
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
		
		# ─── STANDARD PATH-FOLLOWING MOVEMENT (non-door) ─────────────────────
		# Follow the navigation path toward the window marker. This is the
		# default movement for standard window approaches (not the door).
		# Door Phase 2 has its own movement handler below.
		if entity._door_phase != 2:
			if not nav_finished:
				var next_pos = entity.get_nav_agent().get_next_path_position()
				var dir_2d := Vector2(next_pos.x - entity.global_position.x, next_pos.z - entity.global_position.z)
				if dir_2d.length() > 0.01:
					var move_dir_2d = dir_2d.normalized()
					_calculated_velocity.x = move_dir_2d.x * entity.current_stalk_speed
					_calculated_velocity.z = move_dir_2d.y * entity.current_stalk_speed
					return
			else:
				# ─── NAV FINISHED BUT NOT YET AT WINDOW ─────────────────────
				# The NavMesh can't get us closer. Stop moving immediately and
				# wait for the failsafe timeout or distance threshold.
				# CRITICAL FIX: Force velocity to ZERO in the physics engine
				# to stop the jitter loop where ground snapping + nav agent
				# fight over the Entity's Y position. Without this, the Entity
				# jitters in place and the _path_timer re-triggers next frame.
				_calculated_velocity = Vector3.ZERO
				entity.velocity = Vector3.ZERO
				# ─── DIAG: Log Y position when stuck at nav edge ──────
			# Prevent the path timer from re-triggering next frame by
			# setting it to a high value. Without this, _path_timer -= delta
			# on the next frame causes _path_timer <= 0.0, which resets
			# target_position and re-engages the nav agent, creating a
			# 60fps NavFinished=true→false→true jitter loop.
			_path_timer = PATH_UPDATE_INTERVAL
		
		# ─── DOOR PHASE 2 LOOP: Runs every frame when _door_phase == 2 ─────
		# This MUST be checked BEFORE the arrival check below, because once
		# the Entity enters Phase 2 (walking through the doorway), the Phase 2
		# loop needs to run every frame independently of the distance check.
		# If we put it inside the arrival check block, the arrival check
		# re-fires every frame (dist is still < 2.5m), causing the Phase 2
		# loop to re-enter from scratch each frame — the ghost motor lerps
		# the position, but the "Arrived at DOOR!" print floods the console
		# and the logic is re-entered unnecessarily.
		#
		# BREACH LOCK: When _door_phase == 2, the Entity is mid-breach
		# (walking through the doorway via ghost motor). We set
		# is_breach_locked = true to prevent the Director from transitioning
		# to INDOOR_SEARCH before the ghost motor reaches the
		# IndoorBreachWaypoint. The Director's breach lock guard (checked
		# BEFORE state_locked) returns the current state when is_breach_locked
		# is true, preventing premature transition.
		if entity._door_phase == 2:
			# ─── SET BREACH LOCK ON FIRST FRAME OF PHASE 2 ──────────────────
			# This prevents the Director from transitioning to INDOOR_SEARCH
			# before the ghost motor has lerped the Entity through the doorway
			# to the IndoorBreachWaypoint. The lock is released when Phase 2
			# completes (arrival check below) or the failsafe fires.
			entity.is_breach_locked = true
			
			# ─── DELEGATE TO CONTROLLER'S GHOST MOTOR ────────────────────────
			# If the controller's ghost motor is already handling Phase 2,
			# just zero out velocity and return — the controller handles the
			# lerp, arrival check, and completion signaling.
			if entity._ghost_door_phase_2:
				_calculated_velocity = Vector3.ZERO
				return
			
			# ─── RESOLVE THE BREACH WAYPOINT POSITION ────────────────────────
			var breach_wp: Node3D = entity.get_door_breach_waypoint()
			
			if not breach_wp:
				print("[Entity AI] APPROACH_WINDOW: No DoorBreachWaypoint found on Door. Signaling completion.")
				entity.is_breach_locked = false
				entity.was_door_entry = true
				entity.is_approach_finished = true
				entity.state_locked = false
				entity._door_phase = 0
				entity._door_phase_2_timer = 0.0
				_approach_min_timer = 0.0
				_approach_failsafe_timer = 0.0
				_calculated_velocity = Vector3.ZERO
				return
			
			var waypoint_pos = breach_wp.global_position
			waypoint_pos.y = entity.global_position.y  # Flatten Y
			
			# ─── ARRIVAL CHECK (before starting ghost motor) ─────────────────
			var dist_to_wp2 = entity.global_position.distance_to(waypoint_pos)
			if dist_to_wp2 <= door_phase_2_arrival_distance:
				print("[Entity AI] APPROACH_WINDOW: Phase 2 complete! Already at IndoorBreachWaypoint (dist=%.2f). Signaling completion." % dist_to_wp2)
				entity.is_breach_locked = false
				entity.was_door_entry = true
				entity.is_approach_finished = true
				entity.state_locked = false
				entity._door_phase = 0
				entity._door_phase_2_timer = 0.0
				_approach_min_timer = 0.0
				_approach_failsafe_timer = 0.0
				_calculated_velocity = Vector3.ZERO
				# Restore physics in case ghost motor was active
				entity.set_collision_mask_value(1, true)
				if entity.has_method("get_collision_shape"):
					entity.get_collision_shape().disabled = false
				entity.is_physics_suspended = false
				return
			
			# ─── NAVMESH PATHFINDING ────────────────────────────────────────
			var nav_finished2 = entity.get_nav_agent().is_navigation_finished()
			
			if not nav_finished2:
				# NavMesh path is active — follow it
				entity.set_path_timer(entity.get_path_timer() + delta)
				if entity.get_path_timer() >= entity.path_update_interval:
					entity.set_path_timer(0.0)
					entity.get_nav_agent().target_position = waypoint_pos
				
				var next_pos = entity.get_nav_agent().get_next_path_position()
				var dir_2d := Vector2(next_pos.x - entity.global_position.x, next_pos.z - entity.global_position.z)
				if dir_2d.length() > 0.01:
					var move_dir_2d = dir_2d.normalized()
					_calculated_velocity.x = move_dir_2d.x * entity.current_stalk_speed
					_calculated_velocity.z = move_dir_2d.y * entity.current_stalk_speed
				return
			
			# ─── GHOST MOTOR FALLBACK (delegated to controller) ──────────────
			print("[Entity AI] APPROACH_WINDOW: Phase 2 GHOST MOTOR! Nav finished at dist=%.2f. Delegating to controller's ghost motor." % dist_to_wp2)
			
			# ─── RESET PHASE 2 FAILSAFE TIMER ────────────────────────────────
			# The NavMesh pathfinding phase may have consumed most of the 5-second
			# failsafe budget. Reset the timer here so the ghost motor gets a full
			# 5 seconds to lerp the Entity through the doorway. Without this reset,
			# the combined NavMesh + ghost motor time can exceed the 5-second limit,
			# causing the failsafe to fire prematurely and skip the IndoorBreachWaypoint.
			entity._door_phase_2_timer = 0.0
			
			# Set up the controller's ghost motor
			entity._ghost_target = waypoint_pos
			entity._ghost_door_phase_2 = true
			entity._ghost_mode = true
			
			# Disable collision so the Entity phases through the doorway
			entity.set_collision_mask_value(1, false)
			if entity.has_method("get_collision_shape"):
				entity.get_collision_shape().disabled = true
			entity.is_physics_suspended = true
			entity.velocity = Vector3.ZERO
			_calculated_velocity = Vector3.ZERO
			return
		
		# ─── ARRIVAL CHECK: 2D distance threshold (generous 2.5m) ──────────
		# The Entity must be within 2.5m of the window target to signal
		# completion. We do NOT gate on _approach_min_timer here because the
		# timer was previously causing a 15-second delay: the Entity reached
		# dist_2d=1.45m (within range) but the timer gate prevented the arrival
		# check from firing until the 15-second failsafe triggered. The minimum
		# approach duration is now checked ONLY in the failsafe logic above,
		# not in the primary arrival check. The 2.5m threshold alone is
		# sufficient to prevent false arrivals from across the map.
		#
		# NOTE: We use BOTH the 2D distance check AND is_navigation_finished()
		# as arrival signals. The NavMesh may not reach the exact window
		# coordinate (e.g., the cabin wall blocks further pathfinding). In that
		# case, the Entity gets as close as the NavMesh allows and then
		# is_navigation_finished() fires. The old code relied SOLELY on the
		# 2.5m distance check — if the NavMesh stopped at 3-4m (blocked by the
		# cabin wall collision box), the Entity physically could not get closer
		# and was stuck until the 15-second failsafe. Now, if the NavMesh
		# reports finished AND the Entity is within a generous 5m of the window
		# marker, we treat it as arrived (walk-up-and-peek position).
		#
		# ERROR PREVENTION: is_navigation_finished() ALONE is NOT sufficient —
		# if the NavMesh is completely blocked early (e.g., at 10m), it would
		# fire falsely. The 5m gate ensures the Entity is actually close enough
		# to transition into WINDOW_PEEK.
		if dist_2d <= approach_arrival_distance or (nav_finished and dist_2d <= 5.0):
			# ─── DETECT IF TARGET IS A DOOR ─────────────────────────────────
			# Use the cached @export door_waypoint_marker reference to check if
			# the current window target IS the door waypoint. If the cached
			# reference matches the current target, it's a door.
			# This replaces the expensive per-frame duck-typing checks
			# (has_method("is_in_group"), "is_open" in window_target, etc.)
			# that were called every frame during APPROACH_WINDOW.
			var is_door_target: bool = false
			var cached_door_wp = entity.get_door_waypoint_marker()
			if cached_door_wp and window_target == cached_door_wp:
				is_door_target = true
				print("[DOOR DEBUG] Target IS the cached DoorWaypointMarker. Detected as door.")
			elif cached_door_wp and window_target.get_parent() == cached_door_wp.get_parent():
				# The window_target might be the Door node itself, while the
				# cached marker is a child. Check if they share the same parent.
				is_door_target = true
				print("[DOOR DEBUG] Target shares parent with cached DoorWaypointMarker. Detected as door.")
			
			
			if is_door_target:
				# ─── SET DOOR TARGET FLAG ───────────────────────────────────
				entity.is_door_target = true
				
				# ─── DOOR ARRIVAL (Multi-Phase) ─────────────────────────────
				# Phase 0: Not started (standard approach pathfinding)
				# Phase 1: Arrived at door — handle door state
				# Phase 2: Walk through doorway to interior waypoint (handled above)
				#
				print("[Entity AI] APPROACH_WINDOW: Arrived at DOOR! dist_2d=%.2f, min_timer=%.2f. Door phase=%d." % [dist_2d, _approach_min_timer, entity._door_phase])
				
				# Get the actual Door node using the cached @export reference
				var door_node = entity.get_door_node()
				if not door_node:
					door_node = window_target
				
				# ─── PHASE 1: Handle door state ─────────────────────────────
				if entity._door_phase == 0:
					# Initialize Phase 1 — arrived at door
					entity._door_phase = 1
					entity._door_phase_timer = 2.0  # 2-second pause
					
					# ─── RESET FAILSAFE TIMER ON DOOR ARRIVAL ───────────────────
					# The Entity has physically arrived at the door. Reset the
					# 15-second failsafe timer so it doesn't fire while the Entity
					# is waiting for the 2-second pause or opening the door.
					# The failsafe should only measure time spent PATHFINDING to
					# the door, not time spent interacting with it.
					_approach_failsafe_timer = 0.0
					
					# Check if door is locked
					if door_node and "is_locked" in door_node and door_node.is_locked:
						print("[Entity AI] APPROACH_WINDOW: Door is LOCKED! Playing rattle sound.")
						if door_node.has_method("interact"):
							door_node.interact()
						entity.is_door_locked = true
						entity._door_approach_cooldown = 30.0
					
					# Check if door is already open — skip the pause
					if door_node and "is_open" in door_node and door_node.is_open:
						entity._door_phase_timer = 0.0
						print("[Entity AI] APPROACH_WINDOW: Door already open. Skipping pause.")
					
					_calculated_velocity = Vector3.ZERO
					return
				
				if entity._door_phase == 1:
					# Count down the pause timer
					entity._door_phase_timer -= delta
					_calculated_velocity = Vector3.ZERO
					
					if entity._door_phase_timer > 0.0:
						return  # Still waiting
					
					# ─── LOCKED DOOR: Return to OBSERVE ──────────────────────
					if entity.is_door_locked:
						print("[Entity AI] APPROACH_WINDOW: Door locked pause complete. Returning to OBSERVE.")
						entity.is_approach_finished = true
						entity.state_locked = false
						entity._door_phase = 0
						_approach_min_timer = 0.0
						_approach_failsafe_timer = 0.0
						_calculated_velocity = Vector3.ZERO
						return
					
					# ─── CLOSED DOOR: Open it ───────────────────────────────
					if door_node and door_node.has_method("interact") and "is_open" in door_node and not door_node.is_open:
						door_node.interact()
						print("[Entity AI] APPROACH_WINDOW: Door was closed. Opened it after 2s pause.")
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
					
					# ─── RESET FAILSAFE TIMER ───────────────────────────────
					_approach_failsafe_timer = 0.0
					
					# Advance to Phase 2 — walk through doorway
					entity._door_phase = 2
					entity._door_phase_2_timer = 0.0  # Reset failsafe timer so Phase 2 gets a full 5s budget
					
					# ─── PHASE 2 INIT: Set NavigationAgent target ──────────────
					var door_breach_wp: Node3D = entity.get_door_breach_waypoint()
					
					if not door_breach_wp:
						print("[Entity AI] APPROACH_WINDOW: No DoorBreachWaypoint found on Door node. Falling back to immediate completion.")
						entity.was_door_entry = true
						entity.is_approach_finished = true
						entity.state_locked = false
						entity._door_phase = 0
						entity._door_phase_2_timer = 0.0
						_approach_min_timer = 0.0
						_approach_failsafe_timer = 0.0
						_calculated_velocity = Vector3.ZERO
						return
		else:
			# ─── WINDOW ARRIVAL: Signal completion IMMEDIATELY ─────────────
			# CRITICAL FIX: The arrival block previously had NO completion
			# path for WINDOW targets — only the door branch existed. When
			# the Entity reached the window (dist <= 2.5m, or nav finished
			# within 5m), it fell through to the end of the function with
			# is_approach_finished = false. It stood still in APPROACH_WINDOW
			# (velocity zeroed by the nav-finished branch) until the 15-second
			# failsafe finally fired — the visible 3-5 second "time lapse".
			# Now window arrival immediately signals completion so the
			# Director transitions to WINDOW_PEEK on the next evaluation.
			entity.is_approach_finished = true
			entity.state_locked = false
			_approach_min_timer = 0.0
			_approach_failsafe_timer = 0.0
			_calculated_velocity = Vector3.ZERO
			print("[Entity AI] APPROACH_WINDOW: Window arrival (dist_2d=%.2f). Signaling completion → WINDOW_PEEK." % dist_2d)
			return



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
	
	# ─── SIEGE MAX DURATION FAILSAFE ───────────────────────────────────────
	# If the Entity has been stuck in WINDOW_PEEK for longer than the max
	# duration (default 30.0s), abandon the siege and return to treeline
	# observation. This is a hard safety net to prevent the Entity from
	# getting permanently stuck in WINDOW_PEEK when it cannot reach the
	# target window (e.g., stuck behind geometry or at the NavMesh edge).
	if _siege_duration_timer > siege_max_duration:
		print("[WINDOW_PEEK] SIEGE MAX DURATION (%.1fs) EXCEEDED! Abandoning siege." % siege_max_duration)
		entity.is_observe_finished = true
		entity.state_locked = false
		_calculated_velocity = Vector3.ZERO
		_siege_duration_timer = 0.0
		_glass_shatter_pending = false
		_glass_shatter_impact_timer = 0.0
		_barricade_anim_lock = 0.0
		_window_peek_debug_counter = 0
		_peek_assessment_done = false
		return
	
	# ─── RESET PEEK ASSESSMENT ON FRESH ENTRY ───────────────────────────
	# When the Entity first enters WINDOW_PEEK (siege timer is 0.0), reset
	# the _peek_assessment_done flag so the peek assessment runs again.
	# Without this reset, if the Entity aborted a previous peek (e.g., room
	# was lit) and later re-enters WINDOW_PEEK at a different window, the
	# stale _peek_assessment_done = true would prevent re-evaluation.
	#
	# ─── SNAP ROTATION ON FRESH ENTRY (Facing-the-cabin fix) ─────────────
	# Previously the model rotated toward the window via lerp_angle at a
	# rate of only 0.1 per frame — an extremely slow turn that could take
	# seconds to face the cabin interior. On fresh entry, snap the model
	# to the correct facing angle instantly so the Entity is looking inside
	# the cabin the moment WINDOW_PEEK begins. The existing lerp below then
	# maintains the facing direction smoothly.
	if _siege_duration_timer <= 0.0:
		_peek_assessment_done = false
		var snap_target = entity.get_current_window_target()
		if snap_target:
			var snap_peek_target: Node3D = snap_target
			if snap_target.has_node("WindowMarker"):
				snap_peek_target = snap_target.get_node("WindowMarker") as Node3D
			var snap_dir = (snap_peek_target.global_position - entity.global_position).normalized()
			var snap_angle = atan2(snap_dir.x, snap_dir.z)
			var snap_model = entity.get_monster_model()
			if snap_model:
				snap_model.rotation.y = snap_angle
				print("[WINDOW_PEEK] Fresh entry: Snapped model rotation to face window (angle=%.2f)." % snap_angle)
	
	_siege_duration_timer += delta
	
	# ─── NIGHT 2 BARRICADE GUARD ────────────────────────────────────────
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
	# PERFORMANCE: Use cached @onready reference instead of per-frame get_node_or_null
	if night_manager and "current_night" in night_manager:
		current_night = night_manager.current_night
	
	var window_target = entity.get_current_window_target()
	
	# ─── NULL WINDOW TARGET GUARD ───────────────────────────────────────
	# If the window target was cleared (e.g., by FLINCH completion), the
	# Entity has no window to peek at. Signal completion to the Director
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
		var peek_target = window_target
		if window_target.has_node("WindowMarker"):
			peek_target = window_target.get_node("WindowMarker") as Node3D
		var window_pos = peek_target.global_position
		var nav_target = entity.get_nav_agent().target_position
		var nav_finished = entity.get_nav_agent().is_navigation_finished()
		print("[APPROACH DEBUG] Entity=(%.2f, %.2f, %.2f) | Window '%s'=(%.2f, %.2f, %.2f) | NavTarget=(%.2f, %.2f, %.2f) | NavFinished=%s | dist_2d=%.2f" % [
			entity_pos.x, entity_pos.y, entity_pos.z,
			window_id_str, window_pos.x, window_pos.y, window_pos.z,
			nav_target.x, nav_target.y, nav_target.z,
			nav_finished,
			Vector2(entity_pos.x, entity_pos.z).distance_to(Vector2(window_pos.x, window_pos.z))
		])
	
	# ─── BREACH TIMER: breach_delay seconds before attempting breach ────
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
	
	# ─── PEEK ASSESSMENT ─────────────────────────────────────────────
	# The Entity commits to a fixed-duration peek at the window. It will
	# stand here for breach_delay seconds (5.0s by default) and then breach,
	# regardless of whether the player is looking. This creates reliable
	# tension — the player sees the Entity at the window and knows they have
	# 5 seconds before it attacks.
	#
	# The previous "abort if player is visible" logic caused a rapid
	# OBSERVE → WINDOW_PEEK → OBSERVE oscillation loop,
	# because the Entity would abort the peek, re-escalate, and abort again.
	# Removing the abort fixes the loop.
	#
	# NOTE: _peek_assessment_done is kept for compatibility but no longer
	# branches on visibility. It just marks that the assessment has run.
	if not _peek_assessment_done:
		_peek_assessment_done = true
	
	# Check if the window is unbarricaded (glass-only) — if so, the Entity
	# must play the AttackWindow animation and shatter the glass at the
	# impact frame BEFORE transitioning to INDOOR_SEARCH.
	# CabinWindow uses `is_boarded` (variable) to track barricade state.
	# If is_boarded is false, the window is glass-only and can be breached.
	var is_window_boarded: bool = "is_boarded" in window_target and window_target.is_boarded
	if not is_window_boarded:
		# ─── UNBARRICADED WINDOW (glass-only) ──────────────────────────
		if _siege_duration_timer >= breach_delay:
			if not _glass_shatter_pending:
				# ─── START THE ATTACK ANIMATION ─────────────────────────────
				# The breach delay has expired. Instead of instantly
				# transitioning to INDOOR_SEARCH, we initiate the AttackWindow
				# animation and set a timer for the impact frame.
				# The glass shatter will be applied when the timer fires.
				_glass_shatter_pending = true
				_glass_shatter_impact_timer = glass_shatter_impact_delay
				_barricade_anim_lock = barricade_anim_lock_duration  # Force AttackWindow animation

				# ─── STOP TALKING VOICE ─────────────────────────────────
				# The Entity starts attacking — stop the looping talking
				# voice to avoid the incongruous sound of an Entity calmly
				# muttering while violently smashing glass.
				var voice_player = entity.get_voice_player()
				if voice_player and voice_player.playing:
					voice_player.stop()
					voice_player.stream = null

				print("[WINDOW_PEEK DEBUG] *** GLASS SHATTER INITIATED! Playing AttackWindow animation. Impact in %.1fs." % glass_shatter_impact_delay)
			
			# ─── COUNTDOWN TO IMPACT ───────────────────────────────────────
			# Decrement the impact timer each frame. When it reaches 0.0,
			# the glass shatters and we signal completion to the Director.
			if _glass_shatter_pending:
				_glass_shatter_impact_timer -= delta
				_barricade_anim_lock -= delta  # Keep anim lock in sync
				if _barricade_anim_lock < 0.0:
					_barricade_anim_lock = 0.0
				
				if _glass_shatter_impact_timer <= 0.0:
					# ─── IMPACT FRAME: Breach the target ────────────────────
					_glass_shatter_pending = false
					_glass_shatter_impact_timer = 0.0
					
					# ─── BREACH DEBUG: Resolve the actual window target ──
					var resolved_window = _resolve_window_target(window_target)
					print("[BREACH DEBUG] window_target=", window_target.name,
						  " (class=", window_target.get_class(), ")",
						  " | resolved=", resolved_window.name if resolved_window else "NULL",
						  " | is_CabinWindow=", resolved_window is CabinWindow,
						  " | has_shatter=", resolved_window.has_method("shatter_window") if resolved_window else false)
					
					# ─── SAFE TYPE-CHECK: Door vs Window Breach ─────────────
					# The Entity can approach both windows (CabinWindow) and
					# doors (AnimatableBody3D with Door script). Each has a
					# different breach method:
					#   - Window: shatter_window() — destroys glass panes
					#   - Door:   break_door() — forces the door open
					# Use the resolved window target (walk-up parent chain to find
					# the CabinWindow ancestor) to safely dispatch the breach.
					if resolved_window and resolved_window.has_method("shatter_window"):
						resolved_window.shatter_window()
						# ─── BACKUP: Force PristineVisuals/ShatteredVisuals visibility ──
						# The CabinWindow's _shatter_glass() calls _update_window_visuals()
						# which sets PristineVisuals.visible=false and ShatteredVisuals.visible=true.
						# However, if the node references are stale (null due to scene reload or
						# if hasn_node returned false at _ready time), the swap silently fails.
						# This belt-and-suspenders approach guarantees the visuals swap even if
						# cabin_window.gd's internal logic doesn't fire correctly.
						if resolved_window.has_node("PristineVisuals"):
							resolved_window.get_node("PristineVisuals").visible = false
						if resolved_window.has_node("ShatteredVisuals"):
							resolved_window.get_node("ShatteredVisuals").visible = true
						print("[WINDOW_PEEK] Glass shattered via resolved window! Transitioning to INDOOR_SEARCH.")
					elif window_target.has_method("break_door"):
						# ─── PROXIMITY GUARD: Door Breach ──────────────────────
						# Before forcing the door open, check if the Entity is
						# physically close enough to the door. If the Entity is
						# too far away (e.g., the APPROACH_WINDOW failsafe fired
						# and the Director transitioned to WINDOW_PEEK while the
						# Entity was still 20m away in the forest), block the
						# breach and fall back to OBSERVE_FROM_TREELINE.
						#
						# This prevents the "ghost breach" bug where the Entity
						# teleports inside the cabin from across the map.
						if _is_close_enough_to_door(window_target):
							window_target.break_door()
							print("[WINDOW_PEEK] Door forced open at impact frame! Transitioning to INDOOR_SEARCH.")
						else:
							# ─── PROXIMITY GUARD TRIGGERED ─────────────────────
							# The Entity is too far from the door to physically
							# breach it. Block the breach and fall back to
							# OBSERVE_FROM_TREELINE so the Entity continues
							# stalking from the treeline.
							print("[WINDOW_PEEK] PROXIMITY GUARD: Door breach blocked! Entity too far from door. Falling back to OBSERVE.")
							
							# CRITICAL: Reset was_door_entry to false so the
							# Director doesn't force INDOOR_SEARCH with stale
							# door entry state on the next cycle.
							entity.was_door_entry = false
							entity.is_door_target = false
							
							# Fall back to OBSERVE_FROM_TREELINE
							entity.is_observe_finished = true
							entity.state_locked = false
							_calculated_velocity = Vector3.ZERO
							_siege_duration_timer = 0.0
							_glass_shatter_pending = false
							_glass_shatter_impact_timer = 0.0
							_barricade_anim_lock = 0.0
							_window_peek_debug_counter = 0
							_peek_assessment_done = false
							return
					else:
						print("[WINDOW_PEEK] WARNING: Target has no breach method! window_target=%s (class=%s)" % [window_target.name, window_target.get_class()])
					
					# ─── MARK WINDOW AS BREACHED ────────────────────────────
					# Register this window on the breach cooldown system so
					# the Entity will NOT select it for approach/breach again
					# for the next 30 seconds.
					if window_target.has_method("register_breach"):
						window_target.register_breach()
					
				# ─── SET BREACH WINDOW ──────────────────────────────────
				# Store the breached window so INDOOR_SEARCH knows which
				# window to retreat through when repelled by light.
				entity.last_breached_window = window_target

				# ─── GUARANTEED VISUAL DESTRUCTION (BUG FIX) ─────────────
				# The shatter_window() call above is nested inside the
				# `if resolved_window and resolved_window.has_method(...)`
				# branch. If window resolution fails (resolved_window is null)
				# the breach STILL completes below (last_breached_window set,
				# INDOOR_SEARCH entered) but the glass is never visually
				# broken — GlassPane/WoodenCross stay intact. This unconditional
				# block re-runs the visual swap at the exact breach moment so
				# the pristine visuals are always destroyed and ShatteredVisuals
				# always shown, regardless of which sub-branch executed.
				# Guarded by is_glass_shattered so it is idempotent (no double
				# shatter if the branch above already fired).
				var breach_win = _resolve_window_target(window_target)
				if breach_win and breach_win.has_method("shatter_window") and not breach_win.is_glass_shattered:
					breach_win.shatter_window()
					print("[WINDOW_PEEK] GUARANTEED shatter fired on '%s' (id=%s)." % [breach_win.name, breach_win.window_id if "window_id" in breach_win else "?"])
				
				# ─── CAPTURE INDOOR LANDING POSITION ──────────────────
				# Store the window's IndoorBreachWaypoint position so
				# INDOOR_SEARCH Phase A can teleport the Entity inside
				# after the vault animation plays. Without this, the
				# Entity stays outside trying to pathfind through walls.
				if window_target.has_method("get_indoor_landing_position"):
					var landing = window_target.get_indoor_landing_position()
					entity.set_indoor_landing_position(landing)
					print("[WINDOW_PEEK] Breach: Landing position set to (%.2f, %.2f, %.2f)" % [landing.x, landing.y, landing.z])
				else:
					print("[WINDOW_PEEK] WARNING: Window target has no get_indoor_landing_position()! Teleport will fail.")
				
				# ─── FALLBACK: If landing position is zero (no IndoorBreachWaypoint),
				# set a default landing point 1.5m inside from the window's position.
				if entity.get_indoor_landing_position() == Vector3.ZERO:
					var fallback_landing = window_target.global_position
					fallback_landing.y = 0.0
					entity.set_indoor_landing_position(fallback_landing)
					print("[WINDOW_PEEK] Breach: No IndoorBreachWaypoint. Using fallback landing position: (%.2f, %.2f, %.2f)" % [fallback_landing.x, fallback_landing.y, fallback_landing.z])
				
				# ─── NAVMESH LANDING VALIDATION (BUG 1 FIX) ───────────────
				# The landing position from get_indoor_landing_position() may
				# clip just outside the NavMesh boundary (e.g. inside a wall
				# collider). When INDOOR_SEARCH teleports the Entity there,
				# the NavigationAgent cannot find a direct path to patrol
				# waypoints and routes OUT through the only valid NavMesh
				# exit — the front door — producing the "doorway detour" bug.
				#
				# Fix: project the landing XZ onto the NavMesh floor and
				# verify the snapped point is inside a VALID_INDOOR_ROOM. If
				# it is NOT, fall back to the IndoorBreachWaypoint (the
				# known-safe door entry point) for the landing position.
				var landing_check = entity.get_indoor_landing_position()
				if landing_check != Vector3.ZERO:
					var nav_map_v = entity.get_world_3d().navigation_map
					var snapped_v = NavigationServer3D.map_get_closest_point(nav_map_v, landing_check)
					var check_pos_v = landing_check
					check_pos_v.y = snapped_v.y
					if not _is_position_inside_cabin(check_pos_v):
						var fallback_wp = entity.get_door_breach_waypoint()
						if fallback_wp:
							var wp_landing = fallback_wp.global_position
							entity.set_indoor_landing_position(wp_landing)
							print("[WINDOW_PEEK] Breach: Landing (%.2f, %.2f, %.2f) is OUTSIDE valid cabin rooms! Falling back to IndoorBreachWaypoint (%.2f, %.2f, %.2f)." % [landing_check.x, landing_check.y, landing_check.z, wp_landing.x, wp_landing.y, wp_landing.z])
				
				# ─── SIGNAL COMPLETION ──────────────────────────────────
				# The glass has shattered. Signal the Director to transition
				# to INDOOR_SEARCH.
				entity.is_window_unbarricaded = true
				entity.state_locked = false
				_calculated_velocity = Vector3.ZERO
				_siege_duration_timer = 0.0
				_glass_shatter_pending = false
				_glass_shatter_impact_timer = 0.0
				_barricade_anim_lock = 0.0
				_window_peek_debug_counter = 0
				_peek_assessment_done = false
				return
	else:
		# ─── BARRICADED WINDOW: Damage the barricade ─────────────────────
		# The window is boarded up. The Entity must damage the barricade
		# before it can breach. The barricade damage timer accumulates each
		# frame while the Entity is within range of the window.
		if _siege_duration_timer >= breach_delay:
			# Accumulate barricade damage timer
			_barricade_damage_timer += delta
			
			# ─── BARRICADE HIT ─────────────────────────────────────────
			# Every 2 seconds, the Entity strikes the barricade.
			# This plays the AttackWindow animation and applies damage.
			if _barricade_damage_timer >= barricade_damage_interval:
				_barricade_damage_timer = 0.0
				
				# Apply damage to the barricade
				# BUG FIX (Missing Visual Window Destruction): Resolve the actual
				# CabinWindow ancestor before calling damage_barricade(). The raw
				# window_target may be a child node (e.g. a marker or sub-node), in
				# which case has_method("damage_barricade") is false and the glass
				# is never shattered. damage_barricade() internally calls
				# _shatter_glass() on the first hit when glass is intact, which
				# performs the PristineVisuals -> ShatteredVisuals swap.
				var resolved_win = _resolve_window_target(window_target)
				if resolved_win and resolved_win.has_method("damage_barricade"):
					resolved_win.damage_barricade()
					print("[WINDOW_PEEK] Barricade hit! Damaging barricade (resolved window).")
					# Belt-and-suspenders: if the glass is now shattered, force the
					# visual swap in case cabin_window.gd's internal logic missed it.
					if resolved_win.is_glass_shattered:
						if resolved_win.has_node("PristineVisuals"):
							resolved_win.get_node("PristineVisuals").visible = false
						if resolved_win.has_node("ShatteredVisuals"):
							resolved_win.get_node("ShatteredVisuals").visible = true
				elif window_target.has_method("damage_barricade"):
					window_target.damage_barricade()
					print("[WINDOW_PEEK] Barricade hit! Damaging barricade.")
				
				# Force the AttackWindow animation
				_barricade_anim_lock = barricade_anim_lock_duration
				
				# Set pending damage delay for impact frame sync
				_has_pending_damage = true
				_pending_damage_delay = pending_damage_delay
			
			# ─── PENDING DAMAGE DELAY ──────────────────────────────────
			# Count down the pending damage delay. When it reaches 0.0,
			# the damage is applied to the barricade (synced with the
			# AttackWindow animation impact frame).
			if _has_pending_damage:
				_pending_damage_delay -= delta
				if _pending_damage_delay <= 0.0:
					_has_pending_damage = false
					_pending_damage_delay = 0.0
					# Damage already applied above — this is just the
					# animation sync marker.
			
			# ─── BARRICADE ANIMATION LOCK ──────────────────────────────
			# Decrement the animation lock timer. While > 0.0, the
			# AttackWindow animation is forced to play.
			if _barricade_anim_lock > 0.0:
				_barricade_anim_lock -= delta
				if _barricade_anim_lock < 0.0:
					_barricade_anim_lock = 0.0
		
		# ─── SIEGE TIMER DECAY ──────────────────────────────────────────
		# The siege timer accumulates while the Entity is at the window.
		# It is NOT reset here — it persists across frames so the Entity
		# can accumulate time toward the breach delay.
		# The timer is reset to 0.0 when the Entity transitions out of
		# WINDOW_PEEK (handled in the completion block above).
		


	# ─── FACE THE WINDOW (ALL WINDOW TYPES) ───────────────────────────────
	# Rotate the monster model to face the window while peeking.
	# Use the WindowMarker (outside the window) as the look target, not
	# the CabinWindow node which is inside the wall. This runs for BOTH
	# barricaded and unbarricaded (glass-only) windows — previously only
	# the barricaded damage path rotated the model toward the glass, so the
	# Entity looked away during the unbarricaded siege/glass-shatter sequence.
	var peek_target = window_target
	if window_target.has_node("WindowMarker"):
		peek_target = window_target.get_node("WindowMarker") as Node3D
	var window_pos = peek_target.global_position
	var dir_to_window = (window_pos - entity.global_position).normalized()
	var target_angle = atan2(dir_to_window.x, dir_to_window.z)
	var model = entity.get_monster_model()
	if model:
		model.rotation.y = lerp_angle(model.rotation.y, target_angle, 0.1)
	
	_calculated_velocity = Vector3.ZERO


# ---------------------------------------------------------------------------
# STATE: FLINCH — Lateral sprint to evade flashlight beam
# ---------------------------------------------------------------------------
## The Entity sprints away from the cabin toward a NavMesh-projected forest
## point over a randomized 6-8 second escape sprint. After the sprint
## completes, it signals completion to the Director.
##
## The flinch target position is calculated as a point 15 meters away from
## the cabin center, blended with the window's outward normal, then projected
## onto the NavMesh (avoiding the "face plant into a tree" edge trap).

# ─── TASK 1.1: SHARED FLINCH EXIT CLEANUP ────────────────────────────────
## Called by EVERY FLINCH exit path (early abort + timer expiry). Clears the
## stale illumination/overcharge booleans that otherwise remain true after
## FLINCH completes, resets the NavigationAgent's target to prevent the
## Entity from pathfinding to the previous window marker, and arms the
## 3-frame post-flinch re-entry cooldown. Without this cleanup, the Entity
## re-enters APPROACH_WINDOW with stale is_illuminated=true and instantly
## re-triggers FLINCH — the 1-frame oscillation that degraded the AI and
## made the Entity appear stuck/ignoring the flashlight on Night 3+.
func _cleanup_after_flinch() -> void:
	# ─── ISSUE 3 FIX: DO NOT CLEAR BLACKBOARD BOOLEANS ───────────────
	# Previously this cleared entity.is_illuminated / is_overcharged /
	# thinks_player_is_inside. Those booleans are OWNED by the perception
	# system (perception_manager.gd / entity_controller.gd on_player_stare)
	# which updates them every frame. Clearing them here created a stale-read
	# gap: the FLINCH OVERRIDE GATE would read is_overcharged=false for a few
	# frames even while the player still held the overcharge beam, letting the
	# Entity "ignore" the flashlight and continue APPROACH_WINDOW. The
	# extended 0.5s FLINCH_EXIT_COOLDOWN below is the correct mechanism —
	# it simply delays re-entry long enough for perception to catch up,
	# without trampling the perception system's authoritative state.
	
	# ─── RESET NAVIGATION STATE ────────────────────────────────────────
	# The NavigationAgent still holds the flinch escape target. If we
	# don't reset it, the next APPROACH_WINDOW entry could pathfind to
	# the old forest escape point instead of the new window marker.
	var nav_agent_cleanup = entity.get_nav_agent()
	if nav_agent_cleanup:
		nav_agent_cleanup.target_position = entity.global_position
		nav_agent_cleanup.target_desired_distance = 1.5
	
	# ─── CLEAR WINDOW TARGET ──────────────────────────────────────────
	# The flinch escape used the current window's outward normal. Clear
	# the target so the next APPROACH_WINDOW cycle re-selects via
	# pick_tactical_window() (which now respects _banned_room).
	entity.set_current_window_target(null)
	
	# ─── ARM POST-FLINCH RE-ENTRY COOLDOWN ─────────────────────────────
	# Give the perception system a few frames to recompute the true
	# illumination state before allowing APPROACH_WINDOW re-entry.
	_flinch_exit_cooldown = FLINCH_EXIT_COOLDOWN_DURATION
	
	# ─── RESET FLINCH SYSTEM STATE ─────────────────────────────────────
	_flinch_total_duration = 0.0
	entity.set_flinched_timer(0.0)
	entity.set_flinch_target_pos(entity.global_position)
	
	print("[FLINCH] Cleanup complete. Stale booleans cleared, nav target reset, cooldown armed (%.3fs)." % _flinch_exit_cooldown)


func _flinch_state(delta: float) -> void:
	# Lock the state — the Director must not override while we're mid-flinch
	entity.state_locked = true
	
	# ─── INITIALIZE FLINCH ON FIRST FRAME ──────────────────────────────
	# If the flinch timer is 0.0 (or less), this is the first frame of the
	# flinch. Calculate the escape target (away from cabin) and set the timer
	# to a randomized 6-8 second duration.
	#
	# ESCAPE FROM CABIN (NEW):
	#   Instead of the old lateral sprint perpendicular to the player's camera,
	#   the Entity now flees from the cabin center toward a NavMesh-projected
	#   point in the forest. This makes FLINCH feel like a real retreat rather
	#   than a combat sidestep.
	if entity.get_flinched_timer() <= 0.0:
		# Randomized 6-8 second escape sprint duration
		_flinch_total_duration = randf_range(6.0, 8.0)
		entity.set_flinched_timer(_flinch_total_duration)
		print("[FLINCH] Duration set to %.1fs." % _flinch_total_duration)
		
		# ─── CALCULATE ESCAPE VECTOR: Away from cabin center + window outward ──
		# Bug Fix: Combining cabin-center direction with the window's outward-facing
		# normal (-Z basis) prevents the Entity from hugging the cabin wall.
		# When the Entity is pressed against the cabin (from APPROACH_WINDOW/
		# WINDOW_PEEK), the cabin-center vector points *along* the wall rather
		# than outward. Adding the window's outward normal ensures a clean
		# perpendicular escape into the forest.
		var cabin_center = entity.cabin_center if "cabin_center" in entity else Vector3(0.0, 0.0, 14.88)
		var away_from_cabin = (entity.global_position - cabin_center)
		away_from_cabin.y = 0.0
		var away_len = away_from_cabin.length()
		if away_len > 0.01:
			away_from_cabin = away_from_cabin / away_len
		else:
			away_from_cabin = Vector3(0.0, 0.0, -1.0)
		
		# Blend with window outward direction if available
		var window_target_escape = entity.get_current_window_target()
		var window_outward = Vector3.ZERO
		if window_target_escape:
			# The window's -Z basis points outward from the glass
			window_outward = -window_target_escape.global_transform.basis.z
			window_outward.y = 0.0
			var w_len = window_outward.length()
			if w_len > 0.01:
				window_outward = window_outward / w_len
		
		# Blend: 60% cabin-away + 40% window-outward. This ensures the Entity
		# flees both away from the cabin structure AND away from the specific
		# window it was at, preventing wall-hugging.
		var escape_dir_raw = away_from_cabin * 0.6
		if window_outward.length_squared() > 0.01:
			escape_dir_raw += window_outward * 0.4
		escape_dir_raw.y = 0.0
		var escape_len = escape_dir_raw.length()
		var escape_dir = escape_dir_raw / escape_len if escape_len > 0.01 else Vector3(0.0, 0.0, -1.0)
		
		# Add a random perturbation (±30 degrees) to avoid predictable
		# straight-line escape paths. The Entity should not run the exact
		# same direction every time.
		var random_angle = deg_to_rad(randf_range(-30.0, 30.0))
		escape_dir = escape_dir.rotated(Vector3.UP, random_angle)
		
		# ─── NAVMESH-PROJECTED ESCAPE TARGET ────────────────────────────
		# Project the escape vector endpoint onto the NavMesh so the Entity
		# sprints to a reachable position in the forest. This prevents the
		# "face plant into a tree" problem where a straight-line escape would
		# intersect with impassable foliage (Correction 1: NavMesh Edge Trap).
		var escape_distance: float = 15.0  # 15m escape into the forest
		var raw_target = entity.global_position + escape_dir * escape_distance
		
		# Use NavigationServer3D to snap the target to the nearest valid
		# point on the NavMesh surface
		var nav_map = entity.get_world_3d().navigation_map
		var snapped_target = NavigationServer3D.map_get_closest_point(nav_map, raw_target)
		# Preserve the source XZ but use the NavMesh-snapped Y
		snapped_target.x = raw_target.x
		snapped_target.z = raw_target.z
		
		entity.set_flinch_target_pos(snapped_target)
		
		# Set the NavigationAgent's target so the Entity actually nav-pathfinds
		# toward the escape point, rather than blindly sprinting in world-space.
		var nav_agent = entity.get_nav_agent()
		if nav_agent:
			nav_agent.target_position = snapped_target
			nav_agent.target_desired_distance = 0.5
		
		print("[FLINCH] ESCAPE INITIALIZED! Duration=%.1fs, EscapeDir=(%.2f, %.2f), NavTarget=(%.2f, %.2f, %.2f)" % [entity.get_flinched_timer(), escape_dir.x, escape_dir.z, snapped_target.x, snapped_target.y, snapped_target.z])
	
	# ─── EARLY ABORT GUARD (Correction 1: NavMesh Edge Trap + Min Duration) ─
	# If the Entity has reached the escape target (navigation finished OR
	# distance < 0.5m) BEFORE the flinch timer expires, abort early. The Entity
	# would otherwise stand still facing a tree for the remaining seconds.
	#
	# MINIMUM DURATION (Bug 3 Fix): The Entity must sprint for at least 1.5
	# seconds before the early abort can trigger. Without this, map_get_closest_point
	# at the NavMesh edge returns a point very close to the Entity, causing
	# immediate "arrival" on frame 2 → Entity sits still for the full flinch.
	var nav_agent = entity.get_nav_agent()
	var reached_target: bool = false
	var elapsed_time: float = _flinch_total_duration - entity.get_flinched_timer()
	if nav_agent and elapsed_time >= 1.5:
		var dist_to_target = entity.global_position.distance_to(entity.get_flinch_target_pos())
		if nav_agent.is_navigation_finished() or dist_to_target < 0.5:
			reached_target = true
	
	if reached_target and entity.get_flinched_timer() > 0.0:
		print("[FLINCH] Early abort: Reached escape target (timer still at %.2fs). Signaling completion." % entity.get_flinched_timer())
		entity.is_flinch_finished = true
		entity.state_locked = false
		_calculated_velocity = Vector3.ZERO
		# ─── TASK 1.1: SHARED EXIT CLEANUP ────────────────────────────
		# Prevents stale booleans / nav targets from poisoning the next
		# APPROACH_WINDOW entry after an early-abort flinch.
		_cleanup_after_flinch()
		return
	
	# ─── SPRINT TOWARD TARGET ──────────────────────────────────────────
	# Use speed-limited sprint toward the escape target. The flinch speed
	# multiplier (1.5x default) makes the Entity sprint significantly faster
	# than normal stalk speed, creating the feeling of desperate retreat.
	var target = entity.get_flinch_target_pos()
	var dir_to_target_flat = (target - entity.global_position)
	dir_to_target_flat.y = 0.0
	var flat_dist = dir_to_target_flat.length()
	
	if flat_dist > 0.1:
		var move_dir = dir_to_target_flat.normalized()
		var flinch_speed = entity.current_stalk_speed * flinch_sprint_multiplier
		_calculated_velocity.x = move_dir.x * flinch_speed
		_calculated_velocity.z = move_dir.z * flinch_speed
	else:
		# At the exact target — this shouldn't happen due to the early abort
		# guard above, but just in case, stop movement.
		_calculated_velocity.x = 0.0
		_calculated_velocity.z = 0.0
	
	# ─── DECREMENT TIMER ───────────────────────────────────────────────
	entity.set_flinched_timer(entity.get_flinched_timer() - delta)
	
	# ─── COMPLETION CHECK ──────────────────────────────────────────────
	if entity.get_flinched_timer() <= 0.0:
		entity.is_flinch_finished = true
		entity.state_locked = false
		_calculated_velocity = Vector3.ZERO
		print("[FLINCH] Timer expired (%.1fs). Signaling completion to Director." % _flinch_total_duration)
		_flinch_total_duration = 0.0
		
		# ─── NIGHT 2.2 VAN SEQUENCE: FLINCH → DORMANT (HARD-OVERRIDE) ──
		# When the player escapes into the cabin during the car-alarm
		# sequence, the Entity flinches and must immediately vanish into
		# DORMANT (completely invisible). The flag is armed by
		# _evaluate_night_rules() once and consumed here, so the override
		# only fires once — subsequent normal flitches behave normally.
		if _van_sequence_flinch_armed and night_manager and "is_van_sequence_active" in night_manager and night_manager.is_van_sequence_active:
			_van_sequence_flinch_armed = false
			# ─── TASK 1.1: SHARED EXIT CLEANUP ────────────────────────
			# Even for the van-sequence DORMANT transition, the stale
			# booleans must be cleared so the next night phase starts clean.
			_cleanup_after_flinch()
			entity.set_state(EntityAI.State.DORMANT)
			entity.visible = false
			var van_model = entity.get_monster_model()
			if van_model:
				van_model.visible = false
			print("[FLINCH → DORMANT] Night 2.2 van sequence complete. Entity vanished into DORMANT.")
			return
		
		# ─── TASK 1.1: SHARED EXIT CLEANUP ────────────────────────────
		# The primary stun-lock fix: clear stale booleans, reset the
		# NavigationAgent target, and arm the post-flinch cooldown so
		# the next APPROACH_WINDOW entry cannot instantly re-flinch.
		_cleanup_after_flinch()
		return


# ---------------------------------------------------------------------------
# STATE: HARASS — Psychological harassment at a window
# ---------------------------------------------------------------------------
## The Entity stands at a window and performs psychological harassment
## (breathing, tapping, rattling) to pressure the player. This state is
## used when the Entity cannot breach the window (boarded, lit room, etc.)
## but wants to keep the player on edge.
##
## The harassment continues until the player looks at the window (RLOS check)
## or a timeout expires.
func _harass_state(delta: float) -> void:
	# Lock the state
	entity.state_locked = true
	
	_calculated_velocity = Vector3.ZERO
	
	# ─── GET CURRENT WINDOW TARGET ─────────────────────────────────────
	var window_target = entity.get_current_window_target()
	if not window_target:
		entity.is_observe_finished = true
		entity.state_locked = false
		return
	
	# ─── FACE THE WINDOW ───────────────────────────────────────────────
	var window_pos = window_target.global_position
	var dir_to_window = (window_pos - entity.global_position).normalized()
	var target_angle = atan2(dir_to_window.x, dir_to_window.z)
	var model = entity.get_monster_model()
	if model:
		model.rotation.y = lerp_angle(model.rotation.y, target_angle, 0.1)
	
	# ─── CHECK IF PLAYER IS LOOKING AT THIS WINDOW ─────────────────────
	var sensory = entity.get_sensory_module()
	var player_looking = false
	if sensory and sensory.has_method("is_player_looking_at_window"):
		player_looking = sensory.is_player_looking_at_window(window_pos)
	
	if player_looking:
		# Player noticed us — stop harassing and return to treeline
		entity.is_observe_finished = true
		entity.state_locked = false
		print("[HARASS] Player is looking! Aborting harassment.")
		return
	
	# ─── HARASSMENT TIMEOUT ────────────────────────────────────────────
	# After 10 seconds of harassment without the player noticing, give up.
	if entity.get_state_timer() <= 0.0:
		entity.set_state_timer(10.0)
	
	entity.set_state_timer(entity.get_state_timer() - delta)
	if entity.get_state_timer() <= 0.0:
		entity.is_observe_finished = true
		entity.state_locked = false
		print("[HARASS] Timeout expired. Returning to treeline.")
		return


# ---------------------------------------------------------------------------
# STATE: INDOOR_SEARCH — Hunting the player inside the cabin
# ---------------------------------------------------------------------------
## The Entity has breached a window or entered through the door and is now
## hunting the player inside the cabin. This state has two phases:
##
##   Phase A (Vault/Door Entry): The Entity plays the vault animation
##     (window breach) or walks through the doorway (door entry), then
##     teleports to the indoor landing position.
##
##   Phase B (Indoor Patrol): The Entity patrols room-to-room using the
##     INDOOR_ROOM_GRAPH BFS pathfinding system. It checks each room for
##     the player using the sensory module. If the player is seen, it
##     CHARGEs. If the player is heard, it pathfinds to the room center.
##     If the player is in a lit room, the Entity avoids that room.
##
##   Phase C (Investigation): When the Entity arrives at a room center
##     and cannot find the player, it enters a scanning sub-state. The
##     Entity rotates slowly in place for 4 seconds, looking for the
##     player. If the player is spotted during the scan, the Entity
##     immediately resumes the chase. If the scan timer expires without
##     finding the player, the Entity returns to patrol.
func _indoor_search_state(delta: float) -> void:
	# ─── ENTRY PATH DEBUG ────────────────────────────────────────────
	# Log whether the Entity entered via door or window, and which window
	# (if any) was recorded as last breached. This tells us whether the
	# window breach path (which calls _shatter_glass) was actually used.
	var _lw = entity.last_breached_window
	print("[INDOOR_SEARCH ENTRY] was_door_entry=%s | last_breached_window=%s | _has_arrived_indoor=%s" % [entity.was_door_entry, _lw.name if _lw else "NULL", _has_arrived_indoor])
	
	# ─── FORCE INDOOR_SEARCH COLLISION MASK (HOT-RELOAD SAFETY) ────
	# During INDOOR_SEARCH the Entity must NOT collide with Cabin geometry
	# (Layer 1) — the baked NavMesh confines it to walkable interior spaces,
	# and the doorframe lip colliders ("lister") would otherwise snag the
	# capsule. _update_collision_layers() normally applies this on state
	# transition, but a hot-reload while ALREADY in INDOOR_SEARCH skips the
	# transition path, leaving the full mask (including Layer 1) active.
	# Force the correct mask every frame here as a safety net.
	entity.collision_mask = 0
	entity.collision_mask |= (1 << (2 - 1))  # Layer 2: Player only
	
	# ─── LIGHT SWITCH RETREAT CHECK ──────────────────────────────────
	# If the Entity is inside a lit room, immediately set the indoor
	# retreat flag. The Director's Tier 0 will detect this and transition
	# to RETREAT on the next frame.
	if RoomLightDetector.is_entity_in_lit_room():
		entity.is_indoor_retreat = true
		entity.state_locked = false
		_calculated_velocity = Vector3.ZERO
		return
	
	# ─── PHASE A: Vault/Door Entry ───────────────────────────────────
	# ARCHITECTURAL NOTE:
	#   APPROACH_WINDOW now handles the physical breach (ghost motor through
	#   the doorway) AND sets _has_arrived_indoor = true on arrival.
	#   INDOOR_SEARCH should immediately begin patrol without re-entering
	#   breach logic. The legacy velocity-based "GHOST MOTOR" is removed
	#   from this function — if the Entity reaches here with was_door_entry
	#   but _has_arrived_indoor is false, it means the ghost motor failed to
	#   set the flag. We teleport directly as a failsafe.
	if not _has_arrived_indoor:
		# ─── SECONDARY ARRIVAL GUARD (Physics Reconciliation Fix) ─────
		# Even if _has_arrived_indoor was not explicitly set, check if the
		# Entity is already within arrival distance of the IndoorBreachWaypoint.
		# This handles the case where the ghost motor lerped the position but
		# the set_has_arrived_indoor call was somehow missed (e.g., the
		# _physics_process returned before reaching the arrival block).
		# Without this guard, the Entity re-enters the Door Phase A pathfinding/
		# ghost-motor logic every frame, creating the "BREACH LOCKED" loop.
		if entity.was_door_entry:
			var guard_wp: Node3D = entity.get_door_breach_waypoint()
			if guard_wp:
				var guard_pos = guard_wp.global_position
				guard_pos.y = entity.global_position.y
				if entity.global_position.distance_to(guard_pos) <= door_phase_2_arrival_distance:
					print("[INDOOR_SEARCH] Secondary arrival guard: Entity already at IndoorBreachWaypoint (dist <= %.2f). Skipping Phase A." % door_phase_2_arrival_distance)
					entity.was_door_entry = false
					_has_arrived_indoor = true
					entity.is_breach_locked = false
					entity._breach_lock_timer = 0.0
					entity.state_locked = false
					# Sync physics state to prevent rubber-banding
					entity.velocity = Vector3.ZERO
					entity._breach_lock_timer = 0.0
					var director = _director
					if director and director.has_method("reset_indoor_search_persistence"):
						director.reset_indoor_search_persistence()
					# Fall through to Phase B

		# ─── DOOR ENTRY (Phase A navigation) ─────────────────────────
		if not _has_arrived_indoor and entity.was_door_entry:
			# ─── RESOLVE THE BREACH WAYPOINT ──────────────────────────────
			var breach_wp: Node3D = entity.get_door_breach_waypoint()
			
			if breach_wp:
				var waypoint_pos = breach_wp.global_position
				waypoint_pos.y = entity.global_position.y  # Flatten Y
				var dist_to_wp = entity.global_position.distance_to(waypoint_pos)
				
				# ─── SET NAV TARGET ───────────────────────────────────────
				_path_timer -= delta
				if _path_timer <= 0.0:
					_path_timer = PATH_UPDATE_INTERVAL
					entity.get_nav_agent().target_position = waypoint_pos
				
				# ─── ARRIVAL CHECK ───────────────────────────────────────
				if dist_to_wp <= door_phase_2_arrival_distance:
					print("[INDOOR_SEARCH] Door Phase A complete! Arrived at IndoorBreachWaypoint (dist=%.2f). Starting Phase B patrol." % dist_to_wp)
					
					# ─── RESTORE PHYSICS ─────────────────────────────────────
					entity.set_collision_mask_value(1, true)
					if entity.has_method("get_collision_shape"):
						entity.get_collision_shape().disabled = false
					entity.is_physics_suspended = false
					entity.velocity = Vector3.ZERO
					
					entity.was_door_entry = false
					_has_arrived_indoor = true
					entity.is_breach_locked = false
					entity.state_locked = false
					# Zero the controller's breach lock timer to prevent stale timeout
					entity._breach_lock_timer = 0.0
					# Reset the indoor search persistence timer
					var director = _director
					if director and director.has_method("reset_indoor_search_persistence"):
						director.reset_indoor_search_persistence()
					# Fall through to Phase B below
				else:
					# ─── MOVEMENT TOWARD WAYPOINT ─────────────────────────
					entity.state_locked = true
					entity.is_breach_locked = true
					
				if entity.get_nav_agent().is_navigation_finished():
					# ─── TELEPORT FAILSAFE (replaces legacy GHOST MOTOR) ──────
					# APPROACH_WINDOW's ghost motor handles the actual breach.
					# If we reach here, the ghost motor didn't set _has_arrived_indoor
					# but the Entity's NavMesh path has ended. Teleport directly.
					print("[INDOOR_SEARCH] Door Phase A teleport failsafe! Nav finished at dist=%.2f. Teleporting to waypoint." % dist_to_wp)
					entity.global_position = waypoint_pos
					entity.velocity = Vector3.ZERO
					# Fall through — the arrival check above will fire on next iteration
				else:
					# Follow the NavMesh path
					var next_pos = entity.get_nav_agent().get_next_path_position()
					var dir_2d := Vector2(next_pos.x - entity.global_position.x, next_pos.z - entity.global_position.z)
					if dir_2d.length() > 0.01:
						var move_dir_2d = dir_2d.normalized()
						_calculated_velocity.x = move_dir_2d.x * entity.current_stalk_speed
						_calculated_velocity.z = move_dir_2d.y * entity.current_stalk_speed
					return
			else:
				# ─── NO BREACH WAYPOINT FOUND ─────────────────────────────
				# Fallback: no waypoint found, skip Phase A and go to Phase B.
				print("[INDOOR_SEARCH] No DoorBreachWaypoint found. Skipping Phase A. Starting Phase B patrol.")
				entity.was_door_entry = false
				_has_arrived_indoor = true
				entity.is_breach_locked = false
				entity.state_locked = false
				var director = _director
				if director and director.has_method("reset_indoor_search_persistence"):
					director.reset_indoor_search_persistence()
				# Fall through to Phase B below
		
		# ─── WINDOW BREACH ENTRY ─────────────────────────────────────
		if not entity.was_door_entry and not _has_arrived_indoor:
			# Phase A: Vault animation + teleport to landing position
			# The Entity plays the EnterWindow animation for 1.5 seconds,
			# then teleports to the indoor landing position.
			if _enter_window_anim_timer <= 0.0:
				# Initialize the vault animation timer
				_enter_window_anim_timer = enter_window_anim_duration
				entity.state_locked = true
				print("[INDOOR_SEARCH] Phase A: Starting vault animation (%.1fs)." % enter_window_anim_duration)
			
			# Count down the vault animation timer
			_enter_window_anim_timer -= delta
			
			if _enter_window_anim_timer <= 0.0:
				# ─── VAULT COMPLETE: Teleport to landing position ─────────
				# The vault animation has finished playing. Teleport the Entity
				# to the indoor landing position and transition to Phase B.
				# The IndoorBreachWaypoint is placed at Z=1.5 (inside the room)
				# but inherits the CabinWindow's world Y, which may be at window
				# height (high on the wall). Snap the Y to the NavMesh floor
				# height so the Entity lands at the correct interior floor level
				# (matching the player's Y≈0.5).
				#
				# NOTE: We deliberately do NOT cast a downward physics ray from
				# the waypoint. The waypoint sits at window height, so a ray cast
				# from there (or above) hits the cabin's ceiling/attic floor before
				# reaching the ground floor, teleporting the Entity into the attic.
				# The NavMesh is baked on the ground floor (never the ceiling), so
				# snapping Y to the NavMesh is safe and lands the Entity correctly.
				var landing_pos = entity.get_indoor_landing_position()
				if landing_pos != Vector3.ZERO:
					# Snap Y to NavMesh floor at the landing XZ coordinates
					var nav_map = entity.get_world_3d().navigation_map
					var snapped = NavigationServer3D.map_get_closest_point(nav_map, landing_pos)
					landing_pos.y = snapped.y
					# ─── BUG FIX (Hover & Freeze): Snap to the REAL floor ─────
					# The NavMesh Y at the landing XZ can be baked ~1.5m above the
					# physical cabin floor (e.g. at window-sill height), leaving the
					# Entity hovering. The controller's gravity fallback only fires
					# when _floor_ray.is_colliding() is false, but the 4m downward
					# floor ray DOES hit the floor below, so gravity never applies
					# and the Entity floats frozen. Cast a downward physics ray from
					# the NavMesh-snapped position (which is already below the
					# ceiling) to find the actual ground floor and land on it.
					var space = entity.get_world_3d().direct_space_state
					var ray_from = landing_pos + Vector3(0, 0.5, 0)
					var ray_to = landing_pos + Vector3(0, -6.0, 0)
					var q = PhysicsRayQueryParameters3D.create(ray_from, ray_to)
					# Reuse the floor ray's collision mask (Cabin/Player/Tree/Rock)
					q.collision_mask = 0
					q.collision_mask |= (1 << (1 - 1))  # Layer 1: Cabin
					q.collision_mask |= (1 << (2 - 1))  # Layer 2: Player
					q.collision_mask |= (1 << (3 - 1))  # Layer 3: Trees
					q.collision_mask |= (1 << (4 - 1))  # Layer 4: Rocks
					var hit = space.intersect_ray(q)
					if hit:
						# ─── RAISE LANDING (BUG FIX) ─────────────────────────────
						# Previously landed at hit.position.y + 0.1, which left the
						# Entity clipping slightly into the cabin floor. Raise the
						# landing to +0.6 so it rests at the same height the
						# controller's hover-snap uses (floor_y + 0.6), matching the
						# player's resting height and clearing the floor mesh.
						landing_pos.y = hit.position.y + 0.6
						print("[INDOOR_SEARCH] Phase A: Floor ray hit at Y=%.2f. Landing on real floor (Y=%.2f)." % [hit.position.y, landing_pos.y])
					else:
						print("[INDOOR_SEARCH] Phase A: Floor ray missed. Keeping NavMesh Y=%.2f." % snapped.y)
					entity.global_position = landing_pos
					entity.velocity = Vector3.ZERO
					print("[INDOOR_SEARCH] Phase A: Vault complete! Teleported to landing position (%.2f, %.2f, %.2f) [NavMesh floor Y=%.2f]." % [landing_pos.x, landing_pos.y, landing_pos.z, snapped.y])
				else:
					print("[INDOOR_SEARCH] Phase A: No landing position set. Staying at current position.")
				
				_has_arrived_indoor = true
				entity.state_locked = false
				_enter_window_anim_timer = 0.0
				
				# ─── RESTORE PHYSICS (BUG FIX: Hover & Freeze) ─────────────
				# The window breach path (unlike the door ghost-motor path) never
				# explicitly restored normal physical movement. If is_physics_suspended
				# was left true (e.g. from a prior door Phase-2 ghost climb, or set
				# during the approach), the controller's physics block
				# (`if not is_physics_suspended:`) is skipped entirely — no
				# move_and_slide(), no gravity, no ground snapping. The Entity then
				# hovers frozen ~1m above the floor. Re-enable collision and restore
				# normal physics here so the Entity lands and patrols correctly.
				entity.set_collision_mask_value(1, true)
				# Null-check the collision shape: the Entity may not have a
				# CollisionShape3D child (get_collision_shape() can return null),
				# so guard against assigning .disabled on a null instance.
				if entity.has_method("get_collision_shape"):
					var _cs = entity.get_collision_shape()
					if _cs:
						_cs.disabled = false
				entity.is_physics_suspended = false
				entity.is_breach_locked = false
				entity._breach_lock_timer = 0.0
				entity.velocity = Vector3.ZERO
				
				# ─── CLEAR VAN SEQUENCE FLAG ──────────────────────────
				# The Entity has successfully entered the cabin. The Night 2.2
				# van chase is over — normal Entity behavior resumes.
				var nm_van = night_manager
				if nm_van and nm_van.is_van_sequence_active:
					nm_van.is_van_sequence_active = false
					print("[INDOOR_SEARCH] Van sequence flag cleared! Normal behavior restored.")
				
				# Reset the indoor search persistence timer
				var director = _director
				if director and director.has_method("reset_indoor_search_persistence"):
					director.reset_indoor_search_persistence()
				
				# Fall through to Phase B below
			else:
				# Still playing the vault animation — freeze movement
				_calculated_velocity = Vector3.ZERO
				return
	
	# ─── PHASE B: Indoor Patrol ──────────────────────────────────────
	# The Entity has arrived inside the cabin. It now patrols room-to-room
	# using the INDOOR_ROOM_GRAPH BFS pathfinding system.
	
	# ─── THROTTLE: Re-check player room every 1.0 seconds ────────────
	_room_path_recheck_timer += delta
	if _room_path_recheck_timer >= 1.0:
		_room_path_recheck_timer = 0.0
		
		# ─── GET PLAYER'S CURRENT ROOM ───────────────────────────────
		var nav = entity.get_navigation_module()
		var player_room: String = ""
		if nav and nav.has_method("get_player_room"):
			player_room = nav.get_player_room()
		
		# ─── CHECK IF PLAYER IS IN A LIT ROOM ────────────────────────
		# If the player is in a lit room, the Entity will NOT enter that
		# room. It will patrol to adjacent rooms instead.
		var player_in_lit_room = false
		if nav and nav.has_method("is_player_in_lit_room"):
			player_in_lit_room = nav.is_player_in_lit_room()
		
		# ─── ACOUSTIC DETECTION ──────────────────────────────────────
		# If the Entity heard the player (last_heard_room is set), pathfind
		# to that room's center instead of the player's exact position.
		var sensory = entity.get_sensory_module()
		var heard_room = ""
		if sensory and sensory.has_method("get_last_heard_room"):
			heard_room = sensory.last_heard_room
		
		if heard_room != "" and heard_room != "Outside":
			# ─── HEARD PLAYER: Pathfind to room center ─────────────────
			# The Entity heard the player in a specific room. Compute a
			# BFS path to that room and set the first waypoint as the target.
			var room_path = _compute_room_path(_get_entity_current_room(), heard_room)
			if not room_path.is_empty():
				_room_path = room_path
				_current_room_index = 0
				# Set BOTH the direct interior move target AND the nav target
				# (nav target only serves as a stale fallback). The cabin
				# interior is off-NavMesh, so direct movement is authoritative.
				var room_center = _get_room_center_position(_room_path[_current_room_index])
				if room_center != Vector3.ZERO:
					_indoor_direct_target = room_center
					entity.get_nav_agent().target_position = room_center
					print("[INDOOR_SEARCH] Heard player in '%s'. Pathfinding to room center." % heard_room)
		elif player_room != "" and player_room != "Outside" and not player_in_lit_room:
			# ─── PLAYER VISIBLE IN DARK ROOM: Pathfind via ROOM GRAPH ──
			# The Entity can see the player in a dark room. Do NOT set the
			# nav target directly to the player's world position — that
			# bypasses the BFS room graph and makes the Entity walk a
			# straight world-space line toward the player, colliding with
			# walls between rooms if any separate them.
			#
			# Instead, compute a BFS room-to-room path (like the acoustic
			# branch above) so the Entity routes through doorways into the
			# player's ROOM. The scanning sub-state / catch check then
			# handles the close-range interaction once inside.
			var current_room = _get_entity_current_room()
			var room_path_to_player = _compute_room_path(current_room, player_room)
			if not room_path_to_player.is_empty():
				_room_path = room_path_to_player
				_current_room_index = 0
				var room_center = _get_room_center_position(_room_path[_current_room_index])
				if room_center != Vector3.ZERO:
					_indoor_direct_target = room_center
					entity.get_nav_agent().target_position = room_center
					print("[INDOOR_SEARCH] Player spotted in dark room '%s'. Routing via '%s'." % [player_room, str(_room_path)])
			else:
				# Fallback: same room as player — direct approach is safe
				# because there is no intervening wall.
				var player = entity.get_player()
				if player:
					_indoor_direct_target = player.global_position
					entity.get_nav_agent().target_position = player.global_position
					print("[INDOOR_SEARCH] Player spotted in same room '%s'. Direct approach." % player_room)
		elif player_room != "" and player_room != "Outside" and player_in_lit_room:
			# ─── PLAYER IN LIT ROOM: Avoid, patrol adjacent ────────────
			# The player is in a lit room. The Entity will NOT enter that
			# room. Compute a BFS path to an adjacent dark room instead.
			var current_room = _get_entity_current_room()
			var adjacent_rooms = INDOOR_ROOM_GRAPH.get(current_room, [])
			var target_room = ""
			for adj in adjacent_rooms:
				if adj != player_room:
					target_room = adj
					break
			if target_room != "":
				var room_path = _compute_room_path(current_room, target_room)
				if not room_path.is_empty():
					_room_path = room_path
					_current_room_index = 0
					var room_center = _get_room_center_position(_room_path[_current_room_index])
					if room_center != Vector3.ZERO:
						_indoor_direct_target = room_center
						entity.get_nav_agent().target_position = room_center
						print("[INDOOR_SEARCH] Player in lit room '%s'. Patrolling to adjacent '%s'." % [player_room, target_room])
	
	# ─── PATHFINDING / DIRECT MOVEMENT SETUP ─────────────────────────
	# BUG 1 FIX (REVISED): The cabin interior is NOT covered by the
	# NavMesh. Do NOT trust the NavigationAgent inside the cabin — snapping
	# both the Entity and the room-center target to outdoor NavMesh points
	# produces a path that routes OUT through the front door and back in
	# (the "doorway detour" bug). Instead, always set a DIRECT world-space
	# move target to the current room center; the Entity walks a straight
	# line through the open-plan interior (it ignores cabin wall collisions
	# via the Player-only collision mask set at the top of this state).
	# Re-sync every frame in case the room path changed (throttled to the
	# usual PATH_UPDATE_INTERVAL to keep the NavAgent fallback in sync).
	_path_timer -= delta
	if _path_timer <= 0.0:
		_path_timer = PATH_UPDATE_INTERVAL
		# If we have a room path, update BOTH the direct target and the
		# (stale-fallback) nav target to the current room's center.
		if not _room_path.is_empty() and _current_room_index < _room_path.size():
			var room_center_b = _get_room_center_position(_room_path[_current_room_index])
			if room_center_b != Vector3.ZERO:
				_indoor_direct_target = room_center_b
				entity.get_nav_agent().target_position = room_center_b
	
	# ─── ARRIVAL CHECK (distance-based, NavAgent-independent) ─────────
	# The NavigationAgent cannot report "finished" at the true room center
	# (interior is off-NavMesh / its path routes via the doorway), so
	# arrival is gated on PHYSICAL distance to the room center instead
	# via _arrived_at_indoor_target().
	if _is_scanning:
		# ─── SCANNING SUB-STATE ──────────────────────────────────────
		_scan_timer -= delta
		
		# Rotate slowly in place while scanning
		var model = entity.get_monster_model()
		if model:
			model.rotation.y += delta * 0.5  # Slow rotation
		
		# Check if player is spotted during scan
		var sensory = entity.get_sensory_module()
		if sensory and sensory.has_method("can_entity_see_player") and sensory.can_entity_see_player():
			# Player spotted! CHARGE!
			_is_scanning = false
			_scan_timer = 0.0
			entity.is_charge_triggered = true
			entity.state_locked = false
			_calculated_velocity = Vector3.ZERO
			print("[INDOOR_SEARCH] Player spotted during scan! CHARGING!")
			return
		
		if _scan_timer <= 0.0:
			# Scan complete — advance to next room or compute new route
			_is_scanning = false
			_current_room_index += 1
			if _current_room_index >= _room_path.size():
				_room_path = _compute_random_patrol_route()
				_current_room_index = 0
			print("[INDOOR_SEARCH] Scan complete. Moving to next room.")
		
		_calculated_velocity = Vector3.ZERO
		return
	elif _arrived_at_indoor_target():
		# ─── PHYSICALLY ARRIVED AT ROOM CENTER: Start scanning ──────
		_is_scanning = true
		_scan_timer = 4.0
		print("[INDOOR_SEARCH] Arrived at '%s'. Starting scan (%.1fs)." % [_room_path[_current_room_index], _scan_timer])
		# Do NOT clear _indoor_direct_target or return here — fall through
		# to the CATCH CHECK below so the arrival frame still catches the
		# player if they are within reach at the room center.
	
	# ─── CATCH CHECK ─────────────────────────────────────────────────
	# If the Entity is close enough to the player, catch them.
	# This check runs every frame regardless of nav state, so the Entity
	# can catch the player even if the NavigationAgent3D hasn't finished
	# its path (e.g., the player is standing right next to the Entity).
	# ─── Y COMPARISON DEBUG (1 Hz during INDOOR_SEARCH) ─────────
	# Every second, print both the Entity's Y position and the Player's
	# Y position so we can verify the Entity is at floor level inside
	# the cabin (matching the player's Y ≈ 0.5).
	_y_debug_timer -= delta
	if _y_debug_timer <= 0.0:
		_y_debug_timer = 1.0
		var p = entity.get_player()
		var player_y: float = p.global_position.y if p else -999.0
		print("[Y-AXIS DEBUG] INDOOR_SEARCH: Entity Y=%.2f | Player Y=%.2f | Diff=%.2f" % [entity.global_position.y, player_y, entity.global_position.y - player_y])
	
	# ─── CATCH CHECK ─────────────────────────────────────────────────
	# If the Entity is close enough to the player, catch them.
	# This check runs every frame regardless of nav state, so the Entity
	# can catch the player even if the NavigationAgent3D hasn't finished
	# its path (e.g., the player is standing right next to the Entity).
	var player = entity.get_player()
	if player and entity.global_position.distance_to(player.global_position) <= entity.catch_distance:
		entity._on_caught_player()
		return
	
	# ─── MOVEMENT ────────────────────────────────────────────────────
	# BUG 1/2 FIX (REVISED): Prefer DIRECT straight-line movement toward
	# the indoor move target. The NavigationAgent cannot be trusted inside
	# the cabin (interior is off-NavMesh; its path routes through the front
	# door). The Entity ignores cabin wall collisions during indoor search,
	# so the straight line to the target is always valid and never detours
	# to the door. NavAgent following is kept only when no direct target
	# is set (e.g., stale empty room path) as a last-resort safeguard.
	if _indoor_direct_target != Vector3.ZERO:
		var direct_dir = (_indoor_direct_target - entity.global_position)
		direct_dir.y = 0.0
		if direct_dir.length() > 0.01:
			var move_dir = direct_dir.normalized()
			_calculated_velocity.x = move_dir.x * entity.current_stalk_speed
			_calculated_velocity.z = move_dir.z * entity.current_stalk_speed
		else:
			_calculated_velocity.x = 0.0
			_calculated_velocity.z = 0.0
	elif entity.get_nav_agent().is_navigation_finished():
		_calculated_velocity.x = 0.0
		_calculated_velocity.z = 0.0
	else:
		var next_pos = entity.get_nav_agent().get_next_path_position()
		var dir_2d := Vector2(next_pos.x - entity.global_position.x, next_pos.z - entity.global_position.z)
		if dir_2d.length() > 0.01:
			var move_dir_2d = dir_2d.normalized()
			_calculated_velocity.x = move_dir_2d.x * entity.current_stalk_speed
			_calculated_velocity.z = move_dir_2d.y * entity.current_stalk_speed


## ─── INDOOR ROOM NAVIGATION HELPERS ──────────────────────────────────────

## Returns the name of the room the Entity is currently in.
## Uses RoomLightDetector.get_room_name_at() to resolve the Entity's position.
##
## HEIGHT-INSENSITIVE FIX (Indoor Room Detection):
## After a window-breach teleport, the Entity lands on the PHYSICS floor at
## Y≈0.6 (ground collider at hit_y≈0.025 + 0.6 hover). However, the
## Cabin_Interior Area3D room volumes are aligned with the NAVMESH floor,
## baked at Y≈0.96. RoomLightDetector.get_room_name_at() uses 3D volume
## containment (contains_point), so sampling at Y=0.6 returns "Outside"
## even though the Entity is physically inside the cabin.
##
## FIX: Project the Entity's XZ position onto the NavigationMesh to obtain
## the NavMesh floor height at that location. If that NavMesh Y is above the
## Entity's current Y, sample the room at the NavMesh height instead — the
## room volumes recognize it. This makes room detection independent of the
## Entity's resting Y after teleports.
func _get_entity_current_room() -> String:
	var room_detector = entity.get_node_or_null("/root/RoomLightDetector")
	if not room_detector or not room_detector.has_method("get_room_name_at"):
		return ""
	
	var check_pos = entity.global_position
	# ─── NAVMESH-AWARE Y HEIGHT ────────────────────────────────────────
	# Project onto the navigation map to get the walkable floor height at
	# the Entity's XZ position. If that height is ABOVE the Entity's current
	# Y (the Entity is below the room volumes), lift the sample point.
	var nav_map = entity.get_world_3d().navigation_map
	if nav_map.is_valid():
		var nav_pos = NavigationServer3D.map_get_closest_point(nav_map, check_pos)
		if nav_pos.y > check_pos.y:
			check_pos.y = nav_pos.y
	
	return room_detector.get_room_name_at(check_pos)


## Returns the world-space position of a room's center node.
## Looks for a CabinRoom node with the matching room name in the scene tree.
func _get_room_center_position(room_name: String) -> Vector3:
	var rooms = entity.get_tree().get_nodes_in_group("CabinRooms")
	for room in rooms:
		if "room_name" in room and room.room_name == room_name:
			return room.global_position
	return Vector3.ZERO


## BUG 1 FIX: Returns true if the Entity has physically arrived (distance
## <= 1.5m) at the current indoor move-target room center. Used to gate the
## INDOOR_SEARCH arrival/scan logic independently of the NavigationAgent,
## which cannot be trusted inside the cabin (interior is off-NavMesh — its
## path routes via the doorway and may never report "finished" at the true
## room center).
func _arrived_at_indoor_target() -> bool:
	if _room_path.is_empty() or _current_room_index >= _room_path.size():
		return false
	var room_center = _get_room_center_position(_room_path[_current_room_index])
	if room_center == Vector3.ZERO:
		return false
	return entity.global_position.distance_to(room_center) <= 1.5


## Computes a BFS path from start_room to end_room using INDOOR_ROOM_GRAPH.
## Returns an array of room names representing the shortest path.
## Returns an empty array if no path exists.
func _compute_room_path(start_room: String, end_room: String) -> Array[String]:
	if start_room == "" or end_room == "":
		return []
	if start_room == end_room:
		return [start_room]
	
	# BFS
	var queue: Array[String] = [start_room]
	var visited: Dictionary = {}
	var parent: Dictionary = {}
	visited[start_room] = true
	
	while not queue.is_empty():
		var current = queue.pop_front()
		if current == end_room:
			# Reconstruct path
			var path: Array[String] = []
			var node = end_room
			while node != start_room:
				path.push_front(node)
				node = parent[node]
			path.push_front(start_room)
			return path
		
		var neighbors = INDOOR_ROOM_GRAPH.get(current, [])
		for neighbor in neighbors:
			if not visited.has(neighbor):
				visited[neighbor] = true
				parent[neighbor] = current
				queue.push_back(neighbor)
	
	return []


## Computes a random patrol route for the Entity to follow during indoor search.
## Picks a random room from the graph and computes a BFS path to it.
func _compute_random_patrol_route() -> Array[String]:
	var current_room = _get_entity_current_room()
	if current_room == "":
		return []
	
	# Pick a random room that is NOT the current room
	var all_rooms = INDOOR_ROOM_GRAPH.keys()
	var target_room = current_room
	while target_room == current_room:
		target_room = all_rooms[randi() % all_rooms.size()]
	
	return _compute_room_path(current_room, target_room)




# ---------------------------------------------------------------------------
# PROXIMITY HELPERS
# ---------------------------------------------------------------------------
## ─── DOOR PROXIMITY CHECK ──────────────────────────────────────────────────
## Returns true if the Entity is within `threshold` meters (2D XZ plane) of
## the given door node. Used by both the APPROACH_WINDOW failsafe and the
## WINDOW_PEEK breach guard to prevent the Entity from breaching a door it
## cannot physically reach.
##
## Uses 2D distance (XZ plane) to ignore vertical differences (e.g., the Entity
## is on the ground and the door is on a porch step).
const DOOR_PROXIMITY_THRESHOLD: float = 2.0

func _is_close_enough_to_door(door_node: Node3D) -> bool:
	if not door_node or not is_instance_valid(door_node):
		return false
	var my_pos_2d = Vector2(entity.global_position.x, entity.global_position.z)
	var door_pos_2d = Vector2(door_node.global_position.x, door_node.global_position.z)
	var dist_2d = my_pos_2d.distance_to(door_pos_2d)
	return dist_2d <= DOOR_PROXIMITY_THRESHOLD


## ─── CONSECUTIVE DOOR FAILSAFE COUNTER ─────────────────────────────────────
## Tracks how many times the APPROACH_WINDOW failsafe has fired consecutively
## for a door target. After MAX_DOOR_FAILSAFE_RETRIES consecutive failures,
## the Entity gives up on the door and falls back to OBSERVE_FROM_TREELINE.
## Reset to 0 when the Entity successfully reaches any target.
var _consecutive_door_failsafe_count: int = 0
const MAX_DOOR_FAILSAFE_RETRIES: int = 3


## ─── CABIN WINDOW RESOLUTION HELPER ──────────────────────────────────────────
## Walks UP the entire scene tree from any child node to find the nearest
## CabinWindow ancestor. Uses a while loop that never gives up until it
## reaches the scene root. Returns null if NO CabinWindow is found anywhere
## in the ancestry chain.
##
## This prevents the "capability cache failure" bug where _cap_window_shatter was
## sampled from the FIRST WindowMarker in the group — if that marker was a door
## or a non-CabinWindow node, the cache returned false and glass never shattered.
## By resolving to the CabinWindow parent at runtime, we ensure the correct node
## receives the shatter call regardless of which child marker was targeted.
func _resolve_window_target(target: Node3D) -> CabinWindow:
	if not target:
		return null
	if target is CabinWindow:
		return target
	var current: Node = target
	while current:
		if current is CabinWindow:
			return current
		current = current.get_parent()
	return null
