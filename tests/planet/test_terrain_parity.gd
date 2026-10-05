class_name TestTerrainParity
extends "res://tests/test_case.gd"

## Parity and continuity verification test for TerrainNoise and PlanetQuadtree (SH-11).
## Validates determinism across repeated queries, edge continuity across all 12 cube face boundaries,
## and strict mathematical range bounds on height generation functions.

func test_noise_hash_and_fbm_determinism() -> void:
	# Test hash33 determinism across various float coordinates
	var sample_coords = [
		Vector3(0.0, 0.0, 0.0),
		Vector3(12.345, -67.89, 42.0),
		Vector3(-999.1, 100.25, -0.004),
		Vector3(1e4, -1e4, 5e3)
	]
	for pt in sample_coords:
		var h1 = TerrainNoise.hash33(pt.x, pt.y, pt.z)
		var h2 = TerrainNoise.hash33(pt.x, pt.y, pt.z)
		assert_eq(h1, h2, "hash33 must be strictly deterministic at %s" % str(pt))

	# Test get_noise_3d determinism
	for pt in sample_coords:
		var n1 = TerrainNoise.get_noise_3d(pt.x, pt.y, pt.z)
		var n2 = TerrainNoise.get_noise_3d(pt.x, pt.y, pt.z)
		assert_eq(n1, n2, "get_noise_3d must be strictly deterministic at %s" % str(pt))

	# Test fbm determinism with multiple octave counts
	for oct in [1, 3, 5, 7]:
		for pt in sample_coords:
			var f1 = TerrainNoise.fbm(pt, oct, 0.5)
			var f2 = TerrainNoise.fbm(pt, oct, 0.5)
			assert_eq(f1, f2, "fbm with %d octaves must be strictly deterministic at %s" % [oct, str(pt)])

	# Test crater_noise_3d determinism
	for pt in sample_coords:
		var c1 = TerrainNoise.crater_noise_3d(pt)
		var c2 = TerrainNoise.crater_noise_3d(pt)
		assert_eq(c1, c2, "crater_noise_3d must be strictly deterministic at %s" % str(pt))

func test_terrain_height_determinism_earth_and_moon() -> void:
	var test_dirs = [
		Vector3(1.0, 0.0, 0.0),
		Vector3(-1.0, 0.0, 0.0),
		Vector3(0.0, 1.0, 0.0),
		Vector3(0.0, -1.0, 0.0),
		Vector3(0.0, 0.0, 1.0),
		Vector3(0.0, 0.0, -1.0),
		Vector3(0.577, 0.577, 0.577).normalized(),
		Vector3(-0.35, 0.82, -0.45).normalized(),
		Vector3(0.123, -0.456, 0.789).normalized()
	]

	for dir in test_dirs:
		# Earth height determinism
		var eh1 = TerrainNoise.sample_earth_height(dir)
		var eh2 = TerrainNoise.sample_earth_height(dir)
		assert_eq(eh1, eh2, "Earth height must be strictly deterministic at dir %s" % str(dir))

		# Moon height determinism
		var mh1 = TerrainNoise.sample_moon_height(dir)
		var mh2 = TerrainNoise.sample_moon_height(dir)
		assert_eq(mh1, mh2, "Moon height must be strictly deterministic at dir %s" % str(dir))

		# General sample_height dispatch determinism
		var sh_e1 = TerrainNoise.sample_height(dir.x, dir.y, dir.z, "Earth")
		var sh_e2 = TerrainNoise.sample_height(dir.x, dir.y, dir.z, "Earth")
		assert_eq(sh_e1, sh_e2, "sample_height Earth dispatch must match")
		assert_eq(sh_e1, eh1, "sample_height Earth must match sample_earth_height")

		var sh_m1 = TerrainNoise.sample_height(dir.x, dir.y, dir.z, "Moon")
		var sh_m2 = TerrainNoise.sample_height(dir.x, dir.y, dir.z, "Moon")
		assert_eq(sh_m1, sh_m2, "sample_height Moon dispatch must match")
		assert_eq(sh_m1, mh1, "sample_height Moon must match sample_moon_height")

