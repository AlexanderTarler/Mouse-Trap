class_name EntityTraversal
extends Node

## The Entity's scripted moves, where it leaves the navmesh for a moment:
##   - crossing an entry link: diving in through a ground-floor window,
##     crawling out of one, walking through the door;
##   - climbing the wall to an upstairs window, clinging outside it (peeking,
##     tapping and breaking the glass happen from there), climbing in, back
##     down, or dropping off when it is driven away.
## A move is a Tween on the Entity's position with its collision off; the
## Entity's own movement and its states wait meanwhile (Entity.is_traversing),
## though it still senses (EntityBrain.sense), and the overcharged beam held
## on it long enough drives it off mid-move (check_driven_off).
##
## States use it through the Entity (traverse_link, climb_to_perch,
## leave_perch, enter_from_perch, set_perch_duck, is_traversing, is_clinging,
## is_perched_at).

## Backup for link_reached: if the path was requested while already standing
## on a link's end, the agent may skip the signal and head straight for the
## far end (into the wall). Standing at one end of an open link with the far
## end as the next waypoint means: cross it.
const LINK_CROSS_NEAR := 1.2
const LINK_CROSS_NEXT := 0.8
## Coming in through a ground floor window: it backs off a few metres (still
## facing it), runs at it, and dives through (Entity Dive Through Bottom
## Floor Windows), landing inside.
const DIVE_BACK_OFF := 3.0
const DIVE_RUN_SPEED := 7.0
const DIVE_TIME := 1.2
const DIVE_ANIM := &"DiveIn"
## Out through a window: crawling (the floor crawl), low over the sill.
const EXIT_CRAWL_ANIM := &"LowCrawl"
const EXIT_CRAWL_APEX := 0.55
## In through an upstairs window from the wall (Entity Climbing Inside Upper
## Floor), at the animation's own pace.
const CLIMB_IN_ANIM := &"ClimbIn"
const CLIMB_IN_TIME := 3.8
## Claws on the logs while it climbs: one scrape this often (s).
const CLIMB_TAP_INTERVAL := 0.95
## Getting up after dropping off a wall (the rest of Falling To Landing).
const DROP_LAND_TIME := 0.55

var entity: Entity
var config: EntityConfig

## Animation for the current leg of a move (empty: pick from the kind).
var anim: StringName = &""
## The kind of link being crossed (CabinEntryLink.Kind), -1 when not moving.
var kind := -1

var _tween: Tween = null
## The link being crossed or climbed, and whether the move was abandoned
## (driven off mid-move: bail_out).
var _link: CabinEntryLink = null
var _bailing := false
# Clinging to the wall outside an upstairs window.
var _perch_link: CabinEntryLink = null
var _perch_offset := Vector3.ZERO
var _climb_tap_left := 0.0


func setup(owner_entity: Entity) -> void:
	entity = owner_entity
	config = owner_entity.config


# ═════════════════════════════════════════════════════════════════════════════
# STATE
# ═════════════════════════════════════════════════════════════════════════════

## In the middle of a move.
func is_active() -> bool:
	return _tween != null


## Holding on to the wall outside an upstairs window (including while ducking).
func is_clinging() -> bool:
	return _perch_link != null


## Clinging outside `link`'s window, not in the middle of a move.
func is_perched_at(link: CabinEntryLink) -> bool:
	return _perch_link == link and not is_active()


## Where it holds on right now (clinging only).
func perch_hold() -> Vector3:
	return entity.world.perch_position(_perch_link) + _perch_offset


## Ducks below the sill (`down`) or comes back up while clinging.
func set_perch_duck(down: bool) -> void:
	_perch_offset = Vector3.DOWN * config.perch_duck_drop if down else Vector3.ZERO


## Stops any move and lets go of the wall at once (teleport, deactivation,
## a cutscene taking it over).
func abort() -> void:
	_cancel()
	_release_perch()


# ═════════════════════════════════════════════════════════════════════════════
# EVERY FRAME (from Entity._physics_process)
# ═════════════════════════════════════════════════════════════════════════════

## In the middle of a move: the sounds of it.
func update_moving(delta: float) -> void:
	if anim != &"ClimbUp" and anim != &"ClimbDown":
		return
	_climb_tap_left -= delta
	if _climb_tap_left <= 0.0:
		_climb_tap_left = CLIMB_TAP_INTERVAL
		entity.audio.play_climb_scrape(entity.global_position + Vector3.UP * 1.2)


