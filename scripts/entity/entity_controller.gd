extends CharacterBody3D

## "The Entity" — the main antagonist.
## Systemic Hunting Paradigm: The Entity uses vision cones and audio pings to track the player.
##
## Orchestrator node that delegates to sub-modules:
##   - entity_ai.gd        → FSM state behaviors
##   - entity_sensory.gd   → Vision cone, flashlight detection, audio hearing
##   - entity_navigation.gd → Vantage point selection, outside detection

enum State {
	DORMANT,
	OBSERVE_FROM_TREELINE,  # Night 1 & 2 (Passive Voyeurism)
	PATROL,                 # Wandering the map looking for clues
	CHASE,                  # Active pursuit (Line of sight established)
	RETREAT,                # Physically running away to deep woods
	APPROACH_WINDOW,        # Night 3+ (Moving to glass)
	WINDOW_PEEK,            # Night 2+ (Staring inside)
	RELOCATE,               # Fading out and teleporting to a new position
	STANDOFF,               # Player is staring at Entity with flashlight — frozen in place
	CHARGE,                 # Player stared too long — Entity sprints at 3x speed
}

@export var speed: float = 4.0
@export var catch_distance: float = 2.5
@export var relocate_radius: float = 20.0
@export var path_update_interval: float = 0.3
@export var stuck_timeout: float = 1.5
@export var fade_duration: float = 0.5
@export var shadow_material: Material = null

@onready var _nav_agent: NavigationAgent3D = $NavigationAgent3D
@onready var _collision_shape: CollisionShape3D = $CollisionShape3D
@onready var _monster_model: Node3D = $MonsterModel if has_node("MonsterModel") else null
@onready var _anim_tree: AnimationTree = $AnimationTree if has_node("AnimationTree") else null
@onready var _growl_audio: AudioStreamPlayer3D = $GrowlAudio if has_node("GrowlAudio") else null
@onready var _footstep_audio: AudioStreamPlayer3D = $FootstepAudio if has_node("FootstepAudio") else null

# Catch Area — a wide overlap zone that detects the player before physics
# collision pushback prevents the distance check from triggering.
var _catch_area: Area3D = null

# Chase music — 2D (non-positional) soundtrack that plays during active pursuit
var _chase_music_player: AudioStreamPlayer = null
var _chase_music_was_playing: bool = false
const CHASE_MUSIC_PATH: String = "res://assets/audio/Echoes - Audio Super Kit/OGG (recommended)/Ambiences/ambience_d6_loop.ogg"
const CHASE_MUSIC_FADE_SPEED: float = 2.0  # Seconds to fade in/out
const CHASE_MUSIC_VOLUME_DB: float = -8.0

# Grunt sound when leaving CHASE state
var _chase_exit_grunt_player: AudioStreamPlayer = null
var _was_chasing: bool = false
const CHASE_EXIT_GRUNT_PATH: String = "res://assets/audio/Entity/Entity_grunt_long.ogg"

# Night ambience — 2D background soundtrack that plays during non-chase night hours
var _night_ambience_player: AudioStreamPlayer = null
var _night_ambience_was_playing: bool = false
const NIGHT_AMBIENCE_PATH: String = "res://assets/audio/Echoes - Audio Super Kit/OGG (recommended)/Ambiences/ambience_d1_loop.ogg"
const NIGHT_AMBIENCE_FADE_SPEED: float = 3.0  # Seconds to fade in/out
const NIGHT_AMBIENCE_VOLUME_DB: float = -18.0

# Sub-modules
@onready var _ai: Node = $EntityAI if has_node("EntityAI") else null
@onready var _sensory: Node = $EntitySensory if has_node("EntitySensory") else null
@onready var _navigation: Node = $EntityNavigation if has_node("EntityNavigation") else null

var _anim_state_machine: AnimationNodeStateMachinePlayback = null
var _entity_step_timer: float = 0.0
var _entity_step_interval: float = 0.5

var _player: Node3D = null
var _state: State = State.DORMANT
var _is_active: bool = false
var _path_timer: float = 0.0
var _stuck_timer: float = 0.0
var _game_time: float = 0.0

# --- SENSORY & HUNTING VARIABLES ---
var _last_known_position: Vector3 = Vector3.ZERO
var _current_interest_level: float = 0.0
var _is_hunting: bool = false
var _vision_cone_angle: float = deg_to_rad(70.0) # 140-degree field of view
var _interest_decay_rate: float = 2.5 # How fast it loses interest

