extends SceneTree
func _init():
	var sim_time = 0.0
	var earth_pos = GravityService.body_position("Earth", sim_time)
	print("Earth pos: ", earth_pos)
	var offset = earth_pos.add(DVec3.new(0.0, 637100.0 + 50000.0, 0.0))
	print("Offset: ", offset)
	quit(0)
