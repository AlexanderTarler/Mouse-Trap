extends Node

## Entity AI — Finite State Machine behaviors for the Entity.
## Receives a reference to the parent entity_controller to read/write shared state.
## Called from entity_controller._physics_process() each frame.

var entity: CharacterBody3D = null

## Timer for damaging window barricades (accumulates delta while at a boarded window)
var _barricade_damage_timer: float = 0.0

## Whether the Entity has arrived at the indoor breach landing position.
## Used by INDOOR_SEARCH to distinguish Phase A (vault entry) from Phase B (patrol).
var _has_arrived_indoor: bool = false

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

## Whether a retreat target has been set for physical RETREAT pathfinding.
## Reset after the Entity reaches the exit point and fades out.
var _retreat_target_set: bool = false

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

func setup(parent: CharacterBody3D) -> void:
	entity = parent


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

## Resets the barricade damage and siege timers to 0.0.
## Called by entity_controller.gd's _debug_attack_window() when F2 forces
## the Entity into WINDOW_PEEK state.
func reset_barricade_timers() -> void:
	_barricade_damage_timer = 0.0
	_siege_duration_timer = 0.0


## Main update tick — dispatches to the correct state function.
func update(delta: float) -> void:
	# --- VAULT ENTRY HARDENING ---
	# During Phase A of INDOOR_SEARCH (vault entry), the Entity is committed
	# to entering the cabin. Skip ALL external stimuli — no outside interception,
	# no light sanctuary checks, no line-of-sight distractions.
	# This prevents the Entity from being interrupted mid-vault-transition.
	if entity._state == entity.State.INDOOR_SEARCH and not _has_arrived_indoor:
		# Skip outside interception — Entity is mid-vault
		pass
	else:
		# --- GLOBAL OVERRIDE: OUTSIDE INTERCEPTION ---
		# Only intercept if the entity is currently 'Watching' from the treeline.
		# This prevents the logic from overriding an active CHASE or RETREAT
		# sequence every frame, which would cause the "Yo-Yo" chasing loop.
		if entity._state == entity.State.OBSERVE_FROM_TREELINE and entity._navigation.is_player_outside():
			entity._state = entity.State.CHASE
			print("[Entity AI] Player went outside! Switching to CHASE.")
	
	# --- STATE DISPATCHER ---
	match entity._state:
		entity.State.DORMANT:
			entity.velocity = Vector3.ZERO
		entity.State.OBSERVE_FROM_TREELINE:
			_observe_from_treeline_state(delta)
		entity.State.RETREAT:
			_retreat_state(delta)
		entity.State.APPROACH_WINDOW:
			_approach_window_state(delta)
		entity.State.WINDOW_PEEK:
			_window_peek_state(delta)
		entity.State.CHASE, entity.State.PATROL:
			_stalk_state(delta)
		entity.State.CHARGE:
			_charge_state(delta)
		entity.State.FLINCH:
			_flinch_state(delta)
		entity.State.INDOOR_SEARCH:
			_indoor_search_state(delta)
		entity.State.CLIMB_WALL:
			_climb_wall_state(delta)
		entity.State.ATTACK_LAMP:
			_attack_lamp_state(delta)
		_:
			entity.velocity = Vector3.ZERO



# ---------------------------------------------------------------------------
# STATE: OBSERVE_FROM_TREELINE
# ---------------------------------------------------------------------------

func _observe_from_treeline_state(delta: float) -> void:
	# --- PORTABLE TRAP ATTRACTION OVERRIDE ---
	# If a powered, deployed portable lamp exists, the Entity abandons its
	# treeline observation and physically stalks toward the lamp to attack it.
	# This prevents the old teleport loop where the Entity would be attracted
	# to the trap but then fade_and_relocate() when the stare timer expired.
	var trap = entity.get_tree().get_first_node_in_group("portable_trap")
	if trap and trap.is_deployed and trap.is_powered:
		entity._state = entity.State.ATTACK_LAMP
		entity._nav_agent.target_position = trap.global_position
		entity._lamp_attack_timer = 0.0
		print("[Entity AI] Powered portable trap detected! Transitioning to ATTACK_LAMP.")
		return
	
	# --- STARE TIMER ---
	# After staring at a vantage point for a while, fade and relocate.
	entity._stare_timer -= delta
	if entity._stare_timer <= 0.0:
		entity.fade_and_relocate()



# ---------------------------------------------------------------------------
# STATE: ATTACK_LAMP — Physical approach and strike against the portable lamp
# ---------------------------------------------------------------------------
# The Entity abandons all treeline observation and physically pathfinds
# toward the deployed portable high-voltage lamp. Once within striking
# distance (3.0 units), it attacks the lamp every 3 seconds.
#
# BEHAVIOR:
#   1. Sets NavigationAgent3D target_position directly to the lamp's position.
#   2. Moves toward it using standard stalk speed. No random relocations.
#   3. When within 3.0 units, accumulates a 3-second strike timer.
#   4. Every 3.0 seconds, calculates the directional vector toward the lamp
#      and calls trap.take_physical_hit(direction_vector).
#   5. If the lamp loses power (is_powered == false) or is no longer deployed,
#      instantly exits ATTACK_LAMP and returns to OBSERVE_FROM_TREELINE.
# ---------------------------------------------------------------------------

