extends RigidBody3D
class_name PortableLamp

## PortableLamp — Deployable high-voltage lamp trap (physics-based carry).
##
## The player finds this lamp as a physical object in the world. They hold E
## to pick it up (via PhysicalGrab), carry it in real space, and press E again
## to drop/deploy it. Once deployed on the ground, the computer terminal's
## "EXECUTE OVERLOAD" command targets this lamp instead of the porch light.
##
## When overloaded, the lamp spikes its energy_drain_rate to 50.0 and boosts
## its light to blinding intensity, forcing the generator to burn through fuel
## at a catastrophic rate. The Entity is attracted to the deployed lamp and
## will pathfind toward it during OBSERVE_FROM_TREELINE and PATROL states.
##
## POWER CABLE NOTE:
## The cable system has been extracted into a standalone PowerCable scene/script
## (objects/power_cable.gd). This lamp no longer manages its own cable geometry.
## A PowerCable instance connects to this lamp via connect_to_lamp(), setting
## is_powered = true.

## Whether this lamp has been placed on the ground by the player.
var is_deployed: bool = false

## Whether the overload has been triggered on this lamp.
var is_overloaded: bool = false

## Number of physical hits the Entity has landed on this lamp.
## Incremented by take_physical_hit(). When it reaches 3, the cable is
## forcibly disconnected and the counter resets.
var attack_strikes: int = 0


## Whether this lamp is powered by the generator via the PowerCable.
## Set to true when the player connects the cable to this lamp's base.
var is_powered: bool = false

## Whether the player is currently carrying this lamp.
var is_being_carried: bool = false

## Fuel drain rate contributed to the generator while deployed.
## Set to 0.0 when idle; spiked to 50.0 during overload.
var energy_drain_rate: float = 0.0

## The original drain rate before the overload spike.
## Used to restore the normal rate if the overload is ever reset.
var _original_drain_rate: float = 0.0

## Reference to the hand marker node where the lamp sits while carried.
## Set by PhysicalGrab when pick_up() is called.
var _hand_marker: Marker3D = null

## Reference to the OmniLight3D child node for intensity control.
@onready var lamp_light: OmniLight3D = $OmniLight3D

## Reference to the LampMesh for visibility control.
@onready var lamp_mesh: MeshInstance3D = $LampMesh

## Reference to the AggroRadius Area3D for Entity attraction detection.
@onready var aggro_radius: Area3D = $AggroRadius

## The collision layers the lamp normally collides with (saved for restore).
var _saved_collision_mask: int = 0

## The collision layers the lamp normally belongs to (saved for restore).
var _saved_collision_layer: int = 0


func _ready() -> void:
	add_to_group("portable_trap")
	
	# Save the original collision mask/layer so we can restore them on drop
	_saved_collision_mask = collision_mask
	_saved_collision_layer = collision_layer
	
	# Start with the light off — it only turns on when deployed
	if lamp_light:
		lamp_light.visible = false
	
	# ─── AGGRORADIUS CONFIGURATION ────────────────────────────────────────
	# The AggroRadius Area3D is a pure detection zone — it should NOT collide
	# with anything physically. We configure it to only detect the Entity
	# (assumed to be on collision layer 2) and ignore everything else.
	#
	# Collision Layer: 0 (not on any layer — Area3Ds don't need to be on a
	#   layer to detect overlaps; they only need the mask to specify targets)
	# Collision Mask: 2 (only detect nodes on layer 2, i.e. the Entity)
	# Monitorable: false (prevents other areas from detecting this one)
	if aggro_radius:
		aggro_radius.collision_layer = 0
		aggro_radius.collision_mask = 2
		aggro_radius.monitorable = false


## Public API: Called by InteractionManager when the player quick-taps E
## while looking at the lamp.
##
## BEHAVIOR:
## If the lamp is deployed and there's an active PowerCable in
## PLUGGED_TO_SOURCE state (free end in player's hand), this connects
## the cable to the lamp, setting is_powered = true.
## The light does NOT turn on automatically — it must be toggled remotely
## from the computer terminal via toggle_power().
##
## To pick up the lamp, the player must hold E (0.5s) — the PhysicalGrab
## hold path will grab it as a RigidBody3D (or via the portable_trap group).
func interact() -> void:
	# Don't interact if already being carried (shouldn't happen, but guard)
	if is_being_carried:
		return
	
	# ─── CABLE CONNECTION CHECK ──────────────────────────────────────────
	# If the lamp is deployed and there's an active PowerCable in
	# PLUGGED_TO_SOURCE state, connect the cable to this lamp.
	if is_deployed:
		var cable: Node = _find_active_cable()
		if cable and cable.has_method("connect_to_lamp"):
			cable.connect_to_lamp(self)
			print("[PortableLamp] Cable connected to lamp!")
			return



