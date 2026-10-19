class_name CreditsScreen
extends Control
## The credits, from the main menu: who made the game and the assets it uses.
## Edit TEXT below (BBCode). Lines marked [TODO] still need the pack's author
## and licence checked against the licence that came with it.

const TEXT := """[center][font_size=34]Mouse Trap[/font_size]

A game by Alexander Tarler
Made with Godot Engine (godotengine.org)

[color=#e6d9b8]3D MODELS[/color]
PSX Nature, PSX Mega Pack, PSX Mega Pack II, PSX Interior, PSX Bunkers,
PSX Kidnapper's Van, PSX Traps, PSX Paintings, PSX Tech, PSX-Electrical  [TODO: authors, licences]
PSX Forest Meadows by VadaCross  [TODO: licence]
PSX Rural Environment Pack  [TODO: author, licence]
Three Cabins, Car 01, Car 06  [TODO: authors, licences]

[color=#e6d9b8]ANIMATION[/color]
Universal Animation Library by Quaternius (CC0)
Mixamo (Adobe)

[color=#e6d9b8]SOUND[/color]
Echoes - Audio Super Kit  [TODO: author, licence]
Horror SFX Vol. 1  [TODO: author, licence]
40 Free PSX Footsteps  [TODO: author, licence]

[color=#e6d9b8]FONTS[/color]
Courier Prime by Alan Dague-Greene (SIL Open Font License 1.1)
Special Elite by Astigmatic (Apache License 2.0)

[color=#e6d9b8]TERRAIN[/color]
TerraBrush  [TODO: author, licence]

Thank you for playing.[/center]"""


func _ready() -> void:
	process_mode = PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.85)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(shade)
	var column := VBoxContainer.new()
	column.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	column.grow_horizontal = Control.GROW_DIRECTION_BOTH
	column.grow_vertical = Control.GROW_DIRECTION_BOTH
	column.custom_minimum_size = Vector2(900, 640)
	column.add_theme_constant_override("separation", 14)
	add_child(column)
	var text := RichTextLabel.new()
	text.name = "CreditsText"
	text.bbcode_enabled = true
	text.text = TEXT
	text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	text.add_theme_font_size_override("normal_font_size", 18)
	column.add_child(text)
	var back := Button.new()
	back.name = "BackButton"
	back.text = "Back"
	back.custom_minimum_size = Vector2(160, 40)
	back.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	back.pressed.connect(queue_free)
	column.add_child(back)
	back.grab_focus.call_deferred()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause_menu") or event.is_action_pressed("ui_cancel"):
		queue_free()
		get_viewport().set_input_as_handled()