func _attack_lamp_state(delta: float) -> void:
	var trap = entity.get_tree().get_first_node_in_group("portable_trap")
	
	# --- EXIT CONDITION: Lamp is gone, unpowered, or undeployed ---
	if not trap or not trap.is_deployed or not trap.is_powered:
		print("[Entity AI] Portable lamp lost power or was removed. Exiting ATTACK_LAMP.")
		entity._state = entity.State.OBSERVE_FROM_TREELINE
		entity._lamp_attack_timer = 0.0
		entity.velocity = Vector3.ZERO
		return
	
	# --- CONTINUOUS PATHFINDING TOWARD THE LAMP ---
	# Update the nav target every path_update_interval seconds so the Entity
	# tracks the lamp's current position (it may have been knocked away by a hit).
	entity._path_timer += delta
	if entity._path_timer >= entity.path_update_interval:
		entity._path_timer = 0.0
		entity._nav_agent.target_position = trap.global_position
	
	# --- STRIKE TIMER: Attack the lamp every 3 seconds when close enough ---
	var dist_to_trap: float = entity.global_position.distance_to(trap.global_position)
	
	if dist_to_trap < 3.0:
		# Accumulate the attack timer
		entity._lamp_attack_timer += delta
		
		if entity._lamp_attack_timer >= 3.0:
			entity._lamp_attack_timer = 0.0
			
			# Calculate the direction from the Entity to the lamp
			var hit_dir: Vector3 = (trap.global_position - entity.global_position).normalized()
			
			# Call take_physical_hit on the lamp
			if trap.has_method("take_physical_hit"):
				trap.take_physical_hit(hit_dir)
				print("[Entity AI] ATTACK_LAMP: Struck portable lamp at distance %.1f!" % dist_to_trap)
			
			# Trigger a claw/strike animation
			if entity._anim_state_machine:
				entity._anim_state_machine.travel("AttackWindow")
		
		# Stop movement while attacking (stand still and swing)
		entity.velocity = Vector3.ZERO
	else:
		# --- MOVE TOWARD THE LAMP ---
		if entity._nav_agent.is_navigation_finished():
			entity.velocity.x = 0.0
			entity.velocity.z = 0.0
		else:
			var next_pos = entity._nav_agent.get_next_path_position()
			var dir_2d := Vector2(next_pos.x - entity.global_position.x, next_pos.z - entity.global_position.z)
			if dir_2d.length() > 0.01:
				var move_dir_2d = dir_2d.normalized()
				entity.velocity.x = move_dir_2d.x * entity.current_stalk_speed
				entity.velocity.z = move_dir_2d.y * entity.current_stalk_speed


# ---------------------------------------------------------------------------
# STATE: STALK (CHASE / PATROL)
# ---------------------------------------------------------------------------


func _stalk_state(delta: float) -> void:
	# --- LIGHT SANCTUARY ESCAPE ---
	# If the Entity is chasing indoors and the player reaches a lit room,
	# the Entity is repelled by the light and must abort the chase.
	# This gives the player a meaningful counterplay: run to a lit room.
	if entity._state == entity.State.CHASE and not entity._navigation.is_player_outside():
		var cabin_lights = entity.get_tree().get_nodes_in_group("CabinLights")
		var near_lit_light = false
		for cl in cabin_lights:
			var cabin_light = cl as CabinLight
			if cabin_light and cabin_light.is_switched_on:
				var dist = entity._player.global_position.distance_to(cabin_light.global_position)
				if dist < 6.0:  # Sanctuary radius around each lit light
					near_lit_light = true
					break
		if near_lit_light:
			print("[Entity AI] Player reached a lit sanctuary! Aborting chase.")
			# Play a one-shot frustrated grunt before fading out.
			# This gives the player clear audio feedback that they've
			# successfully escaped into a lit room.
			entity._play_light_sanctuary_grunt()
			entity.fade_and_relocate()
			return

	
	if entity.global_position.distance_to(entity._player.global_position) <= entity.catch_distance:
		entity._on_caught_player()
		return
	
	entity._path_timer += delta
	if entity._path_timer >= entity.path_update_interval:
		entity._path_timer = 0.0
		entity._nav_agent.target_position = entity._player.global_position
	
	if entity._nav_agent.is_navigation_finished():
		entity.velocity.x = 0.0
		entity.velocity.z = 0.0
	else:
		var next_pos = entity._nav_agent.get_next_path_position()
		var dir_2d := Vector2(next_pos.x - entity.global_position.x, next_pos.z - entity.global_position.z)
		if dir_2d.length() > 0.01:
			var move_dir_2d = dir_2d.normalized()
			entity.velocity.x = move_dir_2d.x * entity.current_stalk_speed
			entity.velocity.z = move_dir_2d.y * entity.current_stalk_speed


# ---------------------------------------------------------------------------
# STATE: CHARGE (3x speed sprint at the player)
# ---------------------------------------------------------------------------

