shader_type spatial;
render_mode blend_add, depth_draw_never, cull_disabled, unshaded;

uniform float throttle : hint_range(0.0, 1.0) = 0.0;
uniform float atmospheric_pressure_atm : hint_range(0.0, 2.0) = 1.0;
uniform float expansion_factor : hint_range(0.2, 3.0) = 1.0;
uniform vec4 inner_color : source_color = vec4(0.68, 0.90, 1.0, 1.0);
uniform vec4 outer_color : source_color = vec4(1.0, 0.46, 0.12, 1.0);
uniform float plume_brightness = 3.2;

varying float v_axial_uv;

void vertex() {
	v_axial_uv = clamp(UV.y, 0.0, 1.0);
	float vacuum_Bell = mix(1.75, 1.0, clamp(atmospheric_pressure_atm, 0.0, 1.0));
	VERTEX.xz *= mix(1.0, vacuum_Bell, v_axial_uv) * expansion_factor * (0.45 + 0.55 * throttle);
}

void fragment() {
	// S2d fix: maintain cylindrical core visibility from side angles
	float view_alignment = abs(dot(NORMAL, VIEW));
	float side_visibility = max(pow(view_alignment, 0.65), 0.48);
	float axial_fade = pow(1.0 - v_axial_uv, 1.35);
	float shock_freq = mix(2.5, 16.0, clamp(atmospheric_pressure_atm, 0.0, 1.0));
	float shock_diamonds = 0.78 + 0.22 * cos(v_axial_uv * shock_freq - TIME * 26.0);

	float intensity = throttle * side_visibility * axial_fade * shock_diamonds;
	vec3 rgb = mix(outer_color.rgb, inner_color.rgb, pow(1.0 - v_axial_uv, 2.0));
	ALBEDO = rgb * intensity * plume_brightness;
	ALPHA = clamp(intensity, 0.0, 1.0);
}
