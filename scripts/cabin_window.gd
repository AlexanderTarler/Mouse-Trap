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

## If true, this window is on the second floor (upstairs).
## Level designers should explicitly tag second-floor windows rather than
## relying on Y-coordinate math, which can be unreliable with varying
## terrain heights and foundation elevations.
## When true, the Entity (from Night 4) climbs the wall to cling outside it,
## peeks and breaks in from there (see CabinEntryLink.climb).
@export var is_upstairs_window: bool = false

## ─── TUTORIAL: Broken Window ────────────────────────────────────────────────
## If true, this window starts the game with shattered glass and no planks.
## Used for the Day 1 tutorial where the player must fix a drafty window.
## Set this to true on the Hall_Window node in the cabin scene.
@export var start_broken: bool = false

## Whether this window is currently boarded up with planks
var is_boarded: bool = false:
	set(value):
		is_boarded = value
		_update_entry_link()

## Navigation link from the WindowMarker (outside) to the indoor landing
## point. Enabled only while the window is passable (see is_passable()).
var _entry_link: CabinEntryLink = null

# ─── HOLD-TO-INTERACT: Plank Boarding ─────────────────────────────────────
## Whether the player is currently holding E to board this window.
## Set to true by start_hold_interact(), set to false by stop_hold_interact().
var _is_boarding: bool = false

## Accumulated hold progress (seconds) for boarding the current plank.
## Counts up from 0.0 to BOARD_PER_PLANK_TIME (4.0s), then one plank is added.
## Saved on release so the player can continue from where they left off.
var _boarding_progress: float = 0.0

## How long the player must hold E to add one plank to this window.
const BOARD_PER_PLANK_TIME: float = 4.0

## Seconds between hammer-blow noises while boarding (see NoiseEvent.emit).
const HAMMER_NOISE_INTERVAL: float = 1.0
var _hammer_noise_timer: float = 0.0

## Whether to show an extra visual plank while the player is holding E.
## Set to true when start_hold_interact() begins, set to false in
## stop_hold_interact() or when a plank finishes hammering.
## The _update_plank_visuals() function checks this to show the
## "pending" plank during the hold animation.
var _show_preview_plank: bool = false

## Whether the glass panes and crossbars have been shattered by the Entity.
## Once true, the glass is permanently destroyed and can never be restored.
## The player can still board up the opening with planks, but the glass is gone.
var is_glass_shattered: bool = false:
	set(value):
		is_glass_shattered = value
		_update_entry_link()

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

## Reference to the DoorBreachWaypoint Marker3D — positioned ~1.5m inside the room
## behind the window opening. The Entity navigates here after shattering the barricade.
## Found via the "DoorBreachWaypoint" group instead of a hardcoded node name.
@onready var _indoor_breach_waypoint: Marker3D = _find_door_breach_waypoint()

## Finds the DoorBreachWaypoint marker in this window's children via the group.
## Returns the Marker3D node, or null if not found.
func _find_door_breach_waypoint() -> Marker3D:
	var children = get_children()
	for child in children:
		if child is Marker3D and child.is_in_group("DoorBreachWaypoint"):
			return child
	return null

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


## Copies of the intact glass and crossbars (shattering frees them), so a
## checkpoint from before the break can put them back.
var _pristine_templates: Array[Node] = []


func _keep_pristine_templates() -> void:
	var pristine := get_node_or_null("PristineVisuals")
	if not pristine:
		return
	for child in pristine.get_children():
		_pristine_templates.append(child.duplicate())


## Checkpoint restored this window's state: rebuild what it looks like.
func _on_checkpoint_restored() -> void:
	var pristine := get_node_or_null("PristineVisuals")
	if pristine and not is_glass_shattered:
		# Only the pieces shattering freed (the glass pane, the crossbars).
		for template in _pristine_templates:
			if not pristine.has_node(NodePath(template.name)):
				var piece := template.duplicate()
				pristine.add_child(piece)
				piece.visible = true
	if is_instance_valid(_glass_shards) and "emitting" in _glass_shards:
		_glass_shards.emitting = false
	_update_window_visuals()
	_update_plank_visuals()
	_update_nav_blocker()
	_update_entry_link()


