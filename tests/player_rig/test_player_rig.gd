extends "res://tests/test_case.gd"

const PlayerRigScript = preload("res://game/player/player_rig.gd")
const OnFootRigScript = preload("res://game/player/on_foot_rig.gd")

class MockShip extends RigidBody3D:
	var is_landed: bool = false
	var current_throttle: float = 0.5
	var control_pitch: float = 0.2
	var control_yaw: float = 0.1
	var control_roll: float = 0.0

class MockSurvival extends Node:
	var is_inside_ship: bool = true

func test_player_rig_initial_mode() -> void:
	var rig = PlayerRigScript.new()
	assert_eq(rig.get_current_mode(), PlayerRigScript.PlayerMode.SHIP, "Default mode is SHIP")
	rig.free()

func test_player_rig_eva_blocked_in_flight() -> void:
	var rig = PlayerRigScript.new()
	var ship = MockShip.new()
	ship.is_landed = false
	ship.linear_velocity = Vector3(250.0, 0, 0)
	rig.set_ship(ship)
	
	assert_false(rig.can_exit_ship(), "Cannot exit ship while in flight")
	var success = rig.exit_ship()
	assert_false(success, "exit_ship fails when flying")
	assert_eq(rig.get_current_mode(), PlayerRigScript.PlayerMode.SHIP, "Mode stays SHIP")
	
	rig.free()
	ship.free()

func test_player_rig_eva_allowed_when_landed() -> void:
	var rig = PlayerRigScript.new()
	var ship = MockShip.new()
	ship.is_landed = true
	ship.linear_velocity = Vector3.ZERO
	rig.set_ship(ship)
	
	var on_foot = OnFootRigScript.new()
	rig.set_on_foot_rig(on_foot)
	rig.add_child(on_foot)
	
	assert_true(rig.can_exit_ship(), "Can exit ship when landed")
	var success = rig.exit_ship()
	assert_true(success, "exit_ship succeeds when landed")
	assert_eq(rig.get_current_mode(), PlayerRigScript.PlayerMode.WALK, "Mode transitions to WALK")
	assert_eq(ship.current_throttle, 0.0, "Ship throttle neutralized on EVA")
	assert_true(on_foot.visible, "OnFootRig is visible after exit")
	
	rig.free()
	ship.free()

func test_player_rig_hatch_position_and_reentry() -> void:
	var rig = PlayerRigScript.new()
	var ship = MockShip.new()
	ship.position = Vector3(100.0, 20.0, 100.0)
	rig.set_ship(ship)
	
	var hatch_pos = rig.get_hatch_position()
	# Expect hatch offset on port side (-3.5 on X relative to ship)
	assert_almost_eq(hatch_pos.distance_to(ship.position), 3.5, 0.01, "Hatch offset is approx 3.5m from ship")
	
	var on_foot = OnFootRigScript.new()
	rig.set_on_foot_rig(on_foot)
	rig.add_child(on_foot)
	rig.exit_ship(true)
	
	on_foot.position = hatch_pos + Vector3(1.0, 0, 0)
	assert_true(rig.is_near_hatch(), "Player is near hatch")
	
	var reentered = rig.enter_ship()
	assert_true(reentered, "Reentering ship succeeds")
	assert_eq(rig.get_current_mode(), PlayerRigScript.PlayerMode.SHIP, "Mode transitions back to SHIP")
	assert_false(on_foot.visible, "OnFootRig hidden after boarding ship")
	
	rig.free()
	ship.free()
