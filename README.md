# Mouse Trap

A first-person survival horror game made in Godot 4.6.

Late April, the end of the 1990s. You're a field researcher sent to a remote
cabin in the Swedish pine forest to survey dormouse nests for Svea
Naturinstitut. No phone signal, a generator that needs fuel, a fuse box
that keeps failing, and an old forestry terminal that still remembers the
last researcher. Something in the treeline is watching the cabin. It hunts by
sound, it learns where you hide, and each night it gets bolder.

Days are for the work: the survey, the generator, boarding up windows.
Nights are for staying alive until dawn.

## What's in it

- **An enemy that thinks.** The Entity runs a state machine (watching,
  stalking, searching, approaching a window, peeking, breaking in, hunting
  room to room, fleeing) driven by what it actually perceives:
  - **Sight:** a vision cone with occlusion. It sees farther when you use
    the flashlight or stand in a lit room, less when you crouch in a bush.
  - **Hearing:** every noise has a range. Cabin walls cut it hard, trees and
    props barely, and sound leaks out through open doors and broken
    windows. At the edge of its hearing it only roughly knows where a noise
    came from.
  - **Memory:** it chases where it last saw or heard you, not where you
    are, so you can lose it.
  - **Learning:** it remembers the windows you defend and the rooms you
    hide in, across nights.
  - **Nerve:** a confidence level builds over each night and drops when it
    is driven off. That gives a build-up, peak and relief rhythm.
  - **It would rather not be seen:** spotted, it slips away. It lures you to
    one window while it goes for another. From the third night it lies in
    wait, kills lights from the dark, copies your footsteps, and fakes
    leaving.
- **Light as your only weapon.** The flashlight holds it in a standoff, the
  overcharged beam drives it off, and lit rooms keep it out. It breaks the
  fuse box to take those away.
- **Climbing.** From the fourth night it scales the walls to the upstairs
  windows.
- **A story told through the place:** a working Windows 98 style terminal,
  a field notebook, notes, and two endings.
- **Controller support**, rebindable keys, captions, brightness calibration,
  and a confirm-or-revert step for display changes.

## Running it

1. Install [Godot 4.6](https://godotengine.org/download) (standard build,
   not .NET).
2. Open `project.godot`. The first import takes a few minutes.
3. Press F5. The game starts at the main menu (`scenes/ui/main_menu.tscn`).

| Action | Keyboard / mouse | Gamepad |
|---|---|---|
| Move / look | WASD / mouse | Left / right stick |
| Sprint (unlocked later) | Shift | Left stick click |
| Crouch | Ctrl | B |
| Use (hold: board, refuel, carry) | E | X |
| Flashlight (hold: overcharge) | F | Y |
| Notebook | J | D-pad up |
| Inventory | Tab | View |
| Pause | Esc | Menu |

All keys can be rebound under Settings > Controls.

## How the code is organised

```
scripts/
  entity/            The Entity (see below)
    states/          One class per behaviour
  managers/          Autoloads: checkpoints, saves, tutorial, captions, ...
  ui/                Menus, HUD, notebook, options
  items/, objects/, interactables/
  night_manager.gd   Night and day flow
  routine_manager.gd Objectives
  game_time.gd       The clock (and when it holds for the story)
resources/entity_config.tres   Every Entity tuning value, in one place
tests/               Headless test scenes (see below)
tools/               Bakers and diagnostics (navmesh, forest, export checks)
```

### The Entity

`Entity` (`scripts/entity/entity.gd`) is the body and its public API.
Everything it decides or knows lives in a module:

| Module | Responsibility |
|---|---|
| `EntityBrain` | The state machine. It updates the senses once per frame, applies interrupts (the flashlight, lit rooms, the portable lamp), then runs the current state. |
| `EntityPerception` | Sight, hearing (with wall occlusion and sound leaking through openings), the flashlight on it, and memory. |
| `EntityWorld` | Where things are: vantage points, the cabin's entries and how attractive each is, a light map of the yard, hiding spots it has learned. |
| `EntityConfidence` | How bold it is. Rises over the night, drops when driven off. |
| `EntityTraversal` | Scripted moves off the navmesh: diving through windows, the door, climbing and clinging to the wall. |
| `EntityAnimator` | Which animation plays, keeping its feet on the ground and its head under the ceiling, cutscene poses. |
| `EntityAudio`, `EntityTraces` | Its sounds (including mimicry) and the claw prints it leaves. |
| `states/*.gd` | `EntityState` subclasses: `enter`, `update`, `next_state`, `exit`. |

All tuning is in `EntityConfig` (`resources/entity_config.tres`), grouped in
the Inspector, including what it may do from which night.

## Tests

The `tests/` folder holds headless scene tests: the Entity's behaviour,
hearing, climbing, checkpoints, the endings, the UI, a full playthrough and
more. Each one loads the real level and checks what happens in it.
`tests/regression/` holds the suites written with each round of playtest
fixes, so those fixes stay fixed.

Run them all:

```bash
GODOT=/path/to/godot tools/run_tests.sh            # everything
GODOT=/path/to/godot tools/run_tests.sh climb_test # one or more by name
```

Or one directly:

```bash
godot --headless --path . --fixed-fps 60 --script res://tests/climb_test.gd
```

## Credits

Code and design by Alexander Tarler. The full list of asset packs, sounds
and fonts, with their authors and licences, is on the in-game Credits
screen (`scripts/ui/credits_screen.gd`).

Third-party Godot add-ons in `addons/`, each under its own licence:
[TerraBrush](https://github.com/spimort/TerraBrush) (MIT),
Prism Collider 3D (MIT), and Godot MCP (Apache 2.0, an editor tool used
during development). The asset packs are licensed from their authors and
are not covered by any licence in this repository.
