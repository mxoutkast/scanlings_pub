extends Control

@onready var shell: PanelContainer = %Shell
@onready var title_logo: PanelContainer = %TitleLogo
@onready var title_logo_placeholder: Label = %TitleLogoPlaceholder

@onready var charges_label: Label = %ChargesLabel
@onready var essence_label: Label = %EssenceLabel
@onready var cores_label: Label = %CoresLabel
@onready var footer_hint: Label = %FooterHint

@onready var scan_button: Button = %ScanButton
@onready var bestiary_button: Button = %BestiaryButton
@onready var team_button: Button = %TeamButton
@onready var settings_button: Button = %SettingsButton
@onready var dev_spawn_button: Button = %DevSpawnButton
@onready var ladder_button: Button = %LadderButton

func _ready() -> void:
	AppState.apply_ui_scale(self)
	_apply_styles()

	# Only show dev tools in debug builds
	var is_debug: bool = OS.has_feature("debug")
	settings_button.visible = is_debug
	dev_spawn_button.visible = is_debug

	# Connect signals in code
	scan_button.pressed.connect(_on_scan_pressed)
	bestiary_button.pressed.connect(_on_bestiary_pressed)
	team_button.pressed.connect(_on_team_pressed)
	settings_button.pressed.connect(_on_settings_pressed)
	dev_spawn_button.pressed.connect(_on_dev_spawn_pressed)
	ladder_button.pressed.connect(_on_ladder_pressed)

	refresh()

func _apply_styles() -> void:
	# Shell
	var shell_sb: StyleBoxFlat = StyleBoxFlat.new()
	shell_sb.bg_color = Color("#E1E6EC")
	shell_sb.corner_radius_top_left = 18
	shell_sb.corner_radius_top_right = 18
	shell_sb.corner_radius_bottom_left = 18
	shell_sb.corner_radius_bottom_right = 18
	shell_sb.border_width_left = 6
	shell_sb.border_width_top = 6
	shell_sb.border_width_right = 6
	shell_sb.border_width_bottom = 6
	shell_sb.border_color = Color("#8A95A6")
	shell_sb.shadow_size = 12
	shell_sb.shadow_color = Color(0, 0, 0, 0.25)
	shell.add_theme_stylebox_override("panel", shell_sb)

	# Title logo placeholder frame
	var logo_sb: StyleBoxFlat = StyleBoxFlat.new()
	logo_sb.bg_color = Color(1, 1, 1, 0.30)
	logo_sb.corner_radius_top_left = 16
	logo_sb.corner_radius_top_right = 16
	logo_sb.corner_radius_bottom_left = 16
	logo_sb.corner_radius_bottom_right = 16
	logo_sb.border_width_left = 4
	logo_sb.border_width_top = 4
	logo_sb.border_width_right = 4
	logo_sb.border_width_bottom = 4
	logo_sb.border_color = Color("#8A95A6")
	title_logo.add_theme_stylebox_override("panel", logo_sb)
	title_logo_placeholder.add_theme_color_override("font_color", Color("#2B3340"))

	# Text colors for light background
	var body_color: Color = Color("#1B1F24")
	charges_label.add_theme_color_override("font_color", body_color)
	essence_label.add_theme_color_override("font_color", body_color)
	cores_label.add_theme_color_override("font_color", body_color)
	footer_hint.add_theme_color_override("font_color", Color("#516070"))

	# Button style
	_style_primary_button(scan_button, Color("#4AA3FF"))
	_style_primary_button(bestiary_button, Color("#7A45D6"))
	_style_primary_button(team_button, Color("#69C06A"))
	_style_primary_button(ladder_button, Color("#D18A1E"))
	_style_secondary_button(settings_button)
	_style_secondary_button(dev_spawn_button)

func _style_primary_button(btn: Button, accent: Color) -> void:
	var sb: StyleBoxFlat = StyleBoxFlat.new()
	sb.bg_color = accent
	sb.corner_radius_top_left = 14
	sb.corner_radius_top_right = 14
	sb.corner_radius_bottom_left = 14
	sb.corner_radius_bottom_right = 14
	sb.border_width_left = 2
	sb.border_width_top = 2
	sb.border_width_right = 2
	sb.border_width_bottom = 2
	sb.border_color = accent.darkened(0.25)
	btn.add_theme_stylebox_override("normal", sb)

	var sb_h: StyleBoxFlat = sb.duplicate() as StyleBoxFlat
	sb_h.bg_color = accent.lightened(0.08)
	btn.add_theme_stylebox_override("hover", sb_h)

	var sb_p: StyleBoxFlat = sb.duplicate() as StyleBoxFlat
	sb_p.bg_color = accent.darkened(0.08)
	btn.add_theme_stylebox_override("pressed", sb_p)

	btn.add_theme_color_override("font_color", Color.WHITE)
	btn.add_theme_color_override("font_hover_color", Color.WHITE)
	btn.add_theme_color_override("font_pressed_color", Color.WHITE)

func _style_secondary_button(btn: Button) -> void:
	var sb: StyleBoxFlat = StyleBoxFlat.new()
	sb.bg_color = Color(1, 1, 1, 0.55)
	sb.corner_radius_top_left = 12
	sb.corner_radius_top_right = 12
	sb.corner_radius_bottom_left = 12
	sb.corner_radius_bottom_right = 12
	sb.border_width_left = 2
	sb.border_width_top = 2
	sb.border_width_right = 2
	sb.border_width_bottom = 2
	sb.border_color = Color("#8A95A6")
	btn.add_theme_stylebox_override("normal", sb)

	var sb_h: StyleBoxFlat = sb.duplicate() as StyleBoxFlat
	sb_h.bg_color = Color(1, 1, 1, 0.72)
	btn.add_theme_stylebox_override("hover", sb_h)

	var sb_p: StyleBoxFlat = sb.duplicate() as StyleBoxFlat
	sb_p.bg_color = Color(1, 1, 1, 0.45)
	btn.add_theme_stylebox_override("pressed", sb_p)

	btn.add_theme_color_override("font_color", Color("#1B1F24"))
	btn.add_theme_color_override("font_hover_color", Color("#1B1F24"))
	btn.add_theme_color_override("font_pressed_color", Color("#1B1F24"))

func refresh() -> void:
	charges_label.text = "Aether: %d" % AppState.aether_charges
	essence_label.text = "Essence: %d" % AppState.essence
	cores_label.text = "Cores: %d" % AppState.fusion_cores

func _on_scan_pressed() -> void:
	AppState.go("res://scenes/Scan.tscn")

func _on_bestiary_pressed() -> void:
	AppState.go("res://scenes/Bestiary.tscn")

func _on_team_pressed() -> void:
	AppState.go("res://scenes/TeamBuilder.tscn")

func _on_settings_pressed() -> void:
	AppState.go("res://scenes/Settings.tscn")

func _on_dev_spawn_pressed() -> void:
	AppState.go("res://scenes/DevSpawn.tscn")

func _on_ladder_pressed() -> void:
	AppState.go("res://scenes/Ladder.tscn")
