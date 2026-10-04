shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

// Photorealistic Earth planetary surface shader for Low Earth Orbit (LEO)
// Features:
// 1. Physically-based Rayleigh atmospheric aerial perspective & terminator extinction
// 2. Anisotropic ocean solar specular glint & coastal turquoise bathymetry
// 3. Dynamic cloud shadows cast onto continents and oceans
// 4. Procedural multi-scale geological relief detail for low-orbit flyovers
// 5. High-dynamic range sodium/LED nocturnal city lights with atmospheric diffusion

uniform sampler2D albedo_map : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D normal_map : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D water_mask : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform sampler2D night_lights : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D cloud_map : filter_linear_mipmap, repeat_enable;

uniform vec3 sun_direction = vec3(0.707, 0.35, 0.612);
uniform float night_lights_intensity : hint_range(0.0, 8.0) = 4.5;
uniform vec3 night_lights_tint : source_color = vec3(1.0, 0.85, 0.52);
uniform float atmosphere_density : hint_range(0.1, 4.0) = 1.35;
uniform float planet_rotation : hint_range(-6.28318, 6.28318) = 0.0;
uniform float cloud_rotation : hint_range(-6.28318, 6.28318) = 0.0;

varying vec3 v_world_normal;
varying vec3 v_world_pos;
varying vec2 v_uv;

// High-speed hash & value noise for orbital micro-relief
float hash21(vec2 p) {
	p = fract(p * vec2(234.34, 435.345));
	p += dot(p, p + 34.23);
	return fract(p.x * p.y);
}

float micro_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash21(i), hash21(i + vec2(1.0, 0.0)), f.x),
	           mix(hash21(i + vec2(0.0, 1.0)), hash21(i + vec2(1.0, 1.0)), f.x), f.y);
}

void vertex() {
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	v_uv = UV;
}

void fragment() {
	// Surface & cloud UV coordinates with rotation
	vec2 surface_uv = vec2(fract(v_uv.x + planet_rotation / (2.0 * PI)), v_uv.y);
	vec2 cloud_uv = vec2(fract(v_uv.x + cloud_rotation / (2.0 * PI)), v_uv.y);
	
	vec4 base_color = texture(albedo_map, surface_uv);
	vec3 normal_sample = texture(normal_map, surface_uv).rgb * 2.0 - 1.0;
	float is_water = texture(water_mask, surface_uv).r;
	vec3 lights_sample = texture(night_lights, surface_uv).rgb;
	
	// Vectors
	vec3 N = normalize(v_world_normal);
	vec3 L = normalize(sun_direction);
	vec3 V = normalize(CAMERA_POSITION_WORLD - v_world_pos);
	
	// Micro-relief on land for crisp detail during close approaches
	if (is_water < 0.5) {
		float n1 = micro_noise(surface_uv * 1800.0);
		float n2 = micro_noise(surface_uv * 4200.0) * 0.5;
		vec2 micro_grad = vec2(n1 - 0.5, n2 - 0.25) * 0.35;
		normal_sample.xy += micro_grad * (1.0 - is_water);
	}
	
	NORMAL = normalize(mix(NORMAL, NORMAL + normal_sample * 0.5, 1.0 - is_water * 0.85));
	
	float n_dot_l = dot(N, L);
	float n_dot_v = clamp(dot(N, V), 0.0, 1.0);
	float day_factor = smoothstep(-0.06, 0.18, n_dot_l);
	float night_factor = 1.0 - smoothstep(-0.15, 0.05, n_dot_l);
	
	// Atmospheric extinction on incoming sunlight (golden/red sunset at terminator)
	float sun_zenith = clamp(n_dot_l, 0.0, 1.0);
	float airmass_sun = 1.0 / (sun_zenith + 0.08);
	vec3 sun_tint = exp(-vec3(0.08, 0.22, 0.55) * airmass_sun * 0.7);
	sun_tint = mix(vec3(1.0, 0.42, 0.12), vec3(1.0, 0.98, 0.95), smoothstep(0.02, 0.35, n_dot_l));
	
	// Dynamic cloud shadow cast onto surface
	vec3 L_proj = L - N * dot(L, N);
	vec2 shadow_offset = L_proj.xz * 0.0035;
	float cloud_shadow_raw = texture(cloud_map, cloud_uv - shadow_offset).a;
	float cloud_shadow = smoothstep(0.15, 0.85, cloud_shadow_raw) * 0.72 * day_factor;
	
	// Ocean bathymetry & shallow coastal water enhancement (e.g. Gulf St Vincent / Spencer Gulf)
	vec3 surface_rgb = base_color.rgb;
	if (is_water > 0.4) {
		// Deep ocean vs coastal shallow shelf
		vec3 deep_blue = vec3(0.015, 0.065, 0.18);
		vec3 shallow_turquoise = vec3(0.03, 0.28, 0.42);
		surface_rgb = mix(deep_blue, shallow_turquoise, clamp(base_color.g * 2.2, 0.0, 0.75));
	}
	
	// Apply sunlight extinction and cloud shadows
	surface_rgb *= sun_tint * (1.0 - cloud_shadow);
	
	// Ocean solar specular glint (blinding realistic sun reflection on water)
	if (is_water > 0.15) {
		vec3 H = normalize(L + V);
		float n_dot_h = max(0.0, dot(N, H));
		float glint_core = pow(n_dot_h, 320.0) * 12.0;
		float glint_broad = pow(n_dot_h, 24.0) * 0.45;
		float v_dot_h = max(0.0, dot(V, H));
		float fresnel = 0.02 + 0.98 * pow(1.0 - v_dot_h, 5.0);
		vec3 glint = (glint_core + glint_broad) * sun_tint * fresnel * is_water * (1.0 - cloud_shadow);
		surface_rgb += glint;
	}
	
	// Atmospheric Rayleigh aerial perspective (haze over terrain towards the horizon)
	float optical_depth = atmosphere_density * (1.0 / (n_dot_v + 0.14) - 0.85);
	float haze_amount = 1.0 - exp(-optical_depth * 0.38);
	vec3 rayleigh_haze = mix(vec3(0.15, 0.52, 0.98), vec3(1.0, 0.55, 0.22), smoothstep(0.20, -0.05, n_dot_l));
	surface_rgb = mix(surface_rgb, rayleigh_haze, haze_amount * day_factor * 0.82);
	
	// Physical material PBR properties
	ROUGHNESS = mix(0.82, 0.06, is_water);
	METALLIC = mix(0.01, 0.12, is_water);
	SPECULAR = mix(0.12, 0.98, is_water);
	ALBEDO = surface_rgb;
	
	// City night lights (Adelaide, Sydney, Melbourne, etc.) with atmospheric diffusion
	vec3 night_glow = lights_sample * night_lights_tint * night_lights_intensity * night_factor;
	float city_rim = pow(1.0 - n_dot_v, 2.5);
	vec3 atmo_night_diffusion = vec3(0.08, 0.18, 0.35) * city_rim * 0.4 * night_factor;
	
	EMISSION = night_glow + atmo_night_diffusion;
}
