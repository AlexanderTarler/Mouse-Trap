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
## Committed lunge at the player (outdoors).
@export var charge_speed: float = 9.0
## Lunge inside the cabin: slower, so the player can bring the overcharge up
## in the tight rooms.
@export var indoor_charge_speed: float = 6.0
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
## Crouched inside a bush (FoliageRustle.in_cover), it sees the player only
## from this close (m), unless their flashlight is on.
@export var bush_cover_range: float = 4.0
## Height of the Entity's eyes above its feet.
@export var eye_height: float = 1.9
## After this long without seeing or hearing the player, the last known
## position is treated as stale.
@export var memory_time: float = 12.0

@export_group("Hearing")
## How far (m) each kind of noise carries in the open (see NoiseEvent.emit).
@export var noise_radius: Dictionary = {
	"walk": 18.0,
	"sprint": 35.0,
	"crouch": 3.0,
	"land": 8.0,
	"hammer": 25.0,
	"door": 12.0,
	"drop": 8.0,
	"click": 3.0,
	"rustle": 10.0,
	"rustle_crouch": 6.0,
}
## Footsteps on the cabin's wooden floors carry this much farther.
@export var indoor_footstep_multiplier: float = 1.3
## Each cabin wall (or closed door / intact window) between the noise and
## the Entity keeps this fraction of the range.
@export var hearing_wall_multiplier: float = 0.35
## Each tree, rock or prop in between keeps this fraction...
@export var hearing_obstacle_multiplier: float = 0.9
## ...but together they never cut the range below this fraction.
@export var hearing_obstacle_floor: float = 0.6
## Sound escaping through an open door or a broken, unboarded window keeps
## this fraction of the range (on the path through the opening).
@export var hearing_opening_multiplier: float = 0.85
## A noise near the edge of hearing is placed up to this far (m) from where
## it really was; noises within half the range are exact.
@export var hearing_max_error: float = 5.0
## Confidence gained for a noise heard from inside the cabin (full for a
## clear one, half at the edge of hearing).
@export var noise_confidence_boost: float = 1.5

@export_group("Flashlight")
## Stare pressure (0-1) builds while a standard beam is on it outdoors (both
## outside) and drains slowly when it isn't. At 1 it winds up to charge.
## A close, centred beam fills it in this many seconds; a weak one (far away
## or at the edge of the beam) takes up to 2.5x as long.
@export var charge_stare_time: float = 1.8
## Stare pressure lost per second while no beam is on it, so flicking the
## beam on and off doesn't reset it.
@export var stare_pressure_decay: float = 0.2
## Seconds it crouches and growls before charging. Looking away (or
## overcharging) during the wind-up stops the charge.
@export var charge_windup_time: float = 1.0
## Beam off it for this long during the wind-up: it backs off instead.
@export var windup_release_time: float = 0.25
## When a standoff ends it backs away from the player this far (m)...
@export var standoff_retreat_distance: float = 5.0
## ...for at most this long, facing the player, before resuming.
@export var standoff_retreat_time: float = 2.0
## After a standoff a standard beam can't freeze it again for this long.
@export var standoff_cooldown: float = 5.0
## Overcharged beam held on it for this long: it flees.
@export var overcharge_repel_time: float = 0.9
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
## Caught being watched (from further than stalk_freeze_min_distance) it
## stops dead and stares back for stalk_stare_time seconds...
@export var stalk_freeze_when_watched: bool = true
## Distance inside which being watched no longer stops it at all.
@export var stalk_freeze_min_distance: float = 5.0
@export var stalk_stare_time: float = 1.5
## ...then keeps creeping closer at this fraction of stalk_speed for as long
## as it is watched. Watching slows it; it never holds it off for good.
@export var stalk_watched_speed: float = 0.45
## Visible, unwatched and this close: it lunges (CHARGE).
@export var stalk_lunge_distance: float = 3.5
## Further than this and out of view: it repositions near the player.
@export var rubberband_distance: float = 45.0

@export_group("Search")
@export var search_points: int = 3
@export var search_radius: float = 6.0
@export var search_listen_min: float = 1.5
@export var search_listen_max: float = 3.0
## Searching for the player outdoors it grows more frantic: its speed
## doubles every this many seconds (and its listening pauses shrink to
## match)...
@export var search_speed_doubling_time: float = 10.0
## ...up to this (m/s). Just under the player's sprint (6.5), so running
## still escapes it.
@export var search_speed_max: float = 6.0

