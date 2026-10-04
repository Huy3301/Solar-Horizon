class_name GameScale extends Resource

@export var radius_scale: float = 0.1
@export var distance_scale: float = 0.01
@export var rotation_time_scale: float = 0.05
@export var preserve_surface_gravity: bool = true

static var _instance: GameScale = null

static func get_instance() -> GameScale:
	if _instance == null:
		if ResourceLoader.exists("res://game/core/game_scale.tres"):
			_instance = ResourceLoader.load("res://game/core/game_scale.tres") as GameScale
		if _instance == null:
			_instance = GameScale.new()
	return _instance

func scaled_radius(real_r: float) -> float:
	return real_r * radius_scale

func scaled_semi_major_axis(real_a: float) -> float:
	return real_a * distance_scale

func scaled_mu(real_mu: float, real_r: float) -> float:
	# If we preserve surface gravity (g = mu / r^2), then
	# mu_scaled / r_scaled^2 = real_mu / real_r^2
	# mu_scaled = real_mu * (r_scaled / real_r)^2
	# mu_scaled = real_mu * radius_scale^2
	# If distance and mu are both scaled differently? Wait, the prompt says:
	# (if preserve_surface_gravity: mu*radius_scale^2)
	# Document why: with a and mu both scaled by 0.01, all orbital periods scale uniformly by 0.01
	if preserve_surface_gravity:
		return real_mu * radius_scale * radius_scale
	else:
		return real_mu * distance_scale * distance_scale

func scaled_rotation_period(real_s: float) -> float:
	return real_s * rotation_time_scale

func scaled_soi(real_a_scaled: float, mu_ratio: float) -> float:
	# Laplace formula: r_soi = a * (m / M)^(2/5)
	# mu_ratio = m / M = mu_m / mu_M
	return real_a_scaled * pow(mu_ratio, 0.4)
