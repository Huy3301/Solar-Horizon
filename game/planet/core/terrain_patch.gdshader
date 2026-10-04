shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

// Terrain Patch Shader - Cube-Sphere CDLOD
// Supports procedural PBR palettes, CDLOD geomorphing and skirts, detail normals, and horizon AO.

uniform int body_type : hint_range(0, 1) = 0; // 0 = Earth, 1 = Moon
uniform vec2 patch_offset = vec2(0.0);
uniform float patch_scale = 1.0;
uniform int face_index = 0;
uniform float planet_radius = 637100.0;
uniform float max_height = 8848.0;
uniform vec3 patch_center_local = vec3(0.0);
uniform float patch_resolution = 33.0;
uniform float morph_factor : hint_range(0.0, 1.0) = 0.0;

uniform bool use_gpu_height = false;
uniform sampler2D height_map;
uniform sampler2D water_mask : hint_default_white, filter_linear_mipmap, repeat_enable;

// Biome / Altitude / Slope thresholds
uniform float slope_threshold : hint_range(0.0, 1.0) = 0.72;
uniform float slope_blend : hint_range(0.01, 0.5) = 0.12;
uniform float sand_altitude : hint_range(0.0, 1000.0) = 150.0;
uniform float snow_altitude : hint_range(500.0, 9000.0) = 2800.0;
uniform float snow_blend : hint_range(50.0, 1000.0) = 400.0;
uniform float detail_normal_strength : hint_range(0.0, 2.0) = 0.65;
uniform float ao_strength : hint_range(0.0, 1.0) = 0.85;

vec3 hash33(vec3 p) {
	p = p * 0.1031;
	p -= floor(p);
	float dot_val = dot(p, vec3(p.z + 39.346, p.y + 39.346, p.x + 39.346));
	p += vec3(dot_val);
	vec3 res = vec3(p.x + p.y, p.x + p.z, p.y + p.z);
	return res - floor(res);
}

float get_noise_3d(vec3 p) {
	vec3 i = floor(p);
	vec3 f = p - i;
	vec3 u = f * f * (3.0 - 2.0 * f);
	
	float n000 = hash33(i).x;
	float n100 = hash33(i + vec3(1.0, 0.0, 0.0)).x;
	float n010 = hash33(i + vec3(0.0, 1.0, 0.0)).x;
	float n110 = hash33(i + vec3(1.0, 1.0, 0.0)).x;
	float n001 = hash33(i + vec3(0.0, 0.0, 1.0)).x;
	float n101 = hash33(i + vec3(1.0, 0.0, 1.0)).x;
	float n011 = hash33(i + vec3(0.0, 1.0, 1.0)).x;
	float n111 = hash33(i + vec3(1.0, 1.0, 1.0)).x;
	
	float nx00 = mix(n000, n100, u.x);
	float nx10 = mix(n010, n110, u.x);
	float nx01 = mix(n001, n101, u.x);
	float nx11 = mix(n011, n111, u.x);
	
	float nxy0 = mix(nx00, nx10, u.y);
	float nxy1 = mix(nx01, nx11, u.y);
	
	return mix(nxy0, nxy1, u.z) * 2.0 - 1.0;
}

float fbm(vec3 p, int octaves) {
	float value = 0.0;
	float amp = 0.5;
	float freq = 1.0;
	for (int i = 0; i < octaves; i++) {
		value += amp * get_noise_3d(p * freq);
		freq *= 2.0;
		amp *= 0.5;
	}
	return value;
}

float crater_noise_3d(vec3 p) {
	vec3 i = floor(p);
	vec3 f = p - i;
	float min_dist = 10.0;
	for (int z = -1; z <= 1; z++) {
		for (int y = -1; y <= 1; y++) {
			for (int x = -1; x <= 1; x++) {
				vec3 cell = vec3(float(x), float(y), float(z));
				vec3 h = hash33(i + cell);
				vec3 feature_pt = cell + h * 0.65;
				float d = length(f - feature_pt);
				min_dist = min(min_dist, d);
			}
		}
	}
	float rim = smoothstep(0.52, 0.38, min_dist) * smoothstep(0.22, 0.38, min_dist);
	float bowl = smoothstep(0.36, 0.0, min_dist);
	float peak = smoothstep(0.08, 0.0, min_dist) * 0.35;
	return rim * 1.5 - bowl * 0.85 + peak;
}

float sample_height_analytic(vec3 dir, int body) {
	if (body == 1) {
		float highlands = fbm(dir * 1.8, 3) * 0.25;
		float c_large = crater_noise_3d(dir * 4.8) * 0.38;
		float c_med = crater_noise_3d(dir * 13.5 + vec3(3.7, 8.2, 5.1)) * 0.22;
		float c_small = crater_noise_3d(dir * 30.0 + vec3(9.1, 14.5, 2.3)) * 0.10;
		return clamp(0.35 + highlands + c_large + c_med + c_small, 0.0, 1.0);
	}
	vec3 warp = vec3(
		fbm(dir + vec3(1.2, 3.4, 5.6), 4),
		fbm(dir + vec3(7.8, 9.0, 1.2), 4),
		fbm(dir + vec3(3.4, 5.6, 7.8), 4)
	);
	float noise_val = fbm(dir * 3.2 + warp, 6);
	float ridged = 1.0 - abs(noise_val);
	return pow(ridged, 2.2);
}

