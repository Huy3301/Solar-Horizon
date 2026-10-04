class_name GameBootstrap extends Node

## Master Game Bootstrap & Systems Integrator for Earth-Moon Vertical Slice.
## Connects PlayerRig, Ship, GameUI, TutorialDirector, SurvivalSystem,
## InventorySystem, ScannerSystem, MiningLaser, and SaveService.

const SaveServiceScript = preload("res://game/autoload/save_service.gd")
const DEFAULT_SAVE_PATH: String = "user://save_data.json"

signal soi_changed(dominant_body_id: StringName)
signal saved(path: String)
signal loaded(path: String)
signal player_respawned(spawn_position: Vector3)

@export var auto_start_tutorial: bool = true
@export var autosave_on_touchdown: bool = true

var ship: ShipFlightController = null
var player_rig: PlayerRig = null
var on_foot_rig: OnFootRig = null
var game_ui: GameUI = null
var tutorial_director: TutorialDirector = null
var earth_globe: Node3D = null
var moon_globe: Node3D = null

var survival_system: SurvivalSystem = null
var inventory_system: InventorySystem = null
var scanner_system: ScannerSystem = null
var mining_laser: MiningLaser = null
var crafting_system: Node = null
var discovery_system: Node = null

var _current_dominant_body: StringName = &"Earth"
var _adelaide_base_pos: Vector3 = Vector3(0.0, 50.0, 0.0)

func _ready() -> void:
	_resolve_scene_references()
	_init_gameplay_systems()
	_scatter_resource_nodes()
	_connect_system_events()
	_init_initial_environment()

func _resolve_scene_references() -> void:
	var parent_node = get_parent()
	if parent_node:
		ship = parent_node.get_node_or_null("Ship") as ShipFlightController
		player_rig = parent_node.get_node_or_null("PlayerRig") as PlayerRig
		game_ui = parent_node.get_node_or_null("GameUI") as GameUI
		tutorial_director = parent_node.get_node_or_null("TutorialDirector") as TutorialDirector
		earth_globe = parent_node.get_node_or_null("EarthGlobe")
		moon_globe = parent_node.get_node_or_null("MoonGlobe")

	if ship == null and is_inside_tree():
		ship = get_tree().root.find_child("Ship", true, false) as ShipFlightController
	if player_rig == null and is_inside_tree():
		player_rig = get_tree().root.find_child("PlayerRig", true, false) as PlayerRig
	if game_ui == null and is_inside_tree():
		game_ui = get_tree().root.find_child("GameUI", true, false) as GameUI
	if tutorial_director == null and is_inside_tree():
		tutorial_director = get_tree().root.find_child("TutorialDirector", true, false) as TutorialDirector

	if is_instance_valid(player_rig):
		on_foot_rig = player_rig.get_node_or_null("OnFootRig") as OnFootRig
		if on_foot_rig == null:
			on_foot_rig = player_rig.find_child("OnFootRig", true, false) as OnFootRig

	crafting_system = get_node_or_null("/root/CraftingSystem")
	discovery_system = get_node_or_null("/root/DiscoverySystem")

	if is_instance_valid(tutorial_director):
		_adelaide_base_pos = tutorial_director.adelaide_base_pos

