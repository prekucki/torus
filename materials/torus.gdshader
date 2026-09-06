shader_type spatial;

varying vec3 mesh_position;

void vertex() {
	mesh_position = VERTEX;
}

void fragment() {
	// A pale segment makes the spin visible on an otherwise symmetric ring.
	float angle = atan(mesh_position.z, mesh_position.x);
	float stripe = 1.0 - smoothstep(0.10, 0.16, abs(angle));
	ALBEDO = mix(vec3(0.96, 0.23, 0.065), vec3(1.0, 0.9, 0.6), stripe);
	ROUGHNESS = 0.48;
}
