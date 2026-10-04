shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

// Gerstner Wave shader for mobile Vulkan
// Includes depth fading and basic foam.

uniform vec3 albedo : source_color = vec3(0.0, 0.4, 0.7);
uniform vec3 shallow_color : source_color = vec3(0.0, 0.7, 0.8);
uniform float metallic : hint_range(0.0, 1.0) = 0.0;
uniform float roughness : hint_range(0.0, 1.0) = 0.1;
uniform sampler2D depth_texture : hint_depth_texture, filter_linear_mipmap;

uniform float wave_amplitude = 1.0;
uniform float wave_frequency = 1.0;
uniform float wave_speed = 1.0;
uniform vec2 wave_direction = vec2(1.0, 0.0);

uniform float depth_blend_distance = 10.0;
uniform float foam_distance = 2.0;
uniform vec3 foam_color : source_color = vec3(1.0, 1.0, 1.0);

// For large scale origin rebasing, we can pass an offset to the time/position
uniform vec3 origin_offset = vec3(0.0);

void vertex() {
	vec3 world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz + origin_offset;
	
	float time_val = TIME * wave_speed;
	float k = wave_frequency;
	
	float dot_dir = dot(world_pos.xz, normalize(wave_direction));
	float f = k * dot_dir - time_val;
	
	float a = wave_amplitude;
	
	// Basic single gerstner wave for mobile performance
	// Can be extended to 3-4 waves if needed
	VERTEX.y += a * sin(f);
	VERTEX.x += a * cos(f) * wave_direction.x;
	VERTEX.z += a * cos(f) * wave_direction.y;
}

void fragment() {
	// Depth fading
	float depth = texture(depth_texture, SCREEN_UV).r;
	
	// Linearize depth
	vec3 ndc = vec3(SCREEN_UV * 2.0 - 1.0, depth);
	vec4 view = INV_PROJECTION_MATRIX * vec4(ndc, 1.0);
	view.xyz /= view.w;
	float linear_depth = -view.z;
	
	float z_pos = FRAGCOORD.z;
	vec4 view_pos = INV_PROJECTION_MATRIX * vec4(vec3(SCREEN_UV * 2.0 - 1.0, z_pos), 1.0);
	view_pos.xyz /= view_pos.w;
	float fragment_depth = -view_pos.z;
	
	float depth_diff = linear_depth - fragment_depth;
	
	// Blend colors based on depth
	float depth_blend = clamp(depth_diff / depth_blend_distance, 0.0, 1.0);
	vec3 final_color = mix(shallow_color, albedo, depth_blend);
	
	// Foam
	float foam_blend = clamp(1.0 - (depth_diff / foam_distance), 0.0, 1.0);
	// Basic foam wave patterns can be added here
	final_color = mix(final_color, foam_color, foam_blend * 0.8); // Simple fade foam
	
	ALBEDO = final_color;
	METALLIC = metallic;
	ROUGHNESS = roughness;
}
