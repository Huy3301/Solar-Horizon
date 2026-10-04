shader_type spatial;
render_mode blend_mix, depth_draw_always, cull_back, diffuse_burley, specular_schlick_ggx;

// Multi-layered realistic Earth cloud shell for Low Earth Orbit (LEO)
// Features:
// 1. Physically-inspired cloud volumetric self-shadowing & ambient occlusion
// 2. High-dynamic sunset/sunrise fiery golden-red scattering at terminator
// 3. Forward Mie scattering silver-lining highlights
// 4. Procedural multi-frequency wispy fractal micro-fluff on cloud edges

uniform sampler2D cloud_texture : source_color, filter_linear_mipmap, repeat_enable;
uniform vec3 sun_direction = vec3(0.707, 0.35, 0.612);
uniform float cloud_coverage : hint_range(0.0, 2.0) = 1.05;
uniform float cloud_rotation : hint_range(-6.28318, 6.28318) = 0.0;
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
	
	// Multi-octave wispy edge noise for photorealistic cloud boundaries
	float n1 = noise_cld(cloud_uv * 450.0);
	float n2 = noise_cld(cloud_uv * 1200.0) * 0.5;
	float edge_fluff = (n1 + n2 - 0.75) * 0.14;
	
	float raw_alpha = cloud_sample.a;
	float alpha = smoothstep(0.06, 0.72, (raw_alpha + edge_fluff) * cloud_coverage);
	
	vec3 N = normalize(v_world_normal);
	vec3 L = normalize(sun_direction);
	vec3 V = normalize(CAMERA_POSITION_WORLD - v_world_pos);
	
	float n_dot_l = dot(N, L);
	float day_factor = smoothstep(-0.06, 0.22, n_dot_l);
	
	// Sunset & twilight cloud illumination (ISS golden-hour clouds)
	float sunset_band = smoothstep(-0.16, -0.02, n_dot_l) * (1.0 - smoothstep(0.01, 0.28, n_dot_l));
	float dusk_band = smoothstep(-0.25, -0.10, n_dot_l) * (1.0 - smoothstep(-0.05, 0.05, n_dot_l));
	vec3 lit_color = mix(cloud_color, sunset_cloud_color, sunset_band * 0.95);
	lit_color = mix(lit_color, dusk_cloud_color, dusk_band * 0.75);
	
	// Volumetric cloud self-shadowing (thicker parts receive self-shadowing)
	float cloud_thickness = smoothstep(0.15, 0.85, raw_alpha);
	float self_shadow = mix(0.62, 1.0, clamp(n_dot_l * 1.5 + 0.3, 0.0, 1.0));
	lit_color *= mix(1.0, self_shadow, cloud_thickness);
	
	// Forward Mie scattering (brilliant silver lining when looking into the sun)
	float v_dot_l = dot(V, -L);
	float forward_scatter = pow(max(0.0, v_dot_l), 8.0) * 0.48 * day_factor;
	
	// Night side faint moonlight/starlight tint
	vec3 night_cloud_tint = vec3(0.012, 0.025, 0.05);
	vec3 final_cloud_rgb = mix(night_cloud_tint, lit_color + vec3(forward_scatter), day_factor);
	
	ALBEDO = final_cloud_rgb;
	ALPHA = alpha;
	ROUGHNESS = 0.85;
	SPECULAR = 0.04;
}
