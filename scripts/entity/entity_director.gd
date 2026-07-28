extends Node
class_name EntityDirector

## THE MASTER BEHAVIOR DIRECTOR
## 
## ARCHITECTURE:
##   This is the SINGLE source of truth for all state transitions.
##   NO script is allowed to call set_state() except this Director.
##   External scripts (Player, sensory, etc.) may ONLY write data to
##   the Entity's Blackboard (entity_controller.gd).
##
##   The Director runs once per frame, evaluates the Blackboard data
##   from top-to-bottom priority, and returns the one true state.
##
## THE GOLDEN RULE:
##   If you need to change the Entity's behavior, modify this file.
##   Do NOT add set_state() calls anywhere else in the codebase.
##
## STATE COMPLETION FLAGS:
##   State handlers in entity_ai.gd set completion flags on the Blackboard
##   (e.g., entity.is_approach_finished = true) instead of calling set_state().
##   The Director checks these flags and transitions accordingly.
##   After consuming a flag, the Director resets it to false.
##
## EVALUATION ORDER:
##   Tier 0: Pending State Override — checked BEFORE state_locked
##   Tier 0: Critical Survival & Reactions (flashlight) — checked BEFORE state_locked
##   Tier 1: Sabotage Override (frustration-based fuse box attack) — checked BEFORE state_locked
##   Tier 2: Night Rules (narrative restrictions)
##   Tier 2: Stare Grace Period (anti-flap extension)
##   Tier 3: Active Aggression (chase, charge, indoor search)
##   Tier 4: Confidence Escalation (window approach, wall climb)
##   Tier 5: State Completion Flags (approach finished, climb finished, etc.)
##   Tier 6: Portable Trap Attraction
##   Tier 7: Confidence Escalation (Fallback for non-passive states)
##   Tier 8: Default Baseline (observe from treeline)

## ─── ANTI-FLAP COOLDOWN ──────────────────────────────────────────────────────
## When a state handler completes (e.g., FLINCH finishes), the Director sets
## this cooldown timer to prevent the Director from immediately re-entering the
## same state on the next frame. This breaks the 60fps oscillation loop where
## the Director forces FLINCH → handler finishes → Director forces FLINCH again.
##
## The cooldown is set to 0.5 seconds after each state completion. During this
## window, the Director will NOT transition into FLINCH (or other locked states)
## even if the Blackboard conditions still match.
var _anti_flap_cooldown: float = 0.0

## The state that was just completed. Used by the anti-flap system to prevent
## immediate re-entry into the same state.
var _last_completed_state: int = -1

## ─── HYSTERESIS TRACKING (H3: Oscillation Prevention) ──────────────────────────
## Tracks the game time (seconds) when the current state was entered.
## Used by the minimum state dwell time guard. Reset to Time.get_ticks_msec()/1000
## when evaluate_master_state() transitions to a different state.
var _state_entry_time: float = 0.0

## Tracks the confidence value at the moment the current state was entered.
## Used by confidence hysteresis: the Entity must drop below
## (threshold - hysteresis_margin) before the Director de-escalates.
## Prevents 60fps state flapping when confidence hovers at threshold boundaries.
var _state_entry_confidence: float = -1.0

## ─── NAVIGATION QUERY CACHE (H4: Performance) ─────────────────────────────────
## Cached result of get_player_room() for the current evaluation frame.
## Refreshed once at the top of evaluate_master_state() and reused across all
## tiers. Eliminates 3 redundant navigation module queries per frame.
var _cached_player_room: String = ""

## Cached result of is_player_lit_by_static_lights() for the current frame.
var _cached_player_lit: bool = false

## Timer for throttling navigation query cache refreshes (seconds).
## Room changes don't happen at 60Hz — 0.5s refresh is more than sufficient.
var _nav_cache_timer: float = 0.0

## Refresh interval for the navigation query cache.
const NAV_CACHE_INTERVAL: float = 0.5

## Cached NightManager reference — resolved once per frame in evaluate_master_state()
## to avoid repeated get_node_or_null("/root/NightManager") lookups across tiers.
## Set at the top of evaluate_master_state() and read by tier methods that need it.
var _cached_night_manager: Node = null

## ─── PERIODIC DEBUG LOG ──────────────────────────────────────────────────────
## Timer that accumulates delta each frame. When it reaches 3.0 seconds, the
## Director prints a comprehensive debug log of all Blackboard data, confidence,
## sensory info, navigation state, and AI internals — mirroring the F3 overlay.
## This provides a persistent console record for post-mortem analysis without
## needing the F3 overlay to be visible.
var _debug_log_timer: float = 0.0

## EntityAI is registered globally via class_name EntityAI in entity_ai.gd.
## No preload needed — reference EntityAI.State.X directly.

## ─── PERFORMANCE: Pre-cached state keys ──────────────────────────────────────
## Avoids EntityAI.State.keys() heap allocation every frame.
## Populated in _ready().
var _state_keys: Array = []

## ─── PERFORMANCE: Debug trace gating ─────────────────────────────────────────
## Set to false in production to eliminate all print() overhead from hot paths.
## GODOT 4 NOTE: Const boolean lets the editor dead-code-eliminate guarded blocks
## when this is set to false, resulting in zero runtime overhead for printing.
const TRACE_DIRECTOR_ENABLED: bool = false

## ─── PERFORMANCE: Director evaluation throttling ─────────────────────────────
## The FSM doesn't need to re-evaluate state decisions 60 times per second.
## 20 Hz (every 3rd physics frame) is more than sufficient for a horror game.
## Threshold: increments every physics frame, evaluate when >= INTERVAL.
var _director_tick_counter: int = 0
const DIRECTOR_TICK_INTERVAL: int = 3  # 20 Hz at 60 fps physics

## Trace print helper. Only formats and outputs when TRACE_DIRECTOR_ENABLED is true.
## Wraps all [TRACE_DIRECTOR] prints so they can be globally disabled.
func _trace(msg: String) -> void:
	if TRACE_DIRECTOR_ENABLED:
		print(msg)

## Pre-cache STATE_KEYS to avoid EntityAI.State.keys() heap allocation.
## Called once at startup. The cached array is used by _state_key(state)
## instead of calling .keys() which allocates a new Array every time.
func _ready() -> void:
	_state_keys = EntityAI.State.keys()

## Returns the human-readable name of a state enum value.
## Uses the pre-cached _state_keys array instead of EntityAI.State.keys()
## which allocates a new Array on every call (heap allocation → GC pressure).
func _state_key(state: int) -> String:
	return _state_keys[state] if state >= 0 and state < _state_keys.size() else "UNKNOWN"
## ─── INDOOR SEARCH PERSISTENCE ───────────────────────────────────────────────
## Timer that forces the Entity to stay in INDOOR_SEARCH for at least 30 seconds
## after breaching a window. This prevents the "Breach → Search → Give Up →
## Breach again" loop by ensuring the Entity commits to a full indoor search
## before it can re-breach.
##
## Set to INDOOR_SEARCH_PERSISTENCE_DURATION (30.0s) when the Entity enters
## INDOOR_SEARCH. Decremented by delta each frame in evaluate_master_state().
## While the timer is active, Tier 8 returns INDOOR_SEARCH instead of
## OBSERVE_FROM_TREELINE.
var _indoor_search_persistence_timer: float = 0.0

## Duration (in seconds) the Entity must stay in INDOOR_SEARCH after breaching.
## NOTE: The controller's indoor patrol timers and fade_and_relocate() logic
## handle the actual 30-second persistence. This const provides the MINIMUM
## hold time — the Director will NOT transition away from INDOOR_SEARCH until
## this timer expires AND the Entity is physically outside the cabin.
const INDOOR_SEARCH_PERSISTENCE_DURATION: float = 10.0

## ─── OUTSIDE CONFIRMATION TIMER ──────────────────────────────────────────────
## When the Entity deduces the player has escaped (thinks_player_is_inside=false),
## this timer counts DOWN from a random value between 5-10 seconds. The Entity
## must remain in OBSERVE_FROM_TREELINE until the timer reaches 0.0, at which
## point it "confirms" the player is truly outside and transitions to SEARCH.
##
## This prevents the Entity from immediately SEARCHing the moment it loses sight
## of the player or the 3-waypoint miss rule fires. The random delay (5-10s)
## gives the player time to actually sneak away before the Entity starts
## actively looking for them.
##
## Reset to a new random value whenever thinks_player_is_inside flips back to
## true (player was heard or sighted indoors again).
var _outside_confirmation_timer: float = 0.0

## ─── NIGHT 2.2 VAN SEQUENCE RESOLVED ──────────────────────────────────────
## When true, the Night 2.2 van sequence has been fully resolved — the player
## successfully entered the cabin (room != "Outside"). Once set, the ENTIRE
## Van Sequence Persistent Lock (Guard A) is permanently bypassed. This
## prevents the STALK↔OBSERVE_FROM_TREELINE ping-pong that occurred when the
## player briefly stepped into the HallRoom but then moved to the Bedroom
## (which also reports "Outside" in some room detectors).
##
## Set to true when Guard A detects player_room != "Outside".
## Remains true for the rest of this game session.
var _night_2_van_sequence_resolved: bool = false

## Whether the confirmation timer has been initialized with a random value.
## Set to false when thinks_player_is_inside flips to false, triggering a new
## random timer value on the next frame. Set to true after initialization.
var _outside_confirmation_initialized: bool = false

## Minimum duration (in seconds) for the outside confirmation timer.
const OUTSIDE_CONFIRMATION_MIN: float = 5.0

## Maximum duration (in seconds) for the outside confirmation timer.
## Extended to 20.0 seconds so the player cannot "hide outside" forever.
## Combined with proximity-based STALK triggers below, this acts as a
## backup: if the player hasn't been detected via proximity within 20s,
## the timer forces the Entity to begin stalking anyway.
const OUTSIDE_CONFIRMATION_MAX: float = 20.0

## Resets the indoor search persistence timer to 30.0 seconds.
## Called by entity_ai.gd when the Entity enters INDOOR_SEARCH state.
func reset_indoor_search_persistence() -> void:
	_indoor_search_persistence_timer = INDOOR_SEARCH_PERSISTENCE_DURATION
	print("[Director] Indoor search persistence timer set to %.1f seconds." % INDOOR_SEARCH_PERSISTENCE_DURATION)


## Resets the outside confirmation timer so the Entity must wait another
## 5-10 seconds in OBSERVE_FROM_TREELINE before re-entering SEARCH.
## Called by entity_ai.gd's _search_state() when SEARCH completes.
## This prevents the Director from immediately returning SEARCH on the
## next frame after SEARCH completes (the timer would be at 0.0 and
## _outside_confirmation_initialized would still be true).
func reset_outside_confirmation() -> void:
	_outside_confirmation_timer = 0.0
	_outside_confirmation_initialized = false
	print("[Director] Outside confirmation timer reset for next SEARCH cycle.")


