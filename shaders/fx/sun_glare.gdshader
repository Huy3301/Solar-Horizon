shader_type spatial;
render_mode blend_add, depth_draw_never, cull_disabled, unshaded;

// High-Dynamic-Range Sun Glare & Lens Flare Billboard Shader
// Features:
// 1. Intense solar core disc with HDR bloom trigger (> 1.0)
// 2. Multi-stage radial corona halo
// 3. Diffraction spikes (4-point / 6-point) with anamorphic flare streak
// 4. Subtle chromatic ghost rings
// 5. Dynamic eclipse attenuation factor (0.0 = eclipsed, 1.0 = full sun)
// 6. Quality tier support: Low (core + corona only) vs High (full flare & spikes)

uniform int quality_tier : hint_range(0, 1) = 1;

uniform vec3 sun_color : source_color = vec3(1.0, 0.98, 0.92);
uniform float core_intensity : hint_range(1.0, 50.0) = 12.0;
uniform float corona_intensity : hint_range(0.0, 10.0) = 2.5;
uniform float spike_intensity : hint_range(0.0, 10.0) = 1.8;
uniform float eclipse_factor : hint_range(0.0, 1.0) = 1.0;
uniform float flare_scale : hint_range(0.1, 5.0) = 1.0;

varying vec2 v_uv;

void vertex() {
	v_uv = UV * 2.0 - 1.0; // [-1, 1] centred coordinates
	
	// Billboard facing camera
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(
		INV_VIEW_MATRIX[0],
		INV_VIEW_MATRIX[1],
		INV_VIEW_MATRIX[2],
		MODEL_MATRIX[3]
	);
}

void fragment() {
	vec2 p = v_uv / max(0.001, flare_scale);
	float dist = length(p);

	if (dist > 1.0 || eclipse_factor <= 0.0001) {
		ALBEDO = vec3(0.0);
		ALPHA = 0.0;
	} else {
		// Solar core
		float core = exp(-dist * 18.0) * core_intensity;
		
		// Corona halo
		float corona = pow(clamp(1.0 - dist, 0.0, 1.0), 3.5) * corona_intensity;
		float wide_glow = pow(clamp(1.0 - dist * 0.7, 0.0, 1.0), 5.0) * 0.6;

		vec3 flare_rgb = sun_color * (core + corona + wide_glow);

		if (quality_tier == 1) {
			// HIGH QUALITY TIER: Diffraction spikes & anamorphic streak
			float spike_x = exp(-abs(p.y) * 45.0) * exp(-abs(p.x) * 3.5);
			float spike_y = exp(-abs(p.x) * 45.0) * exp(-abs(p.y) * 3.5);
			
			// Diagonal spikes
			vec2 p_rot = vec2(p.x + p.y, p.x - p.y) * 0.7071;
			float diag_x = exp(-abs(p_rot.y) * 55.0) * exp(-abs(p_rot.x) * 4.5) * 0.5;
			float diag_y = exp(-abs(p_rot.x) * 55.0) * exp(-abs(p_rot.y) * 4.5) * 0.5;

			// Horizontal anamorphic streak
			float streak = exp(-abs(p.y) * 120.0) * exp(-abs(p.x) * 1.8) * 1.2;
			vec3 streak_color = mix(sun_color, vec3(0.5, 0.7, 1.0), 0.35);

			float spikes = (spike_x + spike_y + diag_x + diag_y) * spike_intensity;
			flare_rgb += sun_color * spikes;
			flare_rgb += streak_color * streak * spike_intensity;

			// Subtle ghost ring
			float ring_dist = abs(dist - 0.42);
			float ring = exp(-ring_dist * 28.0) * 0.35;
			vec3 ring_color = mix(vec3(0.4, 0.6, 1.0), vec3(1.0, 0.7, 0.3), dist);
			flare_rgb += ring_color * ring;
		}

		flare_rgb *= eclipse_factor;
		ALBEDO = flare_rgb;
		ALPHA = clamp(max(flare_rgb.r, max(flare_rgb.g, flare_rgb.b)), 0.0, 1.0);
	}
}
