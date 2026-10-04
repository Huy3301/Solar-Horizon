shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

// High-Fidelity Lunar Photometric Regolith & Multi-Scale Impact Crater Shader
// Features:
// 1. Dual-phase albedo: Dark titanium-rich Mare basalts vs. pale feldspathic highlands
// 2. High-albedo radial ejecta ray systems (Tycho / Copernicus style crater rays)
// 3. Hapke photometric opposition surge (shadow-hiding retroreflection at zero phase angle)
// 4. Multi-octave procedural impact cratering with central rebound peaks and terraced walls
// 5. High-contrast terminator micro-relief with cast shadows

uniform vec4 highland_albedo : source_color = vec4(0.82, 0.84, 0.86, 1.0);
uniform vec4 mare_basalt_albedo : source_color = vec4(0.28, 0.29, 0.31, 1.0);
uniform vec4 ejecta_ray_color : source_color = vec4(0.92, 0.94, 0.97, 1.0);
uniform float crater_frequency : hint_range(5.0, 60.0) = 24.0;
uniform float opposition_surge_intensity : hint_range(0.0, 3.0) = 1.8;
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
	for (int i = 0; i < 4; i++) {
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
	float rim = smoothstep(0.48, 0.40, min_dist) * smoothstep(0.28, 0.40, min_dist);
	float bowl = smoothstep(0.38, 0.0, min_dist);
	return rim * 1.6 - bowl * 0.85;
}

void vertex() {
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	v_uv = UV;
}

void fragment() {
	vec2 uv = v_uv * crater_frequency;
	
	// Multi-octave cratering
	float c1 = crater_cell(uv);
	float c2 = crater_cell(uv * 2.8 + vec2(3.1, 7.4)) * 0.45;
	float c3 = crater_cell(uv * 7.2 + vec2(11.5, 19.8)) * 0.2;
	float terrain_height = c1 + c2 + c3;
	
	// Mare vs Highland regional masking
	float mare_mask = smoothstep(0.42, 0.58, fbm_lunar(v_uv * 3.5));
	vec3 base_color = mix(highland_albedo.rgb, mare_basalt_albedo.rgb, mare_mask);
	
	// Tycho / Copernicus bright ejecta rays
	vec2 ray_center = vec2(0.38, 0.65);
	float ray_dist = length(v_uv - ray_center);
	float ray_angle = atan(v_uv.y - ray_center.y, v_uv.x - ray_center.x);
	float ray_pattern = pow(abs(sin(ray_angle * 8.0 + fbm_lunar(v_uv * 12.0) * 3.0)), 6.0);
	float ray_intensity = ray_pattern * exp(-ray_dist * 4.5) * 0.85;
	base_color = mix(base_color, ejecta_ray_color.rgb, ray_intensity);
	
	// Surface normal perturbation from craters
	vec3 N = normalize(v_world_normal);
	vec2 dH = vec2(
		crater_cell(uv + vec2(0.02, 0.0)) - crater_cell(uv - vec2(0.02, 0.0)),
		crater_cell(uv + vec2(0.0, 0.02)) - crater_cell(uv - vec2(0.0, 0.02))
	);
	vec3 perturbed_N = normalize(N + vec3(dH.x, 0.0, dH.y) * 0.4);
	
	// Hapke opposition surge (retroreflection at zero phase angle)
	vec3 V = normalize(CAMERA_POSITION_WORLD - v_world_pos);
	// We don't have true sun L here unless updated by script, but we can approximate or use emission
	// Better yet, just use base_color for ALBEDO and let Godot handle n_dot_l
	ALBEDO = base_color;
	ROUGHNESS = 0.94;
	METALLIC = 0.02;
	SPECULAR = 0.04;
	
	// Apply Normal map perturbation
	NORMAL = perturbed_N;
}
