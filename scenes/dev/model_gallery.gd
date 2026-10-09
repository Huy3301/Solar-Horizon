extends Node3D

## Spacecraft Model Gallery (Showroom)
## Allows inspection of spacecraft 3D models (Hero Orbiter, Lunar Lander)
## with lighting, turntable rotation, and animation controls.

@onready var orbiter_node: Node3D = $Showroom/OrbiterInstance
@onready var lander_node: Node3D = $Showroom/LanderInstance
@onready var camera_pivot: Node3D = $CameraPivot
@onready var camera: Camera3D = $CameraPivot/Camera3D
@onready var info_label: Label = $CanvasLayer/InfoLabel

var target_pivot_pos: Vector3 = Vector3(0, 1.5, 0)
var camera_distance: float = 18.0
var turntable_speed: float = 0.25
var auto_rotate: bool = true
var mouse_dragging: bool = false
var last_mouse_pos: Vector2 = Vector2.ZERO

var orbiter_anim_player: AnimationPlayer = null
var gear_deployed: bool = true

func _ready() -> void:
	_ensure_nodes()
	if orbiter_node:
		var col = orbiter_node.get_node_or_null("COL_hull")
		if col:
			col.visible = false
		if orbiter_anim_player and orbiter_anim_player.has_animation("gear_deploy"):
			orbiter_anim_player.play("gear_deploy")
			orbiter_anim_player.seek(1.0, true) # Start with gear deployed
	if lander_node:
		var col_l = lander_node.get_node_or_null("COL_hull")
		if col_l:
			col_l.visible = false

	_update_hud()

func _ensure_nodes() -> void:
	if not orbiter_node:
		orbiter_node = get_node_or_null("Showroom/OrbiterInstance")
	if not lander_node:
		lander_node = get_node_or_null("Showroom/LanderInstance")
	if not camera_pivot:
		camera_pivot = get_node_or_null("CameraPivot")
	if not camera and camera_pivot:
		camera = camera_pivot.get_node_or_null("Camera3D")
	if not info_label:
		info_label = get_node_or_null("CanvasLayer/InfoLabel")
	if not orbiter_anim_player and orbiter_node:
		orbiter_anim_player = orbiter_node.get_node_or_null("AnimationPlayer")

func _process(delta: float) -> void:
	_ensure_nodes()
	if camera_pivot:
		if auto_rotate and not mouse_dragging:
			camera_pivot.rotate_y(turntable_speed * delta)
		camera_pivot.position = camera_pivot.position.lerp(target_pivot_pos, delta * 5.0)
	if camera:
		camera.position.z = lerpf(camera.position.z, camera_distance, delta * 5.0)

func _unhandled_input(event: InputEvent) -> void:
	_ensure_nodes()
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_1:
			# Focus Orbiter
			var orb_pos = orbiter_node.position if orbiter_node else Vector3(0, 0.5, 0)
			target_pivot_pos = orb_pos + Vector3(0, 1.5, 0)
			camera_distance = 18.0
			_update_hud("Focused: Spacecraft Orbiter (14.2m)")
		elif event.keycode == KEY_2:
			# Focus Lunar Lander
			var lnd_pos = lander_node.position if lander_node else Vector3(14, 0, 0)
			target_pivot_pos = lnd_pos + Vector3(0, 2.0, 0)
			camera_distance = 12.0
			_update_hud("Focused: Lunar Lander (Artemis/Apollo Modular)")
		elif event.keycode == KEY_SPACE:
			auto_rotate = not auto_rotate
			_update_hud("Turntable Auto-Rotate: %s" % ("ON" if auto_rotate else "OFF"))
		elif event.keycode == KEY_G:
			# Toggle gear animation on Orbiter
			if orbiter_anim_player and orbiter_anim_player.has_animation("gear_deploy"):
				gear_deployed = not gear_deployed
				if gear_deployed:
					orbiter_anim_player.play("gear_deploy")
				else:
					orbiter_anim_player.play_backwards("gear_deploy")
				_update_hud("Orbiter Landing Gear: %s" % ("DEPLOYING" if gear_deployed else "RETRACTING"))

	elif event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			mouse_dragging = event.pressed
			last_mouse_pos = event.position
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP:
			camera_distance = clampf(camera_distance - 1.5, 5.0, 40.0)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			camera_distance = clampf(camera_distance + 1.5, 5.0, 40.0)

	elif event is InputEventMouseMotion and mouse_dragging:
		var delta_mouse = event.position - last_mouse_pos
		last_mouse_pos = event.position
		camera_pivot.rotate_y(-delta_mouse.x * 0.006)
		var pitch = clampf(camera_pivot.rotation.x - delta_mouse.y * 0.006, -1.2, 1.2)
		camera_pivot.rotation.x = pitch

func _update_hud(status_msg: String = "") -> void:
	if not info_label:
		return
	var txt = "=== SOLAR HORIZON — SPACECRAFT SHOWROOM ===\n"
	txt += "[1] Focus Orbiter   [2] Focus Lunar Lander   [G] Toggle Gear\n"
	txt += "[Space] Toggle Turntable   [Mouse Drag] Orbit   [Wheel] Zoom\n"
	if status_msg != "":
		txt += "\nStatus: " + status_msg
	info_label.text = txt
