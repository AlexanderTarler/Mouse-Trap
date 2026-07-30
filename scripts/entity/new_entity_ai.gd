extends CharacterBody3D

## Entity v2 — Self-Contained 4-State FSM
## Replaces the old 16-state FSM + Director dual-brain pattern.
## Everything: movement, navigation, state transitions — lives here.

# ─── EXPORT TUNING KNOBS ───────────────────────────────────────────────
@export var observe_speed: float = 3.5
@export var stalk_speed: float = 2.5
@export var charge_speed: float = 12.0

@export var observe_dwell_min: float = 3.0
@export var observe_dwell_max: float = 8.0

@export var charge_trigger_distance: float = 5.0    # Within this range → CHARGE
@export var charge_break_distance: float = 12.0      # Beyond this range → STALK
@export var stalk_lose_distance: float = 40.0        # Beyond this range → OBSERVE

@export var path_update_interval: float = 0.25       # ~4 Hz navigation throttle
@export var nav_path_desired_distance: float = 1.0   # Prevent navmesh vertex stutter
@export var nav_target_desired_distance: float = 1.5 # Arrival radius for waypoints

@export var waypoint_arrival_distance: float = 2.0

# ─── STATE ENUM ────────────────────────────────────────────────────────
enum State {
	DORMANT,   # Frozen, no movement
	OBSERVE,   # Waypoint patrol between treeline points
	STALK,     # NavigationAgent3D pursuit of player
	CHARGE,    # Direct line-of-sight sprint, no pathfinding
}

# ─── INTERNAL STATE ───────────────────────────────────────────────────
var _current_state: State = State.DORMANT
var _velocity: Vector3 = Vector3.ZERO
var _move_speed: float = observe_speed

# Navigation
var _nav_agent: NavigationAgent3D
var _path_update_timer: float = 0.0

# Player reference
var _player: CharacterBody3D = null

# OBSERVE state
var _waypoints: Array[Vector3] = []
var _current_waypoint_index: int = 0
var _waypoint_dwell_timer: float = 0.0
var _waypoint_dwell_duration: float = observe_dwell_max

# ─── PUBLIC API ────────────────────────────────────────────────────────
func set_dormant() -> void:
	_transition_to(State.DORMANT)

func set_active() -> void:
	_transition_to(State.OBSERVE)

func get_current_state() -> State:
	return _current_state

# ─── LIFECYCLE ─────────────────────────────────────────────────────────
func _ready() -> void:
	# Setup NavigationAgent3D
	_nav_agent = $NavigationAgent3D
	assert(_nav_agent != null, "Entity v2: NavigationAgent3D child node is required.")
	_nav_agent.path_desired_distance = nav_path_desired_distance
	_nav_agent.target_desired_distance = nav_target_desired_distance
	_nav_agent.avoidance_enabled = true
	_nav_agent.max_speed = charge_speed  # Cap at highest speed

	_resolve_player_reference()
	_initialize_waypoints()

	# Start in OBSERVE by default (caller can set_dormant() to freeze)
	_transition_to(State.OBSERVE)

func _physics_process(delta: float) -> void:
	# ─── DORMANT: freeze — early exit, no nav processing ───────────
	if _current_state == State.DORMANT:
		_velocity = Vector3.ZERO
		_nav_agent.target_position = global_position  # Stop any in-flight navigation
		move_and_slide()
		return

	# ─── Resolve player reference (retry each frame until found) ──
	if _player == null:
		_resolve_player_reference()
		if _player == null:
			_velocity = Vector3.ZERO
			move_and_slide()
			return

	# ─── Path update throttle ────────────────────────────────────
	_path_update_timer -= delta

	# ─── Cross-cutting state transition checks ───────────────────
	_cross_cutting_state_checks(delta)

	# ─── State dispatcher ────────────────────────────────────────
	match _current_state:
		State.OBSERVE:
			_observe_process(delta)
		State.STALK:
			_stalk_process(delta)
		State.CHARGE:
			_charge_process(delta)
		_:
			_velocity = Vector3.ZERO

	# ─── Apply velocity ─────────────────────────────────────────
	if not is_on_floor():
		_velocity.y -= ProjectSettings.get_setting("physics/3d/default_gravity") * delta

	move_and_slide()

# ─── CROSS-CUTTING STATE CHECKS ─────────────────────────────────────
func _cross_cutting_state_checks(_delta: float) -> void:
	if _player == null:
		return

	var dist := global_position.distance_to(_player.global_position)

	match _current_state:
		State.OBSERVE:
			# If player is within awareness range, escalate to STALK
			if dist <= stalk_lose_distance and dist > charge_break_distance:
				_transition_to(State.STALK)

		State.STALK:
			# Close enough → CHARGE
			if dist <= charge_trigger_distance:
				_transition_to(State.CHARGE)
			# Too far → OBSERVE
			elif dist > stalk_lose_distance:
				_transition_to(State.OBSERVE)

		State.CHARGE:
			# Lost the player or they got too far → back to STALK
			if dist > charge_break_distance:
				_transition_to(State.STALK)

