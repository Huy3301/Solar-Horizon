class_name FlightTelemetry extends Control

## Flight telemetry HUD component displaying altitude AGL, speed, Ap/Pe, throttle, and gear.
## Supports keyboard/gamepad navigation and responsive scaling.

var label_speed: Label = null
var label_mach: Label = null
var label_alt_agl: Label = null
var label_alt_asl: Label = null
var label_ap: Label = null
var label_pe: Label = null
var label_throttle: Label = null
var bar_throttle: ProgressBar = null
var label_gear: Label = null
var label_status: Label = null

var current_telemetry: Dictionary = {}

func _ready() -> void:
	_resolve_nodes()

func _resolve_nodes() -> void:
	label_speed = get_node_or_null("Margin/VBox/RowSpeed/SpeedValue") as Label
	label_mach = get_node_or_null("Margin/VBox/RowMach/MachValue") as Label
	label_alt_agl = get_node_or_null("Margin/VBox/RowAGL/AGLValue") as Label
	label_alt_asl = get_node_or_null("Margin/VBox/RowASL/ASLValue") as Label
	label_ap = get_node_or_null("Margin/VBox/RowAp/ApValue") as Label
	label_pe = get_node_or_null("Margin/VBox/RowPe/PeValue") as Label
	label_throttle = get_node_or_null("Margin/VBox/RowThrottle/ThrottleValue") as Label
	bar_throttle = get_node_or_null("Margin/VBox/RowThrottle/ThrottleBar") as ProgressBar
	label_gear = get_node_or_null("Margin/VBox/RowGear/GearValue") as Label
	label_status = get_node_or_null("Margin/VBox/StatusLabel") as Label

func update_telemetry(data: Dictionary) -> void:
	if not label_speed:
		_resolve_nodes()
		
	current_telemetry = data
	
	var speed: float = data.get("speed_ms", 0.0)
	var mach: float = data.get("mach", speed / 340.29)
	var agl: float = data.get("altitude_agl_m", 0.0)
	var asl: float = data.get("altitude_asl_m", 0.0)
	var ap: float = data.get("ap_km", 0.0)
	var pe: float = data.get("pe_km", 0.0)
	var throttle: float = data.get("throttle_pct", 0.0)
	var gear_down: bool = data.get("gear_down", false)
	var is_landed: bool = data.get("is_landed", false)
	var is_crashed: bool = data.get("is_crashed", false)
	
	if label_speed:
		label_speed.text = "%8.1f m/s" % speed
	if label_mach:
		label_mach.text = "%5.2f M" % mach
		
	if label_alt_agl:
		if agl < 10000.0:
			label_alt_agl.text = "%6.1f m" % agl
		else:
			label_alt_agl.text = "%6.2f km" % (agl / 1000.0)
			
	if label_alt_asl:
		label_alt_asl.text = "%7.2f km" % (asl / 1000.0)
		
	if label_ap:
		label_ap.text = "%7.1f km" % ap
	if label_pe:
		label_pe.text = "%7.1f km" % pe
		if pe < 85.0:
			label_pe.modulate = Color(1.0, 0.4, 0.4)
		else:
			label_pe.modulate = Color.WHITE
			
	if label_throttle:
		label_throttle.text = "%3.0f%%" % throttle
	if bar_throttle:
		bar_throttle.value = throttle
		
	if label_gear:
		if gear_down:
			label_gear.text = "DEPLOYED"
			label_gear.modulate = Color(0.2, 1.0, 0.4)
		else:
			label_gear.text = "RETRACTED"
			label_gear.modulate = Color(0.7, 0.7, 0.7)
			
	if label_status:
		if is_crashed:
			label_status.text = "CRITICAL DAMAGE"
			label_status.modulate = Color.RED
		elif is_landed:
			label_status.text = "VESSEL LANDED"
			label_status.modulate = Color(0.2, 1.0, 0.4)
		else:
			label_status.text = "NOMINAL FLIGHT"
			label_status.modulate = Color.WHITE

func get_telemetry_value(key: String, default_val: Variant = null) -> Variant:
	return current_telemetry.get(key, default_val)
