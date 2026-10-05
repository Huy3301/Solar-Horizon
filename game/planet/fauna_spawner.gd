class_name FaunaSpawner
extends Node3D
## Generates simple low-poly creatures with basic procedural animations.
## Keeps fauna budgets strict (max 8 active on mobile).

@export var max_active_fauna: int = 8
@export var spawn_radius: float = 50.0

var _active_fauna: Array[Node3D] = []

func _ready() -> void:
	# Keep budget strict on mobile
	if OS.has_feature("mobile") or OS.get_name() in ["Android", "iOS"]:
		max_active_fauna = min(8, max_active_fauna)
		
	var timer = Timer.new()
	timer.wait_time = 5.0
	timer.autostart = true
	timer.timeout.connect(_on_spawn_tick)
	add_child(timer)

func _on_spawn_tick() -> void:
	_cleanup_distant_fauna()
	
	if _active_fauna.size() < max_active_fauna:
		_spawn_fauna()

func _spawn_fauna() -> void:
	var fauna = ProceduralCreature.new()
	
	# Procedural body plan: Body + 4 Legs
	var body_mesh = MeshInstance3D.new()
	var box = BoxMesh.new()
	box.size = Vector3(1.0, 0.5, 2.0)
	body_mesh.mesh = box
	body_mesh.position.y = 1.0
	fauna.add_child(body_mesh)
	
	# Position randomly
	var angle = randf() * TAU
	var dist = randf_range(10.0, spawn_radius)
	var pos = global_position + Vector3(cos(angle), 0, sin(angle)) * dist
	
	add_child(fauna)
	fauna.global_position = pos
	_active_fauna.append(fauna)
	
	# Initialize procedural leg structure
	fauna.initialize_legs()

func _cleanup_distant_fauna() -> void:
	var to_remove = []
	for fauna in _active_fauna:
		if is_instance_valid(fauna):
			if fauna.global_position.distance_squared_to(global_position) > spawn_radius * spawn_radius * 1.5:
				to_remove.append(fauna)
		else:
			to_remove.append(fauna)
			
	for fauna in to_remove:
		_active_fauna.erase(fauna)
		if is_instance_valid(fauna):
			fauna.queue_free()
