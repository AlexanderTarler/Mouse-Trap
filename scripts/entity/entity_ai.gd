extends Node

## Entity AI — Finite State Machine behaviors for the Entity.
## Receives a reference to the parent entity_controller to read/write shared state.
## Called from entity_controller._physics_process() each frame.

var entity: CharacterBody3D = null

var current_exposure: float = 0.0
var exposure_tolerance: float = 0.2

## Timer for damaging window barricades (accumulates delta while at a boarded window)
var _barricade_damage_timer: float = 0.0


func setup(parent: CharacterBody3D) -> void:
	entity = parent


## Main update tick — dispatches to the correct state function.
func update(delta: float) -> void:
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
		_:
			entity.velocity = Vector3.ZERO


# ---------------------------------------------------------------------------
# STATE: OBSERVE_FROM_TREELINE
# ---------------------------------------------------------------------------

func _observe_from_treeline_state(delta: float) -> void:
	# --- STARE TIMER ---
	# After staring at a vantage point for a while, fade and relocate.
	entity._stare_timer -= delta
	if entity._stare_timer <= 0.0:
		entity.fade_and_relocate()


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
# STATE: RETREAT
# ---------------------------------------------------------------------------

func _retreat_state(delta: float) -> void:
	# Zero out velocity immediately — no physical running.
	# The entity.fade_and_relocate() call handles the visual fade,
	# the void timer, and the final state reset.
	entity.velocity = Vector3.ZERO
	print("[Entity AI] RETREAT state triggered. Initiating fade-and-relocate.")
	entity.fade_and_relocate()


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
	
	if entity._nav_agent.is_navigation_finished():
		entity.velocity = Vector3.ZERO
		
		# Check if the arrived window is a CabinWindow with barricade planks.
		# The marker may be a child node of the CabinWindow, so fall back to the parent.
		var cabin_win = entity._current_window_target as CabinWindow
		if not cabin_win:
			cabin_win = entity._current_window_target.get_parent() as CabinWindow
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
	# --- BARRICADE DAMAGE SEQUENCE ---
	# If the Entity is at a boarded window, it pauses and damages the planks.
	# The stare timer is set to 9999.0 when barricade damage begins, so the
	# Entity stays until the planks break or it's interrupted.
	if _barricade_damage_timer >= 0.0:
		# Find the nearest CabinWindow to damage
		var windows = entity.get_tree().get_nodes_in_group("WindowMarkers")
		var nearest_win: CabinWindow = null
		var nearest_dist = INF
		for w in windows:
			var cw = w as CabinWindow
			if not cw:
				cw = w.get_parent() as CabinWindow
			if cw and cw.is_boarded:
				var d = entity.global_position.distance_to(w.global_position)
				if d < nearest_dist:
					nearest_dist = d
					nearest_win = cw
		
		if nearest_win and nearest_dist < 5.0:
			# Accumulate damage over time
			_barricade_damage_timer += delta
			if _barricade_damage_timer >= 0.5:  # Damage every 0.5 seconds
				_barricade_damage_timer = 0.0
				
				# --- AUDIO TELEGRAPH: Wood-splintering sound at the window ---
				# Play a loud AudioStreamPlayer3D at the window's position so the
				# player can hear their defenses breaking from anywhere in the house.
				var splinter_sound = nearest_win.get_node_or_null("BarricadeDamageAudio")
				if splinter_sound and splinter_sound is AudioStreamPlayer3D:
					splinter_sound.play()
				
				var destroyed = nearest_win.damage_barricade(delta * 2.0)  # 2x speed for feel
				if destroyed:
					print("[Entity AI] Barricade destroyed! Window is now open.")
					entity._stare_timer = 3.0  # Short peek then move on
					_barricade_damage_timer = -1.0  # Reset damage state
		else:
			# No boarded window nearby — fall through to normal peek behavior
			_barricade_damage_timer = -1.0
	
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
# NIGHT DIFFICULTY
# ---------------------------------------------------------------------------

func setup_night_difficulty(night: int) -> void:
	entity.current_night = night
	entity.current_stalk_speed = 3.5 + (night - 1) * 0.6
	entity.current_relocate_cooldown = maxf(0.7, 3.0 - (night - 1) * 0.5)
	entity.window_peek_chance = maxf(0.05, 0.70 - (night - 1) * 0.15)
	
	# Exposure tolerance scales with difficulty.
	# Higher values = harder to repel with flashlight.
	# Night 5 is essentially immune (99999 = cannot be repelled).
	if night == 1:
		exposure_tolerance = 0.2
	elif night == 2:
		exposure_tolerance = 1.0
	elif night == 3:
		exposure_tolerance = 2.5
	elif night == 4:
		exposure_tolerance = 4.0
		entity.current_stalk_speed = 5.3
	elif night == 5:
		exposure_tolerance = 99999.0
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
