class_name TestSaveService extends TestCase

var save_service_script = preload("res://game/autoload/save_service.gd")
var crafting_script = preload("res://game/gameplay/crafting_system.gd")
var discovery_script = preload("res://game/gameplay/discovery_system.gd")

const TEST_SAVE_PATH: String = "user://test_save_v1.json"
const TEST_LEGACY_SAVE_PATH: String = "user://test_save_legacy.json"

func test_universe_position_roundtrip() -> void:
	var saver = save_service_script.new()

	var sec := Vector3i(1, -2, 3)
	var off := DVec3.new(12345.6, -7890.1, 4567.8)
	var orig_pos := UniversePosition.new(sec, off)

	var dict := saver.serialize_universe_position(orig_pos, "Moon")
	assert_eq(dict["body_id"], "Moon", "Body ID preserved")
	assert_eq(dict["sector"][0], 1)
	assert_eq(dict["sector"][1], -2)
	assert_eq(dict["sector"][2], 3)

	var restored_pos := saver.deserialize_universe_position(dict)
	assert_eq(restored_pos.sector, sec, "Restored sector matches")
	var diff := orig_pos.difference_to(restored_pos)
	assert_almost_eq(diff.length(), 0.0, 0.01, "Restored position identical")

	saver.free()

func test_save_and_load_profile() -> void:
	var saver = save_service_script.new()

	var profile_in: Dictionary = {
		"inventory": {
			"items": {"iron_ore": 25, "steel_plate": 4, "he3": 2},
			"max_slots": 25,
			"max_mass": 300.0,
		},
		"discoveries": {
			"iron_deposit": {"id": "iron_deposit", "category": "mineral", "uploaded": true}
		},
		"unlocked_upgrades": {
			"suit_o2_tank": 1,
			"mining_speed": 2,
		},
		"crafting_stats": {
			"max_life_support": 125.0,
			"mining_speed": 1.5,
		},
		"credits": 750,
		"ship_state": {
			"hull": 950.0,
			"fuel": 800.0,
			"landed": true,
		},
		"player_position": {
			"sector": [0, 0, 0],
			"offset": [100.0, 200.0, 300.0],
			"body_id": "Earth",
		},
		"survival_state": {
			"life_support": 92.0,
			"hazard_protection": 88.0,
			"current_body_id": "Earth",
		},
	}

	var saved := saver.save_profile(profile_in, TEST_SAVE_PATH)
	assert_true(saved, "Profile saved successfully")

	var profile_out := saver.load_profile(TEST_SAVE_PATH)
	assert_eq(profile_out.get("version"), 1, "Version is 1")
	assert_eq(profile_out.get("credits"), 750, "Credits loaded")
	assert_eq(profile_out["inventory"]["items"]["iron_ore"], 25, "Inventory item amount matches")
	assert_eq(profile_out["unlocked_upgrades"]["mining_speed"], 2, "Upgrade tier matches")
	assert_almost_eq(profile_out["crafting_stats"]["mining_speed"], 1.5, 0.01, "Crafting stat matches")
	assert_almost_eq(profile_out["ship_state"]["hull"], 950.0, 0.01, "Ship hull matches")
	assert_almost_eq(profile_out["survival_state"]["life_support"], 92.0, 0.01, "Life support matches")

	# Clean up test file
	if FileAccess.file_exists(TEST_SAVE_PATH):
		DirAccess.remove_absolute(TEST_SAVE_PATH)

	saver.free()

func test_migration_from_v0_legacy() -> void:
	var saver = save_service_script.new()

	# Older schema with version 0 and unstructured fields
	var legacy_raw: Dictionary = {
		"version": 0,
		"player": {
			"credits": 200,
			"inventory": {
				"iron_ore": 10
			},
			"upgrades": {
				"suit_o2_tank": 1
			},
			"position": {
				"sector": [0, 1, 0],
				"offset": [50.0, 0.0, 50.0],
				"body_id": "Earth"
			}
		},
		"terrain": {}
	}

	var migrated := saver.migrate_data(legacy_raw)
	assert_eq(migrated["version"], 1, "Version bumped to 1")
	assert_eq(migrated["credits"], 200, "Credits extracted from player dict")
	assert_eq(migrated["unlocked_upgrades"]["suit_o2_tank"], 1, "Upgrades extracted")
	assert_true(migrated.has("inventory"), "Inventory key created")
	assert_true(migrated.has("discoveries"), "Discoveries key created")
	assert_true(migrated.has("ship_state"), "Default ship state populated")
	assert_eq(migrated["ship_state"]["hull"], 1000.0, "Default hull is 1000")
	assert_eq(migrated["player_position"]["body_id"], "Earth", "Position body ID preserved")

	# Also test migrating completely empty dict
	var empty_migrated := saver.migrate_data({})
	assert_eq(empty_migrated["version"], 1, "Empty data migrated to version 1")
	assert_eq(empty_migrated["credits"], 0, "Default credits 0")
	assert_true(empty_migrated.has("inventory"), "Default inventory structure exists")

	saver.free()

func test_systems_state_roundtrip() -> void:
	var saver = save_service_script.new()

	var inv := InventorySystem.new()
	inv.max_slots = 15
	inv.max_mass = 200.0
	inv.add_item("silicate", 14)
	inv.add_item("fuel_cell", 3)

	var crafter = crafting_script.new()
	crafter.load_all_recipes()
	# Unlock upgrade
	var up_recipe := crafter.get_recipe("upgrade_mining_speed_t1")
	inv.add_item("steel_plate", 5)
	inv.add_item("circuit", 5)
	crafter.craft(up_recipe, inv)

	var disc = discovery_script.new()
	disc.register_discovery("moon_rock_1", "mineral", "Basalt Sample", "Moon")
	disc.upload_discovery("moon_rock_1")

	var survival := SurvivalSystem.new()
	survival.set_environment("Moon")
	survival.replenish_life_support(-20.0)

	var ship_state := {"hull": 850.0, "fuel": 600.0, "landed": false}
	var player_pos := UniversePosition.new(Vector3i(0, 0, 0), DVec3.new(500.0, 100.0, 500.0))

	var saved := saver.save_systems_state(
		inv,
		crafter,
		disc,
		survival,
		ship_state,
		player_pos,
		"Moon",
		TEST_SAVE_PATH
	)
	assert_true(saved, "Systems state saved successfully")

	# Load and verify
	var loaded := saver.load_profile(TEST_SAVE_PATH)
	assert_eq(loaded["version"], 1)
	assert_eq(loaded["credits"], 100, "100 credits from discovery upload")
	assert_eq(loaded["unlocked_upgrades"]["mining_speed"], 1, "Upgrade tier 1 saved")
	assert_eq(loaded["inventory"]["items"]["silicate"], 14, "Silicate count preserved")
	assert_almost_eq(loaded["survival_state"]["life_support"], 80.0, 0.01, "Life support saved")
	assert_eq(loaded["player_position"]["body_id"], "Moon", "Body ID Moon preserved")

	# Clean up test save file
	if FileAccess.file_exists(TEST_SAVE_PATH):
		DirAccess.remove_absolute(TEST_SAVE_PATH)

	inv.free()
	crafter.free()
	disc.free()
	survival.free()
	saver.free()
