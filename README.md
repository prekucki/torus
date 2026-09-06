# Torus Racer — Phase 2

A Godot **4.7.x** GDScript physics experiment using **built-in Jolt**.
Godot **4.7.2** is pinned in `mise.toml`:

```sh
mise install
mise run play
# Or open the editor:
mise exec -- godot --editor --path .
```

In the editor, open `controls_lab.tscn` and press **F6**, or press **F5** to run
the project. Phases 1 and 2 are implemented. Phase 3 assists and Phase 4 track/laps
wait for confirmation.

The torus starts with a spin impulse and rolls through ground friction. The
camera follows travel from directly behind so left/right bank looks symmetric. The
playable scene has no automatic nudge. Use small lean inputs while moving; at low
speed the unassisted ring can fall over. Reset to start a fresh run.

## Controls

| Action | Keyboard | Gamepad |
| --- | --- | --- |
| Accelerate | Up | RT, proportional |
| Brake | Down | LT, proportional |
| Lean | Left / Right | Left stick X, proportional |
| Hop | Space | A / Cross |
| Reset | R | Y / Triangle |
| Physics debug | D | Back / Select |

Keyboard and gamepad work simultaneously. HUD hints follow the last meaningful
input device, ignoring stick noise. Input Map actions are installed at startup
by `torus_input.gd`; their deadzones are zero so the configurable stick deadzone
is applied once. Default stick response is `sign(x) * ((abs(x)-0.15)/0.85)^1.5`
outside the deadzone. Keyboard keys retain full strength.

All player driving/banking commands use torque inside `_integrate_forces`; the
optional lower-pivot correction described below uses contact impulses. RT and LT contribute
independently to the net axle torque. Braking opposes current spin and caps its
one-step effect at zero; LT alone does not drive in reverse. Contacts can still
rotate a stopped ring, as expected in a free rigid-body simulation.

Left/right now requests a **bank angle**, not a yaw rate. Full input requests
25 degrees; the shaped analog value scales that target. A gyro-aware torque
changes bank about the travel direction, using the perpendicular torque axis
(`up` projected into the ring plane). At very low spin, ordinary roll torque
provides control instead. Turning then emerges from bank, spin and ground
contact. A brief initial countersteer is possible; no heading or velocity is
assigned. Releasing input applies no bank torque and does not automatically
return the body upright. Bank-rate feedback damps rocking without damping axle
spin. At high speed, changing sides takes longer because the bank actuator has
a finite torque cap and must redirect greater angular momentum.

The requested **manual lower pivot** is a separate, explicit contact assist.
While banking on support it applies bounded impulses **at the support point**,
5 cm above the averaged ground contacts by default. It reduces lateral/vertical
velocity at that point using the full angular velocity and contact effective
mass, including the impulse's angular reaction. It adds no forward impulse,
does not relocate the center of mass, and disables on hop or loss of support.
Applying this correction at the center of mass instead would suppress the
contact torque needed for a natural turn. This is a soft contact constraint,
not a fixed joint or a kinematic transform rotation.
Set `Lean Pivot Strength` to zero to compare against unassisted contacts.

Hop applies one vertical impulse only on an upward-facing support contact.
Wall contacts do not qualify. Holding the button or pressing it again in flight
does not add jumps or queue a jump on landing. Another hop requires landing and
a fresh press. Rumble is optional on landings and hard collisions.

Reset cancels linear and angular momentum with impulses, then relocates to the
checkpoint inside the integration callback. It applies the launch spin again
on the following tick. The spawn point is the initial checkpoint;
`TorusBody.set_checkpoint(Transform3D)` supplies later checkpoints. Camera
placement resets with the body.

## Live tuning and debug

While running in the editor, select **Remote > ControlsLab > Torus > Tuning**.
The `TorusTuning` resource exposes acceleration/braking/bank torque, hop impulse,
stick deadzone/curve, support-contact threshold, hop rearm time, and rumble.
Defaults are 18 / 24 / 30 N·m (bank torque is a cap), a 10.5 N·s hop, deadzone
0.15, and exponent 1.5. Bank target limit is 25 degrees, bank-rate limit is
40 degrees/s, response is 3/s, and bank-rate feedback is 20 N·m per rad/s.
The lower pivot defaults to 5 cm above the
support contacts, strength 1, response 40/s, and a correction acceleration cap
of 20 m/s². These values are live-editable; general Phase 3 assists remain deferred.
Edit geometry and base damping on the Torus node itself.
`ChaseCamera > Side Offset` can restore an angled view (4.5 m in the original
physics lab); zero in the playable scene avoids perspective-induced bank asymmetry.