## Called by entity_ai.gd's process_state_logic() every physics frame to

## accumulate the anti-flap cooldown timer. Decrements the cooldown toward
## 0.0 so that locked states can eventually be re-entered.
func accumulate_anti_flap(delta: float) -> void:
	if _anti_flap_cooldown > 0.0:
		_anti_flap_cooldown -= delta


## Called by entity_ai.gd's process_state_logic() every physics frame to
## accumulate the debug log timer. Prints the full debug dump every 3 seconds.
func accumulate_debug_log(delta: float, entity: CharacterBody3D) -> void:
	_debug_log_timer += delta
	if _debug_log_timer >= 3.0:
		_debug_log_timer = 0.0
		_print_debug_dump(entity)


## Prints a comprehensive debug dump of all Entity behavioral data to the
## console. Mirrors the F3 Entity Debug overlay data for post-mortem analysis.
## Called every 3 seconds by accumulate_debug_log().
func _print_debug_dump(entity: CharacterBody3D) -> void:
	# Debug dump removed to reduce console noise.
	# Use F3 overlay for real-time debug data.
	pass


## Evaluates the Blackboard data and returns the one true state for this frame.
## Called by entity_ai.gd's process_state_logic() every physics frame.
##
## ARCHITECTURE:
##   Each tier is extracted into its own private method for readability and
##   testability. Tiers are evaluated in strict priority order. The first tier
##   that returns a non-null value wins. If all tiers return null, the default
##   baseline (OBSERVE_FROM_TREELINE) is returned.
##
## Parameters:
##   entity: The entity_controller.gd instance (CharacterBody3D)
##
## Returns: EntityAI.State enum value
func evaluate_master_state(entity: CharacterBody3D) -> int:
	var state = entity.get_state()
	
	# ─── CACHE NIGHT MANAGER ──────────────────────────────────────────────
	# Resolve the NightManager once at the top of this function so all tier
	# methods can read _cached_night_manager instead of calling expensive
	# get_node_or_null("/root/NightManager") up to 6 times per frame.
	_cached_night_manager = entity.get_night_manager() if entity.has_method("get_night_manager") else null
	
	# ─── INDOOR SEARCH PERSISTENCE TIMER DECAY ──────────────────────────
	# Decrement the indoor search persistence timer each frame so it counts
	# down from 30.0 to 0.0 while the Entity is in INDOOR_SEARCH.
	# When it reaches 0.0, the preservation guard (after state lock check)
	# no longer applies, allowing the Director to transition to
	# OBSERVE_FROM_TREELINE if appropriate.
	if state == EntityAI.State.INDOOR_SEARCH and _indoor_search_persistence_timer > 0.0:
		_indoor_search_persistence_timer -= entity.get_physics_process_delta_time()
	
	# ─── TIER 0: PENDING STATE OVERRIDE ──────────────────────────────
	# Checked BEFORE state_locked so critical overrides (stun release,
	# blackout enrage, debug) can interrupt locked states.
	var pending = _tier_0_pending_override(entity)
	if pending >= 0:
		if state == EntityAI.State.INDOOR_SEARCH:
			print("[TRACE_DIRECTOR] TIER 0 PENDING OVERRIDE returning %d (interrupting INDOOR_SEARCH!)" % pending)
		return pending
	
	# ─── TIER 0: CRITICAL SURVIVAL & REACTIONS ───────────────────────
	# Checked BEFORE state_locked so flashlight reactions can forcefully
	# interrupt any ongoing task (approach, climb, etc.).
	var flashlight_state = _tier_0_flashlight_reaction(entity, state)
	if flashlight_state >= 0:
		if state == EntityAI.State.INDOOR_SEARCH:
			print("[TRACE_DIRECTOR] TIER 0 FLASHLIGHT returning %d (interrupting INDOOR_SEARCH!)" % flashlight_state)
		return flashlight_state
	
	# ─── TIER 1: SABOTAGE OVERRIDE ──────────────────────────────────
	# Checked BEFORE state_locked so frustration-based fuse box sabotage
	# can interrupt locked states (approach, climb, indoor search, etc.).
	# Sabotage is a psychological override — it must interrupt standard
	# patrol/search behaviors when the Entity is frustrated by lit rooms.
	#
	# When interrupting a locked state, we safely unlock the motor and
	# reset animation flags before transitioning to FUSE_SABOTAGE.
	var sabotage_state = _tier_1_sabotage(entity, state)
	if sabotage_state >= 0:
		if state == EntityAI.State.INDOOR_SEARCH:
			print("[TRACE_DIRECTOR] TIER 1 SABOTAGE returning %d (interrupting INDOOR_SEARCH!)" % sabotage_state)
		return sabotage_state
	
	# ─── BREACH LOCK GUARD ────────────────────────────────────────────
	# After Tier 0 (flashlight reactions) and Tier 1 (sabotage override),
	# check if the Entity is mid-breach (walking through the doorway).
	# When is_breach_locked is true, the Entity is in Door Phase A of
	# INDOOR_SEARCH and MUST NOT be interrupted by sensory-driven state
	# overrides (Tiers 2-8). This prevents the "Sensory Interference" bug
	# where the Entity sees the player outside during Door Phase A and
	# aborts the search.
	#
	# Unlike state_locked (which is set by state handlers for animation
	# locks), is_breach_locked is a HARD lock that prevents ANY tier
	# (including Tier 0 flashlight and Tier 1 sabotage) from overriding
	# the state while the Entity is physically walking through the doorway.
	#
	# The lock is released when:
	#   1. Door Phase A completes (Entity reaches IndoorBreachWaypoint)
	#   2. The 5-second timeout fires (entity_controller.gd force-teleports)
	if entity.is_breach_locked:
		if state == EntityAI.State.INDOOR_SEARCH:
			print("[TRACE_DIRECTOR] BREACH LOCKED! is_breach_locked=true. Returning INDOOR_SEARCH (preserving breach lock).")
		return state
	
	# ─── STALK LOCK GUARD (Night 2.2 Van Sequence) ────────────────────
	# When the Entity is force-spawned at the van (escape_van.gd), a
	# "stalk_lock_until_ms" meta is set for 5 seconds. During this window,
	# the Director MUST NOT transition the Entity to OBSERVE_FROM_TREELINE,
	# RETREAT, or any passive state. The Entity stays locked in STALK to
	# ensure it immediately pursues the player.
	if entity.has_meta("stalk_lock_until_ms"):
		var lock_until = entity.get_meta("stalk_lock_until_ms") as int
		if Time.get_ticks_msec() < lock_until:
			if state == EntityAI.State.CHARGE or state == EntityAI.State.FLINCH:
				return state
			return EntityAI.State.STALK
		else:
			entity.remove_meta("stalk_lock_until_ms")
			print("[TRACE_DIRECTOR] STALK LOCK EXPIRED. Meta removed.")
	
	# ─── VAN SEQUENCE PERSISTENT LOCK (Night 2.2) ──────────────────
	# After the 5-second stalk_lock_until_ms meta expires, the Director's
	# Tier 3 (Active Aggression) transitions STALK→OBSERVE via the outside
	# confirmation timer. This lock runs BEFORE Tier 3 and forces STALK
	# unconditionally while is_van_sequence_active is true.
	#
	# RELEASE CONDITION:
	#   The lock is released when the player enters the cabin (player room
	#   is NOT "Outside"). When released, the Director falls through to
	#   Tier 3 (Active Aggression) which naturally transitions STALK →
	#   APPROACH_WINDOW (if confidence >= 40) or OBSERVE (if < 40).
	#   This allows the Entity to leave STALK and start approaching the
	#   cabin via windows/doors instead of endlessly stalking outside.
	#   Only CHARGE/FLINCH override it while the lock is active.
	#
	# PERMANENT RESOLUTION CHECK:
	#   Once _night_2_van_sequence_resolved is true (player entered the
	#   cabin and the flag was set), the ENTIRE Guard A block is bypassed.
	#   The function falls through to Tier 3, which evaluates the player's
	#   current room and naturally transitions STALK→APPROACH_WINDOW or
	#   STALK→OBSERVE_FROM_TREELINE. Without this bypass, Guard A would
	#   return `state` on every frame, preventing Tier 3 from ever running.
	if _cached_night_manager and _cached_night_manager.is_van_sequence_active and not _night_2_van_sequence_resolved:
		# ─── PLAYER ENTERED CABIN CHECK ──────────────────────────
		# If the player has entered the cabin (room != "Outside"),
		# release the van sequence lock permanently. The Entity can
		# now transition out of STALK naturally via Tier 3.
		#
		# Uses get_player_room() which covers ALL indoor rooms:
		# HallRoom, LivingRoom, ComputerRoom — not just HallRoom.
		var nav = entity.get_navigation_module()
		var player_room: String = "Outside"
		if nav and nav.has_method("get_player_room"):
			player_room = nav.get_player_room()
		if player_room != "Outside":
			# Player is inside the cabin — permanently resolve the
			# van sequence. Set the flag so this block NEVER evaluates
			# again, preventing the Bedroom → "Outside" → re-lock
			# oscillation. Then fall through to Tier 3 by doing nothing
			# (no return) — the function continues to tiers below.
			_night_2_van_sequence_resolved = true
			print("[TRACE_DIRECTOR] NIGHT 2.2 VAN SEQUENCE RESOLVED! Player room='%s'. Lock permanently released. Falling through to Tier 3." % player_room)
			# Do NOT return — fall through to Tier 3+ evaluations below
		else:
			if state != EntityAI.State.STALK and state != EntityAI.State.CHARGE and state != EntityAI.State.FLINCH:
				_trace("[TRACE_DIRECTOR] VAN SEQUENCE PERSISTENT LOCK: Forcing STALK (was %s)." % _state_key(state))
				return EntityAI.State.STALK
			# State is already STALK, CHARGE, or FLINCH — preserve it.
			return state
	
	# ─── STALK CABIN-ENTRY INTERRUPT ─────────────────────────────────
	# If the Entity is STALKing and the player enters the cabin (any room
	# other than "Outside"), forcefully release the STALK lock so the
	# Director can evaluate Tier 3 (Active Aggression) which naturally
	# transitions STALK→APPROACH_WINDOW (if confidence >= 40) or
	# STALK→OBSERVE_FROM_TREELINE (if < 40).
	#
	# This check runs BEFORE the State Lock Guard so it can break an
	# active STALK even if the state handler has set state_locked = true.
	#
	# Uses get_player_room() from entity_navigation.gd which delegates to
	# the player's RoomLightDetector physics overlap checks against
	# Cabin_Interior Area3D volumes. Returns "Outside" or a room name
	# (HallRoom, LivingRoom, ComputerRoom). This covers ALL indoor rooms
	# without hardcoding any specific room name.
	#
	# The van sequence persistent lock (above) has already been checked —
	# if is_van_sequence_active is true, the Director returns STALK
	# unconditionally. By the time we reach this interrupt, the van
	# sequence has either expired or the player has entered the cabin.
	if state == EntityAI.State.STALK:
		var nav_interrupt = entity.get_navigation_module()
		if nav_interrupt and nav_interrupt.has_method("get_player_room"):
			var player_room_interrupt: String = nav_interrupt.get_player_room()
			if player_room_interrupt != "Outside" and not player_room_interrupt.is_empty():
				# Player entered the cabin — release STALK locks and
				# fall through to Tier 3+ evaluations. The Director's
				# Tier 3 STALK handler (lines 1039-1075) will naturally
				# transition to APPROACH_WINDOW or OBSERVE based on
				# confidence.
				entity.state_locked = false
				entity.is_observe_finished = false
				entity.is_flinch_finished = false
				# Fall through — return -1 so Tier 3 evaluates next
	
	# ─── STATE LOCK GUARD ─────────────────────────────────────────────
	# After Tier 0 (flashlight reactions) and Tier 1 (sabotage override),
	# check if the state handler is mid-execution. If locked, return the
	# current state to prevent "State Flapping" where the Director and
	# FSM fight over the state.
	if entity.state_locked:
		if state == EntityAI.State.INDOOR_SEARCH:
			print("[TRACE_DIRECTOR] STATE LOCKED! Returning INDOOR_SEARCH (preserving lock).")
		return state

	
	# ─── INDOOR SEARCH PRESERVATION GUARD ──────────────────────────────
	# If the Entity is currently in INDOOR_SEARCH, do NOT allow Tiers 2-8
	# to override it with outdoor behaviors (OBSERVE_FROM_TREELINE,
	# APPROACH_WINDOW, etc.).
	#
	# This is a HARD LOCK — the Director will NOT transition away from
	# INDOOR_SEARCH under any circumstances (except Tier 0/1 critical
	# overrides checked above, and the breach lock guard above).
	# The Entity stays inside hunting until the _indoor_search_persistence_timer
	# expires (30 seconds).
	#
	# This prevents the infinite loop where the Entity enters the cabin
	# through the door, the Director immediately returns OBSERVE_FROM_TREELINE
	# (because was_door_entry was consumed by the Door Phase A handler), and
	# the Entity re-enters APPROACH_WINDOW → INDOOR_SEARCH → OBSERVE → ...
	#
	# Higher-priority overrides (Tier 0 pending, Tier 0 flashlight, Tier 1
	# sabotage, breach lock guard) are checked ABOVE this guard
	# and can still interrupt.
	if state == EntityAI.State.INDOOR_SEARCH:
		# PERMANENT INDOOR LOCK: Block all transitions away from INDOOR_SEARCH
		# while the Entity is physically inside the cabin. The Entity can ONLY
		# leave via Tier 0 (flashlight → RETREAT) or Tier 1 (frustration →
		# SABOTAGE), which run ABOVE this guard.
		#
		# The persistence timer provides a MINIMUM stay guarantee (10s).
		# is_physically_inside() provides a PERMANENT hold as long as the
		# Entity remains indoors. was_door_entry provides a ONE-FRAME hold
		# while the state handler initializes the persistence timer.
		if _indoor_search_persistence_timer > 0.0:
			return EntityAI.State.INDOOR_SEARCH  # Minimum stay not yet expired
		if entity.has_method("is_physically_inside") and entity.is_physically_inside():
			return EntityAI.State.INDOOR_SEARCH  # Still inside — hold indefinitely
		if entity.was_door_entry:
			# Entity just entered via door breach — hold INDOOR_SEARCH for one
			# frame so the state handler can prime the persistence timer.
			# was_door_entry is consumed by _indoor_search_state() this frame.
			return EntityAI.State.INDOOR_SEARCH  # Door entry in progress
		# Persistence expired AND Entity is outside AND no door entry pending
		# — allow falling through to lower tiers so the Director can transition
		# to an outdoor state (e.g., OBSERVE_FROM_TREELINE).
		pass
	
	# ─── STATE PERSISTENCE GUARD ──────────────────────────────────────
	# If the Entity is in an active state (FLINCH, CHARGE, etc.)
	# and the state timer is still counting down, the Director MUST return
	# the current state and skip Tier 3–8 evaluations. This prevents the
	# Director from overriding a state mid-execution while the animation
	# is still playing.
	#
	# The state timer is set by state handlers on entry (e.g., _flinch_state
	# sets this to 1.5s) and decremented each frame in _physics_process().
	# When it reaches 0.0, the Director is free to re-evaluate.
	if entity.get_state_timer() > 0.0:
		if state == EntityAI.State.INDOOR_SEARCH:
			print("[TRACE_DIRECTOR] STATE PERSISTENCE GUARD: timer=%.3f > 0. Preserving INDOOR_SEARCH." % entity.get_state_timer())
		return state
	
	# ─── TIER 2: NIGHT RULES ─────────────────────────────────────────
	var night_state = _tier_2_night_rules(entity, state)
	if night_state >= 0:
		if state == EntityAI.State.INDOOR_SEARCH:
			print("[TRACE_DIRECTOR] TIER 2 NIGHT RULES returning %d (interrupting INDOOR_SEARCH!)" % night_state)
		return night_state
	
	# ─── ANTI-FLAP COOLDOWN CHECK ────────────────────────────────────
	# If the anti-flap cooldown is active, the Director must NOT transition
	# into FLINCH (or other locked states) even if the Blackboard conditions
	# still match. This prevents the 60fps oscillation loop.
	if _anti_flap_cooldown > 0.0:
		if state == EntityAI.State.INDOOR_SEARCH:
			print("[TRACE_DIRECTOR] ANTI-FLAP COOLDOWN: %.3f > 0. Preserving INDOOR_SEARCH." % _anti_flap_cooldown)
		return state
	
	# ─── STARE GRACE PERIOD ──────────────────────────────────────────
	# Even after the anti-flap cooldown expires, if the stare timer is still
	# high (> 0.5s), the Director extends the cooldown by another 0.5s.
	var stare_grace = _tier_2_stare_grace_period(entity, state)
	if stare_grace >= 0:
		if state == EntityAI.State.INDOOR_SEARCH:
			print("[TRACE_DIRECTOR] TIER 2 STARE GRACE returning %d (interrupting INDOOR_SEARCH!)" % stare_grace)
		return stare_grace
	
	# ─── TIER 3: ACTIVE AGGRESSION ───────────────────────────────────
	var aggression_state = _tier_3_active_aggression(entity, state)
	if aggression_state >= 0:
		if state == EntityAI.State.INDOOR_SEARCH:
			print("[TRACE_DIRECTOR] TIER 3 AGGRESSION returning %d (interrupting INDOOR_SEARCH!)" % aggression_state)
		return aggression_state
	
	# ─── TIER 4: CONFIDENCE ESCALATION (Interrupts passive states) ───
	var confidence_state = _tier_4_confidence_escalation(entity, state)
	if confidence_state >= 0:
		if state == EntityAI.State.INDOOR_SEARCH:
			print("[TRACE_DIRECTOR] TIER 4 CONFIDENCE returning %d (interrupting INDOOR_SEARCH!)" % confidence_state)
		return confidence_state
	
	# ─── TIER 5: STATE COMPLETION FLAGS ──────────────────────────────
	var completion_state = _tier_5_completion_flags(entity, state)
	if completion_state >= 0:
		if state == EntityAI.State.INDOOR_SEARCH:
			print("[TRACE_DIRECTOR] TIER 5 COMPLETION returning %d (interrupting INDOOR_SEARCH!)" % completion_state)
		return completion_state
	
	# ─── TIER 6: PORTABLE TRAP ATTRACTION ────────────────────────────
	var trap_state = _tier_6_trap_attraction(entity)
	if trap_state >= 0:
		if state == EntityAI.State.INDOOR_SEARCH:
			print("[TRACE_DIRECTOR] TIER 6 TRAP returning %d (interrupting INDOOR_SEARCH!)" % trap_state)
		return trap_state
	
	# ─── TIER 7: CONFIDENCE ESCALATION (Fallback for non-passive states)
	var fallback_state = _tier_7_fallback_confidence(entity)
	if fallback_state >= 0:
		if state == EntityAI.State.INDOOR_SEARCH:
			print("[TRACE_DIRECTOR] TIER 7 FALLBACK returning %d (interrupting INDOOR_SEARCH!)" % fallback_state)
		return fallback_state
	
	# ─── TIER 8: DEFAULT BASELINE ────────────────────────────────────
	# ─── INDOOR SEARCH PERSISTENCE ──────────────────────────────────────
	# If the Entity has breached a window (last_breached_window is not null)
	# OR entered through the door (was_door_entry is true), and is currently
	# in INDOOR_SEARCH, force it to stay in INDOOR_SEARCH for at least 30
	# seconds regardless of whether it has found the player.
	# This prevents the "Breach → Search → Give Up → Breach again" loop.
	#
	# The 30-second timer is tracked via the _indoor_search_persistence_timer.
	# It is reset to 30.0 when the Entity enters INDOOR_SEARCH and decremented
	# each frame. While the timer is active, the Director returns INDOOR_SEARCH
	# as the default baseline instead of OBSERVE_FROM_TREELINE.
	#
	# NOTE: was_door_entry is consumed (set to false) by the Ghost Breach block
	# in entity_ai.gd before the Director evaluates. So we also check
	# last_door_breach_time as an alternative trigger — if the Entity has
	# breached the door within the last 30 seconds, it should stay inside.
	var _door_breach_recently: bool = false
	var _current_time = Time.get_ticks_msec() / 1000.0
	var _time_since_door_breach = _current_time - entity.last_door_breach_time
	if _time_since_door_breach < 30.0:
		_door_breach_recently = true
	
	if state == EntityAI.State.INDOOR_SEARCH and (entity.last_breached_window != null or entity.was_door_entry or _door_breach_recently or (entity.has_method("is_physically_inside") and entity.is_physically_inside())):
		# If any hold condition is met, ALWAYS return INDOOR_SEARCH — no timeout.
		# The persistence timer is handled by the INDOOR_SEARCH preservation
		# guard above, so this check is purely a safety net.
		if (entity.has_method("is_physically_inside") and entity.is_physically_inside()) or _indoor_search_persistence_timer > 0.0 or entity.was_door_entry:
			print("[TRACE_DIRECTOR] TIER 8 BASELINE: INDOOR_SEARCH (entity physically inside). Keeping INDOOR_SEARCH.")
			return EntityAI.State.INDOOR_SEARCH
	
	_trace("[TRACE_DIRECTOR] TIER 8 BASELINE: Returning OBSERVE_FROM_TREELINE (state=%s, persistence=%.1f)" % [_state_key(state), _indoor_search_persistence_timer])
	return EntityAI.State.OBSERVE_FROM_TREELINE


