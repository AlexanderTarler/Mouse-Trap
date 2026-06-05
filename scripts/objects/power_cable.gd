extends Node3D
class_name PowerCable

## PowerCable — Standalone verlet-physics power cable that stretches between
## a generator outlet and a PortableLamp (or the player's hand while dragging).
##
## This is a multi-step connection puzzle:
##   1. Player collects a cable spool item.
##   2. Player interacts with the generator outlet → spawns this cable,
##      sets state to PLUGGED_TO_SOURCE, attaches to player's hand.
##   3. Player carries the free end to a deployed PortableLamp and interacts
##      with its base → state becomes FULLY_CONNECTED, lamp.is_powered = true.
##
## The cable uses pure GLOBAL coordinates for all point sampling to prevent
## local transform warping that caused the "closed loop" bug.

# ─── CONNECTION STATES ──────────────────────────────────────────────────────

enum CableState {
	DISCONNECTED,       # Cable not in use — no geometry drawn
	PLUGGED_TO_SOURCE,  # Plugged into generator outlet, free end in player's hand
	FULLY_CONNECTED     # Both ends connected: outlet → lamp
}

## Current connection state of this cable.
var current_state: CableState = CableState.DISCONNECTED:
	set(value):
		current_state = value
		# Reset the verlet simulation when state changes so particles
		# re-initialize along the new target path
		_cable_initialized = false
		# Show/hide the mesh based on state
		if _cable_mesh_instance:
			_cable_mesh_instance.visible = value != CableState.DISCONNECTED

# ─── TARGET NODES ───────────────────────────────────────────────────────────

## The generator outlet node (Marker3D or mesh) the cable originates from.
## Set when the player plugs the cable into the generator.
var source_node: Node3D = null

## The PortableLamp node the cable connects to.
## Set when the player connects the free end to a deployed lamp.
var target_node: Node3D = null

## Fallback target while the player is dragging the free end.
## When PLUGGED_TO_SOURCE, the cable draws from source_node to player_hand.
var player_hand: Marker3D = null

# ─── CABLE VISUALS ──────────────────────────────────────────────────────────

## Material for the cable — a solid, heavy industrial rubber look.
## Assign a StandardMaterial3D with dark orange/black color in the editor.
@export var cable_material: Material = null

## Maximum cable length in meters. The lamp clamps at this distance.
@export var max_cable_length: float = 20.0


## Cable radius for the tube geometry.
@export var cable_radius: float = 0.04

## Number of vertices around the circumference (6 = hexagonal tube).
@export var radial_segments: int = 6

# ─── VERLET SIMULATION ──────────────────────────────────────────────────────

## Number of verlet particles in the cable simulation.
const CABLE_PARTICLES: int = 12

## Verlet particle positions (global space).
var _cable_points: PackedVector3Array = PackedVector3Array()

## Previous-frame positions for verlet integration.
var _cable_prev: PackedVector3Array = PackedVector3Array()

## Whether the cable simulation has been initialized.
var _cable_initialized: bool = false

## The ImmediateMesh used to draw the cable line each frame.
var _cable_mesh: ImmediateMesh = null

## The MeshInstance3D that renders the cable in the world.
var _cable_mesh_instance: MeshInstance3D = null


func _ready() -> void:
	add_to_group("power_cable")
	
	# ─── CABLE MESH SETUP ────────────────────────────────────────────────
	# Create a MeshInstance3D with an ImmediateMesh for the cable.
	# We set it as top-level so its transform uses global coordinates,
	# preventing any parent node movement from warping the cable geometry.
	_cable_mesh = ImmediateMesh.new()
	_cable_mesh_instance = MeshInstance3D.new()
	_cable_mesh_instance.mesh = _cable_mesh
	_cable_mesh_instance.top_level = true  # Use global transform
	_cable_mesh_instance.visible = false   # Hidden until connected
	add_child(_cable_mesh_instance)
	
	# If no cable material is assigned, create a default dark orange rubber
	if not cable_material:
		var default_mat := StandardMaterial3D.new()
		default_mat.albedo_color = Color(0.35, 0.15, 0.05)  # Dark orange/brown
		default_mat.roughness = 0.9
		default_mat.metallic = 0.0
		cable_material = default_mat


## ─── PUBLIC API ────────────────────────────────────────────────────────────

## Plugs the cable into the generator outlet and attaches the free end
## to the player's hand for dragging.
func plug_to_source(outlet: Node3D, hand: Marker3D) -> void:
	source_node = outlet
	player_hand = hand
	current_state = CableState.PLUGGED_TO_SOURCE
	print("[PowerCable] Plugged to source. Drag the free end to a lamp.")


