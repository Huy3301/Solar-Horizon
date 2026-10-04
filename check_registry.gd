extends SceneTree
func _init():
	var earth = BodyRegistry.get_body("Earth")
	if earth:
		print("Earth found!")
	else:
		print("Earth NOT found!")
		print(BodyRegistry._bodies.keys())
	quit(0)
