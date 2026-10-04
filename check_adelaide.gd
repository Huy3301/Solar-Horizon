extends SceneTree
func _init():
	var alb = load('res://assets/textures/earth_albedo.png').get_image()
	alb.decompress()
	var w = alb.get_width()
	var h = alb.get_height()
	var px = int(0.885 * w)
	var py = int(0.694 * h)
	print('Adelaide pixel coord: ', px, ', ', py)
	print('Adelaide pixel color: ', alb.get_pixel(px, py))
	# Check water mask
	var wm = load('res://assets/textures/earth_specular_water.png').get_image()
	wm.decompress()
	print('Adelaide water mask: ', wm.get_pixel(px, py))
	quit(0)