func _charge_state(delta: float) -> void:
	# 3x movement speed during charge
	var charge_speed = entity.current_stalk_speed * 3.0
	
	# Continuously update target to the player's current position
	entity._path_timer += delta
	if entity._path_timer >= entity.path_update_interval:
		entity._path_timer = 0.0
		entity._nav_agent.target_position = entity._player.global_position
	
	# Check if we caught the player
	if entity.global_position.distance_to(entity._player.global_position) <= entity.catch_distance:
		entity._on_caught_player()
		return
	
	if entity._nav_agent.is_navigation_finished():
		entity.velocity.x = 0.0
		entity.velocity.z = 0.0
	else:
		var next_pos = entity._nav_agent.get_next_path_position()
		var dir_2d := Vector2(next_pos.x - entity.global_position.x, next_pos.z - entity.global_position.z)
		if dir_2d.length() > 0.01:
			var move_dir_2d = dir_2d.normalized()
			entity.velocity.x = move_dir_2d.x * charge_speed
			entity.velocity.z = move_dir_2d.y * charge_speed


# ---------------------------------------------------------------------------
# STATE: FLINCH (Lateral Sprint to Evade Flashlight)
# ---------------------------------------------------------------------------
# BEHAVIOR 1 (Cowardly Outside Flinch):
# Called when the player is INSIDE the cabin and shines the flashlight at the
# Entity while it is OUTSIDE. The Entity does NOT fade/teleport — it sprints
# laterally (perpendicular to the player's camera view) at 1.5x speed for
# 1.5 seconds, then transitions to RELOCATE to pick a new vantage point.
#
# PHYSICS-BASED MOVEMENT:
# The Entity's velocity is set as a directional vector, and the engine's
# built-in move_and_slide() in entity_controller._physics_process() handles
# collision resolution automatically. This guarantees the Entity slides
# cleanly around tree trunks, exterior pillars, and boulders during its
# blind lateral dash.
#
# Gravity is bypassed during FLINCH (see entity_controller.gd gravity bypass)
# to prevent the Entity from dropping into a ditch or clipping through terrain.
# ---------------------------------------------------------------------------

func _flinch_state(delta: float) -> void:
	entity._flinched_timer -= delta
	
	# Move toward the flinch target position using physics-based velocity.
	# move_and_slide() in entity_controller._physics_process() handles
	# collision resolution automatically.
	var dir = (entity._flinch_target_pos - entity.global_position).normalized()
	var flinch_speed = entity.current_stalk_speed * 1.5
	entity.velocity.x = dir.x * flinch_speed
	entity.velocity.z = dir.z * flinch_speed
	
	# Check if timer expired or we're close enough to target
	var dist_to_target = entity.global_position.distance_to(entity._flinch_target_pos)
	if entity._flinched_timer <= 0.0 or dist_to_target < 1.0:
		# Flinch complete — transition to RELOCATE to pick a new vantage point
		entity.fade_and_relocate()


# ---------------------------------------------------------------------------
# STATE: RETREAT (Physical Pathfinding Escape)
# ---------------------------------------------------------------------------
# The Entity does NOT fade-and-teleport when repelled by light during
# INDOOR_SEARCH. Instead, it physically pathfinds back to the nearest broken
# window or open door and escapes through it. Once outside, it fades out.
#
# This creates a terrifying visual: the Entity skittering backward through
# the cabin on all fours, scrambling out the broken window frame.
# ---------------------------------------------------------------------------

func _retreat_state(delta: float) -> void:
	# --- PHYSICAL RETREAT PATHFINDING ---
	# The Entity must physically navigate to an exit point and escape.
	# This is NOT a fade/teleport — the player can see the Entity fleeing.
	
	# If we haven't set a retreat target yet, find one
	if not _retreat_target_set:
		_retreat_target_set = true
		
		# Priority 1: Retreat back through the breach window
		if entity._indoor_breach_window:
			var exit_pos = entity._indoor_breach_window.global_position
			entity._nav_agent.target_position = exit_pos
			print("[Entity AI] Retreating to breach window at: ", exit_pos)
		
		# Priority 2: Find nearest unsecured window
		else:
			_find_nearest_unsecured_window()
	
	# Move toward the retreat target
	if entity._nav_agent.is_navigation_finished():
		# Reached the exit point — now fade out and relocate to treeline
		entity.fade_and_relocate()
		_retreat_target_set = false
		return
	
	var next_pos = entity._nav_agent.get_next_path_position()
	var dir_2d := Vector2(next_pos.x - entity.global_position.x, next_pos.z - entity.global_position.z)
	if dir_2d.length() > 0.01:
		var move_dir_2d = dir_2d.normalized()
		# Retreat speed = 1.5x stalk speed (frantically escaping the light)
		var retreat_speed = entity.current_stalk_speed * 1.5
		entity.velocity.x = move_dir_2d.x * retreat_speed
		entity.velocity.z = move_dir_2d.y * retreat_speed
	
	# Play panicked indoor footsteps while retreating
	_play_indoor_footstep(delta)


# ---------------------------------------------------------------------------
# STATE: APPROACH_WINDOW
# ---------------------------------------------------------------------------