## Finds an active PowerCable in PLUGGED_TO_SOURCE state that the player
## is currently dragging (free end in hand).
func _find_active_cable() -> Node:
	var cables: Array[Node] = get_tree().get_nodes_in_group("power_cable")
	for cable in cables:
		if cable.has_method("get_state"):
			var state = cable.get_state()
			# Only connect if the cable is in PLUGGED_TO_SOURCE state
			# (free end is in the player's hand, not yet connected to a lamp)
			if state == 1:  # CableState.PLUGGED_TO_SOURCE == 1
				return cable
	return null



## Public API: Called by PhysicalGrab when the player picks up the lamp.
##
## 1. Sets is_being_carried = true
## 2. Freezes physics so the lamp doesn't fall or collide while held
## 3. Saves the hand marker reference for the lerp loop
## 4. Removes the lamp from the "portable_trap" group temporarily so the
##    Entity doesn't pathfind toward it while the player is carrying it
## 5. Excludes the player's collision layer so the lamp doesn't violently
##    collide with the player's capsule collider while held
func pick_up(hand_marker: Marker3D) -> void:
	if is_being_carried:
		return
	
	is_being_carried = true
	_hand_marker = hand_marker
	
	# Freeze physics so the lamp doesn't fall or collide while held
	freeze = true
	freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	
	# Stop any existing motion
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	
	# Remove from the portable_trap group so the Entity doesn't pathfind
	# toward the lamp while the player is carrying it
	remove_from_group("portable_trap")
	
	# Exclude the player collision layer (layer 1) so the lamp doesn't
	# collide with the player's capsule collider while held
	collision_mask = _saved_collision_mask & ~1
	
	print("[PortableLamp] Picked up by player.")


## Public API: Called by PhysicalGrab when the player releases the lamp.
##
## 1. Sets is_being_carried = false
## 2. Unfreezes physics so the lamp drops naturally
## 3. Re-adds the lamp to the "portable_trap" group so the Entity can
##    pathfind toward it
## 4. Restores the original collision mask
## 5. Sets is_deployed = true so the Entity attraction and computer terminal
##    register it as an active trap
## 6. Applies a minor forward impulse so it drops naturally away from the player
func drop_trap() -> void:
	if not is_being_carried:
		return
	
	is_being_carried = false
	_hand_marker = null
	
	# ─── GROUND-SNAPPING SAFETY NET ──────────────────────────────────────
	# Before unfreezing physics, raycast downward to find the ground surface.
	# This prevents the lamp from spawning mid-air (e.g., if the player drops
	# it while standing on a slope or uneven terrain) and falling through the
	# world geometry due to the initial velocity impulse.
	#
	# The raycast starts 2.0m above the lamp's current position and extends
	# 5.0m downward. If it hits a collider on layer 1 (world/terrain), we
	# snap the lamp's Y to the hit point + half the collision box height
	# (0.2m) so the lamp rests cleanly on the surface.
	var space_state: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	if space_state:
		var ray_origin: Vector3 = global_position + Vector3.UP * 2.0
		var ray_end: Vector3 = global_position + Vector3.DOWN * 5.0
		var query = PhysicsRayQueryParameters3D.create(ray_origin, ray_end)
		query.collision_mask = 1  # Layer 1: World/terrain geometry
		var result: Dictionary = space_state.intersect_ray(query)
		if result:
			# Snap the lamp to the ground surface + half the collision box height
			var ground_y: float = result.position.y
			var box_half_height: float = 0.2  # BoxShape3D height is 0.4, half is 0.2
			global_position.y = ground_y + box_half_height
			print("[PortableLamp] Ground-snapped to Y=%.2f (hit: %s)" % [global_position.y, result.collider.name])
		else:
			print("[PortableLamp] WARNING: No ground found beneath lamp! It may fall through.")
	
	# Unfreeze physics so the lamp drops naturally
	freeze = false
	
	# Restore the original collision mask
	collision_mask = _saved_collision_mask
	
	# Re-add to the portable_trap group so the Entity can pathfind toward it
	add_to_group("portable_trap")
	
	# Mark as deployed — the Entity attraction and computer terminal now
	# register this as an active trap
	is_deployed = true
	
	# Light stays off on drop — it must be toggled remotely from the
	# computer terminal via toggle_power(). Drain rate starts at 0.0.
	if lamp_light:
		lamp_light.visible = false
	energy_drain_rate = 0.0
	
	# Apply a minor forward impulse so it drops naturally away from the player
	var forward: Vector3 = Vector3.FORWARD
	if _hand_marker:
		forward = -_hand_marker.global_transform.basis.z
	linear_velocity = forward * 1.5
	
	print("[PortableLamp] Dropped and deployed at: ", global_position)
	
	# Notify the NightManager to recalculate fuel drain
	var nm: Node = get_node_or_null("/root/NightManager")
	if nm and nm.has_method("recalculate_fuel_drain"):
		nm.recalculate_fuel_drain()