func _init_gameplay_systems() -> void:
	# 1. SurvivalSystem
	survival_system = SurvivalSystem.new()
	survival_system.name = "SurvivalSystem"
	survival_system.is_inside_ship = (player_rig.current_mode == PlayerRig.PlayerMode.SHIP) if is_instance_valid(player_rig) else true
	add_child(survival_system)
	survival_system.add_to_group("survival_system")

	# 2. InventorySystem
	inventory_system = InventorySystem.new()
	inventory_system.name = "InventorySystem"
	inventory_system.max_slots = 20
	inventory_system.max_mass = 250.0
	add_child(inventory_system)
	inventory_system.add_to_group("inventory_system")

	# 3. ScannerSystem (mounted on OnFootRig if available)
	scanner_system = ScannerSystem.new()
	scanner_system.name = "ScannerSystem"
	scanner_system.scan_radius = 80.0
	scanner_system.scan_duration = 0.5
	scanner_system.add_to_group("scanner")
	if is_instance_valid(on_foot_rig):
		on_foot_rig.add_child(scanner_system)
		scanner_system.position = Vector3(0.0, 1.6, 0.0)
	else:
		add_child(scanner_system)

	# 4. MiningLaser (mounted on OnFootRig if available)
	mining_laser = MiningLaser.new()
	mining_laser.name = "MiningLaser"
	mining_laser.range_m = 40.0
	mining_laser.mining_efficiency = 1.0
	if is_instance_valid(on_foot_rig):
		on_foot_rig.add_child(mining_laser)
		mining_laser.position = Vector3(0.0, 1.4, 0.0)
	else:
		add_child(mining_laser)

	# Connect subsystems to OnFootRig
	if is_instance_valid(on_foot_rig):
		on_foot_rig.set("inventory", inventory_system)
		on_foot_rig.set("scanner", scanner_system)
		on_foot_rig.set("mining_laser", mining_laser)
		on_foot_rig.set("crafting", crafting_system)
		on_foot_rig.set("discovery", discovery_system)
		on_foot_rig.set("survival", survival_system)

	# Connect Inventory to GameUI Inventory Menu
	if is_instance_valid(game_ui) and game_ui.inventory_menu:
		if game_ui.inventory_menu.has_method("set_inventory_system"):
			game_ui.inventory_menu.set_inventory_system(inventory_system)

	# Connect Survival and SuitBars
	if is_instance_valid(game_ui) and game_ui.suit_bars:
		survival_system.life_support_changed.connect(game_ui.suit_bars.update_life_support)
		survival_system.hazard_protection_changed.connect(game_ui.suit_bars.update_hazard)
		if is_instance_valid(on_foot_rig) and on_foot_rig.has_signal("jetpack_fuel_changed"):
			on_foot_rig.jetpack_fuel_changed.connect(game_ui.suit_bars.update_jetpack)

func _connect_system_events() -> void:
	# Survival events
	survival_system.player_died.connect(_on_player_died)

	# Ship landing and crash events
	if is_instance_valid(ship):
		ship.landing_state_changed.connect(_on_ship_landing_state_changed)
		if ship.has_signal("ship_crashed"):
			ship.ship_crashed.connect(_on_ship_crashed)

	# PlayerRig mode changes
	if is_instance_valid(player_rig):
		player_rig.mode_changed.connect(_on_player_mode_changed)

	# Scanner cataloging
	scanner_system.scan_completed.connect(_on_scan_completed)

	# Tutorial Director wiring
	if is_instance_valid(tutorial_director):
		tutorial_director.ship = ship
		tutorial_director.player_rig = player_rig
		tutorial_director.game_ui = game_ui
		tutorial_director.scanner_system = scanner_system
		tutorial_director.respawned_at_base.connect(_on_tutorial_respawned)
		if auto_start_tutorial and not tutorial_director.is_active:
			tutorial_director.start_tutorial()

	# Pause menu respawn request
	if is_instance_valid(game_ui) and game_ui.pause_menu:
		if game_ui.pause_menu.has_signal("respawn_requested"):
			game_ui.pause_menu.respawn_requested.connect(respawn_player)

func _init_initial_environment() -> void:
	_current_dominant_body = &"Earth"
	if is_instance_valid(survival_system):
		survival_system.set_environment(_current_dominant_body)

func _physics_process(_delta: float) -> void:
	_check_soi_change()