func _approach_window_state(delta: float) -> void:
	# If the player goes outside, intercept them in the yard
	if entity._navigation.is_player_outside():
		print("[Entity AI] Player went outside! Intercepting in the yard.")
		entity._state = entity.State.CHASE
		return
	
	var windows = entity.get_tree().get_nodes_in_group("WindowMarkers")
	if windows.is_empty():
		entity._state = entity.State.PATROL # Fallback if no windows exist
		return
	
	if not entity._current_window_target:
		# Find the window closest to the player, excluding the previous target.
		# Skip windows that are secure by light (Entity avoids lit windows).
		var best_window = null
		var shortest = INF
		for w in windows:
			if w == entity._current_window_target:
				continue # Don't pick the same window twice in a row
			
			# Check if this window is a CabinWindow and if it's secure by light.
			# The marker may be a child node of the CabinWindow, so fall back to the parent.
			var cabin_win = w as CabinWindow
			if not cabin_win:
				cabin_win = w.get_parent() as CabinWindow
			if cabin_win and cabin_win.is_secure() and cabin_win.get_secure_type() == "light":
				# ─── LIGHT SABOTAGE ──────────────────────────────────────
				# 30% chance to sabotage the light and approach anyway.
				# The Entity reaches through the window frame or uses its
				# supernatural influence to flick the light switch, plunging
				# the room into darkness. This removes the light sanctuary
				# protection, making the window vulnerable to siege.
				if randf() < 0.3 and entity._light_sabotage_cooldown <= 0.0:
					entity._sabotage_light(cabin_win)
					# Do NOT skip this window — approach it now that the light is off
				else:
					continue # Entity avoids light-sanctuary windows — pick a different one
			
			var d = w.global_position.distance_to(entity._player.global_position)
			if d < shortest:
				shortest = d
				best_window = w
		
		# If all windows are light-secure, pick the closest one anyway (fallback)
		if not best_window:
			best_window = windows[0]
			for w in windows:
				var d = w.global_position.distance_to(entity._player.global_position)
				if d < shortest:
					shortest = d
					best_window = w
		
		entity._current_window_target = best_window
		entity._nav_agent.target_position = entity._current_window_target.global_position
		
		# Log the selected window with its window_id for debugging
		var selected_win = entity._current_window_target as CabinWindow
		if not selected_win:
			selected_win = entity._current_window_target.get_parent() as CabinWindow
		var win_id_str = selected_win.window_id if selected_win and not selected_win.window_id.is_empty() else "UNKNOWN"
		print("[Entity AI] Approaching window: ", win_id_str)
		
		# ─── WINDOW BLUFF ──────────────────────────────────────────────
		# 20% chance to bluff instead of commit. The Entity fakes an
		# approach toward the window, stops short, pauses, then retreats.
		# This creates tension and uncertainty for the player, who must
		# guess whether the Entity is actually sieging.
		if randf() < 0.2 and entity._window_bluff_cooldown <= 0.0:
			entity._start_window_bluff(entity._current_window_target)
			return
	
	if entity._nav_agent.is_navigation_finished():
		entity.velocity = Vector3.ZERO
		
		# Check if the arrived window is a CabinWindow with barricade planks.
		# The marker may be a child node of the CabinWindow, so fall back to the parent.
		var cabin_win = entity._current_window_target as CabinWindow
		if not cabin_win:
			cabin_win = entity._current_window_target.get_parent() as CabinWindow
		
		# Log arrival with window ID
		var arrived_id = cabin_win.window_id if cabin_win and not cabin_win.window_id.is_empty() else "UNKNOWN"
		print("[Entity AI] Arrived at window: ", arrived_id)
		
		if cabin_win and cabin_win.is_boarded:
			# Window is boarded — enter barricade damage state instead of peeking
			entity._state = entity.State.WINDOW_PEEK
			entity._stare_timer = 9999.0  # Stay until barricade is destroyed
			_barricade_damage_timer = 0.0
			print("[Entity AI] Window is boarded! Beginning barricade damage sequence.")
		else:
			# Normal window peek
			entity._state = entity.State.WINDOW_PEEK
			entity._stare_timer = 6.0
		
		entity._current_window_target = null
	else:
		var next_pos = entity._nav_agent.get_next_path_position()
		var dir_2d := Vector2(next_pos.x - entity.global_position.x, next_pos.z - entity.global_position.z).normalized()
		entity.velocity.x = dir_2d.x * entity.current_stalk_speed
		entity.velocity.z = dir_2d.y * entity.current_stalk_speed


# ---------------------------------------------------------------------------
# STATE: WINDOW_PEEK
# ---------------------------------------------------------------------------