# ═══════════════════════════════════════════════════════════════════════════════
# TIER 0: PENDING STATE OVERRIDE
# ═══════════════════════════════════════════════════════════════════════════════
## Checks if an external event (stun, blackout, debug, activation) has
## requested a state change via request_state(). If so, applies it immediately
## and clears the flag.
##
## This is the ONLY mechanism by which external events can force a state
## change. It is checked BEFORE the state_locked guard so that critical
## overrides (like stun release or blackout enrage) can interrupt locked
## states.
##
## Returns: The pending state value, or -1 if no override is pending.
func _tier_0_pending_override(entity: CharacterBody3D) -> int:
	var pending = entity.get_pending_state()
	if pending >= 0:
		entity.clear_pending_state()
		return pending
	return -1


# ═══════════════════════════════════════════════════════════════════════════════
# TIER 0: CRITICAL SURVIVAL & REACTIONS (Flashlight + Light Switch)
# ═══════════════════════════════════════════════════════════════════════════════
## Applies the flashlight-confirmed confidence penalty (-15.0) to the Entity.
## Called by _tier_0_flashlight_reaction() when transitioning to FLINCH.
## The penalty is applied only once per FLINCH transition, gated by
## _last_completed_state != FLINCH. This prevents the penalty from
## stacking every frame while is_illuminated is true.
func _apply_flinch_confidence_penalty(entity: CharacterBody3D) -> void:
	if _last_completed_state != EntityAI.State.FLINCH:
		var confidence_module = entity.get_confidence_module()
		if confidence_module:
			var current_conf = confidence_module.get_confidence()
			var new_conf = maxf(0.0, current_conf - 15.0)
			confidence_module.set_confidence(new_conf)
			print("[Director] FLINCH confidence penalty applied: %.1f → %.1f (Δ-15.0)" % [current_conf, new_conf])