func _check_soi_change() -> void:
	var active_pos: DVec3 = DVec3.zero()
	var sim_time: float = _get_sim_time()

	if is_instance_valid(player_rig) and player_rig.current_mode == PlayerRig.PlayerMode.WALK:
		if is_instance_valid(on_foot_rig) and on_foot_rig.has_method("_get_universe_pos"):
			active_pos = on_foot_rig._get_universe_pos()
		elif is_instance_valid(on_foot_rig):
			active_pos = DVec3.from_vector3(on_foot_rig.global_position)
	elif is_instance_valid(ship) and ship.has_method("_get_universe_pos"):
		active_pos = ship._get_universe_pos()
	elif is_instance_valid(ship):
		active_pos = DVec3.from_vector3(ship.global_position)

	var dom_body = GravityService.dominant_body(active_pos, sim_time)
	if dom_body != _current_dominant_body:
		_current_dominant_body = dom_body
		if is_instance_valid(survival_system):
			survival_system.set_environment(dom_body)
		soi_changed.emit(dom_body)

func _get_sim_time() -> float:
	var clock = get_node_or_null("/root/SimulationClock")
	if clock and "sim_time_s" in clock:
		return clock.sim_time_s
	return 0.0

# --- Resource Node Generation ---

func _scatter_resource_nodes() -> void:
	_scatter_earth_resources()
	_scatter_moon_resources()

func _scatter_earth_resources() -> void:
	if not is_instance_valid(earth_globe):
		earth_globe = get_node_or_null("../EarthGlobe")
	if not is_instance_valid(earth_globe):
		return

	var earth_runtime = earth_globe.get_node_or_null("PlanetRuntime") as PlanetRuntime
	var earth_r = earth_runtime.planet_radius_m if earth_runtime else 637100.0
	var max_h = earth_runtime.max_height_m if earth_runtime else 8848.0

	var container = Node3D.new()
	container.name = "EarthResourceNodes"
	earth_globe.add_child(container)

	var deposits = [
		{"type": "iron_ore", "color": Color(0.72, 0.32, 0.15), "count": 6},
		{"type": "silicate", "color": Color(0.68, 0.65, 0.60), "count": 6},
		{"type": "ice", "color": Color(0.55, 0.85, 0.98), "count": 4},
	]

	var rng = RandomNumberGenerator.new()
	rng.seed = 42

	for dep in deposits:
		for i in range(dep["count"]):
			var angle = rng.randf_range(0.0, TAU)
			var dist = rng.randf_range(25.0, 160.0)
			var offset_x = cos(angle) * dist
			var offset_z = sin(angle) * dist

			var dir = Vector3(offset_x, earth_r, offset_z).normalized()
			var h_norm = TerrainNoise.sample_height(dir.x, dir.y, dir.z, "Earth")
			var r_surface = earth_r + h_norm * max_h
			var local_pos = dir * r_surface

			_create_resource_node(container, local_pos, dep["type"], dep["color"], 100.0)

func _scatter_moon_resources() -> void:
	if not is_instance_valid(moon_globe):
		moon_globe = get_node_or_null("../MoonGlobe")
	if not is_instance_valid(moon_globe):
		return

	var moon_runtime = moon_globe.get_node_or_null("PlanetRuntime") as PlanetRuntime
	var moon_r = moon_runtime.planet_radius_m if moon_runtime else 173740.0
	var max_h = moon_runtime.max_height_m if moon_runtime else 10700.0

	var container = Node3D.new()
	container.name = "MoonResourceNodes"
	moon_globe.add_child(container)

	var deposits = [
		{"type": "iron_ore", "color": Color(0.65, 0.35, 0.18), "count": 5},
		{"type": "silicate", "color": Color(0.60, 0.60, 0.62), "count": 5},
		{"type": "ice", "color": Color(0.50, 0.80, 0.95), "count": 5},
		{"type": "he3", "color": Color(0.30, 0.95, 0.80), "count": 5},
	]

	var rng = RandomNumberGenerator.new()
	rng.seed = 1337

	for dep in deposits:
		for i in range(dep["count"]):
			var angle = rng.randf_range(0.0, TAU)
			var dist = rng.randf_range(20.0, 180.0)
			var offset_x = cos(angle) * dist
			var offset_z = sin(angle) * dist

			var dir = Vector3(offset_x, moon_r, offset_z).normalized()
			var h_norm = TerrainNoise.sample_height(dir.x, dir.y, dir.z, "Moon")
			var r_surface = moon_r + h_norm * max_h
			var local_pos = dir * r_surface

			_create_resource_node(container, local_pos, dep["type"], dep["color"], 100.0)