## Holding on outside the window: no gravity, no walking.
func update_clinging(delta: float) -> void:
	entity.global_position = entity.global_position.lerp(perch_hold(), clampf(delta * 6.0, 0.0, 1.0))
	entity.velocity = Vector3.ZERO
	_face_window(_perch_link)


## Standing at one end of an open link with its far end next on the path:
## cross it (see LINK_CROSS_NEAR).
func check_link_crossing(moving: bool) -> void:
	var nav := entity.nav_agent
	if nav.is_navigation_finished() or not moving:
		return
	var here := entity.global_position
	var next := nav.get_next_path_position()
	for link in entity.world.entries():
		if not link.enabled:
			continue
		if Entity.reach_distance(here, link.start_position) < LINK_CROSS_NEAR \
				and Entity.reach_distance(next, link.end_position) < LINK_CROSS_NEXT:
			_traverse(link, link.start_position, link.end_position)
			return
		if Entity.reach_distance(here, link.end_position) < LINK_CROSS_NEAR \
				and Entity.reach_distance(next, link.start_position) < LINK_CROSS_NEXT:
			_traverse(link, link.end_position, link.start_position)
			return


## The overcharged beam held on it for Entity.repel_time() in the middle of a
## move (up the wall, over a sill, through the door): it is driven off there
## and then. (Its senses used to stop for the whole move, up to four seconds
## of climbing in with the beam on it doing nothing.)
func check_driven_off() -> void:
	var state := entity.brain.state_id
	if _bailing or not _link or state == Entity.State.FLEE or state == Entity.State.STUNNED \
			or entity.van_chase_active or entity.perception.overcharge_time < entity.repel_time():
		return
	entity.note_driven_off()
	entity.audio.play_scream()
	bail_out()
	entity.brain.force(Entity.State.FLEE)


# ═════════════════════════════════════════════════════════════════════════════
# CROSSING A LINK (windows and the door)
# ═════════════════════════════════════════════════════════════════════════════

## Crosses `link` now: outside -> inside if `inward`, otherwise back out.
func traverse_link(link: CabinEntryLink, inward: bool) -> void:
	if is_active() or not link.enabled:
		return
	if inward:
		_traverse(link, link.start_position, link.end_position)
	else:
		_traverse(link, link.end_position, link.start_position)


## The navigation agent reached a link on its path.
func on_link_reached(details: Dictionary) -> void:
	var link := details.get("owner") as CabinEntryLink
	if not link or is_active():
		return
	var start: Vector3 = details.get("link_entry_position", link.start_position)
	var end: Vector3 = details.get("link_exit_position", link.end_position)
	_traverse(link, start, end)


## Carries the Entity across an entry link. Collision is off during the move:
## windows are climbed over the sill, the door is walked through after opening.
func _traverse(link: CabinEntryLink, start: Vector3, end: Vector3) -> void:
	if link.climb:
		_traverse_climb(link, start.distance_to(link.start_position) < start.distance_to(link.end_position))
		return
	_begin(link)
	var dir := end - start
	entity.rotation.y = atan2(dir.x, dir.z)
	if link.kind == CabinEntryLink.Kind.DOOR:
		var door := link.entry
		if door and not door.is_open and not door.is_locked:
			door.interact()
			_tween.tween_interval(0.5)
		var duration := maxf(start.distance_to(end) / config.approach_speed, 0.5)
		_tween.tween_property(entity, "global_position", start, 0.15)
		_tween.tween_property(entity, "global_position", end, duration)
	else:
		# Leaving (from inside): it crawls out head first, low over the sill,
		# facing the window.
		var leaving := start.distance_to(link.end_position) < start.distance_to(link.start_position)
		if leaving:
			entity.audio.play_vault()
			anim = EXIT_CRAWL_ANIM
			var apex := (start + end) * 0.5 + Vector3.UP * EXIT_CRAWL_APEX
			var half := config.vault_time * 0.5
			_tween.tween_property(entity, "global_position", start, 0.15)
			_tween.tween_property(entity, "global_position", apex, half).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_SINE)
			_tween.tween_property(entity, "global_position", end, half).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_SINE)
		else:
			_tween_dive_in(start, end)