## Captures the current window target's ID to the flinch blacklist.
## Called by _tier_0_flashlight_reaction() when transitioning to FLINCH
## from APPROACH_WINDOW or WINDOW_PEEK. This prevents the Entity from
## re-selecting the same window on the next approach cycle (Correction 3).
func _capture_flinch_window_id(entity: CharacterBody3D) -> void:
	var window_target = entity.get_current_window_target()
	if window_target and entity.has_method("add_flinch_blacklisted_window"):
		var window_id: String = ""
		if window_target.has_method("get_window_id"):
			window_id = window_target.get_window_id()
		elif "window_id" in window_target:
			window_id = str(window_target.window_id)
		
		if not window_id.is_empty():
			entity.add_flinch_blacklisted_window(window_id)

## Evaluates flashlight-based reactions AND light-switch indoor retreat.
## These are checked BEFORE the state_locked guard so that reactions can
## forcefully interrupt any ongoing task (approach, climb, etc.).
##
## LIGHT SWITCH RETREAT (is_indoor_retreat):
##   When the Entity is inside the cabin (INDOOR_SEARCH) and a room light
##   is turned on, entity_ai.gd's _indoor_search_state() sets the
##   is_indoor_retreat flag on the Blackboard. This tier detects that flag
##   and transitions to RETREAT — even if the flashlight is NOT shining.
##   This handles the "Entity will not enter a lit room" and "Entity inside
##   a room that gets its light turned on → RETREAT" rules from the design doc.
##
## FLASHLIGHT REACTIONS:
##   If the Entity is illuminated, we break any existing locks and react
##   immediately.
##
## EXCEPTION: FLINCH state lock is preserved. When the Entity has just escaped
## from an indoor retreat (teleported outside through the breach window), the
## indoor retreat handler sets the state to FLINCH and locks it. The FLINCH
## handler must be allowed to complete its lateral sprint before the Director
## re-evaluates.
##
## CRITICAL RULE — CHARGE IGNORES FLASHLIGHT:
##   If the Entity is in the CHARGE state (outdoor aggression), it has already
##   committed to the attack. The flashlight should NOT interrupt a charge.
##   The Entity is sprinting at 3x speed and will not flinch away.
##
## FLINCH vs RETREAT LOGIC:
##   - RETREAT (indoor escape): Only allowed if the Entity is in an "Aggression"
##     state (WINDOW_PEEK, INDOOR_SEARCH, CHASE). The Entity is inside or at a
##     window and must escape back outside.
##   - FLINCH (escape from cabin): Only allowed if the Entity is in APPROACH_WINDOW
##     (approaching a window from outside). The Entity sprints AWAY from the cabin.
##   - STANDOFF (freeze): Default reaction when the Entity is outside and the
##     player is staring with the flashlight.
##
## CORRECTION 2: Every FLINCH transition from a flashlight trigger applies a
##   -15.0 confidence penalty. This damages the Entity's confidence as a root-
##   cause fix for the "flinch → re-approach → flinch" ping-pong loop.
##
## Returns: The target state, or -1 if no flashlight reaction applies.
func _tier_0_flashlight_reaction(entity: CharacterBody3D, state: int) -> int:
	# ─── LIT ROOM REACTIVE EXIT (APPROACH_WINDOW / WINDOW_PEEK) ─────
	# If the Entity is approaching or peeking a window, and that window's
	# room becomes lit (player turned on the light), immediately FLINCH.
	# This prevents the Entity from standing at a window that just got lit up.
	if (state == EntityAI.State.APPROACH_WINDOW or state == EntityAI.State.WINDOW_PEEK) and not entity.is_illuminated:
		var window_target = entity.get_current_window_target()
		if window_target:
			var nav = entity.get_navigation_module()
			if nav and nav.has_method("is_position_in_lit_room") and nav.is_position_in_lit_room(window_target.global_position):
				# Reset locks and flags
				entity.state_locked = false
				entity.is_approach_finished = false
				entity.is_window_unbarricaded = false
				entity.is_observe_finished = false
				entity.is_flinch_finished = false
				# Capture the window ID to the flinch blacklist (Correction 3)
				_capture_flinch_window_id(entity)
				# Apply confidence penalty (Correction 2)
				_apply_flinch_confidence_penalty(entity)
				# Clear window target so we don't re-select the same lit window
				entity.set_current_window_target(null)
				print("[Director] LIT ROOM REACTIVE EXIT: Window room became lit during %s! Flinching away." % _state_key(state))
				return EntityAI.State.FLINCH
	
	# ─── LIGHT SWITCH RETREAT (is_indoor_retreat) ──────────────────────
	# Checked BEFORE is_illuminated so that a light switch flip triggers
	# RETREAT even if the flashlight is not currently shining on the Entity.
	# The is_indoor_retreat flag is set by entity_ai.gd's _indoor_search_state()
	# when RoomLightDetector.is_entity_in_lit_room() returns true.
	#
	# This handles two design doc rules:
	#   1. "The Entity will not enter a room that has a cabin light turned on."
	#   2. "If the Entity is inside a room that gets its cabin light turned on,
	#      it goes into RETREAT state."
	if entity.is_indoor_retreat:
		# Forcefully break any existing task locks so we can react
		entity.state_locked = false
		entity.is_approach_finished = false
		entity.is_climb_finished = false
		entity.is_flinch_finished = false
		entity.is_retreat_arrived = false
		entity.is_window_unbarricaded = false
		entity.is_observe_finished = false
		
		# Drop confidence to 20% — the Entity is spooked by being caught inside
		var confidence_module = entity.get_confidence_module()
		if confidence_module:
			confidence_module.set_confidence(20.0)
		
		return EntityAI.State.RETREAT
	
	if not entity.is_illuminated:
		return -1
	
	# ─── FLINCH STATE LOCK PRESERVATION ──────────────────────────────
	# If the Entity is already in FLINCH and state_locked is true, the
	# indoor retreat handler just set this state. Preserve the lock so
	# the FLINCH handler can complete its escape sprint.
	if state == EntityAI.State.FLINCH and entity.state_locked:
		return EntityAI.State.FLINCH
	
	# ─── CHARGE IGNORES FLASHLIGHT ──────────────────────────────────
	# The Entity has committed to a charge attack. It will NOT flinch,
	# retreat, or standoff. The flashlight has no effect on a charging
	# Entity — it continues sprinting at 3x speed toward the player.
	if state == EntityAI.State.CHARGE:
		return EntityAI.State.CHARGE
	
	# Forcefully break any existing task locks so we can react
	entity.state_locked = false
	entity.is_approach_finished = false
	entity.is_climb_finished = false
	entity.is_flinch_finished = false
	entity.is_retreat_arrived = false
	entity.is_window_unbarricaded = false
	entity.is_observe_finished = false
	
	# ═══════════════════════════════════════════════════════════════════════
	# ANTI-FLAP GUARD (Bug 1 Fix)
	# ═══════════════════════════════════════════════════════════════════════
	# Before any flashlight-triggered FLINCH, check the anti-flap cooldown.
	# If the cooldown is still active (last FLINCH completed < 0.5s ago),
	# do NOT force FLINCH again — prevent 60fps FLINCH→OBSERVE→FLINCH cycling.
	# This guard is checked BEFORE the ground truth override so that even
	# the definitive trigger respects the cooldown.
	if entity.is_illuminated and _anti_flap_cooldown > 0.0:
		# The Entity is lit but the anti-flap cooldown is active. Do NOT
		# force FLINCH. Fall through to the normal tiers below so the
		# Director can evaluate other state transitions (STANDOFF, etc.).
		# Also do not return -1 here — we need the standard light-based
		# reaction logic to still apply (e.g., STANDOFF for outdoor stare).
		pass
	else:
		# ═══════════════════════════════════════════════════════════════════════
		# GROUND TRUTH FLASHLIGHT OVERRIDE
		# ═══════════════════════════════════════════════════════════════════════
		# Uses the NAVIGATION MODULE's get_player_room() as ground truth,
		# NOT the belief system (thinks_player_is_inside). This prevents the
		# "flashlight bypass" where the Entity registers the light but refuses
		# to enter FLINCH because its belief system hasn't caught up with the
		# player re-entering the cabin.
		#
		# RULE: If the Entity is illuminated by the flashlight AND the player
		# is ACTUALLY inside the cabin (ground truth), the Entity MUST flinch
		# regardless of its belief state. This check runs BEFORE the belief-
		# system gates below so it cannot be bypassed by stale beliefs.
		#
		# EXCEPTIONS:
		#   - FLINCH state lock: Preserve if already flinching
		#   - CHARGE: Flashlight has no effect on a charging Entity
		#   - INDOOR_SEARCH: Handled by RETREAT path below
		if entity.is_illuminated and state != EntityAI.State.FLINCH and state != EntityAI.State.CHARGE and state != EntityAI.State.INDOOR_SEARCH:
			# Query ground truth player room from navigation module
			var nav_gt = entity.get_navigation_module()
			var player_room_gt: String = "Outside"
			if nav_gt and nav_gt.has_method("get_player_room"):
				player_room_gt = nav_gt.get_player_room()
			
			# Ground truth: player is actually inside the cabin
			if player_room_gt != "Outside" and not player_room_gt.is_empty():
				# Forcefully break locks and FLINCH
				entity.state_locked = false
				entity.is_approach_finished = false
				entity.is_climb_finished = false
				entity.is_flinch_finished = false
				entity.is_retreat_arrived = false
				entity.is_window_unbarricaded = false
				entity.is_observe_finished = false
				entity.is_indoor_retreat = false
				
				# Capture window target to blacklist if applicable
				if state == EntityAI.State.WINDOW_PEEK or state == EntityAI.State.APPROACH_WINDOW:
					_capture_flinch_window_id(entity)
				
				# Apply -15.0 confidence penalty (Correction 2)
				_apply_flinch_confidence_penalty(entity)
				
				print("[Director] GROUND TRUTH FLINCH: Player is ACTUALLY inside (room='%s')! Forcing FLINCH from state %s." % [player_room_gt, _state_key(state)])
				return EntityAI.State.FLINCH
	
	# ─── SAFELY CHECK PLAYER LOCATION (BELIEF SYSTEM) ──────────────
	# The Director also checks the Entity's belief about the player's
	# location. This is a SECONDARY check — the ground truth override
	# above has already handled the "stale belief" case.
	var is_player_inside = entity.get_thinks_player_is_inside() if entity.has_method("get_thinks_player_is_inside") else false
	
	# ─── INDOOR AGGRESSION STATE → RETREAT (Player inside, Entity inside) ──

	# If the Entity is inside the cabin (INDOOR_SEARCH) and the player shines
	# the flashlight, the Entity must RETREAT — run to the nearest
	# broken/unboarded window, leave through it, then FLINCH.
	# CHASE is NOT included here — CHASE is outdoor pursuit, not indoor.
	if state == EntityAI.State.INDOOR_SEARCH:
		# Set the indoor retreat flag so the RETREAT handler knows to
		# pathfind to the breach window instead of the farthest treeline.
		entity.is_indoor_retreat = true
		
		# Drop confidence to 20% — the Entity is spooked by being caught inside
		var confidence_module = entity.get_confidence_module()
		if confidence_module:
			confidence_module.set_confidence(20.0)
		
		return EntityAI.State.RETREAT

	# ─── WINDOW PEEK → FLINCH (Player inside, Entity outside at window) ──
	# The Entity is standing outside a window, peering in. When the player
	# shines the flashlight at it through the window, the Entity should flinch
	# (sprint away from the cabin). The Entity loses 15% confidence and sprints
	# away for 5.0 seconds to evade the flashlight beam.
	if state == EntityAI.State.WINDOW_PEEK:
		entity.is_indoor_retreat = false  # Entity is outside, NOT retreating
		entity.is_observe_finished = false  # Cancel any in-progress observation
		
		# Capture the window ID to the flinch blacklist (Correction 3)
		_capture_flinch_window_id(entity)
		# Apply -15.0 confidence penalty (Correction 2)
		_apply_flinch_confidence_penalty(entity)
		
		return EntityAI.State.FLINCH
	
	# ─── APPROACH WINDOW → FLINCH ───────────────────────────────────
	# The Entity is approaching a window from outside. The flashlight
	# causes it to sprint away from the cabin to evade the beam.
	if state == EntityAI.State.APPROACH_WINDOW:
		# Capture the window ID to the flinch blacklist (Correction 3)
		_capture_flinch_window_id(entity)
		# Apply -15.0 confidence penalty (Correction 2)
		_apply_flinch_confidence_penalty(entity)
		return EntityAI.State.FLINCH
	
	# ─── PLAYER INSIDE, ENTITY OUTSIDE → FLINCH ─────────────────────
	# If the player is inside the cabin and shines the flashlight at the
	# Entity (which is outside), the Entity loses 15% confidence and goes
	# into FLINCH state — it sprints away from the cabin for 5.0 seconds.
	#
	# ONE-SHOT GUARD: The confidence penalty is applied once per FLINCH
	# transition. We use _apply_flinch_confidence_penalty() which checks
	# _last_completed_state != FLINCH to prevent double-application.
	if is_player_inside:
		# Apply -15.0 confidence penalty (Correction 2)
		_apply_flinch_confidence_penalty(entity)
		
		return EntityAI.State.FLINCH
	
	# ─── OUTDOOR STARE → STANDOFF or CHARGE ─────────────────────────
	var stare_time = entity.player_stare_timer
	if stare_time >= 1.5:
		# Player stared too long while outside — CHARGE at 3x speed
		return EntityAI.State.CHARGE
	
	# Player is outside staring — STANDOFF (frozen in place, stunned)
	# the flashlight. If the player stops shining, this immobility ends.
	# When stare_time reaches 1.5s, the Entity enters CHARGE state above.
	return EntityAI.State.STANDOFF



