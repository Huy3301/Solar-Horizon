shader_type spatial;
render_mode blend_add, depth_draw_never, cull_disabled, unshaded;

// Supersonic rocket engine exhaust plume with shock diamonds (Mach discs)
uniform vec3 plume_color_core : source_color = vec3(0.3, 0.75, 1.0);
uniform vec3 plume_color_outer : source_color = vec3(0.08, 0.25, 0.85);
uniform float thrust_intensity : hint_range(0.0, 2.0) = 1.0;
uniform float shock_diamond_frequency : hint_range(1.0, 20.0) = 8.0;

varying vec3 v_local_pos;
varying vec2 v_uv;

void vertex() {
	v_local_pos = VERTEX;
	v_uv = UV;
}

void fragment() {
	float z_dist = clamp(v_uv.y, 0.0, 1.0);
	float r_dist = clamp(abs(v_uv.x - 0.5) * 2.0, 0.0, 1.0);
	
	float shock = pow(max(0.0, sin(z_dist * shock_diamond_frequency * 3.14159)), 4.0);
	shock *= (1.0 - z_dist * 0.85) * (1.0 - r_dist);
	
	float core = pow(1.0 - r_dist, 2.5) * (1.0 - z_dist);
	float edge = pow(1.0 - r_dist, 1.2) * (1.0 - pow(z_dist, 0.6));
	
	vec3 col = mix(plume_color_outer, plume_color_core, core);
	col += vec3(1.0, 1.0, 1.0) * shock * 2.5;
	
	float alpha = (core * 0.9 + edge * 0.4 + shock * 0.6) * thrust_intensity;
	
	ALBEDO = col * alpha * 4.0;
}
