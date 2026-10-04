class_name TestSlicePlaythrough
extends TestCase

## Integration smoke test for the Earth-Moon vertical slice playthrough.
## Exercises scene loading, PlayerRig, GameUI, GameBootstrap systems,
## resource gathering, scanning, and save/load persistence.

func test_main_scene_slice_hierarchy() -> void:
	var scene_res = load("res://scenes/main.tscn") as PackedScene
	assert_true(scene_res != null, "main.tscn loads")

	var world = scene_res.instantiate() as MainWorld
	assert_true(world != null, "main.tscn instantiates as MainWorld")

	var loop = Engine.get_main_loop()
	if loop and "root" in loop and loop.root != null:
		loop.root.add_child(world)
	else:
		world._ready()
		var b = world.get_node_or_null("GameBootstrap") as GameBootstrap
		if b:
			b._ready()

	# Verify essential nodes
	var ship = world.get_node_or_null("Ship") as ShipFlightController
	assert_true(ship != null, "Ship node exists")

	var player_rig = world.get_node_or_null("PlayerRig") as PlayerRig
	assert_true(player_rig != null, "PlayerRig node exists")

	var game_ui = world.get_node_or_null("GameUI") as GameUI
	assert_true(game_ui != null, "GameUI node exists")

	var tutorial = world.get_node_or_null("TutorialDirector") as TutorialDirector
	assert_true(tutorial != null, "TutorialDirector node exists")

	var bootstrap = world.get_node_or_null("GameBootstrap") as GameBootstrap
	assert_true(bootstrap != null, "GameBootstrap node exists")

	# Check GameBootstrap initialized systems
	assert_true(bootstrap.get_inventory() != null, "InventorySystem initialized")
	assert_true(bootstrap.get_survival() != null, "SurvivalSystem initialized")
	assert_true(bootstrap.get_scanner() != null, "ScannerSystem initialized")
	assert_true(bootstrap.get_mining_laser() != null, "MiningLaser initialized")

	# Check scattered resource nodes exist
	var earth_resources = world.get_node_or_null("EarthGlobe/EarthResourceNodes")
	assert_true(earth_resources != null, "EarthResourceNodes container exists")
	if earth_resources:
		assert_true(earth_resources.get_child_count() > 0, "Earth has scattered resource deposits")

	var moon_resources = world.get_node_or_null("MoonGlobe/MoonResourceNodes")
	assert_true(moon_resources != null, "MoonResourceNodes container exists")
	if moon_resources:
		assert_true(moon_resources.get_child_count() > 0, "Moon has scattered resource deposits")

	if world.get_parent():
		world.get_parent().remove_child(world)
	world.free()

func test_slice_gameplay_and_persistence() -> void:
	var scene_res = load("res://scenes/main.tscn") as PackedScene
	var world = scene_res.instantiate() as MainWorld

	var loop = Engine.get_main_loop()
	if loop and "root" in loop and loop.root != null:
		loop.root.add_child(world)
	else:
		world._ready()
		var b = world.get_node_or_null("GameBootstrap") as GameBootstrap
		if b:
			b._ready()

	var ship = world.get_node_or_null("Ship") as ShipFlightController
	var bootstrap = world.get_node_or_null("GameBootstrap") as GameBootstrap
	var inventory = bootstrap.get_inventory()

	# 1. Simulate physics ticks
	for i in range(30):
		world._physics_process(1.0 / 60.0)
		ship._physics_process(1.0 / 60.0)
		bootstrap._physics_process(1.0 / 60.0)

	# 2. Mine a resource node
	var earth_resources = world.get_node_or_null("EarthGlobe/EarthResourceNodes")
	if earth_resources and earth_resources.get_child_count() > 0:
		var target_node = earth_resources.get_child(0) as ResourceNode
		assert_true(target_node != null, "First resource node is valid")
		var initial_amount = target_node.amount
		var result = bootstrap.fire_mining_laser(target_node, 1.0)
		assert_true(result.get("hit", false), "Mining laser hit target node")
		assert_true(result.get("amount_mined", 0.0) > 0.0, "Resource mined from node")
		assert_true(target_node.amount < initial_amount, "Target node amount depleted")
		assert_true(inventory.get_amount(target_node.item_id) > 0, "Mined resources added to inventory")

	# 3. Test Scanner system
	var scan_results = bootstrap.trigger_scan()
	assert_true(scan_results is Array, "Scanner returned target array")

	# 4. Test Quick Save & Quick Load round-trip
	var test_save_path = "user://test_slice_save.json"
	var save_success = bootstrap.quick_save(test_save_path)
	assert_true(save_success, "Quick save succeeds")

	var load_success = bootstrap.quick_load(test_save_path)
	assert_true(load_success, "Quick load succeeds")

	# Clean up test save file
	if FileAccess.file_exists(test_save_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(test_save_path))

	if world.get_parent():
		world.get_parent().remove_child(world)
	world.free()
