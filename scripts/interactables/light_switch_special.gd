extends Area3D
class_name LightSwitchSpecial

## LightSwitchSpecial — Wall switch that toggles the high-voltage yard trap.
##
## A modified color variant of the standard light switch (pink/magenta glow)
## that specifically controls the deployed PortableLamp in the "portable_trap"
## group, rather than the cabin room lights.
##
## The switch has a physical ON/OFF state tracked by is_switch_on. When the
## player interacts with it, it toggles the state, plays a mechanical click
## sound, and calls toggle_power() on the deployed portable lamp.
##
## Safety guards:
##   - Does nothing if no lamp is deployed in the "portable_trap" group
##   - Does nothing if the lamp is not connected to the generator circuit
##   - Gracefully handles null references without errors

## Whether the switch is in the ON position.
var is_switch_on: bool = false

## Reference to the GlowLight child node for visual feedback.
@onready var _glow_light: OmniLight3D = $"../GlowLight"

## Local audio player for the mechanical toggle click sound.
@onready var _audio_player: AudioStreamPlayer3D = AudioStreamPlayer3D.new()


func _ready() -> void:
	collision_layer = 2

	# Add the local audio player so we can play the click sound
	# even if the generator is dead or HorrorSoundManager is unavailable.
	add_child(_audio_player)
	
	# Start with the glow light matching the switch state
	if _glow_light:
		_glow_light.visible = is_switch_on


## Returns the interaction prompt text shown in the HUD.
func get_interact_text() -> String:
	if is_switch_on:
		return "[E] Flip Switch OFF"
	else:
		return "[E] Flip Switch ON"


## Called by InteractionManager when the player quick-taps E while
## looking at this switch.
##
## 1. Toggles is_switch_on
## 2. Plays a mechanical click sound via HorrorSoundManager (with local fallback)
## 3. Finds the deployed PortableLamp in the "portable_trap" group
## 4. If the lamp is deployed and connected to the generator, calls
##    toggle_power(is_switch_on) to turn the light on/off
func interact() -> void:
	# 1. Toggle the switch state
	is_switch_on = not is_switch_on
	print("[LightSwitchSpecial] Switch flipped %s." % ("ON" if is_switch_on else "OFF"))
	
	# 2. Play mechanical toggle click sound
	_play_click_sound()
	
	# 3. Update the glow light visual
	if _glow_light:
		_glow_light.visible = is_switch_on
	
	# 4. Find the deployed portable trap
	var trap: Node = get_tree().get_first_node_in_group("portable_trap")
	
	# Safety guard: no trap deployed
	if not trap:
		print("[LightSwitchSpecial] No portable trap found in 'portable_trap' group.")
		return
	
	# Safety guard: trap not deployed on the ground
	if not trap.has_method("toggle_power"):
		print("[LightSwitchSpecial] Trap node missing toggle_power() method!")
		return
	
	# Delegate to the lamp's toggle_power() — it handles its own safety
	# checks (is_deployed, is_powered) internally.
	trap.toggle_power(is_switch_on)


## Plays a mechanical toggle click sound.
## First tries HorrorSoundManager for a global 2D sound, then falls back
## to the local AudioStreamPlayer3D if no stream is configured.
func _play_click_sound() -> void:
	# Try the global HorrorSoundManager first
	var hsm: Node = get_node_or_null("/root/HorrorSoundManager")
	if hsm and hsm.has_method("play_sound"):
		hsm.play_sound("switch_toggle", global_position)
		return
	
	# Fallback: play the local audio player if it has a stream
	if _audio_player.stream:
		_audio_player.play()