func _window_peek_state(delta: float) -> void:
	# ─── SIEGE DURATION LOCK ───────────────────────────────────────
	# Forces the Entity to stay in WINDOW_PEEK for a minimum of 5 seconds
	# before the stare timer can trigger an exit. This prevents premature
	# departure after the glass shatters, ensuring the full attack animation
	# plays out and all barricade hits are delivered.
	# The timer is incremented every frame and only checked when deciding
	# whether to tick down the stare timer (see below).
	_siege_duration_timer += delta
	
	# Decrement the barricade animation lock timer.
	# When > 0.0, the "AttackWindow" animation is forced to play.
	# This ensures the animation plays for its full 1.5s duration even if
	# the next hit is 2 seconds away.
	if _barricade_anim_lock > 0.0:
		_barricade_anim_lock = max(0.0, _barricade_anim_lock - delta)
	
	# --- BARRICADE DAMAGE SEQUENCE ---
	# If the Entity is at a boarded window, it pauses and damages the planks.
	# The stare timer is set to 9999.0 when barricade damage begins, so the
	# Entity stays until the planks break or it's interrupted.
	if _barricade_damage_timer >= 0.0:
		# ─── TARGET ANCHOR OPTIMIZATION ────────────────────────────
		# If _current_window_target is already valid and attached to the
		# scene tree, bypass the group scanning loop entirely and use it
		# directly. This guarantees the target chosen by F2 (or any prior
		# state) is held securely throughout the entire sequential
		# destruction timeline without risk of dropping the reference.
		var nearest_win: CabinWindow = null
		if entity._current_window_target and is_instance_valid(entity._current_window_target):
			nearest_win = entity._current_window_target as CabinWindow
			if not nearest_win:
				nearest_win = entity._current_window_target.get_parent() as CabinWindow
		
		# Fallback: scan the group if no valid target is cached
		if not nearest_win:
			# Find the nearest CabinWindow to damage.
			# The Entity attacks windows that are EITHER boarded (planks present)
			# OR have intact glass (glass not yet shattered). This ensures the
			# Entity smashes through the glass first, then damages the planks.
			var windows = entity.get_tree().get_nodes_in_group("WindowMarkers")
			var nearest_dist = INF
			for w in windows:
				var cw = w as CabinWindow
				if not cw:
					cw = w.get_parent() as CabinWindow
				if cw and (cw.is_boarded or not cw.is_glass_shattered):
					var d = entity.global_position.distance_to(w.global_position)
					if d < nearest_dist:
						nearest_dist = d
						nearest_win = cw
			
			if nearest_win and nearest_dist >= 4.5:
				nearest_win = null  # Too far — don't damage
		
		if nearest_win:
			# Accumulate damage over time
			_barricade_damage_timer += delta
			
			# ─── STEP A: The Swing ──────────────────────────────────────
			# When the 2.0s timer ticks over, play the AttackWindow animation
			# and start the impact delay timer. Do NOT apply damage yet.
			# The damage is applied in STEP B when _pending_damage_delay reaches 0.
			if _barricade_damage_timer >= 2.0 and not _has_pending_damage:
				_barricade_damage_timer = 0.0
				_has_pending_damage = true
				_pending_damage_delay = 0.6  # Mid-point of AttackWindow animation
				
				# Play the attack sound telegraph
				var splinter_sound = nearest_win.get_node_or_null("BarricadeDamageAudio")
				if splinter_sound and splinter_sound is AudioStreamPlayer3D:
					splinter_sound.play()
				
				# Set the animation lock so the controller plays AttackWindow
				_barricade_anim_lock = 1.5
				
				print("[Entity AI] AttackWindow swing started. Impact pending in 0.6s.")
			
			# ─── STEP B: The Impact Delay ───────────────────────────────
			# Count down the pending damage delay. When it reaches 0, apply
			# the actual damage to the barricade. This syncs the health
			# subtraction with the visual impact frame of the AttackWindow
			# animation, so the player sees the Entity's arm swing through
			# the window before the plank health decreases.
			if _has_pending_damage:
				_pending_damage_delay -= delta
				if _pending_damage_delay <= 0.0:
					_has_pending_damage = false
					_pending_damage_delay = 0.0
					
					# Apply damage NOW — the animation has reached impact
					var destroyed = nearest_win.damage_barricade()
					
					if destroyed:
						print("[Breach Debug] Barricade shattered! Entity forcing entry through window into room node.")
						
						# --- BREACH SEQUENCE: Transition to INDOOR_SEARCH ---
						# Store a reference to the breached window so the Entity knows
						# where to retreat back through if repelled by a light sanctuary.
						entity._indoor_breach_window = nearest_win
						
						# Play a violent mechanical crunch + high-intensity Entity growl
						var crunch_sound = nearest_win.get_node_or_null("BreakSound")
						if crunch_sound and crunch_sound is AudioStreamPlayer3D:
							crunch_sound.pitch_scale = 1.3
							crunch_sound.play()
						if entity._growl_audio:
							entity._growl_audio.pitch_scale = 1.2
							entity._growl_audio.play()
						
						# ─── HOLLYWOOD TELEPORT SWAP ─────────────────────────────
						# Instantly teleport the Entity's outdoor body to the indoor
						# landing position. This bypasses the narrow window frame
						# collision geometry entirely — no lerp glide, no pathfinding
						# through the wall opening. The Entity simply vanishes from
						# the window sill and reappears on the interior floor, ready
						# to patrol.
						var landing_pos = nearest_win.get_indoor_landing_position()
						entity.global_position = landing_pos
						entity.velocity = Vector3.ZERO
						_has_arrived_indoor = true  # Skip Phase A entirely
						print("[F2 Hollywood Swap] Outdoor Entity seamlessly swapped to indoor landing coordinates: ", landing_pos)
						
						# Transition to INDOOR_SEARCH. Because _has_arrived_indoor is
						# already true, _indoor_search_state() will skip Phase A (Vault
						# Entry) and fall directly into Phase B (Stalk Patrol) on the
						# next physics frame.
						entity._state = entity.State.INDOOR_SEARCH
						entity._indoor_patrol_index = 0
						_barricade_damage_timer = -1.0  # Reset damage state
						return
		else:
			# No boarded window nearby — fall through to normal peek behavior
			_barricade_damage_timer = -1.0
	
	# ─── SIEGE DURATION GUARD ──────────────────────────────────────
	# If the siege duration timer hasn't reached 5 seconds yet, do NOT
	# tick down the stare timer. This forces the Entity to stay in
	# WINDOW_PEEK for a minimum duration, preventing premature exit
	# after the glass shatters. The siege timer is reset to 0.0 when
	# transitioning into WINDOW_PEEK (see _approach_window_state).
	if _siege_duration_timer >= 5.0:
		# Tick down stare timer
		entity._stare_timer -= delta
		
		# If the entity sees the player, freeze the timer (stares indefinitely, building interest)
		if entity._sensory.can_entity_see_player():
			entity._stare_timer = 9999.0 # Effectively infinite — stays as long as it has line of sight
		
		# If stare timer expired, pick a different window
		if entity._stare_timer <= 0.0:
			print("[Entity AI] Window peek timer expired. Seeking new window.")
			entity._state = entity.State.APPROACH_WINDOW
			entity._current_window_target = null
			return
	
	entity.velocity = Vector3.ZERO


