shader_type canvas_item;
render_mode blend_mix, unshaded;

uniform float charge_mix : hint_range(0.0, 1.0) = 0.0;
uniform float travel_mix : hint_range(0.0, 1.0) = 0.0;
uniform float arrival_mix : hint_range(0.0, 1.0) = 0.0;
uniform float velocity_mix : hint_range(0.0, 1.0) = 0.0;
uniform float elapsed = 0.0;

void fragment() {
	vec2 centered = (UV - vec2(0.5)) * vec2(1.0, SCREEN_PIXEL_SIZE.x / SCREEN_PIXEL_SIZE.y);
	float radius = length(centered);
	float angle = atan(centered.y, centered.x);

	float radial_lines = 0.0;
	for (int i = 0; i < 18; i++) {
		float index = float(i);
		float ray_angle = TAU * (index / 18.0) + sin(index * 17.31) * 0.045;
		float angular_distance = abs(atan(sin(angle - ray_angle), cos(angle - ray_angle)));
		float ray = 1.0 - smoothstep(0.003, 0.018, angular_distance);
		float cadence = 0.58 + 0.42 * sin(radius * 34.0 - elapsed * (4.0 + velocity_mix * 11.0) + index * 2.7);
		radial_lines += ray * cadence;
	}
	radial_lines = clamp(radial_lines / 3.2, 0.0, 1.0);
	float outward_mask = smoothstep(0.12, 0.86, radius) * (1.0 - smoothstep(0.94, 1.18, radius));
	float travel_streaks = radial_lines * outward_mask * travel_mix * (0.12 + velocity_mix * 0.32);

	float charge_radius = charge_mix * 1.24;
	float charge_ring = exp(-abs(radius - charge_radius) * 54.0) * charge_mix;
	float arrival_radius = arrival_mix * 1.35;
	float arrival_ring = exp(-abs(radius - arrival_radius) * 70.0) * arrival_mix;
	float center_flare = exp(-radius * 13.0) * (charge_mix * (1.0 - charge_mix) * 2.2 + arrival_mix * 0.7);
	float edge_shade = smoothstep(0.18, 0.92, radius) * (travel_mix * 0.18 + charge_mix * 0.08 + arrival_mix * 0.12);

	vec3 deep_teal = vec3(0.025, 0.12, 0.19);
	vec3 ion_blue = vec3(0.30, 0.78, 1.0);
	vec3 warm_arrival = vec3(1.0, 0.73, 0.42);
	vec3 color = deep_teal * edge_shade;
	color += ion_blue * (travel_streaks + charge_ring * 0.24);
	color += warm_arrival * arrival_ring * 0.32;
	color += vec3(0.62, 0.9, 1.0) * center_flare;

	float alpha = edge_shade + travel_streaks * 0.7 + charge_ring * 0.2 + arrival_ring * 0.28 + center_flare * 0.45;
	COLOR = vec4(color, clamp(alpha, 0.0, 0.62));
}
