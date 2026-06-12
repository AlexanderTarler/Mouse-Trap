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
@export var flinch_duration: float = 1.5

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
	OBSERVE_FROM_TREELINE,  # Night 1 & 2 (Passive Voyeurism)
	PATROL,                 # Wandering the map looking for clues
	CHASE,                  # Active pursuit (Line of sight established)
	RETREAT,                # Physically running away to deep woods
	APPROACH_WINDOW,        # Night 3+ (Moving to glass)
	WINDOW_PEEK,            # Night 2+ (Staring inside)
	RELOCATE,               # Safe initialization state only — never used during active runtime
	STANDOFF,               # Player is staring at Entity with flashlight — frozen in place
	FLINCH,                 # Player inside, Entity outside — lateral sprint to evade flashlight
	CHARGE,                 # Player stared too long — Entity sprints at 3x speed
	INDOOR_SEARCH,          # Entity has breached a window and is hunting inside the cabin
	CLIMB_WALL,             # Entity is climbing the exterior wall to a second-story window
	STUNNED,                # Entity is paralyzed by the porch light overload trap
	ENRAGED,                # Blackout released Entity — permanent speed boost for the rest of the night
	ATTACK_LAMP,            # Entity is physically approaching and striking the portable high-voltage lamp
	HARASS,                 # Entity stands at a window performing psychological harassment (breathing, tapping, rattling)
	FUSE_SABOTAGE,          # Entity is physically approaching and striking the Fuse Box to break it
}

var entity: CharacterBody3D = null

## The Master Behavior Director — the SINGLE source of truth for state transitions.
## NO script is allowed to call set_state() except this Director.
## External scripts may ONLY write data to the Entity's Blackboard.
var _director: EntityDirector = null

## Preload the Director class for typed access.
const _DirectorClass = preload("entity_director.gd")

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

## Duration of the EnterWindow vault animation in seconds.
## The animation is ~1.5 seconds long. The Entity must play this animation
## for its full duration before teleporting inside, ensuring the visual
## effect of vaulting through the window frame is fully visible.
## NOTE: This is now an @export variable (enter_window_anim_duration).
## The const is kept as a fallback for the initial value.
const ENTER_WINDOW_ANIM_DURATION: float = 1.5

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

# ─── PHASE 3: WINDOW SHOPPING UTILITY SCORER ────────────────────────────────
## Array of recently visited windows (max 3 entries).
## Each entry is the window's NodePath or unique identifier string.
## Used by _score_window() to apply a recency malus (-30.0 penalty).
var _recently_visited_windows: Array[String] = []

## Maximum number of entries in _recently_visited_windows.
const MAX_RECENT_WINDOWS: int = 3