# ---------------------------------------------------------------------------
# STATE: INDOOR_SEARCH (Breach Entry + Cabin Patrol)
# ---------------------------------------------------------------------------
# Phase A (Vault Entry): The Entity navigates to the window's IndoorBreachWayPoint.
#   - HARD LOCK: Ignores ALL external stimuli during vault entry.
#     The Entity is committed to entering — no light sanctuary repel,
#     no line-of-sight distraction, no outside interception.
# Phase B (Stalk Patrol): Once inside, the Entity loops through
#   Cabin_Patrol_Waypoints to hunt for the player. If line-of-sight is
#   established, upgrades to CHASE.
# ---------------------------------------------------------------------------

func _indoor_search_state(delta: float) -> void:
	# --- CATCH CHECK ---
	if entity.global_position.distance_to(entity._player.global_position) <= entity.catch_distance:
		entity._on_caught_player()
		return
	
	# --- LIGHT SANCTUARY REPEL OVERRIDE ---
	# If the Entity is indoors and the player reaches a lit room, do NOT
	# instantly teleport away via RELOCATE. Instead, force RETREAT and
	# pathfind back to the nearest broken window to vault back out.
	# NOTE: This check is SKIPPED during Phase A (vault entry) to prevent
	# the Entity from being interrupted mid-transition.
	if _has_arrived_indoor and _check_light_sanctuary_near_player():
		print("[Entity AI] Light sanctuary detected during indoor search! Retreating to broken window.")
		entity._state = entity.State.RETREAT
		_retreat_target_set = false  # Force retreat to find a new target
		# Pathfind back to the breach window's position to exit the cabin
		if entity._indoor_breach_window:
			entity._nav_agent.target_position = entity._indoor_breach_window.global_position
		else:
			# Fallback: pathfind to the nearest unsecured window
			_find_nearest_unsecured_window()
		return
	
	# --- PHASE A: Vault Entry (DEPRECATED — handled by Hollywood Teleport Swap) ---
	# The instant teleport in _window_peek_state() sets _has_arrived_indoor = true
	# before transitioning to INDOOR_SEARCH, so this block is never reached during
	# normal gameplay. The Entity is already on the interior floor when
	# _indoor_search_state() runs.
	#
	# This guard is kept as a safety net in case some other code path transitions
	# to INDOOR_SEARCH without setting _has_arrived_indoor. If triggered, it
	# performs an instant teleport to the landing position and marks as arrived.
	if not _has_arrived_indoor and entity._indoor_breach_window:
		var landing_pos = entity._indoor_breach_window.get_indoor_landing_position()
		entity.global_position = landing_pos
		entity.velocity = Vector3.ZERO
		_has_arrived_indoor = true
		print("[Entity AI] Safety teleport: Entity was in INDOOR_SEARCH without _has_arrived_indoor. Teleported to: ", landing_pos)
		_play_indoor_footstep(delta)
		return
	
	# --- PHASE B: Stalk Patrol ---
	# Once inside, loop through Cabin_Patrol_Waypoints to hunt the player.
	_has_arrived_indoor = true
	
	# Check for line-of-sight — if we see the player, upgrade to CHASE.
	# LIGHT SANCTUARY GUARD:
	# Before upgrading to CHASE, check if the player is standing in a lit room.
	# If they are, do NOT enter CHASE — the light sanctuary check in
	# _stalk_state() would immediately repel the Entity on the next frame,
	# creating a 1-frame CHASE blip that triggers the chase exit grunt sound.
	# Instead, continue patrolling. The Entity will naturally retreat via the
	# light sanctuary check at the top of this function if the player stays
	# in the light.
	if entity._sensory.can_entity_see_player() and not _check_light_sanctuary_near_player():
		print("[Entity AI] Line of sight established indoors! Upgrading to CHASE.")
		entity._state = entity.State.CHASE
		entity._nav_agent.target_position = entity._player.global_position
		return
	
	# Patrol loop: navigate to the next cabin patrol waypoint
	var patrol_points = entity.get_tree().get_nodes_in_group("Cabin_Patrol_Waypoints")
	if patrol_points.is_empty():
		# Fallback: if no patrol waypoints exist, just chase the player's last known position
		entity._path_timer += delta
		if entity._path_timer >= entity.path_update_interval:
			entity._path_timer = 0.0
			entity._nav_agent.target_position = entity._player.global_position
		
		if entity._nav_agent.is_navigation_finished():
			entity.velocity.x = 0.0
			entity.velocity.z = 0.0
		else:
			var next_pos = entity._nav_agent.get_next_path_position()
			var dir_2d := Vector2(next_pos.x - entity.global_position.x, next_pos.z - entity.global_position.z)
			if dir_2d.length() > 0.01:
				var move_dir_2d = dir_2d.normalized()
				var indoor_speed = entity.current_stalk_speed * 0.7
				entity.velocity.x = move_dir_2d.x * indoor_speed
				entity.velocity.z = move_dir_2d.y * indoor_speed
		
		_play_indoor_footstep(delta)
		return
	
	# Ensure the patrol index is valid
	if entity._indoor_patrol_index >= patrol_points.size():
		entity._indoor_patrol_index = 0
	
	var target_waypoint = patrol_points[entity._indoor_patrol_index]
	
	# Update path to the current waypoint
	entity._path_timer += delta
	if entity._path_timer >= entity.path_update_interval:
		entity._path_timer = 0.0
		entity._nav_agent.target_position = target_waypoint.global_position
	
	# Check if we've arrived at the current waypoint
	if entity._nav_agent.is_navigation_finished():
		# Advance to the next waypoint in the loop
		entity._indoor_patrol_index = (entity._indoor_patrol_index + 1) % patrol_points.size()
		entity.velocity.x = 0.0
		entity.velocity.z = 0.0
	else:
		var next_pos = entity._nav_agent.get_next_path_position()
		var dir_2d := Vector2(next_pos.x - entity.global_position.x, next_pos.z - entity.global_position.z)
		if dir_2d.length() > 0.01:
			var move_dir_2d = dir_2d.normalized()
			var indoor_speed = entity.current_stalk_speed * 0.7  # Slow, methodical stalk
			entity.velocity.x = move_dir_2d.x * indoor_speed
			entity.velocity.z = move_dir_2d.y * indoor_speed
	
	# Play heavy wood-plank footstep thuds while moving inside
	_play_indoor_footstep(delta)


