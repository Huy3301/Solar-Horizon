class_name SuitBars extends Control

## EVA suit status bars displaying life support (O2), hazard protection, and jetpack fuel.

var bar_life_support: ProgressBar = null
var val_life_support: Label = null
var bar_hazard: ProgressBar = null
var val_hazard: Label = null
var bar_jetpack: ProgressBar = null
var val_jetpack: Label = null
var compass_label: Label = null

var current_life_support: float = 100.0
var current_hazard: float = 0.0
var current_jetpack: float = 100.0

func _ready() -> void:
	_resolve_nodes()

func _resolve_nodes() -> void:
	bar_life_support = get_node_or_null("VBox/RowLifeSupport/LifeSupportBar") as ProgressBar
	val_life_support = get_node_or_null("VBox/RowLifeSupport/LifeSupportVal") as Label
	bar_hazard = get_node_or_null("VBox/RowHazard/HazardBar") as ProgressBar
	val_hazard = get_node_or_null("VBox/RowHazard/HazardVal") as Label
	bar_jetpack = get_node_or_null("VBox/RowJetpack/JetpackBar") as ProgressBar
	val_jetpack = get_node_or_null("VBox/RowJetpack/JetpackVal") as Label
	compass_label = get_node_or_null("VBox/CompassLabel") as Label

func update_life_support(current: float, max_val: float = 100.0) -> void:
	if not bar_life_support:
		_resolve_nodes()
	current_life_support = current
	var pct = (current / max_val) * 100.0 if max_val > 0.0 else 0.0
	if bar_life_support:
		bar_life_support.max_value = max_val
		bar_life_support.value = current
	if val_life_support:
		val_life_support.text = "%3.0f%%" % pct
		if pct < 20.0:
			val_life_support.modulate = Color(1.0, 0.2, 0.2)
		elif pct < 50.0:
			val_life_support.modulate = Color(1.0, 0.8, 0.2)
		else:
			val_life_support.modulate = Color.WHITE

func update_hazard(current: float, max_val: float = 100.0) -> void:
	if not bar_hazard:
		_resolve_nodes()
	current_hazard = current
	var pct = (current / max_val) * 100.0 if max_val > 0.0 else 0.0
	if bar_hazard:
		bar_hazard.max_value = max_val
		bar_hazard.value = current
	if val_hazard:
		val_hazard.text = "%3.0f%%" % pct
		if pct > 60.0:
			val_hazard.modulate = Color(1.0, 0.3, 0.2)
		else:
			val_hazard.modulate = Color.WHITE

func update_jetpack(current: float, max_val: float = 100.0) -> void:
	if not bar_jetpack:
		_resolve_nodes()
	current_jetpack = current
	var pct = (current / max_val) * 100.0 if max_val > 0.0 else 0.0
	if bar_jetpack:
		bar_jetpack.max_value = max_val
		bar_jetpack.value = current
	if val_jetpack:
		val_jetpack.text = "%3.0f%%" % pct

func update_heading(deg: float) -> void:
	if not compass_label:
		_resolve_nodes()
	if compass_label:
		var normalized_deg = fmod(deg + 360.0, 360.0)
		compass_label.text = "HEADING: %03d°" % int(normalized_deg)
