class_name DVec3 extends RefCounted

var x: float = 0.0
var y: float = 0.0
var z: float = 0.0

func _init(_x: float = 0.0, _y: float = 0.0, _z: float = 0.0) -> void:
	x = _x
	y = _y
	z = _z

static func zero() -> DVec3:
	return DVec3.new(0.0, 0.0, 0.0)

static func from_vector3(v: Vector3) -> DVec3:
	return DVec3.new(v.x, v.y, v.z)

func to_vector3() -> Vector3:
	return Vector3(x, y, z)

func to_local_vector3(origin: DVec3) -> Vector3:
	return Vector3(x - origin.x, y - origin.y, z - origin.z)

func _to_string() -> String:
	return "(%f, %f, %f)" % [x, y, z]

# Out-of-place operations
func add(other: DVec3) -> DVec3:
	return DVec3.new(x + other.x, y + other.y, z + other.z)

func sub(other: DVec3) -> DVec3:
	return DVec3.new(x - other.x, y - other.y, z - other.z)

func mul_scalar(s: float) -> DVec3:
	return DVec3.new(x * s, y * s, z * s)

func div_scalar(s: float) -> DVec3:
	return DVec3.new(x / s, y / s, z / s)

func dot(other: DVec3) -> float:
	return x * other.x + y * other.y + z * other.z

func cross(other: DVec3) -> DVec3:
	return DVec3.new(
		y * other.z - z * other.y,
		z * other.x - x * other.z,
		x * other.y - y * other.x
	)

func length_squared() -> float:
	return x * x + y * y + z * z

func length() -> float:
	return sqrt(length_squared())

func normalized() -> DVec3:
	var l = length()
	if l == 0.0:
		return DVec3.zero()
	return DVec3.new(x / l, y / l, z / l)

func distance_to(other: DVec3) -> float:
	var dx = x - other.x
	var dy = y - other.y
	var dz = z - other.z
	return sqrt(dx * dx + dy * dy + dz * dz)

func lerp_vec(other: DVec3, t: float) -> DVec3:
	return DVec3.new(
		x + (other.x - x) * t,
		y + (other.y - y) * t,
		z + (other.z - z) * t
	)

func is_equal_approx(other: DVec3) -> bool:
	return is_equal_approx(x, other.x) and is_equal_approx(y, other.y) and is_equal_approx(z, other.z)

# In-place operations
func add_in_place(other: DVec3) -> void:
	x += other.x
	y += other.y
	z += other.z

func sub_in_place(other: DVec3) -> void:
	x -= other.x
	y -= other.y
	z -= other.z

func mul_scalar_in_place(s: float) -> void:
	x *= s
	y *= s
	z *= s

func div_scalar_in_place(s: float) -> void:
	x /= s
	y /= s
	z /= s