# --- DEBUG SETTINGS ---
var _debug_logging_enabled: bool = false  # Set to true to see heartbeat logs

# --- STATE TRACKING ---
var _last_logged_state: State = State.DORMANT
var _ai_debug_timer: float = 0.0
var _has_logged_sight: bool = false
var _is_at_vantage_point: bool = false

# --- RELOCATION / FADE STATE ---
var _relocate_cooldown: float = 0.0
var _is_fading: bool = false
var _is_fleeing: bool = false
var _flee_angle: float = 0.0
var _flee_direction: int = 1

# --- NIGHT DIFFICULTY (set by entity_ai.gd) ---
var current_night: int = 1
var window_peek_chance: float = 0.60
var current_stalk_speed: float = 4.0
var current_relocate_cooldown: float = 2.5

# --- WINDOW PEEK STATE ---
var _window_peek_timer: float = 0.0
var _window_peek_duration: float = 12.0
var _window_peek_marker: Node3D = null
var _window_peek_spotted: bool = false
var _window_peek_vanish_timer: float = 0.0
var _window_peek_vanish_delay: float = 1.0
var _window_peek_staging_pos: Vector3 = Vector3.ZERO
var _retreat_timer: float = 0.0
var _current_window_target: Node3D = null
var _stare_timer: float = 0.0
var _outside_log_timer: float = 0.0
var _visited_markers: Array[Node3D] = []
var _last_vantage_point: Node3D = null
var cabin_center: Vector3 = Vector3(0.0, 0.0, 14.88)


func _ready() -> void:
	add_to_group("entity")
	_find_player()
	
	# Set up chase music player (2D, non-positional soundtrack)
	_chase_music_player = AudioStreamPlayer.new()
	_chase_music_player.bus = "Music"
	_chase_music_player.volume_db = -80.0  # Start silent (fade in on chase)
	var chase_stream = load(CHASE_MUSIC_PATH) as AudioStream
	if chase_stream:
		if chase_stream is AudioStreamOggVorbis:
			chase_stream.loop = true
		_chase_music_player.stream = chase_stream
	add_child(_chase_music_player)
	
	# Set up night ambience player (2D, background soundtrack during non-chase night hours)
	_night_ambience_player = AudioStreamPlayer.new()
	_night_ambience_player.bus = "Music"
	_night_ambience_player.volume_db = -80.0  # Start silent (fade in when night starts)
	var ambience_stream = load(NIGHT_AMBIENCE_PATH) as AudioStream
	if ambience_stream:
		if ambience_stream is AudioStreamOggVorbis:
			ambience_stream.loop = true
		_night_ambience_player.stream = ambience_stream
	add_child(_night_ambience_player)
	
	# Set up chase exit grunt player (2D, plays when leaving CHASE state)
	_chase_exit_grunt_player = AudioStreamPlayer.new()
	_chase_exit_grunt_player.bus = "Entity"
	_chase_exit_grunt_player.volume_db = -6.0
	var grunt_stream = load(CHASE_EXIT_GRUNT_PATH) as AudioStream
	if grunt_stream:
		_chase_exit_grunt_player.stream = grunt_stream
	add_child(_chase_exit_grunt_player)
	
	# Set up sub-modules
	if _ai and _ai.has_method("setup"):
		_ai.setup(self)
	if _sensory and _sensory.has_method("setup"):
		_sensory.setup(self)
	if _navigation and _navigation.has_method("setup"):
		_navigation.setup(self)
	
	_nav_agent.path_desired_distance = 2.0
	_nav_agent.target_desired_distance = 2.0
	
	# Validate Model setup
	var active_player: AnimationPlayer = null
	if _monster_model:
		if _monster_model.has_node("AnimationPlayer"):
			active_player = _monster_model.get_node("AnimationPlayer") as AnimationPlayer
	
	if _anim_tree and active_player:
		_anim_tree.anim_player = _anim_tree.get_path_to(active_player)
		_anim_state_machine = _anim_tree.get("parameters/playback")
	
	axis_lock_angular_x = true
	axis_lock_angular_z = true
	floor_constant_speed = true
	floor_snap_length = 0.5
	floor_max_angle = deg_to_rad(60.0)
	
	# Set up the catch area — a wide overlap zone that detects the player
	# before physics collision pushback prevents the distance check from triggering.
	# This ensures the Entity can actually catch the player during a chase.
	_catch_area = Area3D.new()
	_catch_area.name = "CatchArea"
	var catch_shape = CollisionShape3D.new()
	var sphere = SphereShape3D.new()
	sphere.radius = catch_distance
	catch_shape.shape = sphere
	_catch_area.add_child(catch_shape)
	_catch_area.body_entered.connect(_on_catch_area_body_entered)
	add_child(_catch_area)
	
	visible = false
	_set_visuals_visible(false)
	call_deferred("_initialize_entity")