func test_patch_height_determinism() -> void:
	# Check PlanetQuadtree.sample_patch_height determinism across multiple faces and UV coordinates
	for face in range(6):
		for u_i in range(3):
			for v_i in range(3):
				var uv = Vector2(float(u_i) * 0.5, float(v_i) * 0.5)
				var h_e1 = PlanetQuadtree.sample_patch_height(face, uv, "Earth")
				var h_e2 = PlanetQuadtree.sample_patch_height(face, uv, "Earth")
				assert_eq(h_e1, h_e2, "sample_patch_height Earth must be deterministic on face %d at uv %s" % [face, str(uv)])

				var h_m1 = PlanetQuadtree.sample_patch_height(face, uv, "Moon")
				var h_m2 = PlanetQuadtree.sample_patch_height(face, uv, "Moon")
				assert_eq(h_m1, h_m2, "sample_patch_height Moon must be deterministic on face %d at uv %s" % [face, str(uv)])

func test_edge_direction_and_height_continuity_all_faces() -> void:
	# Define all 12 edge pairings between the 6 cube faces:
	# Face 0: +X, Face 1: -X, Face 2: +Y, Face 3: -Y, Face 4: +Z, Face 5: -Z
	var edge_pairs = [
		[4, func(t): return Vector2(1.0, t), 0, func(t): return Vector2(0.0, t), "Face 4 (+Z) right <-> Face 0 (+X) left"],
		[4, func(t): return Vector2(0.0, t), 1, func(t): return Vector2(1.0, t), "Face 4 (+Z) left <-> Face 1 (-X) right"],
		[5, func(t): return Vector2(1.0, t), 1, func(t): return Vector2(0.0, t), "Face 5 (-Z) right <-> Face 1 (-X) left"],
		[5, func(t): return Vector2(0.0, t), 0, func(t): return Vector2(1.0, t), "Face 5 (-Z) left <-> Face 0 (+X) right"],
		[4, func(t): return Vector2(t, 0.0), 2, func(t): return Vector2(t, 1.0), "Face 4 (+Z) top <-> Face 2 (+Y) bottom"],
		[4, func(t): return Vector2(t, 1.0), 3, func(t): return Vector2(t, 0.0), "Face 4 (+Z) bottom <-> Face 3 (-Y) top"],
		[5, func(t): return Vector2(t, 0.0), 2, func(t): return Vector2(1.0 - t, 0.0), "Face 5 (-Z) top <-> Face 2 (+Y) top"],
		[5, func(t): return Vector2(t, 1.0), 3, func(t): return Vector2(1.0 - t, 1.0), "Face 5 (-Z) bottom <-> Face 3 (-Y) bottom"],
		[0, func(t): return Vector2(t, 0.0), 2, func(t): return Vector2(1.0, 1.0 - t), "Face 0 (+X) top <-> Face 2 (+Y) right"],
		[0, func(t): return Vector2(t, 1.0), 3, func(t): return Vector2(1.0, t), "Face 0 (+X) bottom <-> Face 3 (-Y) right"],
		[1, func(t): return Vector2(t, 0.0), 2, func(t): return Vector2(0.0, t), "Face 1 (-X) top <-> Face 2 (+Y) left"],
		[1, func(t): return Vector2(t, 1.0), 3, func(t): return Vector2(0.0, 1.0 - t), "Face 1 (-X) bottom <-> Face 3 (-Y) left"]
	]

	for pair in edge_pairs:
		var faceA: int = pair[0]
		var uvA_fn: Callable = pair[1]
		var faceB: int = pair[2]
		var uvB_fn: Callable = pair[3]
		var desc: String = pair[4]

		for step in range(5):
			var t = float(step) / 4.0
			var uvA: Vector2 = uvA_fn.call(t)
			var uvB: Vector2 = uvB_fn.call(t)

			var dirA = PlanetQuadtree.get_spherified_dir(faceA, uvA)
			var dirB = PlanetQuadtree.get_spherified_dir(faceB, uvB)
			assert_vec_almost_eq(dirA, dirB, 0.002, "Spherified direction mismatch on edge: %s (t=%f)" % [desc, t])

			var h_moon_A = PlanetQuadtree.sample_patch_height(faceA, uvA, "Moon")
			var h_moon_B = PlanetQuadtree.sample_patch_height(faceB, uvB, "Moon")
			assert_almost_eq(h_moon_A, h_moon_B, 0.005, "Moon height boundary continuity mismatch on edge: %s (t=%f)" % [desc, t])

			var h_earth_A = PlanetQuadtree.sample_patch_height(faceA, uvA, "Earth")
			var h_earth_B = PlanetQuadtree.sample_patch_height(faceB, uvB, "Earth")
			assert_almost_eq(h_earth_A, h_earth_B, 0.005, "Earth height boundary continuity mismatch on edge: %s (t=%f)" % [desc, t])