func _ready() -> void:
	_keep_pristine_templates()
	# Add to the WindowMarkers group so the Entity AI can find this window
	add_to_group("WindowMarkers")
	
	# ─── TUTORIAL: Broken Window Initial State ──────────────────────────
	# If this window is flagged as the tutorial broken window (start_broken),
	# check the NightManager's tutorial_window_fixed flag. If the window has
	# already been fixed in a previous session (persisted across scene reloads),
	# skip the broken initialization — the window stays boarded.
	#
	# If the window hasn't been fixed yet, set it to broken state:
	#   - is_glass_shattered = true (glass is gone)
	#   - is_boarded = false (no planks)
	#   - planks_remaining = 0 (no planks to break)
	#
	# This allows the tutorial window to persist its fixed state across
	# scene reloads (death → restart, save/load, etc.) via the NightManager
	# flag, while still starting broken on a fresh game.
	if start_broken:
		var nm = get_node_or_null("/root/NightManager")
		var already_fixed = nm and "tutorial_window_fixed" in nm and nm.tutorial_window_fixed
		if not already_fixed:
			is_glass_shattered = true
			is_boarded = false
			planks_remaining = 0
			
	
	# Initialize plank visibility based on initial state
	_update_plank_visuals()
	
	# Initialize window visual state (pristine shown, shattered hidden)
	_update_window_visuals()
	
	# Initialize navigation blocker state
	_update_nav_blocker()

	_create_entry_link()

	if OS.is_debug_build():
		# ─── DIAGNOSTIC VISIBILITY LOG ──────────────────────────────────
		# Logs the initial state of all visual child nodes at startup.
		# Only runs in debug builds to avoid console spam in production.
		# NOTE: Each diagnostic variable is explicitly typed to avoid Godot 4.6
		# static type warnings from ternary operators mixing Node3D and String.
		
		var diag_pristine: String = str(_pristine_visuals) if _pristine_visuals else "MISSING"
		
		var diag_shattered: String = str(_shattered_visuals) if _shattered_visuals else "MISSING"
		
		var diag_plank1: String = str(_plank_1) if _plank_1 else "MISSING"
		
		var diag_plank2: String = str(_plank_2) if _plank_2 else "MISSING"
		
		var diag_plank3: String = str(_plank_3) if _plank_3 else "MISSING"
		
		var diag_nav: String = str(_nav_blocker) if _nav_blocker else "MISSING"
		
		var diag_waypoint: String = str(_indoor_breach_waypoint) if _indoor_breach_waypoint else "MISSING"
		
		var diag_break: String = str(_break_sound) if _break_sound else "MISSING"
		
		var diag_hammer: String = str(_hammer_sound) if _hammer_sound else "MISSING"
		
		var diag_crunch: String = str(_glass_crunch_sound) if _glass_crunch_sound else "MISSING"
		
		var diag_shards: String = str(_glass_shards) if _glass_shards else "MISSING"
		
		


