# Vehicle Physics

## Physics model versions

`VehicleStats.physics_model_version` selects the handling implementation:

- **`0` (Legacy)** — Explicit comparison mode. Direct-yaw steering, simple
  lateral grip, and input-driven arcade drift.
- **`1` (Bicycle)** — Default for all four cars. Two-axle tire forces,
  friction-circle braking, a speed-sensitive steering rack, and deliberate
  drift with qualified boost rewards. Arcade recentering and neutral yaw
  damping keep steering corrections and slide release predictable.

Canonical per-car values live in `data/vehicles/*.tres`; the championship
catalog references those resources and keeps presentation ratings separate
from simulation units.

## V1 Model summary

Per tick at 60 Hz:

1. **Steering rack**: steer input → speed-sensitive target angle → smooth
   tracking at `steering_response` rate. Persistent `_rack_angle` state.
2. **Slip angles**: front/rear computed from linear+angular velocity,
   wheelbase geometry, and rack angle.
3. **Tire forces**: linear below peak (`cornering_stiffness × slip`),
   saturated at peak (`axle_grip × surface_grip × normal_load`), post-peak
   falloff (`max(post_peak_grip_ratio, 1 - falloff_rate × (demand-1))`).
   Surface stiffness scales by `sqrt(grip_multiplier)` (progressive).
4. **Front force along steered axis** at front axle position; rear force
   along body lateral at rear axle → natural yaw torque/under/oversteer.
5. **Load split**: front_weight_ratio distributes normal load between axles.
6. **Engine**: torque curve (launch_torque → peak → falloff to max_speed).
   Scaled by surface_speed_multiplier and external_power_multiplier.
7. **Drag**: `aero_drag_coefficient × v × |v|`. Rolling:
   `rolling_resistance × sign(v)`. Slow materials do not multiply these
   resistances again: their lower drive target and bounded scrub already
   reduce sustained speed.
8. **Braking**: 62/38 front/rear bias. Each axle capped by remaining friction
   circle capacity (ABS-style clamp, no cadence). Mass/grip/surface dependent.
9. **Handbrake**: rear-only longitudinal braking + rear grip reduction via
   `drift_rear_grip_ratio` during drift.
10. **Surface target**: overspeed scrub ramps up near `eff_max × 0.95`, bounded
    to 0.5 gravity-equivalent deceleration. Entering a slow patch carries
    momentum instead of truncating velocity. Hard caps use the dry chassis
    maximum: `1.0×` normal, `1.2×` boosted, shared by all racers.
11. **Low-speed blend**: yaw stability damping below 35 wu/s prevents
    oscillation.

## Drift state machine (v1)

```
NONE → ACTIVE → EXITING → NONE
         ↓         ↑
    (conditions)  (grace timer / cancel)
```

- **Entry**: handbrake held AND |steer| ≥ `drift_entry_steer` AND speed ≥
  `drift_min_speed` AND rear slip growing in steering direction.
- **During**: rear grip × `drift_rear_grip_ratio`; bounded
  `drift_yaw_assist` torque (reduced with counter-steer); front stays
  physical; natural scrub loss.
- **Qualified time**: accumulates when rear slip within ±12° of
  `drift_optimal_slip_deg` AND throttle AND speed ≥ entry speed.
- **Controlled exit**: handbrake released + slip < 6° for 0.20 s → boost
  awarded ONCE (min 0.35 s qualified, capped at `drift_boost_max_reward`).
- **Cancel**: speed < 80% entry speed, or slip > 60° with forward v ≤ 0, or
  collision during drift → no boost.
- **Recovery**: rear grip recovers exponentially at `drift_grip_recovery_rate`.
  Recovery starts on handbrake release, not after the drift-state exit. A
  completed exit never drops the restored grip again. Neutral steering adds
  yaw damping without snapping velocity or changing the car's position.

## Boost (v1)

Unified `add_boost(amount, source)`:
- Sources: player drift (on controlled exit), AI clean-line, drafting.
- No recharge while boosting.
- Drain at per-car `boost_drain_rate`; capacity per-car `boost_capacity`.
- Speed cap: 1.0× normal, 1.2× boosted (hard limit, shared).

## AI integration (v1)

