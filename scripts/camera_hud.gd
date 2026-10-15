extends CanvasLayer
class_name CameraHUD

## CameraHUD — Retro digital camera viewfinder overlay for the Floppy Disk Camera.
##
## This HUD is shown/hidden by PhotoCamera when the player equips/unequips the camera.
## It provides:
##   - Green corner brackets (change color based on state)
##   - Battery indicator (top-left)
##   - Disk capacity counter (top-right)
##   - Aim status label (center)
##   - Mode label (bottom)
##   - A:\ drive write progress bar (bottom)
##   - Screen flash overlay
##   - Freeze-frame effect on photo capture

signal photo_captured()

## ─── CONSTANTS ───────────────────────────────────────────────────────────────

const TOTAL_NESTS: int = 3

## ─── EXPORTS ─────────────────────────────────────────────────────────────────

## Reference to the PhotoCamera node (set by PhotoCamera when enabling)
var photo_camera: Node = null

## ─── STATE ───────────────────────────────────────────────────────────────────

var is_active: bool = false
var documented_nests: Array[String] = []

## ─── NODE REFERENCES (resolved lazily in show_hud) ───────────────────────────
## These are NOT @onready — they are resolved on first access via _resolve_node_references().
## This avoids the Godot 4 lifecycle bug where _ready() doesn't fire fast enough
## when the scene is instantiated via code.

var bracket_tl: ColorRect = null
var bracket_tl_v: ColorRect = null
var bracket_tr: ColorRect = null
var bracket_tr_v: ColorRect = null
var bracket_bl: ColorRect = null
var bracket_bl_v: ColorRect = null
var bracket_br: ColorRect = null
var bracket_br_v: ColorRect = null

var batt_label: Label = null
var disk_label: Label = null
var aim_label: Label = null
var mode_label: Label = null

var progress_bar_bg: ColorRect = null
var progress_bar_fill: ColorRect = null
var progress_label: Label = null

var flash_overlay: ColorRect = null
var freeze_overlay: TextureRect = null

var all_brackets: Array[ColorRect] = []

## ─── COLORS ──────────────────────────────────────────────────────────────────

const COLOR_IDLE: Color = Color(0.0, 0.8, 0.2, 0.7)
const COLOR_ZOOMED: Color = Color(0.9, 0.8, 0.1, 0.8)
const COLOR_NEST_FOUND: Color = Color(0.0, 1.0, 0.3, 0.9)
const COLOR_ERROR: Color = Color(0.9, 0.1, 0.1, 0.8)
const COLOR_FLASH: Color = Color(0.8, 1.0, 0.8, 1.0)  # Retro digital green-tinted flash

## ─── LOW-LEVEL DRAW OVERRIDE ─────────────────────────────────────────────────
## Forces Godot's rendering engine to draw a solid, un-culled colored box.
## This bypasses any 2D/3D render pass culling that might be hiding the HUD.
## The red rectangle is drawn at the top-left corner of the screen.
## NOTE: CanvasLayer does NOT inherit from CanvasItem, so _draw() is placed
## on the Viewfinder Control child node instead (set up in show_hud()).

## Attaches a small inline script to the Viewfinder Control that overrides
## _draw() to render a solid red debug rectangle. This forces Godot's renderer
## to process this CanvasItem branch regardless of viewport culling.
func _attach_viewfinder_draw_override(viewfinder: Control) -> void:
	if not viewfinder:
		return
	# Create an inline GDScript that overrides _draw()
	var draw_script = GDScript.new()
	draw_script.source_code = """
extends Control

func _draw() -> void:
	draw_rect(Rect2(0, 0, 400, 400), Color(1, 0, 0, 1), true)
"""
	draw_script.reload()
	viewfinder.set_script(draw_script)
	viewfinder.queue_redraw()


## ─── INIT ────────────────────────────────────────────────────────────────────

func _ready() -> void:
	# Resolve nodes immediately so they're available even if show_hud() is called
	# before _ready() would normally fire (Godot 4 lifecycle quirk).
	_resolve_node_references()
	
	# ─── ENFORCE HIDDEN DEFAULT STATE ──────────────────────────────────────
	# The HUD must start completely invisible and asleep. Only photo_camera.gd's
	# equip() should wake it up via show_hud().
	visible = false
	is_active = false
	set_process(false)
	
	# Connect to viewport resize to reposition elements
	if get_viewport():
		get_viewport().size_changed.connect(_on_viewport_resized)