## Public API: Called by PowerCable when the cable is connected to this lamp.
## Sets is_powered = true, enabling the lamp to draw power from the generator.
## The light does NOT turn on automatically — use toggle_power() for that.
func set_powered(powered: bool) -> void:
	is_powered = powered
	if powered:
		print("[PortableLamp] Now powered by generator cable.")
	else:
		print("[PortableLamp] Power disconnected.")

## Public API: Called by the Entity when it physically strikes this lamp.
##
## The Entity attacks the lamp every 3 seconds while within hitting distance.
## Each hit applies a heavy physical impulse to send the lamp flying, and
## plays a metallic smashing sound. On the 3rd hit, the cable is forcibly
## disconnected, requiring the player to re-plug it manually.
##
## If the lamp is currently overloaded (is_overloaded == true), hits are
## ignored — the blinding light protects the lamp from damage.
##
## Parameters:
##   hit_direction: Vector3 — the direction from the Entity to the lamp,
##                  used to apply a realistic knockback impulse.
func take_physical_hit(hit_direction: Vector3) -> void:
	# Ignore hits while overloaded — the blinding light protects the lamp
	if is_overloaded:
		print("[PortableLamp] Overload active! Entity's hit is repelled by the blinding light.")
		return
	
	# Increment the strike counter
	attack_strikes += 1
	print("[PortableLamp] Entity strike #%d!" % attack_strikes)
	
	# Apply a heavy physical impulse to send the lamp flying
	apply_central_impulse(hit_direction * 15.0)
	
	# Play a metallic smashing sound via HorrorSoundManager
	var hsm: Node = get_node_or_null("/root/HorrorSoundManager")
	if hsm and hsm.has_method("play_sound"):
		hsm.play_sound("lamp_hit")
	
	# Check if this is the 3rd strike — destroy the cable completely
	if attack_strikes >= 3:
		attack_strikes = 0
		print("[PortableLamp] 3 strikes! Cable destroyed by Entity!")
		
		# Force is_powered to false
		is_powered = false
		
		# Turn off the light immediately
		if lamp_light:
			lamp_light.visible = false
		energy_drain_rate = 0.0
		
		# ─── DISPOSABLE CABLE DESTRUCTION ────────────────────────────────
		# Find the connected cable in FULLY_CONNECTED state and vaporize it
		# from the scene tree entirely. The player must forge out into the
		# world, retrieve a fresh Cable Spool from their resource stashes,
		# and run the physical connection pipeline from scratch.
		var cables: Array[Node] = get_tree().get_nodes_in_group("power_cable")
		for cable in cables:
			if cable.has_method("get_state") and cable.get_state() == 2:  # CableState.FULLY_CONNECTED == 2
				# Notify the generator outlet to clear its internal reference
				# and reset its interaction state back to AVAILABLE.
				var outlet: Node = get_tree().get_first_node_in_group("generator_outlet")
				if outlet and outlet.has_method("on_cable_destroyed"):
					outlet.on_cable_destroyed()
				
				# Completely remove the cable from the scene tree.
				# The player must manually forge a fresh connection from scratch.
				cable.queue_free()
				print("[PortableLamp] Cable node queued for deletion. Player must reconnect from scratch.")
				break
		
		# Notify NightManager to recalculate fuel drain
		var nm: Node = get_node_or_null("/root/NightManager")
		if nm and nm.has_method("recalculate_fuel_drain"):
			nm.recalculate_fuel_drain()

