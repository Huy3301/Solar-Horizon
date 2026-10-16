class_name TutorialDirector extends Node

## Step-based onboarding and tutorial director covering the full Earth-to-Moon loop:
## Adelaide launch -> Low Earth Orbit -> Moon landing -> EVA -> Scan -> Return to ship.
## Fully data-driven with failure handling and Adelaide Base respawn recovery.

signal step_changed(step_index: int, step_data: Dictionary)
signal step_completed(step_index: int, step_id: String)
signal tutorial_completed()
signal mission_failed(reason: String)
signal respawned_at_base()

@export var auto_start: bool = true
@export var current_step_index: int = 0
@export var adelaide_base_pos: Vector3 = Vector3(0.0, 50.0, 0.0)

var ship: Node = null
var player_rig: Node = null
var game_ui: Node = null
var scanner_system: Node = null

var steps: Array[Dictionary] = []
var is_active: bool = true

func _ready() -> void:
	_init_steps()
	_resolve_scene_nodes()
	if auto_start:
		start_tutorial()

## "[Up]" / "[Shift]" ... the first keyboard binding of an action (falls back to the action name).
static func key_label(action: StringName) -> String:
	if InputMap.has_action(action):
		for ev in InputMap.action_get_events(action):
			if ev is InputEventKey:
				var k: InputEventKey = ev
				var code: Key = k.physical_keycode if k.physical_keycode != KEY_NONE else k.keycode
				return "[%s]" % OS.get_keycode_string(code)
	return "[%s]" % String(action)

func _init_steps() -> void:
	var k_thr: String = key_label(&"throttle_up")
	var k_pitch: String = key_label(&"pitch_up")
	var k_boost: String = key_label(&"boost")
	var k_pulse: String = key_label(&"pulse_drive")
	var k_gear: String = key_label(&"toggle_gear")
	var k_map: String = key_label(&"toggle_map")
	steps = [
		{
			"id": "adelaide_launch",
			"title": "MISSION STEP 1: LIFT OFF",
			"instruction": "Hold Throttle %s to lift off, pitch up %s and climb out of the atmosphere. Hold Boost %s to climb faster." % [k_thr, k_pitch, k_boost],
			"hint": "Reach 15 km altitude. The sky darkens as you leave the atmosphere.",
			"check": _check_launch
		},
		{
			"id": "engage_pulse",
			"title": "MISSION STEP 2: PULSE DRIVE",
			"instruction": "Point the nose at the Moon and engage the Pulse Drive %s (needs 60 km clear of any planet). Open the map %s to find it." % [k_pulse, k_map],
			"hint": "The pulse drive brakes by itself when you approach a planet.",
			"check": _check_pulse
		},
		{
			"id": "moon_landing",
			"title": "MISSION STEP 3: LUNAR TOUCHDOWN",
			"instruction": "The pulse drive drops you out above the Moon. Descend, deploy landing gear %s and touch down gently." % k_gear,
			"hint": "Keep descent speed below 5 m/s upon lunar contact.",
			"check": _check_moon_landing
		},
		{
			"id": "eva_exit",
			"title": "MISSION STEP 4: LUNAR EVA",
			"instruction": "The vessel is secured on the lunar surface. Interact with the hatch [F] to begin EVA exploration.",
			"hint": "Approach the port crew airlock hatch to exit.",
			"check": _check_eva_exit
		},
		{
			"id": "scan_sample",
			"title": "MISSION STEP 5: REGOLITH ANALYSIS",
			"instruction": "Activate your multi-spectral scanner [C] to analyze lunar surface geology.",
			"hint": "Press [C] while standing on the lunar surface to complete the survey.",
			"check": _check_scan_sample
		},
		{
			"id": "return_to_ship",
			"title": "MISSION STEP 6: RETURN TO VESSEL",
			"instruction": "Survey complete. Return to the vessel's hatch and interact [F] to board the spacecraft.",
			"hint": "Approach the hatch until '[F] Board Ship' is displayed.",
			"check": _check_return_to_ship
		}
	]

