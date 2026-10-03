shader_type spatial;
render_mode blend_add, depth_draw_never, cull_front, unshaded;

// Photorealistic Earth atmospheric scattering shell for Low Earth Orbit (LEO)
uniform vec3 sun_direction = vec3(0.707, 0.35, 0.612);
uniform vec3 rayleigh_day_color : source_color = vec3(0.18, 0.6, 1.0);
uniform vec3 rayleigh_sunset_color : source_color = vec3(1.0, 0.45, 0.12);
uniform vec3 airglow_green_color : source_color = vec3(0.12, 0.95, 0.45);
uniform float atmosphere_density : hint_range(0.1, 5.0) = 2.4;
uniform float rim_falloff_power : hint_range(0.5, 10.0) = 3.8;
uniform float mie_phase_strength : hint_range(0.0, 3.0) = 1.8;
uniform float airglow_intensity : hint_range(0.0, 1.0) = 0.32;

varying vec3 v_world_normal;
varying vec3 v_world_pos;

void vertex() {
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_world_normal = normalize((MODEL_MATRIX * vec4(-NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 V = normalize(CAMERA_POSITION_WORLD - v_world_pos);
	vec3 N = normalize(v_world_normal);
	vec3 L = normalize(sun_direction);

	float v_dot_n = clamp(dot(V, N), 0.0, 1.0);
	float rim = pow(1.0 - v_dot_n, rim_falloff_power);
	
	float n_dot_l = dot(N, L);
	float v_dot_l = dot(V, L);
	
	float day_weight = smoothstep(-0.05, 0.35, n_dot_l);
	float sunset_weight = smoothstep(-0.25, -0.02, n_dot_l) * (1.0 - smoothstep(0.0, 0.25, n_dot_l));
	float night_weight = 1.0 - smoothstep(-0.20, 0.10, n_dot_l);
	
	vec3 scatter_color = mix(rayleigh_day_color, rayleigh_sunset_color, sunset_weight);
	float mie_glow = pow(max(0.0, v_dot_l), 12.0) * mie_phase_strength * (day_weight + sunset_weight * 1.5);
	
	// Airglow thin ribbon at grazing angle
	float airglow_rim = pow(1.0 - v_dot_n, 9.0) * airglow_intensity;
	vec3 airglow = airglow_green_color * airglow_rim * (0.4 + 0.6 * night_weight);
	
	vec3 final_color = scatter_color * rim * atmosphere_density * (day_weight + sunset_weight * 1.8);
	final_color += vec3(1.0, 0.95, 0.85) * mie_glow * rim;
	final_color += airglow;
	
	ALBEDO = final_color;
}
