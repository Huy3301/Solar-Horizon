class_name TestInventory extends TestCase

func test_item_def_loading() -> void:
	var items := [
		"iron_ore", "silicate", "ice", "carbon", "oxygen_canister",
		"steel_plate", "circuit", "fuel_cell", "regolith_sample", "he3"
	]
	for item_id in items:
		var def := InventorySystem.get_item_def(item_id)
		assert_true(def != null, "ItemDef should load for " + item_id)
		assert_eq(String(def.id), item_id, "ItemDef ID matches")
		assert_true(def.mass > 0.0, "ItemDef mass should be > 0")
		assert_true(def.stack_max > 0, "ItemDef stack_max should be > 0")

func test_add_and_get_item() -> void:
	var inv := InventorySystem.new()
	inv.max_slots = 10
	inv.max_mass = 100.0

	var leftover := inv.add_item("iron_ore", 15)
	assert_eq(leftover, 0, "All 15 iron ore should fit")
	assert_eq(inv.get_amount("iron_ore"), 15, "Should have 15 iron ore")
	assert_true(inv.has_item("iron_ore", 10), "Should have at least 10")
	assert_false(inv.has_item("iron_ore", 20), "Should not have 20")
	inv.free()

func test_remove_item() -> void:
	var inv := InventorySystem.new()
	inv.add_item("silicate", 20)

	var removed := inv.remove_item("silicate", 5)
	assert_eq(removed, 5, "Should remove 5 silicate")
	assert_eq(inv.get_amount("silicate"), 15, "15 silicate remaining")

	removed = inv.remove_item("silicate", 30)
	assert_eq(removed, 15, "Should remove remaining 15")
	assert_eq(inv.get_amount("silicate"), 0, "0 silicate remaining")
	assert_false(inv.inventory.has("silicate"), "Key erased when zero")
	inv.free()

func test_mass_capacity_limit() -> void:
	var inv := InventorySystem.new()
	# steel_plate has mass 5.0 kg
	inv.max_mass = 20.0 # can hold at most 4 plates
	inv.max_slots = 10

	var leftover := inv.add_item("steel_plate", 10)
	assert_eq(leftover, 6, "Leftover should be 6 because only 4 fit in 20kg")
	assert_eq(inv.get_amount("steel_plate"), 4, "Inventory contains 4 steel plates")
	assert_almost_eq(inv.get_total_mass(), 20.0, 0.01, "Total mass is 20kg")
	inv.free()

func test_slot_capacity_limit() -> void:
	var inv := InventorySystem.new()
	inv.max_slots = 2
	inv.max_mass = 1000.0

	# iron_ore has stack_max 50
	inv.add_item("iron_ore", 50) # 1 slot
	inv.add_item("ice", 50)      # 2nd slot

	# 3rd item cannot fit because max_slots = 2
	var leftover := inv.add_item("carbon", 10)
	assert_eq(leftover, 10, "Carbon cannot fit when slots are full")
	assert_eq(inv.get_amount("carbon"), 0, "No carbon added")
	inv.free()

func test_transfer_to() -> void:
	var inv_a := InventorySystem.new()
	var inv_b := InventorySystem.new()
	inv_b.max_mass = 10.0 # ice has mass 1.0, can take 10
	inv_b.max_slots = 5

	inv_a.add_item("ice", 25)
	var transferred := inv_a.transfer_to(inv_b, "ice", 15)
	assert_eq(transferred, 10, "Only 10 transferred due to mass cap")
	assert_eq(inv_a.get_amount("ice"), 15, "15 left in source")
	assert_eq(inv_b.get_amount("ice"), 10, "10 placed in destination")

	inv_a.free()
	inv_b.free()

func test_serialization_roundtrip() -> void:
	var inv1 := InventorySystem.new()
	inv1.max_slots = 30
	inv1.max_mass = 500.0
	inv1.add_item("iron_ore", 12)
	inv1.add_item("he3", 5)

	var saved := inv1.to_dict()
	var inv2 := InventorySystem.new()
	inv2.from_dict(saved)

	assert_eq(inv2.max_slots, 30, "Max slots restored")
	assert_almost_eq(inv2.max_mass, 500.0, 0.01, "Max mass restored")
	assert_eq(inv2.get_amount("iron_ore"), 12, "Iron ore amount restored")
	assert_eq(inv2.get_amount("he3"), 5, "He3 amount restored")

	inv1.free()
	inv2.free()