## Resolves all child node references using absolute paths from this node.
## Safe to call multiple times — only resolves if references are null.
func _resolve_node_references() -> void:
	if bracket_tl != null:
		return  # Already resolved
	
	bracket_tl = get_node_or_null("Viewfinder/BracketTL") as ColorRect
	bracket_tl_v = get_node_or_null("Viewfinder/BracketTL_V") as ColorRect
	bracket_tr = get_node_or_null("Viewfinder/BracketTR") as ColorRect
	bracket_tr_v = get_node_or_null("Viewfinder/BracketTR_V") as ColorRect
	bracket_bl = get_node_or_null("Viewfinder/BracketBL") as ColorRect
	bracket_bl_v = get_node_or_null("Viewfinder/BracketBL_V") as ColorRect
	bracket_br = get_node_or_null("Viewfinder/BracketBR") as ColorRect
	bracket_br_v = get_node_or_null("Viewfinder/BracketBR_V") as ColorRect
	
	batt_label = get_node_or_null("Viewfinder/BattLabel") as Label
	disk_label = get_node_or_null("Viewfinder/DiskLabel") as Label
	aim_label = get_node_or_null("Viewfinder/AimLabel") as Label
	mode_label = get_node_or_null("Viewfinder/ModeLabel") as Label
	
	progress_bar_bg = get_node_or_null("Viewfinder/ProgressBarBG") as ColorRect
	progress_bar_fill = get_node_or_null("Viewfinder/ProgressBarBG/ProgressBarFill") as ColorRect
	progress_label = get_node_or_null("Viewfinder/ProgressBarBG/ProgressLabel") as Label
	
	flash_overlay = get_node_or_null("FlashOverlay") as ColorRect
	freeze_overlay = get_node_or_null("FreezeOverlay") as TextureRect
	
	# ─── ENFORCE DEFAULT ALPHA SILENCING ON OVERLAYS ──────────────────────
	# Force all full-screen image overlay masks to be hidden or fully
	# transparent by default. Prevents solid white screen blocking the view.
	if flash_overlay:
		flash_overlay.visible = false
		flash_overlay.modulate.a = 0.0
	if freeze_overlay:
		freeze_overlay.visible = false
		freeze_overlay.modulate.a = 0.0
	
	# Build the brackets array
	all_brackets = []
	for b in [bracket_tl, bracket_tl_v, bracket_tr, bracket_tr_v,
			  bracket_bl, bracket_bl_v, bracket_br, bracket_br_v]:
		if b:
			all_brackets.append(b)
	
	# Log any missing nodes
	if all_brackets.size() < 8:
		print("[CameraHUD] Warning: Only found %d/8 bracket nodes." % all_brackets.size())
	if not batt_label:
		print("[CameraHUD] Warning: batt_label not found!")
	if not disk_label:
		print("[CameraHUD] Warning: disk_label not found!")
	if not aim_label:
		print("[CameraHUD] Warning: aim_label not found!")
	if not mode_label:
		print("[CameraHUD] Warning: mode_label not found!")
	if not progress_bar_bg:
		print("[CameraHUD] Warning: progress_bar_bg not found!")
	if not progress_bar_fill:
		print("[CameraHUD] Warning: progress_bar_fill not found!")
	if not progress_label:
		print("[CameraHUD] Warning: progress_label not found!")
	if not flash_overlay:
		print("[CameraHUD] Warning: flash_overlay not found!")
	if not freeze_overlay:
		print("[CameraHUD] Warning: freeze_overlay not found!")


## ─── ACTIVATION ──────────────────────────────────────────────────────────────

