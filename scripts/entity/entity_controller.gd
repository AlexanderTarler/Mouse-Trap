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
	RELOCATE,               # Safe initialization state only — never used during active runtime
	STANDOFF,               # Player is staring at Entity with flashlight — frozen in place
	FLINCH,                 # Player inside, Entity outside — lateral sprint to evade flashlight
	CHARGE,                 # Player stared too long — Entity sprints at 3x speed
	INDOOR_SEARCH,          # Entity has breached a window and is hunting inside the cabin
	CLIMB_WALL,             # Entity is climbing the exterior wall to a second-story window
	STUNNED,                # Entity is paralyzed by the porch light overload trap
	ENRAGED,                # Blackout released Entity — permanent speed boost for the rest of the night
	ATTACK_LAMP,            # Entity is physically approaching and striking the portable high-voltage lamp
	HARASS,                 # Entity stands at a window performing psychological harassment (breathing, tapping, rattling)
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
var _chase_exit_grunt_cooldown: float = 0.0
const CHASE_EXIT_GRUNT_COOLDOWN_DURATION: float = 5.0
const CHASE_EXIT_GRUNT_PATH: String = "res://assets/audio/Entity/Entity_grunt_long.ogg"

# Grunt sound when Entity is repelled by light sanctuary (one-shot, higher pitch)
var _light_sanctuary_grunt_player: AudioStreamPlayer = null

## Debounce flag for the light sanctuary grunt sound.
## Prevents the frustrated grunt from repeating every frame while the player
## remains in a lit room. Set to true when the sound plays, reset to false
## when the Entity fades/relocates or resets exposure.
var _has_played_light_sound: bool = false

# Night ambience — 2D background soundtrack that plays during non-chase night hours
var _night_ambience_player: AudioStreamPlayer = null
var _night_ambience_was_playing: bool = false
const NIGHT_AMBIENCE_PATH: String = "res://assets/audio/Echoes - Audio Super Kit/OGG (recommended)/Ambiences/ambience_d1_loop.ogg"
const NIGHT_AMBIENCE_FADE_SPEED: float = 3.0  # Seconds to fade in/out
const NIGHT_AMBIENCE_VOLUME_DB: float = -18.0

# Sub-modules
@onready var _ai: Node = $EntityAI if has_node("EntityAI") else null
@onready var _sensory: Node = $EntitySensory if has_node("EnttySensory") else null
@onready var _navigation: Node = $EntityNavigation if has_node("EntityNavigation") else null
@onready var _confidence: Node = $EntityConfidence if has_node("EntityConfidence") else null

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

# --- FLINCH STATE (Flashlight Evasion) ---
## Whether flinching is enabled for the current night.
## Set to false on Night 5 — the Entity never flinches, it immediately sieges.
var _flinch_enabled: bool = true

## Timer counting down the flinch sprint duration (default 1.5 seconds).
var _flinched_timer: float = 0.0

## The world-space position the Entity sprints toward during the flinch.
## Calculated as a lateral vector perpendicular to the player's camera view.
var _flinch_target_pos: Vector3 = Vector3.ZERO

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

# --- INDOOR BREACH STATE ---
## Reference to the CabinWindow that the Entity broke through to enter the cabin.
## Used by INDOOR_SEARCH to know which window to retreat back through when
## repelled by a light sanctuary.
var _indoor_breach_window: CabinWindow = null


## Index into the Cabin_Patrol_Waypoints group for indoor search patrol looping.
var _indoor_patrol_index: int = 0

# --- WALL CLIMB STATE ---
## Claw-scraping audio player (3D, positioned on the exterior wall).
## Plays a scraping sound as the Entity climbs up the wooden siding.
var _claw_scrape_player: AudioStreamPlayer3D = null

# --- 3D SPATIAL VOICE STATE MACHINE ---
## 3D spatial audio player for the Entity's voice (talking, searching, angry).
## Programmatically created in _ready() with inverse-square distance attenuation.
## The voice is routed by entity_ai.gd's _manage_spatial_voice() based on FSM state.
var _voice_player: AudioStreamPlayer3D = null

## Audio streams for the voice state machine.
## Loaded safely using ResourceLoader.exists() guards.
var _voice_talking_1: AudioStream = null
var _voice_talking_2: AudioStream = null
var _voice_searching: AudioStream = null
var _voice_angry: AudioStream = null

## Harassment audio player (3D, positioned at the window during HARASS state).
## Plays intimate sounds (breathing, tapping, rattling) to psychologically
## pressure the player. Created programmatically in _ready().
var _harass_audio: AudioStreamPlayer3D = null

## Paths to the Entity voice audio assets.
const VOICE_TALKING_1_PATH: String = "res://assets/audio/Entity/entity_talking_1.ogg"
const VOICE_TALKING_2_PATH: String = "res://assets/audio/Entity/entity_talking_2.ogg"
const VOICE_SEARCHING_PATH: String = "res://assets/audio/Entity/entity_searching.ogg"
const VOICE_ANGRY_PATH: String = "res://assets/audio/Entity/entity_angry.ogg"

## Whether the angry voice has been played this charge instance.
## Set to true when entity_angry.ogg fires during CHARGE/CHASE entry.
## Reset to false when the Entity leaves CHARGE/CHASE state.
var _voice_angry_played_this_charge: bool = false

## Tracks whether the voice player was in a "talking" state (OBSERVE_FROM_TREELINE/PATROL)
## on the previous frame. Used by _manage_spatial_voice() to detect transitions
## between talking and non-talking states for the interchangeable track cycling.
var _voice_was_talking: bool = false

# --- WINDOW BLUFF STATE ---
## When true, the Entity is performing a fake window approach (bluff).
## The Entity moves toward a window, stops short, then backs away to
## create tension and uncertainty for the player.
var _window_bluff_active: bool = false

## Timer for the window bluff sequence.
## Counts down the approach phase, pause phase, and retreat phase.
var _window_bluff_timer: float = 0.0

## The position the Entity retreats to after a bluff.
## Set to the Entity's starting position when the bluff began.
var _window_bluff_retreat_pos: Vector3 = Vector3.ZERO

## Cooldown timer preventing back-to-back bluffs.
## Set to a random value between 8-15 seconds after each bluff completes.
var _window_bluff_cooldown: float = 0.0

# --- LIGHT SABOTAGE STATE ---
## Cooldown timer for light sabotage.
## The Entity can only sabotage one light every 30 seconds to prevent
## the mechanic from being too oppressive.
var _light_sabotage_cooldown: float = 0.0

# --- LAMP ATTACK TIMING ---
## Timer counting up to 3.0 seconds between Entity strikes on the portable
## high-voltage lamp trap. Incremented by delta each frame while the Entity
## is within hitting distance of an active, deployed lamp. When it reaches
## 3.0, the Entity calls take_physical_hit() on the lamp and resets.
var _lamp_attack_timer: float = 0.0

# --- OVERLOAD STUN STATE ---
## Timer counting down the stun duration (seconds remaining).
## Set by trigger_overload_stun() and decremented each frame during STUNNED.
## When it reaches 0.0, the Entity is released from the stun.
var _stun_timer: float = 0.0


## Whether the Entity has been enraged by a blackout this night.
## Once set to true, the Entity's movement speed is permanently boosted
## by 1.5x for the rest of the night. Reset to false when the night ends.
var _is_enraged: bool = false

## Tracks whether the player was staring at the Entity with the flashlight
## on the previous frame. Used by the confidence modification system to
## detect the transition from "staring" to "not staring" and apply the
## one-time +8.0 confidence boost exactly once when line of sight breaks.
var _confidence_stare_was_active: bool = false

## The original stalk speed before the enrage multiplier was applied.
## Used to restore the speed if the enrage is ever reset.
var _original_stalk_speed: float = 0.0


