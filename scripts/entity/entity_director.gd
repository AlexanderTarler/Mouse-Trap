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

## ─── PERIODIC DEBUG LOG ──────────────────────────────────────────────────────
## Timer that accumulates delta each frame. When it reaches 3.0 seconds, the
## Director prints a comprehensive debug log of all Blackboard data, confidence,
## sensory info, navigation state, and AI internals — mirroring the F3 overlay.
## This provides a persistent console record for post-mortem analysis without
## needing the F3 overlay to be visible.
var _debug_log_timer: float = 0.0

## EntityAI is registered globally via class_name EntityAI in entity_ai.gd.
## No preload needed — reference EntityAI.State.X directly.

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
const INDOOR_SEARCH_PERSISTENCE_DURATION: float = 30.0

## Resets the indoor search persistence timer to 30.0 seconds.
## Called by entity_ai.gd when the Entity enters INDOOR_SEARCH state.
func reset_indoor_search_persistence() -> void:
	_indoor_search_persistence_timer = INDOOR_SEARCH_PERSISTENCE_DURATION
	print("[Director] Indoor search persistence timer set to %.1f seconds." % INDOOR_SEARCH_PERSISTENCE_DURATION)


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
	
	# ─── INDOOR SEARCH PERSISTENCE TIMER DECAY ──────────────────────────
	# Decrement the indoor search persistence timer each frame so it counts
	# down from 30.0 to 0.0 while the Entity is in INDOOR_SEARCH.
	# When it reaches 0.0, the Tier 8 guard no longer applies, allowing the
	# Director to transition to OBSERVE_FROM_TREELINE if appropriate.
	if state == EntityAI.State.INDOOR_SEARCH and _indoor_search_persistence_timer > 0.0:
		_indoor_search_persistence_timer -= entity.get_physics_process_delta_time()
	
	# ─── TIER 0: PENDING STATE OVERRIDE ──────────────────────────────
	# Checked BEFORE state_locked so critical overrides (stun release,
	# blackout enrage, debug) can interrupt locked states.
	var pending = _tier_0_pending_override(entity)
	if pending >= 0:
		return pending
	
	# ─── TIER 0: CRITICAL SURVIVAL & REACTIONS ───────────────────────
	# Checked BEFORE state_locked so flashlight reactions can forcefully
	# interrupt any ongoing task (approach, climb, etc.).
	var flashlight_state = _tier_0_flashlight_reaction(entity, state)
	if flashlight_state >= 0:
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
		return sabotage_state
	
	# ─── STATE LOCK GUARD ─────────────────────────────────────────────
	# After Tier 0 (flashlight reactions) and Tier 1 (sabotage override),
	# check if the state handler is mid-execution. If locked, return the
	# current state to prevent "State Flapping" where the Director and
	# FSM fight over the state.
	if entity.state_locked:
		return state
	
	# ─── STATE PERSISTENCE GUARD ──────────────────────────────────────
	# If the Entity is in an active state (FLINCH, CLIMB_WALL, CHARGE, etc.)
	# and the state timer is still counting down, the Director MUST return
	# the current state and skip Tier 3–8 evaluations. This prevents the
	# Director from overriding a state mid-execution while the animation
	# is still playing.
	#
	# The state timer is set by state handlers on entry (e.g., _flinch_state
	# sets this to 1.5s) and decremented each frame in _physics_process().
	# When it reaches 0.0, the Director is free to re-evaluate.
	if entity.get_state_timer() > 0.0:
		return state
	
	# ─── TIER 2: NIGHT RULES ─────────────────────────────────────────
	var night_state = _tier_2_night_rules(entity, state)
	if night_state >= 0:
		return night_state
	
	# ─── ANTI-FLAP COOLDOWN CHECK ────────────────────────────────────
	# If the anti-flap cooldown is active, the Director must NOT transition
	# into FLINCH (or other locked states) even if the Blackboard conditions
	# still match. This prevents the 60fps oscillation loop.
	if _anti_flap_cooldown > 0.0:
		return state
	
	# ─── STARE GRACE PERIOD ──────────────────────────────────────────
	# Even after the anti-flap cooldown expires, if the stare timer is still
	# high (> 0.5s), the Director extends the cooldown by another 0.5s.
	var stare_grace = _tier_2_stare_grace_period(entity, state)
	if stare_grace >= 0:
		return stare_grace
	
	# ─── TIER 3: ACTIVE AGGRESSION ───────────────────────────────────
	var aggression_state = _tier_3_active_aggression(entity, state)
	if aggression_state >= 0:
		return aggression_state
	
	# ─── TIER 4: CONFIDENCE ESCALATION (Interrupts passive states) ───
	var confidence_state = _tier_4_confidence_escalation(entity, state)
	if confidence_state >= 0:
		return confidence_state
	
	# ─── TIER 5: STATE COMPLETION FLAGS ──────────────────────────────
	var completion_state = _tier_5_completion_flags(entity, state)
	if completion_state >= 0:
		return completion_state
	
	# ─── TIER 6: PORTABLE TRAP ATTRACTION ────────────────────────────
	var trap_state = _tier_6_trap_attraction(entity)
	if trap_state >= 0:
		return trap_state
	
	# ─── TIER 7: CONFIDENCE ESCALATION (Fallback for non-passive states)
	var fallback_state = _tier_7_fallback_confidence(entity)
	if fallback_state >= 0:
		return fallback_state
	
	# ─── TIER 8: DEFAULT BASELINE ────────────────────────────────────
	# ─── INDOOR SEARCH PERSISTENCE ──────────────────────────────────────
	# If the Entity has breached a window (last_breached_window is not null)
	# and is currently in INDOOR_SEARCH, force it to stay in INDOOR_SEARCH
	# for at least 30 seconds regardless of whether it has found the player.
	# This prevents the "Breach → Search → Give Up → Breach again" loop.
	#
	# The 30-second timer is tracked via the _indoor_search_persistence_timer.
	# It is reset to 30.0 when the Entity enters INDOOR_SEARCH and decremented
	# each frame. While the timer is active, the Director returns INDOOR_SEARCH
	# as the default baseline instead of OBSERVE_FROM_TREELINE.
	if state == EntityAI.State.INDOOR_SEARCH and entity.last_breached_window != null:
		if _indoor_search_persistence_timer > 0.0:
			return EntityAI.State.INDOOR_SEARCH
	
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
# TIER 0: CRITICAL SURVIVAL & REACTIONS (Flashlight)
# ═══════════════════════════════════════════════════════════════════════════════
## Evaluates flashlight-based reactions. These are checked BEFORE the
## state_locked guard so that flashlight reactions can forcefully interrupt
## any ongoing task (approach, climb, etc.).
##
## If the Entity is illuminated, we break any existing locks and react
## immediately.
##
## EXCEPTION: FLINCH state lock is preserved. When the Entity has just escaped
## from an indoor retreat (teleported outside through the breach window), the
## indoor retreat handler sets the state to FLINCH and locks it. The FLINCH
## handler must be allowed to complete its 1.5-second lateral sprint before
## the Director re-evaluates.
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
##   - FLINCH (lateral sprint): Only allowed if the Entity is in APPROACH_WINDOW
##     (approaching a window from outside). The Entity dodges sideways.
##   - STANDOFF (freeze): Default reaction when the Entity is outside and the
##     player is staring with the flashlight.
##
## Returns: The target state, or -1 if no flashlight reaction applies.
func _tier_0_flashlight_reaction(entity: CharacterBody3D, state: int) -> int:
	if not entity.is_illuminated:
		return -1
	
	# ─── FLINCH STATE LOCK PRESERVATION ──────────────────────────────
	# If the Entity is already in FLINCH and state_locked is true, the
	# indoor retreat handler just set this state. Preserve the lock so
	# the FLINCH handler can complete its 1.5-second lateral sprint.
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
	
	# ─── SAFELY CHECK PLAYER LOCATION ───────────────────────────────
	# Null-check the navigation module to prevent crashes if it's not
	# initialized yet. Default to "player is outside" if unavailable.
	var nav = entity.get_navigation_module()
	var is_player_inside = false
	if nav and nav.has_method("is_player_outside"):
		is_player_inside = not nav.is_player_outside()
	
	# ─── INDOOR AGGRESSION STATE → RETREAT (Player inside, Entity inside) ──
	# If the Entity is inside the cabin (INDOOR_SEARCH, WINDOW_PEEK) and the
	# player shines the flashlight, the Entity must RETREAT — run to the nearest
	# broken/unboarded window, leave through it, then FLINCH.
	# CHASE is NOT included here — CHASE is outdoor pursuit, not indoor.
	if state == EntityAI.State.WINDOW_PEEK or state == EntityAI.State.INDOOR_SEARCH:
		# Set the indoor retreat flag so the RETREAT handler knows to
		# pathfind to the breach window instead of the farthest treeline.
		entity.is_indoor_retreat = true
		
		# Drop confidence to 20% — the Entity is spooked by being caught inside
		var confidence_module = entity.get_confidence_module()
		if confidence_module:
			confidence_module.set_confidence(20.0)
		
		return EntityAI.State.RETREAT
	
	# ─── APPROACH WINDOW → FLINCH ───────────────────────────────────
	# The Entity is approaching a window from outside. The flashlight
	# causes it to flinch laterally (sideways sprint) to evade the beam.
	if state == EntityAI.State.APPROACH_WINDOW:
		return EntityAI.State.FLINCH
	
	# ─── PLAYER INSIDE, ENTITY OUTSIDE → FLINCH ─────────────────────
	# If the player is inside the cabin and shines the flashlight at the
	# Entity (which is outside), the Entity loses 20% confidence and goes
	# into FLINCH state — it tries to flee from the flashlight beam and
	# runs further away for 3-5 seconds.
	#
	# ONE-SHOT GUARD: The confidence penalty is only applied ONCE per
	# FLINCH transition. Without this guard, the penalty would be applied
	# every frame while is_illuminated is true, dropping confidence below
	# 0% in a single frame. We track whether we've already applied the
	# penalty for this FLINCH via the _last_completed_state system.
	if is_player_inside:
		# Apply 20% confidence penalty only if we haven't already done so
		# for this FLINCH transition. Check if the last completed state
		# was FLINCH — if so, the penalty was already applied.
		if _last_completed_state != EntityAI.State.FLINCH:
			var confidence_module = entity.get_confidence_module()
			if confidence_module:
				var current_conf = confidence_module.get_confidence()
				var new_conf = maxf(0.0, current_conf - 20.0)
				confidence_module.set_confidence(new_conf)
				print("[Director] Player inside + Entity outside flashlight! Confidence dropped by 20%% to %.1f" % new_conf)
		
		return EntityAI.State.FLINCH
	
	# ─── OUTDOOR STARE → STANDOFF or CHARGE ─────────────────────────
	var stare_time = entity.player_stare_timer
	if stare_time >= 1.5:
		# Player stared too long while outside — CHARGE at 3x speed
		return EntityAI.State.CHARGE
	
	# Player is outside staring — STANDOFF (frozen in place, stunned)
	# The Entity is briefly "stunned" (immobile) while the player shines
	# the flashlight. If the player stops shining, this immobility ends.
	# When stare_time reaches 1.5s, the Entity enters CHARGE state above.
	return EntityAI.State.STANDOFF



