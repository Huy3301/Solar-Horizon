extends SceneTree
func _init():
	var sm = SphereMesh.new()
	sm.radius = 1.0
	sm.height = 2.0
	sm.radial_segments = 16
	sm.rings = 8
	var arr = sm.get_mesh_arrays()
	var verts = arr[Mesh.ARRAY_VERTEX]
	var uvs = arr[Mesh.ARRAY_TEX_UV]
	# Ring 4 (equator)
	var start = 4 * 17
	for i in range(start, start + 5):
		print('eq v: ', verts[i], ' uv: ', uvs[i])
	quit(0)
