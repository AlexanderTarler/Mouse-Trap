extends Node3D
class_name CabinWindow

## CabinWindow — Window barricade and light sanctuary system.
## Attach this script to each window Marker3D (or a parent node) in the cabin.
##
## TWO-STAGE DESTRUCTION SYSTEM (Outside → Inside):
##   Stage 1 (Glass Shatter): The Entity smashes through the glass panes and
##     crossbars FIRST. PristineVisuals are hidden, ShatteredVisuals are shown.
##     Glass is permanently destroyed — can never be restored.
##     Interior planks are UNTOUCHED during this phase.
##   Stage 2 (Plank Break): If the player boarded up the shattered window with
##     Wooden Planks, the Entity must damage the planks until they break.
##     Once planks break, the Entity can enter the cabin.
##
## PHYSICAL LAYER ORDER (Outside → Inside):
##   Outside (Entity side)
##     ├── NavBlocker (StaticBody3D) — blocks Entity pathfinding
##     ├── PristineVisuals — frame, crossbars, glass pane
##     ├── ShatteredVisuals — splintered stumps, hollow cavity
##     ├── BarricadePlanks — 3 plank meshes (Z = +0.15, behind glass)
##     └── IndoorBreachWayPoint — ~1.5m inside the room
##   Inside (Player side)
##
## The three plank meshes (Plank1, Plank2, Plank3) visualize the barricade's
## remaining health:
##   - 100%–67% : All 3 planks visible
##   - 66%–34%  : Plank3 disappears (2 planks visible)
##   - 33%–1%   : Plank2 disappears (1 plank visible)
##   - 0%       : Plank1 disappears (barricade broken)
##
## If the room's CabinLight is switched on, the window is considered "secure"
## by light — the Entity will avoid it and pick a different window.
## If boarded up, the Entity must pause and damage the planks until they break.
## If glass is intact, the Entity must shatter it first.
##
## is_secure() returns true if EITHER the light is on, the window is boarded,
## OR the glass is intact.

## Human-readable identifier for this window (e.g. "LivingRoom", "Kitchen", "Bedroom1").
## Used by the F2 debug tool and AI decision-making to reference specific windows.
## Assign a unique, meaningful name in the Inspector for each window instance.
@export var window_id: String = ""

## Reference to the corresponding room's CabinLight node.
## Assign this in the scene editor to link the window to its room light.
@export var room_light: CabinLight = null

## Whether this window is currently boarded up with planks
var is_boarded: bool = false

## Whether the glass panes and crossbars have been shattered by the Entity.
## Once true, the glass is permanently destroyed and can never be restored.
## The player can still board up the opening with planks, but the glass is gone.
var is_glass_shattered: bool = false

## Number of planks still intact (3 = fully boarded, 0 = fully breached).
## Each plank requires HITS_PER_PLANK hits from the Entity to break.
var planks_remaining: int = 3

## Hits accumulated on the current plank. When this reaches HITS_PER_PLANK,
## one plank breaks and the counter resets for the next plank.
var hits_on_current_plank: int = 0

## Number of Entity hits required to break a single plank.
const HITS_PER_PLANK: int = 3

## Reference to the three individual plank meshes (children of BarricadePlanks).
## These are toggled on/off based on remaining health to give a visual
## indication of barricade integrity.
@onready var _plank_1: Node3D = $BarricadePlanks/Plank1 if has_node("BarricadePlanks/Plank1") else null
@onready var _plank_2: Node3D = $BarricadePlanks/Plank2 if has_node("BarricadePlanks/Plank2") else null
@onready var _plank_3: Node3D = $BarricadePlanks/Plank3 if has_node("BarricadePlanks/Plank3") else null

## Reference to an AudioStreamPlayer3D for the plank break sound
@onready var _break_sound: AudioStreamPlayer3D = $BreakSound if has_node("BreakSound") else null

## Reference to an AudioStreamPlayer3D for the plank hammer sound
@onready var _hammer_sound: AudioStreamPlayer3D = $HammerSound if has_node("HammerSound") else null

