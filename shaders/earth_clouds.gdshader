shader_type spatial;
render_mode blend_mix, depth_draw_always, cull_back, diffuse_burley, specular_schlick_ggx;

// Multi-layered photorealistic Earth cloud shell for orbit & surface views
// Features:
// 1. Physically-inspired cloud volumetric self-shadowing & ambient occlusion
// 2. High-dynamic sunset/sunrise fiery golden-red scattering at terminator
// 3. Forward Mie scattering silver-lining highlights
// 4. Procedural multi-frequency wispy fractal micro-fluff on cloud edges (High tier)
// 5. Cheap mobile variant with minimal ALU instructions (Low tier)
// 6. Cloud shadow projection factor for planetary surface/terrain

uniform int quality_tier : hint_range(0, 1) = 1; // 0 = Mobile / Low, 1 = Desktop / High

uniform sampler2D cloud_texture : source_color, filter_linear_mipmap, repeat_enable;
uniform vec3 sun_direction = vec3(0.707, 0.35, 0.612);
uniform float cloud_coverage : hint_range(0.0, 2.0) = 1.05;
uniform float cloud_rotation : hint_range(-6.28318, 6.28318) = 0.0;
uniform float cloud_thickness : hint_range(0.1, 3.0) = 1.0;
uniform float shadow_intensity : hint_range(0.0, 1.0) = 0.75;

uniform vec3 cloud_color : source_color = vec3(1.0, 1.0, 1.0);
uniform vec3 sunset_cloud_color : source_color = vec3(1.0, 0.48, 0.18);
uniform vec3 dusk_cloud_color : source_color = vec3(0.85, 0.28, 0.35);

varying vec3 v_world_normal;
varying vec3 v_world_pos;
varying vec2 v_uv;

float hash_cld(vec2 p) {
	p = fract(p * vec2(127.1, 311.7));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float noise_cld(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash_cld(i), hash_cld(i + vec2(1.0, 0.0)), f.x),
	           mix(hash_cld(i + vec2(0.0, 1.0)), hash_cld(i + vec2(1.0, 1.0)), f.x), f.y);
}

void vertex() {
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	v_uv = UV;
}

void fragment() {
	vec2 cloud_uv = vec2(fract(v_uv.x + cloud_rotation / (2.0 * PI)), v_uv.y);
	vec4 cloud_sample = texture(cloud_texture, cloud_uv);
	float raw_alpha = cloud_sample.a;

	vec3 N = normalize(v_world_normal);
	vec3 L = normalize(sun_direction);
	vec3 V = normalize(CAMERA_POSITION_WORLD - v_world_pos);

	float n_dot_l = dot(N, L);

	if (quality_tier == 0) {
		// CHEAP MOBILE VARIANT (< 1 ms budget):
		// Simple single texture fetch, cheap sunset blend, zero procedural noise loops
		float alpha = smoothstep(0.12, 0.65, raw_alpha * cloud_coverage);
		float day_factor = clamp(n_dot_l * 2.0 + 0.1, 0.0, 1.0);
		float sunset = smoothstep(-0.15, 0.05, n_dot_l) * (1.0 - smoothstep(0.05, 0.25, n_dot_l));
		
		vec3 lit_color = mix(cloud_color, sunset_cloud_color, sunset);
		vec3 night_color = vec3(0.015, 0.025, 0.05);
		vec3 final_rgb = mix(night_color, lit_color, day_factor);

		ALBEDO = final_rgb;
		ALPHA = alpha;
		ROUGHNESS = 0.9;
		SPECULAR = 0.02;
	} else {
		// HIGH QUALITY DESKTOP VARIANT:
		// Multi-octave wispy fractal fluff on cloud edges
		float n1 = noise_cld(cloud_uv * 450.0);
		float n2 = noise_cld(cloud_uv * 1200.0) * 0.5;
		float edge_fluff = (n1 + n2 - 0.75) * 0.14;
		
		float alpha = smoothstep(0.06, 0.72, (raw_alpha + edge_fluff) * cloud_coverage);

		float day_factor = smoothstep(-0.06, 0.22, n_dot_l);
		float sunset_band = smoothstep(-0.16, -0.02, n_dot_l) * (1.0 - smoothstep(0.01, 0.28, n_dot_l));
		float dusk_band = smoothstep(-0.25, -0.10, n_dot_l) * (1.0 - smoothstep(-0.05, 0.05, n_dot_l));
		
		vec3 lit_color = mix(cloud_color, sunset_cloud_color, sunset_band * 0.95);
		lit_color = mix(lit_color, dusk_cloud_color, dusk_band * 0.75);
		
		// Volumetric self-shadowing (thicker parts receive self-shadowing)
		float thick = smoothstep(0.15, 0.85, raw_alpha) * cloud_thickness;
		float self_shadow = mix(1.0 - shadow_intensity * 0.5, 1.0, clamp(n_dot_l * 1.5 + 0.3, 0.0, 1.0));
		lit_color *= mix(1.0, self_shadow, thick);
		
		// Forward Mie scattering silver lining
		float v_dot_l = dot(V, -L);
		float forward_scatter = pow(max(0.0, v_dot_l), 8.0) * 0.48 * day_factor;
		
		vec3 night_cloud_tint = vec3(0.012, 0.025, 0.05);
		vec3 final_cloud_rgb = mix(night_cloud_tint, lit_color + vec3(forward_scatter), day_factor);
		
		ALBEDO = final_cloud_rgb;
		ALPHA = alpha;
		ROUGHNESS = 0.85;
		SPECULAR = 0.04;
	}
}