# ═══════════════════════════════════════════════════════════════════════════════
# TIER 1: SABOTAGE OVERRIDE (Door-prerequisite + Frustration-based)
# ═══════════════════════════════════════════════════════════════════════════════
## Evaluates whether the Entity should sabotage the Fuse Box. Two triggers:
##
##   1. DOOR PREREQUISITE (SABOTAGE_FUSE): If the Entity is in APPROACH_WINDOW
##      AND the current target is a door AND the Fuse Box is powered (generator
##      ON → porch light ON), the Entity must sabotage the Fuse Box FIRST before
##      it can approach the door. This prevents the Entity from approaching the
##      front door while the porch light is on.
##
##   2. FRUSTRATION-BASED (FUSE_SABOTAGE): When the Entity has been frustrated
##      by all windows being lit for too long (frustration >= 90.0), it abandons
##      window approach and goes straight to sabotaging the Fuse Box.
##
## This tier is checked BEFORE the state_locked guard so that sabotage can
## interrupt locked states (approach, climb, indoor search, etc.).
## When interrupting a locked state, we safely unlock the motor and reset
## animation flags before transitioning.
##
## Returns: The target state, or -1 if no sabotage override applies.
func _tier_1_sabotage(entity: CharacterBody3D, state: int) -> int:
	# ─── DOOR PREREQUISITE: Porch Light Gate ──────────────────────────
	# If the Entity is in APPROACH_WINDOW AND the current target is a door
	# AND the Fuse Box is powered (generator ON → porch light ON), the
	# Entity must sabotage the Fuse Box FIRST before it can approach the door.
	#
	# This prevents the Entity from approaching the front door while the
	# porch light is on. The Entity must destroy the fuse box (killing the
	# generator and all lights including the porch light) before it can
	# safely approach the door.
	#
	# We check this BEFORE the frustration check so the door-prerequisite
	# gate takes priority over frustration-based sabotage.
	if state == EntityAI.State.APPROACH_WINDOW:
		var window_target = entity.get_current_window_target()
		if window_target:
			# ─── DOOR DETECTION: Use cached @export door_waypoint_marker ─────
			# This replaces the expensive per-frame duck-typing checks
			# (has_method("is_in_group"), "is_open" in window_target, etc.)
			# that were called every frame during APPROACH_WINDOW.
			# The cached reference is resolved once in entity_controller.gd's
			# _initialize_entity() and stored as an @export variable.
			var is_door_target: bool = false
			var cached_door_wp = entity.get_door_waypoint_marker()
			if cached_door_wp and window_target == cached_door_wp:
				is_door_target = true
			elif cached_door_wp and window_target.get_parent() == cached_door_wp.get_parent():
				is_door_target = true
			
			if is_door_target:
				# Check if the Fuse Box is powered (generator ON → porch light ON)
				var fuse_box = entity.get_fuse_box_node()
				if fuse_box and fuse_box.has_method("is_powered") and fuse_box.is_powered():
					print("[Director] TIER 1 SABOTAGE: Door target detected but Fuse Box is powered! Interrupting APPROACH_WINDOW to sabotage Fuse Box first.")
					
					# Reset all completion flags to prevent stale state
					entity.state_locked = false
					entity.is_approach_finished = false
					entity.is_climb_finished = false
					entity.is_flinch_finished = false
					entity.is_retreat_arrived = false
					entity.is_window_unbarricaded = false
					entity.is_observe_finished = false
					entity.is_indoor_retreat = false
					
					# Reset AI-specific state flags
					var ai = entity.get_ai_module()
					if ai and ai.has_method("reset_retreat_target"):
						ai.reset_retreat_target()
					
					return EntityAI.State.SABOTAGE_FUSE
	
	# ─── UNIVERSAL FRUSTRATION CHECK ──────────────────────────────────
	# Read frustration directly from the AI module. This works regardless
	# of the current state — frustration accumulates in OBSERVE_FROM_TREELINE
	# (all windows lit), INDOOR_SEARCH (player in lit room), and CHASE
	# (player in lit room).
	var ai = entity.get_ai_module()
	if not ai or not ai.has_method("get_all_lit_frustration"):
		return -1
	
	var frustration = ai.get_all_lit_frustration()
	var threshold = ai.get_frustration_threshold() if ai.has_method("get_frustration_threshold") else 90.0
	
	if frustration < threshold:
		return -1
	
	# ─── FRUSTRATION THRESHOLD REACHED ────────────────────────────────
	# The Entity is frustrated enough to sabotage the Fuse Box.
	# Safely unlock the motor and reset animation flags before transitioning.
	print("[Director] TIER 1 SABOTAGE: Frustration=%.1f >= %.1f! Interrupting state %d to sabotage Fuse Box." % [frustration, threshold, state])
	
	# Reset all completion flags to prevent stale state
	entity.state_locked = false
	entity.is_approach_finished = false
	entity.is_climb_finished = false
	entity.is_flinch_finished = false
	entity.is_retreat_arrived = false
	entity.is_window_unbarricaded = false
	entity.is_observe_finished = false
	entity.is_indoor_retreat = false
	
	# Reset AI-specific state flags
	if ai.has_method("reset_retreat_target"):
		ai.reset_retreat_target()
	
	return EntityAI.State.FUSE_SABOTAGE