func setup(parent: CharacterBody3D) -> void:
	entity = parent
	
	# Initialize the Master Behavior Director
	_director = _DirectorClass.new()
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
	
	# --- STATE DISPATCHER ---
	# Execute Movement/Physics for the current state.
	# These functions ONLY contain movement, animation, and pathfinding code.
	# ALL transition logic has been moved to the Master Director above.
	match entity.get_state():

		State.DORMANT:
			_calculated_velocity = Vector3.ZERO
		State.OBSERVE_FROM_TREELINE:
			_observe_from_treeline_state(delta)
		State.RETREAT:
			_retreat_state(delta)
		State.APPROACH_WINDOW:
			_approach_window_state(delta)
		State.WINDOW_PEEK:
			_window_peek_state(delta)
		State.CHASE, State.PATROL:
			_stalk_state(delta)
		State.CHARGE:
			_charge_state(delta)
		State.FLINCH:
			_flinch_state(delta)
		State.HARASS:
			_harass_state(delta)
		State.INDOOR_SEARCH:
			_indoor_search_state(delta)
		State.CLIMB_WALL:
			_climb_wall_state(delta)
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
		print("[CHASE] Light switch triggered! Entity is in a lit room. Forcing RETREAT!")
		entity.is_indoor_retreat = true
		entity.state_locked = false
		_calculated_velocity = Vector3.ZERO
		return
	
	# ─── PATHFINDING & MOVEMENT ───────────────────────────────────────
	# Update the navigation path toward the player at the configured interval.
	entity.set_path_timer(entity.get_path_timer() + delta)
	if entity.get_path_timer() >= entity.path_update_interval:
		entity.set_path_timer(0.0)
	# ─── NAV TARGET JITTER ──────────────────────────────────────────────
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
			print("[CHASE] Investigation interrupted! Player spotted. Resuming chase.")
		elif entity.is_hunting() and entity.get_current_interest_level() > 50.0:
			# Player was heard (acoustic detection) during investigation
			_is_investigating = false
			_investigation_timer = 0.0
			print("[CHASE] Investigation interrupted! Player heard. Resuming chase.")
		
		if _investigation_timer <= 0.0:
			# Investigation complete — give up and transition to OBSERVE
			_is_investigating = false
			entity.is_observe_finished = true
			entity.state_locked = false
			_calculated_velocity = Vector3.ZERO
			print("[CHASE] Investigation complete. Player not found. Giving up.")
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
			print("[CHASE] Arrived at last_known_position but player not found. Investigating for 4 seconds...")
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
		entity.set_state(entity.EntityAI.State.FLINCH)
		entity.state_locked = true
		_calculated_velocity = Vector3.ZERO
		print("[INDOOR RETREAT] Phase 2 complete! Teleported outside. Transitioning to FLINCH state.")
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
			# Arrived at window — signal completion to the Director
			# via the Blackboard completion flag. The Director will
			# transition to WINDOW_PEEK (Tier 3).
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
					# ─── IMPACT FRAME: Shatter the glass ────────────────
					_glass_shatter_pending = false
					_glass_shatter_impact_timer = 0.0
					
					# Call shatter_window() to destroy the glass at the
					# exact impact frame of the AttackWindow animation.
					# This triggers _shatter_glass() which sets
					# is_glass_shattered = true, hides PristineVisuals,
					# shows ShatteredVisuals, plays audio, and bursts
					# glass shard particles — all IMMEDIATELY (no deferred
					# timer), so the visual swap is frame-perfect with the
					# animation's impact moment.
					if window_target.has_method("shatter_window"):
						window_target.shatter_window()
						print("[WINDOW_PEEK] Glass shattered at impact frame! Transitioning to INDOOR_SEARCH.")
					
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
			return
		else:
			# Animation still playing — freeze movement
			_calculated_velocity = Vector3.ZERO
			return
	
	# ─── PHASE B: Indoor Patrol ──────────────────────────────────────────
	# Pathfind toward the player's last known position.
	# If the player is in a dark room, actively patrol between waypoints.
	var player = entity.get_player()
	if player:
		# ─── LIGHT SWITCH RETREAT CHECK (every frame) ────────────────────
		# If the Entity is standing in a lit room (player flipped the light
		# switch), it panics and immediately executes the RETREAT state.
		# This check runs EVERY FRAME for instant response — the player
		# flipping a light switch needs immediate reaction, not a 0.3s delay.
		if RoomLightDetector.is_entity_in_lit_room():
			print("[INDOOR_SEARCH] Light switch triggered! Entity is in a lit room. Forcing RETREAT!")
			entity.is_indoor_retreat = true
			entity.state_locked = false
			_calculated_velocity = Vector3.ZERO
			# The Director will pick up the RETREAT state on the next
			# evaluation cycle. We don't call set_state() directly —
			# the Director handles all state transitions.
			return
		
		# ─── DARK ROOM PATROL ─────────────────────────────────────────────
		# If the player is in a dark room (not lit), the Entity cannot track
		# them via last_known_position effectively. Instead of standing still
		# at a single waypoint, actively patrol between Cabin_Patrol_Waypoints.
		# This makes the Entity pace around the cabin looking for the player.
		var player_in_lit_room = false
		if entity.get_navigation_module().has_method("is_player_in_lit_room"):
			player_in_lit_room = entity.get_navigation_module().is_player_in_lit_room()
		
		if not player_in_lit_room and not _is_investigating:
			# Player is in the dark — patrol between waypoints
			if _current_patrol_waypoint == Vector3.ZERO or entity.get_nav_agent().is_navigation_finished():
				# Pick a new random waypoint from the Cabin_Patrol_Waypoints group
				var waypoints: Array[Node] = entity.get_tree().get_nodes_in_group("Cabin_Patrol_Waypoints")
				if not waypoints.is_empty():
					var random_wp: Node3D = waypoints[randi() % waypoints.size()] as Node3D
					if random_wp:
						_current_patrol_waypoint = random_wp.global_position
						entity.get_nav_agent().target_position = _current_patrol_waypoint
						print("[INDOOR_SEARCH] Dark room patrol: New waypoint set to (%.2f, %.2f, %.2f)" % [_current_patrol_waypoint.x, _current_patrol_waypoint.y, _current_patrol_waypoint.z])
				else:
					# Fallback: if no waypoints exist, use last_known_position
					_current_patrol_waypoint = entity.get_last_known_position()
					entity.get_nav_agent().target_position = _current_patrol_waypoint
			
			# Move toward the current patrol waypoint
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
			
			# ─── CATCH CHECK ──────────────────────────────────────────────
			if entity.global_position.distance_to(player.global_position) <= entity.catch_distance:
				entity._on_caught_player()
				return
			
			# ─── UNIVERSAL FRUSTRATION: LIT ROOM BLOCK ─────────────────
			# Even during patrol, accumulate frustration if the player is in
			# a lit room (shouldn't happen here since we checked above, but
			# keep for consistency).
			if entity.get_navigation_module().has_method("is_player_in_lit_room"):
				if player_in_lit_room:
					_all_lit_frustration += ALL_LIT_FRUSTRATION_RATE * delta
					_all_lit_frustration = minf(_all_lit_frustration, ALL_LIT_FRUSTRATION_THRESHOLD)
			return
		
		entity.set_path_timer(entity.get_path_timer() + delta)
		if entity.get_path_timer() >= entity.path_update_interval:
			entity.set_path_timer(0.0)
			
			# ─── INVESTIGATION CONFUSION CHECK ───────────────────────────
			# If the Entity has arrived at the last_known_position and cannot
			# see the player, enter the Investigation sub-state. The Entity
			# stops, plays a searching animation, and waits 4 seconds before
			# giving up and transitioning to OBSERVE_FROM_TREELINE.
			if _is_investigating:
				# Already investigating — count down the timer
				_investigation_timer -= delta
				
				# ─── SEARCHING ANIMATION ─────────────────────────────────
				# Play the searching animation (head turning left/right).
				# The animation state machine handles the visual — we just
				# keep the Entity frozen in place.
				_calculated_velocity = Vector3.ZERO
				
				# ─── CHECK IF PLAYER IS SPOTTED DURING INVESTIGATION ─────
				# If the Entity sees or hears the player during the 4-second
				# investigation window, it immediately resumes the chase.
				var sensory = entity.get_sensory_module()
				if sensory and sensory.has_method("can_entity_see_player") and sensory.can_entity_see_player():
					_is_investigating = false
					_investigation_timer = 0.0
					print("[INDOOR_SEARCH] Investigation interrupted! Player spotted. Resuming chase.")
				elif entity.is_hunting() and entity.get_current_interest_level() > 50.0:
					# Player was heard (acoustic detection) during investigation
					_is_investigating = false
					_investigation_timer = 0.0
					print("[INDOOR_SEARCH] Investigation interrupted! Player heard. Resuming chase.")
				
				if _investigation_timer <= 0.0:
					# ─── INVESTIGATION COMPLETE ──────────────────────────
					# The Entity has searched for 4 seconds and found nothing.
					# Give up and transition to OBSERVE_FROM_TREELINE.
					_is_investigating = false
					entity.is_observe_finished = true
					entity.state_locked = false
					_calculated_velocity = Vector3.ZERO
					print("[INDOOR_SEARCH] Investigation complete. Player not found. Giving up.")
					return
				else:
					# Still investigating — freeze and wait
					return
			
			# ─── CHECK IF WE'VE ARRIVED AT LAST_KNOWN_POSITION ───────────
			var lkp = entity.get_last_known_position()
			var dist_to_lkp = entity.global_position.distance_to(lkp)
			var nav_finished = entity.get_nav_agent().is_navigation_finished()
			
			# If the nav agent finished OR we're close to the last known
			# position, AND we can't see the player, start investigating.
			if (nav_finished or dist_to_lkp <= 3.0) and not _is_investigating:
				# Check if the Entity can actually see the player right now
				var sensory = entity.get_sensory_module()
				var can_see_player = false
				if sensory and sensory.has_method("can_entity_see_player"):
					can_see_player = sensory.can_entity_see_player()
				
				if not can_see_player:
					# ─── START INVESTIGATION ─────────────────────────────
					# The Entity arrived at the last known position but the
					# player is not here. Enter confusion mode: search for
					# 4 seconds, then give up.
					_is_investigating = true
					_investigation_timer = 4.0
					_calculated_velocity = Vector3.ZERO
					print("[INDOOR_SEARCH] Arrived at last_known_position but player not found. Investigating for 4 seconds...")
					return
			
			# ─── STANDARD PATHFINDING ────────────────────────────────────
			# If not investigating, pathfind toward the player normally.
			# Use last_known_position as the target so the Entity doesn't
			# magically track the player's exact current position.
			if not _is_investigating:
				entity.get_nav_agent().target_position = entity.get_last_known_position()
		
		if entity.global_position.distance_to(player.global_position) <= entity.catch_distance:
			entity._on_caught_player()
			return
		
		# ─── UNIVERSAL FRUSTRATION: LIT ROOM BLOCK ─────────────────────
		# If the player is in a lit room and the Entity is inside the cabin
		# (INDOOR_SEARCH), accumulate frustration. The Entity can't reach
		# the player through the light sanctuary, so it gets frustrated.
		# When frustration reaches the threshold, the Director's Tier 1
		# Sabotage will transition to FUSE_SABOTAGE to kill the generator.
		if entity.get_navigation_module().has_method("is_player_in_lit_room"):
			var player_in_lit = entity.get_navigation_module().is_player_in_lit_room()
			if player_in_lit:
				_all_lit_frustration += ALL_LIT_FRUSTRATION_RATE * delta
				_all_lit_frustration = minf(_all_lit_frustration, ALL_LIT_FRUSTRATION_THRESHOLD)
		
		if _is_investigating:
			_calculated_velocity = Vector3.ZERO
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


