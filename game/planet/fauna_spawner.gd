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
	var fauna = Node3D.new()
	
	# Procedural body plan: Body + 4 Legs
	var body_mesh = MeshInstance3D.new()
	var box = BoxMesh.new()
	box.size = Vector3(1.0, 0.5, 2.0)
	body_mesh.mesh = box
	body_mesh.position.y = 1.0
	fauna.add_child(body_mesh)
	
	# Basic procedural animation via script
	var anim_script = _create_fauna_animator()
	fauna.set_script(anim_script)
	
	# Position randomly
	var angle = randf() * TAU
	var dist = randf_range(10.0, spawn_radius)
	var pos = global_position + Vector3(cos(angle), 0, sin(angle)) * dist
	
	fauna.global_position = pos
	
	add_child(fauna)
	_active_fauna.append(fauna)
	
	# Setup initial state for script
	if fauna.has_method("initialize_legs"):
		fauna.call("initialize_legs")

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

func _create_fauna_animator() -> GDScript:
	var script = GDScript.new()
	script.source_code = """
extends Node3D

var time: float = 0.0
var walk_speed: float = 2.0
var legs: Array[MeshInstance3D] = []

func initialize_legs() -> void:
	for i in range(4):
		var leg = MeshInstance3D.new()
		var cyl = CylinderMesh.new()
		cyl.top_radius = 0.1
		cyl.bottom_radius = 0.05
		cyl.height = 1.0
		leg.mesh = cyl
		
		var x_offset = 0.6 if i % 2 == 0 else -0.6
		var z_offset = 0.8 if i < 2 else -0.8
		leg.position = Vector3(x_offset, 0.5, z_offset)
		add_child(leg)
		legs.append(leg)

func _process(delta: float) -> void:
	time += delta * walk_speed
	
	# Basic sine-wave walk animation for legs
	for i in range(legs.size()):
		var leg = legs[i]
		var phase_offset = PI if (i % 2 == 0) != (i < 2) else 0.0
		var lift = max(0.0, sin(time + phase_offset)) * 0.5
		var stride = cos(time + phase_offset) * 0.5
		
		var original_x = 0.6 if i % 2 == 0 else -0.6
		var original_z = 0.8 if i < 2 else -0.8
		
		leg.position = Vector3(original_x, 0.5 + lift, original_z + stride)
		
	# Move forward slowly
	position.z += delta * walk_speed * 0.5
"""
	script.reload()
	return script
