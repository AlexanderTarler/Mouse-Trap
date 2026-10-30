extends Node
## GamepadInput (autoload): a gamepad as a way to play.
##
##   - Which device was used last (GameKeys.gamepad_active), so hints and
##     prompts say "[X]" or "[E]" to match.
##   - The sticks and buttons themselves are actions (GameKeys: the left
##     stick walks, the right stick looks, see PAD_BUTTONS / PAD_AXES).
##   - On the screens that want a mouse (the inventory, the notebook, the
##     computer, the phone, the stash), the right stick moves the cursor and
##     the right trigger clicks (A too, when nothing has focus). Menus with
##     focus work with the d-pad / left stick and A / B as Godot does.
## Typing (the computer's login and number fields) still takes a keyboard.

signal device_changed(gamepad: bool)

## The cursor's speed at full tilt (px/s in the 1920x1080 layout).
const CURSOR_SPEED := 900.0

var _click_down := false
## Mouse motion we made ourselves isn't a mouse being used.
var _synthetic_until := 0


func _ready() -> void:
	process_mode = PROCESS_MODE_ALWAYS
	if not GameKeys._applied:
		GameKeys.apply()
	# A pad plugged in already: it is the likely way to play.
	if not Input.get_connected_joypads().is_empty():
		GameKeys.pad_device = Input.get_connected_joypads()[0]


func _input(event: InputEvent) -> void:
	if event is InputEventJoypadButton and event.pressed:
		_use_pad(event.device)
	elif event is InputEventJoypadMotion and absf(event.axis_value) > 0.6:
		_use_pad(event.device)
	elif (event is InputEventKey and event.pressed) or (event is InputEventMouseButton and event.pressed):
		_use_keyboard_and_mouse()
	elif event is InputEventMouseMotion and Time.get_ticks_msec() > _synthetic_until and event.relative.length() > 2.0:
		_use_keyboard_and_mouse()


func _use_pad(device: int) -> void:
	GameKeys.pad_device = device
	if not GameKeys.gamepad_active:
		GameKeys.gamepad_active = true
		device_changed.emit(true)
		_focus_a_button.call_deferred()


## A pad picked up on a screen of buttons (the main menu, the death screen)
## with nothing selected: the top screen's first button is, so the d-pad has
## somewhere to start.
func _focus_a_button() -> void:
	var viewport := get_viewport()
	var scene := get_tree().current_scene
	if Input.mouse_mode != Input.MOUSE_MODE_VISIBLE or viewport.gui_get_focus_owner() != null or not scene:
		return
	var best: BaseButton = null
	var best_layer := -INF
	for node in scene.find_children("*", "BaseButton", true, false):
		var button := node as BaseButton
		if button.focus_mode == Control.FOCUS_NONE or button.disabled or not button.is_visible_in_tree():
			continue
		var layer := _layer_of(button)
		if layer > best_layer:
			best = button
			best_layer = layer
	if best:
		best.grab_focus()


func _layer_of(node: Node) -> float:
	var parent := node.get_parent()
	while parent:
		if parent is CanvasLayer:
			return float(parent.layer)
		parent = parent.get_parent()
	return 0.0


func _use_keyboard_and_mouse() -> void:
	if GameKeys.gamepad_active:
		GameKeys.gamepad_active = false
		device_changed.emit(false)


func _process(delta: float) -> void:
	var cursor_free := Input.mouse_mode == Input.MOUSE_MODE_VISIBLE and not Input.get_connected_joypads().is_empty()
	if not cursor_free:
		if _click_down:
			_click(false)
		return
	var viewport := get_viewport()
	var stick := Input.get_vector("look_left", "look_right", "look_up", "look_down")
	if stick != Vector2.ZERO:
		_use_pad(GameKeys.pad_device)
		stick *= stick.length()
		var rect := viewport.get_visible_rect()
		var at := (viewport.get_mouse_position() + stick * CURSOR_SPEED * delta).clamp(Vector2.ZERO, rect.size - Vector2.ONE)
		_synthetic_until = Time.get_ticks_msec() + 150
		viewport.warp_mouse(at)
		var motion := InputEventMouseMotion.new()
		motion.position = at
		motion.global_position = at
		motion.relative = stick * CURSOR_SPEED * delta
		Input.parse_input_event(motion)
	var down := Input.is_action_pressed("pad_click") \
		or (Input.is_joy_button_pressed(GameKeys.pad_device, JOY_BUTTON_A) and viewport.gui_get_focus_owner() == null)
	if down != _click_down:
		_click(down)


func _click(down: bool) -> void:
	_click_down = down
	var at := get_viewport().get_mouse_position()
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = down
	click.position = at
	click.global_position = at
	click.button_mask = MOUSE_BUTTON_MASK_LEFT if down else 0
	_synthetic_until = Time.get_ticks_msec() + 150
	Input.parse_input_event(click)
