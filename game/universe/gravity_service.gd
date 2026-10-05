class_name GravityService extends RefCounted

static var _cached_time: float = -1.0
static var _pos_cache: Dictionary = {}
static var _vel_cache: Dictionary = {}

static func _invalidate_if_needed(t: float) -> void:
	if _cached_time != t:
		_cached_time = t
		_pos_cache.clear()
		_vel_cache.clear()

static func _calc_state(id: StringName, t: float) -> void:
	if _pos_cache.has(id):
		return
		
	var def = BodyRegistry.get_body(id)
	if def == null:
		_pos_cache[id] = DVec3.zero()
		_vel_cache[id] = DVec3.zero()
		return
		
	if def.parent_id == "":
		_pos_cache[id] = DVec3.zero()
		_vel_cache[id] = DVec3.zero()
		return
		
	_calc_state(def.parent_id, t)
	var parent_pos = _pos_cache[def.parent_id]
	var parent_vel = _vel_cache[def.parent_id]
	
	var parent_def = BodyRegistry.get_body(def.parent_id)
	var real_mu = parent_def.mu_m3_s2 if parent_def else 1.0
	
	var scale = GameScale.get_instance()
	var scaled_a = scale.scaled_semi_major_axis(def.semi_major_axis_m)
	var scaled_mu = scale.scaled_mu(real_mu, parent_def.radius_m if parent_def else 1.0)
	
	var elements = OrbitalMechanics.OrbitElements.new()
	elements.semi_major_axis = scaled_a
	elements.eccentricity = def.eccentricity
	elements.inclination_rad = deg_to_rad(def.inclination_deg)
	elements.lan_rad = deg_to_rad(def.longitude_ascending_node_deg)
	elements.arg_periapsis_rad = deg_to_rad(def.argument_periapsis_deg)
	elements.mean_anomaly_rad = deg_to_rad(def.mean_anomaly_at_epoch_deg)
	elements.epoch = 0.0 # From J2000
	
	if scaled_a > 0:
		elements.period_seconds = 2.0 * PI * sqrt(pow(scaled_a, 3.0) / scaled_mu)
		
	var state = OrbitalMechanics.state_from_elements(elements, scaled_mu, t)
	var local_pos = state[0] as DVec3
	var local_vel = state[1] as DVec3
	
	# state_from_elements already returns coordinates in Godot frame
	_pos_cache[id] = parent_pos.add(local_pos)
	_vel_cache[id] = parent_vel.add(local_vel)

static func body_position(id: StringName, t: float) -> DVec3:
	_invalidate_if_needed(t)
	_calc_state(id, t)
	return _pos_cache[id]

static func body_velocity(id: StringName, t: float) -> DVec3:
	_invalidate_if_needed(t)
	_calc_state(id, t)
	return _vel_cache[id]

static func get_body_scaled_mu(id: StringName) -> float:
	var def = BodyRegistry.get_body(id)
	if def == null:
		return 0.0
	var scale = GameScale.get_instance()
	return scale.scaled_mu(def.mu_m3_s2, def.radius_m)

static func get_body_scaled_radius(id: StringName) -> float:
	var def = BodyRegistry.get_body(id)
	if def == null:
		return 0.0
	var scale = GameScale.get_instance()
	return scale.scaled_radius(def.radius_m)

static func get_soi_radius(child_id: StringName) -> float:
	var child_def = BodyRegistry.get_body(child_id)
	if child_def == null or child_def.parent_id == "":
		return INF
	var parent_def = BodyRegistry.get_body(child_def.parent_id)
	if parent_def == null:
		return INF
	var scale = GameScale.get_instance()
	var scaled_a = scale.scaled_semi_major_axis(child_def.semi_major_axis_m)
	var child_scaled_mu = scale.scaled_mu(child_def.mu_m3_s2, child_def.radius_m)
	var parent_scaled_mu = scale.scaled_mu(parent_def.mu_m3_s2, parent_def.radius_m)
	if parent_scaled_mu <= 0.0:
		return INF
	return scale.scaled_soi(scaled_a, child_scaled_mu / parent_scaled_mu)

static func dominant_body(pos: DVec3, t: float) -> StringName:
	var root = BodyRegistry.get_root()
	return _find_dominant_recursive(root, pos, t)

static func _find_dominant_recursive(current_id: StringName, pos: DVec3, t: float) -> StringName:
	var children = BodyRegistry.get_children(current_id)
	var current_pos = body_position(current_id, t)
	
	var scale = GameScale.get_instance()
	var current_def = BodyRegistry.get_body(current_id)
	var current_scaled_mu = scale.scaled_mu(current_def.mu_m3_s2, current_def.radius_m) if current_def else 1.0
	
	for child_id in children:
		var child_def = BodyRegistry.get_body(child_id)
		if child_def == null:
			continue
		var child_pos = body_position(child_id, t)
		var dist = pos.distance_to(child_pos)
		
		var scaled_a = scale.scaled_semi_major_axis(child_def.semi_major_axis_m)
		var child_scaled_mu = scale.scaled_mu(child_def.mu_m3_s2, child_def.radius_m)
		var soi = scale.scaled_soi(scaled_a, child_scaled_mu / current_scaled_mu)
		
		if dist < soi:
			return _find_dominant_recursive(child_id, pos, t)
			
	return current_id

static func gravity_accel(pos: DVec3, t: float, include_perturbations: bool = false) -> DVec3:
	var dom_id = dominant_body(pos, t)
	var acc = DVec3.zero()
	
	var dom_def = BodyRegistry.get_body(dom_id)
	if dom_def == null:
		return acc
		
	var dom_pos = body_position(dom_id, t)
	var scale = GameScale.get_instance()
	var dom_mu = scale.scaled_mu(dom_def.mu_m3_s2, dom_def.radius_m)
	
	# Primary dominant-body 2-body gravitational acceleration
	var r_vec = dom_pos.sub(pos)
	var r_sq = r_vec.length_squared()
	if r_sq > 1e-6:
		acc.add_in_place(r_vec.normalized().mul_scalar(dom_mu / r_sq))
		
	# Optional third-body tidal perturbations (relative to dominant body non-inertial frame)
	if include_perturbations:
		var parent_id = dom_def.parent_id
		if parent_id != "":
			var parent_def = BodyRegistry.get_body(parent_id)
			if parent_def != null:
				var parent_pos = body_position(parent_id, t)
				var parent_mu = scale.scaled_mu(parent_def.mu_m3_s2, parent_def.radius_m)
				
				# Tidal acceleration = g(pos) - g(dominant_body_pos)
				var d_pos = parent_pos.sub(pos)
				var d_dom = parent_pos.sub(dom_pos)
				var d_pos_len = d_pos.length()
				var d_dom_len = d_dom.length()
				if d_pos_len > 1.0 and d_dom_len > 1.0:
					var a_ship = d_pos.mul_scalar(parent_mu / pow(d_pos_len, 3.0))
					var a_dom = d_dom.mul_scalar(parent_mu / pow(d_dom_len, 3.0))
					acc.add_in_place(a_ship.sub(a_dom))
					
	return acc
