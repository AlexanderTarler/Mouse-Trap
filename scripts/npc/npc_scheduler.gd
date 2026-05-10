extends Node
class_name NPCScheduler

## Schedule manager for NPC behavior.
## Defines a daily routine with time-based activities.
## NPCs query their schedule against GameTime to determine what to do.

enum Activity {
	IDLE,        # Stand around doing nothing
	WANDER,      # Walk to random nearby points
	HOME,        # At home (sleeping/relaxing)
	WORK,        # At workplace
	SHOP,        # At shop
	WALK_HOME,   # Walking to home
	WALK_WORK,   # Walking to work
	WALK_SHOP,   # Walking to shop
	WALK_WANDER  # Walking to wander destination
}

## A schedule entry defining what to do at a given time.
## Stored as a Dictionary with keys: hour, activity, target
static func make_entry(hour: int, activity: Activity, target: Vector3) -> Dictionary:
	return {
		"hour": hour,
		"activity": activity,
		"target": target
	}

## The NPC's daily schedule (array of Dictionaries)
var schedule: Array[Dictionary] = []

## Builds a default schedule based on NPCData positions and personality.
func build_schedule(data: NPCData) -> void:
	schedule.clear()
	
	match data.personality_type:
		"WORKER":
			_build_worker_schedule(data)
		"SHOPPER":
			_build_shopper_schedule(data)
		"LOAFER":
			_build_loafer_schedule(data)
		_:
			_build_neutral_schedule(data)

func _build_worker_schedule(data: NPCData) -> void:
	# Walk to work from 6-7, work 7-12
	schedule.append(make_entry(6, Activity.WALK_WORK, data.work_position))
	schedule.append(make_entry(7, Activity.WORK, data.work_position))
	# Walk to shop 12-13, shop 13-14
	schedule.append(make_entry(12, Activity.WALK_SHOP, data.shop_position))
	schedule.append(make_entry(13, Activity.SHOP, data.shop_position))
	# Walk back to work 14-15, work 15-18
	schedule.append(make_entry(14, Activity.WALK_WORK, data.work_position))
	schedule.append(make_entry(15, Activity.WORK, data.work_position))
	# Walk home 18-19, home 19+
	schedule.append(make_entry(18, Activity.WALK_HOME, data.home_position))
	schedule.append(make_entry(19, Activity.HOME, data.home_position))

func _build_shopper_schedule(data: NPCData) -> void:
	# Walk to shop 8-9, shop 9-12
	schedule.append(make_entry(8, Activity.WALK_SHOP, data.shop_position))
	schedule.append(make_entry(9, Activity.SHOP, data.shop_position))
	# Wander near home 12-15
	schedule.append(make_entry(12, Activity.WALK_WANDER, data.home_position))
	schedule.append(make_entry(13, Activity.WANDER, data.home_position))
	# Walk to shop 15-16, shop 16-19
	schedule.append(make_entry(15, Activity.WALK_SHOP, data.shop_position))
	schedule.append(make_entry(16, Activity.SHOP, data.shop_position))
	# Walk home 19-20, home 20+
	schedule.append(make_entry(19, Activity.WALK_HOME, data.home_position))
	schedule.append(make_entry(20, Activity.HOME, data.home_position))

func _build_loafer_schedule(data: NPCData) -> void:
	# Wander near home 10-11
	schedule.append(make_entry(10, Activity.WALK_WANDER, data.home_position))
	schedule.append(make_entry(11, Activity.WANDER, data.home_position))
	# Walk to shop 14-15, shop 15-17
	schedule.append(make_entry(14, Activity.WALK_SHOP, data.shop_position))
	schedule.append(make_entry(15, Activity.SHOP, data.shop_position))
	# Wander near home 17-22
	schedule.append(make_entry(17, Activity.WALK_WANDER, data.home_position))
	schedule.append(make_entry(18, Activity.WANDER, data.home_position))
	# Walk home 22-23, home 23+
	schedule.append(make_entry(22, Activity.WALK_HOME, data.home_position))
	schedule.append(make_entry(23, Activity.HOME, data.home_position))

func _build_neutral_schedule(data: NPCData) -> void:
	# Walk to work 7-8, work 8-12
	schedule.append(make_entry(7, Activity.WALK_WORK, data.work_position))
	schedule.append(make_entry(8, Activity.WORK, data.work_position))
	# Walk to shop 12-13, shop 13-14
	schedule.append(make_entry(12, Activity.WALK_SHOP, data.shop_position))
	schedule.append(make_entry(13, Activity.SHOP, data.shop_position))
	# Walk back to work 14-15, work 15-17
	schedule.append(make_entry(14, Activity.WALK_WORK, data.work_position))
	schedule.append(make_entry(15, Activity.WORK, data.work_position))
	# Walk home 17-18, home 18+
	schedule.append(make_entry(17, Activity.WALK_HOME, data.home_position))
	schedule.append(make_entry(18, Activity.HOME, data.home_position))

## Gets the current activity based on the game time.
## Returns a Dictionary with keys: hour, activity, target, or IDLE if none found.
func get_current_activity(game_hour: float) -> Dictionary:
	if schedule.is_empty():
		return make_entry(int(game_hour), Activity.IDLE, Vector3.ZERO)
	
	# Find the last schedule entry whose hour <= current hour
	var current: Dictionary = schedule[0]
	for i in range(schedule.size() - 1, -1, -1):
		if schedule[i]["hour"] <= game_hour:
			current = schedule[i]
			break
	
	return current

## Returns true if the current activity involves walking/moving.
static func is_walking_activity(activity: Activity) -> bool:
	return activity in [Activity.WALK_HOME, Activity.WALK_WORK, Activity.WALK_SHOP, Activity.WALK_WANDER]