## Reference to the IndoorBreachWayPoint Marker3D — positioned ~1.5m inside the room
## behind the window opening. The Entity navigates here after shattering the barricade.
@onready var _indoor_breach_waypoint: Marker3D = $IndoorBreachWayPoint if has_node("IndoorBreachWayPoint") else null

# --- TWO-STAGE VISUAL STATE BRANCH ---
## PristineVisuals: Clean frame with intact crossbars and glass panes.
## Shown when is_glass_shattered is false.
@onready var _pristine_visuals: Node3D = $PristineVisuals if has_node("PristineVisuals") else null

## ShatteredVisuals: Splintered wooden stumps clinging to the frame borders,
## with a completely open, hollow center cavity. Shown when is_glass_shattered is true.
@onready var _shattered_visuals: Node3D = $ShatteredVisuals if has_node("ShatteredVisuals") else null

## Glass crunch sound — layered audio sting that plays simultaneously with
## the wood-splintering sound when the glass is shattered.
@onready var _glass_crunch_sound: AudioStreamPlayer3D = $GlassCrunchSound if has_node("GlassCrunchSound") else null

## GPU particles burst for glass shards flying inward when the window shatters.
@onready var _glass_shards: Node = $PristineVisuals/GlassShards if has_node("PristineVisuals/GlassShards") else null

## Navigation blocker — a StaticBody3D or Area3D that blocks the Entity's
## NavMesh path through the window until BOTH glass AND planks are cleared.
## This prevents the Entity from pathfinding through intact windows.
@onready var _nav_blocker: Node3D = $NavBlocker if has_node("NavBlocker") else null

# --- DEFERRED VISUAL SWAP STATE ---
## When true, a glass shatter visual swap is pending (delayed by _deferred_swap_timer).
## Set by _shatter_glass(), consumed by _process() when the timer expires.
var _deferred_glass_swap: bool = false

## When true, a plank break visual swap is pending (delayed by _deferred_swap_timer).
## Set by _shatter_barricade(), consumed by _process() when the timer expires.
var _deferred_plank_swap: bool = false

## Countdown timer for deferred visual swaps.
## Set to 0.5s for glass shatter, 0.3s for plank break.
## Decremented by delta in _process(). When it reaches 0.0, the pending
## visual swap is applied. This syncs the visual change with the impact
## frame of the AttackWindow animation.
var _deferred_swap_timer: float = 0.0


func _ready() -> void:
	# Add to the WindowMarkers group so the Entity AI can find this window
	add_to_group("WindowMarkers")
	
	# Initialize plank visibility based on initial state
	_update_plank_visuals()
	
	# Initialize window visual state (pristine shown, shattered hidden)
	_update_window_visuals()
	
	# Initialize navigation blocker state
	_update_nav_blocker()
	
	if OS.is_debug_build():
		# ─── DIAGNOSTIC VISIBILITY LOG ──────────────────────────────────
		# Logs the initial state of all visual child nodes at startup.
		# Only runs in debug builds to avoid console spam in production.
		# NOTE: Each diagnostic variable is explicitly typed to avoid Godot 4.6
		# static type warnings from ternary operators mixing Node3D and String.
		print("[CabinWindow Init] window_id='", window_id, "' | Path: ", get_path())
		var diag_pristine: String = str(_pristine_visuals) if _pristine_visuals else "MISSING"
		print("  PristineVisuals: ", diag_pristine)
		var diag_shattered: String = str(_shattered_visuals) if _shattered_visuals else "MISSING"
		print("  ShatteredVisuals: ", diag_shattered)
		var diag_plank1: String = str(_plank_1) if _plank_1 else "MISSING"
		print("  BarricadePlanks/Plank1: ", diag_plank1)
		var diag_plank2: String = str(_plank_2) if _plank_2 else "MISSING"
		print("  BarricadePlanks/Plank2: ", diag_plank2)
		var diag_plank3: String = str(_plank_3) if _plank_3 else "MISSING"
		print("  BarricadePlanks/Plank3: ", diag_plank3)
		var diag_nav: String = str(_nav_blocker) if _nav_blocker else "MISSING"
		print("  NavBlocker: ", diag_nav)
		var diag_waypoint: String = str(_indoor_breach_waypoint) if _indoor_breach_waypoint else "MISSING"
		print("  IndoorBreachWayPoint: ", diag_waypoint)
		var diag_break: String = str(_break_sound) if _break_sound else "MISSING"
		print("  BreakSound: ", diag_break)
		var diag_hammer: String = str(_hammer_sound) if _hammer_sound else "MISSING"
		print("  HammerSound: ", diag_hammer)
		var diag_crunch: String = str(_glass_crunch_sound) if _glass_crunch_sound else "MISSING"
		print("  GlassCrunchSound: ", diag_crunch)
		var diag_shards: String = str(_glass_shards) if _glass_shards else "MISSING"
		print("  GlassShards: ", diag_shards)
		print("[CabinWindow Init] End of diagnostic log for '", window_id, "'.")