func show_hud() -> void:
	# Lazily resolve node references if _ready() didn't fire yet
	if not bracket_tl:
		_resolve_node_references()
	
	is_active = true
	
	# ─── OVERRIDE 1: Max rendering layer to guarantee topmost draw ────────
	# Layer 210 ensures the CameraHUD renders ABOVE the HorrorHUD (layer 200)
	# and its StandoffText (layer 210). This guarantees the freeze-frame
	# overlay and white flash are visible on top of all other UI elements.
	layer = 220
	
	# ─── OVERRIDE 1b: Force CanvasLayer rendering parameters ──────────────
	# Disable follow_viewport to prevent Godot from culling this layer
	# based on viewport visibility bounds.
	follow_viewport_enabled = false
	
	# ─── OVERRIDE 2: Force full-screen size using DisplayServer API ────────
	# The canvas size (the UI is scaled from 1920x1080 to the window).
	var real_screen_size = get_viewport().get_visible_rect().size
	
	var viewfinder = get_node_or_null("Viewfinder") as Control
	if viewfinder:
		viewfinder.anchors_preset = Control.PRESET_FULL_RECT
		viewfinder.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 0)
		viewfinder.grow_horizontal = Control.GROW_DIRECTION_BOTH
		viewfinder.grow_vertical = Control.GROW_DIRECTION_BOTH
		viewfinder.custom_minimum_size = real_screen_size
		viewfinder.size = real_screen_size
	
	# ─── OVERRIDE 3: Force visibility cascade on ALL child nodes ─────────
	visible = true
	set_process(true)
	_reset_state()
	_on_viewport_resized()
	
	# Force every visual child to be visible
	for child in get_children():
		if child is CanvasItem:
			child.visible = true
		# Also force grandchildren inside Viewfinder
		if child.has_method("get_children"):
			for grandchild in child.get_children():
				if grandchild is CanvasItem:
					grandchild.visible = true
	
	# ─── ABSOLUTE SIZE & ALPHA RESET FOR ALL BRACKETS ────────────────────
	var bracket_defs = [
		[bracket_tl, Vector2(40, 3)],
		[bracket_tl_v, Vector2(3, 40)],
		[bracket_tr, Vector2(40, 3)],
		[bracket_tr_v, Vector2(3, 40)],
		[bracket_bl, Vector2(40, 3)],
		[bracket_bl_v, Vector2(3, 40)],
		[bracket_br, Vector2(40, 3)],
		[bracket_br_v, Vector2(3, 40)]
	]
	for pair in bracket_defs:
		var b = pair[0] as ColorRect
		var sz = pair[1] as Vector2
		if b:
			b.custom_minimum_size = sz
			b.size = sz
			b.color.a = 0.7
			b.modulate = Color(1, 1, 1, 1)
	
	# ─── ABSOLUTE SIZE & ALPHA RESET FOR LABELS ──────────────────────────
	if batt_label:
		batt_label.size = Vector2(100, 16)
		batt_label.modulate = Color(1, 1, 1, 1)
	if disk_label:
		disk_label.size = Vector2(200, 16)
		disk_label.modulate = Color(1, 1, 1, 1)
	if aim_label:
		aim_label.size = Vector2(200, 20)
		aim_label.modulate = Color(1, 1, 1, 1)
	if mode_label:
		mode_label.size = Vector2(200, 24)
		mode_label.modulate = Color(1, 1, 1, 1)
	
	# ─── ABSOLUTE SIZE & ALPHA SILENCING FOR OVERLAYS ────────────────────
	# Set the size to full-screen, but keep them hidden and fully transparent
	# so they don't block the view. They are only shown briefly during
	# trigger_flash() and trigger_freeze_frame().
	if flash_overlay:
		flash_overlay.custom_minimum_size = real_screen_size
		flash_overlay.size = real_screen_size
		flash_overlay.visible = false
		flash_overlay.modulate.a = 0.0
	if freeze_overlay:
		freeze_overlay.custom_minimum_size = real_screen_size
		freeze_overlay.size = real_screen_size
		freeze_overlay.visible = false
		freeze_overlay.modulate.a = 0.0
	
	# ─── ATTACH LOW-LEVEL DRAW OVERRIDE ──────────────────────────────────
	# Forces Godot's renderer to process this CanvasItem branch regardless
	# of viewport culling by drawing a solid red debug rectangle.
	_attach_viewfinder_draw_override(viewfinder)
	
	# Force queue_redraw() to fire the _draw() function immediately
	if viewfinder:
		viewfinder.queue_redraw()
	
	# ─── REPOSITION ALL ELEMENTS USING CANVASLAYER SIZE ──────────────────
	_reposition_hud_elements()

func hide_hud() -> void:
	is_active = false
	visible = false
	set_process(false)
	if flash_overlay:
		flash_overlay.visible = false
	if freeze_overlay:
		freeze_overlay.visible = false
	if progress_bar_bg:
		progress_bar_bg.visible = false


func _reset_state() -> void:
	set_bracket_color(COLOR_IDLE)
	
	if batt_label:
		batt_label.text = "BATT: OK"
	if disk_label:
		disk_label.text = "DISK CAPACITY: %d / 4" % documented_nests.size()
	if aim_label:
		aim_label.text = ""
	if mode_label:
		mode_label.text = "PHOTO MODE - [R] to exit"
	
	if progress_bar_bg:
		progress_bar_bg.visible = false
	if flash_overlay:
		flash_overlay.visible = false
	if freeze_overlay:
		freeze_overlay.visible = false


