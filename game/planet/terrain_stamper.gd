class_name TerrainStamper
extends RefCounted

## Edits chunk heightmap dynamically around base foundations and saves deltas.

const FLATTEN_RADIUS = 10.0
const BLEND_RADIUS = 5.0

## Applies a foundation stamp to a specific location
static func apply_foundation_stamp(global_pos: Vector3, chunk_streamer: Node, save_service: Node) -> void:
	if not chunk_streamer.has_method("get_chunk_coords") or not chunk_streamer.has_method("get_chunk"):
		return
		
	# Convert global position to chunk coordinates
	var chunk_coords = chunk_streamer.get_chunk_coords(global_pos)
	var chunk = chunk_streamer.get_chunk(chunk_coords)
	
	if not chunk:
		return
		
	var local_pos = chunk.to_local(global_pos)
	var height = local_pos.y
	
	# Apply stamp
	_flatten_area(chunk, local_pos, height)
	
	# Save delta
	if save_service and save_service.has_method("save_terrain_delta"):
		save_service.save_terrain_delta(chunk_coords, local_pos, height, FLATTEN_RADIUS)
		
	# Recalculate collision dynamically
	if chunk.has_method("rebuild_collision"):
		chunk.rebuild_collision()

static func _flatten_area(chunk: Node, center_local: Vector3, target_height: float) -> void:
	if not chunk.has_method("get_heightmap") or not chunk.has_method("set_heightmap"):
		return
		
	var heightmap = chunk.get_heightmap()
	# DEFERRED(phase 7): modify a 2D array or image based on distance to center_local
	pass
