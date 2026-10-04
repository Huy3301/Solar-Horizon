extends SceneTree
func _init():
	var img = load("res://assets/textures/earth_clouds.png").get_image()
	img.decompress()
	var c1 = img.get_pixel(img.get_width()/2, img.get_height()/2)
	var c2 = img.get_pixel(img.get_width()/4, img.get_height()/4)
	print("Cloud format: ", img.get_format())
	print("Cloud C1: ", c1)
	print("Cloud C2: ", c2)
	
	var alb = load("res://assets/textures/earth_albedo.png").get_image()
	alb.decompress()
	var a1 = alb.get_pixel(alb.get_width()/2, alb.get_height()/2)
	var a2 = alb.get_pixel(alb.get_width()/4, alb.get_height()/4)
	print("Albedo format: ", alb.get_format())
	print("Albedo C1: ", a1)
	print("Albedo C2: ", a2)
	
	quit(0)
