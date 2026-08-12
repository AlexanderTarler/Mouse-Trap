extends Control
class_name OptionsMenu

## OptionsMenu — In-game / main-menu audio settings panel.
##
## Provides sliders for every AudioServer bus. The menu runs with
## PROCESS_MODE_ALWAYS so it works while the game is paused.

## Maps internal bus names to user-friendly display names.
const DISPLAY_NAMES: Dictionary = {
	"Master": "Master Volume",
	"SFX": "Sound Effects",
	"Music": "Music",
	"Ambient": "Ambient",
	"Voice": "Voice / Dialogue",
	"UI": "UI Sounds",
}

@onready var _slider_container: VBoxContainer = %SliderContainer
@onready var _back_button: Button = %BackButton
@onready var _highlight_toggle: CheckButton = $PanelContainer/VBoxContainer/ObjectiveHighlightsToggle

var _bus_sliders: Dictionary = {}


func _ready() -> void:
	process_mode = PROCESS_MODE_ALWAYS
	visible = false
	
	if _back_button:
		_back_button.pressed.connect(_on_back_pressed)
	
	# ─── TASK 5: OBJECTIVE HIGHLIGHT TOGGLE ─────────────────────────
	# Wire the CheckButton to RoutineManager.enable_object_highlights.
	# Since RoutineManager is a static var, we can reference it directly.
	if _highlight_toggle:
		# Sync the button state with the current setting on boot.
		_highlight_toggle.button_pressed = RoutineManager.enable_object_highlights
		_highlight_toggle.toggled.connect(_on_highlight_toggle_changed)
	
	_build_sliders()
func _on_highlight_toggle_changed(pressed: bool) -> void:
	RoutineManager.enable_object_highlights = pressed
	print("[OptionsMenu] Objective highlights %s." % ("ENABLED" if pressed else "DISABLED"))


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	
	if event.is_action_pressed("pause_menu"):
		hide_menu()
		get_viewport().set_input_as_handled()
		return
	
	# Consume all action events while the menu is open so the player
	# cannot jump, interact, or move via input while configuring options.
	# Uses _unhandled_input so UI controls (like sliders) get priority over
	# this catch-all consumer.
	if event.is_action_type():
		get_viewport().set_input_as_handled()


## Builds a slider row for each existing AudioServer bus.
func _build_sliders() -> void:
	if not _slider_container:
		return
	
	# Clear existing children (useful if rebuilt)
	for child in _slider_container.get_children():
		child.queue_free()
	_bus_sliders.clear()
	
	for i in AudioServer.bus_count:
		var bus_name := AudioServer.get_bus_name(i)
		if bus_name == "Entity":
			continue
		var slider := HSlider.new()
		
		slider.name = bus_name + "Slider"
		slider.min_value = 0.0
		slider.max_value = 1.0
		slider.step = 0.05
		slider.value = db_to_linear(AudioServer.get_bus_volume_db(i))
		slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		
		# Label the slider with the bus name and current percentage
		var label := Label.new()
		label.name = bus_name + "Label"
		label.text = _format_bus_label(bus_name, slider.value)
		label.theme_type_variation = "HeaderSmall"
		
		var row := HBoxContainer.new()
		row.name = bus_name + "Row"
		row.add_child(label)
		row.add_child(slider)
		_slider_container.add_child(row)
		
		# Update label text when the slider changes
		slider.value_changed.connect(_on_slider_value_changed.bind(i, label))
		_bus_sliders[bus_name] = slider


func _get_display_name(bus_name: String) -> String:
	return DISPLAY_NAMES.get(bus_name, bus_name)


func _format_bus_label(bus_name: String, linear: float) -> String:
	return "%s: %d%%" % [_get_display_name(bus_name), int(linear * 100.0)]


func _on_slider_value_changed(linear: float, bus_index: int, label: Label) -> void:
	AudioServer.set_bus_volume_db(bus_index, linear_to_db(linear))
	_sync_entity_to_sfx(bus_index, linear)
	label.text = _format_bus_label(AudioServer.get_bus_name(bus_index), linear)


func _on_back_pressed() -> void:
	hide_menu()


## Shows the options menu and refreshes sliders to match current bus volumes.
func show_menu() -> void:
	_refresh_slider_values()
	visible = true
	if _back_button:
		_back_button.grab_focus()


## Hides the options menu.
func hide_menu() -> void:
	visible = false


## Ensures the Entity bus volume always matches the SFX bus volume.
## Called on boot (via _refresh_slider_values) and on every SFX slider change.
func _sync_entity_to_sfx(sfx_bus_index: int, linear: float) -> void:
	var sfx_bus_name := AudioServer.get_bus_name(sfx_bus_index)
	if sfx_bus_name != "SFX":
		return
	var entity_index := AudioServer.get_bus_index("Entity")
	if entity_index == -1:
		return
	AudioServer.set_bus_volume_db(entity_index, linear_to_db(linear))

## Refreshes slider values without rebuilding the whole UI.
func _refresh_slider_values() -> void:
	for i in AudioServer.bus_count:
		var bus_name := AudioServer.get_bus_name(i)
		var slider: HSlider = _bus_sliders.get(bus_name, null) as HSlider
		if slider:
			slider.set_block_signals(true)
			slider.value = db_to_linear(AudioServer.get_bus_volume_db(i))
			slider.set_block_signals(false)
			var row := slider.get_parent() as HBoxContainer
			if row:
				var label := row.get_node_or_null(bus_name + "Label") as Label
				if label:
					label.text = _format_bus_label(bus_name, slider.value)
	
	# Boot-time sync: replicate SFX volume onto the Entity bus
	var sfx_index := AudioServer.get_bus_index("SFX")
	if sfx_index >= 0:
		_sync_entity_to_sfx(sfx_index, db_to_linear(AudioServer.get_bus_volume_db(sfx_index)))