func _process(delta: float) -> void:
	# Tick down the deferred swap timer (used only by plank break, _shatter_barricade)
	if _deferred_swap_timer > 0.0:
		_deferred_swap_timer -= delta
		if _deferred_swap_timer <= 0.0:
			_deferred_swap_timer = 0.0
			
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
##
## PREVIEW PLANK: When the player holds E to board a plank, _show_preview_plank
## is true. This shows the NEXT plank (planks_remaining + 1) as a "pending"
## visual during the hold. If the player releases E, _show_preview_plank goes
## false and the preview plank is hidden. If the hold completes, the preview
## becomes a real plank via planks_remaining += 1.
func _update_plank_visuals() -> void:
	if not is_boarded and not _show_preview_plank:
		# All planks hidden when not boarded and no preview
		if _plank_1: _plank_1.visible = false
		if _plank_2: _plank_2.visible = false
		if _plank_3: _plank_3.visible = false
		return
	
	# Calculate effective plank count (including preview plank during hold)
	var effective_planks = planks_remaining
	if _show_preview_plank and _is_boarding and effective_planks < 3:
		effective_planks += 1
	
	# Plank1 visible if at least 1 effective plank
	if _plank_1:
		_plank_1.visible = effective_planks >= 1
	
	# Plank2 visible if at least 2 effective planks
	if _plank_2:
		_plank_2.visible = effective_planks >= 2
	
	# Plank3 visible if all 3 effective planks
	if _plank_3:
		_plank_3.visible = effective_planks >= 3


## Updates the two-stage visual state (PristineVisuals vs ShatteredVisuals).
## Called when is_glass_shattered changes.
func _update_window_visuals() -> void:
	if _pristine_visuals:
		_pristine_visuals.visible = not is_glass_shattered
	if _shattered_visuals:
		_shattered_visuals.visible = is_glass_shattered


## True when the Entity can climb through: the glass is gone and no planks
## remain. (Upstairs it has to climb the wall to get there, from Night 4.)
func is_passable() -> bool:
	return is_glass_shattered and not is_boarded


## Upstairs windows get a climbing link: from the ground below (WindowMarker)
## up the wall and in (see CabinEntryLink.climb).
func _create_entry_link() -> void:
	var outside := get_node_or_null("WindowMarker") as Node3D
	var inside := _indoor_breach_waypoint
	if not outside or not inside:
		push_warning("CabinWindow '%s': missing WindowMarker or IndoorBreachWaypoint; no navigation link created." % window_id)
		return
	_entry_link = CabinEntryLink.create(self, CabinEntryLink.Kind.WINDOW, outside, inside, is_passable())
	_entry_link.climb = is_upstairs_window


func _update_entry_link() -> void:
	if _entry_link:
		_entry_link.enabled = is_passable()


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


## Returns true if the player is currently allowed to board THIS window.
##
## TASK 3 STRICT PROGRESSION GATE: Boarding can ONLY begin when the
## RoutineManager explicitly flags windows as unlocked for boarding
## (windows_unlocked_for_boarding). This flag is set when the Day 1
## "Board up the broken window" objective begins (after the computer
## login) and stays true from Day 2 onward. If RoutineManager is missing,
## fall back to the old behavior (Night 1 = tutorial window only).
##
## DEV MODE BYPASS: When NightManager.is_dev_mode is true, the story lock
## is completely disabled — ALL windows are boardable on ANY day/night.
## This lets designers jump to Night 3+ (or any state) for testing without
## being barred by the Day 1 progression gate.
func _can_board_this_window() -> bool:
	var nm := get_node_or_null("/root/NightManager")
	if nm and "is_dev_mode" in nm and nm.is_dev_mode:
		return true
	var rm := get_node_or_null("/root/RoutineManager")
	if rm and "windows_unlocked_for_boarding" in rm:
		return rm.windows_unlocked_for_boarding
	# Fallback (no RoutineManager): tutorial window only on Day 1 / Night 1.
	if not nm:
		return true
	if int(nm.current_night) >= 2:
		return true
	return start_broken


## Returns true if this window is secure against the Entity.
## A window is secure if:
##   - The room light is lit (light sanctuary — Entity avoids it), OR
##   - The window is boarded up with planks (Entity must break through), OR
##   - The glass is still intact (Entity must shatter it first)
##
## NOTE: Uses is_room_lit() instead of is_switched_on so that a light that
## is switched on but has no generator power is NOT considered secure.
func is_secure() -> bool:
	# Light sanctuary: if the room light is actually lit, the Entity cannot approach
	if room_light and room_light.is_room_lit():
		return true
	
	# Barricade: if boarded up, the window is secure until planks break
	if is_boarded:
		return true
	
	# Glass barrier: if glass is intact, the window is secure until shattered
	if not is_glass_shattered:
		return true
	
	return false


