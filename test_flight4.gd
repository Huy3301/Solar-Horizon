extends SceneTree

func _init():
	var world = load("res://scenes/world.tscn").instantiate()
	root.add_child(world)
	# Wait for a couple physics frames
	await get_tree().physics_frame
	await get_tree().physics_frame
	print("World loaded successfully.")
	quit(0)
