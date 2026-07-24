extends Area3D
class_name PCInteractable

## PCInteractable — Physical PC monitor interaction trigger.
## Attach this script to an Area3D (named "InteractionArea") that is a child
## of the pc_monitor_mp_12 model node in the scene.
##
## When the player looks at the monitor and presses E, this script opens
## the ComputerUI overlay (Windows 98-style Archival System).
##
## The InteractionArea needs a CollisionShape3D child (a box shape works well)
## positioned to cover the monitor screen so the player can click on it.
##
## POWER GRID INTEGRATION:
## The monitor screen turns black when the generator is off (NightManager).
## When power is restored, the screen boots back up automatically.
## If the player tries to use the computer while the generator is off,
## interaction is blocked with a contextual HUD message.
##
## MATERIAL STRATEGY:
## We cache the original material from the mesh resource and never modify it.
## For the unpowered state, we create a fresh StandardMaterial3D with solid
## black albedo as a surface override. For the powered state, we restore the
## cached original material back into the override slot. This ensures the
## retro desktop texture is never lost or corrupted.

## Marker3D that defines where the player's camera should be positioned
## when sitting at the computer (cinematic sitting transition).
@export var sit_marker: Marker3D

## Reference to the ComputerUI CanvasLayer node.
## Found at runtime via the "computer_ui" group.
var _computer_ui: Node = null

## Reference to the player's CameraHolder node (found at runtime)
var _camera_holder: Node3D = null

## The CameraHolder's original global transform, saved before the sitting tween
var _original_cam_transform: Transform3D

## Reference to the pc_monitor_mp_1_screen MeshInstance3D
var _screen_mesh: MeshInstance3D = null

## The material to display on the 3D screen when powered.
## Uses the original CRT material from the mesh resource.
var _viewport_material: Material = null

## Cached original material from the mesh resource — never modified directly.
## We store this so we can restore the pristine CRT texture on power restore.
var _original_screen_material: Material = null

## A simple black material used as the surface override when unpowered.
## Created once and reused to avoid allocating every power toggle.
var _blackout_material: Material = null

## Whether the computer is currently usable (generator is on).
var _is_powered: bool = true

## Interaction state guard: prevents interact() from firing multiple times
## while the player is already seated at the terminal. UI clicks can trigger
## secondary interaction checks that would otherwise overwrite the pristine
## standing transform with the chair's coordinates, causing the player to
## clip through walls upon exit.
var _is_player_sitting: bool = false

## Surface index for the CRT screen material (crt_screen_mp_2).
const SCREEN_SURFACE_INDEX: int = 1


func _ready() -> void:
	add_to_group("interactable")

	# --- POWER GRID SETUP ---
	# Find the screen mesh, cache the original material, and create the
	# blackout material — all before checking the generator state.
	_setup_screen_references()

	# Check initial generator state from NightManager
	var nm = get_node_or_null("/root/NightManager")
	if nm:
		_is_powered = nm.is_generator_on
		# Connect to generator state changes
		if nm.generator_state_changed.is_connected(_on_generator_state_changed):
			nm.generator_state_changed.disconnect(_on_generator_state_changed)
		nm.generator_state_changed.connect(_on_generator_state_changed)

	# Apply initial screen state
	_update_screen_state()

	# --- UI SETUP ---
	# Find the ComputerUI CanvasLayer node via the "computer_ui" group.
	# The ComputerUI is now a direct child of the main scene (CottageHorror),
	# not nested inside a SubViewport. We use group-based discovery for
	# decoupled, reliable access.
	_computer_ui = get_tree().get_first_node_in_group("computer_ui")
	if not _computer_ui:
		print("[PCInteractable] ERROR: Could not find ComputerUI via group 'computer_ui'!")
		return

	# Find the player's CameraHolder for the sitting animation
	_camera_holder = _find_camera_holder()

	# Pass player and camera_holder references to the ComputerUI
	# so it doesn't need to look them up itself (more reliable)
	if _computer_ui.has_method("set_player_references"):
		var player = get_tree().get_first_node_in_group("player")
		_computer_ui.set_player_references(player, _camera_holder)

	# Ensure it's hidden by default
	if _computer_ui.has_method("close_computer"):
		_computer_ui.close_computer()


