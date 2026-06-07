extends Node

## Entity AI — Finite State Machine behaviors for the Entity (The Brain Hub).
## Receives a reference to the parent entity_controller to read/write shared state.
## Called from entity_controller._physics_process() each frame.
##
## ARCHITECTURE:
##   entity_controller.gd (Motor Hub) calls process_state_logic(delta) every frame,
##   then reads get_calculated_velocity() and applies it via move_and_slide().
##   All state decisions, velocity calculations, animation travel() calls, and
##   difficulty multipliers live here.

var entity: CharacterBody3D = null

## The velocity vector computed by the current state's logic.
## Read by entity_controller.gd after process_state_logic() completes.
var _calculated_velocity: Vector3 = Vector3.ZERO

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

## One-shot guard flag for the STANDOFF → RETREAT confidence gate.
## Set to true when the AI forces RETREAT due to low confidence (< 40).
## Reset to false when the Entity exits STANDOFF state.
## Prevents the oscillation loop: Controller sets STANDOFF → AI forces
## RETREAT → AI completes retreat (fade_and_relocate → OBSERVE) →
## Controller sets STANDOFF again.
var _standoff_retreat_triggered: bool = false

# ─── PHASE 3: WINDOW SHOPPING UTILITY SCORER ────────────────────────────────
## Array of recently visited windows (max 3 entries).
## Each entry is the window's NodePath or unique identifier string.
## Used by _score_window() to apply a recency malus (-30.0 penalty).
var _recently_visited_windows: Array[String] = []

## Maximum number of entries in _recently_visited_windows.
const MAX_RECENT_WINDOWS: int = 3

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


## Public API: Called by entity_controller.gd (Motor Hub) every physics frame.
## Processes the current state's logic and stores the result in _calculated_velocity.
## The Motor Hub then reads get_calculated_velocity() and applies it via move_and_slide().
func process_state_logic(delta: float) -> void:
	# ─── 5-NIGHT SIEGE PROGRESSION: NIGHT RULES EVALUATION ──────────────
	# Every decision cycle, evaluate the current night to enforce
	# night-specific infiltration capabilities. This runs BEFORE the
	# state dispatcher so that night rules can override state transitions.
	_evaluate_night_rules(delta)
	
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
			_calculated_velocity = Vector3.ZERO
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
		entity.State.HARASS:
			_harass_state(delta)
		entity.State.INDOOR_SEARCH:
			_indoor_search_state(delta)
		entity.State.CLIMB_WALL:
			_climb_wall_state(delta)
		entity.State.STANDOFF:
			# ─── FLASHLIGHT STANDOFF ──────────────────────────────────────
			# The Entity freezes in place while the player shines the flashlight
			# beam on it. A charge countdown begins (default 1.5s, halved to
			# 0.75s if confidence > THRESHOLD_CLIMAX). When the countdown
			# expires, the Entity's reaction depends on the player's floor material:
			#
			#   WOOD FLOOR (player is inside the cabin):
			#     The Entity does NOT charge through the window. Instead, it
			#     retreats into the deep shadows, startled by the flashlight
			#     beam from inside the cabin.
			#
			#   DIRT/GRASS (player is outside in the yard):
			#     The Entity charges at 3x speed — the player is in the open
			#     yard with no sanctuary.
			#
			# ─── CONFIDENCE GATING ────────────────────────────────────────
			# If confidence < THRESHOLD_WINDOW_APPROACH (40), the Entity is
			# too timid to even stand its ground — force RETREAT immediately.
			# If confidence > THRESHOLD_CLIMAX (85), the charge countdown is
			# halved to 0.75s (relentless aggression).
			_calculated_velocity = Vector3.ZERO
			
			# ─── CONFIDENCE GATE: LOW CONFIDENCE → IMMEDIATE RETREAT ─────
			var current_confidence: float = 15.0
			if entity._confidence and entity._confidence.has_method("get_confidence"):
				current_confidence = entity._confidence.get_confidence()
			
			if current_confidence < 40.0:
				# ─── ONE-SHOT GUARD ──────────────────────────────────────────
				# Only force RETREAT ONCE per STANDOFF entry. Without this guard,
				# the AI forces RETREAT every frame while in STANDOFF, creating an
				# oscillation loop: Controller sets STANDOFF → AI forces RETREAT →
				# AI completes retreat (fade_and_relocate → OBSERVE) → Controller
				# sets STANDOFF again. The _standoff_retreat_triggered flag is set
				# to true on the first retreat and reset to false when the Entity
				# exits STANDOFF state.
				if _standoff_retreat_triggered:
					return
				_standoff_retreat_triggered = true
				
				# Confidence too low to stand ground — retreat immediately
				print("[Entity AI] STANDOFF: Confidence too low (%.1f < 40). Forcing RETREAT." % current_confidence)
				_charge_countdown = 0.0
				entity._state = entity.State.RETREAT
				_retreat_target_set = false
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
					entity._nav_agent.target_position = farthest_marker.global_position
				else:
					entity._nav_agent.target_position = Vector3(9.0, 0.0, 40.0)
				return
			
			if entity._sensory and entity._sensory.is_player_spotting_entity():
				# Player is still staring — accumulate the charge countdown.
				# ─── CONFIDENCE SPEED BOOST ──────────────────────────────
				# If confidence > THRESHOLD_CLIMAX (85), halve the countdown
				# to 0.75s before charging (relentless aggression).
				var charge_threshold: float = 1.5
				if current_confidence >= 85.0:
					charge_threshold = 0.75
				
				_charge_countdown += delta
				
				# ─── CHARGE THRESHOLD ──────────────────────────────────
				if _charge_countdown >= charge_threshold:
					_charge_countdown = 0.0
					
					# ─── FLOOR MATERIAL SAFETY SWITCH ──────────────────
					var player_is_inside_cabin: bool = false
					var floor_raycast: RayCast3D = entity._player.get_node_or_null("FloorRayCast")
					if floor_raycast and floor_raycast.is_colliding():
						var surface_node: Node = floor_raycast.get_collider()
						while surface_node:
							if surface_node.is_in_group("wood"):
								player_is_inside_cabin = true
								break
							surface_node = surface_node.get_parent()
					
					if player_is_inside_cabin and entity._state != entity.State.INDOOR_SEARCH:
						# ─── INSIDE: Startled retreat to deep shadows ──
						entity._state = entity.State.RETREAT
						_retreat_target_set = false
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
							entity._nav_agent.target_position = farthest_marker.global_position
							print("[Entity AI] STANDOFF → RETREAT: Player on wood flooring! Retreating to distant vantage point: ", farthest_marker.name)
						else:
							entity._nav_agent.target_position = Vector3(9.0, 0.0, 40.0)
							print("[Entity AI] STANDOFF → RETREAT: No treeline markers found. Using fallback position.")
					else:
						# ─── OUTSIDE: Charge at the player ─────────────
						entity._state = entity.State.CHARGE
						entity._nav_agent.target_position = entity._player.global_position
						print("[Entity AI] STANDOFF → CHARGE: Player on dirt/grass! Charging at 3x speed.")
			else:
				# Player broke line of sight or turned off the flashlight.
				# Reset the countdown and drop back to observation.
				_charge_countdown = 0.0
				_standoff_retreat_triggered = false  # Reset one-shot guard for next STANDOFF
				entity._state = entity.State.OBSERVE_FROM_TREELINE
				print("[Entity AI] STANDOFF → OBSERVE: Player broke line of sight. Countdown reset.")
		entity.State.ATTACK_LAMP:
			_attack_lamp_state(delta)
		_:
			_calculated_velocity = Vector3.ZERO
	
	# --- 3D SPATIAL VOICE STATE MACHINE ---
	# Route the Entity's voice based on the current FSM state.
	# Called every frame after the state dispatcher so the voice reflects
	# the most recent state transition.
	_manage_spatial_voice()


# ---------------------------------------------------------------------------
# STATE: OBSERVE_FROM_TREELINE
# ---------------------------------------------------------------------------

func _observe_from_treeline_state(delta: float) -> void:
	# --- PORTABLE TRAP ATTRACTION OVERRIDE ---
	# If a powered, deployed portable lamp exists, the Entity abandons its
	# treeline observation and physically stalks toward the lamp to attack it.
	var trap = entity.get_tree().get_first_node_in_group("portable_trap")
	if trap and trap.is_deployed and trap.is_powered:
		entity._state = entity.State.ATTACK_LAMP
		entity._nav_agent.target_position = trap.global_position
		entity._lamp_attack_timer = 0.0
		print("[Entity AI] Powered portable trap detected! Transitioning to ATTACK_LAMP.")
		return
	
	# --- PHYSICAL PATHFINDING TO VANTAGE POINT ---
	if not entity._nav_agent.is_navigation_finished():
		var next_pos = entity._nav_agent.get_next_path_position()
		var dir_2d := Vector2(next_pos.x - entity.global_position.x, next_pos.z - entity.global_position.z)
		if dir_2d.length() > 0.01:
			var move_dir_2d = dir_2d.normalized()
			_calculated_velocity.x = move_dir_2d.x * entity.current_stalk_speed
			_calculated_velocity.z = move_dir_2d.y * entity.current_stalk_speed
		return
	
	# --- ARRIVED AT VANTAGE POINT ---
	if entity._stare_timer >= 9990.0:
		entity._stare_timer = randf_range(8.0, 15.0)
		entity._is_at_vantage_point = true
		print("[Entity AI] Arrived at vantage point. Staring for %.1f seconds." % entity._stare_timer)
	
	_calculated_velocity.x = 0.0
	_calculated_velocity.z = 0.0
	
	entity._stare_timer -= delta
	if entity._stare_timer <= 0.0:
		entity.fade_and_relocate()



