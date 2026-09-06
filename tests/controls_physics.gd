extends SceneTree
## Headless controls regressions using real Jolt bodies and additive inputs.

class Probe extends TorusBody:
	var seed_impulse := Vector3.ZERO
	var seeded: bool = false
	var inverse_tensor := Basis.IDENTITY
	var tick_step: float = 0.0
	var press_hop: bool = false
	var _release_hop: bool = false

	func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
		if _release_hop:
			Input.action_release("hop")
		_release_hop = press_hop
		if press_hop:
			# action_press schedules just_pressed for the following physics tick;
			# tests await both injection and consumption, independent of rendering.
			Input.action_press("hop")
			press_hop = false
		if not seeded:
			# Test launch supplies momentum through the same impulse API as hop.
			state.apply_central_impulse(seed_impulse)
			seeded = true
		inverse_tensor = state.inverse_inertia_tensor
		tick_step = state.step
		super._integrate_forces(state)

var _failures: int = 0
var _checks: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	TorusInput.install_actions()
	var version := Engine.get_version_info()
	_check(version.major == 4 and version.minor == 7, "Godot 4.7.x")
	_check(ProjectSettings.get_setting("physics/3d/physics_engine") == "Jolt Physics", "Jolt backend")
	await _test_acceleration()
	await _test_brakes()
	await _test_lean()
	await _test_hop()
	await _test_wall_contact()
	await _test_reset()
	_release_inputs()
	print("CONTROLS PHYSICS %s checks=%d failures=%d" % [
		"PASS" if _failures == 0 else "FAIL", _checks, _failures])
	quit(0 if _failures == 0 else 1)


