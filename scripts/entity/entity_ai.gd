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

## Arrival distance (in meters) for Phase 2 of the door approach.
## The Entity must be within this distance of the IndoorBreachWaypoint before
## signaling completion. A tight threshold (0.3m) ensures the Entity has
## physically walked through the doorway before transitioning to INDOOR_SEARCH.
@export var door_phase_2_arrival_distance: float = 0.02

## Failsafe timeout (in seconds) for Phase 2 of the door approach.
## If the Entity has been pathfinding to the IndoorBreachWaypoint for this long
## without arriving, force a completion signal to prevent soft-locks.
@export var door_phase_2_failsafe_timeout: float = 5.0

## Debug log interval (in seconds) for APPROACH_WINDOW and WINDOW_PEEK.
## Prints Entity and window coordinates at this interval to help debug
## pathfinding issues.
@export var approach_debug_interval: float = 2.0

## Breach delay (in seconds) before the Entity starts attempting to breach
## a window after arriving at it. Gives the player a brief window to react.
## Reduced from 10.0 to 3.0 — 10s made the Entity too passive and the
## player could easily turn on lights to reset the siege.
@export var breach_delay: float = 5.0

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

## Lamp attack interval (in seconds) — how often the Entity strikes the portable lamp.
@export var lamp_attack_interval: float = 3.0

## Lamp attack range (in meters) — how close the Entity must be to strike the lamp.
@export var lamp_attack_range: float = 3.0

## Fuse sabotage interval (in seconds) — how often the Entity strikes the Fuse Box.
@export var fuse_sabotage_interval: float = 2.0

## Fuse sabotage range (in meters) — how close the Entity must be to strike the Fuse Box.
@export var fuse_sabotage_range: float = 2.5

## Fuse sabotage stuck timeout (in seconds) — if the Entity has been within 5m of the
## EntityFuseWaypoint for this long without reaching the 2.5m arrival threshold,
## teleport directly to the waypoint to prevent soft-locks from geometry blocking.
@export var fuse_sabotage_stuck_timeout: float = 4.0

## Approach arrival distance (in meters) — 2D distance threshold for arriving at a window.
@export var approach_arrival_distance: float = 2.5

## Interaction radius (in meters) — 2D distance threshold for door interaction.
## The Entity must be within this distance of the door before it can open it
## or trigger the breach animation. Prevents "Bluetooth Door Opening" where
## the Entity triggers the breach while still physically distant from the door.
@export var interaction_radius: float = 2.5

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

## Confidence threshold for APPROACH_WINDOW escalation.
@export var confidence_approach_threshold: float = 40.0

## Stare time threshold (in seconds) for CHARGE transition.
@export var charge_stare_threshold: float = 1.5

## ─── STALK BEHAVIOR TUNING ────────────────────────────────────────────
## Minimum distance (meters) the Entity tries to maintain from the player
## during STALK. When closer than this, speed drops to slow approach.
## Default: 3.0m — keeps the Entity at a threatening but not face-hugging range.
@export var stalk_min_distance: float = 3.0

## Maximum distance (meters) for full-speed pursuit during STALK.
## When farther than this, the Entity uses 100% stalk speed.
## Default: 10.0m — beyond this range the Entity sprint-closes the gap.
@export var stalk_max_distance: float = 10.0

## Speed multiplier when the Entity is between stalk_min_distance and stalk_max_distance.
## Applied proportionally: 0.3x at min_distance, 1.0x at max_distance.
@export var stalk_close_speed_mult: float = 0.3

## Whether STALK flanking behavior is enabled. When true, the Entity will
## periodically circle to a flanking offset position instead of pathing
## directly toward the player, creating more organic predatory movement.
@export var flanking_enabled: bool = true

## Interval (seconds) between flank maneuvers during STALK with LOS.
## Default: 8.0s — flank every ~8 seconds while chasing.
@export var flank_interval: float = 8.0