func _create_resource_node(parent: Node, local_pos: Vector3, item_id: String, color: Color, amount: float) -> ResourceNode:
	var node := ResourceNode.new()
	node.name = "%s_%d" % [item_id.capitalize(), parent.get_child_count()]
	node.item_id = item_id
	node.amount = amount
	node.max_amount = amount
	node.mining_rate = 15.0
	node.hardness = 1.0 if item_id != "he3" else 1.5
	node.position = local_pos
	node.add_to_group("scannable")

	# Area3D Collision Shape
	var col := CollisionShape3D.new()
	col.name = "CollisionShape3D"
	var sphere_shape := SphereShape3D.new()
	sphere_shape.radius = 1.8
	col.shape = sphere_shape
	node.add_child(col)

	# Visual Rock / Deposit Mesh
	var mesh_inst := MeshInstance3D.new()
	mesh_inst.name = "DepositMesh"
	var mesh_shape := SphereMesh.new()
	mesh_shape.radius = 1.2
	mesh_shape.height = 2.4
	mesh_inst.mesh = mesh_shape

	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.55
	if item_id == "he3":
		mat.emission_enabled = true
		mat.emission = color
		mat.emission_energy_multiplier = 2.5
	mesh_inst.material_override = mat
	node.add_child(mesh_inst)

	parent.add_child(node)
	return node

# --- Event Handlers & Respawn ---

func _on_player_died() -> void:
	if is_instance_valid(tutorial_director):
		tutorial_director.fail_mission("Life support failure / lethal hazard breach.")
	else:
		respawn_player()

func _on_ship_crashed(reason: String) -> void:
	if is_instance_valid(tutorial_director):
		tutorial_director.fail_mission("Ship crashed: %s" % reason)
	else:
		respawn_player()

func _on_ship_landing_state_changed(is_landed: bool, _message: String) -> void:
	if is_landed and autosave_on_touchdown:
		autosave()

func _on_player_mode_changed(new_mode: int) -> void:
	var origin_svc = get_node_or_null("/root/OriginService")
	if origin_svc:
		if new_mode == PlayerRig.PlayerMode.WALK and is_instance_valid(on_foot_rig):
			origin_svc.set_focus_node(on_foot_rig)
		elif new_mode == PlayerRig.PlayerMode.SHIP and is_instance_valid(ship):
			origin_svc.set_focus_node(ship)

func _on_scan_completed(targets: Array) -> void:
	if is_instance_valid(discovery_system):
		for t in targets:
			if t is Dictionary:
				var id_val: String = str(t.get("id", t.get("name", "unknown")))
				var cat_val: String = str(t.get("category", "mineral"))
				var name_val: String = str(t.get("name", id_val))
				discovery_system.register_discovery(id_val, cat_val, name_val, String(_current_dominant_body), t)

func _on_tutorial_respawned() -> void:
	respawn_player()

func respawn_player() -> void:
	# 1. Reset Survival state
	if is_instance_valid(survival_system):
		survival_system.respawn("Earth", _adelaide_base_pos)

	# 2. Reset Ship to Adelaide Base
	if is_instance_valid(ship):
		ship.linear_velocity = Vector3.ZERO
		ship.angular_velocity = Vector3.ZERO
		ship.global_position = _adelaide_base_pos
		ship.global_transform.basis = Basis.IDENTITY
		ship.is_crashed = false
		ship.is_landed = true
		ship.landing_gear_deployed = true
		ship.current_throttle = 0.0

	# 3. Enter Ship in PlayerRig
	if is_instance_valid(player_rig):
		player_rig.enter_ship(ship)

	# 4. Focus OriginService on ship
	var origin_svc = get_node_or_null("/root/OriginService")
	if origin_svc and is_instance_valid(ship):
		origin_svc.set_focus_node(ship)

	player_respawned.emit(_adelaide_base_pos)

