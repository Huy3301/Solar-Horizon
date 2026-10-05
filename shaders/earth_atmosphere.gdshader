shader_type spatial;
render_mode blend_add, depth_draw_never, cull_front, unshaded;

// Photorealistic Earth atmospheric Rayleigh + Mie scattering shell
// Features:
// 1. Physically-inspired wavelength-dependent Rayleigh scattering (blue day, crimson sunset)
// 2. Forward Mie solar corona flare on the limb when the sun is behind Earth (orbital sunrise/sunset "diamond ring" effect seen from LEO)
// 3. Polar auroral curtains (Aurora Australis / Borealis) animated at latitudes > 55 deg with dual-tone green (557.7 nm) and crimson (630 nm) emissions along the dark limb
// 4. Night-side urban atmospheric diffusion: cities on the night side emit a warm golden atmospheric halo above major landmasses
// 5. Chappuis ozone absorption layer (turquoise gradient between troposphere and space)
// 6. Mesospheric atomic oxygen airglow ribbon (557.7nm green line) along dark limb
// 7. Quality tier support: Low (mobile/fast analytic) vs High (multi-term physical)

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

// Polar Aurora uniforms
uniform float aurora_intensity : hint_range(0.0, 3.0) = 0.85;
uniform vec3 aurora_green_color : source_color = vec3(0.12, 0.98, 0.48);
uniform vec3 aurora_crimson_color : source_color = vec3(0.92, 0.18, 0.32);

// Night-side urban atmospheric diffusion uniforms
uniform sampler2D city_lights_mask : hint_default_black, filter_linear_mipmap, repeat_enable;
uniform float city_diffusion_intensity : hint_range(0.0, 3.0) = 0.65;
uniform vec3 city_diffusion_color : source_color = vec3(1.0, 0.82, 0.48);
uniform float planet_rotation : hint_range(-6.28318, 6.28318) = 0.0;

varying vec3 v_world_normal;
varying vec3 v_world_pos;
varying vec3 v_model_pos;
varying vec2 v_uv;

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
	v_model_pos = VERTEX;
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_world_normal = normalize((MODEL_MATRIX * vec4(-NORMAL, 0.0)).xyz);
	v_uv = UV;
}