func _resolve_scene_nodes() -> void:
	var tree = get_tree()
	if not tree:
		return
		
	if ship == null:
		ship = tree.get_first_node_in_group("ship")
		if ship == null:
			ship = tree.root.find_child("Ship", true, false)
			
	if player_rig == null:
		player_rig = tree.get_first_node_in_group("player_rig")
		if player_rig == null:
			player_rig = tree.root.find_child("PlayerRig", true, false)
			
	if game_ui == null:
		game_ui = tree.get_first_node_in_group("game_ui")
		if game_ui == null:
			game_ui = tree.root.find_child("GameUI", true, false)
			
	if scanner_system == null:
		scanner_system = tree.get_first_node_in_group("scanner")
		if scanner_system == null:
			scanner_system = tree.root.find_child("ScannerSystem", true, false)
			
	_connect_signals()

func _connect_signals() -> void:
	if ship and ship.has_signal("flight_data_updated"):
		if not ship.flight_data_updated.is_connected(_on_flight_data_updated):
			ship.flight_data_updated.connect(_on_flight_data_updated)
			
	if player_rig:
		if player_rig.has_signal("mode_changed") and not player_rig.mode_changed.is_connected(_on_player_mode_changed):
			player_rig.mode_changed.connect(_on_player_mode_changed)
		if player_rig.has_signal("exited_ship") and not player_rig.exited_ship.is_connected(_on_exited_ship):
			player_rig.exited_ship.connect(_on_exited_ship)
		if player_rig.has_signal("entered_ship") and not player_rig.entered_ship.is_connected(_on_entered_ship):
			player_rig.entered_ship.connect(_on_entered_ship)
			
	if scanner_system and scanner_system.has_signal("scan_completed"):
		if not scanner_system.scan_completed.is_connected(_on_scan_completed):
			scanner_system.scan_completed.connect(_on_scan_completed)

func start_tutorial() -> void:
	current_step_index = 0
	is_active = true
	_notify_current_step()

func _notify_current_step() -> void:
	if current_step_index >= 0 and current_step_index < steps.size():
		var data = steps[current_step_index]
		step_changed.emit(current_step_index, data)
		if game_ui and game_ui.has_method("set_tutorial_prompt"):
			game_ui.set_tutorial_prompt(data.get("title", ""), data.get("instruction", ""), true)
	elif current_step_index >= steps.size():
		tutorial_completed.emit()
		if game_ui and game_ui.has_method("set_tutorial_prompt"):
			game_ui.set_tutorial_prompt("MISSION ACCOMPLISHED", "All primary mission milestones completed successfully!", true)

func advance_step() -> void:
	if current_step_index < steps.size():
		var prev_id = steps[current_step_index].get("id", "")
		step_completed.emit(current_step_index, prev_id)
		current_step_index += 1
		_notify_current_step()

func get_current_step() -> Dictionary:
	if current_step_index >= 0 and current_step_index < steps.size():
		return steps[current_step_index]
	return {}

func get_current_step_index() -> int:
	return current_step_index

func _process(_delta: float) -> void:
	if not is_active or current_step_index >= steps.size():
		return
		
	var step = steps[current_step_index]
	if step.has("check") and step.check is Callable:
		if step.check.call():
			advance_step()

func _on_flight_data_updated(data: Dictionary) -> void:
	if not is_active:
		return
		
	# Check ship crash failure condition
	if data.get("is_crashed", false):
		fail_mission("Ship sustained critical structural damage during flight.")
		return
		
	# Check current step condition
	if current_step_index >= 0 and current_step_index < steps.size():
		var step = steps[current_step_index]
		if step.has("check") and step.check is Callable:
			if step.check.call():
				advance_step()

