shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

// High-fidelity Earth planetary surface shader for Low Earth Orbit (LEO)
uniform sampler2D albedo_map : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D normal_map : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D water_mask : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform sampler2D night_lights : source_color, filter_linear_mipmap, repeat_enable;

uniform vec3 sun_direction = vec3(0.707, 0.35, 0.612);
uniform float night_lights_intensity : hint_range(0.0, 5.0) = 3.2;
uniform vec3 night_lights_tint : source_color = vec3(1.0, 0.82, 0.45);
uniform float atmosphere_rim_influence : hint_range(0.0, 1.0) = 0.5;
uniform vec3 atmosphere_rim_color : source_color = vec3(0.2, 0.6, 1.0);
uniform float planet_rotation : hint_range(-3.14159, 3.14159) = 0.0;

varying vec3 v_world_normal;
varying vec3 v_world_pos;
varying vec2 v_uv;

void vertex() {
	float cos_r = cos(planet_rotation);
	float sin_r = sin(planet_rotation);
	vec3 rotated_pos = VERTEX;
	rotated_pos.x = VERTEX.x * cos_r - VERTEX.z * sin_r;
	rotated_pos.z = VERTEX.x * sin_r + VERTEX.z * cos_r;
	
	vec3 rotated_normal = NORMAL;
	rotated_normal.x = NORMAL.x * cos_r - NORMAL.z * sin_r;
	rotated_normal.z = NORMAL.x * sin_r + NORMAL.z * cos_r;

	v_world_pos = (MODEL_MATRIX * vec4(rotated_pos, 1.0)).xyz;
	v_world_normal = normalize((MODEL_MATRIX * vec4(rotated_normal, 0.0)).xyz);
	v_uv = UV;
}

void fragment() {
	vec4 base_color = texture(albedo_map, v_uv);
	vec3 normal_sample = texture(normal_map, v_uv).rgb * 2.0 - 1.0;
	float is_water = texture(water_mask, v_uv).r;
	vec3 lights_sample = texture(night_lights, v_uv).rgb;
	
	NORMAL = normalize(mix(NORMAL, NORMAL + normal_sample * 0.4, 1.0 - is_water * 0.8));
	
	vec3 L = normalize(sun_direction);
	vec3 N = normalize(v_world_normal);
	vec3 V = normalize(CAMERA_POSITION_WORLD - v_world_pos);
	float n_dot_l = dot(N, L);
	
	float day_factor = smoothstep(-0.12, 0.15, n_dot_l);
	float night_factor = 1.0 - day_factor;
	
	float terminator_band = smoothstep(-0.10, 0.0, n_dot_l) * (1.0 - smoothstep(0.0, 0.22, n_dot_l));
	vec3 sunset_tint = vec3(1.0, 0.42, 0.12) * terminator_band * 0.65;
	
	ROUGHNESS = mix(0.78, 0.08, is_water);
	METALLIC = mix(0.02, 0.15, is_water);
	SPECULAR = mix(0.15, 0.95, is_water);
	
	float fresnel = pow(1.0 - clamp(dot(N, V), 0.0, 1.0), 4.0);
	vec3 surface_albedo = base_color.rgb + sunset_tint;
	if (is_water > 0.5) {
		surface_albedo = mix(surface_albedo, vec3(0.08, 0.22, 0.42), fresnel * 0.4);
	}
	
	ALBEDO = surface_albedo;
	
	vec3 lights_emission = lights_sample * night_lights_tint * night_lights_intensity * night_factor;
	float rim = pow(1.0 - clamp(dot(N, V), 0.0, 1.0), 3.0);
	vec3 atmosphere_haze = atmosphere_rim_color * rim * atmosphere_rim_influence * max(0.0, n_dot_l + 0.2);
	
	EMISSION = lights_emission + atmosphere_haze;
}