func _process(delta: float) -> void:
	# Tick down the deferred swap timer
	if _deferred_swap_timer > 0.0:
		_deferred_swap_timer -= delta
		if _deferred_swap_timer <= 0.0:
			_deferred_swap_timer = 0.0
			
			# Apply pending glass swap
			if _deferred_glass_swap:
				_deferred_glass_swap = false
				_update_window_visuals()
				# Burst glass shard GPU particles
				if _glass_shards:
					_glass_shards.emitting = true
				# Layered audio: glass crunch + wood splintering simultaneously
				if _glass_crunch_sound:
					_glass_crunch_sound.play()
				if _break_sound:
					_break_sound.play()
				# Update the navigation blocker — glass is gone but planks may still block
				_update_nav_blocker()
				print("[CabinWindow] Deferred glass swap applied! is_glass_shattered=", is_glass_shattered)
			
			# Apply pending plank swap
			if _deferred_plank_swap:
				_deferred_plank_swap = false
				_update_plank_visuals()
				_update_nav_blocker()
				# Play break sound
				if _break_sound:
					_break_sound.play()
				elif _hammer_sound:
					_hammer_sound.play()
				print("[CabinWindow] Deferred plank swap applied! Barricade shattered.")


## Returns the global position of the IndoorBreachWayPoint marker.
## This is the landing position the Entity navigates to after breaking through
## the window barricade, placing it ~1.5 meters inside the room.
func get_indoor_landing_position() -> Vector3:
	if _indoor_breach_waypoint:
		return _indoor_breach_waypoint.global_position
	# Fallback: estimate a position 1.5m behind the window facing inward
	return global_position + global_transform.basis.z * 1.5


## Updates the visibility of Plank1, Plank2, Plank3 based on planks_remaining.
## Called after boarding up, taking damage, or shattering.
func _update_plank_visuals() -> void:
	if not is_boarded:
		# All planks hidden when not boarded
		if _plank_1: _plank_1.visible = false
		if _plank_2: _plank_2.visible = false
		if _plank_3: _plank_3.visible = false
		return
	
	# Plank1 visible if at least 1 plank remains
	if _plank_1:
		_plank_1.visible = planks_remaining >= 1
	
	# Plank2 visible if at least 2 planks remain
	if _plank_2:
		_plank_2.visible = planks_remaining >= 2
	
	# Plank3 visible if all 3 planks remain
	if _plank_3:
		_plank_3.visible = planks_remaining >= 3


## Updates the two-stage visual state (PristineVisuals vs ShatteredVisuals).
## Called when is_glass_shattered changes.
func _update_window_visuals() -> void:
	if _pristine_visuals:
		_pristine_visuals.visible = not is_glass_shattered
	if _shattered_visuals:
		_shattered_visuals.visible = is_glass_shattered