## Offset distance (meters) for flanking waypoints. The Entity navigates
## to a point offset perpendicular to the Entity→Player direction.
## Default: 8.0m — wide arcs around the player's position.
@export var flank_offset_distance: float = 8.0

## Speed multiplier when LOS is broken during STALK. The Entity slows down
## when it loses visual contact, simulating uncertainty.
## Default: 0.5x — half speed while searching.
@export var stalk_search_speed_mult: float = 0.5

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
var _cap_window_shatter: bool = false
var _cap_window_get_id: bool = false
var _cap_window_damage_barricade: bool = false
var _cap_window_breach: bool = false
var _cap_window_landing: bool = false
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

## Whether a retreat target has been set for physical RETREAT pathfinding.
## Reset after the Entity reaches the exit point and fades out.
var _retreat_target_set: bool = false

## Guard flag for the STALK state's target_desired_distance = 0.3 assignment.
var _stalk_target_distance_set: bool = false

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

## Stuck timer for SABOTAGE_FUSE state. Accumulates delta while the Entity is
## within 5m of the EntityFuseWaypoint but hasn't reached the 2.5m arrival
## threshold. If this timer exceeds fuse_sabotage_stuck_timeout (4.0s), the
## Entity teleports directly to the waypoint to prevent soft-locks from
## geometry blocking (e.g., crates blocking the last 0.07m of the path).
var _sabotage_stuck_timer: float = 0.0

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
	# Cache common window methods on a representative CabinWindow
	var window_markers = entity.get_tree().get_nodes_in_group("WindowMarkers") if entity else []
	if not window_markers.is_empty():
		var sample_window = window_markers[0]
		_cap_window_get_id = sample_window.has_method("get_window_id")
		_cap_window_shatter = sample_window.has_method("shatter_window")
		_cap_window_damage_barricade = sample_window.has_method("damage_barricade")
		_cap_window_landing = sample_window.has_method("get_indoor_landing_position")
		_cap_window_breach = sample_window.has_method("register_breach")
	# Cache door/fuse methods
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
		# STATE LOCK: If the state handler is mid-execution, skip the
		# Director's state transition entirely. The handler will unlock
		# when it completes its work.
		if entity.state_locked:
			# Director still evaluates for logging/debugging.
			var _debug_intended = _director.evaluate_master_state(entity)
			# ─── TIER 0 OVERRIDE GATE ──────────────────────────────────
			# Even when locked, critical reactions (FLINCH, RETREAT,
			# STANDOFF, CHARGE) must break the lock. The Entity cannot
			# stay locked in WINDOW_PEEK while being blinded.
			if _debug_intended == State.FLINCH or _debug_intended == State.RETREAT or _debug_intended == State.STANDOFF or _debug_intended == State.CHARGE:
				entity.state_locked = false
				if entity.get_state() != _debug_intended:
					print("[TRACE_STATE] TIER 0 OVERRIDE: Breaking state lock! %s → %s" % [_get_state_name(entity.get_state()), _get_state_name(_debug_intended)])
					entity.set_state(_debug_intended)
		else:
			var intended_state = _director.evaluate_master_state(entity)
			
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
	#   - If state is CHARGE or RETREAT, the Entity is immune to the stun
	#     (it's already committed to an action).
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
	
	if _is_being_stared_at and current_state != State.CHARGE and current_state != State.RETREAT:
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
	
	if not trap or not trap.is_deployed or not trap.is_powered:
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
	# Lock the state — the Director must not override while we're mid-sabotage
	entity.state_locked = true
	
	# Use the cached @export fuse_box_node reference (resolved once in
	# _initialize_entity()). This avoids the expensive scene tree traversal
	# that was previously called every frame via get_fuse_box_node().
	var fuse_box = entity.fuse_box_node
	
	if not fuse_box or not is_instance_valid(fuse_box):
		# Fuse Box doesn't exist or was destroyed — signal completion
		entity.is_fuse_sabotaged = true
		entity.state_locked = false
		_calculated_velocity = Vector3.ZERO
		return
	
	# Check if the Fuse Box is already destroyed
	# Use direct property access instead of duck-typing has_method() checks.
	# The cached fuse_box_node is typed as FuseBox, so is_powered is guaranteed.
	if not fuse_box.is_powered():
		# Already broken — signal completion
		entity.is_fuse_sabotaged = true
		entity.state_locked = false
		_calculated_velocity = Vector3.ZERO
		print("[SABOTAGE_FUSE] Fuse Box already broken. Signaling completion.")
		return
	
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
			_calculated_velocity = Vector3.ZERO
			print("[SABOTAGE_FUSE] Fuse Box broken! Signaling completion.")
			return
		
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
		return
	
	# ─── PATHFIND TOWARD THE FUSE WAYPOINT ──────────────────────────────
	_path_timer -= delta
	if _path_timer <= 0.0:
		_path_timer = PATH_UPDATE_INTERVAL
		entity.get_nav_agent().target_position = fuse_waypoint.global_position
	
	var dist_to_wp = entity.global_position.distance_to(fuse_waypoint.global_position)
	
	# ─── STUCK DETECTION ────────────────────────────────────────────────
	# If the Entity is within 5m of the waypoint but hasn't reached the
	# 2.5m arrival threshold, accumulate the stuck timer. This handles
	# cases where geometry (e.g., crates, pallets) blocks the last few
	# meters of the path. If the timer exceeds the timeout, teleport
	# directly to the waypoint to prevent soft-locks.
	if dist_to_wp <= 5.0 and dist_to_wp > 2.5:
		_sabotage_stuck_timer += delta
		if _sabotage_stuck_timer >= fuse_sabotage_stuck_timeout:
			print("[SABOTAGE_FUSE] STUCK TIMEOUT! Entity stuck at dist=%.2f for %.1fs. Teleporting to waypoint." % [dist_to_wp, _sabotage_stuck_timer])
			entity.global_position = fuse_waypoint.global_position
			entity.velocity = Vector3.ZERO
			_sabotage_stuck_timer = 0.0
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
		# Arrived at the waypoint — reset stuck timer and break the fuse box
		_sabotage_stuck_timer = 0.0
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
	else:
		# Far from the waypoint — reset stuck timer (not stuck yet)
		_sabotage_stuck_timer = 0.0
	
	# ─── MOVEMENT TOWARD WAYPOINT ──────────────────────────────────────
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