## Path to the claw scrape audio asset. If the file doesn't exist at this path,
## a programmatic fallback is used: the door creak/grunt asset loaded at pitch 0.4,
## looped, with a randomized stutter effect to simulate nails dragging on wood.
const CLAW_SCRAPE_PATH: String = "res://assets/audio/Entity/claw_scrape_loop.ogg"
const CLAW_SCRAPE_FALLBACK_PATH: String = "res://assets/audio/Entity/Entity_grunt_long.ogg"

# ─── "CREEPING GHOST" COLLISION LAYER SYSTEM ──────────────────────────────────
# When the Entity is traveling outside through dense woods (OBSERVE_FROM_TREELINE,
# PATROL), it programmatically disables hard physics collisions with tree/rock
# environmental layers. This allows the Entity to phase through foliage while
# still following the NavigationAgent3D path for steering.
#
# Full physics body collision masks are re-enabled the moment the Entity
# transitions into CHASE, APPROACH_WINDOW, or enters the cabin porch zone,
# ensuring it cannot phase through doors or window frames during an attack.
#
# Collision layers are defined in the project settings (project.godot).
# These constants map to the layer indices used in the physics layer names.
# Adjust these values to match the project's actual layer assignments.
const COLLISION_LAYER_TREE: int = 3   # Layer 3: Trees / large foliage
const COLLISION_LAYER_ROCK: int = 4   # Layer 4: Rocks / boulders / terrain obstacles
const COLLISION_LAYER_CABIN: int = 1  # Layer 1: Cabin geometry (walls, doors, windows)
const COLLISION_LAYER_PLAYER: int = 2 # Layer 2: Player body

## Stores the original collision mask before "Creeping Ghost" modifications.
## Restored when the Entity transitions to an aggressive state.
var _saved_collision_mask: int = 0

# ─── CONTEXT-STEERING RAYCAST ARRAY ──────────────────────────────────────────
# Three RayCast3D nodes used for obstacle avoidance when the Entity is stalking
# with tree/rock collisions disabled (OBSERVE_FROM_TREELINE, PATROL).
# Programmatically instantiated in _ready().
var _ray_center: RayCast3D = null
var _ray_left: RayCast3D = null
var _ray_right: RayCast3D = null


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
	
	# Set up chase exit grunt player (2D, plays ONCE when leaving CHASE state).
	# Uses duplicate() to create an independent copy of the audio stream so that
	# modifying its properties (e.g., loop = false) does NOT affect the shared
	# resource used by the light sanctuary grunt player below.
	_chase_exit_grunt_player = AudioStreamPlayer.new()
	_chase_exit_grunt_player.bus = "Entity"
	_chase_exit_grunt_player.volume_db = -6.0
	var grunt_stream = load(CHASE_EXIT_GRUNT_PATH) as AudioStream
	if grunt_stream:
		grunt_stream = grunt_stream.duplicate()
		if grunt_stream is AudioStreamOggVorbis:
			grunt_stream.loop = false
		_chase_exit_grunt_player.stream = grunt_stream
	add_child(_chase_exit_grunt_player)
	
	# Set up light sanctuary grunt player (2D, one-shot when Entity is repelled by light).
	# Uses duplicate() to create an independent copy so it doesn't interfere with
	# the chase exit grunt's stream settings.
	_light_sanctuary_grunt_player = AudioStreamPlayer.new()
	_light_sanctuary_grunt_player.bus = "Entity"
	_light_sanctuary_grunt_player.volume_db = -3.0  # Slightly louder than chase exit
	_light_sanctuary_grunt_player.pitch_scale = 1.3  # Higher pitch = frustrated/angry
	var sanctuary_stream = load(CHASE_EXIT_GRUNT_PATH) as AudioStream
	if sanctuary_stream:
		sanctuary_stream = sanctuary_stream.duplicate()
		if sanctuary_stream is AudioStreamOggVorbis:
			sanctuary_stream.loop = false
		_light_sanctuary_grunt_player.stream = sanctuary_stream
	add_child(_light_sanctuary_grunt_player)

	
	# Set up claw scrape audio player (3D, positioned on the exterior wall during climbs)
	_claw_scrape_player = AudioStreamPlayer3D.new()
	_claw_scrape_player.bus = "Entity"
	_claw_scrape_player.max_distance = 30.0  # Audible from anywhere near the cabin
	_claw_scrape_player.volume_db = -6.0
	var scrape_stream: AudioStream = null
	if ResourceLoader.exists(CLAW_SCRAPE_PATH):
		scrape_stream = load(CLAW_SCRAPE_PATH) as AudioStream
	if not scrape_stream:
		# Programmatic fallback: load the grunt sound, lower pitch to 0.4, loop it
		print("[Entity] Claw scrape audio not found at ", CLAW_SCRAPE_PATH, ". Using fallback.")
		if ResourceLoader.exists(CLAW_SCRAPE_FALLBACK_PATH):
			scrape_stream = load(CLAW_SCRAPE_FALLBACK_PATH) as AudioStream
		if scrape_stream:
			if scrape_stream is AudioStreamOggVorbis:
				scrape_stream.loop = true
			# The pitch will be set to 0.4 when the climb starts
	if scrape_stream:
		_claw_scrape_player.stream = scrape_stream
	add_child(_claw_scrape_player)
	
	# ─── 3D SPATIAL VOICE PLAYER ──────────────────────────────────
	# Programmatically create an AudioStreamPlayer3D for the Entity's voice.
	# Configured with inverse-square distance attenuation for realistic spatial
	# audio — the voice gets quieter as the player moves away from the Entity.
	# The voice is routed by entity_ai.gd's _manage_spatial_voice() based on
	# the current FSM state (talking, searching, angry).
	_voice_player = AudioStreamPlayer3D.new()
	_voice_player.name = "VoicePlayer"
	_voice_player.bus = "Entity"
	_voice_player.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_SQUARE_DISTANCE
	_voice_player.unit_size = 4.0
	_voice_player.max_distance = 40.0
	_voice_player.pitch_scale = 0.8  # Deep, guttural tone
	add_child(_voice_player)
	
	# ─── HARASSMENT AUDIO PLAYER ──────────────────────────────────
	# Programmatically create an AudioStreamPlayer3D for the HARASS state.
	# Plays intimate sounds (breathing, tapping, rattling) at the window
	# to psychologically pressure the player.
	# Configured with inverse-square attenuation and a short max distance
	# (15.0m) so the sounds are only audible when the player is near the
	# window being harassed.
	_harass_audio = AudioStreamPlayer3D.new()
	_harass_audio.name = "HarassAudio"
	_harass_audio.bus = "Entity"
	_harass_audio.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_SQUARE_DISTANCE
	_harass_audio.unit_size = 2.0
	_harass_audio.max_distance = 15.0
	add_child(_harass_audio)
	
	# ─── SAFE AUDIO LOADING ───────────────────────────────────────
	# Load the 4 voice audio streams using ResourceLoader.exists() guards
	# to avoid engine warnings when the files don't exist yet.
	if ResourceLoader.exists(VOICE_TALKING_1_PATH):
		_voice_talking_1 = load(VOICE_TALKING_1_PATH) as AudioStream
	if ResourceLoader.exists(VOICE_TALKING_2_PATH):
		_voice_talking_2 = load(VOICE_TALKING_2_PATH) as AudioStream
	if ResourceLoader.exists(VOICE_SEARCHING_PATH):
		_voice_searching = load(VOICE_SEARCHING_PATH) as AudioStream
	if ResourceLoader.exists(VOICE_ANGRY_PATH):
		_voice_angry = load(VOICE_ANGRY_PATH) as AudioStream
	
	# ─── CONTEXT-STEERING RAYCAST ARRAY ────────────────────────────
	# Three RayCast3D nodes used for obstacle avoidance when the Entity is
	# stalking with tree/rock collisions disabled (OBSERVE_FROM_TREELINE, PATROL).
	# The center ray is 3.5m long, left/right rays are 2.5m long at 30° angles.
	# Collision mask is set to scan static obstacles (cabin walls, porch posts).
	_ray_center = RayCast3D.new()
	_ray_center.name = "RayCastCenter"
	_ray_center.target_position = Vector3(0.0, 0.0, -3.5)
	_ray_center.collision_mask = (1 << (COLLISION_LAYER_CABIN - 1))  # Layer 1: Cabin
	_ray_center.hit_from_inside = false
	add_child(_ray_center)
	
	_ray_left = RayCast3D.new()
	_ray_left.name = "RayCastLeft"
	_ray_left.target_position = Vector3(0.0, 0.0, -2.5).rotated(Vector3.UP, deg_to_rad(30.0))
	_ray_left.collision_mask = (1 << (COLLISION_LAYER_CABIN - 1))  # Layer 1: Cabin
	_ray_left.hit_from_inside = false
	add_child(_ray_left)
	
	_ray_right = RayCast3D.new()
	_ray_right.name = "RayCastRight"
	_ray_right.target_position = Vector3(0.0, 0.0, -2.5).rotated(Vector3.UP, deg_to_rad(-30.0))
	_ray_right.collision_mask = (1 << (COLLISION_LAYER_CABIN - 1))  # Layer 1: Cabin
	_ray_right.hit_from_inside = false
	add_child(_ray_right)
	
	# Set up sub-modules
	if _ai and _ai.has_method("setup"):
		_ai.setup(self)
	if _sensory and _sensory.has_method("setup"):
		_sensory.setup(self)
	if _navigation and _navigation.has_method("setup"):
		_navigation.setup(self)
	
	# ─── CONFIDENCE SYSTEM ─────────────────────────────────────────
	# Create the EntityConfidence node as a child of the Entity.
	# This module tracks the Entity's boldness (0.0–100.0) and provides
	# the F3 debug overlay for real-time confidence visualization.
	#
	# CRITICAL: add_child() MUST be called immediately after new().
	# Without it, the EntityConfidence node is an orphan — its CanvasLayer
	# cannot render (F3 menu invisible) and its _process(delta) never fires
	# (confidence value freezes and never decays).
	if not _confidence:
		_confidence = EntityConfidence.new()
		_confidence.name = "EntityConfidence"
		add_child(_confidence)  # <-- REQUIRED: attaches to SceneTree
	if _confidence and _confidence.has_method("setup"):
		_confidence.setup(self)
	
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
	
	# Check if the Entity has been manually disabled via the debug console.
	# The debug console sets a meta flag "debug_disabled" when the player
	# toggles it off. If set, we skip activation so the Entity stays dormant
	# even when a new night starts.
	if has_meta("debug_disabled") and get_meta("debug_disabled"):
		print("[Entity] Night %d: Debug-disabled via console. Skipping activation." % night)
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
	
	# ─── SYSTEMIC TIME CRUNCH ──────────────────────────────────────
	# The moment the Entity spawns, the clock is forced to exactly
	# 60 seconds before dawn (cycle_progress ≈ 0.9 for a 600s cycle).
	# The night phase spans 0.5-1.0, and dawn is at cycle_progress 1.0.
	# So 1.0 - (60/600) = 0.9 gives ~60 seconds before dawn.
	# This gives the player exactly 60 seconds to survive.
	# IMPORTANT: Use set_progress() instead of directly assigning cycle_progress
	# so that the internal _elapsed timer stays in sync. Without this, _process()
	# recalculates cycle_progress from the stale _elapsed value and snaps back
	# to daytime.
	var gt = get_node_or_null("/root/GameTime")
	if gt:
		var seconds_before_dawn = 60.0
		var dawn_progress = 1.0 - (seconds_before_dawn / gt.cycle_duration)
		gt.set_progress(dawn_progress)
		gt.is_time_paused = false  # Unpause the clock!
		print("[Entity] Time crunch activated! ", seconds_before_dawn, \
			  " seconds until dawn at cycle_progress ", dawn_progress)





