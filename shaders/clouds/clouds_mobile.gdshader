shader_type spatial;
render_mode blend_mix, depth_draw_opaque, unshaded;

// Parallax/layered clouds for mobile
uniform sampler2D cloud_texture;
uniform vec3 wind_direction = vec3(1.0, 0.0, 0.0);
uniform float wind_speed = 1.0;
uniform int layers = 3;

void fragment() {
	vec2 uv = UV + wind_direction.xy * TIME * wind_speed;
	float alpha = 0.0;
	vec3 color = vec3(1.0);
	
	// Parallax layers stub
	for(int i = 0; i < layers; i++) {
		vec2 layer_uv = uv + vec2(float(i) * 0.01);
		alpha += texture(cloud_texture, layer_uv).r * 0.3;
	}
	
	ALBEDO = color;
	ALPHA = clamp(alpha, 0.0, 1.0);
}