void fragment() {
	vec3 V = normalize(CAMERA_POSITION_WORLD - v_world_pos);
	vec3 N = normalize(v_world_normal);
	vec3 L = normalize(sun_direction);

	float v_dot_n = clamp(dot(V, N), 0.0, 1.0);
	float n_dot_l = dot(N, L);
	float cos_theta = dot(V, L);
	float forward_sun = max(0.0, dot(-V, L));

	// City lights UV with planet rotation
	vec2 city_uv = vec2(fract(v_uv.x + planet_rotation / (2.0 * PI)), v_uv.y);

	// Polar coordinates for auroral curtains (|lat| > 55 deg)
	vec3 norm_model = normalize(v_model_pos);
	float abs_lat = abs(norm_model.y);

	if (quality_tier == 0) {
		// LOW QUALITY TIER (Mobile / Fast Analytic)
		float rim = pow(1.0 - v_dot_n, 3.2);
		float day_factor = smoothstep(-0.05, 0.25, n_dot_l);
		float sunset_factor = smoothstep(-0.25, -0.02, n_dot_l) * (1.0 - smoothstep(0.02, 0.22, n_dot_l));
		float night_factor = 1.0 - smoothstep(-0.15, 0.05, n_dot_l);
		
		vec3 scatter = mix(rayleigh_day_color, rayleigh_sunset_color, sunset_factor);
		float mie = pow(max(0.0, cos_theta), 12.0) * mie_phase_strength * (day_factor + sunset_factor * 1.5);
		
		vec3 col = scatter * rim * atmosphere_density * (day_factor + sunset_factor * 1.5) * sun_intensity;
		col += vec3(1.0, 0.95, 0.85) * mie * rim;

		// Fast forward Mie solar corona flare on the limb (orbital sunrise/sunset diamond ring)
		float corona_low = pow(forward_sun, 18.0) * pow(1.0 - v_dot_n, 2.5) * smoothstep(-0.35, 0.15, n_dot_l);
		col += vec3(1.0, 0.85, 0.65) * corona_low * 3.0 * sun_intensity;

		// Fast analytic polar aurora (> 55 degrees)
		float polar_low = smoothstep(0.819, 0.96, abs_lat);
		vec3 aurora_col_low = mix(aurora_green_color, aurora_crimson_color, pow(1.0 - v_dot_n, 3.0));
		col += aurora_col_low * polar_low * pow(1.0 - v_dot_n, 3.5) * night_factor * aurora_intensity * 1.5;

		// Fast night-side urban atmospheric diffusion
		vec3 city_sample_low = texture(city_lights_mask, city_uv).rgb;
		float city_lum_low = dot(city_sample_low, vec3(0.299, 0.587, 0.114));
		col += city_diffusion_color * city_lum_low * pow(1.0 - v_dot_n, 2.0) * city_diffusion_intensity * night_factor * 1.8;

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

		// Mesospheric atomic oxygen airglow ribbon (557.7nm green line on dark limb)
		float airglow_rim = pow(1.0 - v_dot_n, 8.5) * airglow_intensity;
		vec3 airglow = airglow_green_color * airglow_rim * (0.3 + 0.7 * night_weight);

		// Forward Mie solar corona flare on the limb when sun is behind Earth (orbital sunrise/sunset diamond ring)
		float corona_rim = pow(1.0 - v_dot_n, 2.4);
		float sun_behind = smoothstep(-0.35, 0.15, n_dot_l);
		float corona_core = pow(forward_sun, 26.0) * corona_rim * sun_behind;
		float corona_burst = pow(forward_sun, 60.0) * pow(1.0 - v_dot_n, 1.8) * sun_behind;
		vec3 corona_color = mix(vec3(1.0, 0.48, 0.14), vec3(1.0, 0.98, 0.92), smoothstep(0.65, 0.96, forward_sun));
		vec3 corona = corona_color * (corona_core * 3.2 + corona_burst * 6.5);

		// Polar auroral curtains (Aurora Australis / Borealis) animated at latitudes > 55 deg
		// Dual-tone green (557.7 nm) lower emission and crimson (630 nm) upper emission along dark limb
		float polar_mask = smoothstep(0.819, 0.96, abs_lat);
		float phi = atan(norm_model.x, norm_model.z);
		float curtain_undulation = sin(phi * 18.0 + TIME * 0.55) * 0.5 + 0.5;
		float curtain_streamers = sin(phi * 44.0 - TIME * 1.1 + norm_model.y * 16.0) * 0.5 + 0.5;
		float curtain_fold = pow(curtain_undulation * 0.65 + curtain_streamers * 0.35, 2.2);
		float aurora_rim_green = pow(1.0 - v_dot_n, 4.2) * (1.0 - pow(1.0 - v_dot_n, 14.0));
		float aurora_rim_crimson = pow(1.0 - v_dot_n, 8.0);
		vec3 aurora = (aurora_green_color * aurora_rim_green * 2.2 + aurora_crimson_color * aurora_rim_crimson * 1.8)
		              * curtain_fold * polar_mask * night_weight * aurora_intensity;

		// Night-side urban atmospheric diffusion: cities emit a warm golden halo above major landmasses
		vec3 city_sample = texture(city_lights_mask, city_uv).rgb;
		float city_lum = dot(city_sample, vec3(0.299, 0.587, 0.114));
		float city_halo_rim = pow(1.0 - v_dot_n, 2.2) * 0.75 + pow(1.0 - v_dot_n, 1.2) * 0.25;
		vec3 city_halo = city_diffusion_color * city_lum * city_halo_rim * city_diffusion_intensity * night_weight * 2.2;

		// Altitude-adaptive inner disk haze for seamless low-orbit aerial perspective
		float inner_disk_haze = pow(1.0 - v_dot_n, 1.8) * 0.22 * day_weight;
		vec3 inner_haze_color = rayleigh_day_color * inner_disk_haze;

		// Final atmospheric radiance composition
		vec3 final_color = scatter_color * r_phase * total_rim * atmosphere_density * (day_weight + sunset_weight * 1.6);
		final_color += vec3(1.0, 0.94, 0.85) * mie_glow * total_rim;
		final_color += airglow;
		final_color += corona;
		final_color += aurora;
		final_color += city_halo;
		final_color += inner_haze_color;
		final_color *= sun_intensity;

		ALBEDO = final_color;
	}
}
