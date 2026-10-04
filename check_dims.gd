extends SceneTree
func _init():
	for name in ['earth_albedo.png', 'earth_city_lights.png', 'earth_clouds.png', 'earth_normal.png', 'earth_specular_water.png']:
		var img = load('res://assets/textures/' + name).get_image()
		print(name, ' size: ', img.get_size(), ' format: ', img.get_format())
	quit(0)