# ═══════════════════════════════════════════════════════════════════════════════
# TIER 1: SABOTAGE OVERRIDE (Frustration-based Fuse Box Attack)
# ═══════════════════════════════════════════════════════════════════════════════
## Evaluates whether the Entity should abandon its current task and go straight
## to sabotaging the Fuse Box. This is triggered when the Entity has been
## frustrated by all windows being lit for too long (frustration >= 90.0).
##
## Unlike the old _tier_5_fuse_sabotage (which relied on a magic number 9999.0
## hack on the fuse sabotage timer), this tier reads the frustration value
## directly from the AI module via get_all_lit_frustration() and compares it
## against the threshold via get_frustration_threshold().
##
## This tier is checked BEFORE the state_locked guard so that frustration-based
## sabotage can interrupt locked states (approach, climb, indoor search, etc.).
## When interrupting a locked state, we safely unlock the motor and reset
## animation flags before transitioning to FUSE_SABOTAGE.
##
## Returns: The target state, or -1 if no sabotage override applies.
func _tier_1_sabotage(entity: CharacterBody3D, state: int) -> int:
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
	var night_manager = entity.get_node_or_null("/root/NightManager")
	var current_night: int = night_manager.current_night if night_manager else 1
	
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
	# ─── SAFELY CHECK PLAYER LOCATION ───────────────────────────────
	# Null-check the navigation module to prevent crashes if it's not
	# initialized yet. Default to "player is outside" if unavailable.
	var nav = entity.get_navigation_module()
	var is_player_inside = false
	if nav and nav.has_method("is_player_outside"):
		is_player_inside = not nav.is_player_outside()
	
	# ─── HUNTING OVERRIDE: If the Entity actively hears the player ──
	# This check runs BEFORE line-of-sight and state preservation so that
	# acoustic detection (hearing the player through walls) can trigger
	# pursuit regardless of confidence level.
	#
	# RULES:
	#   - Player outside → STALK (slow pursuit toward the player's last
	#     known position). The Entity does NOT CHARGE from hearing alone —
	#     CHARGE is reserved for flashlight stare (outdoor) or seeing the
	#     player indoors.
	#   - Player inside → Return -1 (no match) so the evaluation falls
	#     through to Tier 4 (confidence escalation) and Tier 5 (completion
	#     flags). The Entity knows the player is inside but cannot STALK
	#     them — STALK is an outdoor pursuit state for when both are outside.
	#     The Entity will naturally escalate to APPROACH_WINDOW via confidence
	#     escalation, or relocate to a new vantage point via the completion
	#     flag system. Returning OBSERVE_FROM_TREELINE here would prevent
	#     Tier 4 and Tier 5 from ever running, trapping the Entity in place.
	if entity.is_hunting():
		if is_player_inside:
			return -1  # Fall through to confidence escalation and completion flags
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
		if is_player_inside and state == EntityAI.State.INDOOR_SEARCH:
			# Both inside — CHARGE at 3x speed to attack the player
			return EntityAI.State.CHARGE
		else:
			# Both outside or player inside (Entity outside) — STALK
			return EntityAI.State.STALK
	
	# ─── STALK LOST LINE-OF-SIGHT → INVESTIGATE LAST KNOWN POSITION ──
	# If the Entity was STALKING but lost line-of-sight, it should search
	# for the player at the last known position. The STALK state handler
	# handles this internally via _is_investigating.
	if state == EntityAI.State.STALK:
		return EntityAI.State.STALK
	
	# Preserve active states
	if state == EntityAI.State.STALK:
		if is_player_inside:
			return EntityAI.State.OBSERVE_FROM_TREELINE
		return EntityAI.State.STALK
	
	if state == EntityAI.State.INDOOR_SEARCH:
		return EntityAI.State.INDOOR_SEARCH
	
	if state == EntityAI.State.CHARGE:
		return EntityAI.State.CHARGE
	
	return -1