# --- Save & Load Implementation (F5 / F9 / Autosave) ---

func _get_saver() -> Object:
	var saver: Object = get_node_or_null("/root/SaveService")
	if saver:
		return saver
	return SaveServiceScript.new()

func quick_save(path: String = DEFAULT_SAVE_PATH) -> bool:
	var ship_dict: Dictionary = {}
	if is_instance_valid(ship):
		ship_dict = {
			"position": [ship.global_position.x, ship.global_position.y, ship.global_position.z],
			"linear_velocity": [ship.linear_velocity.x, ship.linear_velocity.y, ship.linear_velocity.z],
			"rotation": [ship.rotation.x, ship.rotation.y, ship.rotation.z],
			"throttle": ship.current_throttle if "current_throttle" in ship else 0.0,
			"gear_down": ship.landing_gear_deployed if "landing_gear_deployed" in ship else false,
			"is_landed": ship.is_landed if "is_landed" in ship else false,
		}

	var on_foot_pos: Array = [0.0, 0.0, 0.0]
	if is_instance_valid(on_foot_rig):
		on_foot_pos = [on_foot_rig.global_position.x, on_foot_rig.global_position.y, on_foot_rig.global_position.z]

	var saver = _get_saver()
	var v_num: int = 1
	if "CURRENT_VERSION" in saver:
		v_num = saver.CURRENT_VERSION

	var profile: Dictionary = {
		"version": v_num,
		"inventory": inventory_system.to_dict() if is_instance_valid(inventory_system) else {},
		"survival_state": survival_system.to_dict() if is_instance_valid(survival_system) else {},
		"ship_state": ship_dict,
		"player_mode": int(player_rig.current_mode) if is_instance_valid(player_rig) else 0,
		"on_foot_position": on_foot_pos,
		"dominant_body": String(_current_dominant_body),
		"unlocked_upgrades": crafting_system.get("unlocked_upgrades") if is_instance_valid(crafting_system) else {},
		"crafting_stats": crafting_system.get("stats") if is_instance_valid(crafting_system) else {},
		"credits": discovery_system.get("credits") if is_instance_valid(discovery_system) else 0,
		"discoveries": discovery_system.get("discoveries") if is_instance_valid(discovery_system) else {},
	}

	var success: bool = false
	if saver.has_method("save_profile"):
		success = saver.save_profile(profile, path)
	if saver is RefCounted or not saver.is_inside_tree():
		if saver is Node and not saver.is_inside_tree():
			saver.free()

	if success:
		saved.emit(path)
		if is_instance_valid(game_ui) and game_ui.has_method("set_interaction_prompt"):
			game_ui.set_interaction_prompt(true, "QUICK SAVED")
	return success

