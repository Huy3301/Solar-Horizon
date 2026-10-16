shader_type spatial;
render_mode cull_back, depth_draw_opaque;

// S2c Debug Views: 0 = Lit Terrain, 1 = World Normals, 2 = Normalized Height, 3 = Patch ID, 4 = Slope & Grid
uniform int debug_view_mode : hint_range(0, 4) = 0;

uniform sampler2D height_tex : filter_nearest, repeat_disable;
uniform bool use_height_tex = true;
uniform float patch_size_m = 2000.0;
uniform float max_relief_m = 3500.0;
uniform float skirt_depth_m = 24.0;
uniform float morph_factor : hint_range(0.0, 1.0) = 0.0;
uniform vec3 patch_origin_local = vec3(0.0);
uniform vec3 planet_center_local = vec3(0.0, -637100.0, 0.0);
uniform vec3 sun_direction_world = vec3(0.35, 0.85, 0.39);
uniform vec3 patch_debug_color = vec3(0.25, 0.65, 0.90);

uniform vec3 col_deep_basalt : source_color = vec3(0.16, 0.18, 0.21);
uniform vec3 col_coastal_sand : source_color = vec3(0.74, 0.68, 0.50);
uniform vec3 col_lowland_grass : source_color = vec3(0.23, 0.43, 0.17);
uniform vec3 col_highland_shrub : source_color = vec3(0.36, 0.40, 0.24);
uniform vec3 col_steep_cliff : source_color = vec3(0.34, 0.32, 0.29);
uniform vec3 col_alpine_snow : source_color = vec3(0.92, 0.95, 0.98);

uniform vec3 haze_tint : source_color = vec3(0.56, 0.73, 0.94);
uniform float haze_falloff = 0.000042;

varying vec3 v_patch_local_pos;
varying vec3 v_sphere_normal;
varying float v_height_m;
varying float v_camera_dist_m;

float sample_height_exact(vec2 uv) {
	if (!use_height_tex) {
		return 0.15 * max_relief_m;
	}
	vec2 clamped = clamp(uv, vec2(0.0), vec2(1.0));
	vec2 texel = clamped * 32.0;
	ivec2 i0 = ivec2(floor(texel));
	ivec2 i1 = min(i0 + ivec2(1, 1), ivec2(32, 32));
	vec2 f = fract(texel);

	float h00 = texelFetch(height_tex, i0, 0).r;
	float h10 = texelFetch(height_tex, ivec2(i1.x, i0.y), 0).r;
	float h01 = texelFetch(height_tex, ivec2(i0.x, i1.y), 0).r;
	float h11 = texelFetch(height_tex, i1, 0).r;

	float h_sample = mix(mix(h00, h10, f.x), mix(h01, h11, f.x), f.y);
	return (abs(h_sample) <= 2.0) ? (h_sample * max_relief_m) : h_sample;
}

float hash_detail(vec3 p) {
	vec3 q = fract(p * 0.1031);
	q += dot(q, q.yzx + 33.33);
	return fract((q.x + q.y) * q.z);
}

