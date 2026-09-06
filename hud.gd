extends CanvasLayer
## Presentation only: body telemetry arrives after each physics integration.

@export var target: TorusBody
@export var debug_view: Node3D

var _speed_label: Label
var _hint_label: Label
var _debug_box: VBoxContainer
var _readout: Label


func _ready() -> void:
	layer = 10
	_build_hud()
	if target == null:
		push_warning("HUD requires a TorusBody target.")
		return
	target.physics_sampled.connect(_on_physics_sampled)
	if target.input_reader != null:
		target.input_reader.device_changed.connect(_on_device_changed)
		_on_device_changed(target.input_reader.using_gamepad, target.input_reader.active_joypad)
	if debug_view != null:
		debug_view.connect(&"toggled", _on_debug_toggled)
		_on_debug_toggled(bool(debug_view.get(&"enabled")))


func _build_hud() -> void:
	var panel := PanelContainer.new()
	panel.name = "TelemetryPanel"
	panel.position = Vector2(18.0, 18.0)
	panel.custom_minimum_size.x = 600.0
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var background := StyleBoxFlat.new()
	background.bg_color = Color(0.025, 0.045, 0.065, 0.88)
	background.content_margin_left = 14.0
	background.content_margin_right = 14.0
	background.content_margin_top = 10.0
	background.content_margin_bottom = 10.0
	background.set_corner_radius_all(8)
	panel.add_theme_stylebox_override(&"panel", background)
	add_child(panel)

	var column := VBoxContainer.new()
	column.add_theme_constant_override(&"separation", 7)
	panel.add_child(column)
	var title := Label.new()
	title.text = "TORUS RACER  /  Phase 2 controls"
	title.add_theme_color_override(&"font_color", Color("9cb7ce"))
	column.add_child(title)
	_speed_label = Label.new()
	_speed_label.text = "0.0 km/h"
	_speed_label.add_theme_font_size_override(&"font_size", 28)
	column.add_child(_speed_label)
	_hint_label = Label.new()
	_hint_label.add_theme_font_size_override(&"font_size", 15)
	column.add_child(_hint_label)
	_on_device_changed(false, -1)

	_debug_box = VBoxContainer.new()
	_debug_box.visible = false
	_debug_box.add_theme_constant_override(&"separation", 6)
	column.add_child(_debug_box)
	_debug_box.add_child(HSeparator.new())
	_readout = Label.new()
	_readout.add_theme_font_size_override(&"font_size", 16)
	_debug_box.add_child(_readout)
	var legend := RichTextLabel.new()
	legend.bbcode_enabled = true
	legend.fit_content = true
	legend.scroll_active = false
	legend.mouse_filter = Control.MOUSE_FILTER_IGNORE
	legend.add_theme_font_size_override(&"normal_font_size", 14)
	legend.text = (
		"[color=#ffffff]● Contact[/color]   [color=#65e572]↑ Normal[/color]   "
		+ "[color=#ffad42]↑ Traction (estimated)[/color]   [color=#48cfff]↑ Velocity[/color]\n"
		+ "[color=#cb86ff]↑ Angular velocity[/color]   [color=#fff06a]↑ Player torque[/color]\n"
		+ "[color=#ff73b4]↑ Assist torque[/color]   [color=#ff5f65]↑ Gyro torque[/color]\n"
		+ "[color=#64e4c6]↑ Bank pivot force[/color]"
	)
	_debug_box.add_child(legend)


func _on_physics_sampled(snapshot: Dictionary) -> void:
	var speed: float = snapshot.get("speed", 0.0)
	_speed_label.text = "%.1f km/h" % (speed * 3.6)
	if not _debug_box.visible:
		return
	var spin: float = snapshot.get("spin_rate", 0.0)
	var lean: float = snapshot.get("lean_degrees", 0.0)
	var grounded: bool = snapshot.get("grounded", false)
	var slip: float = snapshot.get("slip_ratio", 0.0)
	_readout.text = (
		"Speed %.2f m/s  |  Spin %.2f rad/s (%.0f rpm)\n"
		+ "Lean %+.1f°  |  Grounded %s  |  Slip %.3f"
	) % [speed, spin, spin * 60.0 / TAU, lean, "yes" if grounded else "no", slip]


func _on_device_changed(gamepad: bool, _device: int) -> void:
	if gamepad:
		_hint_label.text = (
			"RT Accelerate · LT Brake · Left stick Lean\n"
			+ "A / Cross Hop · Y / Triangle Reset · Back / Select Physics debug"
		)
	else:
		_hint_label.text = (
			"↑ Accelerate · ↓ Brake · ← / → Lean\n"
			+ "Space Hop · R Reset · D Physics debug"
		)


func _on_debug_toggled(value: bool) -> void:
	_debug_box.visible = value
