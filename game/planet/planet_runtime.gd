class_name PlanetRuntime extends Node3D

@export var body_def: Resource # Suppose this defines radius, etc.

var quadtree: PlanetQuadtree
var origin_service: OriginService
var planet_universe_pos: UniversePosition

func _ready():
	quadtree = PlanetQuadtree.new()
	add_child(quadtree)
	
	origin_service = get_node_or_null("/root/OriginService")
	if origin_service:
		origin_service.origin_shifted.connect(_on_origin_shifted)

	# Set up initial positions
	planet_universe_pos = UniversePosition.new()
	quadtree.planet_center = DVec3.zero()
	
func update_from_universe(camera_universe_pos: UniversePosition):
	var cam_local = camera_universe_pos.difference_to(planet_universe_pos)
	quadtree.camera_pos = cam_local
	
	if origin_service:
		quadtree.planet_center = planet_universe_pos.difference_to(origin_service.origin)
	else:
		quadtree.planet_center = DVec3.zero()

func _on_origin_shifted(_delta: DVec3):
	if origin_service:
		quadtree.planet_center = planet_universe_pos.difference_to(origin_service.origin)

func _exit_tree():
	if quadtree and quadtree.chunk_streamer:
		quadtree.chunk_streamer.wait_all()
