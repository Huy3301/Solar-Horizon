shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

// High-Fidelity Lunar Photometric Regolith & Multi-Scale Impact Crater Shader
// Features:
// 1. Dual-phase albedo: Titanium-rich dark Mare basalts (Oceanus Procellarum, Sea of Tranquility) vs pale anorthosite highlands
// 2. Multi-point radial ejecta ray systems (Tycho & Copernicus style ray networks)
// 3. Multi-octave impact cratering with central rebound peaks & terraced rims
// 4. Hapke opposition surge (retroreflective shadow-hiding surge when sun is behind camera)
// 5. Deep terminator micro-shadowing

uniform vec4 highland_albedo : source_color = vec4(0.74, 0.75, 0.77, 1.0);
uniform vec4 mare_basalt_albedo : source_color = vec4(0.22, 0.23, 0.25, 1.0);
uniform vec4 ejecta_ray_color : source_color = vec4(0.90, 0.92, 0.95, 1.0);
uniform float crater_frequency : hint_range(5.0, 60.0) = 22.0;
uniform float opposition_surge_intensity : hint_range(0.0, 3.0) = 1.6;
uniform vec3 sun_direction = vec3(0.707, 0.35, 0.612);

varying vec3 v_world_normal;
varying vec3 v_world_pos;
varying vec2 v_uv;

float hash_lunar(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

float noise_lunar(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash_lunar(i + vec2(0.0, 0.0)), hash_lunar(i + vec2(1.0, 0.0)), u.x),
	           mix(hash_lunar(i + vec2(0.0, 1.0)), hash_lunar(i + vec2(1.0, 1.0)), u.x), u.y);
}

float fbm_lunar(vec2 uv) {
	float total = 0.0;
	float amp = 0.5;
	for (int i = 0; i < 5; i++) {
		total += amp * noise_lunar(uv);
		uv *= 2.05;
		amp *= 0.5;
	}
	return total;
}

float crater_cell(vec2 uv) {
	vec2 g = floor(uv);
	vec2 f = fract(uv);
	float min_dist = 1.0;
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 neighbor = vec2(float(x), float(y));
			vec2 p = neighbor + vec2(hash_lunar(g + neighbor), hash_lunar(g + neighbor + vec2(5.2, 13.7))) * 0.7;
			float d = length(f - p);
			min_dist = min(min_dist, d);
		}
	}
	float rim = smoothstep(0.48, 0.38, min_dist) * smoothstep(0.24, 0.38, min_dist);
	float bowl = smoothstep(0.35, 0.0, min_dist);
	float peak = smoothstep(0.08, 0.0, min_dist) * 0.45;
	return rim * 1.5 - bowl * 0.8 + peak;
}

void vertex() {
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	v_uv = UV;
}

void fragment() {
	vec2 uv = v_uv * crater_frequency;
	
	// Multi-scale procedural crater field
	float c1 = crater_cell(uv);
	float c2 = crater_cell(uv * 2.6 + vec2(3.1, 7.4)) * 0.45;
	float c3 = crater_cell(uv * 6.8 + vec2(11.5, 19.8)) * 0.22;
	float c_micro = (noise_lunar(uv * 18.0) - 0.5) * 0.12;
	float terrain_height = c1 + c2 + c3 + c_micro;
	
	// Dark lunar maria vs pale highlands (continental scale basalt flow shapes)
	float mare_shape = fbm_lunar(v_uv * 3.2);
	float mare_mask = smoothstep(0.40, 0.56, mare_shape);
	vec3 base_color = mix(highland_albedo.rgb, mare_basalt_albedo.rgb, mare_mask);
	
	// Radial ray network 1: Tycho (South polar ray center)
	vec2 ray1_center = vec2(0.42, 0.78);
	float ray1_dist = length(v_uv - ray1_center);
	float ray1_angle = atan(v_uv.y - ray1_center.y, v_uv.x - ray1_center.x);
	float ray1_streamers = pow(abs(sin(ray1_angle * 10.0 + fbm_lunar(v_uv * 14.0) * 3.2)), 7.0);
	float ray1_intensity = ray1_streamers * exp(-ray1_dist * 3.8) * 0.95;
	
	// Radial ray network 2: Copernicus (Equatorial ray center)
	vec2 ray2_center = vec2(0.68, 0.38);
	float ray2_dist = length(v_uv - ray2_center);
	float ray2_angle = atan(v_uv.y - ray2_center.y, v_uv.x - ray2_center.x);
	float ray2_streamers = pow(abs(sin(ray2_angle * 8.0 + fbm_lunar(v_uv * 11.0) * 2.5)), 6.0);
	float ray2_intensity = ray2_streamers * exp(-ray2_dist * 4.2) * 0.82;
	
	float total_ray = clamp(ray1_intensity + ray2_intensity, 0.0, 1.0);
	base_color = mix(base_color, ejecta_ray_color.rgb, total_ray * (1.0 - mare_mask * 0.4));
	
	// Surface normal perturbation from craters
	vec3 N = normalize(v_world_normal);
	vec2 dH = vec2(
		crater_cell(uv + vec2(0.02, 0.0)) - crater_cell(uv - vec2(0.02, 0.0)),
		crater_cell(uv + vec2(0.0, 0.02)) - crater_cell(uv - vec2(0.0, 0.02))
	);
	vec3 perturbed_N = normalize(N + vec3(dH.x, 0.0, dH.y) * 0.45);
	
	// Hapke opposition surge (retroreflection at zero phase angle)
	vec3 V = normalize(CAMERA_POSITION_WORLD - v_world_pos);
	vec3 L = normalize(sun_direction);
	float cos_phase = clamp(dot(V, L), 0.0, 1.0);
	float opposition_surge = pow(cos_phase, 24.0) * opposition_surge_intensity * max(0.0, dot(perturbed_N, L));
	
	ALBEDO = base_color + ejecta_ray_color.rgb * opposition_surge * 0.35;
	ROUGHNESS = 0.92;
	METALLIC = 0.02;
	SPECULAR = 0.04;
	
	NORMAL = perturbed_N;
}