# ---------------------------------------------------------------------------
# STATE: ATTACK_LAMP — Physical approach and strike against the portable lamp
# ---------------------------------------------------------------------------

func _attack_lamp_state(delta: float) -> void:
	var trap = entity.get_tree().get_first_node_in_group("portable_trap")
	
	if not trap or not trap.is_deployed or not trap.is_powered:
		print("[Entity AI] Portable lamp lost power or was removed. Exiting ATTACK_LAMP.")
		entity._state = entity.State.OBSERVE_FROM_TREELINE
		entity._lamp_attack_timer = 0.0
		_calculated_velocity = Vector3.ZERO
		return
	
	entity._path_timer += delta
	if entity._path_timer >= entity.path_update_interval:
		entity._path_timer = 0.0
		entity._nav_agent.target_position = trap.global_position
	
	var dist_to_trap: float = entity.global_position.distance_to(trap.global_position)
	
	if dist_to_trap < 3.0:
		entity._lamp_attack_timer += delta
		
		if entity._lamp_attack_timer >= 3.0:
			entity._lamp_attack_timer = 0.0
			var hit_dir: Vector3 = (trap.global_position - entity.global_position).normalized()
			if trap.has_method("take_physical_hit"):
				trap.take_physical_hit(hit_dir)
				print("[Entity AI] ATTACK_LAMP: Struck portable lamp at distance %.1f!" % dist_to_trap)
			if entity._anim_state_machine:
				entity._anim_state_machine.travel("AttackWindow")
		
		_calculated_velocity = Vector3.ZERO
	else:
		if entity._nav_agent.is_navigation_finished():
			_calculated_velocity.x = 0.0
			_calculated_velocity.z = 0.0
		else:
			var next_pos = entity._nav_agent.get_next_path_position()
			var dir_2d := Vector2(next_pos.x - entity.global_position.x, next_pos.z - entity.global_position.z)
			if dir_2d.length() > 0.01:
				var move_dir_2d = dir_2d.normalized()
				_calculated_velocity.x = move_dir_2d.x * entity.current_stalk_speed
				_calculated_velocity.z = move_dir_2d.y * entity.current_stalk_speed


# ---------------------------------------------------------------------------
# STATE: STALK (CHASE / PATROL)
# ---------------------------------------------------------------------------

func _stalk_state(delta: float) -> void:
	if entity._state == entity.State.PATROL:
		var trap = entity.get_tree().get_first_node_in_group("portable_trap")
		if trap and trap.is_deployed and trap.is_powered:
			entity._state = entity.State.ATTACK_LAMP
			entity._nav_agent.target_position = trap.global_position
			entity._lamp_attack_timer = 0.0
			print("[Entity AI] Powered portable trap detected during patrol! Transitioning to ATTACK_LAMP.")
			return
	
	if entity._state == entity.State.CHASE and not entity._navigation.is_player_outside():
		var cabin_lights = entity.get_tree().get_nodes_in_group("CabinLights")
		var near_lit_light = false
		for cl in cabin_lights:
			var cabin_light = cl as CabinLight
			if cabin_light and cabin_light.is_switched_on:
				var dist = entity._player.global_position.distance_to(cabin_light.global_position)
				if dist < 6.0:
					near_lit_light = true
					break
		if near_lit_light:
			print("[Entity AI] Player reached a lit sanctuary! Aborting chase.")
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
		_calculated_velocity.x = 0.0
		_calculated_velocity.z = 0.0
	else:
		var next_pos = entity._nav_agent.get_next_path_position()
		var dir_2d := Vector2(next_pos.x - entity.global_position.x, next_pos.z - entity.global_position.z)
		if dir_2d.length() > 0.01:
			var move_dir_2d = dir_2d.normalized()
			_calculated_velocity.x = move_dir_2d.x * entity.current_stalk_speed
			_calculated_velocity.z = move_dir_2d.y * entity.current_stalk_speed


# ---------------------------------------------------------------------------
# STATE: CHARGE (3x speed sprint at the player)
# ---------------------------------------------------------------------------

func _charge_state(delta: float) -> void:
	var charge_speed = entity.current_stalk_speed * 3.0
	
	entity._path_timer += delta
	if entity._path_timer >= entity.path_update_interval:
		entity._path_timer = 0.0
		entity._nav_agent.target_position = entity._player.global_position
	
	if entity.global_position.distance_to(entity._player.global_position) <= entity.catch_distance:
		entity._on_caught_player()
		return
	
	if entity._nav_agent.is_navigation_finished():
		_calculated_velocity.x = 0.0
		_calculated_velocity.z = 0.0
	else:
		var next_pos = entity._nav_agent.get_next_path_position()
		var dir_2d := Vector2(next_pos.x - entity.global_position.x, next_pos.z - entity.global_position.z)
		if dir_2d.length() > 0.01:
			var move_dir_2d = dir_2d.normalized()
			_calculated_velocity.x = move_dir_2d.x * charge_speed
			_calculated_velocity.z = move_dir_2d.y * charge_speed


# ---------------------------------------------------------------------------
# STATE: FLINCH (Phantom Evasion — Lerp to Dark Position)
# ---------------------------------------------------------------------------
## The Entity slides laterally into the darkness to evade the player's
## flashlight beam. Unlike the old sprint-based flinch, this version uses
## a smooth lerp toward a dark position (treeline vantage point) with
## visual alpha fade-out for a "phantom" effect.
##
## BEHAVIOR:
##   1. On first entry, picks the nearest treeline vantage point as the
##      dark target position.
##   2. Each frame, lerps the Entity's position toward the dark target
##      at 1.5x stalk speed.
##   3. The Entity's visual model fades to transparent over 1.5 seconds
##      via a Tween in entity_controller.gd.
##   4. When the flinch timer expires (1.5s) or the Entity reaches the
##      dark target, transitions to OBSERVE_FROM_TREELINE.
##
## Called from process_state_logic() when the state dispatcher routes to
## State.FLINCH.
func _flinch_state(delta: float) -> void:
	# ─── FIRST ENTRY: Pick dark target position ──────────────────────
	if not entity.has_meta("_flinch_dark_target_set"):
		entity.set_meta("_flinch_dark_target_set", true)
		
		# Find the nearest treeline vantage point
		var treeline_markers: Array[Node] = entity.get_tree().get_nodes_in_group("Treeline_Vantage_Points")
		if not treeline_markers.is_empty():
			var nearest_marker: Node3D = treeline_markers[0] as Node3D
			var nearest_dist: float = INF
			for marker in treeline_markers:
				var m: Node3D = marker as Node3D
				if m:
					var d: float = entity.global_position.distance_squared_to(m.global_position)
					if d < nearest_dist:
						nearest_dist = d
						nearest_marker = m
			entity._flinch_target_pos = nearest_marker.global_position
			print("[Entity AI] FLINCH: Dark target set to treeline marker: ", nearest_marker.name)
		else:
			# Fallback: 15 units behind the Entity's current position
			var behind_dir = -entity.global_transform.basis.z
			entity._flinch_target_pos = entity.global_position + behind_dir * 15.0
			print("[Entity AI] FLINCH: No treeline markers found. Using fallback dark position.")
		
		# Start the visual alpha fade Tween
		if entity._monster_model and entity.has_method("_start_flinch_fade"):
			entity._start_flinch_fade()
	
	# ─── LERP TOWARD DARK TARGET ────────────────────────────────────
	entity._flinched_timer -= delta
	
	var lerp_speed: float = entity.current_stalk_speed * 1.5 * delta
	entity.global_position = entity.global_position.lerp(entity._flinch_target_pos, lerp_speed)
	
	# Zero out the calculated velocity — we're lerping position directly
	_calculated_velocity = Vector3.ZERO
	
	# ─── EXIT CONDITION ─────────────────────────────────────────────
	var dist_to_target: float = entity.global_position.distance_to(entity._flinch_target_pos)
	if entity._flinched_timer <= 0.0 or dist_to_target < 2.0:
		# Reset the dark target meta flag
		entity.set_meta("_flinch_dark_target_set", false)
		
		# Reset visual alpha to fully opaque
		if entity._monster_model:
			entity._monster_model.modulate.a = 1.0
		
		# Transition to treeline observation
		entity._state = entity.State.OBSERVE_FROM_TREELINE
		entity._stare_timer = 9999.0
		print("[Entity AI] FLINCH: Reached dark position. Transitioning to OBSERVE_FROM_TREELINE.")


