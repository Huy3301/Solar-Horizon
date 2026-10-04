class_name SpikeTerrainNoise extends RefCounted
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

static func fbm(p: Vector3, octaves: int) -> float:
	var value = 0.0
	var amplitude = 0.5
	var frequency = 1.0
	for _i in range(octaves):
		value += amplitude * get_noise_3d(p.x * frequency, p.y * frequency, p.z * frequency)
		frequency *= 2.0
		amplitude *= 0.5
	return value

static func sample_height(dir_x: float, dir_y: float, dir_z: float) -> float:
	var p = Vector3(dir_x, dir_y, dir_z)
	# Domain warp and ridged noise
	var warp = Vector3(fbm(p + Vector3(1.2, 3.4, 5.6), 4), fbm(p + Vector3(7.8, 9.0, 1.2), 4), fbm(p + Vector3(3.4, 5.6, 7.8), 4))
	var noise_val = fbm(p * 2.0 + warp, 6)
	var ridged = 1.0 - abs(noise_val)
	return ridged * ridged
