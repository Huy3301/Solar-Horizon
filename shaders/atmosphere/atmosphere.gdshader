shader_type sky;

// Earth / Planetary Atmosphere Sky Shader
// Supports both Hillaire skyview LUT sampling and analytic Rayleigh + Mie fallback.

uniform sampler2D transmittance_lut : hint_default_black;
uniform sampler2D multiscattering_lut : hint_default_black;
uniform sampler2D skyview_lut : hint_default_black;
uniform bool use_lut = false;

uniform vec3 sun_direction = vec3(0.0, 0.4, 0.9);
uniform float sun_intensity : hint_range(0.0, 5.0) = 1.0;
uniform vec3 rayleigh_day_color : source_color = vec3(0.18, 0.58, 1.0);
uniform vec3 rayleigh_sunset_color : source_color = vec3(1.0, 0.40, 0.10);
uniform vec3 ground_color : source_color = vec3(0.08, 0.12, 0.15);
uniform float mie_phase_strength : hint_range(0.0, 5.0) = 2.0;

void sky() {
	vec3 dir = normalize(EYEDIR);
	vec3 L = normalize(sun_direction);

	if (use_lut) {
		vec2 uv = dir.xy * 0.5 + 0.5;
		vec3 sky_color = texture(skyview_lut, uv).rgb;
		float sun = max(0.0, dot(dir, L));
		sun = pow(sun, 500.0) * sun_intensity;
		COLOR = sky_color + vec3(sun);
		return;
	}

	// Analytic physical sky model
	float cos_zenith = dir.y;
	float cos_theta = dot(dir, L);
	float sun_zenith = L.y;

	// Rayleigh optical mass
	float zenith_clamped = max(cos_zenith, 0.02);
	float optical_mass = 1.0 / (zenith_clamped + 0.05);

	// Sunset weighting based on solar elevation
	float sunset_factor = smoothstep(0.25, -0.05, sun_zenith);
	vec3 sky_tint = mix(rayleigh_day_color, rayleigh_sunset_color, sunset_factor);

	// Rayleigh phase: 0.75 * (1 + cos^2 theta)
	float r_phase = 0.75 * (1.0 + cos_theta * cos_theta);

	// In-scattering sky color
	vec3 sky_col = sky_tint * r_phase * (1.0 - exp(-optical_mass * 0.45));

	// Mie solar halo
	float m_phase = pow(max(0.0, cos_theta), 48.0) * mie_phase_strength;
	vec3 mie_sun = mix(vec3(1.0, 0.95, 0.85), rayleigh_sunset_color, sunset_factor) * m_phase;

	// Solar disk
	float sun_disk = smoothstep(0.9995, 0.9999, cos_theta) * 15.0;

	// Sky vs ground transition below horizon
	float horizon_mask = smoothstep(-0.04, 0.04, dir.y);
	vec3 final_sky = mix(ground_color, (sky_col + mie_sun + vec3(sun_disk)) * sun_intensity, horizon_mask);

	COLOR = final_sky;
}
