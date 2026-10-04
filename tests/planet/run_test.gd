extends SceneTree

func _init():
	print("Running test...")
	var quadtree = PlanetQuadtree.new(); quadtree._ready()
	var start_pos = DVec3.new(0, 0, 700000)
	var end_pos = DVec3.new(0, 0, 637100)
	
	quadtree.camera_pos = start_pos
	quadtree._process(0.1)
	
	for i in range(10):
		var t = i / 10.0
		quadtree.camera_pos = start_pos.lerp_vec(end_pos, t)
		quadtree._process(0.1)
		
	# Wait for tasks
	if quadtree.chunk_streamer:
		quadtree.chunk_streamer.wait_all()
	
	print("Test passed: Did not crash on rapid movement")
	quit()
