extends Resource
# NOTE: class_name EntityConfig removed to avoid "hides a global script class"
# parse error in the Godot editor cache. The resource works identically without
# a global class name — scripts reference it via preload("res://resources/entity_config.tres")
# and access its @export properties directly on the loaded instance.

## Entity Configuration Resource — Centralized tuning knobs for the Entity AI.
## All balance-critical values that were previously scattered as const/hardcoded
## literals across entity_confidence.gd, entity_director.gd, entity_controller.gd,
## and entity_navigation.gd are consolidated here for single-point-of-truth tuning.
##
## Usage:
##   var config = preload("res://resources/entity_config.tres")
##   if confidence >= config.threshold_window_approach:
##       entity.set_state(EntityAI.State.APPROACH_WINDOW)
##
## Design Goal: Non-breaking refactor. All default values match the current
## hardcoded values exactly — only the source changes (const → @export resource).

# ─── CONFIDENCE THRESHOLDS ───────────────────────────────────────────────────
## Minimum confidence required for the Entity to approach a window.
@export var threshold_window_approach: float = 30.0

## Minimum confidence required for the Entity to attempt a full breach.
@export var threshold_breach: float = 65.0

## Minimum confidence required for the climax sprint (generator dead + max).
@export var threshold_climax: float = 85.0

## Below this threshold, the Entity will retreat from any confrontation.
@export var threshold_retreat: float = 20.0

# ─── CONFIDENCE SYSTEM ───────────────────────────────────────────────────────
## Initial confidence value on Night 1.
@export var initial_confidence: float = 15.0

## Base resting confidence (drifts toward this when no modifiers are active).
@export var resting_confidence_base: float = 15.0

## Rate at which confidence drifts toward the resting value (per second).
@export var confidence_decay_rate: float = 2.0

## Per-night confidence bonus (added to resting_confidence_base per night).
@export var night_confidence_bonus: float = 8.0

# ─── HYSTERESIS BANDS (Oscillation Prevention) ───────────────────────────────
## Confidence hysteresis margin for threshold crossings.
@export var hysteresis_margin: float = 5.0

## Minimum dwell time (seconds) in a non-emergency state before the Director
## can transition out of it. Prevents 60fps oscillation between adjacent states.
@export var min_state_dwell_time: float = 1.0

# ─── MOVEMENT SPEEDS ─────────────────────────────────────────────────────────
## Base walk speed (m/s) during patrol/search states.
@export var walk_speed: float = 2.0

## Sprint speed multiplier during CHARGE state (3.0 = 3x base speed).
@export var charge_speed_multiplier: float = 3.0

## Sprint speed multiplier during FLINCH lateral evasion.
@export var flinch_sprint_multiplier: float = 1.5

## Sprint speed multiplier during indoor retreat.
@export var indoor_retreat_sprint_multiplier: float = 1.5

## Permanent speed boost when enraged (blackout release).
@export var enraged_speed_multiplier: float = 1.5

## Speed multiplier when LOS is broken during STALK.
@export var stalk_search_speed_mult: float = 0.5

# ─── DETECTION RANGES ────────────────────────────────────────────────────────
## Vision range when player's flashlight is ON.
@export var vision_range_flashlight_on: float = 30.0

## Vision range when environment is lit (room lights on).
@export var vision_range_lit: float = 15.0

## Vision range when dark and flashlight OFF (severely limited).
@export var vision_range_dark: float = 10.0

## Extended vision range for treeline/window observation states.
@export var vision_range_observe: float = 35.0

## Hearing radius for sprint noise (meters).
@export var hearing_radius_sprint: float = 20.0

## Hearing radius for walk noise (meters).
@export var hearing_radius_walk: float = 10.0

# ─── NAVIGATION ──────────────────────────────────────────────────────────────
## Arrival distance threshold for window approach (2D distance, meters).
@export var approach_arrival_distance: float = 2.5

## Arrival distance for door interaction (prevents "Bluetooth Door Opening").
@export var interaction_radius: float = 2.5

## Distance threshold for fuse sabotage arrival.
@export var fuse_sabotage_range: float = 2.5

## Distance threshold for lamp attack arrival.
@export var lamp_attack_range: float = 3.0

## Path update throttle interval (seconds).
@export var path_update_interval: float = 0.3

# ─── STATE TIMERS ────────────────────────────────────────────────────────────
## Minimum duration for WINDOW_PEEK siege before exit is allowed.
@export var siege_min_duration: float = 5.0

## Siege max duration — hard failsafe to prevent permanent WINDOW_PEEK lock.
@export var siege_max_duration: float = 30.0

## Barricade damage interval during WINDOW_PEEK (seconds between hits).
@export var barricade_damage_interval: float = 2.0

## Barricade animation lock duration (seconds) — how long AttackWindow is forced.
@export var barricade_anim_lock_duration: float = 1.5

## Pending damage delay (seconds) — syncs health subtraction with animation impact.
@export var pending_damage_delay: float = 0.6

## Breach delay before Entity attempts window breach (seconds).
@export var breach_delay: float = 5.0