func _set_visuals_visible(v: bool) -> void:
	if _monster_model:
		_monster_model.visible = v


func _initialize_entity() -> void:
	var nm = get_node_or_null("/root/NightManager")
	if nm:
		nm.night_started.connect(_on_night_started)
		nm.night_ended.connect(_on_night_ended)
		nm.first_chase_started.connect(_on_first_chase_started)
		if nm.is_night_active:
			# Night 1 exception: Entity stays hidden for the car alarm narrative
			if nm.current_night == 1:
				print("[Entity] Night 1 at startup: Staying hidden for car alarm narrative.")
			else:
				activate()
				_relocate_behind_player()
	else:
		call_deferred("_initialize_entity")


func _on_night_started(night: int) -> void:
	if _ai and _ai.has_method("on_night_started"):
		_ai.on_night_started(night) # AI updates its speed/chance stats
	
	# Night 1 exception: Entity stays hidden for the car alarm narrative event.
	# The Entity only appears when the player interacts with the van.
	if night == 1:
		print("[Entity] Night 1: Staying hidden for car alarm narrative.")
		return
	
	activate() # Controller handles visibility
	_relocate_behind_player() # Controller handles physical placement


func _on_night_ended(night: int) -> void:
	if _ai and _ai.has_method("on_night_ended"):
		_ai.on_night_ended(night)


## Called when NightManager emits first_chase_started (Night 1 narrative event).
## The Entity makes its cinematic arrival: spawns at the EntityVanSpawn marker,
## then immediately begins chasing the player.
func _on_first_chase_started() -> void:
	print("[Entity] First chase triggered! Making cinematic arrival.")
	
	# Search for the EntityVanSpawn marker in the scene tree.
	# This marker is placed by the level designer at a specific position
	# near the van where the Entity should appear for maximum dramatic impact.
	var spawn_marker: Node3D = null
	var spawn_markers = get_tree().get_nodes_in_group("EntityVanSpawn")
	if not spawn_markers.is_empty():
		spawn_marker = spawn_markers[0] as Node3D
	else:
		# Fallback: try to find a node explicitly named "EntityVanSpawn"
		spawn_marker = get_node_or_null("/root/CottageHorror/EntityVanSpawn")
		if not spawn_marker:
			spawn_marker = get_node_or_null("/root/Main/EntityVanSpawn")
	
	if spawn_marker:
		# Place the Entity exactly at the marker's position
		global_position = spawn_marker.global_position
		_nav_agent.target_position = spawn_marker.global_position
		print("[Entity] Spawned at EntityVanSpawn marker: ", spawn_marker.global_position)
	else:
		# Ultimate fallback: 15 units behind the player
		var behind_dir = -_player.global_transform.basis.z
		var fallback_pos = _player.global_position + behind_dir * 15.0
		fallback_pos.y = 0.0
		global_position = fallback_pos
		_nav_agent.target_position = fallback_pos
		print("[Entity] WARNING: No EntityVanSpawn marker found! Using fallback position.")
	
	# Activate the Entity (make visible) and immediately begin chasing
	activate()
	_state = State.CHASE
	print("[Entity] Cinematic arrival complete! Now chasing the player.")


func _find_player() -> void:
	var players = get_tree().get_nodes_in_group("player")
	if players.size() > 0:
		_player = players[0] as Node3D


func activate() -> void:
	_is_active = true
	visible = true
	_state = State.OBSERVE_FROM_TREELINE
	_set_visuals_visible(true)


func deactivate() -> void:
	_is_active = false
	velocity = Vector3.ZERO
	visible = false
	_state = State.DORMANT
	_set_visuals_visible(false)


