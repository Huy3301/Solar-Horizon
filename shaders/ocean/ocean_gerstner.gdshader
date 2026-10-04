shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

// High-Fidelity Spherical Gerstner Ocean Shader
// Supports Mobile (tier 0) and Desktop (tier 1) variants, depth color attenuation,
// shoreline and wave crest foam, solar glint, and planetary horizon blending.

uniform int quality_tier : hint_range(0, 1) = 1;

// Colors
uniform vec3 albedo : source_color = vec3(0.01, 0.08, 0.25); // Deep ocean
uniform vec3 shallow_color : source_color = vec3(0.04, 0.65, 0.75); // Coastal turquoise
uniform vec3 foam_color : source_color = vec3(0.96, 0.98, 1.0);
uniform vec3 horizon_color : source_color = vec3(0.45, 0.65, 0.85);

// Material properties
uniform float metallic : hint_range(0.0, 1.0) = 0.05;
uniform float roughness : hint_range(0.0, 1.0) = 0.08;
uniform sampler2D depth_texture : hint_depth_texture, filter_linear_mipmap;

// Wave dynamics
uniform float wave_amplitude = 1.2;
uniform float wave_frequency = 0.005;
uniform float wave_speed = 1.2;
uniform vec3 sun_direction = vec3(0.707, 0.35, 0.612);

// Depth & Foam tuning
uniform float depth_blend_distance = 25.0;
uniform float foam_distance = 4.0;
uniform float sun_glint_intensity = 3.5;

// Floating origin offset
uniform vec3 origin_offset = vec3(0.0);

varying vec3 v_world_pos;
varying vec3 v_normal;
varying float v_wave_height;
varying vec3 v_sphere_normal;

// Single Gerstner Wave calculation on spherical tangent plane
void add_gerstner_wave(
	inout vec3 p,
	inout vec3 n,
	vec3 sphere_n,
	vec2 dir,
	float amp,
	float freq,
	float speed,
	float t,
	float Q
) {
	vec2 d = normalize(dir);
	
	// Create local tangent frame perpendicular to sphere normal
	vec3 tangent = normalize(abs(sphere_n.y) < 0.999 ? cross(vec3(0.0, 1.0, 0.0), sphere_n) : cross(vec3(1.0, 0.0, 0.0), sphere_n));
	vec3 bitangent = cross(sphere_n, tangent);
	
	// Project position onto tangent plane
	float u = dot(p, tangent);
	float v = dot(p, bitangent);
	float dot_dir = d.x * u + d.y * v;
	
	float phase = freq * dot_dir - t * speed;
	float sin_p = sin(phase);
	float cos_p = cos(phase);
	
	// Displacement along sphere normal
	p += sphere_n * (amp * sin_p);
	// Horizontal displacement along wave propagation direction
	p -= (tangent * d.x + bitangent * d.y) * (Q * amp * cos_p);
	
	// Normal perturbation
	float wa = freq * amp;
	n -= (tangent * d.x + bitangent * d.y) * (wa * cos_p);
}

void vertex() {
	v_sphere_normal = normalize(VERTEX);
	vec3 p = VERTEX;
	vec3 n = v_sphere_normal;
	float t = TIME * wave_speed;
	
	// Wave 1: Primary ocean swell
	add_gerstner_wave(p, n, v_sphere_normal, vec2(1.0, 0.3), wave_amplitude, wave_frequency, 1.0, t, 0.4);
	// Wave 2: Secondary cross swell
	add_gerstner_wave(p, n, v_sphere_normal, vec2(-0.4, 0.9), wave_amplitude * 0.5, wave_frequency * 2.1, 1.3, t, 0.35);
	
	if (quality_tier == 1) {
		// Wave 3: Wind chop (desktop tier)
		add_gerstner_wave(p, n, v_sphere_normal, vec2(0.7, -0.6), wave_amplitude * 0.25, wave_frequency * 4.5, 1.7, t, 0.25);
		// Wave 4: Capillary ripples (desktop tier)
		add_gerstner_wave(p, n, v_sphere_normal, vec2(-0.8, -0.5), wave_amplitude * 0.12, wave_frequency * 9.2, 2.3, t, 0.20);
	}
	
	VERTEX = p;
	v_wave_height = dot(p - VERTEX, v_sphere_normal) / max(0.1, wave_amplitude);
	v_normal = normalize(n);
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz + origin_offset;
}

void fragment() {
	// Linearized depth calculation
	float depth_raw = texture(depth_texture, SCREEN_UV).r;
	vec3 ndc = vec3(SCREEN_UV * 2.0 - 1.0, depth_raw);
	vec4 view = INV_PROJECTION_MATRIX * vec4(ndc, 1.0);
	view.xyz /= view.w;
	float linear_scene_depth = -view.z;
	
	float frag_z = FRAGCOORD.z;
	vec4 view_pos = INV_PROJECTION_MATRIX * vec4(vec3(SCREEN_UV * 2.0 - 1.0, frag_z), 1.0);
	view_pos.xyz /= view_pos.w;
	float linear_frag_depth = -view_pos.z;
	
	float water_depth = max(0.0, linear_scene_depth - linear_frag_depth);
	
	// Depth-based color absorption
	float depth_factor = 1.0 - exp(-water_depth / depth_blend_distance);
	vec3 water_color = mix(shallow_color, albedo, clamp(depth_factor, 0.0, 1.0));
	
	// Foam: Shoreline foam + Wave crest foam
	float shore_foam = clamp(1.0 - (water_depth / foam_distance), 0.0, 1.0);
	float crest_foam = smoothstep(0.45, 0.85, v_wave_height);
	float total_foam = clamp(max(shore_foam, crest_foam * 0.7), 0.0, 1.0);
	vec3 color_with_foam = mix(water_color, foam_color, total_foam * 0.85);
	
	// Horizon / Limb blending (Fresnel blend to horizon color at grazing angles)
	vec3 N = normalize(NORMAL);
	vec3 V = normalize(VIEW);
	float NdotV = clamp(dot(N, V), 0.0, 1.0);
	float fresnel = pow(1.0 - NdotV, 4.0);
	vec3 final_color = mix(color_with_foam, horizon_color, fresnel * 0.35);
	
	// Solar Glint: High-intensity microfacet specular glint
	vec3 L = normalize(sun_direction);
	vec3 H = normalize(L + V);
	float NdotH = max(0.0, dot(N, H));
	float NdotL = max(0.0, dot(N, L));
	float spec_power = (quality_tier == 1) ? 256.0 : 64.0;
	float glint = pow(NdotH, spec_power) * NdotL * (1.0 - total_foam * 0.6);
	vec3 glint_emission = vec3(1.0, 0.95, 0.85) * glint * sun_glint_intensity;
	
	ALBEDO = final_color;
	METALLIC = metallic;
	ROUGHNESS = mix(roughness, 0.45, fresnel); // Increase roughness at grazing distance to avoid specular aliasing
	SPECULAR = 0.8;
	EMISSION = glint_emission;
}