## Public API: Toggles the lamp's light and Entity attraction on/off.
##
## Called from the computer terminal's "TOGGLE TRAP POWER" button or the
## special wall switch (LightSwitchSpecial). This is the ONLY way to turn
## the portable lamp on or off.
##
## When enabled:
##   - Turns on the OmniLight3D at normal intensity (energy 5.0, range 8.0)
##   - Sets energy_drain_rate to 2.0 (modest baseline drain)
##   - Notifies NightManager to recalculate fuel drain
##
## When disabled:
##   - Turns off the OmniLight3D
##   - Sets energy_drain_rate to 0.0 (no drain)
##   - Notifies NightManager to recalculate fuel drain
##
## Safety guards:
##   - Does nothing if the lamp is not deployed
##   - Does nothing if the lamp is not connected to the generator (is_powered == false)
##   - Refuses to turn ON if the generator is off (fuse box not working)
##   - Refuses to turn ON if the generator has no fuel
func toggle_power(enabled: bool) -> void:
	if not is_deployed:
		print("[PortableLamp] Cannot toggle power — lamp is not deployed!")
		return
	
	if not is_powered:
		print("[PortableLamp] Cannot toggle power — lamp is not connected to generator!")
		return
	
	if enabled:
		# ─── GENERATOR HEALTH CHECK ──────────────────────────────────────
		# Check that the generator is actually running (fuse box working)
		# and has fuel before allowing the lamp to draw power.
		var nm: Node = get_node_or_null("/root/NightManager")
		if nm:
			if not nm.is_generator_on:
				print("[PortableLamp] Cannot turn on — generator is off (fuse box needs repair)!")
				return
			if nm.generator_fuel <= 0.0:
				print("[PortableLamp] Cannot turn on — generator has no fuel!")
				return
		
		# Turn the light on at normal intensity
		if lamp_light:
			lamp_light.visible = true
			lamp_light.light_energy = 5.0
			lamp_light.omni_range = 8.0
		
		# Set the drain rate to a modest baseline while powered on
		energy_drain_rate = 2.0
		
		print("[PortableLamp] Power toggled ON via terminal.")
	else:
		# Turn the light off
		if lamp_light:
			lamp_light.visible = false
		
		# Clear the drain rate — no power draw when off
		energy_drain_rate = 0.0
		
		print("[PortableLamp] Power toggled OFF via terminal.")
	
	# Notify the NightManager to recalculate fuel drain
	var nm2: Node = get_node_or_null("/root/NightManager")
	if nm2 and nm2.has_method("recalculate_fuel_drain"):
		nm2.recalculate_fuel_drain()

## Maximum cable length in meters before the lamp is physically restrained.
const MAX_CABLE_LENGTH: float = 20.0


## Cooldown timer for the cable-strain creak sound (seconds).
var _strain_sound_cooldown: float = 0.0


## Physics lerp loop: smoothly interpolates the lamp's position and rotation
## to match the hand marker while being carried.
## Also enforces the 20-meter cable length limit by clamping the lamp's
## position when the player tries to carry it beyond the generator outlet.
func _physics_process(delta: float) -> void:
	if is_being_carried and _hand_marker:
		# ─── LENGTH CLAMPING ──────────────────────────────────────────────
		# Find the active cable to get the generator outlet position.
		var cable: Node = _find_active_cable()
		if cable and cable.has_method("get_source_position"):
			var outlet_pos: Vector3 = cable.get_source_position()
			var current_dist: float = global_position.distance_to(outlet_pos)
			
			if current_dist > MAX_CABLE_LENGTH:
				# Calculate direction from generator to lamp
				var dir: Vector3 = (global_position - outlet_pos).normalized()
				# Clamp the lamp's position exactly at the 20-meter boundary
				global_position = outlet_pos + (dir * MAX_CABLE_LENGTH)
				
				# Trigger a straining creak sound with cooldown
				_strain_sound_cooldown -= delta
				if _strain_sound_cooldown <= 0.0:
					var hsm: Node = get_node_or_null("/root/HorrorSoundManager")
					if hsm and hsm.has_method("play_sound"):
						hsm.play_sound("cable_strain")
					_strain_sound_cooldown = 1.5
		
		# Smoothly interpolate position to the hand marker
		global_position = global_position.lerp(_hand_marker.global_position, 0.3)
		
		# Smoothly interpolate rotation to match the hand marker
		global_rotation = global_rotation.lerp(_hand_marker.global_rotation, 0.3)