func _physics_process(delta: float) -> void:
	_game_time += delta
	
	if _relocate_cooldown > 0.0:
		_relocate_cooldown -= delta
	
	if not _is_active or not _player:
		return
	
	# --- STATE TRANSITION LOGGING ---
	if _state != _last_logged_state:
		print("[Entity FSM] Transitioned from %s to %s" % [State.keys()[_last_logged_state], State.keys()[_state]])
		_last_logged_state = _state
	
	# --- PERIODIC HEARTBEAT LOG (every 2 seconds, only when debug enabled) ---
	if _debug_logging_enabled:
		_ai_debug_timer += delta
		if _ai_debug_timer >= 2.0:
			_ai_debug_timer = 0.0
			var dist_to_player = global_position.distance_to(_player.global_position)
			var nav_target_dist = _nav_agent.target_position.distance_to(global_position) if _nav_agent else 0.0
			var sees_player = _sensory.can_entity_see_player() if _sensory else false
			print("[Entity Heartbeat] State=%s | Pos=(%.1f, %.1f, %.1f) | DistToPlayer=%.1f" % [
				State.keys()[_state], global_position.x, global_position.y, global_position.z, dist_to_player
			])
	
	# --- BACKGROUND SENSE PROCESSING (runs every frame regardless of state) ---
	if _sensory:
		_sensory.can_entity_see_player()
	if _current_interest_level > 0:
		_current_interest_level -= _interest_decay_rate * delta
	
	# --- CHASE MUSIC (ambience_d6_loop) ---
	# Fade in when entering CHASE state, fade out when leaving.
	var is_chasing = _state == State.CHASE
	if is_chasing and not _chase_music_was_playing:
		# Entering chase — start playing and fade in
		if _chase_music_player and _chase_music_player.stream:
			_chase_music_player.play()
		_chase_music_was_playing = true
	elif not is_chasing and _chase_music_was_playing:
		# Leaving chase — begin fade out
		_chase_music_was_playing = false
	
	# --- CHASE EXIT GRUNT ---
	# Play the Entity_grunt_long.ogg sound when the Entity leaves CHASE state.
	# This provides an audio cue that the chase has ended.
	if _was_chasing and not is_chasing:
		if _chase_exit_grunt_player and _chase_exit_grunt_player.stream:
			_chase_exit_grunt_player.play()
			print("[Entity] Playing chase exit grunt.")
	_was_chasing = is_chasing
	
	# Smooth volume interpolation
	if _chase_music_player:
		var target_vol = CHASE_MUSIC_VOLUME_DB if is_chasing else -80.0
		_chase_music_player.volume_db = move_toward(_chase_music_player.volume_db, target_vol, (80.0 / CHASE_MUSIC_FADE_SPEED) * delta)
		# Stop playback once fully silent to save resources
		if not is_chasing and _chase_music_player.volume_db <= -79.0 and _chase_music_player.playing:
			_chase_music_player.stop()
	
	# --- NIGHT AMBIENCE (ambience_d1_loop) ---
	# Plays during active night hours but ducks out during CHASE so the chase
	# music takes over. Fades in/out smoothly to avoid abrupt audio cuts.
	var should_play_ambience = _is_active and not is_chasing
	if should_play_ambience and not _night_ambience_was_playing:
		# Start playing night ambience
		if _night_ambience_player and _night_ambience_player.stream:
			_night_ambience_player.play()
		_night_ambience_was_playing = true
	elif not should_play_ambience and _night_ambience_was_playing:
		# Begin fade out
		_night_ambience_was_playing = false
	
	# Smooth volume interpolation
	if _night_ambience_player:
		var target_vol = NIGHT_AMBIENCE_VOLUME_DB if should_play_ambience else -80.0
		_night_ambience_player.volume_db = move_toward(_night_ambience_player.volume_db, target_vol, (80.0 / NIGHT_AMBIENCE_FADE_SPEED) * delta)
		# Stop playback once fully silent
		if not should_play_ambience and _night_ambience_player.volume_db <= -79.0 and _night_ambience_player.playing:
			_night_ambience_player.stop()
	
	# --- TRANSITION LOCK: RETREAT / RELOCATE / STANDOFF ---
	# During fade/teleport sequences, force velocity to zero and skip movement
	# processing, but STILL execute the AI update tick so that _retreat_state()
	# can call fade_and_relocate(). Without this, the early return would create
	# a deadlock where the AI never runs and the transition never completes.
	# STANDOFF also locks movement — the Entity freezes in place while stared at.
	if _state == State.RETREAT or _state == State.RELOCATE or _state == State.STANDOFF:
		velocity = Vector3.ZERO
		if _ai and _ai.has_method("update"):
			_ai.update(delta)
		_update_animations(delta)
		return
	
	# --- STANDARD ACTIVE NAVIGATION ---
	if not is_on_floor() and _state != State.WINDOW_PEEK:
		velocity += get_gravity() * delta
	
	if _ai and _ai.has_method("update"):
		_ai.update(delta)
	else:
		velocity = Vector3.ZERO
	
	move_and_slide()
	
	var flat_vel = Vector2(velocity.x, velocity.z)
	if flat_vel.length_squared() > 0.05 and _monster_model:
		var target_angle = atan2(flat_vel.x, flat_vel.y)
		_monster_model.rotation.y = lerp_angle(_monster_model.rotation.y, target_angle, delta * 10.0)
	
	_update_animations(delta)