AI queries derive from the same `VehicleDynamics` helpers:
- `get_safe_corner_speed(radius, surface_grip)` → `sqrt(eff_lat_accel × R)`
- `get_braking_distance(v_now, v_target, surface_grip)` → kinematic
- `get_effective_max_speed()` / `get_effective_grip()`

Difficulty margins: sunday 0.86, club 0.96, clockwork 0.99.
AI never sends handbrake; catch-up within 1.15 total; no hidden modifiers.

Each upcoming curve is paired with its own distance and a reachable-speed
braking envelope. The most restrictive envelope wins; a distant hairpin
does not impose apex speed on the entire preceding straight. Corner planning
reserves tire capacity for braking and tracking corrections. Circular-path
geometry tests guard the circumradius calculation, and solo-versus-field
races use the same chassis, normal finish grace, explicit finish/DNF checks,
and measured cruising pace. They are not a proxy for a measured human lap.

Stall progress is net forward arc distance: repeated reversing and advancing
over the same few units cannot keep resetting recovery detection.

Steering lookahead uses local curvature; future corners constrain braking,
not the steering target on the current straight. Grip-only surfaces reduce
speed only when turning or correcting sideslip. Obstacle avoidance supplies
an independent speed limit rather than multiplying the corner limit again.

Club and Clockwork can take a shorter clear apron route to the currently
required checkpoint. The complete route is checked with a car-width swept
strip against solid scenery; a gate is never skipped. These routes require
at least ten percent distance savings, and recovery switches its progress
reference to that route while committed. Sunday retains the reference line.
Passing clearance is measured against the active route, not inferred from
whether an unrelated obstacle exists on the opposite side.

## Parameter table

| Category | `VehicleStats` export group |
|---|---|
| 4.1 Chassis/powertrain | Chassis and powertrain |
| 4.2 Tires/steering | Tires and steering |
| 4.3 Brake/drift | Brakes and drift |
| 4.4 Boost/durability | Boost and durability |

All v1 parameters have validated ranges in `VehicleStats.PARAMETER_RANGES`.

## Recovery resets

- **Player** (`reset_manager.gd`): `0.10 × eff_max` clamped 55–75 wu/s,
  half boost.
- **AI** (`ai_vehicle_controller.gd`): `0.12 × eff_max` clamped 70–90 wu/s,
  half boost.
- Both call `reset_dynamics_state()` to clear drift/rack/grip state.

## Files

- `scripts/vehicle/vehicle_dynamics.gd` — Pure math (no scene tree).
- `scripts/vehicle/vehicle_controller.gd` — Input/state/surfaces/collisions.
- `scripts/vehicle/vehicle_stats.gd` — Resource with validation.
- `data/vehicles/{rustbug,pinbolt,scrapjaw,flicker}.tres` — Canonical stats.
- `tests/vehicle_dynamics_unit_test.gd` — Comprehensive pure-math tests.
- `tests/vehicle_physics_benchmark.gd` — Full scenario benchmark with gates.
- `tests/drift_test.gd` — v0 smoke + v1 isolated drift state tests.

## Verification and comparison

Run the current game with `godot --path .`. All canonical resources select v1.
The benchmark environment variable below selects a test model; it does not
change the normal game's selected resources.

```bash
PC_PHYSICS_MODEL_VERSION=1 godot --path . --headless --script res://tests/vehicle_physics_benchmark.gd
PC_PHYSICS_MODEL_VERSION=0 godot --path . --headless --script res://tests/vehicle_physics_benchmark.gd
godot --path . --headless --script res://tests/vehicle_controllability_test.gd
```

The controllability test runs actual rigid bodies at 60 Hz, three repetitions
per car/model, with short taps, partial steering, S-turns, braking turns and
handbrake release. It observes a full second after release. A high-speed
Rustbug tap is limited to 15 degrees total and 7 degrees after release;
high-speed slide-release rotation is limited to 45 degrees for every car.
These are regression filters, not claims that automated tests prove fun.

The four cars share collision geometry but differ in power delivery, mass,
braking, grip and steering response. Flicker's dry rear grip remains stable;
its drift identity comes from deliberate handbrake use, not unavoidable spins.

The AI adapter follows projected reference paths, requests wheel steering
through the speed-limited rack, and predicts braking from this same model.
Legacy fixtures without a RacingLine use their ordered track-surface samples;
grid slots on bends face the local road tangent. Race pace/recovery limits
remain separate tests and were not widened for the new model.