func _stalk_state(delta: float) -> void:
	# ─── TIGHTEN NAV TARGET DISTANCE (ONCE ON ENTRY) ─────────────────
	var nav_agent = entity.get_nav_agent()
	if not _stalk_target_distance_set:
		_stalk_target_distance_set = true
		nav_agent.target_desired_distance = 0.3
		nav_agent.path_desired_distance = 0.3
		# Reset flank timer on state entry
		_stalk_flank_timer = 0.0
		_stalk_is_flanking = false
		_stalk_los_break_timer = 0.0
		_stalk_current_speed_mult = 1.0
	
	# ─── HALLROOM / INDOOR EXIT GUARD ──────────────────────────
	var nav = entity.get_navigation_module()
	if nav and nav.has_method("get_player_room"):
		var player_room = nav.get_player_room()
		if player_room != "Outside" and player_room != "":
			if player_room == "Hallroom":
				print("[Entity AI] STALK: Player entered Hallroom. Force-exiting STALK.")
				entity.is_observe_finished = true
				entity.state_locked = false
				entity.request_state(EntityAI.State.OBSERVE_FROM_TREELINE)
				_calculated_velocity = Vector3.ZERO
				return
			elif night_manager and night_manager.is_van_sequence_active:
				pass
			else:
				print("[Entity AI] STALK: Player entered '%s'. Force-exiting STALK." % player_room)
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
		
		if _stalk_is_flanking:
			# Navigate toward the flank target
			var dist_to_flank = entity.global_position.distance_to(_stalk_flank_target)
			if dist_to_flank <= 2.0:
				# Reached flank point — resume direct chase
				_stalk_is_flanking = false
				_stalk_flank_target = Vector3.ZERO
				# Set nav target to player
				var jitter = Vector3(randf_range(-0.1, 0.1), 0.0, randf_range(-0.1, 0.1))
				entity.get_nav_agent().target_position = player.global_position + jitter
			else:
				entity.get_nav_agent().target_position = _stalk_flank_target
		else:
			# Normal chase: direct pursuit with jitter
			var jitter_offset = Vector3(randf_range(-0.1, 0.1), 0.0, randf_range(-0.1, 0.1))
			entity.get_nav_agent().target_position = player.global_position + jitter_offset
	
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
	
	if (nav_finished or dist_to_lkp <= 3.0) and not _is_investigating:
		var can_see_player = false
		if sensory and sensory.has_method("can_entity_see_player"):
			can_see_player = sensory.can_entity_see_player()
		
		if not can_see_player:
			_is_investigating = true
			_investigation_timer = 4.0
			_calculated_velocity = Vector3.ZERO
			return
	
	# ─── APPLY SPEED WITH ALL MULTIPLIERS ───────────────────────
	var final_speed = entity.current_stalk_speed * _stalk_current_speed_mult
	
	if entity.get_nav_agent().is_navigation_finished():
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
	var night_manager = night_manager
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
##   APPROACH_WINDOW → OBSERVE_FROM_TREELINE 60fps oscillation loop.
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