## Connects the free end of the cable to a deployed PortableLamp.
## The cable now draws from source_node to target_node.
func connect_to_lamp(lamp: Node) -> void:
	target_node = lamp
	player_hand = null
	current_state = CableState.FULLY_CONNECTED
	
	# Tell the lamp it's powered
	if lamp.has_method("set_powered"):
		lamp.set_powered(true)
	
	print("[PowerCable] Fully connected: outlet → lamp.")


## Disconnects the cable and resets to DISCONNECTED state.
func disconnect_cable() -> void:
	source_node = null
	target_node = null
	player_hand = null
	current_state = CableState.DISCONNECTED
	_cable_initialized = false
	print("[PowerCable] Disconnected.")


## Returns the current CableState enum value.
## Used by PortableLamp to check if the cable is in PLUGGED_TO_SOURCE state
## (free end in player's hand, ready to connect to a lamp).
func get_state() -> int:
	return current_state


## Returns the global position of the source (generator outlet).
## Used by PortableLamp to enforce the 20-meter cable length limit.
func get_source_position() -> Vector3:
	if source_node:
		return source_node.global_position
	return global_position


## Returns the current end position for the cable (hand or lamp).
func _get_end_position() -> Vector3:


	match current_state:
		CableState.PLUGGED_TO_SOURCE:
			if player_hand:
				return player_hand.global_position
		CableState.FULLY_CONNECTED:
			if target_node:
				return target_node.global_position
	
	return global_position


## ─── VERLET CABLE SIMULATION ──────────────────────────────────────────────

## Initializes the cable particle chain along the straight line from source
## to end, with sag inversely proportional to stretch ratio.
## At max extension (20m) the cable starts nearly straight; at short distances
## it hangs with a natural droop.
func _init_cable_particles() -> void:
	if not source_node:
		return
	
	var start_pos: Vector3 = source_node.global_position
	var end_pos: Vector3 = _get_end_position()
	
	_cable_points.resize(CABLE_PARTICLES)
	_cable_prev.resize(CABLE_PARTICLES)
	
	# Calculate stretch ratio: 0.0 = slack (close to outlet), 1.0 = taut (at max length)
	var span: float = start_pos.distance_to(end_pos)
	var stretch_ratio: float = clampf(span / max_cable_length, 0.0, 1.0)
	# Sag amplitude: 0.5m when slack, tapering to 0.05m when fully taut
	var sag_amplitude: float = lerpf(0.5, 0.05, stretch_ratio)
	
	for i in range(CABLE_PARTICLES):
		var t: float = float(i) / float(CABLE_PARTICLES - 1)
		var p: Vector3 = start_pos.lerp(end_pos, t)
		# Sag decreases as the cable stretches toward max length
		p.y -= sin(t * PI) * sag_amplitude
		_cable_points[i] = p
		_cable_prev[i] = p
	
	_cable_initialized = true



## Runs one step of the verlet cable simulation.
## Called from _physics_process() so it runs at a fixed timestep.
func _simulate_cable(delta: float) -> void:
	if not source_node or current_state == CableState.DISCONNECTED:
		return
	
	# Initialize particles on first run
	if not _cable_initialized:
		_init_cable_particles()
		return
	
	var outlet_pos: Vector3 = source_node.global_position
	var end_pos: Vector3 = _get_end_position()
	
	# ─── 1. PIN ENDPOINTS ────────────────────────────────────────────────
	# Particle 0 is pinned to the generator outlet.
	_cable_points[0] = outlet_pos
	_cable_prev[0] = outlet_pos
	
	# Last particle is pinned to the end position (hand or lamp).
	var last_idx: int = CABLE_PARTICLES - 1
	_cable_points[last_idx] = end_pos
	_cable_prev[last_idx] = end_pos
	
	# ─── 2. VERLET INTEGRATION (intermediate particles) ──────────────────
	# Scale gravity by stretch ratio so the cable tightens as it approaches
	# max length. At 20m the cable appears nearly straight and taut.
	var span: float = outlet_pos.distance_to(end_pos)
	var stretch_ratio: float = clampf(span / max_cable_length, 0.0, 1.0)
	# Gravity multiplier: 1.0 at slack, tapering to 0.15 at max extension
	var gravity_scale: float = lerpf(1.0, 0.15, stretch_ratio)
	var gravity: Vector3 = Vector3(0.0, -9.8 * gravity_scale, 0.0)
	var damping: float = 0.99  # Slight energy loss per step

	
	for i in range(1, last_idx):
		var current: Vector3 = _cable_points[i]
		var prev: Vector3 = _cable_prev[i]
		
		# Verlet: new_pos = current + (current - prev) * damping + gravity * dt^2
		var velocity: Vector3 = (current - prev) * damping
		var new_pos: Vector3 = current + velocity + gravity * delta * delta
		
		_cable_prev[i] = current
		_cable_points[i] = new_pos
	
	# ─── 3. CONSTRAINT ITERATIONS (keep segment lengths consistent) ──────
	var segment_length: float = outlet_pos.distance_to(end_pos) / float(CABLE_PARTICLES - 1)
	if segment_length < 0.3:
		segment_length = 0.3
	
	for _iter in range(8):  # 8 iterations for good stiffness
		for i in range(CABLE_PARTICLES - 1):
			var p1: Vector3 = _cable_points[i]
			var p2: Vector3 = _cable_points[i + 1]
			var diff: Vector3 = p2 - p1
			var dist: float = diff.length()
			
			if dist < 0.001:
				continue
			
			var correction: Vector3 = diff * (1.0 - segment_length / dist) * 0.5
			
			# Don't move pinned endpoints
			if i > 0:
				_cable_points[i] += correction
			if i + 1 < last_idx:
				_cable_points[i + 1] -= correction