Press **D / Back** for the separate, removable `TorusDebug` node. It makes the
torus 25% opaque with thin outlines, draws labeled vectors each physics tick,
and shows speed, spin, lean, grounded state, and slip beside the HUD. Its
`debug_vector_scale` controls the shared vector length scale (default 0.08).

- White: contact point; green: support normal; orange: estimated traction.
- Cyan: linear velocity at center of mass; purple: angular velocity.
- Yellow: net player torque; pink: assist torque, including the lower pivot's
  angular impulse divided by the timestep. General Phase 3 assists are still zero.
- Mint: lower-pivot impulse divided by the timestep, drawn at its application point.
- Red: instantaneous gyroscopic term `-ω × (I_world ω)`. The actual applied
  midpoint-integrated torque is also retained in the telemetry snapshot.

Traction is the tangential part of `get_contact_impulse() / state.step`. Jolt
returns world-space **estimated** impulses, including through getters named
`get_contact_local_*`. Slip is the largest tangential relative contact speed
divided by `max(abs(spin) * outer_radius, 0.1 m/s)`. Near rest this denominator
prevents division by zero; it is not a tire-model slip percentage.

Debug reads snapshots and changes visuals only. Removing it restores the torus
material. It adds no forces, damping, contacts, or velocity changes.

## Presentation

The donut has procedural baked-dough pores, glossy dripping strawberry icing,
and colored sprinkles. Asphalt uses fine aggregate, uneven patches and subtle
distance-faded survey markings. The playable lab adds an afternoon sky, warm
sun, light distance fog and 4× MSAA. No external texture downloads are needed.

The separate `TorusEffects` node reads physics snapshots to show slip dust,
short landing puffs and fading contact skid marks. Pure rolling and stationary
spin without ground contact emit no dust. Effects automatically hide in physics
debug and clear on reset. In **Remote > ControlsLab > TorusEffects**, adjust
`Intensity`, `Slip Threshold`, `Skid Lifetime`, or turn `Enabled` off. Removing
the node has no effect on physics; its regression compares 720 simulation ticks
with effects present versus absent, alongside particle/reset/debug probes.

## Original physics experiment

Run `mise run physics-lab`, or open `physics_validation.tscn` and press **F6**.
This scene has controls disabled and applies one automatic lean impulse at
**2 seconds**. Stop with **F8**, edit the Torus node, and restart to compare runs.

- `Major Radius` R = 1 m; `Minor Radius` r = 0.25 m; 100 capsule colliders.
  The outside diameter remains 2.5 m; collider count changes smoothness, not size.
- The axle is local +X. Capsule centerlines form chords of the YZ major circle,
  with rounded overlapping ends. Maximum centerline error is
  `R * (1 - cos(PI / capsule_count))`, about 0.49 mm at the defaults
  (previously 12.31 mm with 20 capsules). The inspector supports 12–128 capsules.
- The matching `TorusMesh` uses `inner_radius = R-r`, `outer_radius = R+r`.
- Mass = 3 kg; initial spin = 24 rad/s; nudge = 8 N·m·s about the forward axis;
  angular damping = 0; linear damping =
  0.01/s. Damping modes replace the project defaults. Spin comes from an angular
  impulse; friction supplies translation. There are no axis locks or assists.
- Geometry and launch settings take effect on restart. When changing radii,
  place the body at `R+r+0.03` above the floor. Physics damping, friction, and the
  manual gyro switch can be edited in the Remote inspector while running.
- Disable `Automatic Nudge` for a straight-line baseline. Use zero `Initial
  Spin` with the nudge enabled as a falling-body control experiment.
- Enable **Debug > Visible Collision Shapes** before running to inspect the
  runtime-generated capsule ring. This is the editor overlay, not Phase 2's
  custom physics debug view.

## Headless validation

Run the passing regression suite with `mise run validate`. Individual comparisons:

```sh
mise run import
mise exec -- godot --headless --path . --script res://tests/physics_validation.gd
mise exec -- godot --headless --path . --script res://tests/physics_validation.gd -- --manual
mise exec -- godot --headless --path . --script res://tests/physics_validation.gd -- --manual --no-nudge
mise exec -- godot --headless --path . --script res://tests/physics_validation.gd -- --manual --no-spin
mise exec -- godot --headless --path . --script res://tests/gyro_conservation.gd
mise exec -- godot --headless --path . --script res://tests/gyro_conservation.gd -- --manual
```

Each rolling experiment runs for 12 simulated seconds at 240 physics ticks/s and prints
one sample per simulated second. A spinning, nudged pass requires less than 5°
lean before the nudge, less than 45° lean throughout, more than 3° change in both
axle heading and travel direction after the nudge, and contact on more than half
the ticks. The no-spin control is
expected to fail the upright criterion. These are bounded validation criteria,
not a guarantee of indefinite stability or a proof of gyro integration by
themselves. Native/manual comparison and a free-flight momentum test distinguish
gyroscopic integration from contact-driven turning.