## ─── VIEWPORT RESIZE ─────────────────────────────────────────────────────────

func _on_viewport_resized() -> void:
	if not is_active or not is_inside_tree():
		return
	
	var vp_size = get_viewport().get_visible_rect().size
	
	# Reposition corner brackets
	if bracket_tr:
		bracket_tr.position = Vector2(vp_size.x - bracket_tr.size.x - 20, 20)
	if bracket_tr_v:
		bracket_tr_v.position = Vector2(vp_size.x - bracket_tr_v.size.x - 20, 20)
	
	if bracket_bl:
		bracket_bl.position = Vector2(20, vp_size.y - bracket_bl.size.y - 20)
	if bracket_bl_v:
		bracket_bl_v.position = Vector2(20, vp_size.y - bracket_bl_v.size.y - 20 - 40 + 3)
	
	if bracket_br:
		bracket_br.position = Vector2(vp_size.x - bracket_br.size.x - 20, vp_size.y - bracket_br.size.y - 20)
	if bracket_br_v:
		bracket_br_v.position = Vector2(vp_size.x - bracket_br_v.size.x - 20, vp_size.y - bracket_br_v.size.y - 20 - 40 + 3)
	
	# Center mode label at bottom
	if mode_label:
		mode_label.position = Vector2(vp_size.x / 2.0 - mode_label.size.x / 2.0, vp_size.y - 60)
	
	# Center aim label
	if aim_label:
		aim_label.position = Vector2(vp_size.x / 2.0 - aim_label.size.x / 2.0, vp_size.y / 2.0 - 40)
	
	# Position disk label at top-right
	if disk_label:
		disk_label.position = Vector2(vp_size.x - disk_label.size.x - 12, 12)
	
	# Center progress bar at bottom
	if progress_bar_bg:
		progress_bar_bg.position = Vector2(vp_size.x / 2.0 - progress_bar_bg.size.x / 2.0, vp_size.y - 90)


## ─── RESPONSIVE LAYOUT ───────────────────────────────────────────────────────
## Completely bypasses broken scene anchor presets by manually calculating
## every element's position based on the CanvasLayer's actual size.
## Called at the end of show_hud() and on viewport resize.

func _reposition_hud_elements() -> void:
	# Use the Viewfinder's size (which was forced to real_screen_size in show_hud)
	var viewfinder = get_node_or_null("Viewfinder") as Control
	var w: float = viewfinder.size.x if viewfinder else get_viewport().get_visible_rect().size.x
	var h: float = viewfinder.size.y if viewfinder else get_viewport().get_visible_rect().size.y
	
	# Top Left Group (keep near 20, 20)
	# bracket_tl and bracket_tl_v stay at their scene defaults (20, 20)
	
	# Top Right Group (move to right edge)
	if bracket_tr:
		bracket_tr.position = Vector2(w - 60, 20)
	if bracket_tr_v:
		bracket_tr_v.position = Vector2(w - 23, 20)
	if disk_label:
		disk_label.position = Vector2(w - 220, 12)
	
	# Bottom Left Group (move down)
	if bracket_bl:
		bracket_bl.position = Vector2(20, h - 23)
	if bracket_bl_v:
		bracket_bl_v.position = Vector2(20, h - 60)
	
	# Bottom Right Group (move right and down)
	if bracket_br:
		bracket_br.position = Vector2(w - 60, h - 23)
	if bracket_br_v:
		bracket_br_v.position = Vector2(w - 23, h - 60)
	
	# Center Layout Group
	if aim_label:
		aim_label.position = Vector2((w / 2.0) - 100, (h / 2.0) - 11)
	
	# Bottom Information Labels & Progress Bars
	if mode_label:
		mode_label.position = Vector2((w / 2.0) - 100, h - 80)
	if progress_bar_bg:
		progress_bar_bg.position = Vector2((w / 2.0) - 150, h - 45)


## ─── BRACKET COLORS ──────────────────────────────────────────────────────────

func set_bracket_color(color: Color) -> void:
	for bracket in all_brackets:
		if bracket:
			bracket.color = color


## ─── AIM DETECTION ───────────────────────────────────────────────────────────

func update_aim_status(text: String, color: Color) -> void:
	if aim_label:
		aim_label.text = text
		aim_label.add_theme_color_override("font_color", color)


func update_disk_count(count: int) -> void:
	if disk_label:
		disk_label.text = "DISK CAPACITY: %d / 4" % count


