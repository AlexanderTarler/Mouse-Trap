extends Node3D
class_name TotemAnchor

## TotemAnchor — The anchoring totem that binds the Entity to the cabin.
##
## This is the endgame objective: the player must destroy the totem while the
## Entity is stunned by the porch light overload trap. Destroying the totem
## advances the RoutineManager step, which unlocks the escape van.
##
## INTERACTION:
## The totem uses the standard interaction system (has_method("interact") and
## has_method("get_interact_text")). The player presses 'E' while looking at
## it to destroy it.
##
## STUN GUARD:
## The totem can ONLY be interacted with while the Entity is in the STUNNED
## state. If the player tries to destroy it while the Entity is active, the
## interaction is rejected with a HUD message.
##
## VISUAL FEEDBACK:
## When destroyed, the totem plays a burning/destruction sound, spawns particle
## sparks, and becomes non-interactable (is_purged = true).

## Whether this totem has been destroyed (purged).
## Once true, the totem cannot be interacted with again.
var is_purged: bool = false

## Reference to the Entity controller for checking STUNNED state.
var _entity: Node = null

## Audio player for the destruction sound effect.
var _destroy_audio: AudioStreamPlayer3D = null

## Particle emitter for the destruction sparks.
var _spark_particles: GPUParticles3D = null

## The prompt text shown when the player looks at the totem.
const INTERACT_PROMPT: String = "[E] Destroy Totem Anchor"


func _ready() -> void:
	add_to_group("interactable")
	
	# Find the Entity in the scene tree
	_entity = get_tree().get_first_node_in_group("entity")
	
	# Set up the destruction audio player
	_destroy_audio = AudioStreamPlayer3D.new()
	_destroy_audio.bus = "SFX"
	_destroy_audio.max_distance = 20.0
	_destroy_audio.volume_db = -4.0
	add_child(_destroy_audio)
	
	# Try to load a destruction sound effect
	var destroy_stream = load("res://assets/audio/Entity/Entity_grunt_long.ogg") as AudioStream
	if destroy_stream:
		destroy_stream = destroy_stream.duplicate()
		if destroy_stream is AudioStreamOggVorbis:
			destroy_stream.loop = false
		_destroy_audio.stream = destroy_stream
	else:
		print("[TotemAnchor] WARNING: Destruction audio not found. Using silent fallback.")
	
	# Set up the spark particle emitter
	_spark_particles = GPUParticles3D.new()
	_spark_particles.name = "SparkParticles"
	_spark_particles.one_shot = true
	_spark_particles.emitting = false
	_spark_particles.amount = 50
	_spark_particles.lifetime = 1.5
	_spark_particles.explosiveness = 0.8
	_spark_particles.randomness = 0.5
	
	# Create a simple particle material for the sparks
	var particle_material = ParticleProcessMaterial.new()
	particle_material.direction = Vector3.UP
	particle_material.spread = 180.0
	particle_material.initial_velocity_min = 2.0
	particle_material.initial_velocity_max = 5.0
	particle_material.gravity = Vector3(0.0, -5.0, 0.0)
	particle_material.color = Color(1.0, 0.5, 0.0, 1.0)  # Orange sparks
	particle_material.scale_min = 0.1
	particle_material.scale_max = 0.3
	_spark_particles.process_material = particle_material
	
	add_child(_spark_particles)
	
	print("[TotemAnchor] Initialized at position: ", global_position)


## Returns the interaction prompt text shown by the InteractionManager.
func get_interact_text() -> String:
	if is_purged:
		return ""  # No prompt if already destroyed
	return INTERACT_PROMPT


## Called by the InteractionManager when the player presses 'E' while looking
## at this totem. Only allows interaction if:
##   1. The totem has not already been purged
##   2. The Entity is currently in the STUNNED state (overload trap active)
##
## If the Entity is not stunned, the player is shown a HUD message explaining
## that the totem is protected by the Entity's presence.
func interact(player: Node3D = null) -> void:
	if is_purged:
		return
	
	# STUN GUARD: Check if the Entity is currently stunned
	var entity_stunned: bool = false
	if _entity and _entity.has_method("get_state"):
		# Use the State enum value — STUNNED = 13 (index in the enum)
		var state_value = _entity._state
		entity_stunned = (state_value == 13)  # State.STUNNED
	elif _entity:
		# Fallback: check if the Entity has a _stun_timer > 0
		if "_stun_timer" in _entity:
			entity_stunned = _entity._stun_timer > 0.0
	
	if not entity_stunned:
		# Reject interaction — the Entity's presence protects the totem
		_show_hud_message("The totem is protected by the Entity's presence... I must find a way to paralyze it first.")
		print("[TotemAnchor] Interaction rejected — Entity is not stunned.")
		return
	
	# ─── DESTROY THE TOTEM ──────────────────────────────────────────
	print("[TotemAnchor] ⚡ TOTEM DESTROYED! The Entity's anchor is broken!")
	
	is_purged = true
	
	# Play the destruction sound
	if _destroy_audio and _destroy_audio.stream:
		_destroy_audio.pitch_scale = randf_range(0.8, 1.2)
		_destroy_audio.play()
	
	# Emit particle sparks
	if _spark_particles:
		_spark_particles.emitting = true
	
	# Show HUD feedback
	_show_hud_message("The totem crumbles to ash! The Entity is anchored no more!")
	
	# Advance the RoutineManager step to unlock the escape van
	var rm = get_node_or_null("/root/RoutineManager")
	if rm and rm.has_method("advance_step"):
		rm.advance_step()
		print("[TotemAnchor] RoutineManager step advanced! Escape van should now be unlocked.")
	else:
		print("[TotemAnchor] WARNING: RoutineManager not found or missing advance_step method!")
	
	# Make the totem visually disappear (fade out)
	var tween = create_tween()
	tween.tween_property(self, "scale", Vector3.ZERO, 1.0)
	tween.tween_callback(queue_free)


## Shows a temporary message on the HUD.
func _show_hud_message(msg: String) -> void:
	var hud = get_tree().get_first_node_in_group("hud")
	if hud and hud.has_method("show_message"):
		hud.show_message(msg)
	else:
		print("[TotemAnchor HUD]: ", msg)
