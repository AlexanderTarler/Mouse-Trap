class_name EntityStateApproach
extends EntityState

## Walking up to a chosen window or the door (data {"entry": CabinEntryLink}).
##
## data {"rush": true} (after LURE drew the player away): faster, and no
## stopping for anything.
##
## Spotted on the way, it would rather not be seen: mostly it slips away out
## of sight (config.shy_retreat_chance; that way in is avoided for a while,
## EntityWorld.mark_spotted). Otherwise it may bluff: stop partway, stare, and
## back off into the dark. Next time it may not stop.
##
## On arrival:
##   broken-open window / unlocked door -> ENTER
##   intact window                      -> PEEK
##   locked door                        -> PEEK (rattles the handle, then leaves)

const S := Entity.State
const ARRIVE_DISTANCE := 0.8

var _entry: CabinEntryLink = null
var _start_distance := 0.0
var _bluff_point := -1.0
var _bluff_left := 0.0
var _bluffing := false
var _arrived := false
## Rushing (after a lure drew the player away): faster, and no stopping.
var _rush := false
## Spotted on the way: slipping away instead (config.shy_retreat_chance).
var _retreating := false
var _was_watched := false


func enter(_from: int, data: Dictionary) -> void:
	_entry = data.get("entry", world.pick_entry())
	brain.target_entry = _entry
	_arrived = false
	_bluffing = false
	_rush = data.get("rush", false)
	_retreating = false
	_was_watched = false
	_bluff_point = randf_range(0.4, 0.65) if randf() < config.bluff_chance and not _rush else -1.0
	_start_distance = Entity._flat_distance(entity.global_position, _entry.start_position) if _entry else 0.0


func update(delta: float) -> void:
	if not _entry:
		return
	if _bluffing:
		_bluff_left -= delta
		entity.stop()
		entity.crawl()
		entity.face(entity.get_player().global_position)
		return
	# Spotted: it would rather not be seen. Mostly it slips away (and avoids
	# this way in for a while); otherwise it may stop and stare (the bluff).
	var watched := perception.player_watching
	if watched and not _was_watched and not _rush and randf() < config.shy_retreat_chance:
		_retreating = true
	_was_watched = watched
	var speed := config.approach_speed * (config.lure_rush_multiplier if _rush else 1.0)
	var remaining := entity.move_to(_entry.start_position, speed)
	if _bluff_point > 0.0 and perception.player_watching and remaining < _start_distance * (1.0 - _bluff_point):
		_bluff_point = -1.0
		_bluffing = true
		_bluff_left = randf_range(2.0, 4.0)
	_arrived = remaining < ARRIVE_DISTANCE


func next_state() -> int:
	if not _entry:
		return S.OBSERVE
	if perception.player_outside:
		return S.STALK if perception.can_see_player else S.OBSERVE
	if _retreating:
		world.mark_spotted(_entry)
		entity.confidence.modify(-config.shy_retreat_confidence, "spotted")
		return S.OBSERVE
	if _bluffing:
		return S.OBSERVE if _bluff_left <= 0.0 else NO_CHANGE
	if not world.is_entry_viable(_entry):
		entity.audio.play_grunt(1.3)
		return S.OBSERVE
	if not _arrived:
		return NO_CHANGE
	if _entry.kind == CabinEntryLink.Kind.DOOR:
		if _entry.entry.is_locked:
			return go(S.PEEK, {"entry": _entry, "rattle": true})
		return go(S.ENTER, {"entry": _entry})
	if _entry.entry.is_passable():
		return go(S.ENTER, {"entry": _entry})
	return go(S.PEEK, {"entry": _entry})