# ═══════════════════════════════════════════════════════════════════════════════
# TIER 2: NIGHT RULES (Narrative Restrictions)
# ═══════════════════════════════════════════════════════════════════════════════
## Enforces narrative night restrictions.
## Night 1: Entity can only observe from treeline (no window approach).
## Night 2: Entity can approach windows and peek inside, but can ONLY breach
##   if the window is NOT boarded up.
##
## Returns: The target state, or -1 if no night rule applies.
func _tier_2_night_rules(entity: CharacterBody3D, state: int) -> int:
	# Use the cached NightManager reference (set at the top of evaluate_master_state).
	var current_night: int = _cached_night_manager.current_night if _cached_night_manager else 1
	
	# ─── VAN SEQUENCE NARRATIVE OVERRIDE ──────────────────────────
	# During the Night 2.2 van sequence (car alarm → player investigates),
	# the Entity MUST stay in STALK mode. It cannot observe, retreat, or
	# enter any passive state. This is a hard narrative gate — the Entity
	# is actively hunting the player at the van.
	#
	# PERMANENT RESOLUTION CHECK:
	# If the van sequence has been resolved (player entered the cabin),
	# skip this override entirely. The _night_2_van_sequence_resolved flag
	# was set by Guard A when the player's room was not "Outside".
	if _cached_night_manager and _cached_night_manager.is_van_sequence_active:
		if not _night_2_van_sequence_resolved:
			if state != EntityAI.State.STALK and state != EntityAI.State.CHARGE and state != EntityAI.State.FLINCH:
				_trace("[TRACE_DIRECTOR] TIER 2 NIGHT RULES: Van sequence active. Forcing STALK (was %s)." % _state_key(state))
				return EntityAI.State.STALK
	
	# ─── NIGHT 1 RESTRICTION ─────────────────────────────────────
	# Night 1: Entity can only observe from treeline (no aggressive states).
	# IMPORTANT: DORMANT is the daytime/despawned state — we MUST allow it
	# so the Entity can be hidden during the day. Without this exemption,
	# the Night 1 check would force the Entity out of DORMANT into
	# OBSERVE_FROM_TREELINE every frame, creating a 60fps DORMANT↔OBSERVE loop.
	# The DORMANT state is also used when the Entity is intentionally hidden
	# (e.g., Night 1 car alarm narrative, daytime hours).
	if current_night == 1:
		if state != EntityAI.State.DORMANT and state != EntityAI.State.OBSERVE_FROM_TREELINE and state != EntityAI.State.RETREAT:
			return EntityAI.State.OBSERVE_FROM_TREELINE
	
	# Night 2: Allow APPROACH_WINDOW and WINDOW_PEEK — the state handler will
	# enforce the "no boarded windows" rule at the barricade level.
	# Night 3+: Full aggression unlocked (no restrictions)
	
	return -1


# ═══════════════════════════════════════════════════════════════════════════════
# TIER 2: STARE GRACE PERIOD (Anti-Flap Extension)
# ═══════════════════════════════════════════════════════════════════════════════
## Even after the anti-flap cooldown expires, if the stare timer is still
## high (> 0.5s), the Director extends the cooldown by another 0.5s.
## This prevents the FLINCH loop from restarting while the player is still
## actively shining the flashlight on the Entity.
##
## Returns: The current state (to skip further evaluation), or -1 if no
##          grace period is needed.
func _tier_2_stare_grace_period(entity: CharacterBody3D, state: int) -> int:
	var stare_time = entity.player_stare_timer
	if stare_time > 0.5 and _last_completed_state == EntityAI.State.FLINCH:
		_anti_flap_cooldown = 0.5
		return state
	return -1