# ---------------------------------------------------------------------------
# STATE: HARASS (Psychological Harassment Probes)
# ---------------------------------------------------------------------------
## The Entity stands at a window performing a 3-phase harassment sequence:
##
##   Phase 1 (0-3s): Heavy breathing loop (intimate, close to the glass).
##   Phase 2 (3-6s): Tap or scratch sound on the window pane.
##   Phase 3 (6-9s): Window rattle / heavier impact (threat display).
##
## Resolution (At 9s): Evaluate player reaction via RLOS.
##   - IF the player is NOT looking at the window: Confidence +8.0.
##     Transition to WINDOW_PEEK to begin damaging the barricade.
##   - IF the player IS looking at the window: Confidence -5.0.
##     Transition immediately to FLINCH (Phantom Evasion) to slide into darkness.
##
## The Entity stands completely still during the harassment (velocity = 0).
## The _harass_audio player is positioned at the window's position so the
## sounds emanate from the correct spatial location.
##
## Called from process_state_logic() when the state dispatcher routes to
## State.HARASS.
func _harass_state(delta: float) -> void:
	# ─── NIGHT 1: PURELY PASSIVE OBSERVATION ─────────────────────────
	if entity.current_night == 1:
		entity._state = entity.State.OBSERVE_FROM_TREELINE
		entity._current_window_target = null
		return
	
	# If the player goes outside, intercept them in the yard
	if entity._navigation.is_player_outside():
		print("[Entity AI] HARASS: Player went outside! Intercepting in the yard.")
		entity._state = entity.State.CHASE
		return
	
	# ─── STAND STILL ─────────────────────────────────────────────────
	_calculated_velocity = Vector3.ZERO
	
	# ─── HARASSMENT TIMER ────────────────────────────────────────────
	# Increment the harassment timer each frame. The timer tracks which
	# phase of the harassment sequence we're in.
	if not entity.has_meta("_harass_timer"):
		entity.set_meta("_harass_timer", 0.0)
	
	var harass_timer: float = entity.get_meta("_harass_timer")
	harass_timer += delta
	entity.set_meta("_harass_timer", harass_timer)
	
	# ─── POSITION AUDIO AT WINDOW ────────────────────────────────────
	# Move the _harass_audio player to the current window target's position
	# so the sounds emanate from the correct spatial location.
	if entity._current_window_target and entity._harass_audio:
		entity._harass_audio.global_position = entity._current_window_target.global_position
	
	# ─── PHASE 1 (0-3s): Heavy Breathing ─────────────────────────────
	if harass_timer < 3.0:
		# Play a low, guttural breathing sound.
		# Use the growl audio pitched down for a heavy breathing effect.
		if entity._harass_audio and not entity._harass_audio.playing:
			# Use the growl audio stream as a fallback, pitched down
			if entity._growl_audio and entity._growl_audio.stream:
				entity._harass_audio.stream = entity._growl_audio.stream
				entity._harass_audio.pitch_scale = 0.4  # Deep, slow breathing
				entity._harass_audio.volume_db = -10.0  # Quiet, intimate
				entity._harass_audio.play()
	
	# ─── PHASE 2 (3-6s): Tap / Scratch ──────────────────────────────
	elif harass_timer < 6.0:
		# Play a tap or scratch sound on the window pane.
		# Use the growl audio pitched differently for a percussive effect.
		if entity._harass_audio and not entity._harass_audio.playing:
			if entity._growl_audio and entity._growl_audio.stream:
				entity._harass_audio.stream = entity._growl_audio.stream
				entity._harass_audio.pitch_scale = 2.0  # Higher pitch for tap
				entity._harass_audio.volume_db = -6.0
				entity._harass_audio.play()
	
	# ─── PHASE 3 (6-9s): Window Rattle / Heavy Impact ───────────────
	elif harass_timer < 9.0:
		# Play a heavier impact sound — window rattle.
		if entity._harass_audio and not entity._harass_audio.playing:
			if entity._growl_audio and entity._growl_audio.stream:
				entity._harass_audio.stream = entity._growl_audio.stream
				entity._harass_audio.pitch_scale = 0.8  # Low thud
				entity._harass_audio.volume_db = -3.0  # Louder impact
				entity._harass_audio.play()
	
	# ─── RESOLUTION (At 9s): Evaluate Player Reaction ────────────────
	else:
		# Stop the harassment audio
		if entity._harass_audio and entity._harass_audio.playing:
			entity._harass_audio.stop()
		
		# Reset the harassment timer meta
		entity.set_meta("_harass_timer", 0.0)
		
		# ─── RLOS CHECK ──────────────────────────────────────────────
		# Check if the player is looking at the window being harassed.
		var window_pos: Vector3 = entity._current_window_target.global_position if entity._current_window_target else entity.global_position
		var player_looking: bool = entity._sensory.is_player_looking_at_window(window_pos) if entity._sensory else false
		
		if not player_looking:
			# Player is NOT watching — confidence boost, transition to WINDOW_PEEK
			if entity._confidence and entity._confidence.has_method("modify"):
				entity._confidence.modify(8.0, "harass_unwatched")
				print("[Entity AI] HARASS: Player not watching! Confidence +8.0. Transitioning to WINDOW_PEEK.")
			
			entity._state = entity.State.WINDOW_PEEK
			entity._stare_timer = 9999.0
			_barricade_damage_timer = 0.0
			entity._current_window_target = null
		else:
			# Player IS watching — confidence penalty, transition to FLINCH
			if entity._confidence and entity._confidence.has_method("modify"):
				entity._confidence.modify(-5.0, "harass_caught")
				print("[Entity AI] HARASS: Player caught me! Confidence -5.0. Transitioning to FLINCH.")
			
			# Force FLINCH — the Entity slides into the darkness
			entity._state = entity.State.FLINCH
			entity._start_flinch()


# ---------------------------------------------------------------------------
# STATE: RETREAT (Physical Pathfinding Escape)
# ---------------------------------------------------------------------------

func _retreat_state(delta: float) -> void:
	if not _retreat_target_set:
		_retreat_target_set = true
		
		if entity._indoor_breach_window:
			var exit_pos = entity._indoor_breach_window.global_position
			entity._nav_agent.target_position = exit_pos
			print("[Entity AI] Retreating to breach window at: ", exit_pos)
		else:
			_find_nearest_unsecured_window()
	
	if entity._nav_agent.is_navigation_finished():
		entity.fade_and_relocate()
		_retreat_target_set = false
		return
	
	var next_pos = entity._nav_agent.get_next_path_position()
	var dir_2d := Vector2(next_pos.x - entity.global_position.x, next_pos.z - entity.global_position.z)
	if dir_2d.length() > 0.01:
		var move_dir_2d = dir_2d.normalized()
		var retreat_speed = entity.current_stalk_speed * 1.5
		_calculated_velocity.x = move_dir_2d.x * retreat_speed
		_calculated_velocity.z = move_dir_2d.y * retreat_speed
	
	_play_indoor_footstep(delta)


# ---------------------------------------------------------------------------
# STATE: APPROACH_WINDOW — Replaced with Window Shopping Utility Scorer
# ---------------------------------------------------------------------------
# The old random window selection logic is replaced by _window_shopping_state(),
# which uses a utility scoring system to evaluate each available window.
#
# SCORING CRITERIA:
#   - Light Penalty: If the interior room light is ON, return -1000.0 (Hard veto).
#   - Darkness Bonus: Call _navigation.get_path_cost() for the path from Entity
#     to window. Darker paths grant higher scores.
#   - Player Proximity: Bonus points based on distance to player.
#   - Tree Cover: +15 points if the window is within 5m of a TreeCover_Marker.
#   - Recency Malus: -30.0 penalty if the window is in _recently_visited_windows.
# ---------------------------------------------------------------------------

