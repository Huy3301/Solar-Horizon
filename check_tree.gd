extends SceneTree
func _init():
	var root = Node3D.new()
	var origin_svc = OriginService.new()
	origin_svc.add_to_group("origin_service")
	root.add_child(origin_svc)
	if root.get_tree() == null:
		print("root not in tree")
	quit(0)