# ---------------------------------------------------------------------------
# STATE: CLIMB_WALL (Multi-Story Wall Climbing)
# ---------------------------------------------------------------------------
# Phase 1: Navigate to the base of the exterior wall below a second-story window.
# Phase 2: Vertical ascent — gravity is bypassed, Entity climbs straight up
#   the wall surface using claw-scraping audio to telegraph the position.
# ---------------------------------------------------------------------------

func _climb_wall_state(delta: float) -> void:
	# --- PHASE 1: Navigate to Wall Base ---
	if not _wall_climb_phase_2:
		var wall_base = entity._navigation.find_nearest_second_story_window_base()
		entity._nav_agent.target_position = wall_base
		
		if entity._nav_agent.is_navigation_finished():
			# Arrived at wall base — begin vertical climb
			_wall_climb_phase_2 = true
			entity.velocity = Vector3.ZERO
			
			# Determine the target Y-coordinate (the second-story window's height)
			_wall_climb_target_y = _find_target_window_y()
			
			# Orient model flat against the wall
			_orient_to_wall()
		else:
			# Move to wall base
			var next_pos = entity._nav_agent.get_next_path_position()
			var dir_2d := Vector2(next_pos.x - entity.global_position.x, next_pos.z - entity.global_position.z).normalized()
			entity.velocity.x = dir_2d.x * entity.current_stalk_speed
			entity.velocity.z = dir_2d.y * entity.current_stalk_speed
		return
	
	# --- PHASE 2: Vertical Ascent ---
	var climb_speed = 2.0  # meters per second
	entity.velocity = Vector3(0.0, climb_speed, 0.0)
	
	# Play claw-scraping audio at current height
	_update_claw_scrape_audio()
	
	# Check if we've reached the target window height
	if entity.global_position.y >= _wall_climb_target_y:
		# Reached the window — transition to WINDOW_PEEK
		entity.velocity = Vector3.ZERO
		entity._state = entity.State.WINDOW_PEEK
		entity._stare_timer = 6.0
		_wall_climb_phase_2 = false
		_stop_claw_scrape_audio()
		print("[Entity AI] Wall climb complete! Peeking through second-story window.")


## Finds the Y-coordinate of the nearest second-story window above the Entity.
## Used by CLIMB_WALL to determine the vertical climb target.
func _find_target_window_y() -> float:
	var windows = entity.get_tree().get_nodes_in_group("WindowMarkers")
	var best_y = 3.5  # Default second-story height
	var shortest = INF
	for w in windows:
		if w.global_position.y < 3.0:
			continue  # Skip ground-floor windows
		var d = entity.global_position.distance_to(w.global_position)
		if d < shortest:
			shortest = d
			best_y = w.global_position.y
	return best_y


