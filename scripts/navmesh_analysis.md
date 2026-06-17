# Entity Navigation & Physics Stalling — Diagnostic Report

## Changes Applied (entity_controller.gd)

### Fix 1: NavigationAgent Tuning (line 715-718)

```gdscript
_nav_agent.path_desired_distance = 1.0      # Was 2.0 — prevents overshoot in tight spaces
_nav_agent.target_desired_distance = 1.5     # Was 2.0 — stops closer to target
_nav_agent.radius = 0.4                      # Reduced from 0.5 for tighter pathfinding
_nav_agent.avoidance_enabled = false         # RVO avoidance fights physics in tight spaces
```

**Why:** The old values (2.0/2.0) meant the Entity would try to hit waypoints too precisely in tight interior spaces. RVO avoidance was producing conflicting velocity vectors that cancelled out to near-zero in narrow corridors (cabin doorframes).

### Fix 2: Physics Property Tweaks (line 723-728)

```gdscript
axis_lock_angular_x = true
axis_lock_angular_z = true
floor_constant_speed = true
floor_snap_length = 0.1       # Was 0.5 — prevents snagging on door thresholds
floor_max_angle = deg_to_rad(65.0)  # Was 60° — helps with porch stairs
safe_margin = 0.02            # Smaller margin = fewer invisible wall hits
```

**Why:** The old `floor_snap_length = 0.5` was too aggressive — the Entity would snag on door thresholds and small geometry bumps. The increased `floor_max_angle` helps the Entity navigate porch stairs without getting stuck. The reduced `safe_margin` prevents the Entity from hitting invisible collision edges.

### Fix 3: Stuck Detection `real_vel` Debug Print (line 1049-1050)

```gdscript
var real_vel := get_real_velocity()
print("[Entity] STUCK DETECTED! No movement for %.1fs while nav is active. real_vel=(%.3f, %.3f, %.3f) len=%.3f. Relocating." % [stuck_timeout, real_vel.x, real_vel.y, real_vel.z, real_vel.length()])
```

**Why:** Prints the actual `get_real_velocity()` value when the Entity gets stuck, so you can determine whether it's a physical collision block (real_vel ~ 0 but AI wants to move) or a pathfinding rejection (nav finished, AI produces zero velocity).

### Fix 4: Duplicate Code Cleanup (line 730-738)

Removed duplicate `_nav_agent.path_desired_distance = 2.0` and `_nav_agent.target_desired_distance = 2.0` assignments that were overwriting the new values. Also removed duplicate `axis_lock_angular_x/z`, `floor_snap_length`, and `floor_max_angle` assignments that were resetting the physics tweaks back to their old values.

---

## How to Interpret the Results

### Question 1: Is the green path line active when the Entity is stuck?

**How to check:**

1. Open Godot Editor
2. Go to **Debug → Visible Navigation** (top menu)
3. Run the game
4. Watch the Entity in the Cabin

**Interpretation:**

- **Line disappears** → The agent has lost its path. This means:
  - The NavMesh was re-baked and no longer covers that area
  - The target position is outside the NavMesh bounds
  - The NavigationAgent3D's `target_position` was reset to an unreachable location
- **Line is present but Entity pushes against wall/door** → This is a **physics collision block**. The Entity has a valid path but cannot move through geometry.

### Question 2: Does the Entity move if `avoidance_enabled` is OFF?

**How to check:**

1. Select the `NavigationAgent3D` child node of the Entity
2. Find the `avoidance_enabled` property
3. Uncheck it (set to `false`)
4. Run the game

**Interpretation:**

- **Entity starts moving** → Godot's internal RVO (Reciprocal Velocity Obstacle) avoidance was fighting against the physics engine in the tight cabin space. RVO tries to steer the Entity away from predicted collisions, but in tight corridors this can produce conflicting velocity vectors that cancel out to near-zero.
- **Entity still stuck** → The issue is NOT RVO avoidance. It's either pathfinding rejection or physical collision.

### Question 3: What is the value of `real_vel` when stuck?

Look for the `[Entity] STUCK DETECTED!` print in the console output.

**Interpretation Matrix:**

| `real_vel` | `nav_finished` | Diagnosis                                                                                                                                                                             |
| ---------- | -------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| ~(0,0,0)   | false          | **PHYSICAL COLLISION BLOCK** — AI wants to move, nav has a path, but `move_and_slide()` returns zero velocity. The Entity is pushing against a wall/door/collider.                    |
| ~(0,0,0)   | true           | **PATHFINDING REJECTION** — Nav says path is finished (or never started), AI produces zero velocity. The target is unreachable or the NavMesh doesn't cover the area.                 |
| ~(0.1,0,0) | false          | **PARTIAL COLLISION** — The Entity is moving slightly but at 1/30th of the intended speed. It's wedged against geometry and `move_and_slide()` is only producing a tiny slide vector. |

---

## Quick Diagnostic Checklist

- [ ] **Step 1:** Enable **Debug → Visible Navigation** and run the game
- [ ] **Step 2:** When Entity stalls, check if green path line is visible
- [ ] **Step 3:** Check `Motion Mode` = `Grounded` on CharacterBody3D
- [ ] **Step 4:** Check `floor_max_angle` (~65°) and `floor_stop_on_slope`
- [ ] **Step 5:** Temporarily disable `CollisionShape3D` — does Entity move?
- [ ] **Step 6:** `avoidance_enabled` is now OFF by default (set in code)
- [ ] **Step 7:** `path_desired_distance` = 1.0, `target_desired_distance` = 1.5 (set in code)
