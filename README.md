# Torus Racer — Phase 1

A Godot **4.7.x** GDScript physics experiment using **built-in Jolt**.
Godot **4.7.2** is pinned in `mise.toml`:

```sh
mise install
mise run play
# Or open the editor:
mise exec -- godot --editor --path .
```

In the editor, open `physics_validation.tscn` and press **F6** (or **F5**).
Only Phase 1 is implemented; further phases wait for confirmation.

The upright torus receives one spin impulse, starts rolling through ground
friction, and receives one lean impulse at **2 seconds**. Watch it against the
floor grid. Stop with **F8**, edit the `Torus` node, then run again for a fresh
experiment. The pale stripe shows rotation; the camera follows travel.

## Experiment settings

- `Major Radius` R = 1 m; `Minor Radius` r = 0.25 m; 20 capsule colliders.
- The axle is local +X. Capsule centerlines form chords of the YZ major circle,
  with rounded overlapping ends. Maximum centerline error is
  `R * (1 - cos(PI / capsule_count))`, about 1.23 cm at the defaults.
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

Each experiment runs for 12 simulated seconds at 240 physics ticks/s and prints
one sample per simulated second. A spinning, nudged pass requires less than 5°
lean before the nudge, less than 45° lean throughout, more than 3° change in both
axle heading and travel direction after the nudge, and contact on more than half
the ticks. The no-spin control is
expected to fail the upright criterion. These are bounded validation criteria,
not a guarantee of indefinite stability or a proof of gyro integration by
themselves. Native/manual comparison and a free-flight momentum test distinguish
gyroscopic integration from contact-driven turning.

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

On Godot **4.7.2.stable.official.ed1daf0bf**, the stabilized manual implementation:

- Stayed upright for the 12-second straight-line baseline (lean below 0.01°).
- Reached **19.37° maximum lean**, **33.43° peak axle heading deflection**, and
  **9.73° peak travel-direction deflection** after the nudge, without falling
  over during the 12-second run.
- Conserved free-flight momentum direction within **0.348°**; momentum magnitude
  and rotational-energy error both printed **0.000%** (below 0.001%). Tolerances
  are 3°, 2%, and 2% respectively over six simulated seconds.
- Fell flat to **90° lean** with zero initial spin, as expected.

The ring has visible small contact bounces from its 20-capsule approximation and
eventually loses speed to contact losses and drag. Finite-rate integration is
approximate; these results validate the defaults over the stated windows. Keep
240 Hz when reproducing them. Changing dimensions, mass, spin, or timestep calls
for rerunning the conservation and rolling tests.

## Physics references

- [Godot 4.7 built-in Jolt](https://docs.godotengine.org/en/4.7/tutorials/physics/using_jolt_physics.html)
- [Direct body state / inertia and torque](https://docs.godotengine.org/en/4.7/classes/class_physicsdirectbodystate3d.html)
- [TorusMesh](https://docs.godotengine.org/en/4.7/classes/class_torusmesh.html)
- [CapsuleShape3D](https://docs.godotengine.org/en/4.7/classes/class_capsuleshape3d.html)
- [Godot/Jolt body setup](https://github.com/godotengine/godot/blob/4.7.2-stable/modules/jolt_physics/objects/jolt_body_3d.cpp)
- [Jolt gyro default](https://github.com/godotengine/godot/blob/4.7-stable/thirdparty/jolt_physics/Jolt/Physics/Body/BodyCreationSettings.h)
