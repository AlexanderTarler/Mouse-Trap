extends Node
class_name EntityBlackboard

## Entity Blackboard — centralized shared state and node cache.
## Extracted from entity_controller.gd to satisfy Single Responsibility Principle.
##
## ARCHITECTURE:
##   The Blackboard holds ALL shared state flags, cached node references, and
##   timer variables that were previously scattered across entity_controller.gd.
##   Neither the Director nor the AI modules own state directly — they read/write
##   through the Blackboard API.
##
##   The entity_controller.gd (Motor Hub) creates this as a child node and
##   delegates all state reads/writes through it. Sub-modules (sensory, ai,
##   navigation) access via `entity.get_blackboard()`.

# ─── REFERENCE: The parent CharacterBody3D (set by entity_controller.gd)
var entity: CharacterBody3D = null

# ─── SUB-MODULE REFERENCES ──────────────────────────────────────────────
var ai: Node = null          # EntityAI
var sensory: Node = null     # EntitySensory
var navigation: Node = null  # EntityNavigation
var confidence: Node = null  # EntityConfidence
var controller = null        # entity_controller.gd (typed loosely to avoid cyclic)

# ─── CACHED NODE REFERENCES ─────────────────────────────────────────────
var nav_agent: NavigationAgent3D = null
var collision_shape: CollisionShape3D = null
var monster_model: Node3D = null
var anim_tree: AnimationTree = null
var anim_state_machine: AnimationNodeStateMachinePlayback = null
var growl_audio: AudioStreamPlayer3D = null
var footstep_audio: AudioStreamPlayer3D = null
var voice_player: AudioStreamPlayer3D = null
var player: Node3D = null

# Cached scene-tree nodes (resolved once to avoid per-frame lookups)
var fuse_box_node: Node = null
var door_node: Node = null
var door_breach_waypoint: Node3D = null
var fuse_waypoint: Marker3D = null
var door_waypoint_marker: Node3D = null
var portable_trap: Node = null
var cabin_lights: Array[Node] = []
var cabin_center: Vector3 = Vector3(0.0, 0.0, 14.88)
var night_manager: Node = null
var room_light_detector: Node = null

# ─── CHASE MUSIC AUDIO ──────────────────────────────────────────────────
var chase_music_player: AudioStreamPlayer = null
var chase_music_was_playing: bool = false
var chase_exit_grunt_player: AudioStreamPlayer = null
var light_sanctuary_grunt_player: AudioStreamPlayer = null

# ─── NIGHT AMBIENCE AUDIO ───────────────────────────────────────────────
var night_ambience_player: AudioStreamPlayer = null
var night_ambience_was_playing: bool = false

# ─── BLACKBOARD STATE FLAGS ─────────────────────────────────────────────
@export_group("Blackboard - State Flags")

## When true, the state handler is mid-execution and the Director must
## not override the state. Prevents State Flapping.
var state_locked: bool = false

## When true, abort state transitions during door/window breach.
var is_breach_locked: bool = false
var breach_lock_timer: float = 0.0

## Last successful door breach timestamp (seconds from Time.get_ticks_msec()/1000).
var last_door_breach_time: float = -999.0

## Completion flags consumed by the Director each evaluation cycle.
var is_approach_finished: bool = false
var is_window_unbarricaded: bool = false
var is_climb_finished: bool = false  # Deprecated, kept for API compatibility
var was_door_entry: bool = false
var is_retreat_arrived: bool = false
var is_flinch_finished: bool = false
var is_observe_finished: bool = false
var is_indoor_retreat: bool = false
var is_fuse_sabotaged: bool = false
var is_door_locked: bool = false
var is_door_target: bool = false
var is_charge_triggered: bool = false

## Physics suspension flag — bypasses move_and_slide() when ghost motor is active.
var is_physics_suspended: bool = false

@export_group("Blackboard - Sensory Data")

## Whether the Entity is illuminated by the player's flashlight.
var is_illuminated: bool = false

## Whether the Entity BELIEVES the player is inside the cabin.
var thinks_player_is_inside: bool = true

## How long the player has been staring at the Entity.
var player_stare_timer: float = 0.0

## Last known world-space position of the player.
var last_known_position: Vector3 = Vector3.ZERO

## Whether the player is currently in the Entity's line of sight.
var player_in_sight: bool = false

## Last heard room name (indoor search acoustic detection).
var last_known_room_name: String = ""

## Exact position of the last noise heard.
var last_heard_exact_position: Vector3 = Vector3.ZERO

# ─── STATE TRACKING ─────────────────────────────────────────────────────
var state: int = -1  # EntityAI.State enum value
var last_state: int = -1
var state_timer: float = 0.0
var path_timer: float = 0.0
var stuck_timer: float = 0.0
var game_time: float = 0.0
var is_active: bool = false
var is_hunting: bool = false
var is_fading: bool = false
var is_fleeing: bool = false
var is_enraged: bool = false
var has_played_light_sound: bool = false