# ─── STATE: OBSERVE ─────────────────────────────────────────────────
func _observe_process(_delta: float) -> void:
	if _waypoints.is_empty():
		_velocity = Vector3.ZERO
		return

	var target_wp := _waypoints[_current_waypoint_index]
	var dist_to_wp := global_position.distance_to(target_wp)

	# Arrived at waypoint — stand still and wait
	if dist_to_wp <= waypoint_arrival_distance:
		_velocity = Vector3.ZERO
		_nav_agent.target_position = global_position  # Stop navigation
		_waypoint_dwell_timer -= _delta
		if _waypoint_dwell_timer <= 0.0:
			_pick_next_waypoint()
		return

	# Path toward waypoint
	if _path_update_timer <= 0.0:
		_nav_agent.target_position = target_wp
		_path_update_timer = path_update_interval

	_navigate_to_target(observe_speed)

func _pick_next_waypoint() -> void:
	if _waypoints.size() <= 1:
		_current_waypoint_index = 0
	else:
		var new_index: int
		while true:
			new_index = randi() % _waypoints.size()
			if new_index != _current_waypoint_index:
				break
		_current_waypoint_index = new_index

	_waypoint_dwell_timer = randf_range(observe_dwell_min, observe_dwell_max)

# ─── STATE: STALK ───────────────────────────────────────────────────
func _stalk_process(_delta: float) -> void:
	var player_pos := _player.global_position
	var dist := global_position.distance_to(player_pos)

	# Update navigation target
	if _path_update_timer <= 0.0:
		_nav_agent.target_position = player_pos
		_path_update_timer = path_update_interval

	_navigate_to_target(stalk_speed)

# ─── STATE: CHARGE ─────────────────────────────────────────────────
func _charge_process(_delta: float) -> void:
	var player_pos := _player.global_position
	# Direct line-of-sight direction (no pathfinding)
	var direction := (player_pos - global_position).normalized()
	direction.y = 0.0  # Keep on ground plane

	_velocity = direction * charge_speed

# ─── NAVIGATION HELPER ──────────────────────────────────────────────
func _navigate_to_target(speed: float) -> void:
	if _nav_agent.is_navigation_finished():
		_velocity = Vector3.ZERO
		return

	var next_pos := _nav_agent.get_next_path_position()
	var direction := (next_pos - global_position).normalized()
	direction.y = 0.0

	_velocity = direction * speed

# ─── TRANSITION HUB ─────────────────────────────────────────────────
func _transition_to(new_state: State) -> void:
	if _current_state == new_state:
		return

	_current_state = new_state

	match new_state:
		State.DORMANT:
			_velocity = Vector3.ZERO
			_move_speed = 0.0
			_nav_agent.target_position = global_position

		State.OBSERVE:
			_move_speed = observe_speed
			_waypoint_dwell_timer = randf_range(observe_dwell_min, observe_dwell_max)
			_path_update_timer = 0.0  # Force immediate path update

		State.STALK:
			_move_speed = stalk_speed
			_path_update_timer = 0.0  # Force immediate path to player

		State.CHARGE:
			_move_speed = charge_speed
			# Velocity is computed directly each frame — no nav agent target needed

# ─── PLAYER REFERENCE ──────────────────────────────────────────────────
func _resolve_player_reference() -> void:
	if _player != null:
		return
	# Try group-based lookup first
	var players := get_tree().get_nodes_in_group("Player")
	if players.size() > 0:
		_player = players[0] as CharacterBody3D
		return
	# Fallback: scan the scene for the first CharacterBody3D that isn't us
	for node in get_tree().get_nodes_in_group(""):
		if node is CharacterBody3D and node != self:
			_player = node as CharacterBody3D
			return

# ─── WAYPOINT INITIALIZATION ──────────────────────────────────────────
func _initialize_waypoints() -> void:
	var waypoint_nodes := get_tree().get_nodes_in_group("TreelineWaypoints")
	if waypoint_nodes.is_empty():
		push_warning("Entity v2: No nodes in 'TreelineWaypoints' group. OBSERVE state will be idle.")
		return

	for node in waypoint_nodes:
		if node is Node3D:
			_waypoints.append(node.global_position)

	print("[Entity v2] Loaded %d treeline waypoints." % _waypoints.size())