extends CharacterBody3D
class_name NPCController

## Main NPC controller with schedule-driven behavior.
## Uses the Entity component system for movement and visuals.

signal activity_changed(activity: NPCScheduler.Activity)

## Reference to the scheduler
@export var scheduler: NPCScheduler

## NPC data for this character
var npc_data: NPCData

## Current movement target
var _current_target: Vector3

## Wander state
var _wander_timer: float = 0.0
var _wander_radius: float = 5.0

## Arrival distance threshold
var _arrival_distance: float = 2.0

## Whether the NPC is ready to start moving
var _ready_to_move: bool = false

## Reference to the loaded character model instance
var _character_model: Node3D = null

## Reference to the AnimationPlayer on the character model
var _animation_player: AnimationPlayer = null

## Current animation state
enum AnimState { IDLE, WALK }
var _anim_state: int = AnimState.IDLE

func _ready() -> void:
	# Disable physics processing until fully initialized
	set_physics_process(false)
	
	# Wait a few frames for everything to initialize
	await get_tree().physics_frame
	await get_tree().physics_frame
	await get_tree().physics_frame
	
	_ready_to_move = true
	
	# Re-enable physics processing
	set_physics_process(true)
	
	# Debug: log NPC info
	print("NPC %s ready at %s" % [npc_data.npc_name if npc_data else "unknown", global_position])


func _physics_process(delta: float) -> void:
	if not npc_data or not scheduler or not _ready_to_move:
		return
	
	# Get current schedule activity
	var game_hour = 8.0
	if Engine.has_singleton("GameTime"):
		var gt = Engine.get_singleton("GameTime")
		game_hour = gt.current_hour
	var current_entry: Dictionary = scheduler.get_current_activity(game_hour)
	var current_activity: int = current_entry["activity"] as int
	var current_target: Vector3 = current_entry["target"] as Vector3
	
	# Handle movement based on activity
	match current_activity:
		NPCScheduler.Activity.WALK_HOME, NPCScheduler.Activity.WALK_WORK, \
		NPCScheduler.Activity.WALK_SHOP, NPCScheduler.Activity.WALK_WANDER:
			_move_to_target(current_target, delta)
		
		NPCScheduler.Activity.WANDER:
			_handle_wander(delta)
		
		NPCScheduler.Activity.IDLE:
			# Stand still
			pass
		
		NPCScheduler.Activity.HOME, NPCScheduler.Activity.WORK, NPCScheduler.Activity.SHOP:
			# Arrived at destination - stand still
			pass
	
	# Update animation based on movement
	_update_animation()
	
	# Face movement direction
	if velocity.length() > 0.1:
		var look_dir = Vector3(velocity.x, 0, velocity.z).normalized()
		if look_dir.length() > 0.01:
			var target_basis = Basis.looking_at(look_dir, Vector3.UP)
			transform.basis = transform.basis.slerp(target_basis, delta * 8.0)


## Sets up this NPC with data, loads the character model, and builds schedule.
func initialize(data: NPCData) -> void:
	npc_data = data
	
	# Load the character model
	_load_character_model(data.character_type)
	
	# Build schedule
	if scheduler:
		scheduler.build_schedule(data)


## Loads a glTF character model and attaches it to this NPC.
func _load_character_model(character_type: String) -> void:
	var scene_path = NPCGenerator.get_character_scene_path(character_type)
	
	# Remove any existing model
	if _character_model:
		_character_model.queue_free()
		_character_model = null
		_animation_player = null
	
	# Load the glTF scene
	var model_scene = load(scene_path) as PackedScene
	if not model_scene:
		push_error("NPC %s: Failed to load model: %s" % [npc_data.npc_name, scene_path])
		return
	
	# Instantiate the model
	_character_model = model_scene.instantiate() as Node3D
	if not _character_model:
		push_error("NPC %s: Invalid model scene" % npc_data.npc_name)
		return
	
	add_child(_character_model)
	
	# Find the AnimationPlayer in the model
	_find_animation_player(_character_model)
	
	# Scale the model to fit (glTF models are often at different scales)
	_character_model.scale = Vector3(1.0, 1.0, 1.0)
	
	# Position the model so feet are at ground level
	_character_model.position.y = 0.0


## Recursively finds the AnimationPlayer in the model hierarchy.
func _find_animation_player(node: Node) -> void:
	if node is AnimationPlayer:
		_animation_player = node
		# Play idle animation by default
		if _animation_player.has_animation("Idle"):
			_animation_player.play("Idle")
		elif _animation_player.get_animation_list().size() > 0:
			_animation_player.play(_animation_player.get_animation_list()[0])
		return
	
	for child in node.get_children():
		_find_animation_player(child)


## Updates the animation based on movement state.
func _update_animation() -> void:
	if not _animation_player:
		return
	
	var is_moving = velocity.length() > 0.2
	var target_state = AnimState.WALK if is_moving else AnimState.IDLE
	
	if target_state == _anim_state:
		return  # Already in correct state
	
	_anim_state = target_state
	
	match _anim_state:
		AnimState.IDLE:
			if _animation_player.has_animation("Idle"):
				_animation_player.play("Idle")
			elif _animation_player.has_animation("idle"):
				_animation_player.play("idle")
		AnimState.WALK:
			if _animation_player.has_animation("Walk"):
				_animation_player.play("Walk")
			elif _animation_player.has_animation("walk"):
				_animation_player.play("walk")


## Returns the NPC's data (used by NPCScheduler).
func get_npc_data() -> NPCData:
	return npc_data


func _move_to_target(target: Vector3, delta: float) -> void:
	# Check if we're already close to the target
	var dist_to_target = global_position.distance_to(target)
	if dist_to_target < _arrival_distance:
		velocity = Vector3.ZERO
		return
	
	# Move directly toward target
	var direct_dir = (target - global_position).normalized()
	direct_dir.y = 0.0
	if direct_dir.length() > 0.01:
		velocity = direct_dir * npc_data.walk_speed
	else:
		velocity = Vector3.ZERO
	
	# Move the NPC directly (no physics collision)
	global_position += velocity * delta


func _handle_wander(delta: float) -> void:
	_wander_timer -= delta
	
	if _wander_timer <= 0.0:
		# Pick a new random wander target
		var random_offset = Vector3(
			randf_range(-_wander_radius, _wander_radius),
			0.0,
			randf_range(-_wander_radius, _wander_radius)
		)
		_current_target = global_position + random_offset
		_wander_timer = randf_range(3.0, 8.0)
	
	# Move directly toward wander target
	var direct_dir = (_current_target - global_position).normalized()
	direct_dir.y = 0.0
	if direct_dir.length() > 0.01:
		velocity = direct_dir * npc_data.walk_speed * 0.5
	else:
		velocity = Vector3.ZERO
	
	# Move the NPC directly (no physics collision)
	global_position += velocity * delta


func _on_time_changed(hour: float) -> void:
	if not scheduler:
		return
	
	var entry: Dictionary = scheduler.get_current_activity(hour)
	var activity: int = entry["activity"] as int
	activity_changed.emit(activity)