# ---------------------------------------------------------------------------
# STATE: CLIMB_WALL — Exterior wall climbing to a second-story window
# ---------------------------------------------------------------------------
## Phase 1: Pathfinding to the base of the wall.
## Phase 2: Vertical ascent (Y-axis movement) toward the target window.
func _climb_wall_state(delta: float) -> void:
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
			# When WallBasePosition doesn't exist in the scene tree, the
			# handler skips directly to Phase 2. But if the Entity is already
			# at ground level (Y ≈ 0.0), Phase 2 completes instantly, setting
			# is_climb_finished = true. The Director then transitions to
			# WINDOW_PEEK, which immediately fails (no window), and the
			# Director falls through to OBSERVE_FROM_TREELINE. Next frame:
			# confidence >= 65 → CLIMB again. 60fps oscillation.
			#
			# Fix: Signal completion immediately so the Director transitions
			# to OBSERVE_FROM_TREELINE (Tier 6 default) instead of re-entering
			# CLIMB_WALL.
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
			# via the Blackboard completion flag. The Director will
			# transition to WINDOW_PEEK (Tier 3).
			entity.is_climb_finished = true
			entity.state_locked = false  # Unlock — Director can now transition
			_calculated_velocity = Vector3.ZERO
			_wall_climb_phase_2 = false
			_siege_duration_timer = 0.0
