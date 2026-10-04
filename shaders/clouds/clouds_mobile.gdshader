shader_type spatial;
render_mode blend_mix, depth_draw_always, cull_back, diffuse_lambert, specular_disabled;

// Cheap mobile cloud layer shader (< 1 ms GPU budget)
uniform sampler2D cloud_texture : source_color, filter_linear_mipmap, repeat_enable;
uniform vec3 sun_direction = vec3(0.707, 0.35, 0.612);
uniform vec2 wind_direction = vec2(1.0, 0.0);
uniform float wind_speed = 0.015;
uniform float cloud_coverage : hint_range(0.0, 2.0) = 1.0;
uniform vec3 cloud_color : source_color = vec3(1.0, 1.0, 1.0);
uniform vec3 sunset_color : source_color = vec3(1.0, 0.45, 0.15);

varying vec3 v_world_normal;
varying vec2 v_uv;

void vertex() {
	v_world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	v_uv = UV + wind_direction * (TIME * wind_speed);
}

void fragment() {
	float raw_alpha = texture(cloud_texture, v_uv).a;
	float alpha = clamp((raw_alpha - 0.2) * (cloud_coverage / 0.8), 0.0, 1.0);

	vec3 N = normalize(v_world_normal);
	vec3 L = normalize(sun_direction);
	float n_dot_l = dot(N, L);

	float day = clamp(n_dot_l * 2.0 + 0.1, 0.0, 1.0);
	float sunset = clamp(1.0 - abs(n_dot_l) * 4.0, 0.0, 1.0);
	vec3 lit = mix(cloud_color, sunset_color, sunset);

	ALBEDO = mix(vec3(0.02, 0.03, 0.05), lit, day);
	ALPHA = alpha;
	ROUGHNESS = 0.95;
}
