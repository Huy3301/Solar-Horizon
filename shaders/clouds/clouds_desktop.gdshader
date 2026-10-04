shader_type spatial;
render_mode blend_mix, depth_draw_always, cull_back, diffuse_burley, specular_schlick_ggx;

// Desktop volumetric-style 2-layer cloud shader with cloud shadow term
uniform sampler2D cloud_texture : source_color, filter_linear_mipmap, repeat_enable;
uniform vec3 sun_direction = vec3(0.707, 0.35, 0.612);
uniform vec2 wind_direction = vec2(1.0, 0.2);
uniform float wind_speed = 0.02;
uniform float cloud_coverage : hint_range(0.0, 2.0) = 1.0;
uniform float shadow_factor : hint_range(0.0, 1.0) = 0.7;
uniform vec3 cloud_color : source_color = vec3(1.0, 1.0, 1.0);
uniform vec3 sunset_color : source_color = vec3(1.0, 0.5, 0.2);

varying vec3 v_world_normal;
varying vec3 v_world_pos;
varying vec2 v_uv;

void vertex() {
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	v_uv = UV;
}

void fragment() {
	vec2 uv1 = v_uv + wind_direction * TIME * wind_speed;
	vec2 uv2 = v_uv * 2.3 - wind_direction * TIME * (wind_speed * 0.7) + vec2(0.3, 0.7);

	float d1 = texture(cloud_texture, uv1).a;
	float d2 = texture(cloud_texture, uv2).a;
	float density = smoothstep(0.15, 0.75, (d1 * 0.7 + d2 * 0.4) * cloud_coverage);

	vec3 N = normalize(v_world_normal);
	vec3 L = normalize(sun_direction);
	float n_dot_l = dot(N, L);

	float day_factor = smoothstep(-0.05, 0.25, n_dot_l);
	float sunset_band = smoothstep(-0.15, 0.0, n_dot_l) * (1.0 - smoothstep(0.0, 0.3, n_dot_l));
	vec3 lit_col = mix(cloud_color, sunset_color, sunset_band);

	// Cloud self-shadowing
	float self_shadow = mix(1.0 - shadow_factor * 0.4, 1.0, clamp(n_dot_l + 0.3, 0.0, 1.0));
	lit_col *= self_shadow;

	vec3 night_col = vec3(0.015, 0.02, 0.04);
	ALBEDO = mix(night_col, lit_col, day_factor);
	ALPHA = density;
	ROUGHNESS = 0.85;
	SPECULAR = 0.04;
}