func _tween_dive_in(start: Vector3, end: Vector3) -> void:
	var outward := Vector3(start.x - end.x, 0.0, start.z - end.z).normalized()
	var back := start + outward * DIVE_BACK_OFF
	_tween.tween_callback(_set_anim.bind(&"Stalk"))
	_tween.tween_property(entity, "global_position", back, maxf(entity.global_position.distance_to(back) / config.approach_speed, 0.3))
	_tween.tween_callback(_set_anim.bind(&"running_crawl"))
	_tween.tween_property(entity, "global_position", start, DIVE_BACK_OFF / DIVE_RUN_SPEED)
	_tween.tween_callback(_set_anim.bind(DIVE_ANIM))
	_tween.tween_callback(entity.audio.play_vault)
	var apex := (start + end) * 0.5 + Vector3.UP * 0.7
	_tween.tween_property(entity, "global_position", apex, DIVE_TIME * 0.45).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_SINE)
	_tween.tween_property(entity, "global_position", end, DIVE_TIME * 0.55).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_SINE)


# ═════════════════════════════════════════════════════════════════════════════
# CLIMBING (upstairs windows, from EntityConfig.climb_night)
# ═════════════════════════════════════════════════════════════════════════════
# It climbs the wall below an upstairs window and clings outside it (on the
# ledge where there is one): peeking, tapping and breaking the glass happen
# from there. It vaults in from the wall, climbs back down when it gives up,
# and drops off when it is driven away. A route through an open upstairs
# window (its link) does the whole climb and vault in one go.

## Climbs from the ground below `link`'s window to cling outside it.
func climb_to_perch(link: CabinEntryLink) -> void:
	if is_active() or is_clinging():
		return
	var perch := entity.world.perch_position(link)
	var base := Vector3(perch.x, link.start_position.y, perch.z)
	_begin(link)
	_face_window(link)
	entity.traces.scratch_climb(link, base, perch)
	_tween.tween_callback(_set_anim.bind(&"Stalk"))
	_tween.tween_property(entity, "global_position", base, maxf(entity.global_position.distance_to(base) / config.approach_speed, 0.2))
	_tween_climb(base, perch, &"ClimbUp")
	_tween.tween_callback(_set_perch.bind(link))


## Lets go of the wall: climbs back down, or (`scared`) drops off.
func leave_perch(scared: bool) -> void:
	if not is_clinging() or is_active():
		return
	var link := _perch_link
	var here := entity.global_position
	var base := Vector3(here.x, link.start_position.y, here.z)
	_perch_offset = Vector3.ZERO
	_begin(link)
	if scared:
		_tween_drop(base)
	else:
		_tween_climb(here, base, &"ClimbDown")
	_tween.tween_callback(_set_perch.bind(null))


## From the wall, in through the (open) window.
func enter_from_perch(link: CabinEntryLink) -> void:
	if not is_perched_at(link) or not link.enabled:
		return
	_begin(link)
	_tween.tween_callback(_set_perch.bind(null))
	_tween_vault(entity.global_position, link.end_position, CLIMB_IN_ANIM, 0.6, CLIMB_IN_TIME)


## A route through an open upstairs window: the whole climb in one move.
func _traverse_climb(link: CabinEntryLink, inward: bool) -> void:
	var perch := entity.world.perch_position(link)
	var base := Vector3(perch.x, link.start_position.y, perch.z)
	_begin(link)
	_face_window(link)
	if inward:
		entity.traces.scratch_climb(link, base, perch)
		_tween.tween_property(entity, "global_position", base, maxf(entity.global_position.distance_to(base) / config.approach_speed, 0.2))
		_tween_climb(base, perch, &"ClimbUp")
		_tween_vault(perch, link.end_position, CLIMB_IN_ANIM, 0.6, CLIMB_IN_TIME)
	else:
		# Out of the window head first (crawling, facing it), then round to
		# face the wall and down it.
		var outward := link.start_position - link.end_position
		entity.rotation.y = atan2(outward.x, outward.z)
		_tween_vault(entity.global_position, perch, EXIT_CRAWL_ANIM, EXIT_CRAWL_APEX)
		var to_wall := link.end_position - link.start_position
		_tween.tween_property(entity, "rotation:y", entity.rotation.y + wrapf(atan2(to_wall.x, to_wall.z) - entity.rotation.y, -PI, PI), 0.35)
		_tween_climb(perch, base, &"ClimbDown")
		_tween.tween_property(entity, "global_position", link.start_position, 0.3)