func quick_load(path: String = DEFAULT_SAVE_PATH) -> bool:
	var saver = _get_saver()
	var data: Dictionary = {}
	if saver.has_method("load_profile"):
		data = saver.load_profile(path)
	if saver is Node and not saver.is_inside_tree():
		saver.free()

	if data.is_empty():
		return false

	# 1. Restore Inventory
	if data.has("inventory") and data["inventory"] is Dictionary and is_instance_valid(inventory_system):
		inventory_system.from_dict(data["inventory"])
		if is_instance_valid(game_ui) and game_ui.inventory_menu:
			game_ui.inventory_menu.refresh_grid()

	# 2. Restore Survival
	if data.has("survival_state") and data["survival_state"] is Dictionary and is_instance_valid(survival_system):
		survival_system.from_dict(data["survival_state"])

	# 3. Restore Ship
	if data.has("ship_state") and data["ship_state"] is Dictionary and is_instance_valid(ship):
		var s: Dictionary = data["ship_state"]
		if s.has("position") and s["position"].size() >= 3:
			ship.global_position = Vector3(float(s["position"][0]), float(s["position"][1]), float(s["position"][2]))
		if s.has("linear_velocity") and s["linear_velocity"].size() >= 3:
			ship.linear_velocity = Vector3(float(s["linear_velocity"][0]), float(s["linear_velocity"][1]), float(s["linear_velocity"][2]))
		if s.has("rotation") and s["rotation"].size() >= 3:
			ship.rotation = Vector3(float(s["rotation"][0]), float(s["rotation"][1]), float(s["rotation"][2]))
		if s.has("throttle") and "current_throttle" in ship:
			ship.current_throttle = float(s["throttle"])
			ship.target_throttle = float(s["throttle"])
		if s.has("gear_down") and "landing_gear_deployed" in ship:
			ship.landing_gear_deployed = bool(s["gear_down"])
		if s.has("is_landed") and "is_landed" in ship:
			ship.is_landed = bool(s["is_landed"])

	# 4. Restore Player Mode & Position
	var p_mode: int = int(data.get("player_mode", 0))
	if is_instance_valid(player_rig):
		if p_mode == 1: # WALK
			player_rig.exit_ship(true)
			if data.has("on_foot_position") and data["on_foot_position"].size() >= 3 and is_instance_valid(on_foot_rig):
				on_foot_rig.global_position = Vector3(float(data["on_foot_position"][0]), float(data["on_foot_position"][1]), float(data["on_foot_position"][2]))
		else: # SHIP
			player_rig.enter_ship(ship)

	# 5. Dominant body / SOI
	if data.has("dominant_body"):
		_current_dominant_body = StringName(data["dominant_body"])
		if is_instance_valid(survival_system):
			survival_system.set_environment(_current_dominant_body)

	loaded.emit(path)
	if is_instance_valid(game_ui) and game_ui.has_method("set_interaction_prompt"):
		game_ui.set_interaction_prompt(true, "QUICK LOADED")
	return true

func autosave(path: String = DEFAULT_SAVE_PATH) -> bool:
	return quick_save(path)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("quick_save") or (event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_F5):
		quick_save()
	elif event.is_action_pressed("quick_load") or (event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_F9):
		quick_load()

# --- Public Gameplay APIs for Tests & Scripting ---

func trigger_scan() -> Array[Dictionary]:
	if not is_instance_valid(scanner_system):
		return []
	var targets: Array[Dictionary] = scanner_system.scan_and_catalog(
		discovery_system,
		String(_current_dominant_body)
	)
	scanner_system.scan_completed.emit(targets)
	return targets

func fire_mining_laser(target_node: ResourceNode = null, delta: float = 1.0) -> Dictionary:
	if not is_instance_valid(mining_laser):
		return {}

	var origin: Vector3 = Vector3.ZERO
	var direction: Vector3 = Vector3.FORWARD
	if is_instance_valid(on_foot_rig):
		origin = on_foot_rig.global_position + Vector3(0.0, 1.4, 0.0)
		direction = -on_foot_rig.global_transform.basis.z
		if on_foot_rig.camera:
			origin = on_foot_rig.camera.global_position
			direction = -on_foot_rig.camera.global_transform.basis.z
	elif is_instance_valid(ship):
		origin = ship.global_position
		direction = -ship.global_transform.basis.z

	if target_node != null and is_instance_valid(target_node):
		direction = (target_node.global_position - origin).normalized()
		var res: Dictionary = mining_laser.fire_laser(origin, direction, delta, inventory_system)
		if not res.get("hit", false) or res.get("amount_mined", 0.0) == 0.0:
			var mined: float = target_node.mine(delta, inventory_system, mining_laser.mining_efficiency)
			res["hit"] = true
			res["collider"] = target_node
			res["position"] = target_node.global_position
			res["amount_mined"] = mined
			mining_laser.laser_hit.emit(target_node, mined)
		return res
	else:
		return mining_laser.fire_laser(origin, direction, delta, inventory_system)

func get_inventory() -> InventorySystem:
	return inventory_system

func get_survival() -> SurvivalSystem:
	return survival_system

func get_scanner() -> ScannerSystem:
	return scanner_system

func get_mining_laser() -> MiningLaser:
	return mining_laser