# ─── HOLD-TO-INTERACT: Plank Boarding ─────────────────────────────────────
## Called by PhysicalGrab when the player presses E while looking at this window.
## Starts accumulating hold progress for boarding up the window.
## Works on ANY window regardless of glass state. The player can board up an
## intact window to reinforce it, or board a shattered window to seal the breach.
## Previously gated on is_glass_shattered which silently blocked non-tutorial
## windows (those without "Start Broken" enabled in the scene Inspector).
## Only the player's plank inventory limits boarding.
func start_hold_interact() -> void:
	# If already fully boarded, nothing to do
	if is_boarded and planks_remaining >= 3:
		return
	# ─── DAY 1 / NIGHT 1 BOARDING RESTRICTION ──────────────────────────
	# Only the tutorial window can be boarded during the first night cycle.
	if not _can_board_this_window():
		return
	# Check if player has planks in inventory
	if not _has_planks():
		return
	_is_boarding = true
	_show_preview_plank = true
	# If the window was completely unboarded, initialize boarding state
	if not is_boarded:
		is_boarded = true
		planks_remaining = 0
	
	# Show the preview plank immediately
	_update_plank_visuals()
	
	# ─── START LOOPING HAMMER SOUND ────────────────────────────────────
	# Play the hammer sound CONTINUOUSLY while the player holds E.
	# BUG 7 FIX: The stream is duplicated and set to loop=true so the
	# hammering sound keeps playing throughout the ENTIRE board-up hold
	# (previously it played once and ended before the last plank was
	# placed). The stop() call in stop_hold_interact() / _process_hold_interact()
	# ends the loop when the player releases E or the window is fully boarded.
	if _hammer_sound and _hammer_sound.stream:
		# Duplicate the stream so we don't mutate the shared resource,
		# then force looping so it sustains across the whole hold.
		var hammer_stream = _hammer_sound.stream.duplicate()
		if hammer_stream is AudioStreamOggVorbis:
			hammer_stream.loop = true
		elif "loop_mode" in hammer_stream and hammer_stream.has_method("set"):
			hammer_stream.loop_mode = 1  # AudioStreamWAV.LOOP_FORWARD
		_hammer_sound.stream = hammer_stream
		_hammer_sound.play()
	
	print("[Window Boarding] Start boarding at progress %.1f/%.1fs" % [_boarding_progress, BOARD_PER_PLANK_TIME])


## Called by PhysicalGrab when the player releases E.
## Saves the current progress so the player can continue from where they left off.
## Also hides the preview plank since the player stopped holding.
func stop_hold_interact() -> void:
	if not _is_boarding:
		return
	_is_boarding = false
	_show_preview_plank = false
	_update_plank_visuals()
	
	# ─── STOP LOOPING HAMMER SOUND (TASK 3.3: Fadeout to prevent pop) ──
	_fadeout_hammer_sound()
	
	print("[Window Boarding] Released at progress %.1f/%.1fs" % [_boarding_progress, BOARD_PER_PLANK_TIME])