# ═══════════════════════════════════════════════════════════════════════════════
# TIER 4: CONFIDENCE ESCALATION (Interrupts passive states)
# ═══════════════════════════════════════════════════════════════════════════════
## Checked BEFORE state completion flags so that high confidence can
## interrupt OBSERVE_FROM_TREELINE and force APPROACH_WINDOW or
## CLIMB_WALL even if the stare timer hasn't expired.
##
## IMPORTANT: We only apply confidence escalation when the Entity is
## in a passive state (OBSERVE, STANDOFF, or idle). Active states
## (CHASE, CHARGE, INDOOR_SEARCH, etc.) are preserved by Tier 3.
##
## Returns: The target state, or -1 if no escalation applies.
func _tier_4_confidence_escalation(entity: CharacterBody3D, state: int) -> int:
	if state != EntityAI.State.OBSERVE_FROM_TREELINE and state != EntityAI.State.STANDOFF:
		return -1
	
	var confidence = entity.get_confidence_module().get_confidence()
	
	# Safely check if player is inside — default to false if nav module unavailable
	var nav = entity.get_navigation_module()
	var is_player_inside = false
	if nav and nav.has_method("is_player_outside"):
		is_player_inside = not nav.is_player_outside()
	
	if confidence >= 65.0 and is_player_inside:
		return EntityAI.State.CLIMB_WALL_UP
	
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
			return EntityAI.State.WINDOW_PEEK
		return EntityAI.State.APPROACH_WINDOW
	
	if state == EntityAI.State.WINDOW_PEEK:
		# ─── NULL WINDOW TARGET GUARD ──────────────────────────────────
		if not entity.get_current_window_target():
			entity.is_window_unbarricaded = false
			return EntityAI.State.OBSERVE_FROM_TREELINE
		
		if entity.is_window_unbarricaded:
			entity.is_window_unbarricaded = false
			return EntityAI.State.INDOOR_SEARCH
		return EntityAI.State.WINDOW_PEEK
	
	if state == EntityAI.State.CLIMB_WALL_UP:
		if entity.is_climb_finished:
			entity.is_climb_finished = false
			return EntityAI.State.WINDOW_PEEK
		return EntityAI.State.CLIMB_WALL_UP
	
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
			
			# ─── CONFIDENCE PENALTY ───────────────────────────────────
			var confidence_module = entity.get_confidence_module()
			if confidence_module:
				var current_conf = confidence_module.get_confidence()
				var new_conf = maxf(0.0, current_conf - 20.0)
				confidence_module.set_confidence(new_conf)
			
			# ─── ANTI-FLAP: Set cooldown to prevent immediate re-entry ──
			_anti_flap_cooldown = 0.5
			_last_completed_state = EntityAI.State.FLINCH
			return EntityAI.State.OBSERVE_FROM_TREELINE
		return EntityAI.State.FLINCH
	
	if state == EntityAI.State.OBSERVE_FROM_TREELINE:
		if entity.is_observe_finished:
			entity.is_observe_finished = false
			entity.fade_and_relocate()
			return EntityAI.State.OBSERVE_FROM_TREELINE
		return EntityAI.State.OBSERVE_FROM_TREELINE
	
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
	var state = entity.get_state()
	
	# ─── ACTIVE STATE GUARD ──────────────────────────────────────────────
	# Do NOT override active indoor states. The Entity is already engaged
	# in a meaningful behavior (indoor search, charge, etc.) and should not
	# be redirected to APPROACH_WINDOW by fallback confidence.
	if state == EntityAI.State.INDOOR_SEARCH:
		return -1
	if state == EntityAI.State.CHARGE:
		return -1
	if state == EntityAI.State.STALK:
		return -1
	if state == EntityAI.State.FLINCH:
		return -1
	if state == EntityAI.State.RETREAT:
		return -1
	if state == EntityAI.State.FUSE_SABOTAGE:
		return -1
	if state == EntityAI.State.ATTACK_LAMP:
		return -1
	
	var confidence = entity.get_confidence_module().get_confidence()
	
	# Safely check if player is inside — default to false if nav module unavailable
	var nav = entity.get_navigation_module()
	var is_player_inside = false
	if nav and nav.has_method("is_player_outside"):
		is_player_inside = not nav.is_player_outside()
	
	if confidence >= 65.0 and is_player_inside:
		return EntityAI.State.CLIMB_WALL_UP
	
	if confidence >= 40.0:
		return EntityAI.State.APPROACH_WINDOW
	
	return -1
