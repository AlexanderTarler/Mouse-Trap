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
##   monitor: the options menu's Test: listens even with the microphone off
##     and plays what it hears straight back (live, nothing kept).
##
## The microphone itself is shared: AudioServer's input, on while any
## listener (the player's, the options menu's) wants it, read once a frame
## for all of them. (Each listener used to play an AudioStreamMicrophone of
## its own; starting or stopping any one of them started or stopped the one
## input under all of them, which left the others deaf: the Test heard you
## once, then never again.)

const SETTING := "audio/microphone"
const THRESHOLD_SETTING := "audio/mic_threshold_db"
const KEEP_SECONDS := 2.0
## Seconds more kept after a loud moment (the end of the gasp).
const TAIL := 0.5
## At most one noise this often (s).
const NOISE_GAP := 0.6
## This many dB over the threshold is "loud" (carries further).
const LOUD_OVER := 10.0
## At most this much is taken in one frame (s): after nobody read for a
## while (all paused), only the latest, not seconds of old sound at once.
const MAX_CHUNK := 0.2
## The Test's playback buffer (s): short, so it's heard as it's said.
const MONITOR_BUFFER := 0.15

var meter_only := false
## The options menu's Test (see the top).
var monitor := false:
	set(value):
		if value == monitor:
			return
		monitor = value
		if monitor and _active:
			_start_monitor()
		elif not monitor:
			_stop_monitor()
		_check = 0.0
## The input level now (dB, the peak, falling back slowly): for the meter.
var level_db := -80.0
var loud_clip: AudioStreamWAV = null
## How many times it has been loud enough to be heard (for the tests).
var heard := 0
var _active := false
var _monitor_player: AudioStreamPlayer = null
var _monitor_playback: AudioStreamGeneratorPlayback = null
var _ring := PackedVector2Array()
var _cooldown := 0.0
var _tail_left := -1.0
var _check := 0.0

## The shared input: how many listeners want it, and this frame's sound.
static var _users := 0
static var _chunk := PackedVector2Array()
static var _chunk_frame := -1


static func enabled() -> bool:
	return bool(GameSettings.get_value(SETTING))


static func threshold_db() -> float:
	return float(GameSettings.get_value(THRESHOLD_SETTING))


## The microphone's sample rate (what its frames are in).
static func mix_rate() -> float:
	var rate := AudioServer.get_input_mix_rate()
	return rate if rate > 0.0 else AudioServer.get_mix_rate()


func is_listening() -> bool:
	return _active


func _process(delta: float) -> void:
	_check -= delta
	if _check <= 0.0:
		_check = 1.0
		var wanted := enabled() or monitor
		if wanted and not _active:
			_start()
		elif not wanted and _active:
			_stop()
	if not _active:
		level_db = -80.0
		return
	var buffer := _frames_now()
	var peak := 0.0
	if not buffer.is_empty():
		for frame in buffer:
			peak = maxf(peak, maxf(absf(frame.x), absf(frame.y)))
		if _monitor_playback:
			var room := _monitor_playback.get_frames_available()
			_monitor_playback.push_buffer(buffer if buffer.size() <= room else buffer.slice(buffer.size() - room))
		if _recording:
			_record.append_array(buffer)
			if _record.size() > int(RECORD_MAX * mix_rate()):
				_record = _record.slice(_record.size() - int(RECORD_MAX * mix_rate()))
			record_peak_db = maxf(record_peak_db, linear_to_db(maxf(peak, 0.00001)))
		if not meter_only:
			_ring.append_array(buffer)
			var keep := int(KEEP_SECONDS * mix_rate())
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
	if not _acquire():
		return
	_active = true
	if monitor:
		_start_monitor()
	print("[PlayerVoice] Listening (threshold %.0f dB)." % threshold_db())


func _stop() -> void:
	if _active:
		_active = false
		_release()
	_stop_monitor()
	_ring = PackedVector2Array()
	loud_clip = null
	level_db = -80.0


func _exit_tree() -> void:
	# (Freed with the options menu, or the player: its share of the input.)
	_stop()


## The Test: what comes in, played straight back.
func _start_monitor() -> void:
	if _monitor_player:
		return
	var generator := AudioStreamGenerator.new()
	generator.mix_rate = mix_rate()
	generator.buffer_length = MONITOR_BUFFER
	_monitor_player = AudioStreamPlayer.new()
	_monitor_player.name = "MicTest"
	_monitor_player.stream = generator
	_monitor_player.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_monitor_player)
	_monitor_player.play()
	_monitor_playback = _monitor_player.get_stream_playback() as AudioStreamGeneratorPlayback


func _stop_monitor() -> void:
	_monitor_playback = null
	if is_instance_valid(_monitor_player):
		_monitor_player.stop()
		_monitor_player.queue_free()
	_monitor_player = null


## The input on for one more listener. (If the driver can't start it, no
## microphone, AudioServer counts it as on all the same: nothing comes in,
## which is silence, not a failure to retry.)
static func _acquire() -> bool:
	if _users == 0:
		var err := AudioServer.set_input_device_active(true)
		if err != OK:
			print("[PlayerVoice] The microphone input didn't start (error %d): listening to silence." % err)
		_chunk = PackedVector2Array()
		_chunk_frame = -1
	_users += 1
	return true


## One listener fewer: the input off with the last.
static func _release() -> void:
	_users = maxi(_users - 1, 0)
	if _users == 0:
		AudioServer.set_input_device_active(false)


## What came in since the last frame: read once, the same for every
## listener this frame.
static func _frames_now() -> PackedVector2Array:
	var frame := Engine.get_process_frames()
	if frame == _chunk_frame:
		return _chunk
	_chunk_frame = frame
	var available := AudioServer.get_input_frames_available()
	_chunk = AudioServer.get_input_frames(available) if available > 0 else PackedVector2Array()
	var most := int(MAX_CHUNK * mix_rate())
	if _chunk.size() > most:
		_chunk = _chunk.slice(_chunk.size() - most)
	return _chunk


## ─── RECORDING (Nest Gamma) ───────────────────────────────────────────────
## Everything heard from start_recording() on (the last RECORD_MAX s), kept
## in memory only, handed back by stop_recording(). record_peak_db: the
## loudest moment in it (was anything said at all?).
const RECORD_MAX := 4.0
var record_peak_db := -80.0
var _recording := false
var _record := PackedVector2Array()


func start_recording() -> void:
	_recording = true
	_record = PackedVector2Array()
	record_peak_db = -80.0


func stop_recording() -> AudioStreamWAV:
	_recording = false
	var clip := _to_wav(_record)
	_record = PackedVector2Array()
	return clip


## The kept seconds as a sound (16-bit stereo).
func _clip() -> AudioStreamWAV:
	return _to_wav(_ring)


func _to_wav(frames: PackedVector2Array) -> AudioStreamWAV:
	if frames.is_empty():
		return null
	var data := PackedByteArray()
	data.resize(frames.size() * 4)
	var at := 0
	for frame in frames:
		data.encode_s16(at, int(clampf(frame.x, -1.0, 1.0) * 32767.0))
		data.encode_s16(at + 2, int(clampf(frame.y, -1.0, 1.0) * 32767.0))
		at += 4
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.stereo = true
	wav.mix_rate = int(mix_rate())
	wav.data = data
	return wav
