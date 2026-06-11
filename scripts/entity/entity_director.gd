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
##   Tier 0: Critical Survival & Reactions (flashlight) — checked BEFORE state_locked
##   Tier 1: Night Rules (narrative restrictions)
##   Tier 2: Active Aggression (chase, charge, indoor search)
##   Tier 3: State Completion Flags (approach finished, climb finished, etc.)
##   Tier 4: Portable Trap Attraction
##   Tier 5: Confidence Escalation (window approach, wall climb)
##   Tier 6: Default Baseline (observe from treeline)

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

## Preload EntityAI for State enum key lookup in debug logs.
const _EntityAI := preload("entity_ai.gd")


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
## Parameters:
##   entity: The entity_controller.gd instance (CharacterBody3D)
##
## Returns: EntityAI.State enum value
func evaluate_master_state(entity: CharacterBody3D) -> int:
	var state = entity.get_state()
	var confidence = entity.get_confidence_module().get_confidence()
	var is_player_inside = not entity.get_navigation_module().is_player_outside()
	var stare_time = entity.player_stare_timer
	
	# ─── PENDING STATE OVERRIDE ──────────────────────────────────────
	# Check if an external event (stun, blackout, debug, activation) has
	# requested a state change via request_state(). If so, apply it
	# immediately and clear the flag.
	#
	# This is the ONLY mechanism by which external events can force a state
	# change. It is checked BEFORE the state_locked guard so that critical
	# overrides (like stun release or blackout enrage) can interrupt locked
	# states.
	#
	# IMPORTANT: The _pending_state is set by request_state() in the
	# entity_controller. It is cleared to -1 after being consumed.
	if entity._pending_state >= 0:
		var pending = entity._pending_state
		entity._pending_state = -1
		return pending
	
	# --- TIER 0: CRITICAL SURVIVAL & REACTIONS (Highest Authority) ---
	# These are checked BEFORE the state_locked guard so that flashlight
	# reactions can forcefully interrupt any ongoing task (approach, climb, etc.).
	# If the Entity is illuminated, we break any existing locks and react immediately.
	#
	# EXCEPTION: FLINCH state lock is preserved. When the Entity has just escaped
	# from an indoor retreat (teleported outside through the breach window), the
	# indoor retreat handler sets the state to FLINCH and locks it. The FLINCH
	# handler must be allowed to complete its 1.5-second lateral sprint before
	# the Director re-evaluates. Without this exception, the Director would
	# immediately override FLINCH with CHARGE (if stare_time >= 1.5) or STANDOFF,
	# breaking the "escape then flinch" pipeline.
	if entity.is_illuminated:
		# ─── FLINCH STATE LOCK PRESERVATION ──────────────────────────────
		# If the Entity is already in FLINCH and state_locked is true, the
		# indoor retreat handler just set this state. Preserve the lock so
		# the FLINCH handler can complete its 1.5-second lateral sprint.
		# The FLINCH handler will unlock when it finishes.
		if state == entity.EntityAI.State.FLINCH and entity.state_locked:
			return entity.EntityAI.State.FLINCH
		
		# Forcefully break any existing task locks so we can react
		entity.state_locked = false
		entity.is_approach_finished = false
		entity.is_climb_finished = false
		entity.is_flinch_finished = false
		entity.is_retreat_arrived = false
		entity.is_window_unbarricaded = false
		entity.is_observe_finished = false

		# ─── INDOOR RETREAT: Entity is inside the cabin and gets flashlighted ──
		# The Entity must rush back to the breach window and escape outside.
		# Confidence is dropped to 20% as a psychological setback.
		#
		# This covers ALL indoor states: INDOOR_SEARCH (hunting inside), CHASE
		# (if the Entity chased the player inside), or any other state where the
		# Entity is physically inside the cabin. The navigation module's
		# is_player_outside() returns false when the player is inside, which
		# means the Entity is also inside (or at the cabin).
		if state == entity.EntityAI.State.INDOOR_SEARCH or state == entity.EntityAI.State.CHASE:
			# Set the indoor retreat flag so the RETREAT handler knows to
			# pathfind to the breach window instead of the farthest treeline.
			entity.is_indoor_retreat = true
			
			# Drop confidence to 20% — the Entity is spooked by being caught inside
			var confidence_module = entity.get_confidence_module()
			if confidence_module:
				confidence_module.set_confidence(20.0)
			
			return entity.EntityAI.State.RETREAT
		
		# ─── APPROACH WINDOW FLINCH ──────────────────────────────────────
		# If the Entity is actively approaching a window and gets flashlighted,
		# it should FLINCH (sprint away) rather than STANDOFF (freeze in place).
		# This makes the flashlight a meaningful defensive tool during window
		# approach — the player can interrupt the Entity's advance.
		if state == entity.EntityAI.State.APPROACH_WINDOW:
			return entity.EntityAI.State.FLINCH
		
		if stare_time >= 1.5 and not is_player_inside:
			# Player stared too long while outside — CHARGE at 3x speed
			return entity.EntityAI.State.CHARGE
		if is_player_inside:
			# Player is inside the cabin, Entity is outside — FLINCH away
			return entity.EntityAI.State.FLINCH
		# Player is outside staring — STANDOFF (frozen in place)
		return entity.EntityAI.State.STANDOFF
	
	# --- STATE LOCK: Prevent transitions while a state handler is mid-execution ---
	# If state_locked is true, the current state handler (e.g., _approach_window_state)
	# is still running and has not yet signaled completion. The Director MUST return
	# the current state to prevent "State Flapping" where the Director and FSM fight
	# over the state variable every frame.
	#
	# The state handler sets state_locked = true on entry and state_locked = false
	# when it completes its work (usually by setting a completion flag like
	# is_approach_finished = true).
	#
	# This is checked AFTER Tier 0 (flashlight reactions) so that locked states are
	# immune to Director overrides EXCEPT for critical survival reactions.
	if entity.state_locked:
		return state
	
	# --- TIER 1: NIGHT RULES (Narrative Restrictions) ---
	# Night 1: Entity can only observe from treeline (no window approach).
	# This is a hard narrative restriction that overrides everything.
	#
	# NOTE: We read current_night from NightManager, NOT GameTime.
	# GameTime manages the day/night cycle (time of day), while NightManager
	# tracks which narrative night the player is on (1-5). The debug console
	# sets the night via NightManager.start_night(night), so reading from
	# NightManager ensures the debug override is respected.
	var night_manager = entity.get_node_or_null("/root/NightManager")
	var current_night: int = night_manager.current_night if night_manager else 1
	if current_night == 1:
		if state != entity.EntityAI.State.DORMANT and state != entity.EntityAI.State.OBSERVE_FROM_TREELINE and state != entity.EntityAI.State.RETREAT:
			return entity.EntityAI.State.OBSERVE_FROM_TREELINE
	
	# Night 2: Entity can approach windows and peek inside, but can ONLY breach
	# if the window is NOT boarded up (glass-only windows). Boarded windows are
	# immune until Night 3. This gives the player a reason to board up windows
	# on Night 1 — they'll be safe from breaches on Night 2.
	#
	# We check this by looking at the current window target. If the Entity is
	# in WINDOW_PEEK and the window is boarded, we prevent the transition to
	# INDOOR_SEARCH by NOT consuming the is_window_unbarricaded flag.
	# The Night 2 restriction is enforced in the WINDOW_PEEK state handler
	# (entity_ai.gd) which checks is_boarded before setting the completion flag.
	#
	# Additionally, on Night 2, the Director prevents APPROACH_WINDOW from
	# targeting windows that are boarded up. The window selection filter in
	# entity_navigation.gd handles this at the tactical level.
	if current_night == 2:
		# Allow APPROACH_WINDOW and WINDOW_PEEK — the state handler will
		# enforce the "no boarded windows" rule at the barricade level.
		pass

	
	# --- ANTI-FLAP COOLDOWN CHECK ---
	# If the anti-flap cooldown is active, the Director must NOT transition
	# into FLINCH (or other locked states) even if the Blackboard conditions
	# still match. This prevents the 60fps oscillation loop where:
	#   FLINCH finishes → Director forces OBSERVE → Director immediately
	#   forces FLINCH again because the flashlight is still on.
	#
	# The cooldown is set to 1.5 seconds after each FLINCH completion.
	# During this window, the Director returns the current state (which
	# should be OBSERVE_FROM_TREELINE after a FLINCH completion) instead
	# of forcing FLINCH again.
	#
	# ADDITIONALLY: Even after the cooldown expires, the Director checks
	# if the stare timer is still high (> 0.5s). If so, it extends the
	# cooldown by another 0.5s. This creates a "stare grace period" that
	# prevents the FLINCH loop from restarting while the player is still
	# actively shining the flashlight on the Entity.
	if _anti_flap_cooldown > 0.0:
		# Anti-flap is active — skip Tier 1 flashlight reactions and
		# return the current state. The Entity stays in OBSERVE until
		# the cooldown expires, at which point the flashlight can
		# trigger FLINCH again.
		return state
	
	# ─── STARE GRACE PERIOD ──────────────────────────────────────────────
	# Even after the anti-flap cooldown expires, if the stare timer is still
	# high (> 0.5s), the Director extends the cooldown by another 0.5s.
	# This prevents the FLINCH loop from restarting while the player is
	# still actively shining the flashlight on the Entity.
	#
	# The player must release the flashlight beam for at least 0.5s before
	# the Director will consider re-entering FLINCH. This gives the Entity
	# a meaningful grace period to stay in OBSERVE before the flashlight
	# can trigger FLINCH again.
	if stare_time > 0.5 and _last_completed_state == entity.EntityAI.State.FLINCH:
		_anti_flap_cooldown = 0.5
		return state
	
	# --- TIER 2: ACTIVE AGGRESSION ---
	# Preserve active pursuit states — don't interrupt mid-action.
	
	# ─── LINE-OF-SIGHT → CHASE ──────────────────────────────────────
	# If the Entity can see the player and the player is outside, transition
	# to CHASE. This is the primary mechanism for outdoor hunting — the
	# sensory module's can_entity_see_player() raycast detects the player
	# through the vision cone, and the Director converts that into a chase.
	#
	# IMPORTANT: This is checked BEFORE the CHASE preservation block so that
	# the Entity can enter CHASE from any passive state (OBSERVE, STANDOFF,
	# PATROL) when it spots the player outside.
	#
	# The sensory module's can_entity_see_player() also sets is_hunting=true
	# and updates the last known position, so the chase has a valid target.
	if not is_player_inside:
		var sensory = entity.get_sensory_module()
		if sensory and sensory.has_method("can_entity_see_player") and sensory.can_entity_see_player():
			return entity.EntityAI.State.CHASE
	
	if state == entity.EntityAI.State.CHASE:
		if is_player_inside:
			# Player ran inside during chase — observe from treeline
			return entity.EntityAI.State.OBSERVE_FROM_TREELINE
		return entity.EntityAI.State.CHASE
	
	if state == entity.EntityAI.State.INDOOR_SEARCH:
		return entity.EntityAI.State.INDOOR_SEARCH
	
	if state == entity.EntityAI.State.CHARGE:
		return entity.EntityAI.State.CHARGE
	
	# --- TIER 3: CONFIDENCE ESCALATION (Interrupts passive states) ---
	# Checked BEFORE state completion flags so that high confidence can
	# interrupt OBSERVE_FROM_TREELINE and force APPROACH_WINDOW or
	# CLIMB_WALL even if the stare timer hasn't expired.
	# This prevents the "Entity never breaches" bug where confidence
	# reaches 100 but the Entity stays in OBSERVE forever because the
	# completion flag loop (Tier 4) always fires first.
	#
	# IMPORTANT: We only apply confidence escalation when the Entity is
	# in a passive state (OBSERVE, STANDOFF, or idle). Active states
	# (CHASE, CHARGE, INDOOR_SEARCH, etc.) are preserved by Tier 2 above.
	if state == entity.EntityAI.State.OBSERVE_FROM_TREELINE or state == entity.EntityAI.State.STANDOFF:
		if confidence >= 65.0 and is_player_inside:
			return entity.EntityAI.State.CLIMB_WALL
		
		if confidence >= 40.0:
			return entity.EntityAI.State.APPROACH_WINDOW
	
	# --- TIER 4: STATE COMPLETION FLAGS ---
	# State handlers set completion flags on the Blackboard when their work
	# is done. The Director checks these flags and transitions accordingly.
	# After consuming a flag, the Director resets it to prevent re-triggering.
	
	if state == entity.EntityAI.State.APPROACH_WINDOW:
		if entity.is_approach_finished:
			entity.is_approach_finished = false
			return entity.EntityAI.State.WINDOW_PEEK
		return entity.EntityAI.State.APPROACH_WINDOW
	
	if state == entity.EntityAI.State.WINDOW_PEEK:
		# ─── NULL WINDOW TARGET GUARD ──────────────────────────────────
		# If the window target was cleared (e.g., by FLINCH completion),
		# the Entity has no window to peek at. Transition to
		# OBSERVE_FROM_TREELINE so the Director re-evaluates and selects
		# a new window on the next confidence escalation cycle.
		if not entity.get_current_window_target():
			entity.is_window_unbarricaded = false
			return entity.EntityAI.State.OBSERVE_FROM_TREELINE
		
		if entity.is_window_unbarricaded:
			entity.is_window_unbarricaded = false
			return entity.EntityAI.State.INDOOR_SEARCH
		return entity.EntityAI.State.WINDOW_PEEK
	
	if state == entity.EntityAI.State.CLIMB_WALL:
		if entity.is_climb_finished:
			entity.is_climb_finished = false
			return entity.EntityAI.State.WINDOW_PEEK
		return entity.EntityAI.State.CLIMB_WALL
	
	if state == entity.EntityAI.State.RETREAT:
		if entity.is_retreat_arrived:
			entity.is_retreat_arrived = false
			# Reset the retreat target flag so the next RETREAT re-selects a target
			var ai = entity.get_ai_module()
			if ai and ai.has_method("reset_retreat_target"):
				ai.reset_retreat_target()
			return entity.EntityAI.State.OBSERVE_FROM_TREELINE
		return entity.EntityAI.State.RETREAT
	
	if state == entity.EntityAI.State.FLINCH:
		if entity.is_flinch_finished:
			entity.is_flinch_finished = false
			# ─── CLEAR WINDOW TARGET ──────────────────────────────────
			# After FLINCH, the Entity is no longer at the window it was
			# approaching. Clear the window target so the next APPROACH_WINDOW
			# cycle re-selects a fresh window via pick_tactical_window().
			# Without this, the old window target remains set, and the Entity
			# immediately transitions to WINDOW_PEEK without actually being
			# at the window — causing the "peeks from nowhere" bug.
			entity.set_current_window_target(null)
			
			# ─── CONFIDENCE PENALTY ───────────────────────────────────
			# Being caught by the flashlight is a psychological setback.
			# Reduce confidence by 20% so the Entity retreats to the treeline
			# and re-evaluates before approaching again. This prevents the
			# FLINCH → APPROACH_WINDOW → FLINCH loop where the Entity
			# immediately re-approaches the same window after being flinched.
			var confidence_module = entity.get_confidence_module()
			if confidence_module:
				var current_conf = confidence_module.get_confidence()
				var new_conf = maxf(0.0, current_conf - 20.0)
				confidence_module.set_confidence(new_conf)
			
			# ─── ANTI-FLAP: Set cooldown to prevent immediate re-entry ──
			# The flashlight is still on, so the Director would immediately
			# force FLINCH again on the next frame. The cooldown gives the
			# Entity a 0.5s grace period in OBSERVE before the flashlight
			# can trigger FLINCH again.
			_anti_flap_cooldown = 0.5
			_last_completed_state = entity.EntityAI.State.FLINCH
			return entity.EntityAI.State.OBSERVE_FROM_TREELINE
		return entity.EntityAI.State.FLINCH
	
	if state == entity.EntityAI.State.OBSERVE_FROM_TREELINE:
		if entity.is_observe_finished:
			entity.is_observe_finished = false
			# ─── CONSUME THE COMPLETION FLAG ──────────────────────────
			# The state handler has finished its observation cycle (stare
			# timer expired). Call fade_and_relocate() to pick a new
			# vantage point and reset timers, then stay in OBSERVE.
			entity.fade_and_relocate()
			return entity.EntityAI.State.OBSERVE_FROM_TREELINE
		return entity.EntityAI.State.OBSERVE_FROM_TREELINE

	
	if state == entity.EntityAI.State.ATTACK_LAMP:
		# Stay in ATTACK_LAMP — the state handler manages the approach and
		# strike sequence. The Director will override if the Entity is
		# illuminated (Tier 1) or if the trap is destroyed.
		return entity.EntityAI.State.ATTACK_LAMP
	
	if state == entity.EntityAI.State.STUNNED:
		# Stay in STUNNED — the controller manages the stun timer.
		return entity.EntityAI.State.STUNNED
	
	if state == entity.EntityAI.State.HARASS:
		# Stay in HARASS — the state handler manages the harassment sequence.
		return entity.EntityAI.State.HARASS
	
	# --- TIER 5: PORTABLE TRAP ATTRACTION ---
	# If a powered, deployed portable lamp exists, the Entity abandons its
	# treeline observation and physically stalks toward the lamp to attack it.
	var trap = entity.get_portable_trap()
	if trap and trap.is_deployed and trap.is_powered:
		return entity.EntityAI.State.ATTACK_LAMP
	
	# --- TIER 6: CONFIDENCE ESCALATION (Fallback for non-passive states) ---
	# If the Entity is in an active state (e.g., PATROL, DORMANT) and
	# confidence is high, escalate to window approach. This is the fallback
	# for states that weren't caught by Tier 3 above.
	if confidence >= 65.0 and is_player_inside:
		return entity.EntityAI.State.CLIMB_WALL
	
	if confidence >= 40.0:
		return entity.EntityAI.State.APPROACH_WINDOW
	
	# --- TIER 7: DEFAULT BASELINE ---
	# If nothing else matches, the Entity observes from the treeline.
	return entity.EntityAI.State.OBSERVE_FROM_TREELINE