## ─── INPUT PASSTHROUGH ──────────────────────────────────────────────────────
## Routes input events to sub-modules that need them.
## Currently forwards F3 to the EntityConfidence debug overlay toggle.
func _input(event: InputEvent) -> void:
	if _confidence and _confidence.has_method("_input"):
		_confidence._input(event)


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
	
	# Reset enrage state so the Entity starts fresh next night
	_is_enraged = false
	_original_stalk_speed = 0.0

	
	# ─── STOP ALL AUDIO ────────────────────────────────────────────
	# Immediately stop all looping audio players so no sounds continue
	# playing after the Entity deactivates (e.g., at dawn).
	# The fade-out system in _physics_process() is too slow for a hard
	# deactivation — the audio would keep looping for several seconds.
	if _chase_music_player:
		_chase_music_player.stop()
		_chase_music_player.volume_db = -80.0
		_chase_music_was_playing = false
	if _night_ambience_player:
		_night_ambience_player.stop()
		_night_ambience_player.volume_db = -80.0
		_night_ambience_was_playing = false
	if _chase_exit_grunt_player and _chase_exit_grunt_player.playing:
		_chase_exit_grunt_player.stop()
	if _light_sanctuary_grunt_player and _light_sanctuary_grunt_player.playing:
		_light_sanctuary_grunt_player.stop()
	if _growl_audio and _growl_audio.playing:
		_growl_audio.stop()
	if _claw_scrape_player and _claw_scrape_player.playing:
		_claw_scrape_player.stop()