func test_height_range_bounds() -> void:
	# Test noise range bounds: get_noise_3d must lie in [-1.0, 1.0]
	for x_i in range(-3, 4):
		for y_i in range(-3, 4):
			for z_i in range(-3, 4):
				var n_val = TerrainNoise.get_noise_3d(float(x_i) * 1.7, float(y_i) * 2.3, float(z_i) * 0.9)
				assert_true(n_val >= -1.0 - 1e-4 and n_val <= 1.0 + 1e-4, "get_noise_3d out of [-1, 1] range: %f" % n_val)
				assert_false(is_nan(n_val), "get_noise_3d produced NaN")

	# Test crater_noise_3d bounds and non-nan
	for i in range(20):
		var p = Vector3(cos(float(i)), sin(float(i) * 0.7), cos(float(i) * 1.3)) * 5.0
		var c_val = TerrainNoise.crater_noise_3d(p)
		assert_false(is_nan(c_val), "crater_noise_3d produced NaN")
		assert_false(is_inf(c_val), "crater_noise_3d produced Inf")
		assert_true(c_val >= -2.0 and c_val <= 3.0, "crater_noise_3d within expected bounds: %f" % c_val)

	# Test Moon and Earth height bounds over spherical directions
	for step_lat in range(11):
		var lat = (float(step_lat) / 10.0 - 0.5) * PI
		for step_lon in range(16):
			var lon = (float(step_lon) / 16.0) * TAU
			var dir = Vector3(cos(lat) * cos(lon), sin(lat), cos(lat) * sin(lon)).normalized()

			# Earth heights must be non-negative and bounded <= 1.0 (water is 0.0, peaks <= 1.0)
			var h_earth = TerrainNoise.sample_earth_height(dir)
			assert_false(is_nan(h_earth), "Earth height is NaN at %s" % str(dir))
			assert_false(is_inf(h_earth), "Earth height is Inf at %s" % str(dir))
			assert_true(h_earth >= 0.0, "Earth height negative: %f" % h_earth)
			assert_true(h_earth <= 1.05, "Earth height exceeded normalized max: %f" % h_earth)

			# Moon heights must be strictly clamped in [0.0, 1.0]
			var h_moon = TerrainNoise.sample_moon_height(dir)
			assert_false(is_nan(h_moon), "Moon height is NaN at %s" % str(dir))
			assert_false(is_inf(h_moon), "Moon height is Inf at %s" % str(dir))
			assert_true(h_moon >= 0.0 and h_moon <= 1.0, "Moon height out of [0, 1] bounds: %f" % h_moon)

	# Test patch heights across all faces and corner/center UVs
	for face in range(6):
		var test_uvs = [
			Vector2(0.0, 0.0),
			Vector2(1.0, 0.0),
			Vector2(0.0, 1.0),
			Vector2(1.0, 1.0),
			Vector2(0.5, 0.5)
		]
		for uv in test_uvs:
			var h_e = PlanetQuadtree.sample_patch_height(face, uv, "Earth")
			assert_true(h_e >= 0.0 and h_e <= 1.05, "Patch Earth height out of bounds on face %d: %f" % [face, h_e])

			var h_m = PlanetQuadtree.sample_patch_height(face, uv, "Moon")
			assert_true(h_m >= 0.0 and h_m <= 1.0, "Patch Moon height out of bounds on face %d: %f" % [face, h_m])