## ─── APPROACH DEBUG LOG TIMER ──────────────────────────────────────────────
## Prints Entity and window coordinates every 2 seconds during APPROACH_WINDOW
## to help debug pathfinding issues (e.g., Entity not moving toward the window,
## NavMesh can't reach the target, or the Entity is stuck at the cabin wall).
var _approach_debug_timer: float = 0.0
const APPROACH_DEBUG_INTERVAL: float = 2.0

func _approach_window_state(delta: float) -> void:
	# ─── FLINCH OVERRIDE GATE (defensive early-exit) ────────────────────
	# If the Entity is illuminated by the player's flashlight while the player
	# is inside, the Director should transition to FLINCH. Release the lock
	# and exit early so the Director can apply FLINCH on the next frame.
	# This prevents a 1-frame race where _approach_window_state locks the
	# state each frame, fighting the Director's FLINCH override.
	if entity.is_illuminated and entity.has_method("get_thinks_player_is_inside") and entity.get_thinks_player_is_inside():
		entity.state_locked = false
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
			# ─── WINDOW FAILSAFE: Standard completion (no teleport) ───────
			# For window targets, just signal completion. The Director will
			# transition to OBSERVE_FROM_TREELINE and try a different window.
			# Reset the consecutive door failsafe counter since we successfully
			# handled a window (non-door) target.
			_consecutive_door_failsafe_count = 0
			print("[Entity AI] APPROACH_WINDOW FAILSAFE: Window target. Signaling completion without teleport.")
		
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
				# The NavMesh can't get us closer. Stop moving and wait for
				# the failsafe timeout (15s) or distance threshold to be met.
				_calculated_velocity.x = 0.0
				_calculated_velocity.z = 0.0
		
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
		#
		# NOTE: This block handles Phase 0→1 transitions (arriving at the door
		# for the first time). Once _door_phase >= 1, the Phase 1 and Phase 2
		# loops above handle the rest independently.
		if dist_2d <= approach_arrival_distance and _approach_min_timer >= approach_min_duration:
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
			else:
				print("[DOOR DEBUG] Target is NOT a door (cached door_waypoint_marker=%s, window_target=%s)." % [cached_door_wp.name if cached_door_wp else "null", window_target.name])
			
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
	
	# ─── RESET PEEK ASSESSMENT ON FRESH ENTRY ───────────────────────────
	# When the Entity first enters WINDOW_PEEK (siege timer is 0.0), reset
	# the _peek_assessment_done flag so the peek assessment runs again.
	# Without this reset, if the Entity aborted a previous peek (e.g., room
	# was lit) and later re-enters WINDOW_PEEK at a different window, the
	# stale _peek_assessment_done = true would prevent re-evaluation.
	if _siege_duration_timer <= 0.0:
		_peek_assessment_done = false
	
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
					
					# ─── SAFE TYPE-CHECK: Door vs Window Breach ─────────────
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
				if window_target.has_method("damage_barricade"):
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
		
		# ─── FACE THE WINDOW ─────────────────────────────────────────────
		# Rotate the monster model to face the window while peeking.
		# Use the WindowMarker (outside the window) as the look target, not
		# the CabinWindow node which is inside the wall.
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
## The Entity sprints laterally (perpendicular to the player's camera view)
## for 1.5 seconds to evade the flashlight beam. After the sprint completes,
## it signals completion to the Director.
##
## The flinch target position is calculated as a point 8 meters to the left
## or right of the Entity's current position, perpendicular to the player's
## camera forward vector. This creates a natural-looking dodge rather than
## a random teleport.
func _flinch_state(delta: float) -> void:
	# Lock the state — the Director must not override while we're mid-flinch
	entity.state_locked = true
	
	# ─── INITIALIZE FLINCH ON FIRST FRAME ──────────────────────────────
	# If the flinch timer is 0.0 (or less), this is the first frame of the
	# flinch. Calculate the target position and set the timer.
	if entity.get_flinched_timer() <= 0.0:
		# Randomize flinch duration between 3-5 seconds
		var flinch_duration = randf_range(3.0, 5.0)
		entity.set_flinched_timer(flinch_duration)
		
		# Calculate lateral sprint direction (perpendicular to player's camera)
		var player = entity.get_player()
		if player:
			var cam = null
			if player.has_node("Camera3D"):
				cam = player.get_node("Camera3D")
			if cam:
				var cam_forward = -cam.global_transform.basis.z
				cam_forward.y = 0.0
				cam_forward = cam_forward.normalized()
				
				# Pick left or right randomly
				var lateral_dir = cam_forward.cross(Vector3.UP).normalized()
				if randf() < 0.5:
					lateral_dir = -lateral_dir
				
				# Calculate target position 8 meters laterally
				entity.set_flinch_target_pos(entity.global_position + lateral_dir * flinch_distance)
		
		print("[FLINCH] Initialized! Duration=%.1fs, Distance=%.1fm" % [flinch_duration, flinch_distance])
	
	# ─── SPRINT TOWARD TARGET ──────────────────────────────────────────
	var target = entity.get_flinch_target_pos()
	var dir_to_target = (target - entity.global_position).normalized()
	var flinch_speed = entity.current_stalk_speed * flinch_sprint_multiplier
	
	_calculated_velocity.x = dir_to_target.x * flinch_speed
	_calculated_velocity.z = dir_to_target.z * flinch_speed
	
	# ─── DECREMENT TIMER ───────────────────────────────────────────────
	entity.set_flinched_timer(entity.get_flinched_timer() - delta)
	
	# ─── COMPLETION CHECK ──────────────────────────────────────────────
	if entity.get_flinched_timer() <= 0.0:
		entity.is_flinch_finished = true
		entity.state_locked = false
		_calculated_velocity = Vector3.ZERO
		print("[FLINCH] Complete! Signaling completion to Director.")
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
				var landing_pos = entity.get_indoor_landing_position()
				if landing_pos != Vector3.ZERO:
					entity.global_position = landing_pos
					entity.velocity = Vector3.ZERO
					print("[INDOOR_SEARCH] Phase A: Vault complete! Teleported to landing position.")
				else:
					print("[INDOOR_SEARCH] Phase A: No landing position set. Staying at current position.")
				
				_has_arrived_indoor = true
				entity.state_locked = false
				_enter_window_anim_timer = 0.0
				
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
				# Set the nav target to the first room's center
				var room_center = _get_room_center_position(_room_path[_current_room_index])
				if room_center != Vector3.ZERO:
					entity.get_nav_agent().target_position = room_center
					print("[INDOOR_SEARCH] Heard player in '%s'. Pathfinding to room center." % heard_room)
		elif player_room != "" and player_room != "Outside" and not player_in_lit_room:
			# ─── PLAYER VISIBLE IN DARK ROOM: Pathfind to player ───────
			# The Entity can see the player in a dark room. Pathfind toward
			# the player's position.
			var player = entity.get_player()
			if player:
				entity.get_nav_agent().target_position = player.global_position
				print("[INDOOR_SEARCH] Player spotted in dark room '%s'. Pathfinding to player." % player_room)
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
						entity.get_nav_agent().target_position = room_center
						print("[INDOOR_SEARCH] Player in lit room '%s'. Patrolling to adjacent '%s'." % [player_room, target_room])
	
	# ─── PATHFINDING ─────────────────────────────────────────────────
	# Throttle NavigationAgent3D target_position updates to prevent FPS drops.
	_path_timer -= delta
	if _path_timer <= 0.0:
		_path_timer = PATH_UPDATE_INTERVAL
		
		# If we have a room path, navigate to the current room's center
		if not _room_path.is_empty() and _current_room_index < _room_path.size():
			var room_center = _get_room_center_position(_room_path[_current_room_index])
			if room_center != Vector3.ZERO:
				entity.get_nav_agent().target_position = room_center
	
	# ─── ARRIVAL CHECK ───────────────────────────────────────────────
	# If the NavigationAgent3D has finished, check if we've arrived at
	# the current room center. If so, advance to the next room or enter
	# the scanning sub-state.
	if entity.get_nav_agent().is_navigation_finished():
		if not _room_path.is_empty() and _current_room_index < _room_path.size():
			var room_center = _get_room_center_position(_room_path[_current_room_index])
			var dist_to_center = entity.global_position.distance_to(room_center)
			
			if dist_to_center <= 1.5 and not _is_scanning:
				# ─── ARRIVED AT ROOM CENTER: Start scanning ──────────────
				_is_scanning = true
				_scan_timer = 4.0
				print("[INDOOR_SEARCH] Arrived at '%s'. Starting scan (%.1fs)." % [_room_path[_current_room_index], _scan_timer])
			
			elif dist_to_center > 1.5:
				# ─── NOT AT CENTER YET: Keep pathfinding ─────────────────
				# The nav agent finished but we're not at the room center.
				# This can happen when the NavMesh doesn't reach the exact
				# room center coordinate. Just advance to the next room.
				_current_room_index += 1
				if _current_room_index >= _room_path.size():
					# Reached the end of the path — compute a new patrol route
					_room_path = _compute_random_patrol_route()
					_current_room_index = 0
		
		# ─── SCANNING SUB-STATE ──────────────────────────────────────
		if _is_scanning:
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


## ─── INDOOR ROOM NAVIGATION HELPERS ──────────────────────────────────────

## Returns the name of the room the Entity is currently in.
## Uses RoomLightDetector.get_room_name_at() to resolve the Entity's position.
func _get_entity_current_room() -> String:
	var room_detector = entity.get_node_or_null("/root/RoomLightDetector")
	if room_detector and room_detector.has_method("get_room_name_at"):
		return room_detector.get_room_name_at(entity.global_position)
	return ""


## Returns the world-space position of a room's center node.
## Looks for a CabinRoom node with the matching room name in the scene tree.
func _get_room_center_position(room_name: String) -> Vector3:
	var rooms = entity.get_tree().get_nodes_in_group("CabinRooms")
	for room in rooms:
		if "room_name" in room and room.room_name == room_name:
			return room.global_position
	return Vector3.ZERO


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