vec3 get_spherified_dir(int face, vec2 face_uv) {
	vec2 p = face_uv * 2.0 - 1.0;
	vec3 v;
	if (face == 0) v = vec3(1.0, -p.y, -p.x);
	else if (face == 1) v = vec3(-1.0, -p.y, p.x);
	else if (face == 2) v = vec3(p.x, 1.0, p.y);
	else if (face == 3) v = vec3(p.x, -1.0, -p.y);
	else if (face == 4) v = vec3(p.x, -p.y, 1.0);
	else if (face == 5) v = vec3(-p.x, -p.y, -1.0);
	else v = vec3(0.0);
	
	float x2 = v.x * v.x;
	float y2 = v.y * v.y;
	float z2 = v.z * v.z;
	return normalize(vec3(
		v.x * sqrt(max(0.0, 1.0 - y2/2.0 - z2/2.0 + y2*z2/3.0)),
		v.y * sqrt(max(0.0, 1.0 - x2/2.0 - z2/2.0 + x2*z2/3.0)),
		v.z * sqrt(max(0.0, 1.0 - x2/2.0 - y2/2.0 + x2*y2/3.0))
	));
}

varying vec3 v_world_pos;
varying vec3 v_dir;
varying float v_height;
varying float v_altitude;

void vertex() {
	vec2 face_uv = patch_offset + UV * patch_scale;
	vec3 dir = get_spherified_dir(face_index, face_uv);
	
	float h = 0.0;
	if (use_gpu_height) {
		h = texture(height_map, UV).r;
	} else {
		h = sample_height_analytic(dir, body_type);
	}
	
	// Geomorphing
	if (morph_factor > 0.001) {
		vec2 grid_coord = UV * (patch_resolution - 1.0);
		vec2 grid_odd = fract(grid_coord * 0.5) * 2.0;
		bool odd_x = (grid_odd.x > 0.4 && grid_odd.x < 1.6);
		bool odd_y = (grid_odd.y > 0.4 && grid_odd.y < 1.6);
		if (odd_x || odd_y) {
			vec2 uv_coarse = UV;
			if (odd_x) uv_coarse.x = (floor(grid_coord.x * 0.5) * 2.0) / (patch_resolution - 1.0);
			if (odd_y) uv_coarse.y = (floor(grid_coord.y * 0.5) * 2.0) / (patch_resolution - 1.0);
			vec3 dir_coarse = get_spherified_dir(face_index, patch_offset + uv_coarse * patch_scale);
			float h_coarse = sample_height_analytic(dir_coarse, body_type);
			h = mix(h, h_coarse, morph_factor);
		}
	}
	
	v_height = h;
	v_dir = dir;
	v_altitude = h * max_height;
	
	vec3 world_pos_from_center = dir * (planet_radius + h * max_height);
	
	// Skirts
	if (COLOR.r > 0.5) {
		float skirt_depth = max_height * 0.4 + (patch_scale * planet_radius * 0.015);
		world_pos_from_center -= dir * skirt_depth;
	}
	
	VERTEX = world_pos_from_center - patch_center_local;
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 N = normalize(NORMAL);
	vec3 up_dir = normalize(v_dir);
	float up_dot = clamp(dot(N, up_dir), 0.0, 1.0);
	
	vec3 micro_p = v_world_pos * 0.15;
	float micro_noise_val = get_noise_3d(micro_p);
	vec3 detail_norm = vec3(
		get_noise_3d(micro_p + vec3(0.05, 0.0, 0.0)) - micro_noise_val,
		get_noise_3d(micro_p + vec3(0.0, 0.05, 0.0)) - micro_noise_val,
		get_noise_3d(micro_p + vec3(0.0, 0.0, 0.05)) - micro_noise_val
	) * 20.0;
	vec3 final_normal = normalize(N + detail_norm * detail_normal_strength * 0.2);
	
	vec3 final_albedo = vec3(0.5);
	float final_roughness = 0.8;
	
	if (body_type == 1) {
		vec3 mare_basalt = vec3(0.18, 0.18, 0.19);
		vec3 highlands = vec3(0.54, 0.55, 0.57);
		vec3 bright_ejecta = vec3(0.74, 0.75, 0.78);
		
		float mare_factor = smoothstep(0.42, 0.35, v_height);
		float ejecta_factor = smoothstep(0.70, 0.85, v_height);
		
		vec3 regolith = mix(highlands, mare_basalt, mare_factor);
		regolith = mix(regolith, bright_ejecta, ejecta_factor);
		
		float cliff = smoothstep(0.75, 0.40, up_dot);
		regolith = mix(regolith, regolith * 0.7, cliff);
		
		final_albedo = regolith;
		final_roughness = 0.90 - ejecta_factor * 0.15;
	} else {
		vec3 sand = vec3(0.76, 0.70, 0.50);
		vec3 grass = vec3(0.22, 0.44, 0.15);
		vec3 rock = vec3(0.36, 0.34, 0.32);
		vec3 snow = vec3(0.92, 0.94, 0.97);
		
		float rock_weight = smoothstep(slope_threshold, slope_threshold - slope_blend, up_dot);
		float sand_weight = smoothstep(sand_altitude + 50.0, sand_altitude - 50.0, v_altitude);
		float snow_weight = smoothstep(snow_altitude - snow_blend, snow_altitude + snow_blend, v_altitude);
		
		vec3 lowland = mix(grass, sand, sand_weight * (1.0 - rock_weight));
		vec3 midland = mix(lowland, rock, rock_weight);
		vec3 highland = mix(midland, snow, snow_weight * (1.0 - rock_weight * 0.5));
		
		final_albedo = highland;
		final_roughness = mix(0.65, 0.88, rock_weight);
		final_roughness = mix(final_roughness, 0.32, snow_weight);
	}
	
	float ao = clamp(v_height * 1.5, 0.2, 1.0);
	final_albedo *= mix(1.0, ao, ao_strength);
	
	ALBEDO = final_albedo;
	ROUGHNESS = final_roughness;
	NORMAL = final_normal;
}
