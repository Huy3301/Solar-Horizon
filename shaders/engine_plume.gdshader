shader_type spatial;
render_mode blend_add, depth_draw_never, cull_disabled, unshaded;

// Supersonic rocket engine exhaust plume with animated shock diamonds (Mach discs),
// core heat gradient (blue-white to orange-red), and atmospheric expansion.

// Color heat gradient uniforms
uniform vec3 plume_color_core : source_color = vec3(0.85, 0.95, 1.0);   // Blue-white hot core
uniform vec3 plume_color_mid : source_color = vec3(0.2, 0.65, 1.0);     // Vibrant cyan/blue
uniform vec3 plume_color_outer : source_color = vec3(1.0, 0.38, 0.08);  // Fiery amber/orange
uniform vec3 plume_color_edge : source_color = vec3(0.85, 0.08, 0.02);  // Cooling red boundary

// Thrust and shock diamond tuning
uniform float thrust_intensity : hint_range(0.0, 3.0) = 1.0;
uniform float shock_diamond_frequency : hint_range(1.0, 30.0) = 8.0;
uniform float shock_speed : hint_range(0.0, 30.0) = 8.0;
uniform float shock_intensity : hint_range(0.0, 5.0) = 2.5;

// Atmosphere expansion factor:
// 0.0 = vacuum (plume flares wide into space)
// 1.0 = sea level dense air (ambient pressure tightens plume)
uniform float atmosphere_density : hint_range(0.0, 2.0) = 0.0;
uniform float expansion_factor : hint_range(0.2, 3.0) = 1.0;

varying vec3 v_local_pos;
varying vec2 v_uv;
varying float v_dist;

void vertex() {
	v_local_pos = VERTEX;
	v_uv = UV;
	
	// Distance from nozzle along plume axis (0.0 = nozzle base, 1.0 = exhaust exit tip)
	// In CylinderMesh with height 4.2, Y ranges from -2.1 to +2.1
	float dist_from_nozzle = clamp((VERTEX.y / 4.2) + 0.5, 0.0, 1.0);
	v_dist = dist_from_nozzle;
	
	// Atmospheric expansion factor:
	// In vacuum (atmosphere_density = 0.0), exhaust flares radially outward into the vacuum.
	// In dense atmosphere (atmosphere_density >= 1.0), atmospheric pressure squeezes/tightens the plume.
	// At the nozzle exit (dist_from_nozzle = 0), radial scale is exactly 1.0 (matching nozzle diameter).
	float vac_flare = mix(1.8, -0.25, clamp(atmosphere_density, 0.0, 1.0)) * expansion_factor;
	float radial_scale = max(0.15, 1.0 + vac_flare * pow(dist_from_nozzle, 1.25));
	VERTEX.xz *= radial_scale;
}

void fragment() {
	float z_dist = clamp(v_dist, 0.0, 1.0);
	
	// Radial distance from central axis (0.0 at center line, 1.0 at outer boundary)
	float view_angle = clamp(abs(dot(NORMAL, VIEW)), 0.0, 1.0);
	float r_view = 1.0 - view_angle;
	float r_uv = clamp(abs(v_uv.x - 0.5) * 2.0, 0.0, 1.0);
	float r_dist = mix(r_view, r_uv, 0.2);
	
	// 1. Animated shock diamonds (sin/cos rings along cylinder length)
	// Dual wave combination: traveling supersonic shock train + standing Mach disc rings
	float phase = z_dist * shock_diamond_frequency * 3.14159265;
	float flow_wave = sin(phase - TIME * shock_speed);
	float ring_wave = cos(phase * 0.5);
	float ring_modulation = cos(z_dist * 3.14159265 * 2.0) * 0.2 + 0.8;
	
	float shock_pattern = max(0.0, (flow_wave * 0.65 + ring_wave * 0.35) * ring_modulation);
	float shock = pow(shock_pattern, 3.5);
	
	// Shock diamonds decay downstream and attenuate towards radial edges
	shock *= (1.0 - z_dist * 0.8) * pow(1.0 - r_dist, 1.4);
	
	// Atmosphere effect on shocks: Mach discs form intensely in dense air; diffuse in vacuum
	float atm_shock_factor = mix(0.3, 1.0, clamp(atmosphere_density, 0.0, 1.0));
	shock *= atm_shock_factor * shock_intensity;
	
	// 2. Inner core heat gradient (blue-white to orange-red)
	// Hottest at nozzle exit (z_dist ~ 0) and along central axis (r_dist ~ 0)
	float core_heat = pow(1.0 - r_dist, 2.2) * (1.0 - z_dist * 0.65);
	// Shock diamonds locally superheat the plasma
	float total_heat = clamp(core_heat + shock * 0.45, 0.0, 1.0);
	
	// Gradient: Blue-white -> Vibrant Cyan -> Amber Orange -> Deep Cooling Red
	vec3 heat_color;
	if (total_heat > 0.65) {
		float t = (total_heat - 0.65) / 0.35;
		heat_color = mix(plume_color_mid, plume_color_core, t);
	} else if (total_heat > 0.25) {
		float t = (total_heat - 0.25) / 0.40;
		heat_color = mix(plume_color_outer, plume_color_mid, t);
	} else {
		float t = total_heat / 0.25;
		heat_color = mix(plume_color_edge, plume_color_outer, t);
	}
	
	// White-hot shock diamond focal spots
	heat_color += vec3(0.9, 0.95, 1.0) * shock * 2.0;
	
	// Transparency and edge falloff
	float edge_mantle = pow(1.0 - r_dist, 1.1) * (1.0 - pow(z_dist, 0.5));
	float alpha = (core_heat * 0.9 + edge_mantle * 0.35 + shock * 0.5) * thrust_intensity;
	
	// Plume density in atmosphere vs vacuum
	float atm_alpha_factor = mix(0.7, 1.0, clamp(atmosphere_density, 0.0, 1.0));
	alpha *= atm_alpha_factor;
	
	ALBEDO = heat_color * alpha * 4.0;
}
