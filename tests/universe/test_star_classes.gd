class_name TestStarClasses extends TestCase

func test_star_class_distribution_decorrelated() -> void:
	var gen := GalaxyGenerator.new(123456789)
	var counts: Dictionary = {
		"M": 0,
		"K": 0,
		"G": 0,
		"F": 0,
		"A": 0,
		"B": 0,
		"O": 0,
	}

	var total_stars: int = 0
	var radius: int = 15

	for x in range(-radius, radius + 1):
		for y in range(-radius, radius + 1):
			for z in range(-radius, radius + 1):
				var sector := Vector3i(x, y, z)
				if gen.has_star(sector):
					total_stars += 1
					var s_class := gen.get_star_class(sector)
					assert_true(counts.has(s_class), "Star class %s must be one of O,B,A,F,G,K,M" % s_class)
					counts[s_class] = counts[s_class] + 1

	assert_true(total_stars >= 100, "Should have found >= 100 stars in scan volume (found %d)" % total_stars)

	# Verify not 100% class M (hash collision bug fix SH-27)
	assert_true(counts["M"] < total_stars, "Class M must not be 100%% of stars (found %d / %d)" % [counts["M"], total_stars])
	assert_true(counts["K"] > 0, "Class K stars must be present (found %d)" % counts["K"])
	assert_true(counts["G"] > 0, "Class G stars must be present (found %d)" % counts["G"])

	# Count distinct classes found
	var distinct_classes: int = 0
	for c in counts.keys():
		if counts[c] > 0:
			distinct_classes += 1
	assert_true(distinct_classes >= 4, "At least 4 distinct star classes should appear in large scan (found %d)" % distinct_classes)

func test_star_catalog_class_consistency() -> void:
	var catalog_script = preload("res://game/universe/star_catalog.gd")
	var catalog = catalog_script.new()
	catalog.scan_radius_sectors = 15
	catalog.set_seed(123456789)

	var stars = catalog.get_stars_for_skybox()
	assert_true(stars.size() > 50, "Catalog should contain stars in scan region")

	var m_count: int = 0
	var k_count: int = 0
	var g_count: int = 0

	for s in stars:
		var s_class: int = s["class"]
		var seed_val: int = s["seed"]
		# Verification that direct get_star_class matches cached
		assert_eq(catalog.get_star_class(seed_val), s_class, "get_star_class must match cached star class")

		if s_class == StarSystemGenerator.StarClass.M:
			m_count += 1
		elif s_class == StarSystemGenerator.StarClass.K:
			k_count += 1
		elif s_class == StarSystemGenerator.StarClass.G:
			g_count += 1

	assert_true(m_count < stars.size(), "Catalog must not consist of 100% M class stars")
	assert_true(k_count > 0, "Catalog must include K class stars")
	assert_true(g_count > 0, "Catalog must include G class stars")

	catalog.free()
