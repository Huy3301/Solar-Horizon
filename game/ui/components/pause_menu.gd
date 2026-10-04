class_name PauseMenu extends Control

## Keyboard and Gamepad navigable pause menu with Resume, Settings, Respawn at Base, and Quit.

signal resumed()
signal settings_opened()
signal respawn_requested()
signal quit_requested()

var btn_resume: Button = null
var btn_settings: Button = null
var btn_respawn: Button = null
var btn_quit: Button = null
var settings_panel: Control = null

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS # Runs while tree is paused
	_resolve_nodes()
	_setup_focus()

func _resolve_nodes() -> void:
	if not btn_resume:
		btn_resume = get_node_or_null("Panel/VBox/ButtonResume") as Button
		if btn_resume and not btn_resume.pressed.is_connected(_on_resume_pressed):
			btn_resume.pressed.connect(_on_resume_pressed)
	if not btn_settings:
		btn_settings = get_node_or_null("Panel/VBox/ButtonSettings") as Button
		if btn_settings and not btn_settings.pressed.is_connected(_on_settings_pressed):
			btn_settings.pressed.connect(_on_settings_pressed)
	if not btn_respawn:
		btn_respawn = get_node_or_null("Panel/VBox/ButtonRespawn") as Button
		if btn_respawn and not btn_respawn.pressed.is_connected(_on_respawn_pressed):
			btn_respawn.pressed.connect(_on_respawn_pressed)
	if not btn_quit:
		btn_quit = get_node_or_null("Panel/VBox/ButtonQuit") as Button
		if btn_quit and not btn_quit.pressed.is_connected(_on_quit_pressed):
			btn_quit.pressed.connect(_on_quit_pressed)
	if not settings_panel:
		settings_panel = get_node_or_null("SettingsPanel") as Control

func _setup_focus() -> void:
	_resolve_nodes()
	if btn_resume and btn_settings:
		btn_resume.focus_neighbor_bottom = btn_resume.get_path_to(btn_settings)
		btn_settings.focus_neighbor_top = btn_settings.get_path_to(btn_resume)
	if btn_settings and btn_respawn:
		btn_settings.focus_neighbor_bottom = btn_settings.get_path_to(btn_respawn)
		btn_respawn.focus_neighbor_top = btn_respawn.get_path_to(btn_settings)
	if btn_respawn and btn_quit:
		btn_respawn.focus_neighbor_bottom = btn_respawn.get_path_to(btn_quit)
		btn_quit.focus_neighbor_top = btn_quit.get_path_to(btn_respawn)

func open() -> void:
	_resolve_nodes()
	visible = true
	if is_inside_tree():
		get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if btn_resume and is_inside_tree():
		btn_resume.grab_focus()

func close() -> void:
	_resolve_nodes()
	visible = false
	if settings_panel:
		settings_panel.visible = false
	if is_inside_tree():
		get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	resumed.emit()

func _on_resume_pressed() -> void:
	close()

func _on_settings_pressed() -> void:
	if settings_panel:
		settings_panel.visible = not settings_panel.visible
	settings_opened.emit()

func _on_respawn_pressed() -> void:
	close()
	respawn_requested.emit()

func _on_quit_pressed() -> void:
	quit_requested.emit()
	if is_inside_tree() and not OS.has_feature("web"):
		get_tree().quit()

func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("pause") or event.is_action_pressed("ui_cancel"):
		if settings_panel and settings_panel.visible:
			settings_panel.visible = false
			if btn_settings:
				btn_settings.grab_focus()
		else:
			close()
		get_viewport().set_input_as_handled()
