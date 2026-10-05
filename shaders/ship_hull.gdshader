shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

// Spacecraft Hull PBR & Re-entry Thermal Glow Shader (WP 3.5)
// Simulates spacecraft hull surface materials with PBR properties (albedo, ORM, normal, procedural panel seams)
// and incandescent blackbody aerothermal re-entry heating glow.

// Surface PBR Uniforms
uniform vec4 albedo_color : source_color = vec4(0.9, 0.9, 0.92, 1.0);
uniform sampler2D albedo_texture : source_color, hint_default_white, filter_linear_mipmap, repeat_enable;
uniform sampler2D orm_texture : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform sampler2D normal_texture : hint_normal, filter_linear_mipmap, repeat_enable;

// Procedural Plating & Seam Detailing
uniform float panel_lines_intensity : hint_range(0.0, 1.0) = 0.4;
uniform float panel_lines_scale : hint_range(1.0, 64.0) = 16.0;

// Material Tuning
uniform float roughness : hint_range(0.0, 1.0) = 0.5;
uniform float metallic : hint_range(0.0, 1.0) = 0.8;
uniform float normal_scale : hint_range(-16.0, 16.0) = 1.0;

// Dynamic Re-entry Heating Uniforms
uniform float reentry_heat : hint_range(0.0, 1.0) = 0.0;
uniform vec4 heat_glow_color : source_color = vec4(1.0, 0.35, 0.05, 1.0);
uniform float underside_bias : hint_range(0.0, 5.0) = 1.0;

// Varyings passed from vertex to fragment
varying vec3 v_local_normal;
varying vec3 v_local_pos;

// Planck thermal blackbody radiation spectrum progression:
// Deep cherry red (~900K) -> incandescent orange (~1400K) -> hot white-yellow (~2200K+)
vec3 calculate_blackbody_glow(float heat, vec3 base_glow) {
	vec3 deep_red = vec3(0.55, 0.025, 0.008);
	vec3 orange = base_glow;
	vec3 hot_white = vec3(1.0, 0.96, 0.84);
	
	float stage1 = clamp(heat / 0.45, 0.0, 1.0);
	float stage2 = clamp((heat - 0.45) / 0.55, 0.0, 1.0);
	
	vec3 col = mix(deep_red, orange, smoothstep(0.0, 1.0, stage1));
	col = mix(col, hot_white, smoothstep(0.0, 1.0, stage2));
	return col;
}

void vertex() {
	v_local_normal = normalize(NORMAL);
	v_local_pos = VERTEX;
}

void fragment() {
	// Sample textures
	vec4 albedo_tex = texture(albedo_texture, UV);
	vec4 orm_sample = texture(orm_texture, UV);
	
	// Procedural hull panel lines / seams
	float panel_seam = 0.0;
	if (panel_lines_intensity > 0.001) {
		vec2 panel_uv = fract(UV * panel_lines_scale);
		vec2 edge_dist = min(panel_uv, vec2(1.0) - panel_uv);
		float min_edge = min(edge_dist.x, edge_dist.y);
		panel_seam = 1.0 - smoothstep(0.008, 0.038, min_edge);
	}
	
	// Albedo modulation (darken panel seams for crevice dirt and depth)
	vec3 base_albedo = albedo_color.rgb * albedo_tex.rgb;
	vec3 final_albedo = mix(base_albedo, base_albedo * 0.28, panel_seam * panel_lines_intensity);
	
	// ORM mapping (Red = AO, Green = Roughness, Blue = Metallic)
	float ao_val = orm_sample.r;
	ao_val = mix(ao_val, ao_val * 0.35, panel_seam * panel_lines_intensity);
	
	float roughness_val = orm_sample.g * roughness;
	roughness_val = mix(roughness_val, min(1.0, roughness_val + 0.35), panel_seam * panel_lines_intensity);
	
	float metallic_val = orm_sample.b * metallic;
	metallic_val = mix(metallic_val, 0.0, panel_seam * panel_lines_intensity);
	
	// Apply PBR surface properties
	ALBEDO = final_albedo;
	ROUGHNESS = roughness_val;
	METALLIC = metallic_val;
	SPECULAR = 0.5;
	AO = ao_val;
	
	// Normal mapping
	NORMAL_MAP = texture(normal_texture, UV).rgb;
	NORMAL_MAP_DEPTH = normal_scale;
	
	// Incandescent blackbody thermal emission during hypersonic atmospheric re-entry
	if (reentry_heat > 0.0001) {
		// Aerothermal flow impingement vector:
		// Forward is -Z (nosecone stagnation) and underside is -Y (vessel belly heat shield).
		// Underside bias concentrates heating on the heat shield belly tiles.
		vec3 flow_target = normalize(vec3(0.0, -max(underside_bias, 0.001), -1.0));
		
		// Normal dot product with incoming flow direction
		vec3 norm_local = normalize(v_local_normal);
		float flow_dot = dot(norm_local, flow_target);
		float local_facing = clamp(flow_dot, 0.0, 1.0);
		
		// Compression heating profile with slight radiative bleed around fuselage
		float heat_exposure = mix(0.04 * reentry_heat, 1.0, pow(local_facing, 1.25));
		float effective_heat = clamp(reentry_heat * heat_exposure, 0.0, 1.0);
		
		// Exponential ramp (heat^2.5) simulating Stefan-Boltzmann / Planck thermal radiation curve
		float heat_ramp = pow(effective_heat, 2.5);
		
		// Blackbody thermal color progression (deep red -> orange -> hot white-yellow)
		vec3 blackbody_color = calculate_blackbody_glow(effective_heat, heat_glow_color.rgb);
		
		// Subtle thermal shimmer and emissive pulsation from hypersonic boundary layer turbulence
		float shimmer_freq = 14.0;
		float shimmer_wave1 = sin(TIME * shimmer_freq + v_local_pos.y * 6.5 + v_local_pos.z * 11.0);
		float shimmer_wave2 = cos(TIME * (shimmer_freq * 1.37) - v_local_pos.x * 8.5);
		float thermal_shimmer = 1.0 + 0.08 * (shimmer_wave1 * 0.6 + shimmer_wave2 * 0.4);
		
		// Heat concentration in tile seams
		float seam_boost = 1.0 + 0.15 * (panel_seam * panel_lines_intensity);
		
		// Radiance output for HDR bloom and glow
		float radiance = heat_ramp * 7.5 * thermal_shimmer * seam_boost;
		EMISSION = blackbody_color * radiance;
	} else {
		EMISSION = vec3(0.0);
	}
}