## ─── TASK 3.3: HAMMER SOUND FADEOUT HELPER ─────────────────────────────
## Replaces all hard _hammer_sound.stop() calls. A hard stop() on a looping
## audio stream cuts the waveform mid-cycle, producing a distorted pop/buzz
## at the tail end. This helper tweens the volume to -80dB over 0.1 seconds,
## THEN calls stop() — eliminating the audio glitch while sounding nearly
## instantaneous to the player.
func _fadeout_hammer_sound() -> void:
	if not _hammer_sound or not _hammer_sound.playing:
		return
	# Kill any existing fade tween on this sound to avoid tween conflicts.
	if _hammer_sound.has_meta("fade_tween"):
		var old_tween: Tween = _hammer_sound.get_meta("fade_tween")
		if old_tween and old_tween.is_valid():
			old_tween.kill()
	var fade := create_tween()
	# Store the tween on the audio player so rapid start/stop cycles don't stack.
	_hammer_sound.set_meta("fade_tween", fade)
	fade.tween_property(_hammer_sound, "volume_db", -80.0, 0.1).set_trans(Tween.TRANS_LINEAR)
	fade.tween_callback(_hammer_sound.stop)
	# Restore the volume for the NEXT play() call — the player's volume_db
	# must be reset or the next boarding cycle starts inaudible.
	fade.tween_callback(func() -> void:
		if _hammer_sound:
			_hammer_sound.volume_db = 0.0
	)


## Called by PhysicalGrab every frame while E is held and the player is
## still looking at this window. Accumulates hold progress.
func _process_hold_interact(delta: float) -> void:
	if not _is_boarding:
		return
	
	_boarding_progress += delta
	# Every hammer blow is a noise the Entity may hear.
	_hammer_noise_timer += delta
	if _hammer_noise_timer >= HAMMER_NOISE_INTERVAL:
		_hammer_noise_timer = 0.0
		NoiseEvent.emit(self, global_position, &"hammer")
	
	# Clamp to avoid overshooting
	if _boarding_progress >= BOARD_PER_PLANK_TIME:
		# One plank added! Consume from inventory
		_boarding_progress = 0.0
		_show_preview_plank = false  # Preview plank becomes real
		
		# Try to consume a plank from inventory
		if _consume_plank_from_inventory():
			planks_remaining += 1
			_update_plank_visuals()
			_update_nav_blocker()
			print("[Window Boarding] Plank %d/3 installed!" % planks_remaining)
			
			# Check if fully boarded
			if planks_remaining >= 3:
				_is_boarding = false
				_boarding_progress = 0.0
				_show_preview_plank = false
				# ─── TASK 3.3: Fadeout instead of hard stop ──────────
				_fadeout_hammer_sound()
				print("[Window Boarding] Window fully boarded!")
				
				# ─── TUTORIAL: Mark boarding as learned ──────────────
				var tm := get_node_or_null("/root/TutorialManager")
				if tm and tm.has_method("mark_learned"):
					tm.mark_learned("board_window")
				
				# Notify RoutineManager
				var rm = get_node_or_null("/root/RoutineManager")
				if rm and rm.has_method("on_window_patched"):
					rm.on_window_patched()
			else:
				# More planks needed — check if player has another
				if not _has_planks():
					# No more planks — stop boarding immediately
					print("[Window Boarding] No more planks in inventory! Stopping.")
					_is_boarding = false
					_boarding_progress = 0.0
					_show_preview_plank = false
					_update_plank_visuals()
					# ─── TASK 3.3: Fadeout instead of hard stop ──────────
					_fadeout_hammer_sound()
				else:
					# Has more planks — show preview for the next one
					_show_preview_plank = true
					_update_plank_visuals()
		else:
			# No more planks in inventory — stop boarding
			print("[Window Boarding] No more planks in inventory!")
			_is_boarding = false


## Checks if the player has at least one Wooden Plank in inventory.
func _has_planks() -> bool:
	for item in Inventory.items:
		if item != null and "item_name" in item and item.item_name == "Wooden Plank":
			return true
	return false


## Removes one Wooden Plank from the player's inventory.
## Returns true if a plank was found and removed.
func _consume_plank_from_inventory() -> bool:
	for i in range(Inventory.items.size()):
		var item = Inventory.items[i]
		if item != null and "item_name" in item and item.item_name == "Wooden Plank":
			Inventory.remove_at(i)
			return true
	return false


