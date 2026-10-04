shader_type sky;

// Photorealistic Deep Space Skybox Shader
// Features:
// 1. Procedural Milky Way galactic band with dark dust absorption lanes & galactic core bulge
// 2. Multi-magnitude 3D procedural starfield (seamless, no polar UV distortion or seam artifacts)
// 3. Realistic stellar spectral class colors (O/B blue, A/F white, G yellow, K orange, M red)
// 4. Catalog star overlay for major constellations from StarCatalog
// 5. High-Dynamic-Range solar disk and corona

uniform vec3 sun_direction = vec3(0.707, 0.35, 0.612);
uniform vec3 sun_color : source_color = vec3(1.0, 0.98, 0.92);
uniform float sun_disk_size : hint_range(0.001, 0.05) = 0.009;
uniform float sun_corona_size : hint_range(0.01, 0.5) = 0.08;

uniform float star_density : hint_range(50.0, 600.0) = 320.0;
uniform float star_brightness : hint_range(0.1, 5.0) = 1.3;
uniform float milky_way_intensity : hint_range(0.0, 5.0) = 1.6;
uniform vec3 milky_way_core_color : source_color = vec3(0.65, 0.52, 0.38);
uniform vec3 milky_way_arm_color : source_color = vec3(0.25, 0.32, 0.52);

// Up to 16 major catalog stars: xyz = direction, w = luminosity/size
uniform vec4 catalog_stars[16];
uniform int catalog_star_count : hint_range(0, 16) = 0;

// High quality 3D hash functions (no trigonometry, completely seamless across the sphere)
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

// 3D value noise for galactic dust lanes
float noise3d(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	
	float n000 = hash31(i + vec3(0.0, 0.0, 0.0));
	float n100 = hash31(i + vec3(1.0, 0.0, 0.0));
	float n010 = hash31(i + vec3(0.0, 1.0, 0.0));
	float n110 = hash31(i + vec3(1.0, 1.0, 0.0));
	float n001 = hash31(i + vec3(0.0, 0.0, 1.0));
	float n101 = hash31(i + vec3(1.0, 0.0, 1.0));
	float n011 = hash31(i + vec3(0.0, 1.0, 1.0));
	float n111 = hash31(i + vec3(1.0, 1.0, 1.0));
	
	float nx00 = mix(n000, n100, f.x);
	float nx10 = mix(n010, n110, f.x);
	float nx01 = mix(n001, n101, f.x);
	float nx11 = mix(n011, n111, f.x);
	
	float nxy0 = mix(nx00, nx10, f.y);
	float nxy1 = mix(nx01, nx11, f.y);
	
	return mix(nxy0, nxy1, f.z);
}

// Spectral class color palette
vec3 get_star_color(float seed) {
	if (seed < 0.20) {
		return vec3(0.70, 0.82, 1.0); // O/B class blue-white
	} else if (seed < 0.55) {
		return vec3(0.95, 0.97, 1.0); // A/F class pure white
	} else if (seed < 0.80) {
		return vec3(1.0, 0.95, 0.80); // G class solar yellow
	} else if (seed < 0.93) {
		return vec3(1.0, 0.78, 0.55); // K class orange
	}
	return vec3(1.0, 0.55, 0.40);     // M class red dwarf / giant
}