func _tween_climb(from: Vector3, to: Vector3, climb_anim: StringName) -> void:
	_tween.tween_callback(_set_anim.bind(climb_anim))
	_tween.tween_property(entity, "global_position", to, maxf(from.distance_to(to) / config.climb_speed, 0.3))


func _tween_vault(from: Vector3, to: Vector3, vault_anim: StringName = &"EnterWindow", lift: float = 0.6, time: float = -1.0) -> void:
	var apex := (from + to) * 0.5 + Vector3.UP * lift
	var half := (config.vault_time if time <= 0.0 else time) * 0.5
	_tween.tween_callback(_set_anim.bind(vault_anim))
	_tween.tween_callback(entity.audio.play_vault)
	_tween.tween_property(entity, "global_position", apex, half).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_SINE)
	_tween.tween_property(entity, "global_position", to, half).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_SINE)


## Falling To Landing: the fall to `ground`, then landing in a crouch and
## rising. Off the wall once it hits the ground.
func _tween_drop(ground: Vector3) -> void:
	_tween.tween_callback(_set_anim.bind(&"DropLand"))
	_tween.tween_property(entity, "global_position", ground, config.drop_time) \
		.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	_tween.tween_callback(entity.audio.play_drop_thud)
	_tween.tween_callback(_set_perch.bind(null))
	_tween.tween_interval(DROP_LAND_TIME)


# ═════════════════════════════════════════════════════════════════════════════
# STARTING, ENDING, ABANDONING A MOVE
# ═════════════════════════════════════════════════════════════════════════════

## A move begins: collision off, a fresh tween that ends it when done.
func _begin(link: CabinEntryLink) -> void:
	kind = link.kind
	_link = link
	_bailing = false
	entity.collision_mask = 0
	entity.velocity = Vector3.ZERO
	_climb_tap_left = 0.0
	_tween = entity.create_tween()
	_tween.finished.connect(_end)


func _end() -> void:
	_tween = null
	kind = -1
	_link = null
	_bailing = false
	anim = &""
	if not is_clinging():
		entity.collision_mask = Entity.MOVE_MASK
	entity.reset_navigation()


func _cancel() -> void:
	if _tween:
		_tween.kill()
		_end()


## Abandons the move it is in the middle of for the nearest footing: past the
## wall already, it lands inside; still outside, it drops to the ground below
## (off the wall) or goes back out to where it started. Collision stays off
## until it is there (_end), so it never ends up inside a wall.
func bail_out() -> void:
	var link := _link
	if not _tween or not link:
		return
	_tween.kill()
	_bailing = true
	_perch_link = null
	_perch_offset = Vector3.ZERO
	var here := entity.global_position
	_tween = entity.create_tween()
	_tween.finished.connect(_end)
	if entity.world.is_inside_cabin(here):
		_tween_scramble(here, link.end_position)
	elif link.climb:
		var ground := Vector3(here.x, link.start_position.y, here.z)
		if here.y - ground.y > 0.5:
			_tween_drop(ground)
		else:
			_tween_scramble(here, ground)
	else:
		_tween_scramble(here, link.start_position)


func _tween_scramble(from: Vector3, to: Vector3) -> void:
	_tween.tween_callback(_set_anim.bind(&"LowCrawl"))
	_tween.tween_property(entity, "global_position", to, clampf(from.distance_to(to) / config.flee_speed, 0.25, 1.2))


func _set_anim(new_anim: StringName) -> void:
	anim = new_anim


func _set_perch(link: CabinEntryLink) -> void:
	_perch_link = link
	if link != null and (entity.perception.player_inside or EntityJournal.player_sees(entity)):
		EntityJournal.learn(entity, "climb")


func _face_window(link: CabinEntryLink) -> void:
	var inward := link.end_position - link.start_position
	entity.rotation.y = atan2(inward.x, inward.z)


## Drops any hold on the wall at once.
func _release_perch() -> void:
	_perch_link = null
	_perch_offset = Vector3.ZERO
	if not is_active():
		entity.collision_mask = Entity.MOVE_MASK
