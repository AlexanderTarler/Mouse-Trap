class_name EntityStateLure
extends EntityState
## Drawing the player out of their room before breaking in (data {"entry":
## the window it wants, "decoy": a window of another room}; see
## EntityWorld.plan_entry). It would rather not come in under the player's
## nose:
##   1. it creeps to the decoy window and knocks on the glass a few times;
##   2. slips out of sight nearby and waits, listening;
##   3. once it believes the player has left the target's room (heard or
##      seen elsewhere), it hurries to the real window (APPROACH, rushing).
## If the player stays put it knocks again (config.lure_rounds), then gives up
## and goes for the least watched way in. Spotted at any point, it slips away
## (OBSERVE) and avoids that window for a while.

const S := Entity.State
const KNOCK_GAP := 1.7

enum Phase { GO, KNOCK, HIDE }

var _target: CabinEntryLink = null
var _decoy: CabinEntryLink = null
var _phase := Phase.GO
var _knocks_left := 0
var _knock_wait := 0.0
var _rounds := 0
var _wait_left := 0.0
var _hide_spot := Vector3.ZERO
var _target_room := ""
var _spotted := false
var _drawn_out := false


func enter(_from: int, data: Dictionary) -> void:
	_target = data.get("entry")
	_decoy = data.get("decoy")
	brain.target_entry = _decoy
	_target_room = world.entry_room(_target) if _target else ""
	_phase = Phase.GO
	_rounds = 0
	_spotted = false
	_drawn_out = false


func update(delta: float) -> void:
	if not _target or not _decoy:
		return
	if perception.player_watching:
		_spotted = true
		return
	match _phase:
		Phase.GO:
			if hold_at_entry(_decoy, config.approach_speed):
				_start_knocking()
		Phase.KNOCK:
			entity.face(_decoy.end_position)
			_knock_wait -= delta
			if _knock_wait <= 0.0:
				if _knocks_left > 0:
					_knocks_left -= 1
					_knock_wait = KNOCK_GAP * randf_range(0.8, 1.2)
					entity.audio.play_tap_at(_decoy.entry.global_position)
				else:
					_phase = Phase.HIDE
					_wait_left = config.lure_wait
					_hide_spot = world.find_hidden_point(_decoy.start_position, 4.0, 9.0, world.outside_of(_decoy, 6.0))
		Phase.HIDE:
			# Out of sight, low, listening.
			if entity.move_to(_hide_spot, config.approach_speed) < 0.8:
				entity.crawl()
				entity.face(_decoy.end_position)
			_wait_left -= delta
			_drawn_out = _player_left_target_room()


func next_state() -> int:
	if perception.player_outside:
		return S.STALK if perception.can_see_player else S.OBSERVE
	if not _target or not _decoy or not world.is_entry_viable(_target):
		return S.OBSERVE
	if _spotted:
		# Seen: away out of sight, and that window is off for a while.
		world.mark_spotted(_decoy)
		return S.OBSERVE
	if _phase != Phase.HIDE:
		return NO_CHANGE
	if _drawn_out:
		return go(S.APPROACH, {"entry": _target, "rush": true})
	if _wait_left > 0.0:
		return NO_CHANGE
	_rounds += 1
	if _rounds < config.lure_rounds:
		# Nothing yet: back to the window, and knock again.
		_phase = Phase.GO
		return NO_CHANGE
	# They won't budge: the least watched way in, then.
	var entry := world.pick_entry()
	if entry:
		return go(S.APPROACH, {"entry": entry})
	return S.OBSERVE


func _start_knocking() -> void:
	_phase = Phase.KNOCK
	_knocks_left = config.lure_knocks
	_knock_wait = 0.4
	if _rounds == 0:
		entity.traces.scratch_window(_decoy)


## Whether it believes the player has gone from the target's room: heard or
## seen somewhere else since it knocked.
func _player_left_target_room() -> bool:
	var room := perception.suspected_player_room().to_lower()
	return room != "" and room != _target_room


func can_catch() -> bool:
	return true
