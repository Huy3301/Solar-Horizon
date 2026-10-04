class_name TestDiscoveryScanner extends TestCase

var discovery_script = preload("res://game/gameplay/discovery_system.gd")

func test_discovery_registration_and_categories() -> void:
	var ds = discovery_script.new()

	var m := ds.register_discovery("iron_ore_deposit", "mineral", "Iron Deposit", "Earth")
	assert_eq(m["category"], "mineral")
	assert_eq(m["reward"], 100, "Mineral reward is 100")

	var fl := ds.register_discovery("lunar_lichen", "flora", "Lunar Lichen", "Moon")
	assert_eq(fl["category"], "flora")
	assert_eq(fl["reward"], 250, "Flora reward is 250")

	var fa := ds.register_discovery("space_tardigrade", "fauna", "Tardigrade", "Moon")
	assert_eq(fa["category"], "fauna")
	assert_eq(fa["reward"], 500, "Fauna reward is 500")

	var an := ds.register_discovery("monolith_alpha", "anomaly", "Alien Monolith", "Moon")
	assert_eq(an["category"], "anomaly")
	assert_eq(an["reward"], 1000, "Anomaly reward is 1000")

	var minerals: Array[Dictionary] = ds.get_discoveries_by_category("mineral")
	assert_eq(minerals.size(), 1, "1 mineral discovered")

	var moon_disc: Array[Dictionary] = ds.get_discoveries_by_planet("Moon")
	assert_eq(moon_disc.size(), 3, "3 discoveries on Moon")

	ds.free()

func test_discovery_upload_and_credits() -> void:
	var ds = discovery_script.new()
	ds.register_discovery("crystal_01", "mineral", "Quartz Crystal", "Earth")

	assert_eq(ds.get_credits(), 0, "Initial credits 0")
	var earned := ds.upload_discovery("crystal_01")
	assert_eq(earned, 100, "Earned 100 credits for mineral")
	assert_eq(ds.get_credits(), 100, "Balance updated to 100")
	assert_true(ds.is_uploaded("crystal_01"), "Marked uploaded")

	# Duplicate upload does not award double credits
	earned = ds.upload_discovery("crystal_01")
	assert_eq(earned, 0, "No reward for duplicate upload")
	assert_eq(ds.get_credits(), 100, "Balance unchanged")

	ds.free()

func test_upload_all_pending() -> void:
	var ds = discovery_script.new()
	ds.register_discovery("item1", "mineral", "M1", "Earth") # 100
	ds.register_discovery("item2", "flora", "F1", "Earth")   # 250
	ds.register_discovery("item3", "anomaly", "A1", "Moon")  # 1000

	var total_earned := ds.upload_all_pending()
	assert_eq(total_earned, 1350, "Total earned is 100+250+1000 = 1350")
	assert_eq(ds.get_credits(), 1350, "Credits updated")

	ds.free()

func test_rename_discovery() -> void:
	var ds = discovery_script.new()
	ds.register_discovery("site_x", "anomaly", "Site X", "Earth")

	ds.rename_discovery("site_x", "Ancient Crater")
	var entry := ds.get_discovery("site_x")
	assert_eq(entry["name"], "Ancient Crater", "Discovery renamed")

	ds.free()

func test_scanner_standalone_no_scattersystem() -> void:
	var scanner := ScannerSystem.new()
	# Without adding to scene tree or with no ScatterSystem, finding targets should return empty array safely
	var targets := scanner.find_scannable_targets()
	assert_eq(targets.size(), 0, "Targets empty when no objects in world")

	# Visor toggle works independently
	assert_false(scanner.is_visor_active(), "Visor initially off")
	assert_true(scanner.toggle_visor(), "Visor toggled on")
	assert_true(scanner.is_visor_active(), "Visor active")
	assert_false(scanner.toggle_visor(), "Visor toggled off")

	scanner.free()

func test_scanner_detects_scannable_group() -> void:
	var scanner := ScannerSystem.new()
	scanner.position = Vector3.ZERO
	scanner.scan_radius = 50.0

	var target := Node3D.new()
	target.name = "AlienObelisk"
	target.set("category", "anomaly")
	target.add_to_group("scannable")
	target.position = Vector3(10, 0, 0)

	# In headless tests, add nodes to SceneTree to enable group querying
	var root := Engine.get_main_loop() as SceneTree
	if root != null and root.root != null:
		root.root.add_child(scanner)
		root.root.add_child(target)

		var found: Array[Dictionary] = scanner.find_scannable_targets()
		assert_true(found.size() >= 1, "Found at least 1 scannable target")

		var matched := false
		for f in found:
			if f.get("name") == "AlienObelisk":
				matched = true
				assert_eq(f.get("category"), "anomaly", "Category detected as anomaly")
		assert_true(matched, "Target AlienObelisk was located")

		root.root.remove_child(target)
		root.root.remove_child(scanner)

	target.free()
	scanner.free()

func test_discovery_serialization() -> void:
	var ds1 = discovery_script.new()
	ds1.register_discovery("sample_1", "mineral", "Iron Sample", "Earth")
	ds1.upload_discovery("sample_1")
	ds1.add_credits(50)

	var saved := ds1.get_state()

	var ds2 = discovery_script.new()
	ds2.load_state(saved)

	assert_eq(ds2.get_credits(), 150, "Restored 100+50 credits")
	assert_true(ds2.is_discovered("sample_1"), "Sample discovered")
	assert_true(ds2.is_uploaded("sample_1"), "Sample marked uploaded")

	ds1.free()
	ds2.free()