void sky() {
	vec3 dir = normalize(EYEDIR);
	vec3 L = normalize(sun_direction);

	vec3 space_color = vec3(0.0008, 0.0012, 0.0025);

	// 1. MILKY WAY PROCEDURAL BAND & DUST LANES
	// Galactic plane orientation
	vec3 galactic_pole = normalize(vec3(-0.4, 0.7, 0.5));
	vec3 galactic_center = normalize(vec3(0.65, -0.22, -0.72));
	
	float gal_lat = abs(dot(dir, galactic_pole));
	float mw_envelope = exp(-gal_lat * 7.5);
	float mw_broad = exp(-gal_lat * 2.8) * 0.35;
	
	// Galactic dust absorption lanes (Great Rift)
	float dust_noise1 = noise3d(dir * 18.0);
	float dust_noise2 = noise3d(dir * 36.0) * 0.5;
	float dust_lane = smoothstep(0.42, 0.65, dust_noise1 + dust_noise2 * 0.6);
	
	// Galactic core bulge
	float core_dot = max(0.0, dot(dir, galactic_center));
	float mw_core = pow(core_dot, 5.0) * 1.8 + pow(core_dot, 32.0) * 2.5;
	
	vec3 mw_color = mix(milky_way_arm_color, milky_way_core_color, clamp(mw_core, 0.0, 1.0));
	float mw_lum = (mw_envelope * 0.22 + mw_broad * 0.1 + mw_core * 0.45) * (1.0 - dust_lane * 0.65 * mw_envelope);
	space_color += mw_color * max(0.0, mw_lum) * milky_way_intensity;

	// 2. PROCEDURAL 3D STARFIELD
	// Dense micro background star dusting
	vec3 cell_micro = floor(dir * (star_density * 1.8));
	vec3 rnd_micro = hash33(cell_micro);
	if (rnd_micro.x > 0.94) {
		vec3 center_micro = (cell_micro + rnd_micro) / (star_density * 1.8);
		float d_micro = length(dir - normalize(center_micro));
		if (d_micro < 0.0008) {
			float br = pow(1.0 - d_micro / 0.0008, 2.0) * (rnd_micro.z * 0.8 + 0.2);
			space_color += get_star_color(rnd_micro.y) * br * 0.45 * star_brightness;
		}
	}

	// Medium field stars
	vec3 cell_med = floor(dir * star_density);
	vec3 rnd_med = hash33(cell_med);
	if (rnd_med.x > 0.86) {
		vec3 center_med = (cell_med + rnd_med) / star_density;
		float d_med = length(dir - normalize(center_med));
		float star_sz = 0.0013 * (rnd_med.y * 0.7 + 0.5);
		if (d_med < star_sz) {
			float br_med = pow(1.0 - d_med / star_sz, 2.8) * (rnd_med.z * 1.8 + 0.4);
			space_color += get_star_color(rnd_med.y) * br_med * star_brightness;
		}
	}

	// Bright prominent navigation stars
	vec3 cell_bright = floor(dir * (star_density * 0.3));
	vec3 rnd_bright = hash33(cell_bright);
	if (rnd_bright.x > 0.97) {
		vec3 center_br = (cell_bright + rnd_bright) / (star_density * 0.3);
		float d_br = length(dir - normalize(center_br));
		float star_sz_br = 0.0028;
		if (d_br < star_sz_br) {
			float br_bright = pow(1.0 - d_br / star_sz_br, 2.5) * 3.8;
			vec3 s_color = get_star_color(rnd_bright.y);
			
			// Subtle diffraction spike on bright stars
			vec3 local_p = dir - normalize(center_br);
			float spike = max(0.0, 1.0 - abs(local_p.x) * 650.0) * max(0.0, 1.0 - abs(local_p.y) * 650.0);
			space_color += s_color * (br_bright + spike * 2.2) * star_brightness;
		}
	}

	// 3. CATALOG STAR OVERLAY (constellation stars from StarCatalog)
	for (int i = 0; i < catalog_star_count; i++) {
		vec3 cat_dir = normalize(catalog_stars[i].xyz);
		float cat_lum = catalog_stars[i].w;
		float d_cat = length(dir - cat_dir);
		float cat_sz = 0.0025 * clamp(cat_lum, 0.5, 2.5);
		if (d_cat < cat_sz) {
			float br_cat = pow(1.0 - d_cat / cat_sz, 2.2) * (cat_lum * 2.5);
			vec3 cat_color = get_star_color(fract(float(i) * 0.381966));
			space_color += cat_color * br_cat * star_brightness;
		}
	}

	// 4. SOLAR DISK & CORONA
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