# --- PUBLIC API ---

## Teleports the Entity to a new position behind the player.
## Uses treeline vantage points for ALL nights to prevent the Entity from
## teleporting inside the cabin or right next to the player.
func _relocate_behind_player() -> void:
	if not _player:
		return
	velocity = Vector3.ZERO
	
	# Always pick a treeline vantage point, regardless of night.
	# This prevents the broken "5 units away" fallback that could place
	# the Entity inside the cabin on Night 3+.
	var treeline_markers = get_tree().get_nodes_in_group("Treeline_Vantage_Points")
	if not treeline_markers.is_empty():
		var safe_marker = treeline_markers.pick_random()
		_finalize_relocation(safe_marker.global_position, "Deep Woods Snap")
		return
	
	# Ultimate fallback: teleport far away behind the cabin
	_finalize_relocation(Vector3(9.0, 0.0, 40.0), "Fallback")


func _finalize_relocation(spawn_pos: Vector3, method: String) -> void:
	# Place the Entity directly on the target position.
	# The NavMesh or marker position already defines the correct Y coordinate.
	global_position = spawn_pos
	velocity = Vector3.ZERO
	_stuck_timer = 0.0
	_is_at_vantage_point = false
	_current_window_target = null
	
	# Reset the navigation agent target to the new position so the pathfinder
	# doesn't try to navigate from the new location to a stale old target.
	_nav_agent.target_position = spawn_pos
	
	if current_night <= 2:
		_state = State.OBSERVE_FROM_TREELINE
	elif current_night == 3:
		_state = State.APPROACH_WINDOW
	else:
		_state = State.PATROL


## Initiates a window peek sequence. Sets the state to APPROACH_WINDOW
## and clears the current window target so the AI picks a new one.
func _start_window_peek() -> void:
	if not _is_active or not _player:
		return
	_state = State.APPROACH_WINDOW
	_current_window_target = null
	_nav_agent.target_position = _player.global_position
	print("[Entity] Starting window peek sequence.")


func _on_caught_player() -> void:
	_is_active = false
	velocity = Vector3.ZERO
	if _growl_audio:
		_growl_audio.play()
	var nm = get_node_or_null("/root/NightManager")
	if nm:
		nm.horror_event.emit("entity_caught_player")


## Called when the player enters the Entity's catch area (Area3D overlap zone).
## This provides a reliable catch trigger even when physics collision pushback
## prevents the distance-based check in _stalk_state() from reaching catch_distance.
func _on_catch_area_body_entered(body: Node) -> void:
	if not _is_active:
		return
	if body == _player and _state == State.CHASE:
		print("[Entity] Player entered catch area during chase! Catching player.")
		_on_caught_player()


## Called by the player controller every frame while the player is staring at
## the Entity with the flashlight on. look_timer ranges from 0.0 to 2.0+.
##
## When look_timer > 0.1: Force the Entity into STANDOFF state — frozen in place,
##   oriented to face the player directly.
## When look_timer >= 1.5: Force the Entity into CHARGE state — 3x speed sprint
##   directly at the player with a terrifying screech.
## When look_timer decays back to 0: Return to previous state.
func on_player_stare(look_timer: float) -> void:
	if not _is_active:
		return
	
	# Don't override CHARGE — once charging, the Entity commits
	if _state == State.CHARGE:
		# During CHARGE, continuously update target to the player's current position
		_nav_agent.target_position = _player.global_position
		return
	
	if look_timer >= 1.5 and _state != State.CHARGE:
		# --- TRIGGER CHARGE ---
		_state = State.CHARGE
		_nav_agent.target_position = _player.global_position
		print("[Entity] CHARGE! Player stared too long! Sprinting at 3x speed!")
		
		# Play terrifying screech sound
		if _growl_audio:
			_growl_audio.pitch_scale = 1.5  # Higher pitch for screech
			_growl_audio.play()
		
		return
	
	if look_timer > 0.1:
		# --- STANDOFF STATE ---
		if _state != State.STANDOFF:
			_state = State.STANDOFF
			print("[Entity] STANDOFF! Player is staring at the Entity.")
		
		# Orient the Entity's model to face the player directly
		if _monster_model and _player:
			var dir_to_player = (_player.global_position - global_position).normalized()
			var target_angle = atan2(dir_to_player.x, dir_to_player.z)
			_monster_model.rotation.y = lerp_angle(_monster_model.rotation.y, target_angle, 0.1)
		
		# Freeze velocity
		velocity = Vector3.ZERO
		
	elif _state == State.STANDOFF:
		# Player looked away — return to previous state
		print("[Entity] Player looked away. Exiting STANDOFF.")
		if current_night <= 2:
			_state = State.OBSERVE_FROM_TREELINE
		elif current_night == 3:
			_state = State.APPROACH_WINDOW
		else:
			_state = State.PATROL