## Updates the navigation blocker based on BOTH glass AND plank state.
## The NavBlocker is disabled (open) ONLY when BOTH conditions are met:
##   - is_glass_shattered == true (glass is gone)
##   - is_boarded == false (planks are gone)
## This means the Entity cannot pathfind through until the full breach occurs.
func _update_nav_blocker() -> void:
	var is_open = is_glass_shattered and not is_boarded
	if _nav_blocker:
		# For StaticBody3D: disable the CollisionShape3D child node(s)
		if _nav_blocker is StaticBody3D:
			for child in _nav_blocker.get_children():
				if child is CollisionShape3D:
					child.disabled = is_open
		# For Area3D: use monitoring/monitorable
		elif _nav_blocker is Area3D:
			_nav_blocker.monitoring = is_open
			_nav_blocker.monitorable = is_open
		# Toggle collision layers as a secondary measure
		if _nav_blocker.has_method("set_collision_layer_value"):
			_nav_blocker.set_collision_layer_value(1, not is_open)
			_nav_blocker.set_collision_mask_value(1, not is_open)
		# Simple visibility toggle as fallback
		_nav_blocker.visible = not is_open


## Returns true if this window is secure against the Entity.
## A window is secure if:
##   - The room light is switched on (light sanctuary — Entity avoids it), OR
##   - The window is boarded up with planks (Entity must break through), OR
##   - The glass is still intact (Entity must shatter it first)
func is_secure() -> bool:
	# Light sanctuary: if the room light is on, the Entity cannot approach
	if room_light and room_light.is_switched_on:
		return true
	
	# Barricade: if boarded up, the window is secure until planks break
	if is_boarded:
		return true
	
	# Glass barrier: if glass is intact, the window is secure until shattered
	if not is_glass_shattered:
		return true
	
	return false


## Returns the type of security active on this window.
## Returns "light" if protected by room light, "planks" if boarded,
## "glass" if glass is intact, "" if unsecured.
func get_secure_type() -> String:
	if room_light and room_light.is_switched_on:
		return "light"
	if is_boarded:
		return "planks"
	if not is_glass_shattered:
		return "glass"
	return ""


## Called by the Entity AI to damage the barricade with a single hit.
## STRICTLY SEQUENTIAL TWO-PHASE EXECUTION:
##
##   Phase 1 (Glass Shatter — Outside Layer):
##     If glass is intact, shatter it FIRST. Interior planks are completely
##     ignored. Returns false to keep the Entity outside.
##
##   Phase 2 (Plank Siege — Inside Layer):
##     Glass is already shattered. If planks are present, each call applies
##     one hit. After HITS_PER_PLANK hits, one plank breaks. When all planks
##     are gone, the barricade is fully destroyed and returns true.
##
## CRITICAL: Phase 1 hard-returns before Phase 2 can execute. Planks are
## NEVER touched while glass is intact.
func damage_barricade() -> bool:
	# ─── DEBUG LOG: Track every damage call ─────────────────────────
	print("[Barricade Debug] damage_barricade() called. is_glass_shattered=", is_glass_shattered,
		  " | is_boarded=", is_boarded,
		  " | planks_remaining=", planks_remaining,
		  " | hits_on_current_plank=", hits_on_current_plank,
		  " | HITS_PER_PLANK=", HITS_PER_PLANK)
	
	# ===== PHASE 1: GLASS SHATTER (Outside Layer) =====
	# If the glass is still intact, the Entity smashes through it FIRST.
	# The interior planks are completely ignored during this phase.
	# Returns false to keep the Entity outside.
	if not is_glass_shattered:
		_shatter_glass()
		return false  # HARD RETURN. Entity stays outside. Planks untouched.
	
	# ===== PHASE 2: PLANK SIEGE (Inside Layer) =====
	# Glass is already shattered. If planks are present, apply one hit.
	if is_boarded:
		hits_on_current_plank += 1
		
		# Check if the current plank is fully broken
		if hits_on_current_plank >= HITS_PER_PLANK:
			planks_remaining -= 1
			hits_on_current_plank = 0
			
			# Update plank visuals to reflect new plank count
			_update_plank_visuals()
			
			if planks_remaining <= 0:
				_shatter_barricade()
				return true  # Full breach! Entity can enter.
		
		return false  # Still planks remaining, Entity stays outside
	
	# If glass is shattered and no planks, the opening is free
	elif is_glass_shattered:
		return true  # Already open, no barricade to damage
	
	return false


