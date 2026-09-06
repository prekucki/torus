class_name TorusBody
extends RigidBody3D
## Phase 1: a free rigid body; no player controls or balance assists.
## Local +X is the axle; the ring lies in the local YZ plane.

@export_group("Geometry (restart after editing)")
@export_range(0.1, 5.0, 0.01) var major_radius: float = 1.0
@export_range(0.02, 1.0, 0.01) var minor_radius: float = 0.25
@export_range(12, 64, 1) var capsule_count: int = 20

@export_group("Physics")
@export var manual_gyroscope: bool = true
@export_range(0.0, 1.0, 0.001) var angular_damping: float = 0.0
@export_range(0.0, 1.0, 0.001) var linear_damping: float = 0.01
@export_range(0.0, 1.0, 0.01) var surface_friction: float = 0.8

@export_group("Repeatable experiment (restart after editing)")
@export_range(0.0, 40.0, 0.1) var initial_spin: float = 24.0
@export var automatic_nudge: bool = true
@export_range(0.1, 10.0, 0.1) var nudge_after_seconds: float = 2.0
@export_range(-10.0, 10.0, 0.05) var nudge_impulse: float = 8.0

var elapsed: float = 0.0
var lean_degrees: float = 0.0
var heading_radians: float = 0.0
var spin_rate: float = 0.0
var contact_count: int = 0
var gyroscopic_torque := Vector3.ZERO
var has_nudged: bool = false
var _initialized: bool = false


func _ready() -> void:
	assert(minor_radius < major_radius, "The torus hole requires minor_radius < major_radius.")
	mass = 3.0
	can_sleep = false
	continuous_cd = true
	contact_monitor = true
	max_contacts_reported = 16
	linear_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	angular_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	physics_material_override = PhysicsMaterial.new()
	physics_material_override.bounce = 0.0
	_build_ring()


func _build_ring() -> void:
	# Each capsule joins adjacent points on the major circle. Overlapping round
	# ends keep the compound continuous; the hole remains genuinely hollow.
	for index in range(capsule_count):
		var angle_a := TAU * float(index) / capsule_count
		var angle_b := TAU * float(index + 1) / capsule_count
		var point_a := Vector3(0.0, cos(angle_a), sin(angle_a)) * major_radius
		var point_b := Vector3(0.0, cos(angle_b), sin(angle_b)) * major_radius
		var chord := point_b - point_a
		var capsule := CapsuleShape3D.new()
		capsule.radius = minor_radius
		# Godot capsule height includes both hemispheres.
		capsule.height = chord.length() + 2.0 * minor_radius
		var collision := CollisionShape3D.new()
		collision.name = "RingCapsule%02d" % index
		collision.shape = capsule
		collision.position = (point_a + point_b) * 0.5
		collision.basis = Basis(Quaternion(Vector3.UP, chord.normalized()))
		add_child(collision)

	var mesh := TorusMesh.new()
	# TorusMesh uses hole/outer radii, not major/tube radii.
	mesh.inner_radius = major_radius - minor_radius
	mesh.outer_radius = major_radius + minor_radius
	mesh.rings = 96
	mesh.ring_segments = 24
	var visual := MeshInstance3D.new()
	visual.name = "TorusMesh"
	visual.mesh = mesh
	visual.rotation.z = PI * 0.5
	var material := ShaderMaterial.new()
	material.shader = preload("res://materials/torus.gdshader")
	visual.material_override = material
	add_child(visual)


func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	linear_damp = linear_damping
	angular_damp = angular_damping
	physics_material_override.friction = surface_friction
	var orientation := state.transform.basis.orthonormalized()
	var axle := orientation.x
	if not _initialized:
		# One launch impulse supplies angular momentum Iω about the ring axle.
		# No velocity assignment: ground friction subsequently produces rolling.
		var world_inertia := state.inverse_inertia_tensor.inverse()
		state.apply_torque_impulse(world_inertia * (axle * initial_spin))
		_initialized = true

	elapsed += state.step
	if automatic_nudge and not has_nudged and elapsed >= nudge_after_seconds:
		# One angular impulse about the forward axis tips the axle out of level.
		# There is no continuing steering or righting force after this nudge.
		var lean_axis := axle.cross(Vector3.UP).normalized()
		state.apply_torque_impulse(lean_axis * nudge_impulse)
		has_nudged = true

	gyroscopic_torque = Vector3.ZERO
	if manual_gyroscope:
		_apply_gyroscopic_torque(state, orientation)

	lean_degrees = rad_to_deg(asin(clampf(axle.dot(Vector3.UP), -1.0, 1.0)))
	heading_radians = atan2(-axle.z, axle.x)
	spin_rate = state.angular_velocity.dot(axle)
	contact_count = state.get_contact_count()


func _apply_gyroscopic_torque(state: PhysicsDirectBodyState3D, orientation: Basis) -> void:
	# Recover the full local tensor from Jolt's world inverse tensor, including
	# any principal-axis rotation, then I_world = B * I_local * Bᵀ.
	var local_inverse := orientation.transposed() * state.inverse_inertia_tensor * orientation
	var local_inertia := local_inverse.inverse()
	var world_inertia := orientation * local_inertia * orientation.transposed()
	var omega := state.angular_velocity
	# Euler gyroscopic term: τ_gyro = -ω × (I_world ω).
	# Evaluate it at the implicit midpoint: raw forward Euler artificially adds
	# rotational energy. Six fixed-point iterations converge at this scene's
	# 240 Hz and spin range. This changes only the torque's numerical integration.
	var midpoint_omega := omega
	for iteration in range(6):
		var midpoint_torque := -midpoint_omega.cross(world_inertia * midpoint_omega)
		midpoint_omega = omega + state.inverse_inertia_tensor * midpoint_torque * (state.step * 0.5)
	gyroscopic_torque = -midpoint_omega.cross(world_inertia * midpoint_omega)
	state.apply_torque(gyroscopic_torque)