The full `mise run validate` suite also exercises real keyboard/gamepad events,
analog torque response, simultaneous inputs, braking near zero and in either
spin direction, ring-relative lean, grounded hopping, reset, and debug on/off
physics equivalence. A separate rolling-steering regression uses the playable
scene with gravity, friction, spin and gyro enabled: it checks sustained bank,
left/right symmetry from identical starts, and turns under keyboard and analog
input, with and without acceleration. The camera and grounded pivot have
separate regressions. `tests/steering_lifecycle.gd` additionally covers a six-second
held bank, a four-second reversal, and three seconds after release, both coasting
and accelerating. The pivot regression checks its impulse bound, angular reaction,
non-increasing kinetic energy on a stationary support, and hop/airborne exclusions.
Free-flight conservation runs for six simulated seconds.
Controller input is tested with synthetic events; physical rumble needs a
controller check on your machine.

## Gyro choice and measured validation

**Manual gyro is enabled by default.** Native Godot/Jolt can keep the rolling
ring upright and make it turn through contact dynamics, but does not enable
Jolt's gyroscopic-force option. The free-flight negative control exposes the
missing term: angular momentum direction drifts **6.903°** over six seconds.
That test intentionally exits with status 1 when `--manual` is omitted.

Applying raw `-ω × (I_world ω)` using a forward Euler step also proved inadequate:
at 24 rad/s and 240 Hz it gained **144.5% rotational energy** during the six-second
test. The final implementation evaluates that same torque with an **implicit
midpoint** step (six fixed-point iterations), keeping all physics additive via
`state.apply_torque()`. It never overwrites velocity or applies an upright assist.
The full local inertia is recovered from the body's world inverse tensor, then
rotated back with `B * I_local * B.transposed()` each tick.

The midpoint predictor includes the known player and assist torques as well as
the gyroscopic term. Omitting the external torques previously passed the
torque-free test but violated angular-momentum balance during steering.
`tests/gyro_forced.gd` covers this independently of the banking controller;
its `--uncoupled-gyro` option intentionally reproduces the old failing predictor.
It checks both angular momentum and rotational energy against external work.
There is no automatic energy normalization: friction, damping, impacts and
the explicit pivot correction must not be mistaken for torque-free motion.

Historical baseline on Godot **4.7.2.stable.official.ed1daf0bf**, using the
original **20-capsule** collider and stabilized manual implementation:

- Stayed upright for the 12-second straight-line baseline (lean below 0.01°).
- Reached **19.37° maximum lean**, **33.43° peak axle heading deflection**, and
  **9.73° peak travel-direction deflection** after the nudge, without falling
  over during the 12-second run.
- Conserved free-flight momentum direction within **0.348°**; momentum magnitude
  and rotational-energy error both printed **0.000%** (below 0.001%). Tolerances
  are 3°, 2%, and 2% respectively over six simulated seconds.
- Fell flat to **90° lean** with zero initial spin, as expected.

The denser 100-capsule default reduces the geometric unevenness of the original
collider. A fresh 12-second automatic-nudge run reached 17.32 degrees peak bank
and 30.25 degrees axle deflection, with contacts on 99% of samples. The ring
still loses speed to contact losses and drag. Finite-rate integration is
approximate; historical values above describe the original collider. Keep
240 Hz when reproducing them. Changing dimensions, mass, spin, or timestep calls
for rerunning the conservation and rolling tests.

## Physics references

- [Godot 4.7 built-in Jolt](https://docs.godotengine.org/en/4.7/tutorials/physics/using_jolt_physics.html)
- [Direct body state / inertia and torque](https://docs.godotengine.org/en/4.7/classes/class_physicsdirectbodystate3d.html)
- [TorusMesh](https://docs.godotengine.org/en/4.7/classes/class_torusmesh.html)
- [CapsuleShape3D](https://docs.godotengine.org/en/4.7/classes/class_capsuleshape3d.html)
- [Godot/Jolt body setup](https://github.com/godotengine/godot/blob/4.7.2-stable/modules/jolt_physics/objects/jolt_body_3d.cpp)
- [Jolt gyro default](https://github.com/godotengine/godot/blob/4.7-stable/thirdparty/jolt_physics/Jolt/Physics/Body/BodyCreationSettings.h)
- [Jolt contact impulse limitations](https://docs.godotengine.org/en/4.7/tutorials/physics/using_jolt_physics.html#contact-impulses)
- [Controller input](https://docs.godotengine.org/en/4.7/tutorials/inputs/controllers_gamepads_joysticks.html)
