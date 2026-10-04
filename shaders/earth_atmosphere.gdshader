shader_type spatial;
render_mode blend_add, depth_draw_never, cull_front, unshaded;

// Photorealistic Earth atmospheric Rayleigh + Mie scattering shell
// Features:
// 1. Physically-inspired wavelength-dependent Rayleigh scattering (blue day, crimson sunset)
// 2. Mie aerosol forward-scatter halo with Henyey-Greenstein phase function
// 3. Limb glow with optical depth integration from Low Earth Orbit (LEO) to deep space
// 4. Chappuis ozone absorption layer (turquoise gradient between troposphere and space)
// 5. Mesospheric atomic oxygen airglow ribbon (557.7nm green line) along dark limb
// 6. Quality tier support: Low (mobile/fast analytic) vs High (multi-term physical)

// Quality Tier: 0 = Low (Mobile/fast analytic), 1 = High (Desktop/multi-term physical)
uniform int quality_tier : hint_range(0, 1) = 1;

uniform vec3 sun_direction = vec3(0.707, 0.35, 0.612);
uniform float sun_intensity : hint_range(0.0, 5.0) = 1.0;
uniform float planet_radius : hint_range(1000.0, 10000000.0) = 637100.0;
uniform float atmosphere_radius : hint_range(1000.0, 10000000.0) = 646100.0;

uniform vec3 rayleigh_day_color : source_color = vec3(0.18, 0.58, 1.0);
uniform vec3 rayleigh_sunset_color : source_color = vec3(1.0, 0.38, 0.08);
uniform vec3 ozone_tint_color : source_color = vec3(0.12, 0.78, 0.95);
uniform vec3 airglow_green_color : source_color = vec3(0.15, 0.96, 0.42);

uniform float atmosphere_density : hint_range(0.1, 5.0) = 2.4;
uniform float rim_falloff_power : hint_range(0.5, 12.0) = 4.0;
uniform float mie_phase_strength : hint_range(0.0, 5.0) = 2.2;
uniform float mie_eccentricity : hint_range(0.5, 0.95) = 0.78;
uniform float airglow_intensity : hint_range(0.0, 2.0) = 0.4;

varying vec3 v_world_normal;
varying vec3 v_world_pos;

// Henyey-Greenstein phase function for aerosol/Mie scattering
float henyey_greenstein(float cos_theta, float g) {
	float g2 = g * g;
	float denom = 1.0 + g2 - 2.0 * g * cos_theta;
	return (1.0 - g2) / (4.0 * 3.14159265 * pow(max(denom, 0.0001), 1.5));
}

// Rayleigh phase function
float rayleigh_phase(float cos_theta) {
	return 0.75 * (1.0 + cos_theta * cos_theta);
}

void vertex() {
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_world_normal = normalize((MODEL_MATRIX * vec4(-NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 V = normalize(CAMERA_POSITION_WORLD - v_world_pos);
	vec3 N = normalize(v_world_normal);
	vec3 L = normalize(sun_direction);

	float v_dot_n = clamp(dot(V, N), 0.0, 1.0);
	float n_dot_l = dot(N, L);
	float cos_theta = dot(V, L);

	if (quality_tier == 0) {
		// LOW QUALITY TIER (Mobile / Fast Analytic)
		float rim = pow(1.0 - v_dot_n, 3.2);
		float day_factor = smoothstep(-0.05, 0.25, n_dot_l);
		float sunset_factor = smoothstep(-0.25, -0.02, n_dot_l) * (1.0 - smoothstep(0.02, 0.22, n_dot_l));
		
		vec3 scatter = mix(rayleigh_day_color, rayleigh_sunset_color, sunset_factor);
		float mie = pow(max(0.0, cos_theta), 12.0) * mie_phase_strength * (day_factor + sunset_factor * 1.5);
		
		vec3 col = scatter * rim * atmosphere_density * (day_factor + sunset_factor * 1.5) * sun_intensity;
		col += vec3(1.0, 0.95, 0.85) * mie * rim;
		ALBEDO = col;
	} else {
		// HIGH QUALITY TIER (Desktop / Multi-term Physical Model)
		// Approximate Chapman grazing optical depth along view ray
		float grazing_rim = pow(1.0 - v_dot_n, rim_falloff_power);
		float inner_glow = pow(1.0 - v_dot_n, rim_falloff_power * 0.45) * 0.25;
		float total_rim = grazing_rim + inner_glow;

		// Solar zenith extinction weights
		float day_weight = smoothstep(-0.04, 0.28, n_dot_l);
		float sunset_weight = smoothstep(-0.24, -0.02, n_dot_l) * (1.0 - smoothstep(0.01, 0.24, n_dot_l));
		float night_weight = 1.0 - smoothstep(-0.16, 0.06, n_dot_l);

		// Multi-wavelength Rayleigh scattering with sunset reddening
		vec3 scatter_color = mix(rayleigh_day_color, rayleigh_sunset_color, sunset_weight * 0.95);
		
		// Phase functions
		float r_phase = rayleigh_phase(cos_theta);
		float m_phase = henyey_greenstein(cos_theta, mie_eccentricity) * 4.0 * 3.14159265;

		// Stratospheric Chappuis ozone absorption (subtle turquoise layer above sunset arc)
		float ozone_band = pow(1.0 - v_dot_n, 2.6) * (1.0 - pow(1.0 - v_dot_n, 7.5));
		scatter_color = mix(scatter_color, ozone_tint_color, ozone_band * 0.38 * day_weight);

		// Mie forward scattering halo
		float mie_glow = m_phase * mie_phase_strength * (day_weight + sunset_weight * 1.8) * 0.25;

		// Mesospheric atomic oxygen airglow ribbon (green line on dark limb)
		float airglow_rim = pow(1.0 - v_dot_n, 8.5) * airglow_intensity;
		vec3 airglow = airglow_green_color * airglow_rim * (0.3 + 0.7 * night_weight);

		// Final atmospheric radiance composition
		vec3 final_color = scatter_color * r_phase * total_rim * atmosphere_density * (day_weight + sunset_weight * 1.6);
		final_color += vec3(1.0, 0.94, 0.85) * mie_glow * total_rim;
		final_color += airglow;
		final_color *= sun_intensity;

		ALBEDO = final_color;
	}
}