func _check(condition: bool, description: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error("FAIL: " + description)
	else:
		print("PASS: " + description)


func _release_inputs() -> void:
	for action in TorusInput.ACTIONS:
		Input.action_release(action)


func _body(spin: float = 0.0, orientation: Basis = Basis.IDENTITY) -> Probe:
	_release_inputs()
	var body := Probe.new()
	body.controls_enabled = true
	body.automatic_nudge = false
	body.manual_gyroscope = false
	body.initial_spin = spin
	body.gravity_scale = 0.0
	body.linear_damping = 0.0
	body.angular_damping = 0.0
	body.surface_friction = 0.0
	body.tuning.rumble_enabled = false
	body.position = Vector3(0, 10, 0)
	body.basis = orientation
	root.add_child(body)
	await body.physics_sampled
	return body


func _ticks(body: Probe, count: int) -> Dictionary:
	for tick in range(count):
		await body.physics_sampled
	return body.last_sample


func _dispose(body: Probe) -> void:
	_release_inputs()
	body.queue_free()
	await process_frame


func _drive_delta(strength: float, brake: float = 0.0) -> float:
	var body := await _body(6.0)
	Input.action_press("accelerate", strength)
	if brake > 0.0:
		Input.action_press("brake", brake)
	var start := await _ticks(body, 1)
	var finish := await _ticks(body, 60)
	var torque := body.tuning.acceleration_torque * strength - body.tuning.braking_torque * brake
	_check((finish.input_torque as Vector3).is_equal_approx(Vector3.RIGHT * torque),
		"axle torque follows independent accel %.2f / brake %.2f strengths" % [strength, brake])
	var delta: float = finish.spin_rate - start.spin_rate
	var expected := torque * body.inverse_tensor.x.x * body.tick_step * 60.0
	_check(absf(delta - expected) < 0.002, "actual spin change matches torque / inertia integration")
	_check((finish.angular_velocity as Vector3).is_finite(), "accelerating state stays finite")
	await _dispose(body)
	return delta


func _test_acceleration() -> void:
	var full := await _drive_delta(1.0)
	var quarter := await _drive_delta(0.25)
	_check(absf(full - quarter * 4.0) < 0.002, "quarter trigger produces quarter spin acceleration")
	await _drive_delta(0.7, 0.2)


func _test_brakes() -> void:
	for spin in [2.0, -2.0, 0.0001, -0.0001, 0.0]:
		var body := await _body(spin)
		Input.action_press("brake", 1.0)
		var minimum := INF
		var maximum := -INF
		for tick in range(150):
			var sample := await _ticks(body, 1)
			minimum = minf(minimum, sample.spin_rate)
			maximum = maxf(maximum, sample.spin_rate)
		var kept_sign: bool = minimum >= -0.00001 if spin >= 0.0 else maximum <= 0.00001
		_check(kept_sign, "brake never reverses initial spin %.5f" % spin)
		_check(absf(body.spin_rate) < 0.0001, "brake reaches rest from spin %.5f" % spin)
		await _dispose(body)
	var together := await _body(0.0001)
	Input.action_press("accelerate", 0.2)
	Input.action_press("brake", 1.0)
	var result := await _ticks(together, 1)
	_check((result.input_torque as Vector3).x < 0.0,
		"brake cap accounts for simultaneous acceleration near zero")
	await _dispose(together)
	var stopped := await _body()
	Input.action_press("accelerate", 0.5)
	Input.action_press("brake", 1.0)
	var held := await _ticks(stopped, 60)
	_check(absf(held.spin_rate) < 0.00001 and (held.input_torque as Vector3).is_zero_approx(),
		"simultaneous triggers keep a stopped ring still when brake exceeds drive")
	await _dispose(stopped)


func _test_lean() -> void:
	for yaw in [0.0, PI * 0.5]:
		# Steering relies on gyroscopic precession: the torque acts about the
		# ring's in-plane up axis and the spinning ring answers by rolling
		# about the travel axis instead of yawing.
		var body := await _body(12.0, Basis(Vector3.UP, yaw))
		body.manual_gyroscope = true
		Input.action_press("lean_right", 1.0)
		var sample := await _ticks(body, 1)
		var axle: Vector3 = sample.spin_axis
		var travel := axle.cross(Vector3.UP).normalized()
		var expected := travel.cross(axle).normalized() * body.tuning.lean_torque
		_check((sample.input_torque as Vector3).is_equal_approx(expected),
			"steering torque acts about the ring's in-plane up axis at yaw %.0f" % rad_to_deg(yaw))
		var start_heading: float = body.heading_radians
		var after := await _ticks(body, 60)
		var camera_right := travel.cross(Vector3.UP).normalized()
		var top := Vector3.UP.slide(after.spin_axis).normalized()
		var heading_change := absf(rad_to_deg(angle_difference(start_heading, body.heading_radians)))
		_check(after.lean_degrees > 0.5 and top.dot(camera_right) > 0.0,
			"ring rolls about the travel axis toward camera-right (lean %.2f deg)" % after.lean_degrees)
		# The instantaneous lean rate nutates around the precession rate, so the
		# accumulated lean angle above is the robust measure of the roll.
		_check(heading_change < after.lean_degrees * 0.25,
			"lean input does not yaw the axle (heading change %.2f deg)" % heading_change)
		await _dispose(body)


func _test_hop() -> void:
	var floor := StaticBody3D.new()
	floor.position.y = -0.5
	var collider := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(100, 1, 100)
	collider.shape = shape
	floor.add_child(collider)
	root.add_child(floor)
	var body := await _body()
	body.gravity_scale = 1.0
	body.manual_gyroscope = true
	body.set_checkpoint(Transform3D(Basis.IDENTITY, Vector3(0, 1.28, 0)))
	body.request_reset()
	await _ticks(body, 2)
	for tick in range(240):
		if body.grounded:
			break
		await _ticks(body, 1)
	await _ticks(body, 24)
	_check(body.grounded, "real floor contact permits hop")
	var world_contacts: bool = not body.last_sample.contacts.is_empty()
	var tangent_traction: bool = world_contacts
	for contact: Dictionary in body.last_sample.contacts:
		world_contacts = world_contacts and (contact.normal as Vector3).dot(Vector3.UP) > 0.99 \
			and absf((contact.position as Vector3).y) < 0.03
		tangent_traction = tangent_traction and absf((contact.traction as Vector3).dot(contact.normal)) < 0.0001
	_check(world_contacts, "floor contact points and normals use world coordinates")
	_check(tangent_traction, "support traction excludes the normal contact impulse")
	_check(body.last_sample.slip_ratio < 0.001, "resting ring has negligible contact slip")
	body.press_hop = true
	var hop := await _ticks(body, 2)
	_check((hop.linear_velocity as Vector3).y > 2.5, "ground hop adds upward momentum")
	body.press_hop = true
	var immediately := await _ticks(body, 2)
	_check((immediately.linear_velocity as Vector3).y <= (hop.linear_velocity as Vector3).y + 0.01,
		"immediate hop repress cannot reuse a stale ground contact")
	await _ticks(body, 6)
	_check(not body.grounded, "hop leaves the real floor")
	var previous_y: float = body.last_sample.linear_velocity.y
	for attempt in range(4):
		body.press_hop = true
		var airborne := await _ticks(body, 2)
		_check((airborne.linear_velocity as Vector3).y <= previous_y + 0.01,
			"airborne hop repress %d adds no impulse" % attempt)
		previous_y = airborne.linear_velocity.y
		await _ticks(body, 1)
	for tick in range(300):
		if body.grounded:
			break
		await _ticks(body, 1)
	_check(body.grounded, "hop returns to ground")
	_check((body.last_sample.linear_velocity as Vector3).y < 1.0,
		"airborne requests do not queue another hop on landing")
	body.press_hop = true
	var second := await _ticks(body, 2)
	_check((second.linear_velocity as Vector3).y > 2.5, "landing rearms hop")
	await _dispose(body)
	floor.queue_free()
	await process_frame


func _test_wall_contact() -> void:
	var wall := StaticBody3D.new()
	wall.position = Vector3(0.75, 10, 0)
	var collider := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(0.5, 100, 100)
	collider.shape = shape
	wall.add_child(collider)
	root.add_child(wall)
	var body := await _body()
	body.seeded = false
	body.seed_impulse = Vector3(3, 0, 0)
	for tick in range(120):
		await _ticks(body, 1)
		if body.contact_count > 0:
			break
	_check(body.contact_count > 0, "real wall produces rigid-body contacts")
	_check(not body.grounded and body.last_sample.contacts.is_empty(),
		"wall-only contacts do not count as ground support")
	var before_y: float = body.last_sample.linear_velocity.y
	body.press_hop = true
	var sample := await _ticks(body, 2)
	_check(body.contact_count > 0 and not sample.grounded, "hop is evaluated while touching only wall")
	_check(absf((sample.linear_velocity as Vector3).y - before_y) < 0.0001,
		"wall-only hop request adds no upward momentum")
	await _dispose(body)
	wall.queue_free()
	await process_frame


func _test_reset() -> void:
	var body := await _body(12.0)
	body.seeded = false
	body.seed_impulse = Vector3(21, 9, -15)
	Input.action_press("lean_right")
	await _ticks(body, 30)
	_check(body.last_sample.speed > 1.0, "reset test starts with linear momentum")
	var checkpoint := Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(20, 8, -12))
	body.set_checkpoint(checkpoint)
	_release_inputs()
	body.request_reset()
	var reset := await _ticks(body, 1)
	_check((reset.origin as Vector3).is_equal_approx(checkpoint.origin), "reset relocates to checkpoint")
	_check((reset.spin_axis as Vector3).is_equal_approx(checkpoint.basis.x), "reset restores checkpoint heading")
	_check((reset.linear_velocity as Vector3).length() < 0.0001, "reset impulses cancel linear momentum")
	_check((reset.angular_velocity as Vector3).length() < 0.0001, "reset impulses cancel angular momentum")
	_check((reset.input_torque as Vector3).is_zero_approx(), "reset clears player torque")
	_check(not reset.grounded and reset.contacts.is_empty(), "reset clears stale contacts")
	var launched := await _ticks(body, 1)
	_check(absf(launched.spin_rate - 12.0) < 0.001, "next tick launches along checkpoint axle")
	_check((launched.linear_velocity as Vector3).length() < 0.0001, "reset launch preserves cancelled linear momentum")
	await _dispose(body)
