extends Area3D
class_name LightSwitchTrigger

@export var target_light: Node3D = null
@export var switch_click_sound: AudioStream = null

@onready var _audio_player: AudioStreamPlayer3D = AudioStreamPlayer3D.new()

func _ready() -> void:
	collision_layer = 2

	# Ensure we can play a local mechanical "click" sound even if the generator is dead
	add_child(_audio_player)
	if switch_click_sound:
		_audio_player.stream = switch_click_sound

func interact() -> void:
	print("[Switch] Interacted with mechanical toggle.")

	# 1. Play local audio feedback
	if _audio_player.stream:
		_audio_player.play()

	# 2. Fire the grid toggle command
	if target_light and target_light.has_method("toggle_light"):
		target_light.toggle_light()
	else:
		print("[Warning] LightSwitchTrigger has no assigned or valid CabinLight target!")
