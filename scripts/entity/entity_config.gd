class_name EntityConfig
extends Resource

## Every tuning value the Entity uses. The live values are in
## res://resources/entity_config.tres; nothing in the Entity scripts
## hardcodes a balance number that belongs here.

@export_group("Movement (m/s)")
## Creeping between treeline vantage points.
@export var observe_speed: float = 2.2
## Walking up to a window or the door.
@export var approach_speed: float = 2.4
## Following the player outside.
@export var stalk_speed: float = 3.8
## Investigating a sighting or a noise.
@export var search_speed: float = 2.6
## Committed lunge at the player.
@export var charge_speed: float = 9.0
## Running from the light.
@export var flee_speed: float = 7.0
## Prowling the cabin with no fresh lead.
@export var hunt_speed: float = 2.2
## Heading for a fresh sighting or noise indoors.
@export var hunt_alert_speed: float = 4.2
## Speed multiplier after a blackout frees it from the overload stun.
@export var enraged_speed_multiplier: float = 1.4

@export_group("Van Chase (Night 2)")
## The van chase is paced against the player's sprint speed so a player who
## keeps running always reaches the cabin first.
@export var van_speed_ratio_start: float = 0.82
@export var van_speed_ratio_max: float = 0.93
@export var van_ramp_delay: float = 6.0
@export var van_ramp_time: float = 16.0

@export_group("Vision")
## Half-angle of the vision cone, in degrees.
@export var vision_half_angle: float = 55.0
@export var vision_range_dark: float = 9.0
## Player standing in a lit room, seen from the dark.
@export var vision_range_lit: float = 16.0
## Player's flashlight is on: they are a beacon.
@export var vision_range_flashlight: float = 28.0
## Watching the cabin from a vantage point or a window.
@export var vision_range_watching: float = 35.0
## Vision range multiplier when the player crouches in the dark.
@export var crouch_vision_multiplier: float = 0.35
## Height of the Entity's eyes above its feet.
@export var eye_height: float = 1.9
## After this long without seeing or hearing the player, the last known
## position is treated as stale.
@export var memory_time: float = 12.0

@export_group("Hearing")
## Noise heard through a wall carries this fraction of its radius.
@export var hearing_wall_multiplier: float = 0.5

@export_group("Flashlight")
## Standard beam held on it outdoors (both outside) for this long: it charges.
@export var charge_stare_time: float = 1.8
## Overcharged beam held on it for this long: it flees.
@export var overcharge_repel_time: float = 1.5
## Brief beam drop-outs shorter than this don't reset the overcharge timer.
@export var overcharge_grace: float = 0.35
## A lost beam must stay lost this long before a standoff ends.
@export var standoff_release_time: float = 0.4

@export_group("Confidence")
@export var confidence_base: float = 15.0
## Added to the resting confidence per night after Night 1.
@export var confidence_per_night: float = 8.0
## Added to the resting confidence as the night progresses (0 -> this).
@export var confidence_night_progress: float = 12.0
## How fast confidence drifts back toward its resting value (per second).
@export var confidence_drift: float = 1.2
## Confidence needed before it approaches the cabin.
@export var approach_threshold: float = 40.0
## Confidence lost when it is driven off.
@export var repel_penalty: float = 15.0
## After being driven off it will not approach again for this long.
@export var relax_time: float = 20.0
## Added each time it watches the cabin from a vantage point without seeing
## the player (impatience).
@export var impatience_boost: float = 6.0
## Drained per second while a flashlight beam is on it.
@export var stare_drain: float = 2.0

@export_group("Observe")
@export var watch_time_min: float = 4.0
@export var watch_time_max: float = 9.0
## Watch time when confident (>= approach_threshold).
@export var watch_time_bold_min: float = 2.0
@export var watch_time_bold_max: float = 4.5
## Relocations longer than this are done by teleporting, but only when both
## ends are out of the player's view.
@export var hidden_relocate_distance: float = 25.0
## If the player has been outside and unseen this long, it senses roughly
## where they are and goes looking.
@export var outside_sense_time: float = 25.0
## How far off its "sense" of the player's position is.
@export var outside_sense_error: float = 10.0

@export_group("Stalk")
## Stalking stops and it goes searching after this long without a sighting.
@export var stalk_lose_time: float = 6.0
## Freeze in place while the player is looking straight at it (unless close).
@export var stalk_freeze_when_watched: bool = true
## Distance inside which being watched no longer freezes it.
@export var stalk_freeze_min_distance: float = 5.0
## Visible, unwatched and this close: it lunges (CHARGE).
@export var stalk_lunge_distance: float = 3.5
## Further than this and out of view: it repositions near the player.
@export var rubberband_distance: float = 45.0

@export_group("Search")
@export var search_points: int = 3
@export var search_radius: float = 6.0
@export var search_listen_min: float = 1.5
@export var search_listen_max: float = 3.0

@export_group("Charge")
@export var charge_max_time: float = 6.0
## Charge ends when the player has been out of sight this long.
@export var charge_lose_sight_time: float = 1.5

@export_group("Windows")
@export var peek_time_min: float = 3.0
@export var peek_time_max: float = 7.0
## Chance to duck out of sight when the player looks at the window.
@export var peek_duck_chance: float = 0.6
@export var peek_duck_time: float = 2.5
## Seconds between taps on the glass while the player isn't looking.
@export var tap_interval_min: float = 3.0
@export var tap_interval_max: float = 6.0
## Chance to stop halfway, stare, and back off while being watched.
@export var bluff_chance: float = 0.35
@export var hit_interval: float = 2.0
## Delay from the start of the AttackWindow swing to the impact.
@export var hit_impact_delay: float = 0.5
## Gives up on a window after this long.
@export var breach_max_time: float = 45.0
## Minimum time between turning off a room light from outside.
@export var light_sabotage_cooldown: float = 45.0
## Time to climb through a broken window.
@export var vault_time: float = 1.4

@export_group("Indoors")
## Leaves the cabin after this long without finding the player.
@export var hunt_give_up_time: float = 45.0
@export var room_scan_time: float = 3.5

@export_group("Flee")
@export var flee_distance: float = 18.0
@export var flee_max_time: float = 8.0

@export_group("Sabotage")
## All entries blocked (lit, locked, repelled) for this long: it goes for
## the fuse box.
@export var frustration_time: float = 40.0
@export var fuse_hits: int = 2
@export var fuse_hit_interval: float = 2.0
@export var sabotage_max_time: float = 25.0
@export var lamp_hit_interval: float = 3.0
@export var lamp_attack_range: float = 2.5

@export_group("Physical")
@export var catch_distance: float = 1.4
## Movement is "stuck" if it gains less than this many meters...
@export var stuck_progress: float = 0.3
## ...over this many seconds.
@export var stuck_time: float = 2.5
