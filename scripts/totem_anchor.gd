extends Node3D
class_name TotemAnchor

## TotemAnchor — The anchoring totem that binds the Entity to the cabin.
##
## This is the endgame objective: the player must destroy the totem to banish
## the Entity. Destroying the totem advances the RoutineManager step, which
## unlocks the escape van.
##
## INTERACTION (HOLD-TO-PURGE):
## Fully autonomous — no InteractionManager dependency. _process() checks the
## physical 'E' key (Input.is_physical_key_pressed(KEY_E)), player distance
## (5m), and a generous camera dot-product (53-degree cone, cos=0.6) to manage
## its own hold-to-purge state. The InteractionManager's get_interact_text()
## is kept only for the prompt display.
##
## RACE MECHANIC:
## The totem is ALWAYS interactable — there is no stun gate. However, the
## Entity will kill the player if it catches them mid-purge. Stunning the
## Entity (via the porch light overload trap) gives the player a safe window
## to reach the totem and begin the purge. If the Entity recovers while the
## player is still purging, the Entity becomes ENRAGED and the player must
## decide whether to finish the purge or flee.
##
## VISUAL FEEDBACK:
## While purging, a progress bar is displayed on the HUD. When complete, the
## totem plays a burning/destruction sound, spawns particle sparks, defeats
## the Entity, and becomes non-interactable (is_purged = true).

## Whether this totem has been destroyed (purged).
## Once true, the totem cannot be interacted with again.
var is_purged: bool = false

## Current purge progress in seconds. Accumulates while the player holds the
## interact key. Reset to 0.0 if the player releases the key early.
var purge_progress: float = 0.0

## Total time in seconds the player must hold the interact key to complete
## the purge. 4.0 seconds creates a high-tension window where the Entity
## could recover from stun before the totem is destroyed.
@export var total_purge_time_required: float = 4.0

## Whether the player is currently actively purging the anchor.
## Set to true by interact() when the purge starts.
## Set to false when the purge completes or the player releases the key.
var is_being_purged: bool = false

## Reference to the Entity controller (used for the defeat sequence).
var _entity: Node = null

## Audio player for the destruction sound effect.
var _destroy_audio: AudioStreamPlayer3D = null

## Particle emitter for the destruction sparks.
var _spark_particles: GPUParticles3D = null

## The prompt text shown when the player looks at the totem.
const INTERACT_PROMPT: String = "[E] Destroy Totem Anchor"

## Maximum distance the player can be from the totem to continue purging.
## Set to 8.0 to account for the interaction raycast range (typically 5-6m)
## plus some leeway so the player doesn't accidentally break the hold.
const MAX_PURGE_DISTANCE: float = 8.0


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


## Called every frame. Fully autonomous — no InteractionManager dependency.
## Checks the physical 'E' key, player distance (5m), and a generous camera
## dot-product (53-degree cone, cos=0.6) to manage its own hold-to-purge state.
func _process(delta: float) -> void:
	if is_purged:
		return
	
	# 1. Is the player physically holding the 'E' key?
	if Input.is_physical_key_pressed(KEY_E):
		var player = get_tree().get_first_node_in_group("player")
		if not player:
			player = get_tree().get_first_node_in_group("Player")
		
		# 2. Is the player within 5 meters?
		if player and global_position.distance_to(player.global_position) <= 5.0:
			
			# 3. Is the player generally looking at the totem? (Very generous 53-degree cone)
			var cam = get_viewport().get_camera_3d()
			if cam:
				var to_totem = (global_position - cam.global_position).normalized()
				var cam_forward = -cam.global_transform.basis.z
				if cam_forward.dot(to_totem) > 0.6:
					_maintain_purge(delta)
					return
	
	# If we drop down here, 'E' is released, player walked away, or looked away.
	if is_being_purged:
		_abort_purge()