## ─── CABLE DRAWING ─────────────────────────────────────────────────────────

## Draws the cable geometry from the verlet particle positions.
## Uses a tube-like triangle strip with multiple vertices around the
## circumference at each point, giving the cable a proper 3D cylindrical
## appearance. All coordinates are in GLOBAL space.
func _draw_cable() -> void:
	if current_state == CableState.DISCONNECTED:
		return
	
	if not _cable_mesh or not cable_material or _cable_points.size() < 2:
		return
	
	_cable_mesh.clear_surfaces()
	
	# Build a smooth set of points by subdividing the particle chain
	var smooth_points: PackedVector3Array = PackedVector3Array()
	var sub_segments: int = 3  # Subdivide each particle gap for smooth curves
	
	for i in range(CABLE_PARTICLES - 1):
		var p1: Vector3 = _cable_points[i]
		var p2: Vector3 = _cable_points[i + 1]
		for s in range(sub_segments):
			var t: float = float(s) / float(sub_segments)
			smooth_points.append(p1.lerp(p2, t))
	# Add the last point
	smooth_points.append(_cable_points[CABLE_PARTICLES - 1])
	
	# Pre-compute direction and basis for each point
	var bases: Array[Basis] = []
	
	for i in range(smooth_points.size()):
		var p: Vector3 = smooth_points[i]
		
		# Compute the direction along the cable at this point
		var dir: Vector3
		if i == 0:
			dir = (smooth_points[1] - smooth_points[0]).normalized()
		elif i == smooth_points.size() - 1:
			dir = (smooth_points[i] - smooth_points[i - 1]).normalized()
		else:
			dir = (smooth_points[i + 1] - smooth_points[i - 1]).normalized()
		
		if dir.length_squared() < 0.001:
			dir = Vector3.UP
		
		# Build a basis from the direction vector
		var up: Vector3 = Vector3.UP
		if abs(dir.dot(up)) > 0.99:
			up = Vector3.RIGHT
		var right: Vector3 = dir.cross(up).normalized()
		var fwd: Vector3 = right.cross(dir).normalized()
		bases.append(Basis(right, fwd, dir))
	
	# Draw the entire cable as a single continuous triangle strip.
	_cable_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP, cable_material)
	
	for i in range(smooth_points.size() - 1):
		var p1: Vector3 = smooth_points[i]
		var p2: Vector3 = smooth_points[i + 1]
		var basis1: Basis = bases[i]
		var basis2: Basis = bases[i + 1]
		
		for r in range(radial_segments + 1):
			var angle: float = float(r) / float(radial_segments) * TAU
			var cos_a: float = cos(angle)
			var sin_a: float = sin(angle)
			
			# Ring vertex at p1 (global coordinates)
			var offset1: Vector3 = basis1.x * (cos_a * cable_radius) + basis1.y * (sin_a * cable_radius)
			_cable_mesh.surface_add_vertex(p1 + offset1)
			
			# Ring vertex at p2 (global coordinates)
			var offset2: Vector3 = basis2.x * (cos_a * cable_radius) + basis2.y * (sin_a * cable_radius)
			_cable_mesh.surface_add_vertex(p2 + offset2)
	
	_cable_mesh.surface_end()


## ─── MAIN LOOPS ────────────────────────────────────────────────────────────

## Main _process loop — draws the cable geometry each frame.
func _process(_delta: float) -> void:
	_draw_cable()


## Physics loop — runs the verlet simulation at fixed timestep.
func _physics_process(delta: float) -> void:
	if current_state != CableState.DISCONNECTED:
		_simulate_cable(delta)