## Finds the pc_monitor_mp_1_screen MeshInstance3D, caches the original
## CRT material from the mesh resource, and creates a blackout material
## for the unpowered state.
##
## Node hierarchy in computer.tscn:
##   Computer (Node3D)          <-- our grandparent
##     ├── pc_monitor_mp_12 (Node3D, GLB instance root)
##     │   ├── pc_monitor_mp_1 (MeshInstance3D, monitor body)
##     │   └── pc_monitor_mp_1_screen (MeshInstance3D, screen surface)
##     ├── SitMarker (Marker3D)
##     └── InteractionArea (Area3D)  <-- this script is here
##
## The crt_screen_mp_2 material is on surface index 1 of the
## pc_monitor_mp_1_screen mesh (the second primitive of that mesh).
func _setup_screen_references() -> void:
	# Walk up to find the Computer root node (our parent)
	var computer_root = get_parent()
	if not computer_root:
		return

	# Find the screen mesh instance nested inside the GLB hierarchy
	var screen_mi: MeshInstance3D = null

	# Try the expected path: pc_monitor_mp_12/pc_monitor_mp_1_screen
	var glb_root = computer_root.get_node_or_null("pc_monitor_mp_12")
	if glb_root:
		screen_mi = glb_root.get_node_or_null("pc_monitor_mp_1_screen")

	# Fallback: search recursively for any MeshInstance3D named pc_monitor_mp_1_screen
	if not screen_mi:
		screen_mi = _find_mesh_instance_recursive(computer_root, "pc_monitor_mp_1_screen")

	if not screen_mi:
		print("[PCInteractable] WARNING: Could not find pc_monitor_mp_1_screen mesh!")
		return

	_screen_mesh = screen_mi

	var mesh = screen_mi.mesh
	if not mesh:
		print("[PCInteractable] WARNING: pc_monitor_mp_1_screen has no mesh!")
		return

	# Surface 1 is the CRT screen (crt_screen_mp_2 material slot).
	# From the GLB: Mesh 0 (pc_monitor_mp_1_screen) has 2 primitives:
	#   Primitive 0 -> Material 0 (pc_monitor_mp_1)
	#   Primitive 1 -> Material 1 (crt_screen_mp_2)
	var surface_count = mesh.get_surface_count()
	if surface_count <= SCREEN_SURFACE_INDEX:
		print("[PCInteractable] WARNING: Screen mesh has only ", surface_count,
			" surfaces (expected at least ", SCREEN_SURFACE_INDEX + 1, ")!")
		return

	# Cache the original material directly from the mesh resource.
	# We NEVER modify this — it stays pristine for restoration.
	_original_screen_material = mesh.surface_get_material(SCREEN_SURFACE_INDEX)
	if not _original_screen_material:
		print("[PCInteractable] WARNING: No material found on surface ", SCREEN_SURFACE_INDEX, "!")
		return

	# Create a clean blackout material for the unpowered state.
	# This is a fresh StandardMaterial3D — no texture references to lose.
	_blackout_material = StandardMaterial3D.new()
	_blackout_material.albedo_color = Color.BLACK
	_blackout_material.roughness = 0.2  # Retro glass reflection

	# Use the original CRT material as the viewport material for the powered state.
	# The ComputerUI is now a CanvasLayer overlay (not rendered into a SubViewport),
	# so the 3D screen displays the original CRT texture when powered.
	_viewport_material = _original_screen_material

	print("[PCInteractable] Screen references set up. Original material: ",
		_original_screen_material.resource_name)


## Recursively searches for a MeshInstance3D with the given name
## starting from the given root node.
func _find_mesh_instance_recursive(root: Node, name: String) -> MeshInstance3D:
	for child in root.get_children():
		if child is MeshInstance3D and child.name == name:
			return child
		var found = _find_mesh_instance_recursive(child, name)
		if found:
			return found
	return null


## Updates the screen material based on the current power state.
## Unpowered: applies a solid black material override (no texture, no emission).
## Powered: applies the original CRT material on the 3D screen mesh.
func _update_screen_state() -> void:
	if not _screen_mesh:
		return

	if _is_powered:
		# Apply the original CRT material — displays the retro desktop texture.
		if _viewport_material:
			_screen_mesh.set_surface_override_material(SCREEN_SURFACE_INDEX, _viewport_material)
	else:
		# Apply the blackout material — no texture, no emission, just black
		if _blackout_material:
			_screen_mesh.set_surface_override_material(SCREEN_SURFACE_INDEX, _blackout_material)


## Called when NightManager emits generator_state_changed.
## Updates the screen state and interaction availability.
func _on_generator_state_changed(is_running: bool) -> void:
	_is_powered = is_running
	_update_screen_state()

	if is_running:
		print("[PCInteractable] Generator restored — monitor is now powered.")
	else:
		print("[PCInteractable] Generator lost — monitor is now dark.")


## Walks up the scene tree to find the Player's CameraHolder node.
func _find_camera_holder() -> Node3D:
	var player = get_tree().get_first_node_in_group("player")
	if player:
		var holder = player.get_node_or_null("CameraHolder")
		if holder is Node3D:
			return holder
	return null


