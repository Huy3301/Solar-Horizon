class_name GameUI extends CanvasLayer

## Master UI orchestrator integrating flight telemetry, suit bars, inventory grid,
## orbit map, pause/settings, interaction prompts, and mobile touch controls.

signal inventory_toggled(is_open: bool)
signal map_toggled(is_open: bool)

@export var player_rig_path: NodePath
@export var ship_path: NodePath

var flight_telemetry: Control = null
var suit_bars: Control = null
var inventory_menu: Control = null
var orbit_map: Control = null
var pause_menu: Control = null
var touch_controls: Control = null
var interaction_prompt: Control = null
var interaction_label: Label = null
var tutorial_banner: Control = null
var tutorial_title: Label = null
var tutorial_label: Label = null

var current_mode: int = 0 # 0 = SHIP, 1 = WALK
var player_rig: Node = null
var ship: Node = null

func _ready() -> void:
	_resolve_nodes()
	_resolve_bindings()
	_update_hud_visibility()

func _resolve_nodes() -> void:
	flight_telemetry = get_node_or_null("FlightTelemetry")
	suit_bars = get_node_or_null("SuitBars")
	inventory_menu = get_node_or_null("InventoryMenu")
	orbit_map = get_node_or_null("OrbitMap")
	pause_menu = get_node_or_null("PauseMenu")
	touch_controls = get_node_or_null("TouchControls")
	interaction_prompt = get_node_or_null("InteractionPrompt")
	interaction_label = get_node_or_null("InteractionPrompt/Label") as Label
	tutorial_banner = get_node_or_null("TutorialBanner")
	tutorial_title = get_node_or_null("TutorialBanner/Margin/VBox/TitleLabel") as Label
	tutorial_label = get_node_or_null("TutorialBanner/Margin/VBox/PromptLabel") as Label

func _resolve_bindings() -> void:
	if not player_rig_path.is_empty():
		var rig_node = get_node_or_null(player_rig_path)
		if rig_node:
			set_player_rig(rig_node)
			
	if not ship_path.is_empty():
		var ship_node = get_node_or_null(ship_path)
		if ship_node:
			set_ship(ship_node)

func set_player_rig(rig: Node) -> void:
	player_rig = rig
	if rig.has_signal("mode_changed"):
		if not rig.mode_changed.is_connected(_on_player_mode_changed):
			rig.mode_changed.connect(_on_player_mode_changed)
	if rig.has_signal("hatch_interaction_possible"):
		if not rig.hatch_interaction_possible.is_connected(set_interaction_prompt):
			rig.hatch_interaction_possible.connect(set_interaction_prompt)
	if "current_mode" in rig:
		set_mode(int(rig.current_mode))

func set_ship(ship_node: Node) -> void:
	ship = ship_node
	if ship_node.has_signal("flight_data_updated"):
		if not ship_node.flight_data_updated.is_connected(_on_flight_data_updated):
			ship_node.flight_data_updated.connect(_on_flight_data_updated)
	if orbit_map and ship_node is Node3D and orbit_map.has_method("set_vessel"):
		orbit_map.set_vessel(ship_node as Node3D)

func set_mode(mode: int) -> void:
	current_mode = mode
	_update_hud_visibility()

func _on_player_mode_changed(new_mode: int) -> void:
	set_mode(new_mode)

func _on_flight_data_updated(data: Dictionary) -> void:
	if flight_telemetry and flight_telemetry.has_method("update_telemetry"):
		flight_telemetry.update_telemetry(data)
	if orbit_map and "orbit" in data and orbit_map.has_method("set_orbit"):
		orbit_map.set_orbit(data.orbit)

func _update_hud_visibility() -> void:
	# Mode 0 = SHIP, Mode 1 = WALK
	if current_mode == 0:
		if flight_telemetry: flight_telemetry.visible = true
		if suit_bars: suit_bars.visible = false
		if touch_controls and touch_controls.has_method("set_flight_mode"):
			touch_controls.set_flight_mode(true)
	else:
		if flight_telemetry: flight_telemetry.visible = false
		if suit_bars: suit_bars.visible = true
		if touch_controls and touch_controls.has_method("set_flight_mode"):
			touch_controls.set_flight_mode(false)

func set_interaction_prompt(is_possible: bool, prompt_text: String = "") -> void:
	if interaction_prompt:
		interaction_prompt.visible = is_possible
	if interaction_label and is_possible:
		interaction_label.text = prompt_text

func set_tutorial_prompt(title: String, prompt: String, visible_state: bool = true) -> void:
	if tutorial_banner:
		tutorial_banner.visible = visible_state
	if tutorial_title:
		tutorial_title.text = title
	if tutorial_label:
		tutorial_label.text = prompt

func toggle_inventory() -> void:
	if not inventory_menu:
		return
	inventory_menu.visible = not inventory_menu.visible
	if inventory_menu.visible:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		if inventory_menu.is_inside_tree() and inventory_menu.has_method("grab_initial_focus"):
			inventory_menu.grab_initial_focus()
	else:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	inventory_toggled.emit(inventory_menu.visible)

func toggle_orbit_map() -> void:
	if not orbit_map:
		return
	orbit_map.visible = not orbit_map.visible
	if orbit_map.visible:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		if orbit_map.is_inside_tree():
			orbit_map.grab_focus()
	else:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	map_toggled.emit(orbit_map.visible)

func toggle_pause() -> void:
	if not pause_menu:
		return
	if pause_menu.visible and pause_menu.has_method("close"):
		pause_menu.close()
	elif not pause_menu.visible and pause_menu.has_method("open"):
		pause_menu.open()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_map"):
		toggle_orbit_map()
	elif event.is_action_pressed("pause"):
		toggle_pause()
	elif event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_I or event.keycode == KEY_TAB:
			toggle_inventory()
