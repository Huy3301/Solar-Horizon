shader_type spatial;
render_mode blend_mix, depth_draw_opaque, unshaded;

// Volumetric clouds for desktop
uniform sampler3D noise_texture;
uniform vec3 wind_direction = vec3(1.0, 0.0, 0.0);
uniform float wind_speed = 1.0;
uniform float cloud_coverage = 0.5;

void fragment() {
	vec3 wpos = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 sample_pos = wpos * 0.01 + wind_direction * TIME * wind_speed;
	
	// Raymarching stub
	float density = texture(noise_texture, sample_pos).r;
	density = smoothstep(1.0 - cloud_coverage, 1.0, density);
	
	ALBEDO = vec3(1.0);
	ALPHA = density * 0.8;
}