## ─── MODE LABEL ──────────────────────────────────────────────────────────────

func set_mode_text(text: String) -> void:
	if mode_label:
		mode_label.text = text


## ─── WRITE PROGRESS BAR ──────────────────────────────────────────────────────

func show_write_progress(progress: float, message: String) -> void:
	if progress_bar_bg:
		progress_bar_bg.visible = true
	if progress_bar_fill and progress_bar_bg:
		progress_bar_fill.size.x = progress_bar_bg.size.x * progress
	if progress_label:
		progress_label.text = message


func hide_write_progress() -> void:
	if progress_bar_bg:
		progress_bar_bg.visible = false


## ─── SCREEN FLASH ────────────────────────────────────────────────────────────
## Retro digital green-tinted flash. Fades out over 0.1s with a sharp easing curve.

func trigger_flash() -> void:
	if not flash_overlay:
		return
	flash_overlay.visible = true
	flash_overlay.color = COLOR_FLASH
	# Fade out over 0.1 seconds with sharp ease-out
	var tween = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tween.tween_property(flash_overlay, "modulate:a", 0.0, 0.1)
	tween.finished.connect(func():
		if flash_overlay:
			flash_overlay.visible = false
			flash_overlay.modulate.a = 1.0
	)


## ─── FREEZE FRAME EFFECT ─────────────────────────────────────────────────────
## Captures the current viewport as a frozen image, shows it for 0.5 seconds,
## then fades it out over 0.2 seconds to reveal the live view.
##
## Also triggers a blinding white flash overlay that snaps to full alpha
## instantly, then fades out over 0.15 seconds for a classic retro horror
## camera bulb flash feel.

func trigger_freeze_frame() -> void:
	if not freeze_overlay:
		return
	
	# Capture the current viewport as an image
	var viewport = get_viewport()
	if not viewport:
		return
	var image = viewport.get_texture().get_image()
	
	# Create a texture from the captured image
	var texture = ImageTexture.create_from_image(image)
	
	# Apply it to the freeze overlay
	freeze_overlay.texture = texture
	freeze_overlay.visible = true
	freeze_overlay.modulate.a = 1.0
	
	# ─── BLINDING WHITE FLASH (DOUBLED INTENSITY) ──────────────────────────
	# Snap the flash overlay to pure solid white instantly, then hold it for
	# 0.2 seconds before fading out over 0.3 seconds. This creates a much
	# more impactful, classic horror camera bulb flash that lingers longer.
	if flash_overlay:
		flash_overlay.color = Color(1, 1, 1, 1.0)  # Pure white
		flash_overlay.visible = true
		flash_overlay.modulate.a = 1.0
		var flash_tween = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
		flash_tween.tween_interval(0.2)  # Hold full white for 0.2s
		flash_tween.tween_property(flash_overlay, "modulate:a", 0.0, 0.3)  # Fade over 0.3s
		flash_tween.finished.connect(func():
			if flash_overlay:
				flash_overlay.visible = false
				flash_overlay.modulate.a = 1.0
		)
	
	# ─── FREEZE FRAME TIMING ───────────────────────────────────────────────
	# 1. Hold the frozen image for 0.5 seconds (player is frozen during this).
	# 2. After the hold, emit photo_captured immediately so PhotoCamera
	#    unfreezes the player while the freeze frame fades out over 0.5s.
	#    This means the player can start moving while the frozen image is
	#    still fading away, creating a smooth transition.
	var tween = create_tween()
	tween.tween_interval(0.5)
	tween.tween_callback(func():
		# Signal PhotoCamera to unfreeze player controls NOW
		photo_captured.emit()
	)
	tween.tween_property(freeze_overlay, "modulate:a", 0.0, 0.5)
	tween.finished.connect(func():
		if freeze_overlay:
			freeze_overlay.visible = false
			freeze_overlay.modulate.a = 1.0
	)


## ─── ERROR FLASH ─────────────────────────────────────────────────────────────

func trigger_error_flash() -> void:
	set_bracket_color(COLOR_ERROR)
	# Wait 0.3 seconds, then restore
	var tween = create_tween()
	tween.tween_interval(0.3)
	tween.finished.connect(func():
		set_bracket_color(COLOR_ZOOMED)
	)


## ─── PROCESS ─────────────────────────────────────────────────────────────────

func _process(delta: float) -> void:
	# Update disk label periodically
	if disk_label:
		disk_label.text = "DISK CAPACITY: %d / 4" % documented_nests.size()
