class_name TerrainNoise extends RefCounted
# INTEGRATE(WP3): Use shared constants/noise once available.

# 3D Noise hashing based on integer arithmetic to match GLSL exactly.
const HASH_SCALE = 0.1031;

static func hash33(p_x: float, p_y: float, p_z: float) -> Vector3:
	# Porting a simple, deterministic float hash that matches across CPU/GPU
	# For actual deterministic cross-platform integer hash, we'd use bitwise logic, 
	# but keeping it simple for the spike.
	var p3 = Vector3(p_x, p_y, p_z) * HASH_SCALE
	p3.x = p3.x - floor(p3.x)
	p3.y = p3.y - floor(p3.y)
	p3.z = p3.z - floor(p3.z)
	
	var dot3 = Vector3(p3.y, p3.x, p3.x).dot(Vector3(p3.z + 39.346, p3.y + 39.346, p3.z + 39.346))
	p3 += Vector3(dot3, dot3, dot3)
	
	var res = Vector3(
		p3.x + p3.y,
		p3.x + p3.z,
		p3.y + p3.z
	)
	res.x = res.x - floor(res.x)
	res.y = res.y - floor(res.y)
	res.z = res.z - floor(res.z)
	return res

static func get_noise_3d(x: float, y: float, z: float) -> float:
	# Simplex or simple value noise. Using simple value noise for ease of GLSL sync.
	var p = Vector3(x, y, z)
	var i = p.floor()
	var f = p - i
	var u = f * f * (Vector3(3.0, 3.0, 3.0) - 2.0 * f)
	
	var res = lerp(
		lerp(
			lerp(hash33(i.x, i.y, i.z).x, hash33(i.x + 1.0, i.y, i.z).x, u.x),
			lerp(hash33(i.x, i.y + 1.0, i.z).x, hash33(i.x + 1.0, i.y + 1.0, i.z).x, u.x), u.y
		),
		lerp(
			lerp(hash33(i.x, i.y, i.z + 1.0).x, hash33(i.x + 1.0, i.y, i.z + 1.0).x, u.x),
			lerp(hash33(i.x, i.y + 1.0, i.z + 1.0).x, hash33(i.x + 1.0, i.y + 1.0, i.z + 1.0).x, u.x), u.y
		), u.z
	)
	return res * 2.0 - 1.0

static func fbm(p: Vector3, octaves: int, persistence: float = 0.5) -> float:
	var value = 0.0
	var amplitude = 0.5
	var frequency = 1.0
	for _i in range(octaves):
		value += amplitude * get_noise_3d(p.x * frequency, p.y * frequency, p.z * frequency)
		frequency *= 2.0
		amplitude *= persistence
	return value

static var _water_image: Image = null
static var _water_image_loaded: bool = false

static func _get_water_image() -> Image:
	if not _water_image_loaded:
		_water_image_loaded = true
		if ResourceLoader.exists("res://assets/textures/earth_specular_water.png"):
			var tex = load("res://assets/textures/earth_specular_water.png")
			if tex is Texture2D:
				_water_image = tex.get_image()
				if _water_image and _water_image.is_compressed():
					_water_image.decompress()
	return _water_image

static func smoothstep_scalar(edge0: float, edge1: float, x: float) -> float:
	var t = clampf((x - edge0) / (edge1 - edge0), 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)

static func crater_noise_3d(p: Vector3) -> float:
	var i = p.floor()
	var f = p - i
	var min_dist = 10.0
	for z in range(-1, 2):
		for y in range(-1, 2):
			for x in range(-1, 2):
				var cell = Vector3(float(x), float(y), float(z))
				var h = hash33(i.x + cell.x, i.y + cell.y, i.z + cell.z)
				var feature_pt = cell + h * 0.65
				var d = (f - feature_pt).length()
				if d < min_dist:
					min_dist = d
	var rim = smoothstep_scalar(0.52, 0.38, min_dist) * smoothstep_scalar(0.22, 0.38, min_dist)
	var bowl = smoothstep_scalar(0.36, 0.0, min_dist)
	var peak = smoothstep_scalar(0.08, 0.0, min_dist) * 0.35
	return rim * 1.5 - bowl * 0.85 + peak

static func sample_earth_height(dir: Vector3) -> float:
	var d = dir.normalized()
	# Equirectangular spherical mapping matching Godot SphereMesh
	var u = fposmod(atan2(d.x, -d.z) / TAU + 0.5, 1.0)
	var v = clampf(0.5 - asin(clampf(d.y, -1.0, 1.0)) / PI, 0.0, 1.0)
	
	var is_water: float = 0.0
	var img = _get_water_image()
	if img != null:
		var px = clampi(int(u * (img.get_width() - 1)), 0, img.get_width() - 1)
		var py = clampi(int(v * (img.get_height() - 1)), 0, img.get_height() - 1)
		is_water = img.get_pixel(px, py).r
	else:
		# Deterministic analytical continent/ocean mask fallback
		is_water = 1.0 if fbm(d * 1.5, 3) < 0.1 else 0.0
		
	# Water surfaces are at sea level (0.0)
	if is_water > 0.45:
		return 0.0
		
	# Continental relief: domain-warped ridged multifractal mountains
	var land_mask = clampf((0.45 - is_water) * 4.0, 0.0, 1.0)
	var warp = Vector3(
		fbm(d + Vector3(1.2, 3.4, 5.6), 4),
		fbm(d + Vector3(7.8, 9.0, 1.2), 4),
		fbm(d + Vector3(3.4, 5.6, 7.8), 4)
	)
	var noise_val = fbm(d * 3.2 + warp, 7, 0.48)
	var ridged = 1.0 - abs(noise_val)
	var mountain_relief = pow(ridged, 2.2)
	var base_elevation = 0.06 + 0.14 * land_mask
	return base_elevation + mountain_relief * 0.8 * land_mask

static func sample_moon_height(dir: Vector3) -> float:
	var d = dir.normalized()
	# Maria basins vs highlands baseline
	var highlands = fbm(d * 1.8, 4) * 0.25
	# Multi-scale impact craters
	var c_large = crater_noise_3d(d * 4.8) * 0.38
	var c_med = crater_noise_3d(d * 13.5 + Vector3(3.7, 8.2, 5.1)) * 0.22
	var c_small = crater_noise_3d(d * 30.0 + Vector3(9.1, 14.5, 2.3)) * 0.10
	var regolith = fbm(d * 60.0, 3) * 0.03
	var total = highlands + c_large + c_med + c_small + regolith
	return clampf(0.35 + total, 0.0, 1.0)

static func sample_height(dir_x: float, dir_y: float, dir_z: float, body_type: String = "Earth") -> float:
	var dir = Vector3(dir_x, dir_y, dir_z)
	if body_type == "Moon":
		return sample_moon_height(dir)
	return sample_earth_height(dir)

