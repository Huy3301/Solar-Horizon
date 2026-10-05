class_name ProceduralCreature
extends Node3D

## Low-poly procedural creature with sine-wave leg locomotion.

@export var walk_speed: float = 2.0

var time: float = 0.0
var legs: Array[MeshInstance3D] = []

func initialize_legs() -> void:
	legs.clear()
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

	# Sine-wave walk animation for legs
	for i in range(legs.size()):
		var leg = legs[i]
		if is_instance_valid(leg):
			var phase_offset = PI if (i % 2 == 0) != (i < 2) else 0.0
			var lift = max(0.0, sin(time + phase_offset)) * 0.5
			var stride = cos(time + phase_offset) * 0.5

			var original_x = 0.6 if i % 2 == 0 else -0.6
			var original_z = 0.8 if i < 2 else -0.8

			leg.position = Vector3(original_x, 0.5 + lift, original_z + stride)

	# Move forward in local space
	translate(Vector3(0, 0, delta * walk_speed * 0.5))