@export_group("Charge")
@export var charge_max_time: float = 6.0
## After the portable lamp's stun wears off (player outside): a committed
## charge at the player (tracks them without needing to see them, the
## flashlight can't stop it) that lasts this long.
@export var post_stun_chase_time: float = 15.0
## The chase music during the Night 2.2 van chase. Off: only the tension
## drone and the Entity's own sounds.
@export var van_chase_music: bool = false
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
## Gives up on a window after this long (not counting pauses).
@export var breach_max_time: float = 45.0
## Chance, once per break-in, to stop halfway and go quiet for a while
## (the player can't tell whether it left).
@export var breach_pause_chance: float = 0.4
## From Night 3: chance to ease out the glass of an unboarded window in a
## room the player isn't in, with one dull crack, instead of smashing it.
@export var quiet_entry_chance: float = 0.4
## Minimum time between turning off a room light from outside.
@export var light_sabotage_cooldown: float = 45.0
## Time to climb through a broken window.
@export var vault_time: float = 1.4

@export_group("Shyness")
## It would rather not be seen. Choosing a way in (EntityWorld.pick_entry),
## it avoids the room it believes the player is in, entries the player can
## see right now, and ones where it was spotted lately; it favours entries far
## from the player.
@export var shy_room_penalty: float = 5.0
@export var shy_view_penalty: float = 3.0
@export var shy_spotted_penalty: float = 4.0
## Up to this much for an entry far from the player (1 per 8 m).
@export var shy_distance_bonus: float = 1.5
## How long it trusts its idea of which room the player is in (s).
@export var room_memory_time: float = 45.0
## How long it avoids an entry where the player spotted it (s).
@export var spotted_memory: float = 45.0
## Spotted while walking up to the cabin: the chance it slips away out of
## sight rather than stopping to stare (bluff_chance).
@export var shy_retreat_chance: float = 0.75
## Confidence it loses slipping away like that.
@export var shy_retreat_confidence: float = 6.0
## At a window, once it has ducked as often as it will, being looked at
## again sends it away from that window.
@export var peek_leave_when_watched: bool = true
@export_subgroup("Lure")
## When the best way in is a window of the player's own room, the chance it
## tries to draw them away first: noises at a window of another room
## (LURE), then, once the player has moved, a quick dash to the real one.
@export var lure_chance: float = 0.7
## Knocks on the decoy window per round, and rounds before it gives up.
@export var lure_knocks: int = 3
@export var lure_rounds: int = 2
## How long it waits, hidden, for the player to leave their room (s).
@export var lure_wait: float = 16.0
## Its speed to the real window once the player has gone (x approach_speed).
@export var lure_rush_multiplier: float = 1.6

@export_group("Climbing")
## From this night it climbs the walls to the upstairs windows.
@export var climb_night: int = 4
## Speed up and down the wall (m/s).
@export var climb_speed: float = 1.4
## Seconds to drop off the wall when it is scared off.
@export var drop_time: float = 0.45
## Clinging outside a window: its feet this far below the window's centre...
@export var perch_head_height: float = 1.65
## ...and this far out from it (on the ledge where there is one).
@export var perch_wall_offset: float = 0.75
## Ducking below the sill while peeking from the wall, this far down.
@export var perch_duck_drop: float = 1.4
## Upstairs windows score this much lower as entries (the climb is a detour).
@export var climb_entry_penalty: float = 1.0

@export_group("Indoors")
## Leaves the cabin after this long without finding the player.
@export var hunt_give_up_time: float = 45.0
@export var room_scan_time: float = 3.5
## From Night 3: after checking a room, chance to wait in ambush instead,
## crouched in the dark, silent, for ambush_time_min..max seconds.
@export var ambush_chance: float = 0.45
@export var ambush_time_min: float = 20.0
@export var ambush_time_max: float = 45.0
## It springs when the player comes this close (or finds it with a look).
@export var ambush_spring_distance: float = 3.0
## The tell before it lunges from an ambush: a breath, then this long.
@export var ambush_tell_time: float = 1.0
## From Night 3, at most once a night: giving up, it sounds like it leaves
## (the window, a thud outside, a growl in the yard) but stays, in ambush.
@export var fake_departure_chance: float = 0.5

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
