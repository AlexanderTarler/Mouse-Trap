extends Node
## NightTwoStory (autoload): the beats of Night 2.2 (the car alarm and the
## chase) that belong to no one object:
##   - waking to the alarm (on_woke_to_alarm, from the bed):
##     "Why is the car alarm blaring?";
##   - the noise a few seconds later (NightManager's "entity_glimpse": a
##     footstep, a murmur, a creak): "What the fuck was that?!", then
##     3 s later the alarm and the car's battery. Never over the wake
##     thought: it waits for it;
##   - the chase: panic, "Oh fuck!" all over the screen (PanicThoughts),
##     faster the closer it is, until they're inside (or caught);
##   - inside: "What the FUCK was that?!";
##   - inside with the front door shut, it stays shut until Day 3
##     (Door.story_locked): "There is no way I'm going outside now."

const CHECK_INTERVAL := 0.1
const INSIDE_THOUGHT_DELAY := 1.0
const WAKE_THOUGHT_DELAY := 1.5
const WAKE_THOUGHT_TIME := 3.5
const NOISE_THOUGHT_TIME := 2.5
const ALARM_THOUGHT_GAP := 3.0
## The noise came before they woke: wait this long for the wake thought at
## most.
const WAKE_WAIT := 6.0
const ALARM_LINE := "If I don't turn off that alarm, that shitty car might run out of power. Fuck me."

var _clock := 0.0
var _check_left := 0.0
var _inside_pending := false
## Woken by the alarm tonight, and until when the wake thought shows.
var _woke := false
var _wake_until := -INF
## The chase began tonight (and the alarm hasn't gone off again since).
var _chase_on := false
var _panic: PanicThoughts = null


func _ready() -> void:
	var nm := get_node_or_null("/root/NightManager")
	if nm:
		nm.horror_event.connect(_on_horror_event)
		nm.first_chase_started.connect(_on_chase_started)
		nm.night_ended.connect(_on_night_ended)


func _process(delta: float) -> void:
	_clock += delta
	_check_left -= delta
	if _check_left > 0.0:
		return
	_check_left = CHECK_INTERVAL
	var inside := _player_inside()
	var chasing := _chasing()
	if _chase_on:
		_update_panic(chasing and not inside)
		if inside:
			_lock_door_if_shut()
	if chasing and inside and not _inside_pending and not Monologue.has_thought("n22_inside"):
		_inside_pending = true
		get_tree().create_timer(INSIDE_THOUGHT_DELAY).timeout.connect(_think_inside)


## The bed, as the player wakes to the alarm.
func on_woke_to_alarm() -> void:
	_woke = true
	_wake_until = _clock + WAKE_THOUGHT_DELAY + WAKE_THOUGHT_TIME
	get_tree().create_timer(WAKE_THOUGHT_DELAY).timeout.connect(
		Monologue.think.bind("Why is the car alarm blaring?", null, WAKE_THOUGHT_TIME, "n22_wake"))


func _on_horror_event(event_name: String) -> void:
	match event_name:
		"car_alarm":
			# Night 2.2 begins (or restarts at the van): nothing has happened yet.
			_woke = false
			_wake_until = -INF
			_chase_on = false
			_update_panic(false)
		"entity_glimpse":
			var nm := get_node_or_null("/root/NightManager")
			if nm and nm.is_van_sequence_active and not _chase_on:
				_react_to_noise(0.0)
		"entity_caught_player":
			_chase_on = false
			_update_panic(false)


## "What the fuck was that?!", once the wake thought is over.
func _react_to_noise(waited: float) -> void:
	if not _woke and waited < WAKE_WAIT:
		get_tree().create_timer(0.5).timeout.connect(_react_to_noise.bind(waited + 0.5))
		return
	var delay := maxf(_wake_until - _clock, 0.0) + 0.4
	get_tree().create_timer(delay).timeout.connect(_think_noise)


func _think_noise() -> void:
	if _chase_on:
		return
	Monologue.think("What the fuck was that?!", null, NOISE_THOUGHT_TIME, "n22_noise")
	get_tree().create_timer(ALARM_THOUGHT_GAP).timeout.connect(_think_alarm)


func _think_alarm() -> void:
	if not _chase_on:
		Monologue.think(ALARM_LINE, null, 5.0, "n22_alarm_power")


func _on_chase_started() -> void:
	_chase_on = true


func _on_night_ended(_night: int) -> void:
	_chase_on = false
	_update_panic(false)
	for door in get_tree().get_nodes_in_group("Door"):
		if door.get("story_locked"):
			door.story_locked = false


func _think_inside() -> void:
	_inside_pending = false
	Monologue.think("What the FUCK was that?!", null, 4.0, "n22_inside")


## Panic on (outside, being chased) or off.
func _update_panic(on: bool) -> void:
	if on and _panic == null:
		_panic = PanicThoughts.new()
		_panic.name = "PanicThoughts"
		add_child(_panic)
	if _panic == null:
		return
	if not on:
		if _panic.active:
			_panic.clear()
		return
	_panic.active = true
	var entity := get_tree().get_first_node_in_group("entity") as Node3D
	var player := get_tree().get_first_node_in_group("player") as Node3D
	if entity and player:
		_panic.distance = entity.global_position.distance_to(player.global_position)


## Inside with the front door shut: it stays shut till morning.
func _lock_door_if_shut() -> void:
	for door in get_tree().get_nodes_in_group("Door"):
		if "story_locked" in door and not door.is_open and not door.story_locked:
			door.story_locked = true


## The van chase is on (the Entity after them).
func _chasing() -> bool:
	var entity := get_tree().get_first_node_in_group("entity")
	return entity != null and entity.get("van_chase_active") == true


func _player_inside() -> bool:
	var player := get_tree().get_first_node_in_group("player")
	return player != null and player.has_method("get_player_room") and player.get_player_room() != "Outside"