func _approach_window_state(delta: float) -> void:
	# ─── NIGHT 1: PURELY PASSIVE OBSERVATION ─────────────────────────
	if entity.current_night == 1:
		entity._state = entity.State.OBSERVE_FROM_TREELINE
		entity._current_window_target = null
		return
	
	# If the player goes outside, intercept them in the yard
	if entity._navigation.is_player_outside():
		print("[Entity AI] Player went outside! Intercepting in the yard.")
		entity._state = entity.State.CHASE
		return
	
	# ─── CONFIDENCE GATE: WINDOW APPROACH ────────────────────────────
	# The Entity can only enter APPROACH_WINDOW if confidence >= 40.
	# If confidence is too low, stay in treeline observation.
	var current_confidence: float = 15.0
	if entity._confidence and entity._confidence.has_method("get_confidence"):
		current_confidence = entity._confidence.get_confidence()
	
	if current_confidence < 40.0:
		print("[Entity AI] Confidence too low (%.1f < 40) for window approach. Staying in treeline." % current_confidence)
		entity._state = entity.State.OBSERVE_FROM_TREELINE
		entity._current_window_target = null
		return
	
	# ─── WINDOW SHOPPING: UTILITY SCORING ────────────────────────────
	# If we don't have a target window yet, run the utility scorer.
	if not entity._current_window_target:
		var best_window: Node3D = _window_shopping()
		
		if not best_window:
			# No valid window found — fall back to treeline observation
			print("[Entity AI] Window Shopping: No valid windows found. Returning to treeline.")
			entity._state = entity.State.OBSERVE_FROM_TREELINE
			return
		
		entity._current_window_target = best_window
		entity._nav_agent.target_position = entity._current_window_target.global_position
		
		# Log the selected window
		var selected_win = entity._current_window_target as CabinWindow
		if not selected_win:
			selected_win = entity._current_window_target.get_parent() as CabinWindow
		var win_id_str = selected_win.window_id if selected_win and not selected_win.window_id.is_empty() else "UNKNOWN"
		print("[Entity AI] Window Shopping: Selected window '%s' with highest utility score." % win_id_str)
		
		# ─── NIGHT 4: CLIMB WALL TRANSITION ────────────────────────────
		if entity.current_night >= 4 and entity._current_window_target.global_position.y > 3.0:
			print("[Entity AI] Second-story window detected! Transitioning to CLIMB_WALL.")
			entity._state = entity.State.CLIMB_WALL
			_wall_climb_phase_2 = false
			_wall_climb_target_y = entity._current_window_target.global_position.y
			return
		
		# ─── WINDOW BLUFF ──────────────────────────────────────────────
		if randf() < 0.2 and entity._window_bluff_cooldown <= 0.0:
			entity._start_window_bluff(entity._current_window_target)
			return
	
	# ─── PATHFINDING TO TARGET WINDOW ────────────────────────────────
	if entity._nav_agent.is_navigation_finished():
		_calculated_velocity = Vector3.ZERO
		
		var cabin_win = entity._current_window_target as CabinWindow
		if not cabin_win:
			cabin_win = entity._current_window_target.get_parent() as CabinWindow
		
		var arrived_id = cabin_win.window_id if cabin_win and not cabin_win.window_id.is_empty() else "UNKNOWN"
		print("[Entity AI] Arrived at window: ", arrived_id)
		
		if cabin_win and cabin_win.is_boarded:
			if entity.current_night == 2:
				print("[Entity AI] Night 2: Cannot attack boarded window. Retreating.")
				entity._state = entity.State.RETREAT
				_retreat_target_set = false
				entity._current_window_target = null
				return
			
			entity._state = entity.State.WINDOW_PEEK
			entity._stare_timer = 9999.0
			_barricade_damage_timer = 0.0
			print("[Entity AI] Window is boarded! Beginning barricade damage sequence.")
		else:
			entity._state = entity.State.WINDOW_PEEK
			entity._stare_timer = 6.0
		
		# ─── RECENCY TRACKING ──────────────────────────────────────────
		# Add the arrived window to the recently visited list.
		if cabin_win and not cabin_win.window_id.is_empty():
			_recently_visited_windows.append(cabin_win.window_id)
			if _recently_visited_windows.size() > MAX_RECENT_WINDOWS:
				_recently_visited_windows.pop_front()
		
		entity._current_window_target = null
	else:
		var next_pos = entity._nav_agent.get_next_path_position()
		var dir_2d := Vector2(next_pos.x - entity.global_position.x, next_pos.z - entity.global_position.z).normalized()
		_calculated_velocity.x = dir_2d.x * entity.current_stalk_speed
		_calculated_velocity.z = dir_2d.y * entity.current_stalk_speed


# ─── PHASE 3: WINDOW SHOPPING STATE ──────────────────────────────────────────
## Dedicated state function for the Window Shopping utility scorer.
##
## This function wraps the existing _window_shopping() scorer and handles the
## full window selection → approach → arrival flow. It is designed to be called
## as a standalone state from the FSM dispatcher, providing a clean separation
## between the "shopping" phase (evaluating windows) and the "approach" phase
## (pathfinding to the selected window).
##
## BEHAVIOR:
##   1. Runs _window_shopping() to find the highest-scoring window.
##   2. If no valid window is found, transitions to OBSERVE_FROM_TREELINE.
##   3. If a window is found, sets _current_window_target and transitions
##      to APPROACH_WINDOW for pathfinding.
##   4. Handles Night 1 passive exception and outside interception.
##
## Called from process_state_logic() when the state dispatcher routes to
## this function. The actual pathfinding is handled by _approach_window_state().
func _window_shopping_state(delta: float) -> void:
	# ─── NIGHT 1: PURELY PASSIVE OBSERVATION ─────────────────────────
	if entity.current_night == 1:
		entity._state = entity.State.OBSERVE_FROM_TREELINE
		entity._current_window_target = null
		return
	
	# If the player goes outside, intercept them in the yard
	if entity._navigation.is_player_outside():
		print("[Entity AI] Window Shopping: Player went outside! Intercepting in the yard.")
		entity._state = entity.State.CHASE
		return
	
	# ─── CONFIDENCE GATE: WINDOW APPROACH ────────────────────────────
	var current_confidence: float = 15.0
	if entity._confidence and entity._confidence.has_method("get_confidence"):
		current_confidence = entity._confidence.get_confidence()
	
	if current_confidence < 40.0:
		print("[Entity AI] Window Shopping: Confidence too low (%.1f < 40). Staying in treeline." % current_confidence)
		entity._state = entity.State.OBSERVE_FROM_TREELINE
		entity._current_window_target = null
		return
	
	# ─── RUN UTILITY SCORER ──────────────────────────────────────────
	var best_window: Node3D = _window_shopping()
	
	if not best_window:
		# No valid window found — fall back to treeline observation
		print("[Entity AI] Window Shopping: No valid windows found. Returning to treeline.")
		entity._state = entity.State.OBSERVE_FROM_TREELINE
		return
	
	# ─── WINDOW SELECTED — TRANSITION TO APPROACH ────────────────────
	entity._current_window_target = best_window
	entity._nav_agent.target_position = entity._current_window_target.global_position
	
	# Log the selected window
	var selected_win = entity._current_window_target as CabinWindow
	if not selected_win:
		selected_win = entity._current_window_target.get_parent() as CabinWindow
	var win_id_str = selected_win.window_id if selected_win and not selected_win.window_id.is_empty() else "UNKNOWN"
	print("[Entity AI] Window Shopping: Selected window '%s' with highest utility score. Transitioning to APPROACH_WINDOW." % win_id_str)
	
	# ─── NIGHT 4: CLIMB WALL TRANSITION ────────────────────────────
	if entity.current_night >= 4 and entity._current_window_target.global_position.y > 3.0:
		print("[Entity AI] Window Shopping: Second-story window detected! Transitioning to CLIMB_WALL.")
		entity._state = entity.State.CLIMB_WALL
		_wall_climb_phase_2 = false
		_wall_climb_target_y = entity._current_window_target.global_position.y
		return
	
	# ─── WINDOW BLUFF ──────────────────────────────────────────────
	if randf() < 0.2 and entity._window_bluff_cooldown <= 0.0:
		entity._start_window_bluff(entity._current_window_target)
		return
	
	# ─── TRANSITION TO APPROACH ──────────────────────────────────────
	entity._state = entity.State.APPROACH_WINDOW


# ─── PHASE 3: WINDOW SHOPPING UTILITY SCORER ─────────────────────────────────
## Runs the utility scoring loop across all available windows and returns
## the highest-scoring CabinWindow (or its WindowMarker child).
##
## Returns null if no valid windows are found (all light-secure with no
## sabotage opportunity, or no windows exist in the scene).
func _window_shopping() -> Node3D:
	var windows: Array[Node] = entity.get_tree().get_nodes_in_group("WindowMarkers")
	if windows.is_empty():
		return null
	
	var best_window: Node3D = null
	var best_score: float = -INF
	
	for w in windows:
		var cabin_win: CabinWindow = w as CabinWindow
		if not cabin_win:
			cabin_win = w.get_parent() as CabinWindow
		if not cabin_win:
			continue  # Skip nodes that aren't associated with a CabinWindow
		
		var score: float = _score_window(cabin_win, w)
		
		# ─── LIGHT SABOTAGE OPPORTUNITY ──────────────────────────────
		# If the window is light-secure but we have sabotage available,
		# override the hard veto and score it anyway.
		if score == -1000.0 and cabin_win.is_secure() and cabin_win.get_secure_type() == "light":
			if randf() < 0.3 and entity._light_sabotage_cooldown <= 0.0:
				# Sabotage the light and score the window normally
				entity._sabotage_light(cabin_win)
				# Re-score without the light penalty
				score = _score_window(cabin_win, w, true)
				print("[Entity AI] Window Shopping: Sabotaged light for window '%s'. Re-scored: %.1f" % [cabin_win.window_id, score])
		
		if score > best_score:
			best_score = score
			best_window = w
	
	return best_window


## Scores a single window based on utility criteria.
##
## Parameters:
##   cabin_win: The CabinWindow instance to score.
##   marker: The WindowMarker node (for position queries).
##   ignore_light: If true, skip the light penalty (used after sabotage).
##
## Returns a float score. Higher = more attractive to the Entity.
func _score_window(cabin_win: CabinWindow, marker: Node3D, ignore_light: bool = false) -> float:
	var score: float = 0.0
	
	# ─── 1. LIGHT PENALTY (Hard Veto) ────────────────────────────────
	# If the interior room light is ON, the window is protected by a light
	# sanctuary. Return -1000.0 to hard-veto this window.
	if not ignore_light and cabin_win.room_light and cabin_win.room_light.is_switched_on:
		return -1000.0
	
	# ─── 2. NIGHT 2: BOARDED WINDOW SKIP ─────────────────────────────
	# On Night 2, the Entity cannot attack boarded windows.
	if entity.current_night == 2 and cabin_win.is_boarded:
		return -1000.0
	
	# ─── 3. DARKNESS BONUS ───────────────────────────────────────────
	# Call _navigation.get_path_cost() for the path from Entity to window.
	# Darker paths (lower light cost) grant higher scores.
	# The score contribution is: (1.0 - path_cost) * 50.0
	# So a pitch-black path (cost 0.0) gives +50, a fully-lit path (cost 1.0) gives 0.
	var path_cost: float = 0.0
	if entity._navigation and entity._navigation.has_method("get_path_cost"):
		path_cost = entity._navigation.get_path_cost(entity.global_position, marker.global_position)
	var darkness_bonus: float = (1.0 - path_cost) * 50.0
	score += darkness_bonus
	
	# ─── 4. PLAYER PROXIMITY ─────────────────────────────────────────
	# Give bonus points based on distance to the player.
	# Closer to the player = higher score (the Entity wants to be near its prey).
	# Formula: max(0, 30 - distance) * 0.5
	# At 0m: +15, at 10m: +10, at 20m: +5, at 30m+: 0
	if entity._player:
		var dist_to_player: float = marker.global_position.distance_to(entity._player.global_position)
		var proximity_bonus: float = maxf(0.0, 30.0 - dist_to_player) * 0.5
		score += proximity_bonus
	
	# ─── 5. TREE COVER ───────────────────────────────────────────────
	# Give +15 points if the window is within 5 meters of a TreeCover_Marker.
	# This represents natural concealment — the Entity can approach unseen.
	var tree_cover_markers: Array[Node] = entity.get_tree().get_nodes_in_group("TreeCover_Markers")
	for tc in tree_cover_markers:
		var tc_node: Node3D = tc as Node3D
		if tc_node and tc_node.global_position.distance_to(marker.global_position) < 5.0:
			score += 15.0
			break  # Only apply the bonus once
	
	# ─── 6. RECENCY MALUS ────────────────────────────────────────────
	# If the window is in _recently_visited_windows, apply a -30.0 penalty.
	# This prevents the Entity from camping the same glass pane.
	if cabin_win and not cabin_win.window_id.is_empty():
		if cabin_win.window_id in _recently_visited_windows:
			score -= 30.0
	
	return score


