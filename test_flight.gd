extends Node

func _ready():
	var root = get_tree().root
	var world = load("res://scenes/world.tscn").instantiate()
	root.add_child(world)
	# Wait for a couple physics frames
	await get_tree().physics_frame
	await get_tree().physics_frame
	
	var ship = world.get_node("Ship")
	if ship:
		print("Ship universe pos: ", ship._get_universe_pos())
		print("Dom ID: ", GravityService.dominant_body(ship._get_universe_pos(), 0.0))
		var dom_id = GravityService.dominant_body(ship._get_universe_pos(), 0.0)
		var dom_pos = GravityService.body_position(dom_id, 0.0)
		print("Dom pos: ", dom_pos)
		
		var to_ship_d = ship._get_universe_pos().sub(dom_pos)
		var r_dist = to_ship_d.length()
		print("r_dist: ", r_dist)
		
		var scale_cfg = GameScale.get_instance()
		var dom_def = BodyRegistry.get_body(dom_id)
		var planet_radius = scale_cfg.scaled_radius(dom_def.radius_m) if dom_def else 637100.0
		print("planet_radius: ", planet_radius)
		print("alt: ", r_dist - planet_radius)
	
	get_tree().quit()
