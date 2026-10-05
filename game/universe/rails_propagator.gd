class_name RailsPropagator extends RefCounted

## Universal-Variable Kepler Propagator & Rails Stepper for Time Warp (SH-04)

class RailsState extends RefCounted:
	var r: DVec3 = DVec3.zero()
	var v: DVec3 = DVec3.zero()
	var mu: float = OrbitalMechanics.DEFAULT_MU
	var dominant_body: StringName = &"Earth"
	
	func _init(p_r: DVec3 = DVec3.zero(), p_v: DVec3 = DVec3.zero(), p_mu: float = OrbitalMechanics.DEFAULT_MU, p_dominant_body: StringName = &"Earth") -> void:
		r = p_r
		v = p_v
		mu = p_mu
		dominant_body = p_dominant_body
		
	func step(dt: float) -> void:
		var res = RailsPropagator.propagate(r, v, dt, mu)
		r = res[0]
		v = res[1]

static func stumpff_c2(z: float) -> float:
	return OrbitalMechanics.stumpff_c2(z)

static func stumpff_c3(z: float) -> float:
	return OrbitalMechanics.stumpff_c3(z)

## Propagates orbital state (r0, v0) by dt seconds under standard gravitational parameter mu.
## Returns Array [r1: DVec3, v1: DVec3].
static func propagate(r0: DVec3, v0: DVec3, dt: float, mu: float = OrbitalMechanics.DEFAULT_MU) -> Array:
	return OrbitalMechanics.propagate_universal(r0, v0, dt, mu)

static func create_state(r: DVec3, v: DVec3, mu: float = OrbitalMechanics.DEFAULT_MU, dominant_body: StringName = &"Earth") -> RailsState:
	return RailsState.new(r, v, mu, dominant_body)