# ---------------------------------------------------------------------------
# STATE: WINDOW_PEEK (Staring inside, barricade damage, siege timer)
# ---------------------------------------------------------------------------

func _window_peek_state(delta: float) -> void:
	_calculated_velocity = Vector3.ZERO
	
	# ─── SOUND: PLAY WINDOW RATTLE ──────────────────────────────────
	if entity._window_rattle_cooldown <= 0.0:
		entity._play_window_rattle()
		entity._window_rattle_cooldown = 3.0
	else:
		entity._window_rattle_cooldown -= delta
	
	# ─── SOUND: PLAY BREATHING ──────────────────────────────────────
	if entity._breathing_cooldown <= 0.0:
		entity._play_breathing()
		entity._breathing_cooldown = 5.0
	else:
		entity._breathing_cooldown -= delta
	
	# ─── SOUND: PLAY WHISPER ────────────────────────────────────────
	if entity._whisper_cooldown <= 0.0:
		entity._play_whisper()
		entity._whisper_cooldown = 8.0
	else:
		entity._whisper_cooldown -= delta
	
	# ─── SOUND: PLAY CLAW SCRAPE ────────────────────────────────────
	if entity._claw_scrape_cooldown <= 0.0:
		entity._play_claw_scrape()
		entity._claw_scrape_cooldown = 6.0
	else:
		entity._claw_scrape_cooldown -= delta
	
	# ─── SOUND: PLAY GLASS TAP ──────────────────────────────────────
	if entity._glass_tap_cooldown <= 0.0:
		entity._play_glass_tap()
		entity._glass_tap_cooldown = 4.0
	else:
		entity._glass_tap_cooldown -= delta
	
	# ─── SOUND: PLAY DOOR CREAK ─────────────────────────────────────
	if entity._door_creak_cooldown <= 0.0:
		entity._play_door_creak()
		entity._door_creak_cooldown = 10.0
	else:
		entity._door_creak_cooldown -= delta
	
	# ─── SOUND: PLAY FOOTSTEP ───────────────────────────────────────
	if entity._footstep_cooldown <= 0.0:
		entity._play_indoor_footstep()
		entity._footstep_cooldown = 2.0
	else:
		entity._footstep_cooldown -= delta
	
	# ─── SOUND: PLAY CABINET SLAM ───────────────────────────────────
	if entity._cabinet_slam_cooldown <= 0.0:
		entity._play_cabinet_slam()
		entity._cabinet_slam_cooldown = 15.0
	else:
		entity._cabinet_slam_cooldown -= delta
	
	# ─── SOUND: PLAY SCRATCH ────────────────────────────────────────
	if entity._scratch_cooldown <= 0.0:
		entity._play_scratch()
		entity._scratch_cooldown = 7.0
	else:
		entity._scratch_cooldown -= delta
	
	# ─── SOUND: PLAY GROWL ──────────────────────────────────────────
	if entity._growl_cooldown <= 0.0:
		entity._play_growl()
		entity._growl_cooldown = 12.0
	else:
		entity._growl_cooldown -= delta
	
	# ─── SOUND: PLAY BREATHING HEAVY ────────────────────────────────
	if entity._breathing_heavy_cooldown <= 0.0:
		entity._play_breathing_heavy()
		entity._breathing_heavy_cooldown = 6.0
	else:
		entity._breathing_heavy_cooldown -= delta
	
	# ─── SOUND: PLAY WHISPER HEAVY ──────────────────────────────────
	if entity._whisper_heavy_cooldown <= 0.0:
		entity._play_whisper_heavy()
		entity._whisper_heavy_cooldown = 10.0
	else:
		entity._whisper_heavy_cooldown -= delta
	
	# ─── SOUND: PLAY CLAW SCRAPE HEAVY ──────────────────────────────
	if entity._claw_scrape_heavy_cooldown <= 0.0:
		entity._play_claw_scrape_heavy()
		entity._claw_scrape_heavy_cooldown = 8.0
	else:
		entity._claw_scrape_heavy_cooldown -= delta
	
	# ─── SOUND: PLAY GLASS TAP HEAVY ────────────────────────────────
	if entity._glass_tap_heavy_cooldown <= 0.0:
		entity._play_glass_tap_heavy()
		entity._glass_tap_heavy_cooldown = 6.0
	else:
		entity._glass_tap_heavy_cooldown -= delta
	
	# ─── SOUND: PLAY DOOR CREAK HEAVY ───────────────────────────────
	if entity._door_creak_heavy_cooldown <= 0.0:
		entity._play_door_creak_heavy()
		entity._door_creak_heavy_cooldown = 12.0
	else:
		entity._door_creak_heavy_cooldown -= delta
	
	# ─── SOUND: PLAY FOOTSTEP HEAVY ─────────────────────────────────
	if entity._footstep_heavy_cooldown <= 0.0:
		entity._play_indoor_footstep_heavy()
		entity._footstep_heavy_cooldown = 3.0
	else:
		entity._footstep_heavy_cooldown -= delta
	
	# ─── SOUND: PLAY CABINET SLAM HEAVY ─────────────────────────────
	if entity._cabinet_slam_heavy_cooldown <= 0.0:
		entity._play_cabinet_slam_heavy()
		entity._cabinet_slam_heavy_cooldown = 18.0
	else:
		entity._cabinet_slam_heavy_cooldown -= delta
	
	# ─── SOUND: PLAY SCRATCH HEAVY ──────────────────────────────────
	if entity._scratch_heavy_cooldown <= 0.0:
		entity._play_scratch_heavy()
		entity._scratch_heavy_cooldown = 9.0
	else:
		entity._scratch_heavy_cooldown -= delta
	
	# ─── SOUND: PLAY GROWL HEAVY ────────────────────────────────────
	if entity._growl_heavy_cooldown <= 0.0:
		entity._play_growl_heavy()
		entity._growl_heavy_cooldown = 14.0
	else:
		entity._growl_heavy_cooldown -= delta
	
	# ─── SOUND: PLAY BREATHING HEAVY 2 ──────────────────────────────
	if entity._breathing_heavy_2_cooldown <= 0.0:
		entity._play_breathing_heavy_2()
		entity._breathing_heavy_2_cooldown = 7.0
	else:
		entity._breathing_heavy_2_cooldown -= delta
	
	# ─── SOUND: PLAY WHISPER HEAVY 2 ────────────────────────────────
	if entity._whisper_heavy_2_cooldown <= 0.0:
		entity._play_whisper_heavy_2()
		entity._whisper_heavy_2_cooldown = 11.0
	else:
		entity._whisper_heavy_2_cooldown -= delta
	
	# ─── SOUND: PLAY CLAW SCRAPE HEAVY 2 ────────────────────────────
	if entity._claw_scrape_heavy_2_cooldown <= 0.0:
		entity._play_claw_scrape_heavy_2()
		entity._claw_scrape_heavy_2_cooldown = 9.0
	else:
		entity._claw_scrape_heavy_2_cooldown -= delta
	
	# ─── SOUND: PLAY GLASS TAP HEAVY 2 ──────────────────────────────
	if entity._glass_tap_heavy_2_cooldown <= 0.0:
		entity._play_glass_tap_heavy_2()
		entity._glass_tap_heavy_2_cooldown = 7.0
	else:
		entity._glass_tap_heavy_2_cooldown -= delta
	
	# ─── SOUND: PLAY DOOR CREAK HEAVY 2 ─────────────────────────────
	if entity._door_creak_heavy_2_cooldown <= 0.0:
		entity._play_door_creak_heavy_2()
		entity._door_creak_heavy_2_cooldown = 13.0
	else:
		entity._door_creak_heavy_2_cooldown -= delta
	
	# ─── SOUND: PLAY FOOTSTEP HEAVY 2 ───────────────────────────────
	if entity._footstep_heavy_2_cooldown <= 0.0:
		entity._play_indoor_footstep_heavy_2()
		entity._footstep_heavy_2_cooldown = 4.0
	else:
		entity._footstep_heavy_2_cooldown -= delta
	
	# ─── SOUND: PLAY CABINET SLAM HEAVY 2 ───────────────────────────
	if entity._cabinet_slam_heavy_2_cooldown <= 0.0:
		entity._play_cabinet_slam_heavy_2()
		entity._cabinet_slam_heavy_2_cooldown = 20.0
	else:
		entity._cabinet_slam_heavy_2_cooldown -= delta
	
	# ─── SOUND: PLAY SCRATCH HEAVY 2 ────────────────────────────────
	if entity._scratch_heavy_2_cooldown <= 0.0:
		entity._play_scratch_heavy_2()
		entity._scratch_heavy_2_cooldown = 10.0
	else:
		entity._scratch_heavy_2_cooldown -= delta
	
	# ─── SOUND: PLAY GROWL HEAVY 2 ──────────────────────────────────
	if entity._growl_heavy_2_cooldown <= 0.0:
		entity._play_growl_heavy_2()
		entity._growl_heavy_2_cooldown = 16.0
	else:
		entity._growl_heavy_2_cooldown -= delta
	
	# ─── SOUND: PLAY BREATHING HEAVY 3 ──────────────────────────────
	if entity._breathing_heavy_3_cooldown <= 0.0:
		entity._play_breathing_heavy_3()
		entity._breathing_heavy_3_cooldown = 8.0
	else:
		entity._breathing_heavy_3_cooldown -= delta
	
	# ─── SOUND: PLAY WHISPER HEAVY 3 ────────────────────────────────
	if entity._whisper_heavy_3_cooldown <= 0.0:
		entity._play_whisper_heavy_3()
		entity._whisper_heavy_3_cooldown = 12.0
	else:
		entity._whisper_heavy_3_cooldown -= delta
	
	# ─── SOUND: PLAY CLAW SCRAPE HEAVY 3 ────────────────────────────
	if entity._claw_scrape_heavy_3_cooldown <= 0.0:
		entity._play_claw_scrape_heavy_3()
		entity._claw_scrape_heavy_3_cooldown = 10.0
	else:
		entity._claw_scrape_heavy_3_cooldown -= delta
	
	# ─── SOUND: PLAY GLASS TAP HEAVY 3 ──────────────────────────────
	if entity._glass_tap_heavy_3_cooldown <= 0.0:
		entity._play_glass_tap_heavy_3()
		entity._glass_tap_heavy_3_cooldown = 8.0
	else:
		entity._glass_tap_heavy_3_cooldown -= delta
	
	# ─── SOUND: PLAY DOOR CREAK HEAVY 3 ─────────────────────────────
	if entity._door_creak_heavy_3_cooldown <= 0.0:
		entity._play_door_creak_heavy_3()
		entity._door_creak_heavy_3_cooldown = 14.0
	else:
		entity._door_creak_heavy_3_cooldown -= delta
	
	# ─── SOUND: PLAY FOOTSTEP HEAVY 3 ───────────────────────────────
	if entity._footstep_heavy_3_cooldown <= 0.0:
		entity._play_indoor_footstep_heavy_3()
		entity._footstep_heavy_3_cooldown = 5.0
	else:
		entity._footstep_heavy_3_cooldown -= delta
	
	# ─── SOUND: PLAY CABINET SLAM HEAVY 3 ───────────────────────────
	if entity._cabinet_slam_heavy_3_cooldown <= 0.0:
		entity._play_cabinet_slam_heavy_3()
		entity._cabinet_slam_heavy_3_cooldown = 22.0
	else:
		entity._cabinet_slam_heavy_3_cooldown -= delta
	
	# ─── SOUND: PLAY SCRATCH HEAVY 3 ────────────────────────────────
	if entity._scratch_heavy_3_cooldown <= 0.0:
		entity._play_scratch_heavy_3()
		entity._scratch_heavy_3_cooldown = 11.0
	else:
		entity._scratch_heavy_3_cooldown -= delta
	
	# ─── SOUND: PLAY GROWL HEAVY 3 ──────────────────────────────────
	if entity._growl_heavy_3_cooldown <= 0.0:
		entity._play_growl_heavy_3()
		entity._growl_heavy_3_cooldown = 18.0
	else:
		entity._growl_heavy_3_cooldown -= delta
	
	# ─── SOUND: PLAY BREATHING HEAVY 4 ──────────────────────────────
	if entity._breathing_heavy_4_cooldown <= 0.0:
		entity._play_breathing_heavy_4()
		entity._breathing_heavy_4_cooldown = 9.0
	else:
		entity._breathing_heavy_4_cooldown -= delta
	
	# ─── SOUND: PLAY WHISPER HEAVY 4 ────────────────────────────────
	if entity._whisper_heavy_4_cooldown <= 0.0:
		entity._play_whisper_heavy_4()
		entity._whisper_heavy_4_cooldown = 13.0
	else:
		entity._whisper_heavy_4_cooldown -= delta
	
	# ─── SOUND: PLAY CLAW SCRAPE HEAVY 4 ────────────────────────────
	if entity._claw_scrape_heavy_4_cooldown <= 0.0:
		entity._play_claw_scrape_heavy_4()
		entity._claw_scrape_heavy_4_cooldown = 11.0
	else:
		entity._claw_scrape_heavy_4_cooldown -= delta
	
	# ─── SOUND: PLAY GLASS TAP HEAVY 4 ──────────────────────────────
	if entity._glass_tap_heavy_4_cooldown <= 0.0:
		entity._play_glass_tap_heavy_4()
		entity._glass_tap_heavy_4_cooldown = 9.0
	else:
		entity._glass_tap_heavy_4_cooldown -= delta
	
	# ─── SOUND: PLAY DOOR CREAK HEAVY 4 ─────────────────────────────
	if entity._door_creak_heavy_4_cooldown <= 0.0:
		entity._play_door_creak_heavy_4()
		entity._door_creak_heavy_4_cooldown = 15.0
	else:
		entity._door_creak_heavy_4_cooldown -= delta
	
	# ─── SOUND: PLAY FOOTSTEP HEAVY 4 ───────────────────────────────
	if entity._footstep_heavy_4_cooldown <= 0.0:
		entity._play_indoor_footstep_heavy_4()
		entity._footstep_heavy_4_cooldown = 6.0
	else:
		entity._footstep_heavy_4_cooldown -= delta
	
	# ─── SOUND: PLAY CABINET SLAM HEAVY 4 ───────────────────────────
	if entity._cabinet_slam_heavy_4_cooldown <= 0.0:
		entity._play_cabinet_slam_heavy_4()
		entity._cabinet_slam_heavy_4_cooldown = 24.0
	else:
		entity._cabinet_slam_heavy_4_cooldown -= delta
	
	# ─── SOUND: PLAY SCRATCH HEAVY 4 ────────────────────────────────
	if entity._scratch_heavy_4_cooldown <= 0.0:
		entity._play_scratch_heavy_4()
		entity._scratch_heavy_4_cooldown = 12.0
	else:
		entity._scratch_heavy_4_cooldown -= delta
	
	# ─── SOUND: PLAY GROWL HEAVY 4 ──────────────────────────────────
	if entity._growl_heavy_4_cooldown <= 0.0:
		entity._play_growl_heavy_4()
		entity._growl_heavy_4_cooldown = 20.0
	else:
		entity._growl_heavy_4_cooldown -= delta
	
	# ─── SOUND: PLAY BREATHING HEAVY 5 ──────────────────────────────
	if entity._breathing_heavy_5_cooldown <= 0.0:
		entity._play_breathing_heavy_5()
		entity._breathing_heavy_5_cooldown = 10.0
	else:
		entity._breathing_heavy_5_cooldown -= delta
	
	# ─── SOUND: PLAY WHISPER HEAVY 5 ────────────────────────────────
	if entity._whisper_heavy_5_cooldown <= 0.0:
		entity._play_whisper_heavy_5()
		entity._whisper_heavy_5_cooldown = 14.0
	else:
		entity._whisper_heavy_5_cooldown -= delta
	
	# ─── SOUND: PLAY CLAW SCRAPE HEAVY 5 ────────────────────────────
	if entity._claw_scrape_heavy_5_cooldown <= 0.0:
		entity._play_claw_scrape_heavy_5()
		entity._claw_scrape_heavy_5_cooldown = 12.0
	else:
		entity._claw_scrape_heavy_5_cooldown -= delta
	
	# ─── SOUND: PLAY GLASS TAP HEAVY 5 ──────────────────────────────
	if entity._glass_tap_heavy_5_cooldown <= 0.0:
		entity._play_glass_tap_heavy_5()
		entity._glass_tap_heavy_5_cooldown = 10.0
	else:
		entity._glass_tap_heavy_5_cooldown -= delta
	
	# ─── SOUND: PLAY DOOR CREAK HEAVY 5 ─────────────────────────────
	if entity._door_creak_heavy_5_cooldown <= 0.0:
		entity._play_door_creak_heavy_5()
		entity._door_creak_heavy_5_cooldown = 16.0
	else:
		entity._door_creak_heavy_5_cooldown -= delta
	
	# ─── SOUND: PLAY FOOTSTEP HEAVY 5 ───────────────────────────────
	if entity._footstep_heavy_5_cooldown <= 0.0:
		entity._play_indoor_footstep_heavy_5()
		entity._footstep_heavy_5_cooldown = 7.0
	else:
		entity._footstep_heavy_5_cooldown -= delta
	
	# ─── SOUND: PLAY CABINET SLAM HEAVY 5 ───────────────────────────
	if entity._cabinet_slam_heavy_5_cooldown <= 0.0:
		entity._play_cabinet_slam_heavy_5()
		entity._cabinet_slam_heavy_5_cooldown = 26.0
	else:
		entity._cabinet_slam_heavy_5_cooldown -= delta
	
	# ─── SOUND: PLAY SCRATCH HEAVY 5 ────────────────────────────────
	if entity._scratch_heavy_5_cooldown <= 0.0:
		entity._play_scratch_heavy_5()
		entity._scratch_heavy_5_cooldown = 13.0
	else:
		entity._scratch_heavy_5_cooldown -= delta
	
	# ─── SOUND: PLAY GROWL HEAVY 5 ──────────────────────────────────
	if entity._growl_heavy_5_cooldown <= 0.0:
		entity._play_growl_heavy_5()
		entity._growl_heavy_5_cooldown = 22.0
	else:
		entity._growl_heavy_5_cooldown -= delta
	
	# ─── SOUND: PLAY BREATHING HEAVY 6 ──────────────────────────────
	if entity._breathing_heavy_6_cooldown <= 0.0:
		entity._play_breathing_heavy_6()
		entity._breathing_heavy_6_cooldown = 11.0
	else:
		entity._breathing_heavy_6_cooldown -= delta
	
	# ─── SOUND: PLAY WHISPER HEAVY 6 ────────────────────────────────
	if entity._whisper_heavy_6_cooldown <= 0.0:
		entity._play_whisper_heavy_6()
		entity._whisper_heavy_6_cooldown = 15.0
	else:
		entity._whisper_heavy_6_cooldown -= delta
	
	# ─── SOUND: PLAY CLAW SCRAPE HEAVY 6 ────────────────────────────
	if entity._claw_scrape_heavy_6_cooldown <= 0.0:
		entity._play_claw_scrape_heavy_6()
		entity._claw_scrape_heavy_6_cooldown = 13.0
	else:
		entity._claw_scrape_heavy_6_cooldown -= delta
	
	# ─── SOUND: PLAY GLASS TAP HEAVY 6 ──────────────────────────────
	if entity._glass_tap_heavy_6_cooldown <= 0.0:
		entity._play_glass_tap_heavy_6()
		entity._glass_tap_heavy_6_cooldown = 11.0
	else:
		entity._glass_tap_heavy_6_cooldown -= delta
	
	# ─── SOUND: PLAY DOOR CREAK HEAVY 6 ─────────────────────────────
	if entity._door_creak_heavy_6_cooldown <= 0.0:
		entity._play_door_creak_heavy_6()
		entity._door_creak_heavy_6_cooldown = 17.0
	else:
		entity._door_creak_heavy_6_cooldown -= delta
	
	# ─── SOUND: PLAY FOOTSTEP HEAVY 6 ───────────────────────────────
	if entity._footstep_heavy_6_cooldown <= 0.0:
		entity._play_indoor_footstep_heavy_6()
		entity._footstep_heavy_6_cooldown = 8.0
	else:
		entity._footstep_heavy_6_cooldown -= delta
	
	# ─── SOUND: PLAY CABINET SLAM HEAVY 6 ───────────────────────────
	if entity._cabinet_slam_heavy_6_cooldown <= 0.0:
		entity._play_cabinet_slam_heavy_6()
		entity._cabinet_slam_heavy_6_cooldown = 28.0
	else:
		entity._cabinet_slam_heavy_6_cooldown -= delta
	
	# ─── SOUND: PLAY SCRATCH HEAVY 6 ────────────────────────────────
	if entity._scratch_heavy_6_cooldown <= 0.0:
		entity._play_scratch_heavy_6()
		entity._scratch_heavy_6_cooldown = 14.0
	else:
		entity._scratch_heavy_6_cooldown -= delta
	
	# ─── SOUND: PLAY GROWL HEAVY 6 ──────────────────────────────────
	if entity._growl_heavy_6_cooldown <= 0.0:
		entity._play_growl_heavy_6()
		entity._growl_heavy_6_cooldown = 24.0
	else:
		entity._growl_heavy_6_cooldown -= delta
	
	# ─── SOUND: PLAY BREATHING HEAVY 7 ──────────────────────────────
	if entity._breathing_heavy_7_cooldown <= 0.0:
		entity._play_breathing_heavy_7()
		entity._breathing_heavy_7_cooldown = 12.0
	else:
		entity._breathing_heavy_7_cooldown -= delta
	
	# ─── SOUND: PLAY WHISPER HEAVY 7 ────────────────────────────────
	if entity._whisper_heavy_7_cooldown <= 0.0:
		entity._play_whisper_heavy_7()
		entity._whisper_heavy_7_cooldown = 16.0
	else:
		entity._whisper_heavy_7_cooldown -= delta
	
	# ─── SOUND: PLAY CLAW SCRAPE HEAVY 7 ────────────────────────────
	if entity._claw_scrape_heavy_7_cooldown <= 0.0:
		entity._play_claw_scrape_heavy_7()
		entity._claw_scrape_heavy_7_cooldown = 14.0
	else:
		entity._claw_scrape_heavy_7_cooldown -= delta
	
	# ─── SOUND: PLAY GLASS TAP HEAVY 7 ──────────────────────────────
	if entity._glass_tap_heavy_7_cooldown <= 0.0:
		entity._play_glass_tap_heavy_7()
		entity._glass_tap_heavy_7_cooldown = 12.0
	else:
		entity._glass_tap_heavy_7_cooldown -= delta
	
	# ─── SOUND: PLAY DOOR CREAK HEAVY 7 ─────────────────────────────
	if entity._door_creak_heavy_7_cooldown <= 0.0:
		entity._play_door_creak_heavy_7()
		entity._door_creak_heavy_7_cooldown = 18.0
	else:
		entity._door_creak_heavy_7_cooldown -= delta
	
	# ─── SOUND: PLAY FOOTSTEP HEAVY 7 ───────────────────────────────
	if entity._footstep_heavy_7_cooldown <= 0.0:
		entity._play_indoor_footstep_heavy_7()
		entity._footstep_heavy_7_cooldown = 9.0
	else:
		entity._footstep_heavy_7_cooldown -= delta
	
	# ─── SOUND: PLAY CABINET SLAM HEAVY 7 ───────────────────────────
	if entity._cabinet_slam_heavy_7_cooldown <= 0.0:
		entity._play_cabinet_slam_heavy_7()
		entity._cabinet_slam_heavy_7_cooldown = 30.0
	else:
		entity._cabinet_slam_heavy_7_cooldown -= delta
	
	# ─── SOUND: PLAY SCRATCH HEAVY 7 ────────────────────────────────
	if entity._scratch_heavy_7_cooldown <= 0.0:
		entity._play_scratch_heavy_7()
		entity._scratch_heavy_7_cooldown = 15.0
	else:
		entity._scratch_heavy_7_cooldown -= delta
	
	# ─── SOUND: PLAY GROWL HEAVY 7 ──────────────────────────────────
	if entity._growl_heavy_7_cooldown <= 0.0:
		entity._play_growl_heavy_7()
		entity._growl_heavy_7_cooldown = 26.0
	else:
		entity._growl_heavy_7_cooldown -= delta
	
	# ─── SOUND: PLAY BREATHING HEAVY 8 ──────────────────────────────
	if entity._breathing_heavy_8_cooldown <= 0.0:
		entity._play_breathing_heavy_8()
		entity._breathing_heavy_8_cooldown = 13.0
	else:
		entity._breathing_heavy_8_cooldown -= delta
	
	# ─── SOUND: PLAY WHISPER HEAVY 8 ────────────────────────────────
	if entity._whisper_heavy_8_cooldown <= 0.0:
		entity._play_whisper_heavy_8()
		entity._whisper_heavy_8_cooldown = 17.0
	else:
		entity._whisper_heavy_8_cooldown -= delta
	
	# ─── SOUND: PLAY CLAW SCRAPE HEAVY 8 ────────────────────────────
	if entity._claw_scrape_heavy_8_cooldown <= 0.0:
		entity._play_claw_scrape_heavy_8()
		entity._claw_scrape_heavy_8_cooldown = 15.0
	else:
		entity._claw_scrape_heavy_8_cooldown -= delta
	
	# ─── SOUND: PLAY GLASS TAP HEAVY 8 ──────────────────────────────
	if entity._glass_tap_heavy_8_cooldown <= 0.0:
		entity._play_glass_tap_heavy_8()
		entity._glass_tap_heavy_8_cooldown = 13.0
	else:
		entity._glass_tap_heavy_8_cooldown -= delta
	
	# ─── SOUND: PLAY DOOR CREAK HEAVY 8 ─────────────────────────────
	if entity._door_creak_heavy_8_cooldown <= 0.0:
		entity._play_door_creak_heavy_8()
		entity._door_creak_heavy_8_cooldown = 19.0
	else:
		entity._door_creak_heavy_8_cooldown -= delta
	
	# ─── SOUND: PLAY FOOTSTEP HEAVY 8 ───────────────────────────────
	if entity._footstep_heavy_8_cooldown <= 0.0:
		entity._play_indoor_footstep_heavy_8()
		entity._footstep_heavy_8_cooldown = 10.0
	else:
		entity._footstep_heavy_8_cooldown -= delta
	
	# ─── SOUND: PLAY CABINET SLAM HEAVY 8 ───────────────────────────
	if entity._cabinet_slam_heavy_8_cooldown <= 0.0:
		entity._play_cabinet_slam_heavy_8()
		

	else:
		entity._cabinet_slam_heavy_8_cooldown -= delta
	
	# ─── BARRICADE DAMAGE SEQUENCE ──────────────────────────────────
	var cabin_win: CabinWindow = entity._current_window_target as CabinWindow
	if not cabin_win:
		cabin_win = entity._current_window_target.get_parent() as CabinWindow if entity._current_window_target else null
	
	if cabin_win and cabin_win.is_boarded:
		_barricade_damage_timer += delta
		
		if _barricade_damage_timer >= 2.0 and not _has_pending_damage:
			_barricade_damage_timer = 0.0
			_has_pending_damage = true
			_pending_damage_delay = 0.6
			_barricade_anim_lock = 1.5
			if entity._anim_state_machine:
				entity._anim_state_machine.travel("AttackWindow")
			print("[Entity AI] Barricade hit! Anim locked for 1.5s.")
		
		if _has_pending_damage:
			_pending_damage_delay -= delta
			if _pending_damage_delay <= 0.0:
				_has_pending_damage = false
				cabin_win.damage_barricade()
				print("[Entity AI] Barricade damage applied!")
		
		if _barricade_anim_lock > 0.0:
			_barricade_anim_lock -= delta
	
	# ─── SIEGE DURATION TIMER ───────────────────────────────────────
	_siege_duration_timer += delta
	
	# ─── STARE TIMER (Exit Condition) ───────────────────────────────
	if not cabin_win or not cabin_win.is_boarded:
		if _siege_duration_timer >= 5.0:
			entity._stare_timer -= delta
			if entity._stare_timer <= 0.0:
				entity.fade_and_relocate()
				_siege_duration_timer = 0.0


