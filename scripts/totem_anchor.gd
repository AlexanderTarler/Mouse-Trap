extends Node3D
class_name TotemAnchor

## TotemAnchor — The anchoring totem that binds the Entity to the cabin.
##
## This is the endgame objective: the player must destroy the totem to banish
## the Entity. Destroying the totem advances the RoutineManager step, which
## unlocks the escape van.
##
## ─── PROGRESSION LOCK ─────────────────────────────────────────────────────
## The player CANNOT interact with/destroy the totem unless they have picked up
## "Arvid's Note 2" (checked via EvidenceManager). Attempting to interact early
## shows: "I don't know what to do with this yet."
##
## ─── DAY/NIGHT ANIMATION ──────────────────────────────────────────────────
## The totem rises out of the ground at night and descends beneath it during
## the day, using smooth 10-second Tween animations. The totem is connected
## to NightManager's night_started and night_ended signals.
##
## ─── COLLISION MANAGEMENT ─────────────────────────────────────────────────
## During the day, when the totem is fully buried, its collision shape is
## disabled to prevent the player from interacting with empty dirt.
## During the night, the collision shape is enabled when the totem emerges.
##
## ─── HOLD-TO-PURGE ───────────────────────────────────────────────────────
## Fully autonomous — no InteractionManager dependency. _process() checks the
## physical 'E' key (Input.is_physical_key_pressed(KEY_E)), player distance
## (5m), and a generous camera dot-product (53-degree cone, cos=0.6) to manage
## its own hold-to-purge state.

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

## ─── TOTEM DEFENSE (Night 3+) ──────────────────────────────────────────
## One-shot guard for the totem defense: when the player approaches within
## 5m on Night 3+, the Entity is teleported to the EntityTotemWaypoint and
## forced into CHARGE. This guard prevents the teleport/CHARGE from firing
## every frame (60fps) while the player stays near the totem — the Entity
## is teleported and forced into CHARGE exactly ONCE per approach. The guard
## resets when the player moves more than 5m away from the totem.
var _totem_defending: bool = false

## Distance (meters) at which the Entity begins aggressively defending the
## totem on Night 3+. Player entering this radius triggers the teleport +
## CHARGE defense unless the Entity is already FLINCHing or STUNNED.
const TOTEM_DEFENSE_RADIUS: float = 5.0

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

## ─── DAY/NIGHT ANIMATION ──────────────────────────────────────────────────
## The original Y position of the totem where it rests on the ground.
## Captured at _ready() from the totem's actual scene placement.
## This is the CANONICAL "raised" position — at night the totem rises to
## exactly this height. No hardcoded raised_y/buried_y magic numbers
## (which previously drifted the totem 2-3m above its planted position
## every night because the night tween targeted original_y + 3.0).
##
## BUG FIX: The old code tweened night to `_original_y + raised_y` (3.0m
## above ground). The correct behavior is: night → rise to `_original_y`
## (its planted, correct height), day → sink 5.0m below to `_original_y - 5.0`.
@onready var _original_y: float = global_position.y

## How far below the original Y the totem sinks during the day.
## The willow tree model extends ~6.9m above its origin point, so burying
## 7.0m below + the tree's height fully submerges the canopy underground.
## TASK 3.4: Changed from 5.0 → 7.0 to lower the totem anchor an extra
## 2 meters into the ground during the daytime.
const BURIED_OFFSET: float = 7.0

## Duration (seconds) of the rise/descent tweens.
@export var animation_duration: float = 10.0

## Whether the totem is currently in its "night" state (above ground).
var _is_night: bool = false

## Collision shape reference, disabled when totem is buried.
@onready var _collision_shape: CollisionShape3D = $CollisionShape3D if has_node("CollisionShape3D") else null

## NightManager reference, cached for signal connections.
var _night_manager: Node = null