func _physics_process(delta: float) -> void:
	# ─── EARLY EXIT: Dormant Entity ─────────────────────────────────
	# If the Entity is not active or the player reference is missing,
	# skip ALL processing — no cooldowns, no F2 checks, no logging.
	# This prevents wasted CPU cycles when the Entity is hidden during
	# daytime or Night 1 narrative setup.
	if not _is_active or not _player:
		_game_time += delta
		return
	
	_game_time += delta
	
	if _relocate_cooldown > 0.0:
		_relocate_cooldown -= delta
	
	# F2 debug cooldown decrement
	if _debug_f2_cooldown > 0.0:
		_debug_f2_cooldown -= delta
	
	# Window bluff cooldown decrement
	if _window_bluff_cooldown > 0.0:
		_window_bluff_cooldown -= delta
	
	# Light sabotage cooldown decrement
	if _light_sabotage_cooldown > 0.0:
		_light_sabotage_cooldown -= delta
	
	# Chase exit grunt cooldown decrement
	if _chase_exit_grunt_cooldown > 0.0:
		_chase_exit_grunt_cooldown -= delta
	
	# ─── DEBUG: F2 — Window Siege Stress Test ──────────────────────────────
	# Development-only shortcut to stress-test the outside-to-inside sequential
	# window destruction system (glass shatter → plank damage → breach → INDOOR_SEARCH).
	# Forces the Entity into APPROACH_WINDOW state with real pathfinding to the
	# first CabinWindow in the "WindowMarkers" group.
	if Input.is_key_pressed(KEY_F2):
		_debug_attack_window()
	
	# --- STATE TRANSITION LOGGING ---
	if _state != _last_logged_state:
		print("[Entity FSM] Transitioned from %s to %s" % [State.keys()[_last_logged_state], State.keys()[_state]])
		_last_logged_state = _state
		
		# ─── "CREEPING GHOST" COLLISION LAYER UPDATE ─────────────────
		# Every time the state changes, update the collision mask to match
		# the new state's requirements. This ensures the Entity phases through
		# tree/rock collision when stalking outside (OBSERVE_FROM_TREELINE,
		# PATROL) and has full collision when attacking (CHASE, APPROACH_WINDOW).
		_update_collision_layers()
	
	# --- BACKGROUND SENSE PROCESSING (runs every frame regardless of state) ---
	if _sensory:
		_sensory.can_entity_see_player()
	if _current_interest_level > 0:
		_current_interest_level -= _interest_decay_rate * delta
	
	# --- FLASHLIGHT SPOTTING: Position-Aware Response ---
	# Replaces the legacy "exposure tolerance" system.
	# Checks every frame if the player is shining the flashlight on the Entity.
	# Redirects to one of two behaviors based on player position:
	#
	#   BEHAVIOR 1 (Cowardly Outside Flinch):
	#     Player is INSIDE the cabin, Entity is OUTSIDE.
	#     Entity flinches and sprints laterally to evade the flashlight beam.
	#
	#   BEHAVIOR 2 (Lethal Outside Interception):
	#     Player is OUTSIDE, Entity is OUTSIDE.
	#     Entity immediately charges at 3x speed — no standoff, no flinch.
	#
	#   Night 5 Exception:
	#     Entity never flinches. If spotted while player is inside, it
	#     immediately sieges the nearest window instead.
	#
	# ─── FLOOR MATERIAL SAFETY GUARD ───────────────────────────────
	# Before ANY flashlight-based state override can force a CHARGE
	# transition, perform a definitive floor material check. If the
	# player is standing on a "wood" group surface (cabin flooring),
	# the Entity is strictly forbidden from charging through the walls.
	#
	# This is a BULLETPROOF safety override that runs BEFORE the AI's
	# STANDOFF handler. Even if the AI's charge countdown expires and
	# tries to transition to CHARGE, this guard will intercept it on
	# the next physics frame and force a RETREAT instead.
	#
	# The check walks up the collider's parent chain to find any node
	# in the "wood" group, ensuring it works even if the floor mesh
	# is nested inside a grouping node.
	var _player_is_on_wood_floor: bool = false
	if _player:
		var floor_raycast: RayCast3D = _player.get_node_or_null("FloorRayCast")
		if floor_raycast and floor_raycast.is_colliding():
			var surface_node: Node = floor_raycast.get_collider()
			while surface_node:
				if surface_node.is_in_group("wood"):
					_player_is_on_wood_floor = true
					break
				surface_node = surface_node.get_parent()
	
	# ─── DEBUG MARCH LOCK ──────────────────────────────────────────
	# When the debug march is active, skip ALL flashlight-based state
	# overrides. The developer tool has absolute priority over player
	# inputs during the pathfinding stress test.
	#
	# ─── WINDOW PEEK LOCK ──────────────────────────────────────────
	# When the Entity is actively sieging a window (WINDOW_PEEK state),
	# skip ALL flashlight-based state overrides. The Entity is committed
	# to the siege — the player cannot interrupt it by shining the
	# flashlight at the window. This prevents premature exit from the
	# barricade damage sequence.
	#
	# ─── HARASS INTERCEPT ──────────────────────────────────────────
	# When the Entity is in HARASS state and the player shines the
	# flashlight on it, the harassment is interrupted and the Entity
	# immediately transitions to FLINCH (Phantom Evasion). The Entity
	# slides laterally into the darkness, denying the player the
	# satisfaction of a direct confrontation.
	#
	# ─── RETREAT EXCLUSION ─────────────────────────────────────────
	# RETREAT is excluded from the outer guard to prevent the oscillation
	# loop: Controller sets STANDOFF → AI forces RETREAT → AI completes
	# retreat (fade_and_relocate → OBSERVE) → Controller sets STANDOFF
	# again. By excluding RETREAT here, the Entity can complete its
	# retreat without being interrupted by the flashlight detection block.
	if _state != State.WINDOW_PEEK and _state != State.HARASS and _state != State.RETREAT and _sensory and _sensory.is_player_spotting_entity():
		var player_outside = _navigation.is_player_outside() if _navigation else false
		
		if player_outside:
			# BEHAVIOR 2: Both outside → IMMEDIATE CHARGE (ALL NIGHTS)
			# No standoff freeze, no exposure timer, no fade.
			# The Entity screeches and sprints directly at the player.
			#
			# ─── FLOOR MATERIAL SAFETY GUARD ──────────────────────────
			# Even if the navigation system reports the player as outside,
			# double-check the floor material. If the player is on wood
			# flooring, they are inside the cabin — do NOT charge.
			if _player_is_on_wood_floor and _state != State.INDOOR_SEARCH:
				# Player is on wood flooring — they are safely inside.
				# Force a retreat instead of charging through the wall.
				print("[Entity Controller] OUTSIDE CHARGE blocked by wood floor safety guard! Player is on cabin flooring. Forcing RETREAT.")
				_state = State.RETREAT
				if _ai and _ai.has_method("fade_and_relocate"):
					_ai.fade_and_relocate()
				elif _navigation:
					_navigation.pick_next_vantage_point()
				return
			
			if _state != State.CHARGE and _state != State.FLINCH:
				_state = State.CHARGE
				_nav_agent.target_position = _player.global_position
				print("[Entity] Player spotted Entity outside! IMMEDIATE CHARGE!")
		else:
			# Player inside, Entity outside
			if not _flinch_enabled:
				# --- NIGHT 5 EXCEPTION ---
				# Skip the standoff entirely. The Entity is relentless.
				# Immediately accelerate into a window breach or door siege.
				if _state != State.CHARGE and _state != State.APPROACH_WINDOW and _state != State.WINDOW_PEEK:
					_state = State.APPROACH_WINDOW
					_current_window_target = null
					print("[Entity] Night 5: No standoff! Immediately sieging nearest window!")
			else:
				# BEHAVIOR 1: Flashlight Standoff (Nights 1-4)
				# The Entity freezes in place while the player shines the flashlight
				# beam on it. A 1.5-second charge countdown begins. If the player
				# holds the beam for the full duration, the Entity charges at 3x speed.
				# If the player breaks line of sight or turns off the flashlight,
				# the countdown resets and the Entity drops back to observation.
				#
				# This replaces the old instant-flinch behavior with a high-tension
				# standoff: the player can delay the Entity by staring at it, but
				# must eventually look away or the Entity will charge.
				#
				# ─── FLOOR MATERIAL SAFETY GUARD ──────────────────────────
				# Before initiating STANDOFF, check if the player is on wood
				# flooring. If they are, the STANDOFF will eventually transition
				# to RETREAT (handled by the AI's floor material check). But
				# we also guard here to prevent the controller from ever setting
				# STANDOFF if the player is safely inside — force RETREAT directly.
				if _player_is_on_wood_floor and _state != State.INDOOR_SEARCH:
					# Player is on wood flooring — they are safely inside.
					# Do NOT initiate STANDOFF. Force a retreat immediately.
					print("[Entity Controller] STANDOFF blocked by wood floor safety guard! Player is on cabin flooring. Forcing RETREAT.")
					_state = State.RETREAT
					if _ai and _ai.has_method("fade_and_relocate"):
						_ai.fade_and_relocate()
					elif _navigation:
						_navigation.pick_next_vantage_point()
					return
				
				if _state != State.STANDOFF and _state != State.CHARGE and _state != State.FLINCH and _state != State.RETREAT:
					_state = State.STANDOFF
					# Reset the charge countdown in the AI module
					if _ai and _ai.has_method("reset_charge_countdown"):
						_ai.reset_charge_countdown()
					print("[Entity] Player spotted Entity from inside! STANDOFF initiated.")
	
	# ─── CONFIDENCE MODIFICATION: FLASHLIGHT STARE ──────────────────────
	# While the player is staring at the Entity with the flashlight beam,
	# continuously drain confidence at 2.0 units per second. This makes the
	# Entity more timid the longer it is exposed to the light.
	#
	# When the player breaks line of sight (stops staring), grant a one-time
	# +8.0 instant confidence boost. This represents the Entity's relief at
	# escaping the light and encourages it to try again.
	#
	# The _confidence_stare_was_active flag tracks whether the player was
	# staring on the previous frame, so we can detect the transition from
	# "staring" to "not staring" and apply the one-time boost exactly once.
	var _confidence_stare_active: bool = _sensory and _sensory.is_player_spotting_entity()
	
	if _confidence_stare_active:
		# Continuous drain: -2.0 confidence per second while stared at
		if _confidence and _confidence.has_method("modify"):
			_confidence.modify(-2.0 * delta, "flashlight_stare")
	elif _confidence_stare_was_active and not _confidence_stare_active:
		# One-time boost: +8.0 confidence when the player breaks line of sight
		if _confidence and _confidence.has_method("modify"):
			_confidence.modify(8.0, "flashlight_stare_break")
			print("[Entity Controller] Confidence boost: +8.0 (player broke flashlight stare)")
	
	_confidence_stare_was_active = _confidence_stare_active
	
	# Reset the light sanctuary grunt debounce when the player stops
	# shining the flashlight on the Entity. This allows the grunt to
	# play again on the next spotting cycle.
	if _has_played_light_sound and not (_sensory and _sensory.is_player_spotting_entity()):
		_has_played_light_sound = false
	
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
	#
	# COOLDOWN GUARD:
	# The _chase_exit_grunt_cooldown prevents the grunt from repeating every
	# time the Entity rapidly enters/exits CHASE (e.g., when the player runs
	# between lit and dark rooms). The cooldown is set to 5 seconds each time
	# the grunt plays, ensuring it can only play once every 5 seconds at most.
	if _was_chasing and not is_chasing and _chase_exit_grunt_cooldown <= 0.0:
		if _chase_exit_grunt_player and _chase_exit_grunt_player.stream:
			_chase_exit_grunt_player.play()
			_chase_exit_grunt_cooldown = CHASE_EXIT_GRUNT_COOLDOWN_DURATION
			print("[Entity] Playing chase exit grunt. _state=", _state, " is_player_outside=", _navigation.is_player_outside() if _navigation else "NO_NAV")
	_was_chasing = is_chasing
	
	# Smooth volume interpolation for chase music
	_fade_audio_player(_chase_music_player, is_chasing, CHASE_MUSIC_VOLUME_DB, CHASE_MUSIC_FADE_SPEED, delta)
	
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
	
	# Smooth volume interpolation for night ambience
	_fade_audio_player(_night_ambience_player, should_play_ambience, NIGHT_AMBIENCE_VOLUME_DB, NIGHT_AMBIENCE_FADE_SPEED, delta)
	
	# --- WINDOW BLUFF HANDLER ---
	# When the Entity is bluffing, it moves toward the window for 2 seconds
	# (Phase 1), pauses for 1.5 seconds (Phase 2), then retreats to its
	# starting position (Phase 3). This creates tension and uncertainty.
	if _window_bluff_active:
		_window_bluff_timer -= delta
		
		if _window_bluff_timer > 0.0:
			# Phase 1: Approach — move toward the window
			if _nav_agent.is_navigation_finished():
				velocity = Vector3.ZERO
			else:
				var next_pos = _nav_agent.get_next_path_position()
				var dir_2d := Vector2(next_pos.x - global_position.x, next_pos.z - global_position.z).normalized()
				velocity.x = dir_2d.x * current_stalk_speed
				velocity.z = dir_2d.y * current_stalk_speed
		else:
			# Phase 2 & 3: Pause then retreat
			# After the approach timer expires, stop and stare for 1.5 seconds,
			# then retreat back to the starting position.
			if _window_bluff_timer > -1.5:
				# Phase 2: Pause — stop and stare at the window
				velocity = Vector3.ZERO
			else:
				# Phase 3: Retreat — move back to starting position
				var retreat_dir = (_window_bluff_retreat_pos - global_position).normalized()
				var dist_to_retreat = global_position.distance_to(_window_bluff_retreat_pos)
				if dist_to_retreat < 1.0:
					# Bluff complete — reset and return to normal behavior
					_window_bluff_active = false
					_window_bluff_cooldown = randf_range(8.0, 15.0)
					_current_window_target = null
					_state = State.OBSERVE_FROM_TREELINE
					velocity = Vector3.ZERO
					print("[Entity] Window Bluff complete! Retreating to treeline.")
				else:
					velocity.x = retreat_dir.x * current_stalk_speed * 0.7
					velocity.z = retreat_dir.z * current_stalk_speed * 0.7
		
		move_and_slide()
		_update_animations(delta)
		return
	
	# --- STUNNED STATE (Porch Light Overload Trap) ---
	# The Entity is paralyzed by the blinding porch light. It cannot move,
	# cannot pathfind, and cannot transition to any other state until the
	# stun timer expires or the generator dies (blackout).
	# This gives the player a window to destroy the totem anchor.
	if _state == State.STUNNED:
		# Decrement the stun timer
		_stun_timer -= delta
		
		# Freeze all movement and pathfinding
		velocity = Vector3.ZERO
		_nav_agent.target_position = global_position  # Keep nav target on self
		
		# Play writhing/pained animation (Idle with transparency flicker)
		_update_animations(delta)
		
		# Check if the stun has expired naturally
		if _stun_timer <= 0.0:
			print("[Entity] Stun expired! Entity released from overload paralysis.")
			_state = State.OBSERVE_FROM_TREELINE
		
		return
	
	# --- ENRAGED STATE (Blackout Release) ---
	# The generator died while the Entity was stunned. The Entity is now
	# permanently enraged for the rest of the night — 1.5x movement speed.
	# ENRAGED is a modifier flag, not a blocking state — the Entity still
	# uses its normal FSM states (CHASE, PATROL, etc.) but with boosted speed.
	# The _is_enraged flag is checked by the AI speed calculations.
	
	# --- TRANSITION LOCK: RETREAT / STANDOFF ---
	# During RETREAT, force velocity to zero and skip movement processing,
	# but STILL execute the AI update tick so that _retreat_state() can
	# call fade_and_relocate(). Without this, the early return would create
	# a deadlock where the AI never runs and the transition never completes.
	# STANDOFF also locks movement — the Entity freezes in place while stared at.
	# NOTE: RELOCATE is NOT included here — it is a safe initialization state only
	# and is never used during active runtime transitions.
	if _state == State.RETREAT or _state == State.STANDOFF:
		velocity = Vector3.ZERO
		if _ai and _ai.has_method("process_state_logic"):
			_ai.process_state_logic(delta)
			velocity = _ai.get_calculated_velocity()
		_update_animations(delta)
		return

	
	# --- STANDARD ACTIVE NAVIGATION ---

	# Gravity is bypassed during CLIMB_WALL (vertical ascent), WINDOW_PEEK
	# (Entity is stationary at the window frame), FLINCH (lateral sprint
	# — the Entity stays at its current Y to avoid dropping into terrain),
	# and ATTACK_LAMP (Entity stands still while striking the lamp).
	if not is_on_floor() and _state != State.WINDOW_PEEK and _state != State.CLIMB_WALL and _state != State.FLINCH and _state != State.ATTACK_LAMP:

		velocity += get_gravity() * delta
	
	if _ai and _ai.has_method("process_state_logic"):
		_ai.process_state_logic(delta)
		velocity = _ai.get_calculated_velocity()
	else:
		velocity = Vector3.ZERO

	
	move_and_slide()
	
	var flat_vel = Vector2(velocity.x, velocity.z)
	if flat_vel.length_squared() > 0.05 and _monster_model:
		var target_angle = atan2(flat_vel.x, flat_vel.y)
		_monster_model.rotation.y = lerp_angle(_monster_model.rotation.y, target_angle, delta * 10.0)
	
	_update_animations(delta)