## Called by the InteractionManager when the player looks at the monitor
## and presses E. Opens the computer UI overlay with a cinematic sitting
## camera transition.
## If the generator is off, blocks interaction and prints a contextual message.
func interact() -> void:
	# --- INTERACTION STATE GUARD ---
	# Prevents interact() from firing multiple times while the player is
	# already seated at the terminal. UI clicks can trigger secondary
	# interaction checks that would otherwise overwrite the pristine
	# standing transform with the chair's coordinates, causing the player
	# to clip through walls upon exit.
	if _is_player_sitting:
		print("[PCInteractable] Interaction ignored: Player is already using the computer.")
		return

	# --- POWER CHECK ---
	# Block interaction if the generator is off
	if not _is_powered:
		print("[PCInteractable] The monitor is dead. There's no power grid activity.")
		# Notify RoutineManager that the player tried the computer without power
		var rm = get_node_or_null("/root/RoutineManager")
		if rm and rm.has_method("on_computer_tried_no_power"):
			rm.on_computer_tried_no_power()
		return

	if not _computer_ui:
		print("[PCInteractable] ComputerUI not available!")
		return

	if not _camera_holder:
		print("[PCInteractable] CameraHolder not found!")
		return

	if not sit_marker:
		print("[PCInteractable] sit_marker not assigned!")
		return

	# --- DISABLE PLAYER INPUT FIRST ---
	# We must disable the player BEFORE the tween, otherwise the player
	# controller's _input() and _physics_process() will fight the tween
	# every frame, causing erratic camera movement.
	var player = get_tree().get_first_node_in_group("player")
	if player:
		player.set_process_input(false)
		player.set_physics_process(false)

	# Unlock the mouse so the tween can move the camera freely
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

	# Force the camera's Z-axis rotation to absolute 0.0 BEFORE saving the
	# original transform. This prevents any accumulated roll/tilt from head bob,
	# physics drift, or floating-point error from being baked into the saved
	# transform and later restored when the player stands up.
	#
	# We use a two-step cleanse:
	#   1. Force rotation.z to 0.0 (eliminate Euler roll)
	#   2. Orthonormalize the basis (wipe out any float skew/shearing from
	#      the Euler-to-quaternion round-trip)
	# This guarantees the saved transform has exactly zero roll, so the
	# standing-up tween restores a perfectly level camera horizon.
	var current_rot = _camera_holder.rotation
	current_rot.z = 0.0
	_camera_holder.rotation = current_rot
	_camera_holder.global_transform.basis = _camera_holder.global_transform.basis.orthonormalized()

	# Mark the player as sitting BEFORE saving the transform, so any stray
	# secondary interact() calls from UI clicks are immediately rejected.
	_is_player_sitting = true

	# Save the CameraHolder's original transform so we can return to it later.
	# IMPORTANT: This must happen AFTER zeroing the Z-rotation above, otherwise
	# the stale Z-tilt gets baked into the saved transform and is restored on
	# stand-up, causing a persistent camera tilt.
	_original_cam_transform = _camera_holder.global_transform
	
	# Pass the original transform to the ComputerUI so it can restore it on close
	if _computer_ui.has_method("set_original_camera_transform"):
		_computer_ui.set_original_camera_transform(_original_cam_transform)

	# Tween the CameraHolder to the sit_marker's position
	var tween = create_tween()
	tween.set_parallel(false)
	tween.tween_property(_camera_holder, "global_transform", sit_marker.global_transform, 0.5)\
		.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)

	# After the tween finishes, open the computer UI
	tween.finished.connect(_on_sit_tween_completed)

	print("[PCInteractable] Player sitting at the PC monitor.")


## Called when the sitting tween animation completes.
## Opens the computer UI overlay and connects the close signal
## to reset the interaction state guard.
func _on_sit_tween_completed() -> void:
	if _computer_ui.has_method("open_computer"):
		_computer_ui.open_computer()
		print("[PCInteractable] Player interacted with the PC monitor.")
	else:
		print("[PCInteractable] ERROR: ComputerUI missing open_computer method!")
		return

	# Connect to the computer_closed signal so we reset the sitting flag
	# when the player exits the terminal. Use a one-shot connection to
	# avoid accumulating duplicate connections across multiple sessions.
	if _computer_ui.has_signal("computer_closed"):
		if _computer_ui.computer_closed.is_connected(_on_computer_closed):
			_computer_ui.computer_closed.disconnect(_on_computer_closed)
		_computer_ui.computer_closed.connect(_on_computer_closed)
	
	# ─── REMOVED: Day 1 onboarding `on_computer_used()` call.
	# This incorrectly fired when the PC UI opened (before login), causing
	# the "Get planks" objective to appear too early.
	# The correct trigger is in computer_ui.gd:_on_login_submit() which only
	# fires when the player actually logs in as LUND with the correct password.



## Called when the ComputerUI emits computer_closed (player exits the terminal).
## Resets the interaction state guard so the player can sit again.
func _on_computer_closed() -> void:
	_is_player_sitting = false
	print("[PCInteractable] Player stood up. _is_player_sitting reset to false.")


## Returns the interaction prompt text shown in the HUD.
## Shows a contextual "no power" message when the generator is off.
func get_interact_text() -> String:
	if not _is_powered:
		return "[E] Use Computer (No Power)"
	return "[E] Use Computer"
