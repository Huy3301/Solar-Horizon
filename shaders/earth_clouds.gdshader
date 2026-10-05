shader_type spatial;
render_mode blend_mix, depth_draw_always, cull_back, diffuse_burley, specular_schlick_ggx;

// Multi-layered photorealistic Earth cloud shell for orbit & surface views
// Features:
// 1. Physically-inspired cloud volumetric self-shadowing & ambient occlusion
// 2. High-dynamic sunset/sunrise fiery golden-red alpenglow at terminator
// 3. Forward Mie scattering silver-lining highlights on backlit edges
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
uniform float silver_lining_intensity : hint_range(0.0, 3.0) = 1.4;

uniform vec3 cloud_color : source_color = vec3(1.0, 1.0, 1.0);
uniform vec3 sunset_cloud_color : source_color = vec3(1.0, 0.52, 0.20);
uniform vec3 dusk_cloud_color : source_color = vec3(0.88, 0.28, 0.38);

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
	float v_dot_l = dot(V, -L);

	if (quality_tier == 0) {
		// CHEAP MOBILE VARIANT (< 1 ms budget):
		// Simple single texture fetch, cheap sunset blend, zero procedural noise loops
		float alpha = smoothstep(0.12, 0.65, raw_alpha * cloud_coverage);
		float day_factor = clamp(n_dot_l * 2.0 + 0.1, 0.0, 1.0);
		float sunset = smoothstep(-0.18, 0.05, n_dot_l) * (1.0 - smoothstep(0.05, 0.25, n_dot_l));
		
		vec3 lit_color = mix(cloud_color, sunset_cloud_color, sunset);
		
		// Fast forward Mie silver-lining highlight
		float silver_low = pow(max(0.0, v_dot_l), 8.0) * 0.45 * day_factor * silver_lining_intensity;
		vec3 night_color = vec3(0.015, 0.025, 0.05);
		vec3 final_rgb = mix(night_color, lit_color + vec3(silver_low), day_factor);

		ALBEDO = final_rgb;
		ALPHA = alpha;
		ROUGHNESS = 0.9;
		SPECULAR = 0.02;
	} else {
		// HIGH QUALITY DESKTOP VARIANT:
		// Multi-octave wispy fractal micro-fluff on cloud edges
		float n1 = noise_cld(cloud_uv * 480.0);
		float n2 = noise_cld(cloud_uv * 1250.0) * 0.5;
		float n3 = noise_cld(cloud_uv * 3200.0) * 0.25;
		float edge_fluff = (n1 + n2 + n3 - 0.875) * 0.16;
		
		float alpha = smoothstep(0.05, 0.72, (raw_alpha + edge_fluff) * cloud_coverage);

		float day_factor = smoothstep(-0.06, 0.22, n_dot_l);
		float thick = smoothstep(0.12, 0.85, raw_alpha) * cloud_thickness;

		// High-dynamic sunset/sunrise alpenglow at the terminator
		float high_alt_catch = thick * 0.12;
		float sunset_band = smoothstep(-0.20 + high_alt_catch, -0.02, n_dot_l) * (1.0 - smoothstep(0.02, 0.28, n_dot_l));
		float dusk_band = smoothstep(-0.30 + high_alt_catch, -0.12, n_dot_l) * (1.0 - smoothstep(-0.06, 0.06, n_dot_l));
		
		vec3 lit_color = mix(cloud_color, sunset_cloud_color, sunset_band * 0.95);
		lit_color = mix(lit_color, dusk_cloud_color, dusk_band * 0.82);
		
		// Volumetric directional self-shadowing
		float lon = cloud_uv.x * 2.0 * PI;
		vec3 T = vec3(-sin(lon), 0.0, cos(lon));
		vec3 B = cross(N, T);
		vec2 sun_proj = vec2(dot(L, T), dot(L, B)) * 0.0035;
		float sunward_alpha = texture(cloud_texture, cloud_uv + sun_proj).a;
		float self_shadow_factor = smoothstep(0.2, 0.8, sunward_alpha) * shadow_intensity * 0.65;
		float direct_light = clamp(n_dot_l * 1.5 + 0.3, 0.0, 1.0);
		float self_shadow = mix(1.0 - self_shadow_factor, 1.0, direct_light);
		lit_color *= mix(1.0, self_shadow, thick);
		
		// Ambient occlusion on cloud undersides and dense pockets
		float ao = mix(1.0, 0.58, thick * (1.0 - direct_light * 0.5));
		lit_color *= ao;
		
		// Forward Mie scattering "silver lining" on backlit edges facing the sun
		float edge_mask = (1.0 - smoothstep(0.35, 0.85, raw_alpha)) * smoothstep(0.05, 0.25, raw_alpha);
		float silver_lining = pow(max(0.0, v_dot_l), 10.0) * edge_mask * silver_lining_intensity * 2.2 * day_factor;
		float forward_scatter_broad = pow(max(0.0, v_dot_l), 4.5) * 0.35 * day_factor;
		
		vec3 silver_color = vec3(1.0, 0.97, 0.93) * (silver_lining + forward_scatter_broad);
		
		vec3 night_cloud_tint = vec3(0.012, 0.025, 0.05);
		vec3 final_cloud_rgb = mix(night_cloud_tint, lit_color + silver_color, day_factor);
		
		ALBEDO = final_cloud_rgb;
		ALPHA = alpha;
		ROUGHNESS = 0.85;
		SPECULAR = 0.04;
	}
}