## Triggers the overload state on this lamp.
##
## Called by the computer terminal when the player executes the
## "EXECUTE OVERLOAD" command after unlocking LOG_02_CRITICAL.
##
## Effects:
##   1. Sets is_overloaded = true
##   2. Saves the original drain rate and spikes it to 50.0
##   3. Boosts the OmniLight3D to blinding intensity (energy 30.0, range 20.0)
##   4. Calls NightManager.recalculate_fuel_drain() so the generator
##      immediately starts burning fuel at the catastrophic rate
##   5. Locates the Entity and calls trigger_overload_stun() with this
##      lamp's position and a 30-second stun duration
func trigger_overload() -> void:
	if not is_deployed:
		print("[PortableLamp] Cannot trigger overload — lamp is not deployed!")
		return
	
	if is_overloaded:
		print("[PortableLamp] Overload already active! Ignoring duplicate call.")
		return
	
	print("[PortableLamp] ⚡ OVERLOAD INITIATED! ⚡")
	
	# 1. Set the overload flag
	is_overloaded = true
	
	# 2. Save original drain rate and spike it to catastrophic levels
	_original_drain_rate = energy_drain_rate
	energy_drain_rate = 50.0  # Drains generator fuel in ~seconds
	
	# 3. Boost the OmniLight3D to blinding intensity
	if lamp_light:
		lamp_light.light_energy = 30.0
		lamp_light.omni_range = 20.0
		lamp_light.visible = true
	
	# 4. Recalculate fuel drain so the generator immediately feels the load
	var nm: Node = get_node_or_null("/root/NightManager")
	if nm and nm.has_method("recalculate_fuel_drain"):
		nm.recalculate_fuel_drain()
	
	# 5. Trigger the Entity stun — locate the Entity and call trigger_overload_stun()
	#    with this lamp's position and a 30-second stun duration.
	#    The Entity's trigger_overload_stun() will check distance internally
	#    (must be within 25 units) and only stun if close enough.
	var entity: Node = get_tree().get_first_node_in_group("entity")
	if entity and entity.has_method("trigger_overload_stun"):
		entity.trigger_overload_stun(global_position, 30.0)
		print("[PortableLamp] Overload stun triggered on Entity at distance %.1f units." % global_position.distance_to(entity.global_position))
	else:
		print("[PortableLamp] WARNING: Entity not found or missing trigger_overload_stun method!")
	
	print("[PortableLamp] Overload active! Drain rate: %.1f | Light energy: %.1f" % [energy_drain_rate, lamp_light.light_energy if lamp_light else 0.0])


## Resets the Overload state, restoring the original drain rate and light
## intensity. Called when the generator dies (blackout) or if the trap
## is manually disarmed.
func reset_overload() -> void:
	if not is_overloaded:
		return
	
	print("[PortableLamp] Overload reset. Restoring normal light parameters.")
	
	is_overloaded = false
	
	# Restore original drain rate
	energy_drain_rate = _original_drain_rate
	_original_drain_rate = 0.0
	
	# Restore light intensity to default
	if lamp_light:
		lamp_light.light_energy = 5.0
		lamp_light.omni_range = 8.0
	
	# Recalculate fuel drain
	var nm: Node = get_node_or_null("/root/NightManager")
	if nm and nm.has_method("recalculate_fuel_drain"):
		nm.recalculate_fuel_drain()
	
	print("[PortableLamp] Overload reset complete. Drain rate restored to %.1f." % [energy_drain_rate])


## Returns the world position of this lamp for Entity attraction targeting.
func get_trap_position() -> Vector3:
	return global_position