func _ready() -> void:
	add_to_group("interactable")
	add_to_group("totem_anchor")
	
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
	
	# ─── CONNECT TO NIGHT MANAGER ─────────────────────────────────────
	_night_manager = get_node_or_null("/root/NightManager")
	if _night_manager:
		if _night_manager.has_signal("night_started"):
			_night_manager.night_started.connect(_on_night_started)
		if _night_manager.has_signal("night_ended"):
			_night_manager.night_ended.connect(_on_night_ended)
		print("[TotemAnchor] Connected to NightManager signals.")
	
	print("[TotemAnchor] Initialized at position: ", global_position)


## ─── DAY/NIGHT SIGNAL HANDLERS ──────────────────────────────────────────────

## Called when a night starts. Tweens the totem UP out of the ground
## over animation_duration seconds. Enables collision at the end.
func _on_night_started(night: int) -> void:
	if is_purged:
		return
	
	_is_night = true
	print("[TotemAnchor] Night %d started. Raising totem to its original position y=%.2f over %.1fs..." % [night, _original_y, animation_duration])
	
	# Kill any existing tweens to prevent conflicts
	if has_node("_rise_tween"):
		get_node("_rise_tween").kill()
	
	var tween = create_tween()
	tween.set_trans(Tween.TRANS_SINE)
	tween.set_ease(Tween.EASE_OUT)
	tween.set_parallel(false)
	
	# Tween UP to the ORIGINAL planted position (no relative addition).
	# Previously this targeted _original_y + raised_y (3.0m above ground),
	# which caused the totem to float 2-3m above its correct position.
	tween.tween_property(self, "global_position:y", _original_y, animation_duration)
	
	# Enable collision shape when the tween completes (totem is fully risen)
	tween.tween_callback(_enable_collision)


## Called when a night ends. Tweens the totem DOWN beneath the ground
## over animation_duration seconds. Disables collision immediately so
## the player can't interact with the empty dirt while it's descending.
func _on_night_ended(night: int) -> void:
	if is_purged:
		return
	
	_is_night = false
	print("[TotemAnchor] Night %d ended. Lowering totem to y=%.2f over %.1fs..." % [night, _original_y - BURIED_OFFSET, animation_duration])
	
	# Disable collision immediately — totem is starting to descend
	_disable_collision()
	
	# Kill any existing tweens to prevent conflicts
	if has_node("_descent_tween"):
		get_node("_descent_tween").kill()
	
	var tween = create_tween()
	tween.set_trans(Tween.TRANS_SINE)
	tween.set_ease(Tween.EASE_IN)
	tween.set_parallel(false)
	
	# Tween DOWN 5.0m below the original planted position so the tree's
	# canopy is fully submerged underground (no relative math, no drift).
	tween.tween_property(self, "global_position:y", _original_y - BURIED_OFFSET, animation_duration)


## Enables the collision shape so the player can interact with the totem.
func _enable_collision() -> void:
	if _collision_shape:
		_collision_shape.disabled = false
		print("[TotemAnchor] Collision shape ENABLED (totem fully risen).")


## Disables the collision shape so the player can't interact with empty dirt.
func _disable_collision() -> void:
	if _collision_shape:
		_collision_shape.disabled = true
		print("[TotemAnchor] Collision shape DISABLED (totem buried or descending).")


## Returns the interaction prompt text shown by the InteractionManager.
func get_interact_text() -> String:
	if is_purged:
		return ""  # No prompt if already destroyed
	
	# ─── TASK 2.1: EXHAUSTED INTERACTION PROMPT ──────────────────
	# When exhausted, grey out the interaction prompt instead of
	# showing the normal "Press E" text. The player is too tired.
	var player_ref = get_tree().get_first_node_in_group("player")
	if player_ref and "is_exhausted" in player_ref and player_ref.is_exhausted:
		return "[color=gray]I am too tired to do this[/color]"
	
	# ─── PROGRESSION LOCK CHECK ─────────────────────────────────────
	if not _has_arvid_note_2():
		return ""  # Player doesn't know what to do yet
		
	return INTERACT_PROMPT


