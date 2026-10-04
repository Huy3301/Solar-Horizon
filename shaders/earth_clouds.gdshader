shader_type spatial;
render_mode blend_mix, depth_draw_always, cull_back, diffuse_burley, specular_schlick_ggx;

// Multi-layered realistic Earth cloud shell for Low Earth Orbit (LEO)
uniform sampler2D cloud_texture : source_color, filter_linear_mipmap, repeat_enable;
uniform vec3 sun_direction = vec3(0.707, 0.35, 0.612);
uniform float cloud_coverage : hint_range(0.0, 2.0) = 1.15;
uniform float cloud_rotation : hint_range(-3.14159, 3.14159) = 0.0;
uniform vec3 cloud_color : source_color = vec3(1.0, 1.0, 1.0);
uniform vec3 sunset_cloud_color : source_color = vec3(1.0, 0.55, 0.25);

varying vec3 v_world_normal;
varying vec3 v_world_pos;
varying vec2 v_uv;

void vertex() {
	float cos_r = cos(cloud_rotation);
	float sin_r = sin(cloud_rotation);
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
	vec4 cloud_sample = texture(cloud_texture, v_uv);
	float alpha = clamp(cloud_sample.r * cloud_coverage, 0.0, 1.0);
	
	vec3 N = normalize(v_world_normal);
	vec3 L = normalize(sun_direction);
	vec3 V = normalize(CAMERA_POSITION_WORLD - v_world_pos);
	
	float n_dot_l = dot(N, L);
	float day_factor = smoothstep(-0.08, 0.18, n_dot_l);
	
	float sunset_factor = smoothstep(-0.15, -0.01, n_dot_l) * (1.0 - smoothstep(0.0, 0.20, n_dot_l));
	vec3 lit_color = mix(cloud_color, sunset_cloud_color, sunset_factor * 0.85);
	
	float v_dot_l = dot(V, -L);
	float forward_scatter = pow(max(0.0, v_dot_l), 4.0) * 0.35 * day_factor;
	
	vec3 night_cloud_tint = vec3(0.03, 0.06, 0.12);
	vec3 final_cloud_rgb = mix(night_cloud_tint, lit_color + vec3(forward_scatter), day_factor);
	
	ALBEDO = final_cloud_rgb;
	ALPHA = alpha;
	ROUGHNESS = 0.88;
	SPECULAR = 0.05;
}