# ─── DEBUG: F2 — Window Siege Stress Test ────────────────────────────────────
# Development-only shortcut to stress-test the outside-to-inside sequential
# window destruction system (glass shatter → plank damage → breach → INDOOR_SEARCH).
#
# When F2 is pressed, the Entity:
#   1. Locates the CabinWindow with window_id == "Hall_Window" in the "WindowMarkers" group.
#   2. Activates itself if dormant.
#   3. Teleports directly to the window's ground-projected position.
#   4. Forces FSM state to WINDOW_PEEK with barricade damage timer initialized.
#   5. The existing _window_peek_state() in entity_ai.gd immediately begins
#      the barricade damage sequence (glass shatter → plank damage → breach).
#
# This is a TELEPORT shortcut — the Entity skips the long pathfinding march
# through the treeline and goes straight to the barricade damage loop.
var _debug_f2_cooldown: float = 0.0


func _debug_attack_window() -> void:
	# Debounce: only trigger once per press (not every frame while held)
	if _debug_f2_cooldown > 0.0:
		return
	_debug_f2_cooldown = 0.5  # 0.5 second cooldown
	
	print("\n========== DEBUG F2: Window Siege Stress Test ==========")
	
	# ─── PART 1: Window Discovery ───────────────────────────────────
	# Scan the active scene tree for nodes registered under the
	# "WindowMarkers" group. Each marker is a child Marker3D of a
	# CabinWindow instance (or the CabinWindow itself).
	var windows = get_tree().get_nodes_in_group("WindowMarkers")
	
	if windows.is_empty():
		print("[F2] ERROR: No WindowMarkers found in scene tree!")
		print("==========================================================\n")
		return
	
	# ─── SINGLE-PASS SCRIPT-VALIDATION LOOP FILTER ────────────────
	# The "WindowMarkers" group may contain:
	#   - CabinWindow root nodes (script on the node itself)
	#   - WindowMarker Marker3D children (script on the parent)
	#   - An organizational "WindowMarkers" Node3D folder
	# We iterate through ALL group members using has_method("damage_barricade")
	# to positively identify the CabinWindow script container, regardless of
	# which node in the hierarchy owns it.
	#
	# TARGET WINDOW SELECTION:
	# We specifically look for the window with window_id == "Hall_Window".
	# This is the front-facing window on the ground floor near the hall area.
	# The Entity will pathfind to this window and begin the barricade damage
	# sequence. Change the target_id string to target a different window.
	#
	# SINGLE-PASS OPTIMIZATION:
	# One loop tracks both the target_id match AND the first valid fallback,
	# eliminating the redundant second pass over the windows array.
	var target_id: String = "Hall_Window"
	var final_window_target: CabinWindow = null
	var first_valid: CabinWindow = null
	for node in windows:
		var candidate: CabinWindow = null
		if node.has_method("damage_barricade"):
			candidate = node as CabinWindow
		elif node.get_parent() and node.get_parent().has_method("damage_barricade"):
			candidate = node.get_parent() as CabinWindow
		
		if not candidate:
			continue
		
		# Track first valid as fallback
		if not first_valid:
			first_valid = candidate
		
		# Check for target_id match
		if candidate.window_id == target_id:
			final_window_target = candidate
			break
	
	# Fallback: if no window_id match found, use the first valid window
	if not final_window_target:
		final_window_target = first_valid
	
	if not final_window_target:
		return
	
	# Store the original state for diagnostic logging
	var original_state = _state
	
	# ─── PART 2: Teleport to Window + Immediate Barricade Damage ───
	# Activate the Entity if it's dormant (e.g. Night 1 before van alarm)
	if not _is_active:
		activate()
	
	# Teleport the Entity directly to the window's position.
	# This bypasses the long pathfinding march through the treeline.
	# The Entity is placed at the window's ground-projected X/Z with
	# the Entity's current Y to avoid vertical snapping.
	var teleport_pos = final_window_target.global_position
	teleport_pos.y = global_position.y
	global_position = teleport_pos
	velocity = Vector3.ZERO
	print("[F2] Entity teleported to window position: ", teleport_pos)
	
	# Store the breach window reference so the AI knows which window
	# was breached (used for retreat pathfinding if repelled by light).
	_indoor_breach_window = final_window_target
	
	# Force the FSM state to WINDOW_PEEK and initialize the barricade
	# damage timer so the Entity immediately begins damaging the window.
	# This skips the APPROACH_WINDOW → WINDOW_PEEK transition entirely.
	_state = State.WINDOW_PEEK
	_stare_timer = 9999.0  # Stay until barricade is destroyed
	
	# Reset the AI's barricade damage timer so the Entity immediately
	# enters barricade-damage mode on the next physics frame.
	if _ai and _ai.has_method("reset_barricade_timers"):
		_ai.reset_barricade_timers()
	
	print("[F2] Entity state override: ", State.keys()[original_state], " → WINDOW_PEEK")
	print("[F2] Entity teleported directly to window. Barricade damage sequence starting.")
	print("[F2] Window state — glass_shattered: ", final_window_target.is_glass_shattered, ", boarded: ", final_window_target.is_boarded)
	print("==========================================================\n")


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