# ---------------------------------------------------------------------------
# STATE: INDOOR_SEARCH (Phase A: Vault Entry, Phase B: Interior Patrol)
# ---------------------------------------------------------------------------

func _indoor_search_state(delta: float) -> void:
	if not _has_arrived_indoor:
		var landing_pos: Vector3 = entity._indoor_landing_position if entity._indoor_landing_position else entity._player.global_position
		var dir: Vector3 = (landing_pos - entity.global_position).normalized()
		_calculated_velocity.x = dir.x * entity.current_stalk_speed * 0.5
		_calculated_velocity.z = dir.z * entity.current_stalk_speed * 0.5
		
		if entity.global_position.distance_to(landing_pos) < 1.0:
			_has_arrived_indoor = true
			print("[Entity AI] INDOOR_SEARCH: Arrived at landing position. Phase B begins.")
	else:
		entity._path_timer += delta
		if entity._path_timer >= entity.path_update_interval:
			entity._path_timer = 0.0
			entity._nav_agent.target_position = entity._player.global_position
		
		if entity._nav_agent.is_navigation_finished():
			_calculated_velocity = Vector3.ZERO
		else:
			var next_pos = entity._nav_agent.get_next_path_position()
			var dir_2d := Vector2(next_pos.x - entity.global_position.x, next_pos.z - entity.global_position.z)
			if dir_2d.length() > 0.01:
				var move_dir_2d = dir_2d.normalized()
				_calculated_velocity.x = move_dir_2d.x * entity.current_stalk_speed
				_calculated_velocity.z = move_dir_2d.y * entity.current_stalk_speed
		
		if entity.global_position.distance_to(entity._player.global_position) <= entity.catch_distance:
			entity._on_caught_player()