## Smoothly fades the Entity out, teleports to a new location, then reappears.
## Uses Godot 4's Tween to animate transparency on all GeometryInstance3D children.
func fade_and_relocate() -> void:
	if _is_fading:
		return
	_is_fading = true
	_state = State.RELOCATE
	
	# Force-reset animation to Idle before the fade begins.
	# This kills any "Running" or "Stalk" animation loop so the monster
	# doesn't appear to be mid-stride while turning transparent.
	if _anim_state_machine:
		_anim_state_machine.travel("Idle")
	
	# 1. Smooth Fade Out
	if _monster_model:
		var tween = create_tween()
		# Find all mesh instances within the model
		var meshes = _monster_model.find_children("*", "GeometryInstance3D", true, false)
		for mesh in meshes:
			# 0.0 is opaque, 1.0 is fully transparent
			tween.parallel().tween_property(mesh, "transparency", 1.0, fade_duration)
		
		await tween.finished
		_monster_model.visible = false
		
		# Reset transparency so it is solid when it reappears
		for mesh in meshes:
			mesh.transparency = 0.0
	
	# 2. Wait in the void
	await get_tree().create_timer(randf_range(3.0, 6.0)).timeout
	
	# 3. Pick a new node and teleport
	# For ALL nights, pick a fresh vantage point so the Entity never
	# reappears at a stale coordinate. On Night 3+, the AI state will
	# transition to APPROACH_WINDOW or PATROL after relocation anyway.
	_navigation.pick_next_vantage_point()
	
	# Place the Entity directly on the NavMesh target position.
	# The NavMesh already defines the perfect Y coordinate for the ground,
	# so no vertical buffer is needed. This prevents the entity from
	# appearing to "fall from the sky" when it reappears.
	global_position = _nav_agent.target_position
	
	# 4. Reappear instantly in the new location
	if _monster_model:
		_monster_model.visible = true
	
	_is_fading = false
	_state = State.OBSERVE_FROM_TREELINE
	if _ai and _ai.has_method("reset_exposure"):
		_ai.reset_exposure()


func _update_animations(_delta: float) -> void:
	if not _anim_state_machine:
		return
	
	# Strictly enforce model grounding offset across ALL frames
	if _monster_model:
		_monster_model.position = Vector3(0.0, -0.95, 0.0)
	
	# Hard clamp animations to Idle if we are fading, relocating, or in a
	# frozen standoff. This prevents the animation state machine from caching
	# and continuously looping the previous sprinting animation during
	# supernatural transitions or while the Entity is locked in place.
	if _state == State.RETREAT or _state == State.RELOCATE or _state == State.DORMANT or _state == State.STANDOFF:
		_anim_state_machine.travel("Idle")
		return
	
	var real_vel := get_real_velocity()
	var horz_speed := Vector2(real_vel.x, real_vel.z).length()
	
	match _state:
		State.CHARGE:
			# Use the running_crawl animation during CHARGE for a terrifying sprint
			_anim_state_machine.travel("running_crawl")
		State.STANDOFF:
			# Drop into Idle while maintaining eye contact with the player
			_anim_state_machine.travel("Idle")
		State.CHASE, State.APPROACH_WINDOW, State.OBSERVE_FROM_TREELINE, State.PATROL:
			if real_vel.y > 0.8:
				_anim_state_machine.travel("ClimbUp")
			elif real_vel.y < -0.8 and not is_on_floor():
				_anim_state_machine.travel("ClimbDown")
			elif horz_speed > 0.2:
				_anim_state_machine.travel("Stalk")
			else:
				_anim_state_machine.travel("Idle")
		_:
			_anim_state_machine.travel("Idle")
