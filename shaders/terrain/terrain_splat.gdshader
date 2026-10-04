shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

// Texture arrays for materials to save bindings and batch draw calls
uniform sampler2DArray albedo_array : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2DArray normal_roughness_array : filter_linear_mipmap_anisotropic, repeat_enable;

// Indices in the texture array. x: dirt, y: grass, z: rock, w: snow
uniform vec4 layer_indices = vec4(0.0, 1.0, 2.0, 3.0);

uniform float slope_threshold : hint_range(0.0, 1.0) = 0.8;
uniform float slope_blend : hint_range(0.0, 1.0) = 0.1;
uniform float snow_height : hint_range(0.0, 5000.0) = 1500.0;
uniform float snow_blend : hint_range(0.0, 500.0) = 100.0;
uniform float texture_scale = 10.0;
uniform float ao_strength = 1.0;

varying vec3 world_pos;
varying vec3 world_normal;
varying float v_ao;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = (MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz;
	
	// Assuming AO is baked into COLOR.r for horizon AO
	v_ao = COLOR.r;
}

void fragment() {
	vec2 uv = world_pos.xz / texture_scale;
	
	// Calculate slope
	float up_dot = dot(normalize(world_normal), vec3(0.0, 1.0, 0.0));
	
	// Blend weights
	float rock_w = smoothstep(slope_threshold, slope_threshold - slope_blend, up_dot);
	float snow_w = smoothstep(snow_height - snow_blend, snow_height + snow_blend, world_pos.y) * (1.0 - rock_w);
	float grass_w = (1.0 - rock_w) * (1.0 - snow_w);
	
	// Normalize
	float total_w = rock_w + snow_w + grass_w;
	rock_w /= total_w;
	snow_w /= total_w;
	grass_w /= total_w;
	
	// Sample texture arrays
	vec4 rock_albedo = texture(albedo_array, vec3(uv, layer_indices.z));
	vec4 snow_albedo = texture(albedo_array, vec3(uv, layer_indices.w));
	vec4 grass_albedo = texture(albedo_array, vec3(uv, layer_indices.y));
	
	vec4 rock_nr = texture(normal_roughness_array, vec3(uv, layer_indices.z));
	vec4 snow_nr = texture(normal_roughness_array, vec3(uv, layer_indices.w));
	vec4 grass_nr = texture(normal_roughness_array, vec3(uv, layer_indices.y));
	
	// Mix
	vec4 final_albedo = rock_albedo * rock_w + snow_albedo * snow_w + grass_albedo * grass_w;
	vec4 final_nr = rock_nr * rock_w + snow_nr * snow_w + grass_nr * grass_w;
	
	ALBEDO = final_albedo.rgb * mix(1.0, v_ao, ao_strength);
	ROUGHNESS = final_nr.g;
	NORMAL_MAP = final_nr.rgb;
	NORMAL_MAP_DEPTH = 1.0;
}