# ═══════════════════════════════════════════════════════════════════════════════
# TIER 3: ACTIVE AGGRESSION
# ═══════════════════════════════════════════════════════════════════════════════
## Preserves active pursuit states — don't interrupt mid-action.
## Also handles line-of-sight → CHASE transitions from passive states.
##
## Returns: The target state, or -1 if no aggression rule applies.
func _tier_3_active_aggression(entity: CharacterBody3D, state: int) -> int:
	# ─── GROUND TRUTH: Player Room Detection ───────────────────────
	# The definitive source of truth for whether the player is inside or outside.
	# Uses entity_navigation.gd's get_player_room() which delegates to
	# player_controller.gd's overlaps_body() detection against Cabin_Interior
	# Area3D volumes. This is the most reliable method — it uses actual physics
	# overlap checks rather than position-based heuristics.
	#
	# If the navigation module's get_player_room() returns "Outside", the player
	# is truly outside. Any other room name means the player is inside the cabin.
	#
	# This is used as the definitive gate for ALL STALK transitions. The Entity
	# can ONLY enter STALK if the player's actual room is "Outside".
	var nav = entity.get_navigation_module()
	var player_room: String = "Outside"
	if nav and nav.has_method("get_player_room"):
		player_room = nav.get_player_room()
	var is_player_actually_outside: bool = (player_room == "Outside")
	
	# ─── BELIEF SYSTEM SYNC ──────────────────────────────────────────
	# Keep the Entity's belief system (thinks_player_is_inside) in sync with
	# the ground truth. If the player's actual room is not "Outside", the
	# Entity should believe the player is inside — regardless of what the
	# acoustic detection or 3-waypoint miss rule says.
	#
	# This prevents the "stale belief" bug where the Entity hears the player
	# outside (setting thinks_player_is_inside=false), the player goes back
	# inside, but the belief system never flips back because the indoor noise
	# position is incorrectly classified as "Outside" by RoomLightDetector.
	if is_player_actually_outside:
		entity.set_thinks_player_is_inside(false)
	else:
		entity.set_thinks_player_is_inside(true)
	
	# ─── PROXIMITY-BASED STALK TRIGGER (OBSERVE_FROM_TREELINE) ─────
	# If the Entity is in OBSERVE_FROM_TREELINE and the player is outside,
	# check distance. The Entity will immediately STALK if the player gets
	# too close, bypassing the outside confirmation timer.
	#
	# RULES:
	#   - Standing player within 15m → STALK (Entity detects them)
	#   - Crouching player within 5m → STALK (harder to detect, but still possible)
	#   - Crouching player beyond 5m → stay in OBSERVE (player is hidden)
	#
	# This prevents the player from standing 2 meters from the Entity
	# without consequence while the confirmation timer ticks down.
	if state == EntityAI.State.OBSERVE_FROM_TREELINE and is_player_actually_outside:
		var player = entity.get_player()
		if player:
			var dist = entity.global_position.distance_to(player.global_position)
			var is_crouching = player.has_method("is_crouching") and player.is_crouching()
			
			if is_crouching and dist <= 5.0:
				print("[Director] PROXIMITY STALK: Crouching player within %.1fm (threshold 5.0m)! Immediate STALK." % dist)
				return EntityAI.State.STALK
			elif not is_crouching and dist <= 15.0:
				print("[Director] PROXIMITY STALK: Standing player within %.1fm (threshold 15.0m)! Immediate STALK." % dist)
				return EntityAI.State.STALK
	
	# ─── OUTSIDE CONFIRMATION TIMER MANAGEMENT ──────────────────────
	# When the player is actually outside (ground truth), a random timer
	# (5-20 seconds) starts counting DOWN. The Entity must remain in
	# OBSERVE_FROM_TREELINE until the timer reaches 0.0, at which point
	# it "confirms" the player is truly outside and transitions to STALK.
	#
	# If the player is inside, reset the timer to 0.0 and clear the
	# initialized flag.
	if not is_player_actually_outside:
		if _outside_confirmation_timer > 0.0 or _outside_confirmation_initialized:
			_outside_confirmation_timer = 0.0
			_outside_confirmation_initialized = false
			print("[Director] Outside confirmation timer RESET (player room='%s')." % player_room)
	else:
		# Player is actually outside — initialize the timer with a random value
		# if it hasn't been initialized yet.
		if not _outside_confirmation_initialized:
			_outside_confirmation_timer = randf_range(OUTSIDE_CONFIRMATION_MIN, OUTSIDE_CONFIRMATION_MAX)
			_outside_confirmation_initialized = true
			print("[Director] Outside confirmation timer set to %.1f seconds (random %d-%d range). Player room='%s'." % [_outside_confirmation_timer, OUTSIDE_CONFIRMATION_MIN, OUTSIDE_CONFIRMATION_MAX, player_room])
		
		# Count down the timer
		_outside_confirmation_timer -= entity.get_physics_process_delta_time()
		if _outside_confirmation_timer < 0.0:
			_outside_confirmation_timer = 0.0
	
	# ─── HUNTING OVERRIDE: If the Entity actively hears the player ──
	# This check runs BEFORE line-of-sight and state preservation so that
	# acoustic detection (hearing the player through walls) can trigger
	# pursuit regardless of confidence level.
	#
	# RULES:
	#   - Player outside AND visually confirmed → STALK (slow pursuit toward
	#     the player's last known position). The Entity does NOT CHARGE from
	#     hearing alone — CHARGE is reserved for flashlight stare (outdoor)
	#     or seeing the player indoors.
	#   - Player outside BUT NOT visually confirmed → STALK (outdoor pursuit).
	#     The Entity heard something but can't see the player, so it enters
	#     STALK mode — pathfinding to the last heard position, then pursuing
	#     the player through the forest.
	#   - Player inside → If the Entity is currently in STALK, it should
	#     exit STALK and fall through to confidence escalation (Tier 4),
	#     which will naturally select the door or a window via
	#     pick_tactical_window(). The door is already a permanent option
	#     in the window selection system.
	if entity.is_hunting():
		if not is_player_actually_outside:
			# Player is inside. If the Entity is currently in STALK, it
			# should exit STALK and fall through to confidence escalation
			# (Tier 4) which will naturally select the door or a window
			# via pick_tactical_window(). The door is already a permanent
			# option in the window selection system.
			if state == EntityAI.State.STALK:
				# Exit STALK — fall through to Tier 4 confidence escalation
				# which will pick the best entry point (door or window).
				return -1
			
			# Not in STALK — fall through to confidence escalation and
			# completion flags as before.
			return -1
		
		# ─── VISUAL CONFIRMATION GATE ──────────────────────────────────
		# The Entity heard the player outside, but it needs VISUAL confirmation
		# before it can STALK. Without this gate, the Entity would magically
		# know the player's exact location from hearing alone and pursue them
		# through the dark forest — which is unfair and omniscient.
		# If the Entity cannot SEE the player, it enters SEARCH mode —
		# pathfinding to the last heard position, then waiting before
		# returning to treeline observation.
		var sensory = entity.get_sensory_module()
		var can_see_player = sensory and sensory.has_method("can_entity_see_player") and sensory.can_entity_see_player()
		if not can_see_player:
			# ─── VAN SEQUENCE OVERRIDE ───────────────────────────────
			# During Night 2.2 van sequence, the Entity must NEVER enter
			# OBSERVE_FROM_TREELINE through this path — doing so creates
			# a 60fps oscillation: Tier 3 returns OBSERVE, then Tier 2
			# (Night Rules) immediately forces back to STALK because
			# is_van_sequence_active is true. This guard prevents the
			# confirmation timer from triggering OBSERVE during the van
			# sequence, matching all other van sequence bypasses.
			if _cached_night_manager and _cached_night_manager.is_van_sequence_active:
				return EntityAI.State.STALK
			
			# ─── OUTSIDE CONFIRMATION GATE ──────────────────────────────
			# Even when hunting, the Entity must wait for the confirmation
			# timer before entering STALK. This prevents the Entity from
			# immediately STALKing the moment it hears a noise outside.
			if _outside_confirmation_timer > 0.0:
				return EntityAI.State.OBSERVE_FROM_TREELINE
			return EntityAI.State.STALK
		
		return EntityAI.State.STALK

	
	# ─── LINE-OF-SIGHT → STALK (both outside) or CHARGE (both inside) ──
	# If both the Entity and player are outside, line-of-sight triggers STALK
	# (slow, menacing pursuit). If the Entity is inside the cabin and sees
	# the player, it triggers CHARGE — the Entity sprints at 3x speed to
	# attack the player.
	#
	# CHARGE (indoor) is only allowed when:
	#   - The Entity is inside the cabin (INDOOR_SEARCH state)
	#   - The Entity sees the player
	#   - The player is NOT shining the flashlight at the Entity
	#     (flashlight reaction is handled by Tier 0, which runs first)
	#   - The player is NOT in a lit room (the Entity will not enter lit rooms)
	#
	# CHASE is NOT used for indoor players. CHASE is an outdoor pursuit state
	# that dispatches to _stalk_state() and pathfinds toward the player's
	# position. If the player is inside, the Entity would try to pathfind
	# through the cabin walls, which is wrong.
	var sensory = entity.get_sensory_module()
	var can_see_player = sensory and sensory.has_method("can_entity_see_player") and sensory.can_entity_see_player()
	
	if can_see_player:
		if not is_player_actually_outside:
			# Player is inside the cabin. The Entity is outside (OBSERVE,
			# APPROACH_WINDOW, etc.) and sees the player through a window.
			# Do NOT STALK — STALK is outdoor pursuit. Fall through to
			# confidence escalation (APPROACH_WINDOW) or
			# state completion flags.
			# Exception: If the Entity is already inside (INDOOR_SEARCH),
			# CHARGE at 3x speed to attack the player.
			if state == EntityAI.State.INDOOR_SEARCH:
				return EntityAI.State.CHARGE
			return -1  # Fall through to Tier 4 (confidence escalation)
		else:
			# Both outside — STALK (slow, menacing pursuit)
			return EntityAI.State.STALK
	
	# ─── PLAYER BELIEVED OUTSIDE BUT NOT VISIBLE → STALK ──────────
	# The Entity believes the player has escaped (thinks_player_is_inside=false)
	# but cannot see them. Instead of immediately STALKing, the Entity must
	# wait for the confirmation timer (random 5-10 seconds) to count down to
	# 0.0 first. During this delay, the Entity stays in OBSERVE_FROM_TREELINE,
	# continuing to watch the cabin from the treeline.
	#
	# This gives the player time to actually sneak away before the Entity
	# starts actively looking for them. The confirmation timer is managed
	# at the top of this function (initialized with a random value, counted
	# down each frame).
	#
	# If the Entity still believes the player is inside, fall through to
	# state preservation below (keep the current state).
	#
	# REALITY CHECK GATE:
	# Even if the Entity BELIEVES the player is outside (thinks_player_is_inside=false),
	# we double-check against the navigation module's ACTUAL player location
	# (is_player_actually_outside, computed at the top of this function via
	# get_player_room()). This prevents the Entity from STALKing when the
	# player has gone back inside but the belief system hasn't been updated.
	if is_player_actually_outside:
		# ─── VAN SEQUENCE BYPASS ──────────────────────────────────────
		# During the Night 2.2 van sequence (car alarm → player investigates),
		# skip the outside confirmation timer entirely. The Entity must
		# STALK immediately — the narrative overrides all confirmation
		# logic. This prevents the "Entity toggles between STALK and
		# OBSERVE every frame" bug where the timer keeps re-initializing.
		if _cached_night_manager and _cached_night_manager.is_van_sequence_active:
			print("[TRACE_DIRECTOR] VAN SEQUENCE: Bypassing outside confirmation timer. Forcing STALK.")
			return EntityAI.State.STALK
		
		# ─── REALITY CHECK: Is the player ACTUALLY outside? ─────────────
		# The Entity's belief system may be stale (e.g., the Entity heard the
		# player outside 10 seconds ago, but the player has since gone back
		# inside without making noise). We verify against the navigation
		# module's real-time player location (computed at the top of this
		# function via get_player_room()) to avoid STALKing an indoor player.
		if _outside_confirmation_timer > 0.0:
			# ─── STILL CONFIRMING: Stay in OBSERVE_FROM_TREELINE ─────────
			# The Entity has deduced the player might be outside, but hasn't
			# confirmed it yet. It continues watching the cabin from the
			# treeline. The confirmation timer is counting down each frame.
			# Once it reaches 0.0, the Entity will transition to STALK.
			return EntityAI.State.OBSERVE_FROM_TREELINE
		
		# ─── CONFIRMED: Player is truly outside. Start STALKING. ────────
		return EntityAI.State.STALK
	
	# ─── STALK STATE HANDLING ─────────────────────────────────────────
	# If the Entity is in STALK, check whether the player is still outside.
	# If the player is outside, preserve STALK (the Entity continues pursuing).
	# If the player entered the cabin, the Entity should exit STALK and fall
	# through to confidence escalation (Tier 4), which will naturally select
	# the door or a window via pick_tactical_window(). The door is already a
	# permanent option in the window selection system.
	#
	# Additionally, if the player is lit up by a cabin light or porch light
	# (static environmental lights), the Entity should also exit STALK and
	# return to default behavior. The Entity avoids lit areas, so chasing
	# the player through a pool of light is counterproductive.
	if state == EntityAI.State.STALK:
		# ─── VAN SEQUENCE PRESERVATION ─────────────────────────────────
		# During the Night 2.2 van sequence, the Entity must hold STALK
		# regardless of lighting conditions, player location, or any
		# other factor. This is a narrative override — the car alarm
		# sequence demands the Entity aggressively pursue the player.
		#
		# PERMANENT RESOLUTION CHECK:
		# If _night_2_van_sequence_resolved is true (the player has
		# entered the cabin room), the van sequence lock is permanently
		# bypassed. This prevents a STALK deadlock where the Entity
		# preserves STALK forever because is_van_sequence_active remains
		# true until entity_ai clears it during INDOOR_SEARCH — but the
		# Entity can never reach INDOOR_SEARCH while STALK is preserved.
		if _cached_night_manager and _cached_night_manager.is_van_sequence_active and not _night_2_van_sequence_resolved:
			print("[TRACE_DIRECTOR] VAN SEQUENCE: Preserving STALK. Lighting and player location checks bypassed.")
			return EntityAI.State.STALK
		
		# ─── LIGHT CHECK: Player lit by cabin/porch light ─────────────
		# If the player is standing in a lit area (cabin light leaking
		# through windows, or the porch floodlight), the Entity should
		# stop STALKING and return to default behavior. The Entity avoids
		# lit areas, so chasing the player through light is pointless.
		if nav and nav.has_method("is_player_lit_by_static_lights") and nav.is_player_lit_by_static_lights():
			var confidence = entity.get_confidence_module().get_confidence()
			var is_player_inside_belief = entity.get_thinks_player_is_inside() if entity.has_method("get_thinks_player_is_inside") else false
			if confidence >= 40.0:
				return EntityAI.State.APPROACH_WINDOW
			return EntityAI.State.OBSERVE_FROM_TREELINE
		
		if not is_player_actually_outside:
			# Player entered the cabin. The Entity should stop STALKING
			# and fall through to confidence escalation (Tier 4) which
			# will naturally select the door or a window via
			# pick_tactical_window(). The door is already a permanent
			# option in the window selection system.
			var confidence = entity.get_confidence_module().get_confidence()
			var is_player_inside_belief = entity.get_thinks_player_is_inside() if entity.has_method("get_thinks_player_is_inside") else false
			if confidence >= 40.0:
				return EntityAI.State.APPROACH_WINDOW
			return EntityAI.State.OBSERVE_FROM_TREELINE
		
		# Player is still outside — preserve STALK (continue pursuing)
		return EntityAI.State.STALK


	
	return -1


# ═══════════════════════════════════════════════════════════════════════════════
# TIER 4: CONFIDENCE ESCALATION (Interrupts passive states)
# ═══════════════════════════════════════════════════════════════════════════════
## Checked BEFORE state completion flags so that high confidence can
## interrupt OBSERVE_FROM_TREELINE and force APPROACH_WINDOW even if the
## stare timer hasn't expired.
##
## IMPORTANT: We only apply confidence escalation when the Entity is
## in a passive state (OBSERVE, STANDOFF, or idle). Active states
## (CHASE, CHARGE, INDOOR_SEARCH, etc.) are preserved by Tier 3.
##
## Returns: The target state, or -1 if no escalation applies.
func _tier_4_confidence_escalation(entity: CharacterBody3D, state: int) -> int:
	# ─── DEFENSE-IN-DEPTH: Physically inside guard ──────────────────────
	# If the Entity is physically inside the cabin, do NOT escalate to
	# exterior states like APPROACH_WINDOW. The Entity should remain in
	# its indoor state. This prevents the Director from forcing an exterior
	# approach when the persistence timer has expired but the Entity is
	# still physically indoors (desync recovery).
	if entity.has_method("is_physically_inside") and entity.is_physically_inside():
		return -1
	
	if state != EntityAI.State.OBSERVE_FROM_TREELINE and state != EntityAI.State.STANDOFF:
		return -1
	
	var confidence = entity.get_confidence_module().get_confidence()
	
	# Safely check if player is inside (BELIEF SYSTEM) — default to false
	var is_player_inside = entity.get_thinks_player_is_inside() if entity.has_method("get_thinks_player_is_inside") else false
	
	if confidence >= 40.0:
		return EntityAI.State.APPROACH_WINDOW
	
	return -1


