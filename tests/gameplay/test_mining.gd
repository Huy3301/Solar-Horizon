class_name TestMining extends TestCase

func test_resource_node_mine_depletion() -> void:
	var node := ResourceNode.new()
	node.item_id = "iron_ore"
	node.amount = 50.0
	node.mining_rate = 10.0 # 10 units/s
	node.hardness = 1.0

	var mined := node.mine(2.0) # 2 seconds -> 20 units
	assert_almost_eq(mined, 20.0, 0.01, "Mined 20 units")
	assert_almost_eq(node.amount, 30.0, 0.01, "30 units remaining")

	# Mine remaining
	mined = node.mine(4.0)
	assert_almost_eq(mined, 30.0, 0.01, "Mined remaining 30 units")
	assert_almost_eq(node.amount, 0.0, 0.001, "Node depleted")
	node.free()

func test_resource_node_yield_to_inventory() -> void:
	var inv := InventorySystem.new()
	inv.max_mass = 500.0
	inv.max_slots = 10

	var node := ResourceNode.new()
	node.item_id = "ice"
	node.amount = 50.0
	node.mining_rate = 5.0 # 5 units/s
	node.hardness = 1.0

	# Mine for 1.5 seconds -> 7.5 units -> 7 whole units yielded
	var mined := node.mine(1.5, inv)
	assert_almost_eq(mined, 7.5, 0.01, "7.5 extracted")
	assert_eq(inv.get_amount("ice"), 7, "7 whole ice units added to inventory")

	# Mine another 0.6 seconds -> 3.0 units -> total fractional was 0.5 + 3.0 = 3.5 -> 3 more units
	node.mine(0.6, inv)
	assert_eq(inv.get_amount("ice"), 10, "10 total ice units in inventory")

	inv.free()
	node.free()

func test_resource_node_hardness() -> void:
	var node := ResourceNode.new()
	node.amount = 100.0
	node.mining_rate = 10.0
	node.hardness = 2.0 # double hardness -> half rate

	var mined := node.mine(1.0)
	assert_almost_eq(mined, 5.0, 0.01, "Hardness 2 halves extraction rate")
	node.free()

func test_mining_laser_heat_and_overheat() -> void:
	var laser := MiningLaser.new()
	laser.max_heat = 50.0
	laser.heat_rate = 25.0 # reaches 50 in 2s
	laser.cool_rate = 50.0

	var res := laser.fire_laser(Vector3.ZERO, Vector3.FORWARD, 1.0)
	assert_almost_eq(laser.heat, 25.0, 0.01, "Heat is 25 after 1s")
	assert_false(laser.is_overheated, "Not yet overheated")

	# Fire another 1.1s -> trips max heat
	res = laser.fire_laser(Vector3.ZERO, Vector3.FORWARD, 1.1)
	assert_true(laser.is_overheated, "Overheat triggered")
	assert_almost_eq(laser.heat, 50.0, 0.01, "Heat capped at max")

	# Attempt to fire while overheated -> returns overheated status without firing
	res = laser.fire_laser(Vector3.ZERO, Vector3.FORWARD, 0.5)
	assert_true(res.get("overheated", false), "Cannot fire while overheated")

	# Cool down process
	laser._process(1.0) # cools 50 -> heat = 0, is_overheated becomes false
	assert_false(laser.is_overheated, "Laser cooled down")
	assert_almost_eq(laser.heat, 0.0, 0.01, "Heat reset to 0")

	laser.free()