float fbm_detail(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash_detail(i);
	float b = hash_detail(i + vec3(1.0, 0.0, 0.0));
	float c = hash_detail(i + vec3(0.0, 1.0, 0.0));
	float d = hash_detail(i + vec3(1.0, 1.0, 0.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

void vertex() {
	vec2 grid_coord = UV * 32.0;
	vec2 odd_frac = fract(grid_coord * 0.5) * 2.0;
	vec2 morphed_uv = clamp(UV - (odd_frac / 32.0) * morph_factor, vec2(0.0), vec2(1.0));

	float h_m = sample_height_exact(morphed_uv);
	float is_skirt = step(0.5, UV2.x);
	float skirt_drop = is_skirt * clamp(patch_size_m * 0.015, 8.0, 80.0);

	vec3 world_base = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 radial_up = normalize(world_base - planet_center_local);
	vec3 displaced_world = world_base + radial_up * (h_m - skirt_drop);

	VERTEX = (inverse(MODEL_MATRIX) * vec4(displaced_world, 1.0)).xyz;
	v_sphere_normal = radial_up;
	v_height_m = h_m;
	v_patch_local_pos = displaced_world - patch_origin_local;
	v_camera_dist_m = length(CAMERA_POSITION_WORLD - displaced_world);
}

void fragment() {
	float duv = 1.0 / 32.0;
	float world_step_m = max(patch_size_m * duv, 1.0);

	float h_w = sample_height_exact(UV - vec2(duv, 0.0));
	float h_e = sample_height_exact(UV + vec2(duv, 0.0));
	float h_s = sample_height_exact(UV - vec2(0.0, duv));
	float h_n = sample_height_exact(UV + vec2(0.0, duv));

	vec3 up = normalize(v_sphere_normal);
	vec3 ref_axis = (abs(up.y) < 0.99) ? vec3(0.0, 1.0, 0.0) : vec3(1.0, 0.0, 0.0);
	vec3 tangent_u = normalize(cross(ref_axis, up));
	vec3 tangent_v = normalize(cross(up, tangent_u));

	float dh_du = (h_e - h_w) / (2.0 * world_step_m);
	float dh_dv = (h_n - h_s) / (2.0 * world_step_m);

	vec3 world_normal = normalize(up - tangent_u * dh_du - tangent_v * dh_dv);
	NORMAL = normalize((VIEW_MATRIX * vec4(world_normal, 0.0)).xyz);

	float slope = clamp(1.0 - dot(world_normal, up), 0.0, 1.0);
	float h_norm = clamp(v_height_m / max(max_relief_m, 1.0), 0.0, 1.0);

	float detail_fine = fbm_detail(v_patch_local_pos * 0.12);
	float detail_macro = fbm_detail(v_patch_local_pos * 0.008);
	float detail_mod = mix(0.86, 1.14, mix(detail_fine, detail_macro, 0.5));

	vec3 biome_col = mix(col_coastal_sand, col_lowland_grass, smoothstep(0.01, 0.09, h_norm));
	biome_col = mix(biome_col, col_highland_shrub, smoothstep(0.28, 0.52, h_norm));
	biome_col = mix(biome_col, col_steep_cliff, smoothstep(0.52, 0.74, h_norm));
	biome_col = mix(biome_col, col_alpine_snow, smoothstep(0.72, 0.88, h_norm + detail_macro * 0.06));

	float cliff_weight = smoothstep(0.16, 0.42, slope);
	vec3 rock_col = mix(col_steep_cliff, col_deep_basalt, smoothstep(0.42, 0.75, slope));
	vec3 terrain_rgb = mix(biome_col, rock_col, cliff_weight) * detail_mod;

	float horizon_ao = clamp(1.0 - slope * 0.55, 0.40, 1.0);
	float haze_mix = clamp(1.0 - exp(-v_camera_dist_m * haze_falloff), 0.0, 0.82);
	vec3 final_rgb = mix(terrain_rgb, haze_tint, haze_mix);

	if (debug_view_mode == 1) {
		ALBEDO = world_normal * 0.5 + 0.5;
		ROUGHNESS = 1.0;
		METALLIC = 0.0;
	} else if (debug_view_mode == 2) {
		ALBEDO = vec3(h_norm, 1.0 - abs(h_norm - 0.5) * 2.0, 1.0 - h_norm);
		ROUGHNESS = 1.0;
		METALLIC = 0.0;
	} else if (debug_view_mode == 3) {
		ALBEDO = patch_debug_color;
		ROUGHNESS = 1.0;
		METALLIC = 0.0;
	} else if (debug_view_mode == 4) {
		float grid_edge = max(step(0.93, fract(UV.x * 32.0)), step(0.93, fract(UV.y * 32.0)));
		ALBEDO = mix(vec3(slope, 1.0 - slope, 0.25), vec3(1.0, 0.9, 0.1), grid_edge);
		ROUGHNESS = 1.0;
		METALLIC = 0.0;
	} else {
		ALBEDO = final_rgb;
		ROUGHNESS = mix(0.88, 0.58, smoothstep(0.72, 0.90, h_norm));
		METALLIC = 0.0;
		AO = horizon_ao;
	}
}