## Stage 1: Shatters the glass panes and crossbars permanently.
## Hides PristineVisuals, shows ShatteredVisuals, plays layered audio,
## bursts glass shard particles, and disables the navigation blocker.
##
## IMPORTANT: This function does NOT touch the interior planks. If the window
## was boarded up, the planks remain at full health behind the shattered frame.
## The NavBlocker stays enabled because planks still block the path.
func _shatter_glass() -> void:
	is_glass_shattered = true
	
	# Schedule a deferred visual swap (0.5s delay).
	# The visual swap (pristine → shattered), glass shard particles, layered
	# audio, and nav blocker update are all handled by _process() when the
	# timer expires. This syncs the visual change with the impact frame of
	# the AttackWindow animation, so the player sees the Entity's arm swing
	# through the glass before it shatters.
	_deferred_glass_swap = true
	_deferred_swap_timer = 0.5
	
	print("[CabinWindow] Glass shattered! Deferred swap scheduled (0.5s). is_glass_shattered=", is_glass_shattered)


## Stage 2: Destroys the plank barricade, plays a break sound, disables the
## NavBlocker, and resets state.
## Only called when glass is already shattered and planks are being broken.
func _shatter_barricade() -> void:
	is_boarded = false
	planks_remaining = 0
	hits_on_current_plank = 0
	
	# Schedule a deferred plank swap (0.3s delay).
	# The visual swap (hide all planks), nav blocker update, and break sound
	# are all handled by _process() when the timer expires. This syncs the
	# visual change with the impact frame of the AttackWindow animation.
	_deferred_plank_swap = true
	_deferred_swap_timer = 0.3
	
	print("[CabinWindow] Barricade shattered! Deferred plank swap scheduled (0.3s).")


## Player interaction: board up this window using a Wooden Plank from inventory.
## Consumes 1 plank item, sets is_boarded to true, restores plank_health to 100.
##
## IMPORTANT: If the glass has been shattered (is_glass_shattered = true),
## the core window remains permanently hollow. The planks cover the opening
## but the glass and crossbars are gone forever. ShatteredVisuals remains
## visible behind/between the planks.
func interact() -> void:
	# If already boarded, show a different message
	if is_boarded:
		print("[CabinWindow] Window is already boarded up.")
		return
	
	# Check if the player has a Wooden Plank in their inventory
	var inventory = get_node_or_null("/root/Inventory")
	if not inventory:
		print("[CabinWindow] Inventory not found!")
		return
	
	# Find a plank item in the inventory
	var plank_item = null
	for item in inventory.items:
		if item != null and item.item_type == ItemData.ItemType.PLANK:
			plank_item = item
			break
	
	if not plank_item:
		print("[CabinWindow] No Wooden Plank in inventory!")
		return
	
	# Consume one plank
	inventory.remove_item(plank_item)
	
	# Board up the window
	is_boarded = true
	planks_remaining = 3
	hits_on_current_plank = 0
	
	# NOTE: is_glass_shattered stays true if it was already shattered.
	# The core window remains hollow — planks just cover the opening.
	# _update_window_visuals() is NOT called — shattered state persists.
	
	# Show all three planks
	_update_plank_visuals()
	
	# Play hammer sound
	if _hammer_sound:
		_hammer_sound.play()
	
	print("[CabinWindow] Window boarded up! Planks: %d (glass_shattered: %s)" % [planks_remaining, str(is_glass_shattered)])


## Returns the interaction prompt text shown in the HUD.
func get_interact_text() -> String:
	if is_boarded:
		var total_hits = (planks_remaining * HITS_PER_PLANK) - hits_on_current_plank
		return "[E] Window - Boarded (Hits remaining: %d)" % total_hits
	
	# Check if the player has a plank
	var inventory = get_node_or_null("/root/Inventory")
	if inventory:
		for item in inventory.items:
			if item != null and item.item_type == ItemData.ItemType.PLANK:
				return "[E] Board up window"
	
	return "[E] Window - No planks available"
