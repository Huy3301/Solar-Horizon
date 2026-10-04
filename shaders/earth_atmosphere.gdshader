shader_type spatial;
render_mode blend_add, depth_draw_never, cull_front, unshaded;

// Photorealistic Earth atmospheric limb scattering shell for Low Earth Orbit (LEO)
// Features:
// 1. Physically-inspired multi-layer Rayleigh wavelength scattering (450nm blue to 650nm red)
// 2. Chappuis ozone absorption layer (subtle turquoise-azure gradient between troposphere and space)
// 3. Mesospheric airglow ribbon (557.7nm atomic oxygen emerald line on night/twilight limb)
// 4. Mie aerosol forward-scatter solar diffraction halo
// 5. Grazing twilight horizon extinction (crimson/amber sunset arc)

uniform vec3 sun_direction = vec3(0.707, 0.35, 0.612);
uniform vec3 rayleigh_day_color : source_color = vec3(0.16, 0.54, 1.0);
uniform vec3 rayleigh_sunset_color : source_color = vec3(1.0, 0.42, 0.12);
uniform vec3 ozone_tint_color : source_color = vec3(0.12, 0.78, 0.95);
uniform vec3 airglow_green_color : source_color = vec3(0.15, 0.96, 0.42);

uniform float atmosphere_density : hint_range(0.1, 5.0) = 2.2;
uniform float rim_falloff_power : hint_range(0.5, 12.0) = 4.2;
uniform float mie_phase_strength : hint_range(0.0, 5.0) = 2.4;
uniform float airglow_intensity : hint_range(0.0, 2.0) = 0.45;

varying vec3 v_world_normal;
varying vec3 v_world_pos;

void vertex() {
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_world_normal = normalize((MODEL_MATRIX * vec4(-NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 V = normalize(CAMERA_POSITION_WORLD - v_world_pos);
	vec3 N = normalize(v_world_normal);
	vec3 L = normalize(sun_direction);

	float v_dot_n = clamp(dot(V, N), 0.0, 1.0);
	float rim = pow(1.0 - v_dot_n, rim_falloff_power);
	
	float n_dot_l = dot(N, L);
	float v_dot_l = dot(V, L);
	
	// Day vs Twilight vs Night weighting
	float day_weight = smoothstep(-0.04, 0.30, n_dot_l);
	float sunset_weight = smoothstep(-0.22, -0.01, n_dot_l) * (1.0 - smoothstep(0.02, 0.26, n_dot_l));
	float night_weight = 1.0 - smoothstep(-0.18, 0.08, n_dot_l);
	
	// Rayleigh sky color with sunset extinction
	vec3 scatter_color = mix(rayleigh_day_color, rayleigh_sunset_color, sunset_weight * 0.95);
	
	// Stratospheric ozone absorption (Chappuis band) creates a subtle turquoise layer
	float ozone_band = pow(1.0 - v_dot_n, 2.8) * (1.0 - pow(1.0 - v_dot_n, 8.0));
	scatter_color = mix(scatter_color, ozone_tint_color, ozone_band * 0.35 * day_weight);
	
	// Forward Mie scattering halo (silver/gold atmospheric flare when looking towards the sun)
	float mie_glow = pow(max(0.0, v_dot_l), 14.0) * mie_phase_strength * (day_weight + sunset_weight * 1.8);
	
	// Mesospheric atomic oxygen airglow green ribbon along the dark limb
	float airglow_rim = pow(1.0 - v_dot_n, 8.5) * airglow_intensity;
	vec3 airglow = airglow_green_color * airglow_rim * (0.35 + 0.65 * night_weight);
	
	// Combine layers
	vec3 final_color = scatter_color * rim * atmosphere_density * (day_weight + sunset_weight * 1.6);
	final_color += vec3(1.0, 0.94, 0.82) * mie_glow * rim;
	final_color += airglow;
	
	ALBEDO = final_color;
}