# ═══════════════════════════════════════════════════════════════════════════════
# TIER 5: STATE COMPLETION FLAGS
# ═══════════════════════════════════════════════════════════════════════════════
## State handlers set completion flags on the Blackboard when their work
## is done. The Director checks these flags and transitions accordingly.
## After consuming a flag, the Director resets it to prevent re-triggering.
##
## Returns: The target state, or -1 if no completion flag is set.
func _tier_5_completion_flags(entity: CharacterBody3D, state: int) -> int:
	if state == EntityAI.State.APPROACH_WINDOW:
		if entity.is_approach_finished:
			entity.is_approach_finished = false
			# ─── DOOR VS WINDOW DISPATCH ───────────────────────────────
			# The APPROACH_WINDOW handler now handles both windows AND the
			# front door using a multi-phase sequence.
			#
			# WINDOW: Standard window approach. Transition to WINDOW_PEEK.
			#   This is the default case — if is_door_target is false, the
			#   Entity approached a window, not a door.
			#
			# LOCKED DOOR: The door was locked. The Entity paused 2 seconds,
			#   played the rattle sound, and signaled completion. Transition
			#   to OBSERVE_FROM_TREELINE — the Entity gives up and returns
			#   to treeline observation. The 30-second door approach cooldown
			#   prevents immediate re-attempt.
			#
			# UNLOCKED DOOR (closed or open): The Entity opened the door,
			#   walked through the doorway to the interior waypoint, and
			#   signaled completion. Transition to INDOOR_SEARCH — the Entity
			#   has entered the cabin through the front door.
			#
			# CRITICAL: We check is_door_target FIRST to distinguish between
			# a window approach and a door approach. If is_door_target is
			# false, this was a window — go to WINDOW_PEEK. If true, check
			# is_door_locked to determine the door outcome.
			if not entity.is_door_target:
				# ─── WINDOW APPROACH ────────────────────────────────────
				# The Entity approached a window, not a door. Transition to
				# WINDOW_PEEK to begin the peek/breach sequence.
				print("[Director] APPROACH_WINDOW (window) complete! Transitioning to WINDOW_PEEK.")
				return EntityAI.State.WINDOW_PEEK
			
			# ─── DOOR APPROACH ──────────────────────────────────────────
			# The Entity approached the front door. Consume the door target
			# flag and check if the door was locked.
			entity.is_door_target = false
			if entity.is_door_locked:
				entity.is_door_locked = false
				print("[Director] APPROACH_WINDOW (door) complete! Door was LOCKED. Returning to OBSERVE_FROM_TREELINE.")
				return EntityAI.State.OBSERVE_FROM_TREELINE
			# Door was unlocked — the Entity walked through the doorway and is now inside the cabin.
			# Transition to INDOOR_SEARCH to begin hunting the player indoors.
			# Set the was_door_entry flag so _indoor_search_state() can bypass Phase A
			# (vault animation + teleport math) and go straight to Phase B (patrol).
			entity.was_door_entry = true
			print("[Director] APPROACH_WINDOW (door) complete! Door was UNLOCKED. Entering cabin via INDOOR_SEARCH.")
			return EntityAI.State.INDOOR_SEARCH

	
	if state == EntityAI.State.WINDOW_PEEK:
		# ─── NULL WINDOW TARGET GUARD ──────────────────────────────────
		if not entity.get_current_window_target():
			entity.is_window_unbarricaded = false
			return EntityAI.State.OBSERVE_FROM_TREELINE
		
		# ─── PEEK ABORT HANDLING ──────────────────────────────────────
		# The peek assessment in entity_ai.gd's _window_peek_state() may
		# determine this is a bad breach point (room is lit OR player is
		# visible). In that case, it sets is_observe_finished to signal
		# the Director to fall back to treeline observation and try a
		# different angle later.
		if entity.is_observe_finished:
			entity.is_observe_finished = false
			return EntityAI.State.OBSERVE_FROM_TREELINE
		
		if entity.is_window_unbarricaded:
			entity.is_window_unbarricaded = false
			return EntityAI.State.INDOOR_SEARCH
		return EntityAI.State.WINDOW_PEEK
	
	if state == EntityAI.State.RETREAT:
		if entity.is_retreat_arrived:
			entity.is_retreat_arrived = false
			# Reset the retreat target flag so the next RETREAT re-selects a target
			var ai = entity.get_ai_module()
			if ai and ai.has_method("reset_retreat_target"):
				ai.reset_retreat_target()
			return EntityAI.State.OBSERVE_FROM_TREELINE
		return EntityAI.State.RETREAT
	
	if state == EntityAI.State.STALK:
		# STALK has no completion flag — it persists until the Director
		# overrides it via a higher-priority tier (e.g., flashlight reaction,
		# line-of-sight lost, or confidence escalation).
		return EntityAI.State.STALK
	
	if state == EntityAI.State.FLINCH:
		if entity.is_flinch_finished:
			entity.is_flinch_finished = false
			# ─── CLEAR WINDOW TARGET ──────────────────────────────────
			entity.set_current_window_target(null)
			
			# ─── ANTI-FLAP: Set cooldown to prevent immediate re-entry ──
			_anti_flap_cooldown = 0.5
			_last_completed_state = EntityAI.State.FLINCH
			return EntityAI.State.OBSERVE_FROM_TREELINE
		return EntityAI.State.FLINCH
	
	if state == EntityAI.State.SEARCH:
		# SEARCH is deprecated — redirect to STALK.
		# The SEARCH state handler in entity_ai.gd is a stub that immediately
		# signals completion. Instead of going through the stub, we redirect
		# directly to STALK so the Entity pursues the player through the forest.
		return EntityAI.State.STALK
	
	if state == EntityAI.State.OBSERVE_FROM_TREELINE:
		if entity.is_observe_finished:
			entity.is_observe_finished = false
			
			# ─── CLEAR FLINCH BLACKLIST ON RELOCATION CYCLE ────────────────
			# The Entity is completing an OBSERVE observation cycle and
			# relocating to a new vantage point. Clear the flinch blacklist
			# so all windows are available for selection on the next approach.
			# This is the primary clear condition (Correction 3).
			if entity.has_method("clear_flinch_blacklist"):
				entity.clear_flinch_blacklist()
			
			entity.fade_and_relocate()
			return EntityAI.State.OBSERVE_FROM_TREELINE
		return EntityAI.State.OBSERVE_FROM_TREELINE
	
	# ─── SABOTAGE_FUSE COMPLETION ────────────────────────────────────
	if state == EntityAI.State.SABOTAGE_FUSE:
		if entity.is_fuse_sabotaged:
			entity.is_fuse_sabotaged = false
			# Fuse Box destroyed! All lights are off including the porch light.
			# Transition to OBSERVE_FROM_TREELINE — the confidence system will
			# escalate to APPROACH_WINDOW naturally since no windows are lit
			# and the porch light is off, allowing the Entity to approach the door.
			print("[Director] SABOTAGE_FUSE complete! Fuse Box broken. Returning to OBSERVE_FROM_TREELINE.")
			return EntityAI.State.OBSERVE_FROM_TREELINE
		return EntityAI.State.SABOTAGE_FUSE
	
	# ─── FUSE SABOTAGE COMPLETION ────────────────────────────────────
	if state == EntityAI.State.FUSE_SABOTAGE:
		if entity.is_fuse_sabotaged:
			entity.is_fuse_sabotaged = false
			# Fuse Box destroyed! All lights are off. Transition to
			# OBSERVE_FROM_TREELINE — the confidence system will escalate
			# to APPROACH_WINDOW naturally since no windows are lit.
			return EntityAI.State.OBSERVE_FROM_TREELINE
		return EntityAI.State.FUSE_SABOTAGE
	
	# ─── PERSISTENT STATES (no completion flags) ─────────────────────
	# These states have no completion flags — they persist until the
	# Director overrides them via a higher-priority tier.
	if state == EntityAI.State.ATTACK_LAMP:
		return EntityAI.State.ATTACK_LAMP
	
	if state == EntityAI.State.STUNNED:
		return EntityAI.State.STUNNED
	
	if state == EntityAI.State.HARASS:
		return EntityAI.State.HARASS
	
	return -1


# ═══════════════════════════════════════════════════════════════════════════════
# TIER 6: PORTABLE TRAP ATTRACTION
# ═══════════════════════════════════════════════════════════════════════════════
## If a powered, deployed portable lamp exists, the Entity abandons its
## treeline observation and physically stalks toward the lamp to attack it.
##
## Returns: The target state, or -1 if no trap attraction applies.
func _tier_6_trap_attraction(entity: CharacterBody3D) -> int:
	var trap = entity.get_portable_trap()
	if trap and trap.is_deployed and trap.is_powered:
		return EntityAI.State.ATTACK_LAMP
	return -1


# ═══════════════════════════════════════════════════════════════════════════════
# TIER 7: CONFIDENCE ESCALATION (Fallback for non-passive states)
# ═══════════════════════════════════════════════════════════════════════════════
## If the Entity is in an active state (e.g., PATROL, DORMANT) and
## confidence is high, escalate to window approach. This is the fallback
## for states that weren't caught by Tier 4 above.
##
## IMPORTANT: This tier must NOT match active indoor states like INDOOR_SEARCH.
## If the Entity is inside the cabin searching for the player, Tier 7 should
## NOT force APPROACH_WINDOW — that would create an infinite loop:
##   WINDOW_PEEK → INDOOR_SEARCH → (Tier 7 catches) → APPROACH_WINDOW → WINDOW_PEEK
##
## Returns: The target state, or -1 if no escalation applies.
func _tier_7_fallback_confidence(entity: CharacterBody3D) -> int:
	# ─── DEFENSE-IN-DEPTH: Physically inside guard ──────────────────────
	# If the Entity is physically inside the cabin, do NOT escalate to
	# exterior states like APPROACH_WINDOW. Same rationale as Tier 4 guard.
	if entity.has_method("is_physically_inside") and entity.is_physically_inside():
		return -1
	
	var state = entity.get_state()
	
	# ─── ACTIVE STATE GUARD ──────────────────────────────────────────────
	# Do NOT override active states. The Entity is already engaged
	# in a meaningful behavior and should not be redirected.
	if state in EntityAI.UNINTERRUPTIBLE_STATES:
		return -1
	
	# ─── DOOR BREACH COOLDOWN GUARD ──────────────────────────────────────
	# After a successful door breach, enforce a 15-second cooldown before
	# the Director can trigger APPROACH_WINDOW again. This prevents the
	# looping bug where the Entity breaches → Director sees player inside →
	# triggers APPROACH_WINDOW again → Entity jitters/teleports back to the door.
	#
	# The timestamp is set by entity_ai.gd's Ghost Breach block when the
	# Entity teleports to the IndoorBreachWaypoint. If the current time is
	# less than 15 seconds after the last breach, block APPROACH_WINDOW.
	var current_time = Time.get_ticks_msec() / 1000.0
	var time_since_breach = current_time - entity.last_door_breach_time
	if time_since_breach < 15.0:
		return -1
	
	var confidence = entity.get_confidence_module().get_confidence()
	
	# Safely check if player is inside (BELIEF SYSTEM) — default to false
	var is_player_inside = entity.get_thinks_player_is_inside() if entity.has_method("get_thinks_player_is_inside") else false
	
	if confidence >= 40.0:
		return EntityAI.State.APPROACH_WINDOW
	
	return -1