## Indoor search persistence — how long Entity must stay inside after breach.
@export var indoor_search_persistence: float = 30.0

## Door breach cooldown — minimum time between door breach attempts.
@export var door_breach_cooldown: float = 15.0

# ─── ANIMATION TIMING ────────────────────────────────────────────────────────
## Duration of the EnterWindow vault animation (seconds).
@export var enter_window_anim_duration: float = 1.5

## Glass shatter impact delay (seconds) — syncs AttackWindow animation with shatter.
@export var glass_shatter_impact_delay: float = 0.5

# ─── APPROACH TIMING ─────────────────────────────────────────────────────────
## Minimum duration (seconds) the Entity must pathfind in APPROACH_WINDOW.
@export var approach_min_duration: float = 2.0

## Failsafe timeout (seconds) for APPROACH_WINDOW.
@export var approach_failsafe_timeout: float = 15.0

## Approach debug log interval (seconds).
@export var approach_debug_interval: float = 2.0

# ─── DOOR PARAMETERS ─────────────────────────────────────────────────────────
## Arrival distance (meters) for Door Phase 2 breach waypoint.
@export var door_phase_2_arrival_distance: float = 0.5

## Failsafe timeout (seconds) for Door Phase 2 pathfinding.
@export var door_phase_2_failsafe_timeout: float = 5.0

# ─── DESPERATION MECHANIC ────────────────────────────────────────────────────
## Passive timer threshold (seconds) before desperation modifier kicks in.
@export var desperation_threshold: float = 45.0

## Desperation confidence modifier rate (confidence per second).
@export var desperation_modifier_rate: float = 0.5

# ─── STARE/FLINCH MECHANICS ──────────────────────────────────────────────────
## Stare time threshold (seconds) before CHARGE transition.
@export var charge_stare_threshold: float = 1.5

## Flinch duration range (seconds) — randomized lateral sprint.
@export var flinch_duration_min: float = 3.0
@export var flinch_duration_max: float = 5.0

## Flinch distance (meters) — how far the Entity sprints laterally.
@export var flinch_distance: float = 8.0

## Confidence penalty on FLINCH completion.
@export var flinch_confidence_penalty: float = 20.0

## Indoor retreat confidence — what confidence is set to when caught inside.
@export var indoor_retreat_confidence: float = 20.0

## Confidence threshold for APPROACH_WINDOW escalation.
@export var confidence_approach_threshold: float = 40.0

## Confidence boost when player breaks flashlight stare.
@export var stare_break_confidence_boost: float = 8.0

## Confidence drain rate while being stared at (per second).
@export var stare_confidence_drain: float = 2.0

## Stare grace threshold (seconds) — extends anti-flap if stare timer is high.
@export var stare_grace_threshold: float = 0.5

## Anti-flap cooldown duration (seconds) — prevents same-state re-entry.
@export var anti_flap_cooldown_duration: float = 0.5

# ─── STALK BEHAVIOR ──────────────────────────────────────────────────────────
## Minimum distance (meters) the Entity tries to maintain during STALK.
@export var stalk_min_distance: float = 3.0

## Maximum distance (meters) for full-speed pursuit during STALK.
@export var stalk_max_distance: float = 10.0

## Speed multiplier when Entity is between min/max STALK distance.
@export var stalk_close_speed_mult: float = 0.3

## Whether STALK flanking behavior is enabled.
@export var flanking_enabled: bool = true

## Interval (seconds) between flank maneuvers during STALK with LOS.
@export var flank_interval: float = 8.0

## Offset distance (meters) for flanking waypoints.
@export var flank_offset_distance: float = 8.0

# ─── LAMP & FUSE ATTACK ──────────────────────────────────────────────────────
## Lamp attack interval (seconds) between strikes.
@export var lamp_attack_interval: float = 3.0

## Fuse sabotage interval (seconds) between strikes.
@export var fuse_sabotage_interval: float = 2.0

## Fuse sabotage stuck timeout (seconds) before teleport bypass.
@export var fuse_sabotage_stuck_timeout: float = 4.0

# ─── WINDOW PEEK / OBSERVE TIMERS ────────────────────────────────────────────
## Window peek stare timer range (seconds).
@export var window_peek_stare_min: float = 8.0
@export var window_peek_stare_max: float = 15.0

## Observe wait time range for high confidence (>= 40).
@export var observe_wait_high_min: float = 2.0
@export var observe_wait_high_max: float = 4.5

## Observe wait time range for low confidence (< 40).
@export var observe_wait_low_min: float = 4.0
@export var observe_wait_low_max: float = 8.0

# ─── RETREAT ─────────────────────────────────────────────────────────────────
## Retreat teleport distance (meters) outside the breach window.
@export var retreat_teleport_distance: float = 2.0

# ─── UTILITY SCORER PENALTIES ────────────────────────────────────────────────
## Recency penalty for recently visited windows (utility scorer).
@export var window_recency_penalty: float = 30.0

## Room avoidance penalty for lit rooms (utility scorer).
@export var room_avoidance_penalty: float = 500.0

## Maximum number of recently visited windows to track.
@export var max_recent_windows: int = 3