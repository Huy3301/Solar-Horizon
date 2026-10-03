shader_type sky;

// Deep space vacuum sky shader with procedural multi-magnitude stars,
// Milky Way galactic band, and high-dynamic-range solar disk.
uniform vec3 sun_direction = vec3(0.707, 0.35, 0.612);
uniform vec3 sun_color : source_color = vec3(1.0, 0.98, 0.92);
uniform float sun_disk_size : hint_range(0.001, 0.05) = 0.009;
uniform float sun_corona_size : hint_range(0.01, 0.5) = 0.08;
uniform float star_density : hint_range(50.0, 500.0) = 280.0;
uniform float milky_way_intensity : hint_range(0.0, 3.0) = 1.35;

float hash31(vec3 p) {
	p = fract(p * 0.3183099 + vec3(0.1, 0.1, 0.1));
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

vec3 hash33(vec3 p) {
	p = fract(p * vec3(0.1031, 0.1030, 0.0973));
	p += dot(p, p.yxz + 33.33);
	return fract((p.xxy + p.yxx) * p.zyx);
}

void sky() {
	vec3 dir = normalize(EYEDIR);
	vec3 L = normalize(sun_direction);
	
	vec3 space_color = vec3(0.001, 0.0015, 0.003);
	
	vec3 galactic_normal = normalize(vec3(-0.4, 0.7, 0.5));
	float galactic_lat = abs(dot(dir, galactic_normal));
	float mw_band = exp(-galactic_lat * 6.5);
	
	float mw_dust = sin(dir.x * 12.0 + dir.z * 8.0) * cos(dir.y * 14.0);
	float mw_core = pow(max(0.0, dot(dir, normalize(vec3(0.6, -0.2, -0.7)))), 4.0);
	vec3 mw_color = mix(vec3(0.18, 0.22, 0.38), vec3(0.55, 0.45, 0.35), mw_core);
	space_color += mw_color * (mw_band * 0.18 + mw_core * 0.35 + mw_dust * mw_band * 0.05) * milky_way_intensity;
	
	vec3 cell_a = floor(dir * star_density);
	vec3 rnd_a = hash33(cell_a);
	if (rnd_a.x > 0.88) {
		vec3 star_center = (cell_a + rnd_a) / star_density;
		float dist = length(dir - normalize(star_center));
		float star_size = 0.0012 * (rnd_a.y * 0.8 + 0.4);
		if (dist < star_size) {
			float brightness = pow(1.0 - dist / star_size, 3.0) * (rnd_a.z * 1.5 + 0.5);
			vec3 star_tint = mix(vec3(0.7, 0.85, 1.0), vec3(1.0, 0.75, 0.5), rnd_a.y);
			space_color += star_tint * brightness;
		}
	}
	
	vec3 cell_b = floor(dir * (star_density * 0.35));
	vec3 rnd_b = hash33(cell_b);
	if (rnd_b.x > 0.96) {
		vec3 star_center = (cell_b + rnd_b) / (star_density * 0.35);
		float dist = length(dir - normalize(star_center));
		float star_size = 0.0028;
		if (dist < star_size) {
			float brightness = pow(1.0 - dist / star_size, 2.5) * 3.5;
			vec3 star_tint = mix(vec3(0.8, 0.95, 1.0), vec3(1.0, 0.85, 0.6), rnd_b.z);
			vec3 local_p = dir - normalize(star_center);
			float spike = max(0.0, 1.0 - abs(local_p.x) * 600.0) * max(0.0, 1.0 - abs(local_p.y) * 600.0);
			space_color += star_tint * (brightness + spike * 2.0);
		}
	}
	
	float cos_sun = dot(dir, L);
	float angle_to_sun = acos(clamp(cos_sun, -1.0, 1.0));
	
	if (angle_to_sun < sun_disk_size) {
		space_color = sun_color * 75.0;
	} else if (angle_to_sun < sun_corona_size) {
		float corona_factor = pow(1.0 - (angle_to_sun - sun_disk_size) / (sun_corona_size - sun_disk_size), 3.5);
		space_color += sun_color * corona_factor * 8.0;
	} else {
		float wide_glare = pow(max(0.0, cos_sun), 64.0) * 0.45;
		space_color += sun_color * wide_glare;
	}
	
	COLOR = space_color;
}