## Starts a visual alpha fade Tween on the Entity's monster model.
## The model fades from opaque (alpha 1.0) to transparent (alpha 0.0)
## over 1.5 seconds, creating a "phantom" effect as the Entity slides
## into the darkness during the FLINCH state.
##
## Called from _flinch_state() in entity_ai.gd on first entry.
func _start_flinch_fade() -> void:
	if not _monster_model:
		return
	# Kill any existing tweens on the monster model to prevent conflicts
	var existing_tween = create_tween()
	existing_tween.kill()
	
	var fade_tween = create_tween()
	fade_tween.tween_property(_monster_model, "modulate:a", 0.0, 1.5).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_SINE)


## Initiates the FLINCH state — a lateral sprint to evade the player's flashlight.
##
## BEHAVIOR 1 (Cowardly Outside Flinch):
## Called when the player is INSIDE the cabin and shines the flashlight at the
## Entity while it is OUTSIDE. The Entity does NOT fade/teleport — it sprints
## laterally (perpendicular to the player's camera view) at 1.5x speed for
## 1.5 seconds, then transitions to RELOCATE to pick a new vantage point.
##
## DOT PRODUCT ZERO GUARD:
## If the Entity is dead-center in the flashlight beam, the dot product of
## the lateral vector and the direction-to-entity could be exactly 0, making
## sign() return 0 and cancelling the movement entirely. We default to
## side = 1.0 (always slide right) when abs(dot) <= 0.001.
func _start_flinch() -> void:
	if not _player or not _sensory:
		return
	
	var cam = get_viewport().get_camera_3d()
	if not cam:
		return
	
	# Calculate the lateral vector perpendicular to the player's camera view
	var cam_forward = -cam.global_transform.basis.z
	cam_forward.y = 0.0
	cam_forward = cam_forward.normalized()
	
	var to_entity = (global_position - cam.global_position)
	to_entity.y = 0.0
	to_entity = to_entity.normalized()
	
	# Perpendicular vector (left/right relative to camera view)
	var up = Vector3.UP
	var lateral = cam_forward.cross(up).normalized()
	
	# --- DOT PRODUCT ZERO GUARD ---
	# If the Entity is dead-center in the flashlight beam, the dot product
	# of lateral and to_entity could be exactly 0, making sign() return 0
	# and cancelling the movement entirely. Default to sliding RIGHT.
	var dot_lateral = lateral.dot(to_entity)
	var side = 1.0  # Default: always slide right
	if abs(dot_lateral) > 0.001:
		side = sign(dot_lateral)
	
	# Sprint 8 meters laterally to clear the window's line-of-sight
	_flinch_target_pos = global_position + lateral * side * 8.0
	_flinched_timer = 1.5
	_state = State.FLINCH
	print("[Entity] FLINCH! Sprinting laterally to evade flashlight!")


