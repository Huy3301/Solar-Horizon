class_name SpikeFreeFlyCamera extends Camera3D

var camera_pos_double: PackedFloat64Array = PackedFloat64Array([0.0, 0.0, 637010.0]) # start 10m above +Z pole
var altitude: float = 10.0

@onready var planet: SpikePlanetQuadtree = $"../SpikePlanetQuadtree"
@onready var label: Label = $"../CanvasLayer/Label"

func _ready():
	# Initial sync
	if planet:
		planet.set_camera_pos_double(camera_pos_double[0], camera_pos_double[1], camera_pos_double[2])
	
func _process(delta):
	var move_dir = Vector3.ZERO
	if Input.is_key_pressed(KEY_W): move_dir.z -= 1.0
	if Input.is_key_pressed(KEY_S): move_dir.z += 1.0
	if Input.is_key_pressed(KEY_A): move_dir.x -= 1.0
	if Input.is_key_pressed(KEY_D): move_dir.x += 1.0
	
	move_dir = global_transform.basis * move_dir
	
	var r = Vector3(camera_pos_double[0], camera_pos_double[1], camera_pos_double[2]).length()
	altitude = max(1.0, r - planet.planet_radius_m)
	var speed = clamp(altitude * 0.5, 1.0, 50000.0)
	
	if move_dir.length_squared() > 0:
		move_dir = move_dir.normalized() * speed * delta
		camera_pos_double[0] += move_dir.x
		camera_pos_double[1] += move_dir.y
		camera_pos_double[2] += move_dir.z
		
	planet.set_camera_pos_double(camera_pos_double[0], camera_pos_double[1], camera_pos_double[2])
	
	if Input.is_key_pressed(KEY_P) and altitude < 2000.0:
		var rb = RigidBody3D.new()
		var col = CollisionShape3D.new()
		var mesh_inst = MeshInstance3D.new()
		var box = BoxMesh.new()
		box.size = Vector3(1,1,1)
		mesh_inst.mesh = box
		var shape = BoxShape3D.new()
		shape.size = Vector3(1,1,1)
		col.shape = shape
		rb.add_child(col)
		rb.add_child(mesh_inst)
		get_parent().add_child(rb)
		rb.position = position + -global_transform.basis.z * 5.0
	
	label.text = "FPS: %d\nAlt: %.1fm\nPatches: %d" % [
		Engine.get_frames_per_second(),
		altitude,
		planet.active_patches.size()
	]

