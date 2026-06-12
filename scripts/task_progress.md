# Player Stealth and Entity Memory - Implementation Progress

## Step 1: Sensory & Memory Architecture

- [ ] 1a. Overhaul `entity_sensory.gd` — Vision scaling with lighting + distance check
- [ ] 1b. Add `hear_noise()` to `entity_controller.gd` — Acoustic detection
- [ ] 1c. Update `player_controller.gd` — Walking noise, sprint noise radius increase
- [ ] 1d. Modify `entity_ai.gd` — Memory-based pathfinding (target `last_known_position`)
- [ ] 1e. Add Investigation Phase to `entity_ai.gd` — 3-5s pause at last_known_position
