extends CanvasLayer
class_name FlightHUD

## Next-Gen Aerospace Flight HUD with Glassmorphism and Orbital Mechanics Telemetry.
## Supports Low Earth Orbit (LEO) orbital dynamics, hypersonic reentry, and atmospheric flight.

@export var ship_path: NodePath
var ship: ShipFlightController

# Orbital Telemetry Nodes
@onready var label_speed: Label = get_node_or_null("OrbitalTelemetryPanel/VBox/SpeedLabel")
@onready var label_mach: Label = get_node_or_null("OrbitalTelemetryPanel/VBox/MachLabel")
@onready var label_alt_asl: Label = get_node_or_null("OrbitalTelemetryPanel/VBox/AltASLLabel")
@onready var label_alt_agl: Label = get_node_or_null("OrbitalTelemetryPanel/VBox/AltAGLLabel")
@onready var label_apoapsis: Label = get_node_or_null("OrbitalTelemetryPanel/VBox/ApoapsisLabel")
@onready var label_periapsis: Label = get_node_or_null("OrbitalTelemetryPanel/VBox/PeriapsisLabel")
@onready var label_period: Label = get_node_or_null("OrbitalTelemetryPanel/VBox/PeriodLabel")
@onready var label_vspeed: Label = get_node_or_null("OrbitalTelemetryPanel/VBox/VSpeedLabel")
@onready var label_heading: Label = get_node_or_null("OrbitalTelemetryPanel/VBox/HeadingLabel")

# Propulsion & Systems Nodes
@onready var label_throttle: Label = get_node_or_null("PropulsionPanel/VBox/ThrottleLabel")
@onready var bar_throttle: ProgressBar = get_node_or_null("PropulsionPanel/VBox/ThrottleBar")
@onready var label_deltav: Label = get_node_or_null("PropulsionPanel/VBox/DeltaVLabel")
@onready var label_rcs: Label = get_node_or_null("PropulsionPanel/VBox/RcsLabel")
@onready var label_thermal: Label = get_node_or_null("PropulsionPanel/VBox/ThermalLabel")
@onready var label_gear: Label = get_node_or_null("PropulsionPanel/VBox/GearLabel")
@onready var label_gforce: Label = get_node_or_null("PropulsionPanel/VBox/GForceLabel")

# Banner & Horizon
@onready var label_status: Label = get_node_or_null("StatusBanner/Label")
@onready var horizon_indicator: Control = get_node_or_null("ArtificialHorizon/HorizonBar")

# Mobile Controls
@onready var mobile_controls_container: Control = get_node_or_null("MobileControls")
@onready var virtual_stick: SolarVirtualJoystick = get_node_or_null("MobileControls/VirtualJoystick")
@onready var throttle_slider: VSlider = get_node_or_null("MobileControls/ThrottleSlider")
@onready var btn_gear: Button = get_node_or_null("MobileControls/ButtonGear")
@onready var btn_brakes: Button = get_node_or_null("MobileControls/ButtonBrakes")
@onready var btn_camera: Button = get_node_or_null("MobileControls/ButtonCamera")
@onready var btn_vtol: Button = get_node_or_null("MobileControls/ButtonVTOL")

func _ready() -> void:
	if not ship_path.is_empty():
		ship = get_node_or_null(ship_path)
		
	if ship:
		ship.flight_data_updated.connect(_on_flight_data_updated)
		ship.landing_state_changed.connect(_on_landing_state_changed)
		
	if Engine.has_singleton("SimulationClock"):
		SimulationClock.warp_changed.connect(_on_warp_changed)
		
	# Setup Mobile UI if mobile device is detected or touch is available
	var is_mobile: bool = OS.has_feature("mobile") or DisplayServer.is_touchscreen_available()
	if mobile_controls_container:
		mobile_controls_container.visible = is_mobile
		
	if virtual_stick:
		virtual_stick.joystick_vector_changed.connect(_on_virtual_stick_moved)
		
	if throttle_slider:
		throttle_slider.value_changed.connect(_on_throttle_slider_changed)
		
	if btn_gear:
		btn_gear.pressed.connect(_on_btn_gear_pressed)
		
	if btn_camera:
		btn_camera.pressed.connect(_on_btn_camera_pressed)

