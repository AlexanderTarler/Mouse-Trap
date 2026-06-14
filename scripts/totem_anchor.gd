extends Node3D
class_name TotemAnchor

## TotemAnchor — The anchoring totem that binds the Entity to the cabin.
##
## This is the endgame objective: the player must destroy the totem to banish
## the Entity. Destroying the totem advances the RoutineManager step, which
## unlocks the escape van.
##
## INTERACTION (HOLD-TO-PURGE):
## The totem uses the standard interaction system (has_method("interact") and
## has_method("get_interact_text")). When the player presses 'E' while looking
## at it, the purge begins. The player must HOLD the interact key for
## total_purge_time_required seconds to complete the destruction. Releasing
## the key early resets progress to zero.
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
## totem plays a burning/destruction sound, spawns particle sparks, and
## becomes non-interactable (is_purged = true).

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
## Set to true by interact() when the Entity is stunned.
## Set to false when the purge completes or the player releases the key.
var is_being_purged: bool = false

## Reference to the Entity controller (optional — used for future
## tension-based features like proximity detection during purge).
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
## at this totem. The totem is ALWAYS interactable — there is no stun gate.
## The player can begin the hold-to-purge at any time, but the Entity will
## kill them if it catches them mid-purge.
##
## Stunning the Entity (via the porch light overload trap) gives the player
## a safe window to reach the totem and begin the purge without being
## interrupted. If the Entity recovers mid-purge, the player must decide
## whether to finish or flee.
##
## The _process(delta) loop handles the hold-to-purge accumulation,
## early-release reset, and completion trigger.
func interact(player: Node3D = null) -> void:
	if is_purged or is_being_purged:
		return
	
	# ─── BEGIN PURGE SEQUENCE ───────────────────────────────────────
	# The totem is always interactable. Reset progress and flip the flag
	# so _process(delta) takes over the hold-to-purge accumulation.
	purge_progress = 0.0
	is_being_purged = true
	
	# Show the HUD progress bar
	var hud = get_tree().get_first_node_in_group("hud")
	if hud and hud.has_method("show_purge_progress"):
		hud.show_purge_progress()
	
	print("[TotemAnchor] Purge sequence started! Hold interact for %.1f seconds." % total_purge_time_required)


## Called every frame. If is_being_purged is true, checks whether the player
## continues to hold the interact key. If released early, resets progress and
## hides the progress bar. If held long enough, triggers the final destruction.
func _process(delta: float) -> void:
	if not is_being_purged:
		return
	
	# ─── EARLY RELEASE CHECK ────────────────────────────────────────
	# If the player releases the interact key, abort the purge and reset.
	if not Input.is_action_pressed("interact"):
		purge_progress = 0.0
		is_being_purged = false
		
		# Hide the HUD progress bar
		var hud = get_tree().get_first_node_in_group("hud")
		if hud and hud.has_method("hide_purge_progress"):
			hud.hide_purge_progress()
		
		print("[TotemAnchor] Purge aborted — interact key released early.")
		return
	
	# ─── ACCUMULATE PROGRESS ────────────────────────────────────────
	purge_progress += delta
	
	# Update the HUD progress bar
	var hud = get_tree().get_first_node_in_group("hud")
	if hud and hud.has_method("update_purge_progress"):
		var ratio: float = clampf(purge_progress / total_purge_time_required, 0.0, 1.0)
		hud.update_purge_progress(ratio)
	
	# ─── COMPLETION CHECK ───────────────────────────────────────────
	if purge_progress >= total_purge_time_required:
		_complete_purge()


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
