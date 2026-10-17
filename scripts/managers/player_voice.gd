class_name PlayerVoice
extends Node
## The microphone (Options > Microphone, off by default). With it on, the
## game listens for the player: a gasp, a yelp, a "what was that?" carries
## like a dropped thing (NoiseEvent "voice", louder: "voice_loud"), and the
## Entity hears it. Quiet talk and room noise stay under the threshold
## (Options > Mic Sensitivity, with a level meter there to set it).
##
## It keeps only the last KEEP_SECONDS of sound, in memory: when the player
## was loud, that moment is kept as `loud_clip` (never saved, never sent);
## the Entity may play it back once a night, from another room, slightly off
## (EntityAudio.mimic "voice").
##
## Without a microphone (none there, permission refused, the web without
## https) nothing comes in and nothing happens.
##
##   meter_only: for the options menu's level meter (no noises, no clips).

const SETTING := "audio/microphone"
const THRESHOLD_SETTING := "audio/mic_threshold_db"
const BUS := "PlayerVoice"
const KEEP_SECONDS := 2.0
## Seconds more kept after a loud moment (the end of the gasp).
const TAIL := 0.5
## At most one noise this often (s).
const NOISE_GAP := 0.6
## This many dB over the threshold is "loud" (carries further).
const LOUD_OVER := 10.0

var meter_only := false
## The input level now (dB, the peak, falling back slowly): for the meter.
var level_db := -80.0
var loud_clip: AudioStreamWAV = null
## How many times it has been loud enough to be heard (for the tests).
var heard := 0
var _mic: AudioStreamPlayer = null
var _capture: AudioEffectCapture = null
var _ring := PackedVector2Array()
var _cooldown := 0.0
var _tail_left := -1.0
var _check := 0.0


static func enabled() -> bool:
	return bool(GameSettings.get_value(SETTING))


static func threshold_db() -> float:
	return float(GameSettings.get_value(THRESHOLD_SETTING))


func is_listening() -> bool:
	return _mic != null and _mic.playing


func _process(delta: float) -> void:
	_check -= delta
	if _check <= 0.0:
		_check = 1.0
		if enabled() and not is_listening():
			_start()
		elif not enabled() and _mic:
			_stop()
	if not is_listening() or _capture == null:
		level_db = -80.0
		return
	var frames := _capture.get_frames_available()
	var peak := 0.0
	if frames > 0:
		var buffer := _capture.get_buffer(frames)
		for frame in buffer:
			peak = maxf(peak, maxf(absf(frame.x), absf(frame.y)))
		if not meter_only:
			_ring.append_array(buffer)
			var keep := int(KEEP_SECONDS * AudioServer.get_mix_rate())
			if _ring.size() > keep:
				_ring = _ring.slice(_ring.size() - keep)
	var db := linear_to_db(maxf(peak, 0.00001))
	level_db = maxf(db, level_db - 40.0 * delta)
	if meter_only:
		return
	_cooldown -= delta
	if db > threshold_db() and _cooldown <= 0.0:
		_cooldown = NOISE_GAP
		voice(db)
	if _tail_left > 0.0:
		_tail_left -= delta
		if _tail_left <= 0.0:
			loud_clip = _clip()


## The player was loud (`db`): a noise where they are, and the moment kept.
func voice(db: float) -> void:
	heard += 1
	var player := get_tree().get_first_node_in_group("player") as Node3D
	if player:
		NoiseEvent.emit(player, player.global_position, &"voice_loud" if db > threshold_db() + LOUD_OVER else &"voice")
	_tail_left = TAIL


func _start() -> void:
	var bus := AudioServer.get_bus_index(BUS)
	if bus < 0:
		bus = AudioServer.bus_count
		AudioServer.add_bus(bus)
		AudioServer.set_bus_name(bus, BUS)
		AudioServer.add_bus_effect(bus, AudioEffectCapture.new())
		# Heard by the game, never played back.
		AudioServer.set_bus_volume_db(bus, -80.0)
	_capture = AudioServer.get_bus_effect(bus, 0) as AudioEffectCapture
	_mic = AudioStreamPlayer.new()
	_mic.name = "Microphone"
	_mic.stream = AudioStreamMicrophone.new()
	_mic.bus = BUS
	add_child(_mic)
	_mic.play()
	print("[PlayerVoice] Listening (threshold %.0f dB)." % threshold_db())


func _stop() -> void:
	_mic.stop()
	_mic.queue_free()
	_mic = null
	_ring = PackedVector2Array()
	loud_clip = null
	level_db = -80.0


## The kept seconds as a sound (16-bit stereo).
func _clip() -> AudioStreamWAV:
	if _ring.is_empty():
		return null
	var data := PackedByteArray()
	data.resize(_ring.size() * 4)
	var at := 0
	for frame in _ring:
		data.encode_s16(at, int(clampf(frame.x, -1.0, 1.0) * 32767.0))
		data.encode_s16(at + 2, int(clampf(frame.y, -1.0, 1.0) * 32767.0))
		at += 4
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.stereo = true
	wav.mix_rate = int(AudioServer.get_mix_rate())
	wav.data = data
	return wav