func _on_player_mode_changed(_mode: int) -> void:
	if not is_active:
		return
	if current_step_index >= 0 and current_step_index < steps.size():
		var step = steps[current_step_index]
		if step.has("check") and step.check is Callable:
			if step.check.call():
				advance_step()

func _on_exited_ship(_ship_node: Node, _spawn_pos: Vector3) -> void:
	if current_step_index == 3: # eva_exit
		advance_step()

func _on_scan_completed(_targets: Variant = null) -> void:
	if current_step_index == 4: # scan_sample
		advance_step()

func _on_entered_ship(_ship_node: Node) -> void:
	if current_step_index == 5: # return_to_ship
		advance_step()

# --- Step Verification Checks ---

func _check_launch() -> bool:
	if not ship or not ("telemetry_data" in ship):
		return false
	return float(ship.telemetry_data.get("altitude_agl_m", 0.0)) > 15000.0

func _check_pulse() -> bool:
	if not ship:
		return false
	if "pulse_drive_active" in ship and ship.pulse_drive_active:
		return true
	return "telemetry_data" in ship and float(ship.telemetry_data.get("speed_ms", 0.0)) > 7200.0

## Landed ON THE MOON (landing on Earth must not complete the lunar step).
func _check_moon_landing() -> bool:
	if not ship or not ("is_landed" in ship) or not ship.is_landed:
		return false
	return _dominant_body_name() == "Moon"

func _dominant_body_name() -> String:
	var origin = get_node_or_null("/root/OriginService")
	var clock = get_node_or_null("/root/SimulationClock")
	if not origin or not clock or not ship:
		return ""
	var su: DVec3 = origin.local_to_universe(ship.global_position).offset
	return String(GravityService.dominant_body(su, clock.sim_time_s))

func _check_eva_exit() -> bool:
	if player_rig and "current_mode" in player_rig:
		# PlayerMode.WALK == 1
		return int(player_rig.current_mode) == 1
	return false

func _check_scan_sample() -> bool:
	# Triggered via scan signal or input
	return false

func _check_return_to_ship() -> bool:
	if player_rig and "current_mode" in player_rig:
		# PlayerMode.SHIP == 0
		return int(player_rig.current_mode) == 0
	return false

# --- Failure & Respawn System ---

func fail_mission(reason: String) -> void:
	mission_failed.emit(reason)
	if game_ui and game_ui.has_method("set_tutorial_prompt"):
		game_ui.set_tutorial_prompt("MISSION FAILED", "%s Respawning at Adelaide Base..." % reason, true)
	respawn_at_adelaide_base()

func respawn_at_adelaide_base() -> void:
	# Reset ship position and physics state
	if is_instance_valid(ship):
		if ship is RigidBody3D:
			var rb = ship as RigidBody3D
			rb.linear_velocity = Vector3.ZERO
			rb.angular_velocity = Vector3.ZERO
			if rb.is_inside_tree():
				rb.global_position = adelaide_base_pos
				rb.global_transform.basis = Basis.IDENTITY
			else:
				rb.position = adelaide_base_pos
				rb.transform.basis = Basis.IDENTITY
		elif ship is Node3D:
			if (ship as Node3D).is_inside_tree():
				(ship as Node3D).global_position = adelaide_base_pos
			else:
				(ship as Node3D).position = adelaide_base_pos
			
		if "is_crashed" in ship:
			ship.is_crashed = false
		if "is_landed" in ship:
			ship.is_landed = true
		if "current_throttle" in ship:
			ship.current_throttle = 0.0
		if "landing_gear_deployed" in ship:
			ship.landing_gear_deployed = true
			
	# Reset PlayerRig to SHIP mode
	if is_instance_valid(player_rig):
		if player_rig.has_method("enter_ship"):
			player_rig.enter_ship(ship)
			
	# Reset tutorial state
	current_step_index = 0
	_notify_current_step()
	respawned_at_base.emit()