func _on_caught_player() -> void:
	_is_active = false
	velocity = Vector3.ZERO
	if _growl_audio:
		_growl_audio.play()
	var nm = get_node_or_null("/root/NightManager")
	if nm:
		nm.horror_event.emit("entity_caught_player")
	# Unpause the game tree in case it was paused by a previous jumpscare
	if get_tree().paused:
		get_tree().paused = false


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


## Physically stalks to a new vantage point using NavigationAgent3D pathfinding.
## Replaces the old fade-out + teleport system. The Entity now physically sneaks
## between trees using the "Stalk" or "running_crawl" locomotion animation.
##
## BEHAVIOR:
##   1. Picks a new vantage point via entity_navigation.pick_next_vantage_point()
##   2. Sets the NavigationAgent3D target to that position
##   3. Transitions to a physical movement phase (State.OBSERVE_FROM_TREELINE)
##      where the Entity moves at stalk speed along the computed path
##   4. The "Creeping Ghost" collision layer is active during this movement,
##      allowing the Entity to phase through tree/rock collision while still
##      following the NavMesh path for steering
##   5. Once the path is complete, the Entity resumes normal observation
##
## Called from entity_ai.gd when the Entity needs to change spots (e.g., the
## player stared at it, its observation timer expired, or it was repelled by
## a light sanctuary).
func fade_and_relocate() -> void:
	if _is_fading:
		return
	print("[Entity] fade_and_relocate() called! Current state: ", State.keys()[_state])
	_is_fading = true
	
	# Pick a new vantage point via the navigation system.
	# This sets _nav_agent.target_position to the new coordinate.
	_navigation.pick_next_vantage_point()
	
	# Transition to OBSERVE_FROM_TREELINE — the AI will handle the physical
	# movement toward the new vantage point via _observe_from_treeline_state().
	# The "Creeping Ghost" collision layer is automatically applied by
	# _update_collision_layers() each frame for this state.
	_state = State.OBSERVE_FROM_TREELINE
	
	# Reset the stare timer so the Entity doesn't immediately try to
	# relocate again upon arrival. The AI will set a new timer once
	# the Entity reaches the vantage point.
	_stare_timer = 9999.0  # Effectively infinite — the AI resets it on arrival
	
	# Reset the light sanctuary grunt debounce flag so the Entity can
	# play the frustrated sound again the next time it is repelled.
	_has_played_light_sound = false
	
	if _ai and _ai.has_method("reset_exposure"):
		_ai.reset_exposure()
	
	_is_fading = false
	print("[Entity] Physical relocation in progress. Stalking to new vantage point.")


## Initiates a Window Bluff — the Entity fakes an approach toward a window,
## stops short, pauses, then retreats. This creates tension and uncertainty
## for the player, who must guess whether the Entity is actually sieging.
##
## The bluff sequence has three phases:
##   Phase 1 (Approach): Entity moves toward the target window for ~2 seconds.
##   Phase 2 (Pause):    Entity stops and stares at the window for ~1.5 seconds.
##   Phase 3 (Retreat):  Entity backs away to its starting position.
##
## Called from _approach_window_state() in entity_ai.gd when the Entity
## selects a window but decides to bluff instead of commit.
func _start_window_bluff(target_window: Node3D) -> void:
	if _window_bluff_active or _window_bluff_cooldown > 0.0:
		return
	
	_window_bluff_active = true
	_window_bluff_timer = 2.0  # Phase 1: Approach for 2 seconds
	_window_bluff_retreat_pos = global_position
	
	# Set the nav target to the window's position
	_nav_agent.target_position = target_window.global_position
	print("[Entity] Window Bluff started! Approaching window: ", target_window.name)


## Sabotages a CabinLight near the target window by switching it off.
## The Entity reaches through the window frame or uses its supernatural
## influence to flick the light switch, plunging the room into darkness.
##
## This removes the light sanctuary protection from the window, making it
## vulnerable to siege. The player must re-light the room to restore protection.
##
## Called from _approach_window_state() in entity_ai.gd when the Entity
## selects a window that is secured by light.
##
## Cooldown: 30 seconds between sabotages to prevent the mechanic from
## being too oppressive.
func _sabotage_light(target_window: CabinWindow) -> void:
	if _light_sabotage_cooldown > 0.0:
		return
	if not target_window or not target_window.room_light:
		return
	
	# Switch off the room light
	target_window.room_light.switch_off()
	_light_sabotage_cooldown = 30.0
	
	print("[Entity] Light sabotaged! Switched off light for window: ", target_window.window_id)


## Plays a one-shot frustrated grunt when the Entity is repelled by a light
## sanctuary. Uses the dedicated _light_sanctuary_grunt_player with a higher
## pitch (1.3) and slightly louder volume (-3.0 dB) to differentiate it from
## the chase exit grunt. This gives the player clear audio feedback that
## they've successfully escaped into a lit room.
##
## DEBOUNCE GUARD:
## The _has_played_light_sound flag prevents this sound from repeating every
## frame while the player remains in a lit room. The flag is set to true when
## the sound plays, and is reset to false when the Entity fades/relocates
## (see fade_and_relocate()) or resets exposure.
func _play_light_sanctuary_grunt() -> void:
	if _has_played_light_sound:
		return
	if _light_sanctuary_grunt_player and _light_sanctuary_grunt_player.stream:
		_light_sanctuary_grunt_player.play()
		_has_played_light_sound = true
		print("[Entity] Playing light sanctuary grunt — frustrated by the light! _state=", _state, " is_player_outside=", _navigation.is_player_outside() if _navigation else "NO_NAV")


## ─────────────────────────────────────────────────────────────────────────────
## OVERLOAD STUN — Portable High-Voltage Lamp Trap
## ─────────────────────────────────────────────────────────────────────────────

## Public API: Triggers the overload stun on the Entity.
##
## Called by PortableLamp.trigger_overload() when the player executes the
## "EXECUTE OVERLOAD" command from the computer terminal.
##
## The Entity must be within 25 units of the portable trap position for the
## stun to take effect. If the Entity is too far away (e.g., patrolling the
## treeline), the stun is ignored and the overload only burns fuel.
##
## Effects:
##   1. Checks distance to the portable trap (must be < 25.0 units)
##   2. Forces state to STUNNED — freezes all movement and pathfinding
##   3. Sets _stun_timer to the provided duration (default 30.0 seconds)
##   4. Plays a high-priority pained scream via HorrorSoundManager
##   5. Logs the stun event for debugging
func trigger_overload_stun(trap_position: Vector3, duration: float = 30.0) -> void:
	if not _is_active:
		print("[Entity] Overload stun ignored — Entity is not active.")
		return
	
	if _state == State.STUNNED:
		print("[Entity] Overload stun ignored — Entity is already stunned.")
		return
	
	# Distance check: Entity must be within 25 units of the portable trap
	var dist_to_trap: float = global_position.distance_to(trap_position)
	if dist_to_trap > 25.0:
		print("[Entity] Overload stun ignored — Entity is too far from portable trap (%.1f units > 25.0)." % dist_to_trap)
		return
	
	print("[Entity] ⚡ OVERLOAD STUN TRIGGERED! Distance to trap: %.1f units. Stun duration: %.1f seconds." % [dist_to_trap, duration])
	
	# Force the Entity into STUNNED state
	_state = State.STUNNED
	_stun_timer = duration
	
	# Freeze all movement immediately
	velocity = Vector3.ZERO
	_nav_agent.target_position = global_position
	
	# Play a high-priority pained scream via HorrorSoundManager
	var hsm = get_node_or_null("/root/HorrorSoundManager")
	if hsm and hsm.has_method("play_distant_monster"):
		hsm.play_distant_monster()
	
	# Also play a local growl at higher pitch for the pained reaction
	if _growl_audio:
		_growl_audio.pitch_scale = 1.8  # Higher pitch = pained scream
		_growl_audio.play()
	
	print("[Entity] Entity is STUNNED! Paralyzed by the blinding portable lamp for %.1f seconds." % duration)



