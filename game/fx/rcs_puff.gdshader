shader_type spatial;
render_mode blend_add, depth_draw_never, cull_disabled, unshaded;

// RCS thruster puff effect shader (high-velocity cold-gas / hypergolic burst)
uniform vec3 puff_color_core : source_color = vec3(0.9, 0.95, 1.0);
uniform vec3 puff_color_outer : source_color = vec3(0.3, 0.65, 1.0);
uniform float puff_intensity : hint_range(0.0, 5.0) = 2.0;
uniform float burst_scale : hint_range(0.1, 4.0) = 1.0;
uniform float burst_progress : hint_range(0.0, 1.0) = 0.0;
uniform float cone_expansion : hint_range(0.1, 3.0) = 1.0;

varying vec3 v_vertex;
varying vec2 v_uv;

void vertex() {
	v_vertex = VERTEX;
	v_uv = UV;
	
	// Expanding conical jet along local Y (exhaust axis)
	// Progress along puff length from nozzle (0.0) to tip (1.0)
	float dist = clamp(UV.y, 0.0, 1.0);
	float flare = 1.0 + dist * cone_expansion * 1.8;
	VERTEX.xz *= flare * burst_scale;
	VERTEX.y *= burst_scale;
}

void fragment() {
	float z_dist = clamp(v_uv.y, 0.0, 1.0);
	float r_dist = clamp(abs(v_uv.x - 0.5) * 2.0, 0.0, 1.0);
	
	// High-speed jet turbulence and gas eddies
	float noise = sin(z_dist * 24.0 - TIME * 32.0) * cos(r_dist * 14.0 + TIME * 20.0) * 0.25 + 0.75;
	
	// Core gas density
	float core = pow(1.0 - r_dist, 2.4) * (1.0 - z_dist);
	vec3 col = mix(puff_color_outer, puff_color_core, core);
	
	// Burst dissipation
	float fade = clamp(1.0 - burst_progress, 0.0, 1.0);
	float alpha = core * noise * puff_intensity * fade;
	
	ALBEDO = col * alpha * 3.5;
}