## Override get_interact_text to show boarding progress.
func get_interact_text() -> String:
	if _is_boarding:
		var pct = int((_boarding_progress / BOARD_PER_PLANK_TIME) * 100.0)
		return "[E] Boarding... %d%%" % pct
	# ─── DAY 1 / NIGHT 1 GATE ──────────────────────────────────────────
	# While boarding is restricted to the tutorial window, non-tutorial
	# windows show a "not yet" message instead of the boarding prompt.
	if not _can_board_this_window():
		if is_boarded and planks_remaining >= 3:
			return "[E] Window (Secured)"
		return "[E] Can't board this window yet"
	# NOTE: No is_glass_shattered guard here — boarding works on ALL windows
	# regardless of glass state. The prompt should always show when the player
	# has planks, so they know they can board any window.
	if is_boarded and planks_remaining >= 3:
		return "[E] Window (Secured)"
	if not _has_planks():
		if planks_remaining > 0:
			return "[E] Board Window (%d/3) — No Planks" % planks_remaining
		return "[E] Board Window — No Planks"
	if planks_remaining > 0:
		return "[E] Board Window (%d/3) [Hold %.1fs]" % [planks_remaining, BOARD_PER_PLANK_TIME]
	return "[E] Board Window [Hold %.1fs]" % BOARD_PER_PLANK_TIME


## Returns the type of security active on this window.
## Returns "light" if protected by room light, "planks" if boarded,
## "glass" if glass is intact, "" if unsecured.
func get_secure_type() -> String:
	if room_light and room_light.is_room_lit():
		return "light"

	if is_boarded:
		return "planks"
	if not is_glass_shattered:
		return "glass"
	return ""


## Blows on the planks: a dull thud, and a wood crack when one gives way.
const PLANK_SFX_DIR := "res://assets/audio/Echoes - Audio Super Kit/OGG (recommended)/SFX/Misc/"
const PLANK_HIT_PATHS: Array[String] = [
	PLANK_SFX_DIR + "hit_1.ogg", PLANK_SFX_DIR + "hit_2.ogg", PLANK_SFX_DIR + "hit_5.ogg"]
const PLANK_CRACK_PATHS: Array[String] = [PLANK_SFX_DIR + "crack_1_wood.ogg", PLANK_SFX_DIR + "crack_2_wood.ogg"]
var _plank_sound: AudioStreamPlayer3D = null


func _play_plank_sound(broken: bool) -> void:
	if not _plank_sound:
		_plank_sound = AudioStreamPlayer3D.new()
		_plank_sound.name = "PlankHitSound"
		_plank_sound.bus = &"SFX"
		_plank_sound.unit_size = 4.0
		_plank_sound.max_distance = 35.0
		add_child(_plank_sound)
	var path: String = (PLANK_CRACK_PATHS if broken else PLANK_HIT_PATHS).pick_random()
	if not ResourceLoader.exists(path):
		return
	_plank_sound.stream = load(path)
	_plank_sound.pitch_scale = randf_range(0.8, 1.0)
	_plank_sound.play()


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
	print("[SHATTER DEBUG] damage_barricade() called on '%s' (id=%s). is_glass_shattered=%s is_boarded=%s" % [name, window_id, is_glass_shattered, is_boarded])
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
		_play_plank_sound(hits_on_current_plank >= HITS_PER_PLANK)
		
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


## Public API: Shatters the glass panes and crossbars permanently.
## This is the clean entry point called by the Entity AI after the
## AttackWindow animation reaches the impact frame.
##
## Hides PristineVisuals, shows ShatteredVisuals, plays layered audio,
## bursts glass shard particles, and disables the navigation blocker.
##
## IMPORTANT: This function does NOT touch the interior planks. If the window
## was boarded up, the planks remain at full health behind the shattered frame.
## The NavBlocker stays enabled because planks still block the path.
func shatter_window() -> void:
	print("[SHATTER DEBUG] shatter_window() called on '%s' (id=%s). is_glass_shattered=%s" % [name, window_id, is_glass_shattered])
	_shatter_glass()


