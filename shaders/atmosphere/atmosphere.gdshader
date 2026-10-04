shader_type sky;

uniform sampler2D transmittance_lut : hint_default_black;
uniform sampler2D multiscattering_lut : hint_default_black;
uniform sampler2D skyview_lut : hint_default_black;
uniform vec3 sun_direction = vec3(0.0, 1.0, 0.0);
uniform float sun_intensity = 1.0;

void sky() {
	// Simple mapping of sky view LUT
	vec2 uv = EYEDIR.xy * 0.5 + 0.5;
	vec3 sky_color = texture(skyview_lut, uv).rgb;
	
	// Add sun
	float sun = max(0.0, dot(EYEDIR, sun_direction));
	sun = pow(sun, 500.0) * sun_intensity;
	
	COLOR = sky_color + vec3(sun);
}