## Checks whether the player has found Arvid's Note 2 via EvidenceManager.
## The evidence ID string must match exactly how note_pickup.gd registers it:
##   em.collect_evidence(note_item.item_name)  (line 196 of note_pickup.gd)
## item_data.item_name for Arvid's Note 2 is "Arvid's Note 2" (from resources/arvid_note_2.tres).
func _has_arvid_note_2() -> bool:
	var em = get_node_or_null("/root/EvidenceManager")
	if not em:
		return false
	return em.has_evidence("Arvid's Note 2")


## Called every frame. Fully autonomous — no InteractionManager dependency.
## Checks the physical 'E' key, player distance (5m), and a generous camera
## dot-product (53-degree cone, cos=0.6) to manage its own hold-to-purge state.
func _process(delta: float) -> void:
	if is_purged:
		return

	# ─── TOTEM DEFENSE (Night 3+) ──────────────────────────────────────
	# From Night 3 onward, if the player gets within 5 meters of the totem,
	# the Entity aggressively defends it — UNLESS the Entity is currently
	# stunned/flinching from the flashlight. The defense teleports the
	# Entity to the EntityTotemWaypoint and forces it into CHARGE state
	# (which is immune to the flashlight overcharge per the Director's
	# CHARGE IGNORES FLASHLIGHT rule).
	#
	# ONE-SHOT GUARD: _totem_defending prevents the teleport + CHARGE from
	# re-firing every frame (60fps) while the player stays in range. The
	# Entity is teleported and forced into CHARGE exactly once per approach;
	# the guard resets when the player leaves the defense radius.
	if _night_manager and "current_night" in _night_manager and _night_manager.current_night >= 3:
		var near_player = get_tree().get_first_node_in_group("player")
		if near_player:
			var dist_to_near_player = global_position.distance_to(near_player.global_position)
			if dist_to_near_player <= TOTEM_DEFENSE_RADIUS:
				if _entity and is_instance_valid(_entity) and not _totem_defending:
					# ─── ONLY DEFEND IF NOT FLINCHING / STUNNED ──────────
					# If the Entity is currently flinching from the flashlight
					# or stunned by the overcharge trap, it cannot defend.
					var ent_state = _entity.get_state() if "get_state" in _entity else -1
					var is_flinching: bool = ent_state == EntityAI.State.FLINCH
					var is_stunned: bool = (ent_state == EntityAI.State.STUNNED) or (ent_state == EntityAI.State.ENRAGED)
					if not is_flinching and not is_stunned:
						_totem_defending = true
						_defend_totem_with_entity()
			else:
				# Player left the defense radius — re-arm the guard so the
				# next approach triggers the defense again.
				_totem_defending = false
	
	# ─── PROGRESSION LOCK ──────────────────────────────────────────────
	# Player cannot interact with the totem unless they have Arvid's Note 2.
	if not _has_arvid_note_2():
		# Show hint if they're pressing E near it without the note
		if Input.is_physical_key_pressed(KEY_E):
			var player = get_tree().get_first_node_in_group("player")
			if player and global_position.distance_to(player.global_position) <= 5.0:
				_show_hud_message("I don't know what to do with this yet.")
		if is_being_purged:
			_abort_purge()
		return
	
	# ─── TASK 2.1: EXHAUSTED GATE ──────────────────────────────────────
	# When the player is exhausted (Day 3+), they are too tired to destroy
	# the totem anchor. Show a greyed-out message and abort any purge.
	var exhausted_player = get_tree().get_first_node_in_group("player")
	if exhausted_player and "is_exhausted" in exhausted_player and exhausted_player.is_exhausted:
		if Input.is_physical_key_pressed(KEY_E) and global_position.distance_to(exhausted_player.global_position) <= 5.0:
			_show_hud_message("I am too tired to do this...")
		if is_being_purged:
			_abort_purge()
		return
	
	# ─── COLLISION GUARD ───────────────────────────────────────────────
	# If the collision shape is disabled (daytime / totem buried), skip
	# interaction checks entirely.
	if _collision_shape and _collision_shape.disabled:
		# Also hide the interaction prompt via the Hud
		if is_being_purged:
			_abort_purge()
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