## Called when the generator runs out of fuel (blackout) while the Entity
## is in the STUNNED state. Instantly transitions the Entity to ENRAGED.
##
## ENRAGED permanently boosts the Entity's movement speed by 1.5x for the
## rest of the night. The Entity is released from the stun and immediately
## begins hunting the player with enhanced aggression.
##
## If the Entity is NOT stunned when the blackout hits, this function does
## nothing — the Entity continues its normal behavior.
func on_generator_blackout() -> void:
	if _state != State.STUNNED:
		return
	
	print("[Entity] ⚡ BLACKOUT RELEASE! Generator died while Entity was stunned. ENRAGED!")
	
	# Save the original stalk speed if not already saved
	if not _is_enraged:
		_original_stalk_speed = current_stalk_speed
		_is_enraged = true
		
		# Permanently boost movement speed by 1.5x for the rest of the night
		current_stalk_speed = _original_stalk_speed * 1.5
		print("[Entity] ENRAGED! Stalk speed permanently boosted from %.1f to %.1f (1.5x)." % [_original_stalk_speed, current_stalk_speed])
	
	# Release from stun — immediately begin hunting the player
	_state = State.CHASE
	_stun_timer = 0.0
	
	# Update nav target to the player's current position
	if _player:
		_nav_agent.target_position = _player.global_position
	
	# Play an enraged roar
	if _growl_audio:
		_growl_audio.pitch_scale = 1.2
		_growl_audio.play()
	
	# Play the distant monster sound as a telegraph
	var hsm = get_node_or_null("/root/HorrorSoundManager")
	if hsm and hsm.has_method("play_distant_monster"):
		hsm.play_distant_monster()


## ─── "CREEPING GHOST" COLLISION LAYER SYSTEM ──────────────────────────────────
## Updates the Entity's collision mask based on the current state.
##
## When the Entity is traveling outside through dense woods (OBSERVE_FROM_TREELINE,
## PATROL), it disables hard physics collisions with tree/rock environmental layers
## (layers 3 and 4). This allows the Entity to phase through foliage while still
## following the NavigationAgent3D path for steering.
##
## Full physics body collision masks are re-enabled the moment the Entity
## transitions into CHASE, APPROACH_WINDOW, or enters the cabin porch zone,
## ensuring it cannot phase through doors or window frames during an attack.
##
## Called automatically every time the state changes (see _physics_process).
func _update_collision_layers() -> void:
	match _state:
		State.OBSERVE_FROM_TREELINE, State.PATROL:
			# "Creeping Ghost" mode: Disable tree/rock collision layers.
			# The Entity phases through foliage while stalking outside.
			# Only cabin geometry (layer 1) and player (layer 2) remain active.
			# This prevents the Entity from getting stuck on trees while
			# physically pathfinding between vantage points.
			collision_mask = 0
			collision_mask |= (1 << (COLLISION_LAYER_CABIN - 1))  # Layer 1: Cabin
			collision_mask |= (1 << (COLLISION_LAYER_PLAYER - 1)) # Layer 2: Player
			# NOTE: Layers 3 (Tree) and 4 (Rock) are intentionally excluded.
			
		State.CHASE, State.CHARGE, State.APPROACH_WINDOW, State.WINDOW_PEEK, State.INDOOR_SEARCH, State.CLIMB_WALL, State.FLINCH, State.ATTACK_LAMP, State.RETREAT:
			# Full collision mode: Re-enable ALL collision layers.
			# The Entity must collide with everything during aggressive states
			# to prevent phasing through doors, window frames, or cabin walls.
			collision_mask = 0
			collision_mask |= (1 << (COLLISION_LAYER_CABIN - 1))  # Layer 1: Cabin
			collision_mask |= (1 << (COLLISION_LAYER_PLAYER - 1)) # Layer 2: Player
			collision_mask |= (1 << (COLLISION_LAYER_TREE - 1))   # Layer 3: Trees
			collision_mask |= (1 << (COLLISION_LAYER_ROCK - 1))   # Layer 4: Rocks
			
		_:
			# Default: Full collision mask for all other states (DORMANT, STANDOFF, STUNNED, etc.)
			collision_mask = 0
			collision_mask |= (1 << (COLLISION_LAYER_CABIN - 1))
			collision_mask |= (1 << (COLLISION_LAYER_PLAYER - 1))
			collision_mask |= (1 << (COLLISION_LAYER_TREE - 1))
			collision_mask |= (1 << (COLLISION_LAYER_ROCK - 1))


## Smoothly fades an AudioStreamPlayer's volume toward a target value.
## Stops playback once fully silent to save resources.
## Used by both chase music and night ambience to avoid code duplication.
func _fade_audio_player(player: AudioStreamPlayer, active: bool, target_vol: float, fade_speed: float, delta: float) -> void:


	if not player:
		return
	var vol_target = target_vol if active else -80.0
	player.volume_db = move_toward(player.volume_db, vol_target, (80.0 / fade_speed) * delta)
	if not active and player.volume_db <= -79.0 and player.playing:
		player.stop()


func _update_animations(_delta: float) -> void:
	if not _anim_state_machine:
		return
	
	# Strictly enforce model grounding offset across ALL frames
	if _monster_model:
		_monster_model.position = Vector3(0.0, -0.95, 0.0)
	
	# Hard clamp animations to Idle if we are retreating, dormant, or in a
	# frozen standoff. This prevents the animation state machine from caching
	# and continuously looping the previous sprinting animation during
	# supernatural transitions or while the Entity is locked in place.
	# NOTE: RELOCATE is NOT included here — it is a safe initialization state
	# only and is never used during active runtime transitions.
	if _state == State.RETREAT or _state == State.DORMANT or _state == State.STANDOFF:
		_anim_state_machine.travel("Idle")
		return
	
	var real_vel := get_real_velocity()
	var horz_speed := Vector2(real_vel.x, real_vel.z).length()
	
	match _state:
		State.CHARGE:
			# Use the running_crawl animation during CHARGE for a terrifying sprint
			_anim_state_machine.travel("running_crawl")
		State.WINDOW_PEEK:
			# If the animation lock timer is active, play the AttackWindow
			# animation. The lock is set to 1.5 seconds by entity_ai.gd's
			# _window_peek_state() each time damage_barricade() is called
			# (every 2.0s). The lock decrements by delta each frame, ensuring
			# the animation plays for its full duration even if the next hit
			# is 2 seconds away.
			if _ai and _ai.has_method("is_barricade_anim_locked") and _ai.is_barricade_anim_locked():
				_anim_state_machine.travel("AttackWindow")
			else:
				_anim_state_machine.travel("Idle")
		State.INDOOR_SEARCH:
			# Phase A (Vault Entry): Entity is climbing through the window frame.
			# Play the EnterWindow animation until the indoor landing is reached.
			if _ai and _ai.has_method("has_arrived_indoor") and not _ai.has_arrived_indoor():
				_anim_state_machine.travel("EnterWindow")
			# Phase B (Stalk Patrol): Low, creeping locomotion while hunting inside.
			elif horz_speed > 0.2:
				_anim_state_machine.travel("running_crawl")
			else:
				_anim_state_machine.travel("Idle")
		State.CLIMB_WALL:
			# Use running_crawl during wall climb for a spider-like ascent
			if horz_speed > 0.2:
				_anim_state_machine.travel("running_crawl")
			else:
				_anim_state_machine.travel("Idle")
		State.FLINCH:
			# Use running_crawl during the lateral sprint flinch
			_anim_state_machine.travel("running_crawl")
		State.ATTACK_LAMP:
			# Use Stalk animation while moving toward the lamp, Idle while striking
			if horz_speed > 0.2:
				_anim_state_machine.travel("Stalk")
			else:
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