## Orients the Entity's model to face the exterior wall during climb.
## Rotates the model 90 degrees so it appears to be flat against the wall surface.
func _orient_to_wall() -> void:
	if not entity._monster_model:
		return
	# Face toward the cabin center (assumes Entity is on the exterior wall)
	var dir_to_cabin = (entity.cabin_center - entity.global_position).normalized()
	var target_angle = atan2(dir_to_cabin.x, dir_to_cabin.z)
	entity._monster_model.rotation.y = target_angle


## Plays claw-scraping audio at the Entity's current height on the exterior wall.
## The audio source is positioned at the wall base X/Z but follows the Entity's Y.
## This creates the illusion of claws dragging up the wooden siding.
func _update_claw_scrape_audio() -> void:
	if not entity._claw_scrape_player:
		return
	# Position the audio at the Entity's current height on the exterior wall
	var wall_base = entity._navigation.find_nearest_second_story_window_base()
	entity._claw_scrape_player.global_position = Vector3(
		wall_base.x,
		entity.global_position.y,
		wall_base.z
	)
	if not entity._claw_scrape_player.playing:
		entity._claw_scrape_player.play()


## Stops the claw-scraping audio. Called when the climb is complete.
func _stop_claw_scrape_audio() -> void:
	if entity._claw_scrape_player and entity._claw_scrape_player.playing:
		entity._claw_scrape_player.stop()


## Plays heavy, localized wood-plank footstep thuds while the Entity moves indoors.
## Uses the Entity's footstep audio player with a timed interval.
## Refined for heavier feel: lower pitch (0.6-0.9) and louder volume (-3.0 dB).
func _play_indoor_footstep(delta: float) -> void:
	if not entity._footstep_audio:
		return
	
	entity._entity_step_timer += delta
	if entity._entity_step_timer >= entity._entity_step_interval:
		entity._entity_step_timer = 0.0
		# Play a heavy wood thud at the Entity's current position
		entity._footstep_audio.pitch_scale = randf_range(0.6, 0.9)  # Lower = heavier
		entity._footstep_audio.volume_db = -3.0  # Louder than exterior footsteps
		entity._footstep_audio.play()


## Checks if the player is within 6 units of any lit cabin light.
## Used by INDOOR_SEARCH to determine if the Entity should retreat.
func _check_light_sanctuary_near_player() -> bool:
	var cabin_lights = entity.get_tree().get_nodes_in_group("CabinLights")
	for cl in cabin_lights:
		var cabin_light = cl as CabinLight
		if cabin_light and cabin_light.is_switched_on:
			var dist = entity._player.global_position.distance_to(cabin_light.global_position)
			if dist < 6.0:
				return true
	return false


## Finds the nearest unsecured window and sets it as the nav target.
## Used as a fallback when the Entity needs to retreat from indoors but
## the breach window reference is lost.
func _find_nearest_unsecured_window() -> void:
	var windows = entity.get_tree().get_nodes_in_group("WindowMarkers")
	var best_window: Node3D = null
	var shortest = INF
	for w in windows:
		var cabin_win = w as CabinWindow
		if not cabin_win:
			cabin_win = w.get_parent() as CabinWindow
		# Skip windows that are light-secure (Entity avoids lit windows).
		# Boarded windows are fine — the Entity can smash through them on the way out.
		if cabin_win and (cabin_win.is_secure() and cabin_win.get_secure_type() == "light"):
			continue
		var d = entity.global_position.distance_to(w.global_position)
		if d < shortest:
			shortest = d
			best_window = w
	
	if best_window:
		entity._nav_agent.target_position = best_window.global_position
		print("[Entity AI] Retreat target set to unsecured window at: ", best_window.global_position)


# ---------------------------------------------------------------------------
# NIGHT DIFFICULTY
# ---------------------------------------------------------------------------

func setup_night_difficulty(night: int) -> void:
	entity.current_night = night
	entity.current_stalk_speed = 3.5 + (night - 1) * 0.6
	entity.current_relocate_cooldown = maxf(0.7, 3.0 - (night - 1) * 0.5)
	entity.window_peek_chance = maxf(0.05, 0.70 - (night - 1) * 0.15)
	
	# --- FLASHLIGHT FLINCH DIFFICULTY ---
	# Nights 1-4: Flinch is enabled. The Entity sprints laterally to evade.
	# Night 5:    Flinch is DISABLED — relentless siege, no escape.
	entity._flinch_enabled = (night < 5)
	
	# Night-specific speed overrides (applied after the formula above)
	if night == 4:
		entity.current_stalk_speed = 5.3
	elif night == 5:
		entity.current_stalk_speed = 5.9


func on_night_started(night: int) -> void:
	setup_night_difficulty(night)


func on_night_ended(_night: int) -> void:
	entity.deactivate()


## Resets the Entity's exposure state after a fade-and-relocate cycle.
## Called by entity_controller.fade_and_relocate() after reappearing.
func reset_exposure() -> void:
	entity._has_logged_sight = false
	entity._current_interest_level = 0.0
	entity._is_hunting = false
	entity._is_at_vantage_point = false
	print("[Entity AI] Exposure reset after relocation.")