func _on_warp_changed(factor: int, on_rails: bool) -> void:
	if label_status:
		if factor > 1:
			label_status.text = "TIME WARP: %dx %s" % [factor, "(ON RAILS)" if on_rails else ""]
			label_status.modulate = Color(1.0, 0.8, 0.2)
		else:
			label_status.text = "REALTIME (1x)"
			label_status.modulate = Color.WHITE

func _process(_delta: float) -> void:
	if not ship:
		return
	
	# Mobile Brakes button hold
	if btn_brakes and btn_brakes.is_pressed():
		ship.brakes_engaged = true
	elif btn_brakes and not Input.is_action_pressed("brake"):
		ship.brakes_engaged = false
		
	# Mobile VTOL / RCS burst button hold
	if btn_vtol and btn_vtol.is_pressed():
		ship.set_vtol_thrust(1.0)
	elif btn_vtol and not Input.is_action_pressed("vtol_up"):
		ship.set_vtol_thrust(0.0)

func _on_flight_data_updated(data: Dictionary) -> void:
	var speed_ms: float = data.get("speed_ms", 0.0)
	var speed_kmh: float = data.get("speed_kmh", 0.0)
	var mach: float = data.get("mach", 0.0)
	var alt_m: float = data.get("altitude_asl_m", 0.0)
	var vspeed: float = data.get("vspeed_ms", 0.0)
	var throttle_pct: float = data.get("throttle_pct", 0.0)
	
	if label_speed:
		if speed_ms >= 500.0:
			label_speed.text = "ORB VEL: %4.0f m/s (%5.0f km/h)" % [speed_ms, speed_kmh]
		else:
			label_speed.text = "AIRSPEED: %3.0f kts (%3.0f m/s)" % [data.get("speed_knots", 0.0), speed_ms]

	if label_mach:
		if mach >= 5.0:
			label_mach.text = "MACH REGIME: M %2.1f [HYPERSONIC ORBIT]" % mach
		elif mach >= 1.2:
			label_mach.text = "MACH REGIME: M %2.2f [SUPERSONIC]" % mach
		elif mach >= 0.85:
			label_mach.text = "MACH REGIME: M %1.2f [TRANSONIC]" % mach
		else:
			label_mach.text = "MACH REGIME: M %1.2f [SUBSONIC]" % mach

	if label_alt_asl:
		if alt_m >= 1000.0:
			label_alt_asl.text = "ALTITUDE (ASL): %5.1f km [LEO]" % (alt_m / 1000.0)
		else:
			label_alt_asl.text = "ALTITUDE (ASL): %4.0f m (%4.0f ft)" % [alt_m, data.get("altitude_asl_ft", 0.0)]

	if label_alt_agl:
		var agl_m: float = data.get("altitude_agl_m", alt_m)
		if agl_m >= 1000.0:
			label_alt_agl.text = "SURFACE DIST: %5.1f km" % (agl_m / 1000.0)
		else:
			label_alt_agl.text = "RDR (AGL): %4.0f m" % agl_m

	if label_apoapsis and label_periapsis and label_period:
		if alt_m > 500.0:
			var ap_km: float = data.get("ap_km", 0.0)
			var pe_km: float = data.get("pe_km", 0.0)
			var period_min: float = data.get("period_min", 0.0)
			var ecc: float = data.get("eccentricity", 0.0)
			
			if ap_km < 0:
				label_apoapsis.text = "APOAPSIS (Ap): ESCAPE TRAJ"
				label_period.text = "ORB PERIOD: HYPERBOLIC (e: %1.4f)" % ecc
			else:
				label_apoapsis.text = "APOAPSIS (Ap): %5.1f km" % ap_km
				label_period.text = "ORB PERIOD: %4.1f min (e: %1.4f)" % [period_min, ecc]
			label_periapsis.text = "PERIAPSIS (Pe): %5.1f km" % pe_km
		else:
			label_apoapsis.text = "SUB-ORBITAL FLIGHT PATH"
			label_periapsis.text = "ATMOSPHERIC REGIME"
			label_period.text = "AERO FLIGHT DYNAMICS"

	if label_vspeed:
		var sign_str: String = "+" if vspeed >= 0.0 else ""
		label_vspeed.text = "VERTICAL RATE: %s%3.1f m/s" % [sign_str, vspeed]

	if label_heading:
		var inc_deg = data.get("inclination_deg", 0.0)
		label_heading.text = "ORBIT INCLINATION: %2.1f° (HDG: %03.0f°)" % [inc_deg, data.get("heading_deg", 0.0)]

	if label_throttle:
		var thrust_kn: float = (throttle_pct / 100.0) * 450.0
		label_throttle.text = "MAIN THRUST: %3.0f%% (%4.1f kN)" % [throttle_pct, thrust_kn]
	if bar_throttle:
		bar_throttle.value = throttle_pct

	if label_rcs:
		if data.get("vtol_active", false):
			label_rcs.text = "RCS: [BURST FIRING / TRANSLATION]"
			label_rcs.modulate = Color(1.0, 0.7, 0.1)
		else:
			label_rcs.text = "RCS: [STANDBY - QUAD ACTIVE]"
			label_rcs.modulate = Color(0.2, 1.0, 0.5)

	if label_thermal:
		var q_pa: float = data.get("dynamic_pressure_pa", 0.0)
		if q_pa > 2000.0:
			var flux_kw: float = (q_pa / 500.0) * (speed_ms / 500.0) * 8.0
			label_thermal.text = "HEAT SHIELD FLUX: %4.0f kW/m² [ENTRY]" % flux_kw
			label_thermal.modulate = Color(1.0, 0.4, 0.1)
		else:
			label_thermal.text = "HEAT SHIELD FLUX: NOMINAL (0 kW/m²)"
			label_thermal.modulate = Color(0.2, 1.0, 0.5)

	if label_gear:
		if data.get("gear_down", false):
			label_gear.text = "LANDING GEAR: [DEPLOYED / DOWN]"
			label_gear.modulate = Color.GREEN
		else:
			label_gear.text = "LANDING GEAR: [RETRACTED / STOWED]"
			label_gear.modulate = Color(0.6, 0.7, 0.8)

	if label_gforce:
		if alt_m > 500.0 and throttle_pct < 1.0 and data.get("g_force_val", 0.0) < 0.05:
			label_gforce.text = "GRAVITATIONAL LOAD: 0.00 G [MICROGRAVITY]"
		else:
			var g_val = data.get("g_force_val", 1.0)
			label_gforce.text = "GRAVITATIONAL LOAD: %2.2f G" % g_val

	if horizon_indicator:
		var pitch: float = data.get("pitch_deg", 0.0)
		var roll: float = data.get("roll_deg", 0.0)
		horizon_indicator.position.y = clamp(pitch * 2.2, -90.0, 90.0)
		horizon_indicator.rotation_degrees = -roll

func _on_landing_state_changed(_is_landed: bool, msg: String) -> void:
	if label_status:
		label_status.text = msg
		label_status.modulate = Color.GREEN if _is_landed else Color.CYAN

func _on_virtual_stick_moved(vec: Vector2) -> void:
	if not ship:
		return
	ship.set_control_pitch(-vec.y)
	ship.set_control_roll(-vec.x)

func _on_throttle_slider_changed(value: float) -> void:
	if ship:
		ship.set_direct_throttle(value / 100.0)

func _on_btn_gear_pressed() -> void:
	if ship:
		ship.toggle_landing_gear()

func _on_btn_camera_pressed() -> void:
	Input.action_press("toggle_camera")
	Input.action_release("toggle_camera")