# ─── STUCK DETECTION ────────────────────────────────────────────────────
var pos_stuck_timer: float = 0.0
var last_stuck_position: Vector3 = Vector3.ZERO
var pos_stuck_logged: bool = false

# ─── RELOCATION ─────────────────────────────────────────────────────────
var relocate_cooldown: float = 0.0
var relocate_target_set: bool = false
var flee_angle: float = 0.0
var flee_direction: int = 1

# ─── NIGHT DIFFICULTY ───────────────────────────────────────────────────
var current_night: int = 1
var window_peek_chance: float = 0.60
var current_stalk_speed: float = 4.0
var current_relocate_cooldown: float = 2.5

# ─── FLINCH STATE ───────────────────────────────────────────────────────
var flinch_enabled: bool = true
var flinched_timer: float = 0.0
var flinch_target_pos: Vector3 = Vector3.ZERO
var was_chasing: bool = false
var chase_exit_grunt_cooldown: float = 0.0

# ─── WINDOW PEEK STATE ──────────────────────────────────────────────────
var window_peek_timer: float = 0.0
var window_peek_duration: float = 12.0
var window_peek_marker: Node3D = null
var window_peek_spotted: bool = false
var window_peek_vanish_timer: float = 0.0
var window_peek_vanish_delay: float = 1.0
var window_peek_staging_pos: Vector3 = Vector3.ZERO
var retreat_timer: float = 0.0

# ─── LAMP / FUSE ATTACK ─────────────────────────────────────────────────
var lamp_attack_timer: float = 0.0
var fuse_sabotage_timer: float = 0.0

# ─── BREACH STATE ───────────────────────────────────────────────────────
var last_breached_window: Node = null
var indoor_landing_position: Vector3 = Vector3.ZERO
var current_window_target: Node = null
var door_phase: int = 0
var door_phase_timer: float = 0.0
var door_phase_2_timer: float = 0.0
var door_approach_cooldown: float = 0.0
var is_door_open: bool = false  # Mirrors door.is_open

# ─── GHOST MOTOR ────────────────────────────────────────────────────────
var ghost_target: Vector3 = Vector3.ZERO
var ghost_mode: bool = false
var ghost_door_phase_2: bool = false
var ghost_frame_count: int = 0

# ─── CONSECUTIVE MISSES (Window Shopping) ──────────────────────────────
var consecutive_vantage_misses: int = 0

# ─── VOICE STATE ────────────────────────────────────────────────────────
var voice_angry_played_this_charge: bool = false

# ─── MISC ───────────────────────────────────────────────────────────────
var at_vantage_point: bool = false
var stare_timer: float = 0.0
var ai_debug_timer: float = 0.0
var has_logged_sight: bool = false
var catch_distance: float = 1.5
var path_update_interval: float = 0.3


## Initialize the Blackboard with references to all sub-modules and nodes.
## Called by entity_controller.gd's _initialize_entity() after this node is
## added as a child.
func initialize(controller_node) -> void:
	controller = controller_node
	entity = controller_node as CharacterBody3D
	
	# Sub-module references
	ai = controller_node.get_node_or_null("EntityAI")
	sensory = controller_node.get_node_or_null("EntitySensory")
	navigation = controller_node.get_node_or_null("EntityNavigation")
	confidence = controller_node.get_node_or_null("EntityConfidence")
	
	# Core node references
	nav_agent = controller_node.get_node_or_null("NavigationAgent3D")
	collision_shape = controller_node.get_node_or_null("CollisionShape3D")
	monster_model = controller_node.get_node_or_null("MonsterModel")
	anim_tree = controller_node.get_node_or_null("AnimationTree")
	growl_audio = controller_node.get_node_or_null("GrowlAudio")
	footstep_audio = controller_node.get_node_or_null("FootstepAudio")
	voice_player = controller_node.get_node_or_null("VoicePlayer")
	
	# Resolve anim state machine from animation tree
	if anim_tree:
		anim_state_machine = anim_tree.get("parameters/playback")
	
	# Player reference
	player = controller_node.get_tree().get_first_node_in_group("Player")
	
	# Night manager
	night_manager = controller_node.get_node_or_null("/root/NightManager")
	room_light_detector = controller_node.get_node_or_null("/root/RoomLightDetector")


## Returns the current state as a Dictionary for debug overlay display.
func to_debug_dict() -> Dictionary:
	return {
		"state_locked": state_locked,
		"is_illuminated": is_illuminated,
		"thinks_player_is_inside": thinks_player_is_inside,
		"player_stare_timer": player_stare_timer,
		"state": state,
		"is_hunting": is_hunting,
		"is_enraged": is_enraged,
	}