## Maintains the purge state. Called every frame from _process() while all
## conditions (E key held, within 5m, looking at totem) are met.
func _maintain_purge(delta: float) -> void:
	if not is_being_purged:
		is_being_purged = true
		purge_progress = 0.0
		print("[TotemAnchor] Purge started via 'E' key!")
		var hud = get_tree().get_first_node_in_group("hud")
		if hud and hud.has_method("show_purge_progress"):
			hud.show_purge_progress()
	
	purge_progress += delta
	
	var hud = get_tree().get_first_node_in_group("hud")
	if hud and hud.has_method("update_purge_progress"):
		hud.update_purge_progress(purge_progress / total_purge_time_required)
	
	if purge_progress >= total_purge_time_required:
		_complete_purge()


## Aborts the purge sequence. Resets progress and hides the progress bar.
func _abort_purge() -> void:
	is_being_purged = false
	purge_progress = 0.0
	print("[TotemAnchor] Purge aborted.")
	var hud = get_tree().get_first_node_in_group("hud")
	if hud and hud.has_method("hide_purge_progress"):
		hud.hide_purge_progress()


## Executes the final destruction mechanics when the purge completes.
## Called by _process() when purge_progress reaches total_purge_time_required.
func _complete_purge() -> void:
	is_being_purged = false
	is_purged = true
	
	print("[TotemAnchor] ⚡ TOTEM DESTROYED! The Entity's anchor is broken!")
	
	# Hide the HUD progress bar
	var hud = get_tree().get_first_node_in_group("hud")
	if hud and hud.has_method("hide_purge_progress"):
		hud.hide_purge_progress()
	
	# Play the destruction sound
	if _destroy_audio and _destroy_audio.stream:
		_destroy_audio.pitch_scale = randf_range(0.8, 1.2)
		_destroy_audio.play()
	
	# Emit particle sparks
	if _spark_particles:
		_spark_particles.emitting = true
	
	# Show HUD feedback
	_show_hud_message("The totem crumbles to ash! The Entity is anchored no more!")
	
	# ─── DEFEAT THE ENTITY ──────────────────────────────────────────
	_defeat_entity()
	
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


## Defeats the Entity: plays a death scream, hides it, and disables it
## completely so it can no longer interact with the game world.
func _defeat_entity() -> void:
	if not _entity or not is_instance_valid(_entity):
		print("[TotemAnchor] No Entity found to defeat. It may have already been banished.")
		return
	
	print("[TotemAnchor] Defeating Entity...")
	
	# ─── PLAY DEATH SCREAM ──────────────────────────────────────────
	# Find the GrowlAudio player on the Entity and play it with a
	# distorted pitch to sound like a dying scream.
	var growl_audio: AudioStreamPlayer3D = _entity.get_node_or_null("GrowlAudio")
	if growl_audio:
		growl_audio.pitch_scale = randf_range(0.3, 0.6)  # Low, distorted, dying
		growl_audio.play()
		print("[TotemAnchor] Entity death scream played.")
	else:
		print("[TotemAnchor] WARNING: Entity has no GrowlAudio node.")
	
	# ─── DISABLE THE ENTITY COMPLETELY ─────────────────────────────
	# Hide the visual model
	_entity.hide()
	
	# Disable processing — the Entity will no longer think, move, or react
	_entity.process_mode = Node.PROCESS_MODE_DISABLED
	
	# Disable the collision shape so the Entity can't block or push the player
	var collision_shape = _entity.get_node_or_null("CollisionShape3D")
	if collision_shape:
		collision_shape.set_deferred("disabled", true)
	
	# Also disable the catch area if it exists
	var catch_area = _entity.get_node_or_null("CatchArea")
	if catch_area:
		catch_area.monitoring = false
	
	print("[TotemAnchor] Entity defeated and disabled!")


## Shows a temporary message on the HUD.
func _show_hud_message(msg: String) -> void:
	var hud = get_tree().get_first_node_in_group("hud")
	if hud and hud.has_method("show_message"):
		hud.show_message(msg)
	else:
		print("[TotemAnchor HUD]: ", msg)
