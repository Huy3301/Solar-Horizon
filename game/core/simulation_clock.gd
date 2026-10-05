extends Node

const RailsPropagator = preload("res://game/universe/rails_propagator.gd")

signal warp_changed(factor: int, on_rails: bool)
signal time_jumped
signal rails_stepped(dt: float)

const WARP_LEVELS = [1, 2, 4, 10, 50, 100, 1000, 10000, 100000]

var sim_time_s: float = 0.0
var warp_index: int = 0
var physics_warp_allowed: bool = true
var on_rails: bool = false

var _registered_vessels: Array[Dictionary] = []
var _registered_states: Array[RefCounted] = []
var _rails_callbacks: Array[Callable] = []

func _exit_tree() -> void:
	Engine.time_scale = 1.0

func is_on_rails() -> bool:
	return WARP_LEVELS[warp_index] > 4

func get_warp_factor() -> int:
	return WARP_LEVELS[warp_index]

func get_current_warp() -> int:
	return WARP_LEVELS[warp_index]

func set_warp_index(idx: int) -> void:
	if idx < 0:
		idx = 0
	if idx >= WARP_LEVELS.size():
		idx = WARP_LEVELS.size() - 1
		
	var prev_on_rails = on_rails
	warp_index = idx
	var factor = WARP_LEVELS[warp_index]
	on_rails = (factor > 4)
	physics_warp_allowed = not on_rails
	
	if on_rails:
		Engine.time_scale = 1.0
		if not prev_on_rails:
			_enter_rails_warp()
	else:
		Engine.time_scale = float(factor)
		if prev_on_rails:
			_exit_rails_warp()
			
	warp_changed.emit(factor, on_rails)

func request_warp(idx: int, conditions: Dictionary = {}) -> bool:
	if idx > 0 and not can_warp(conditions):
		return false
	set_warp_index(idx)
	return true

func can_warp(conditions: Dictionary) -> bool:
	# Refuse warp if thrust is active
	if conditions.get("thrust", false) == true or conditions.get("is_thrusting", false) == true:
		return false
	if conditions.get("throttle", 0.0) > 0.001:
		return false
		
	# Direct atmosphere flag
	if conditions.get("atmosphere", false) == true or conditions.get("in_atmosphere", false) == true:
		return false
		
	# Determine atmospheric threshold limit
	var scale_height = conditions.get("scale_height", 0.0)
	var atm_limit = 150_000.0
	if scale_height > 0.0:
		atm_limit = 12.0 * float(scale_height)
	elif conditions.has("atmosphere_limit"):
		atm_limit = float(conditions["atmosphere_limit"])
	elif conditions.has("atmosphere_depth"):
		atm_limit = float(conditions["atmosphere_depth"])
		
	# Check altitude
	for k in ["altitude", "alt", "altitude_agl", "altitude_asl"]:
		if conditions.has(k):
			var alt = float(conditions[k])
			if alt < atm_limit:
				return false
			break
			
	# Check periapsis
	for k in ["periapsis_alt", "periapsis_altitude", "pe_alt"]:
		if conditions.has(k):
			var pe = float(conditions[k])
			if pe < atm_limit:
				return false
			break
			
	if conditions.has("orbit"):
		var orb = conditions["orbit"]
		if orb != null and "periapsis_alt" in orb:
			if float(orb.periapsis_alt) < atm_limit:
				return false
				
	if conditions.has("periapsis_radius") and conditions.has("body_radius"):
		var pe_alt = float(conditions["periapsis_radius"]) - float(conditions["body_radius"])
		if pe_alt < atm_limit:
			return false
			
	return true

func advance(delta: float) -> void:
	var factor = WARP_LEVELS[warp_index]
	var dt_step = float(delta) * float(factor)
	sim_time_s += dt_step
	
	if is_on_rails():
		step_rails(dt_step)

func _physics_process(delta: float) -> void:
	advance(delta)

# Rails Registration & Management
func register_vessel(vessel: Node, dominant_body: StringName = &"Earth", mu: float = -1.0) -> void:
	for entry in _registered_vessels:
		if entry.get("vessel") == vessel:
			entry["dominant_body"] = dominant_body
			if mu > 0.0:
				entry["mu"] = mu
			return
			
	var entry = {
		"vessel": vessel,
		"dominant_body": dominant_body,
		"mu": mu,
		"rel_pos": DVec3.zero(),
		"rel_vel": DVec3.zero(),
		"is_frozen": false
	}
	_registered_vessels.append(entry)
	
	if is_on_rails():
		_freeze_vessel_entry(entry)

func unregister_vessel(vessel: Node) -> void:
	for i in range(_registered_vessels.size() - 1, -1, -1):
		var entry = _registered_vessels[i]
		if entry.get("vessel") == vessel:
			if entry.get("is_frozen", false):
				_unfreeze_vessel_entry(entry)
			_registered_vessels.remove_at(i)

func register_state(state: RefCounted) -> void:
	if not _registered_states.has(state):
		_registered_states.append(state)

func unregister_state(state: RefCounted) -> void:
	_registered_states.erase(state)

func register_rails_callback(cb: Callable) -> void:
	if not _rails_callbacks.has(cb):
		_rails_callbacks.append(cb)