## Stage 1: Shatters the glass panes and crossbars permanently.
## Hides PristineVisuals, shows ShatteredVisuals, plays layered audio,
## bursts glass shard particles, and disables the navigation blocker.
##
## IMPORTANT: This function does NOT touch the interior planks. If the window
## was boarded up, the planks remain at full health behind the shattered frame.
## The NavBlocker stays enabled because planks still block the path.
func _shatter_glass() -> void:
	is_glass_shattered = true
	print("[SHATTER DEBUG] _shatter_glass() called on window '%s' (id=%s). is_glass_shattered now true. PristineVisuals=%s" % [name, window_id, str(_pristine_visuals)])
	
	# ─── IMMEDIATE VISUAL SWAP ───────────────────────────────────────────
	# The visual swap (pristine → shattered), glass shard particles, layered
	# audio, and nav blocker update are applied IMMEDIATELY — no deferred
	# timer. The Entity's attack swing (EntitySwing) already provides the
	# animation sync (the AttackWindow animation plays for 0.5s before this
	# function is called). Adding another 0.5s deferred swap here would create
	# a double-delay, causing the Entity to phase through visible glass when
	# it teleports into the cabin via INDOOR_SEARCH Phase A.
	_update_window_visuals()

	# ─── EXPLICIT PRISTINE NODE DESTRUCTION ──────────────────────────────
	# Belt-and-suspenders: in addition to toggling the PristineVisuals parent
	# container above, explicitly hide/free the exact pristine visual nodes so
	# the glass and wooden cross are guaranteed to disappear even if the parent
	# container reference is stale or the container toggle is skipped.
	var _glass_pane = get_node_or_null("PristineVisuals/GlassPane")
	if _glass_pane:
		_glass_pane.visible = false
		_glass_pane.queue_free()
	var _wooden_cross = get_node_or_null("PristineVisuals/WoodenCross")
	if _wooden_cross:
		_wooden_cross.visible = false
		_wooden_cross.queue_free()

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
	
	# ─── BREACH DEBUG LOG ────────────────────────────────────────────────
	# Logs which window was broken, its window_id, and the visibility state
	# of PristineVisuals (should be false) and ShatteredVisuals (should be true).
	var pristine_visible: bool = _pristine_visuals.visible if _pristine_visuals else false
	var shattered_visible: bool = _shattered_visuals.visible if _shattered_visuals else false
	print("[CabinWindow] *** WINDOW BREACHED! window_id='%s' | is_glass_shattered=%s | PristineVisuals.visible=%s | ShatteredVisuals.visible=%s" % [
		window_id, is_glass_shattered, pristine_visible, shattered_visible
	])


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
	
	


## Player interaction: board up this window using a Wooden Plank from inventory.
## Consumes 1 plank item, sets is_boarded to true, restores plank_health to 100.
##
## IMPORTANT: If the glass has been shattered (is_glass_shattered = true),
## the core window remains permanently hollow. The planks cover the opening
## but the glass and crossbars are gone forever. ShatteredVisuals remains
## visible behind/between the planks.
func interact() -> void:
	# ─── TASK 3: INSTANT-PLANK EXPLOIT REMOVED ─────────────────────────
	# Legacy debug code previously consumed 1 plank and instantly set
	# is_boarded = true with planks_remaining = 3, bypassing the inventory
	# hold-to-interact pipeline AND the story unlock gate. Boarding now
	# goes strictly through start_hold_interact() → _process_hold_interact()
	# (4s per plank, one Wooden Plank deducted per stage, gated by
	# RoutineManager.windows_unlocked_for_boarding). This quick-tap entry
	# is intentionally a no-op.
	print("[Window Boarding] Quick-tap E ignored — hold E to board planks (Task 3 exploit lock).")
	
	


## NOTICE: get_interact_text() is now defined in the HOLD-TO-INTERACT section
## near is_secure(). The old version was removed to fix duplicate function error.