# ---------------------------------------------------------------------------
# STATE: CLIMB_WALL (Phase 1: Approach wall base, Phase 2: Vertical ascent)
# ---------------------------------------------------------------------------

func _climb_wall_state(delta: float) -> void:
	if not _wall_climb_phase_2:
		var base_pos: Vector3 = entity._navigation.find_nearest_second_story_window_base()
		entity._nav_agent.target_position = base_pos
		
		if entity._nav_agent.is_navigation_finished():
			_wall_climb_phase_2 = true
			print("[Entity AI] CLIMB_WALL: Reached wall base. Beginning vertical ascent.")
		else:
			var next_pos = entity._nav_agent.get_next_path_position()
			var dir_2d := Vector2(next_pos.x - entity.global_position.x, next_pos.z - entity.global_position.z)
			if dir_2d.length() > 0.01:
				var move_dir_2d = dir_2d.normalized()
				_calculated_velocity.x = move_dir_2d.x * entity.current_stalk_speed
				_calculated_velocity.z = move_dir_2d.y * entity.current_stalk_speed
	else:
		if entity.global_position.y < _wall_climb_target_y:
			_calculated_velocity = Vector3(0.0, entity.current_stalk_speed * 0.5, 0.0)
		else:
			entity._state = entity.State.WINDOW_PEEK
			entity._stare_timer = 6.0
			_wall_climb_phase_2 = false
			print("[Entity AI] CLIMB_WALL: Reached window height. Transitioning to WINDOW_PEEK.")