func unregister_rails_callback(cb: Callable) -> void:
	_rails_callbacks.erase(cb)

func step_rails(dt: float) -> void:
	# 1. Step registered callbacks
	for cb in _rails_callbacks:
		if cb.is_valid():
			cb.call(dt)
			
	# 2. Step registered states
	for state in _registered_states:
		if state.has_method("step"):
			state.call("step", dt)
		elif "r" in state and "v" in state:
			var s_mu = state.get("mu") if "mu" in state else OrbitalMechanics.DEFAULT_MU
			var next = RailsPropagator.propagate(state.r, state.v, dt, s_mu)
			state.r = next[0]
			state.v = next[1]
			
	# 3. Step registered vessels
	for i in range(_registered_vessels.size() - 1, -1, -1):
		var entry = _registered_vessels[i]
		var vessel = entry.get("vessel") as Node
		if vessel == null or not is_instance_valid(vessel):
			_registered_vessels.remove_at(i)
			continue
			
		var r0 = entry.get("rel_pos") as DVec3
		var v0 = entry.get("rel_vel") as DVec3
		var mu = entry.get("mu", OrbitalMechanics.DEFAULT_MU) as float
		if mu <= 0.0:
			mu = OrbitalMechanics.DEFAULT_MU
		var dominant_body = entry.get("dominant_body", &"Earth") as StringName
		
		var next_state = RailsPropagator.propagate(r0, v0, dt, mu)
		var r1 = next_state[0] as DVec3
		var v1 = next_state[1] as DVec3
		entry["rel_pos"] = r1
		entry["rel_vel"] = v1
		
		var body_pos = _get_body_position(dominant_body, sim_time_s)
		var new_world_pos = body_pos.add(r1)
		
		# Auto-drop warp if dominant body changed (SOI transition)
		var new_dominant = _get_dominant_body(new_world_pos, sim_time_s)
		if new_dominant != &"" and new_dominant != dominant_body:
			set_warp_index(0)
			return
			
		if vessel is Node3D:
			(vessel as Node3D).global_position = new_world_pos.to_vector3()
			if vessel.has_method("reset_physics_interpolation"):
				(vessel as Node3D).reset_physics_interpolation()
				
	rails_stepped.emit(dt)

func _enter_rails_warp() -> void:
	for entry in _registered_vessels:
		_freeze_vessel_entry(entry)

func _exit_rails_warp() -> void:
	for entry in _registered_vessels:
		_unfreeze_vessel_entry(entry)

func _freeze_vessel_entry(entry: Dictionary) -> void:
	var vessel = entry.get("vessel") as Node
	if vessel == null or not is_instance_valid(vessel):
		return
		
	var dominant_body: StringName = entry.get("dominant_body", &"Earth")
	var mu: float = entry.get("mu", -1.0)
	if mu <= 0.0:
		mu = _get_body_mu(dominant_body)
		entry["mu"] = mu
		
	var body_pos = _get_body_position(dominant_body, sim_time_s)
	var body_vel = _get_body_velocity(dominant_body, sim_time_s)
	
	var world_pos = DVec3.from_vector3((vessel as Node3D).global_position if vessel is Node3D else Vector3.ZERO)
	var world_vel = DVec3.zero()
	if vessel is RigidBody3D:
		var rb = vessel as RigidBody3D
		world_vel = DVec3.from_vector3(rb.linear_velocity)
		rb.freeze = true
		rb.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
		entry["is_frozen"] = true
	elif vessel.has_method("get_linear_velocity"):
		world_vel = DVec3.from_vector3(vessel.call("get_linear_velocity"))
		
	entry["rel_pos"] = world_pos.sub(body_pos)
	entry["rel_vel"] = world_vel.sub(body_vel)

func _unfreeze_vessel_entry(entry: Dictionary) -> void:
	var vessel = entry.get("vessel") as Node
	if vessel == null or not is_instance_valid(vessel):
		return
		
	var dominant_body: StringName = entry.get("dominant_body", &"Earth")
	var body_vel = _get_body_velocity(dominant_body, sim_time_s)
	var rel_vel = entry.get("rel_vel", DVec3.zero()) as DVec3
	var world_vel = body_vel.add(rel_vel)
	
	if vessel is RigidBody3D:
		var rb = vessel as RigidBody3D
		rb.freeze = false
		rb.linear_velocity = world_vel.to_vector3()
		if rb.has_method("reset_physics_interpolation"):
			rb.reset_physics_interpolation()
	elif vessel.has_method("set_linear_velocity"):
		vessel.call("set_linear_velocity", world_vel.to_vector3())
		
	entry["is_frozen"] = false

func _get_body_position(id: StringName, t: float) -> DVec3:
	return GravityService.body_position(id, t)

func _get_body_velocity(id: StringName, t: float) -> DVec3:
	return GravityService.body_velocity(id, t)

func _get_body_mu(id: StringName) -> float:
	var m = GravityService.get_body_scaled_mu(id)
	if m > 0.0:
		return m
	return OrbitalMechanics.DEFAULT_MU

func _get_dominant_body(pos: DVec3, t: float) -> StringName:
	return GravityService.dominant_body(pos, t)
