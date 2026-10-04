shader_type spatial;
render_mode blend_add, depth_draw_never, cull_disabled, unshaded;

// Hypersonic atmospheric re-entry plasma sheath & shock layer
uniform float heat_intensity : hint_range(0.0, 2.0) = 0.0;
uniform vec3 plasma_color_core : source_color = vec3(1.0, 0.92, 0.75);   // White-yellow stagnation core
uniform vec3 plasma_color_outer : source_color = vec3(1.0, 0.38, 0.05);  // Fiery orange shock sheath
uniform vec3 plasma_color_edge : source_color = vec3(0.75, 0.08, 0.35);  // Ionized magenta/purple edge
uniform float stream_speed : hint_range(0.0, 50.0) = 22.0;
uniform float turbulence_scale : hint_range(0.1, 10.0) = 3.5;

varying vec3 v_normal;
varying vec3 v_vertex;
varying vec2 v_uv;

void vertex() {
	v_normal = NORMAL;
	v_vertex = VERTEX;
	v_uv = UV;
	
	// Micro pulsation along shock envelope
	float pulse = sin(TIME * stream_speed * 0.5 + VERTEX.z * 1.5) * 0.04 * heat_intensity;
	VERTEX += NORMAL * pulse;
}

void fragment() {
	// Reentry plasma streams along length
	float flow1 = sin(v_uv.y * 28.0 - TIME * stream_speed) * 0.5 + 0.5;
	float flow2 = cos(v_uv.x * 18.0 + TIME * (stream_speed * 0.65)) * 0.5 + 0.5;
	float turbulence = flow1 * 0.6 + flow2 * 0.4;
	
	// Fresnel rim glow: glancing angles shine brightest
	vec3 view_dir = normalize(VIEW);
	float fresnel = 1.0 - abs(dot(v_normal, view_dir));
	fresnel = pow(clamp(fresnel, 0.0, 1.0), 2.2);
	
	// Stream intensity decays towards tail
	float compression = clamp(1.0 - (v_uv.y * 0.65), 0.0, 1.0);
	
	// Total plasma glow
	float plasma_strength = (fresnel * 0.65 + compression * 0.55 + turbulence * 0.25) * heat_intensity;
	
	// Heat color stages
	vec3 col;
	if (plasma_strength > 0.75) {
		float t = clamp((plasma_strength - 0.75) / 0.6, 0.0, 1.0);
		col = mix(plasma_color_outer, plasma_color_core, t);
	} else if (plasma_strength > 0.25) {
		float t = clamp((plasma_strength - 0.25) / 0.5, 0.0, 1.0);
		col = mix(plasma_color_edge, plasma_color_outer, t);
	} else {
		col = plasma_color_edge;
	}
	
	float alpha = clamp(plasma_strength, 0.0, 1.0) * min(1.0, heat_intensity * 1.5);
	
	ALBEDO = col * alpha * 4.0;
}