## Teleports the Entity to the EntityTotemWaypoint and forces it into an
## aggressive CHARGE state to defend the totem. Called by _process() when
## the player enters the 5m defense radius on Night 3+.
##
## The EntityTotemWaypoint is a Marker3D node located under EntityWaypoints
## in the scene. If it does not exist yet, the Entity is teleported to a
## position directly adjacent to the totem as a safe fallback so the defense
## still functions.
func _defend_totem_with_entity() -> void:
	if not _entity or not is_instance_valid(_entity):
		return
	
	# ─── FIND THE ENTITY TOTEM WAYPOINT ────────────────────────────────
	var totem_waypoint: Node3D = null
	var waypoint_groups = get_tree().get_nodes_in_group("EntityTotemWaypoint")
	if not waypoint_groups.is_empty():
		totem_waypoint = waypoint_groups[0] as Node3D
	else:
		var waypoints = get_tree().get_nodes_in_group("EntityWaypoints")
		for wp in waypoints:
			if wp.name == "EntityTotemWaypoint":
				totem_waypoint = wp
				break
	
	var target_pos: Vector3
	if totem_waypoint:
		target_pos = totem_waypoint.global_position
		print("[TotemAnchor] EntityTotemWaypoint found at (%.2f, %.2f, %.2f)." % [target_pos.x, target_pos.y, target_pos.z])
	else:
		# ─── SAFE FALLBACK: Adjacent to the totem ──────────────────────
		# If the waypoint isn't placed in the scene yet, teleport the Entity
		# to a position 4m in front of the totem so the defense still works.
		var fallback_offset = (global_position - _entity.global_position)
		fallback_offset.y = 0.0
		if fallback_offset.length() < 0.1:
			fallback_offset = Vector3(0, 0, 1)
		target_pos = global_position + fallback_offset.normalized() * 4.0
		print("[TotemAnchor] WARNING: EntityTotemWaypoint not found in scene. Using fallback position adjacent to totem.")
	
	# ─── SNAP TO NAVMESH FLOOR ────────────────────────────────────────
	# Project the target onto the NavMesh floor (preserving XZ) so the
	# Entity lands on solid ground instead of floating.
	var nav_map = _entity.get_world_3d().navigation_map
	var snapped_pos = NavigationServer3D.map_get_closest_point(nav_map, target_pos)
	snapped_pos.x = target_pos.x
	snapped_pos.z = target_pos.z
	
	# ─── TELEPORT THE ENTITY ──────────────────────────────────────────
	_entity.global_position = snapped_pos
	_entity.velocity = Vector3.ZERO
	
	# ─── FORCE CHARGE STATE ───────────────────────────────────────────
	# Force the Entity into CHARGE — this state is immune to the flashlight
	# overcharge (the Director's CHARGE IGNORES FLASHLIGHT rule), so the
	# Entity will aggressively pursue the player even if they shine the beam.
	if _entity.has_method("set_state"):
		_entity.set_state(EntityAI.State.CHARGE)
	if "state_locked" in _entity:
		_entity.state_locked = true  # Lock so the Director doesn't override mid-charge
	
	# ─── RE-TARGET THE PLAYER ─────────────────────────────────────────
	var near_player = get_tree().get_first_node_in_group("player")
	if near_player and _entity.has_method("get_nav_agent"):
		var nav_agent = _entity.get_nav_agent()
		if nav_agent:
			nav_agent.target_position = near_player.global_position
	
	print("[TotemAnchor] TOTEM DEFENSE: Entity teleported to waypoint and forced into CHARGE to defend the totem!")
	_show_hud_message("The Entity guards the totem with violent ferocity!")


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
	tween.tween_callback(hide) # Changed from queue_free


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