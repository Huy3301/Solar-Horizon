class_name TestCase extends RefCounted

var _failures: Array[String] = []

func get_failures() -> Array[String]:
	return _failures

func fail(msg: String) -> void:
	_failures.append(msg)

func assert_true(condition: bool, msg: String = "") -> void:
	if not condition:
		fail("Assertion failed (true): " + msg)

func assert_false(condition: bool, msg: String = "") -> void:
	if condition:
		fail("Assertion failed (false): " + msg)

func assert_eq(a: Variant, b: Variant, msg: String = "") -> void:
	if a != b:
		fail("Assertion failed (eq): expected %s, got %s. %s" % [str(b), str(a), msg])

func assert_almost_eq(a: float, b: float, tol: float = 1e-5, msg: String = "") -> void:
	if abs(a - b) > tol:
		fail("Assertion failed (almost_eq): expected %f, got %f. %s" % [b, a, msg])

func assert_vec_almost_eq(a: Variant, b: Variant, tol: float = 1e-5, msg: String = "") -> void:
	if a == null or b == null:
		fail("Assertion failed (vec_almost_eq): one of the vectors is null")
		return
	var dist = a.distance_to(b)
	if dist > tol:
		fail("Assertion failed (vec_almost_eq): distance %f > %f (a=%s, b=%s). %s" % [dist, tol, str(a), str(b), msg])