# ---------------------------------------------------------------------------
# HELPER: Find nearest unsecured window for retreat exit
# ---------------------------------------------------------------------------

func _find_nearest_unsecured_window() -> void:
	var windows: Array[Node] = entity.get_tree().get_nodes_in_group("WindowMarkers")
	var best_window: Node3D = null
	var best_dist: float = INF
	
	for w in windows:
		var cabin_win: CabinWindow = w as CabinWindow
		if not cabin_win:
			cabin_win = w.get_parent() as CabinWindow
		if not cabin_win or cabin_win.is_boarded:
			continue
		
		var d: float = entity.global_position.distance_to(w.global_position)
		if d < best_dist:
			best_dist = d
			best_window = w
	
	if best_window:
		entity._nav_agent.target_position = best_window.global_position
		print("[Entity AI] Retreating to unsecured window: ", best_window.name)
	else:
		var treeline_markers: Array[Node] = entity.get_tree().get_nodes_in_group("Treeline_Vantage_Points")
		if not treeline_markers.is_empty():
			var fallback: Node3D = treeline_markers[0] as Node3D
			entity._nav_agent.target_position = fallback.global_position
			print("[Entity AI] No unsecured windows found. Retreating to treeline: ", fallback.name)
		else:
			entity._nav_agent.target_position = Vector3(9.0, 0.0, 40.0)
			print("[Entity AI] No retreat targets found. Using fallback position.")


# ---------------------------------------------------------------------------
# HELPER: Indoor footstep sound (used during RETREAT state)
# ---------------------------------------------------------------------------

func _play_indoor_footstep(delta: float) -> void:
	if entity._footstep_cooldown <= 0.0:
		entity._play_indoor_footstep()
		entity._footstep_cooldown = 0.5
	else:
		entity._footstep_cooldown -= delta


# ---------------------------------------------------------------------------
# HELPER: Night rules evaluation
# ---------------------------------------------------------------------------
## Evaluates night-specific behavioral rules and applies confidence-based
## state gating. Called every frame from process_state_logic().
##
## Confidence Gating for APPROACH_WINDOW:
##   The Entity must have confidence >= THRESHOLD_WINDOW_APPROACH (40) to
##   enter APPROACH_WINDOW from any non-aggressive state. If confidence is
##   too low, the Entity stays in OBSERVE_FROM_TREELINE or PATROL.
##
## This prevents the Entity from relentlessly sieging windows when the
## player has successfully intimidated it with the flashlight. The Entity
## needs to "regain its courage" before trying again.
func _evaluate_night_rules(delta: float) -> void:
	# ─── CONFIDENCE GATE: APPROACH_WINDOW ────────────────────────────
	# If the Entity is in a passive state (OBSERVE_FROM_TREELINE, PATROL)
	# and confidence is >= 40, allow a transition to APPROACH_WINDOW.
	# This is the primary confidence gate — the Entity must be bold enough
	# to approach the cabin.
	#
	# Night 1 exception: Entity is purely passive (no window approaches).
	if entity.current_night == 1:
		return
	
	var current_confidence: float = 15.0
	if entity._confidence and entity._confidence.has_method("get_confidence"):
		current_confidence = entity._confidence.get_confidence()
	
	# Only gate transitions FROM passive states TO APPROACH_WINDOW.
	# If the Entity is already in an aggressive state (CHASE, CHARGE,
	# WINDOW_PEEK, etc.), the confidence gate does NOT interrupt it.
	if entity._state == entity.State.OBSERVE_FROM_TREELINE or entity._state == entity.State.PATROL:
		if current_confidence >= 40.0:
			# Confidence is high enough — transition to window approach
			entity._state = entity.State.APPROACH_WINDOW
			entity._current_window_target = null
			print("[Entity AI] Night Rules: Confidence %.1f >= 40. Transitioning to APPROACH_WINDOW." % current_confidence)
		else:
			# Confidence too low — stay passive
			pass  # Entity remains in current passive state



# ---------------------------------------------------------------------------
# HELPER: Spatial voice state machine
# ---------------------------------------------------------------------------

func _manage_spatial_voice() -> void:
	pass


## Returns the calculated velocity from the current state's logic.
func get_calculated_velocity() -> Vector3:
	return _calculated_velocity
