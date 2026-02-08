extends Control

@onready var name_label: Label = %NameLabel
@onready var art_rect: TextureRect = %Art
@onready var rarity_label: Label = %RarityLabel
@onready var element_label: Label = %ElementLabel
@onready var archetype_label: Label = %ArchetypeLabel
@onready var card: PanelContainer = %Card
@onready var name_banner: PanelContainer = %NameBanner
@onready var rarity_pill: PanelContainer = %RarityPill
@onready var element_pill: PanelContainer = %ElementPill
@onready var art_frame: PanelContainer = %ArtFrame
@onready var rarity_gem: PanelContainer = %RarityGem
@onready var art_top_gradient: TextureRect = %ArtTopGradient
@onready var art_vignette: TextureRect = %ArtVignette

@onready var stats_row: HBoxContainer = %StatsRow
@onready var hp_pill: PanelContainer = %HpPill
@onready var hp_label: Label = %HpLabel
@onready var atk_pill: PanelContainer = %AtkPill
@onready var atk_label: Label = %AtkLabel
@onready var def_pill: PanelContainer = %DefPill
@onready var def_label: Label = %DefLabel
@onready var spd_pill: PanelContainer = %SpdPill
@onready var spd_label: Label = %SpdLabel

@onready var move1_label: Label = %Move1Label
@onready var move2_label: Label = %Move2Label
@onready var lore_label: Label = %LoreLabel
@onready var done_button: Button = %DoneButton

func _ready() -> void:
	AppState.apply_ui_scale(self)
	done_button.pressed.connect(_on_done_pressed)

	var creature = AppState.creatures.back() if AppState.creatures.size() > 0 else null
	if creature == null:
		name_label.text = "(no creature)"
		return
	name_label.text = creature.get("name", "Unknown")
	rarity_label.text = str(creature.get("rarity", "?"))
	element_label.text = str(creature.get("element", "?"))
	archetype_label.text = str(creature.get("archetype", "?"))

	# Lore / flavor text (prefer server-generated flavor_text; fall back to essence)
	var lore := str(creature.get("flavor_text", "")).strip_edges()
	if lore == "":
		lore = str(creature.get("essence", "")).strip_edges()
	if lore == "":
		lore = "A newly-scanned %s infused with %s energy." % [archetype_label.text, element_label.text]
	lore_label.text = lore

	_apply_card_colors(rarity_label.text, element_label.text)

	# Art
	var art_hash: String = str(creature.get("art_hash", ""))
	if art_hash != "":
		var tex := AppState.load_art_texture(art_hash)
		art_rect.texture = tex
	else:
		art_rect.texture = null
	# Stats (prefer server-provided stats)
	var stats: Dictionary = creature.get("stats", {})
	var hp := int(stats.get("hp", 0))
	var atk := int(stats.get("atk", 0))
	var deff := int(stats.get("def", 0))
	var spd := int(stats.get("spd", 0))
	if hp <= 0:
		hp = _hp_max_for_archetype(archetype_label.text)
	hp_label.text = "HP %d" % hp
	atk_label.text = "ATK %d" % atk
	def_label.text = "DEF %d" % deff
	spd_label.text = "SPD %d" % spd

	var moves: Array = creature.get("moves", [])
	if moves.size() > 0:
		move1_label.text = str(moves[0].get("name", "Move"))
	if moves.size() > 1:
		move2_label.text = str(moves[1].get("name", "Move"))

func _hp_max_for_archetype(archetype: String) -> int:
	match archetype:
		"Bulwark Golem": return 160
		"Forge Pup": return 150
		"Sprout Medic": return 120
		"Hex Scholar": return 115
		"Cannon Critter": return 100
		"Pouncer": return 105
		"Zoner Wisp": return 112
		"Storm Skater": return 110
		_: return 100

func _apply_card_colors(rarity: String, element: String) -> void:
	var rarity_bg := Color("#E1E6EC")
	var rarity_accent := Color("#8A95A6")
	match rarity:
		"Rare":
			rarity_bg = Color("#BEDCFF")
			rarity_accent = Color("#3F79D6")
		"Epic":
			rarity_bg = Color("#D4C2FF")
			rarity_accent = Color("#7A45D6")
		"Legendary":
			rarity_bg = Color("#FFE4B4")
			rarity_accent = Color("#D18A1E")

	var element_accent := Color("#7AA0FF")
	match element:
		"Fire": element_accent = Color("#FF6B4A")
		"Water": element_accent = Color("#4AA3FF")
		"Air": element_accent = Color("#A8E6FF")
		"Earth": element_accent = Color("#69C06A")

	# Name banner plate
	var name_sb := StyleBoxFlat.new()	
	name_sb.bg_color = rarity_accent.darkened(0.25)
	name_sb.corner_radius_top_left = 14
	name_sb.corner_radius_top_right = 14
	name_sb.corner_radius_bottom_left = 14
	name_sb.corner_radius_bottom_right = 14
	name_sb.border_width_left = 2
	name_sb.border_width_top = 2
	name_sb.border_width_right = 2
	name_sb.border_width_bottom = 2
	name_sb.border_color = rarity_accent
	name_banner.add_theme_stylebox_override("panel", name_sb)
	name_label.add_theme_color_override("font_color", Color.WHITE)

	# Body text colors (keep readable on light backgrounds)
	var body_color := Color("#1B1F24")	
	archetype_label.add_theme_color_override("font_color", body_color)
	lore_label.add_theme_color_override("font_color", body_color)
	move1_label.add_theme_color_override("font_color", body_color)
	move2_label.add_theme_color_override("font_color", body_color)

	# Card panel
	var card_sb := StyleBoxFlat.new()
	card_sb.bg_color = rarity_bg
	card_sb.corner_radius_top_left = 18
	card_sb.corner_radius_top_right = 18
	card_sb.corner_radius_bottom_left = 18
	card_sb.corner_radius_bottom_right = 18
	card_sb.border_width_left = 6
	card_sb.border_width_top = 6
	card_sb.border_width_right = 6
	card_sb.border_width_bottom = 6
	card_sb.border_color = rarity_accent
	card_sb.shadow_size = 12
	card_sb.shadow_color = Color(0, 0, 0, 0.25)
	card.add_theme_stylebox_override("panel", card_sb)

	# Rarity pill
	var pill_sb := StyleBoxFlat.new()
	pill_sb.bg_color = rarity_accent
	pill_sb.corner_radius_top_left = 10
	pill_sb.corner_radius_top_right = 10
	pill_sb.corner_radius_bottom_left = 10
	pill_sb.corner_radius_bottom_right = 10
	rarity_pill.add_theme_stylebox_override("panel", pill_sb)
	rarity_label.add_theme_color_override("font_color", Color.WHITE)

	# Element pill
	var elem_sb := StyleBoxFlat.new()
	elem_sb.bg_color = element_accent
	elem_sb.corner_radius_top_left = 10
	elem_sb.corner_radius_top_right = 10
	elem_sb.corner_radius_bottom_left = 10
	elem_sb.corner_radius_bottom_right = 10
	element_pill.add_theme_stylebox_override("panel", elem_sb)
	element_label.add_theme_color_override("font_color", Color.BLACK)

	# Stat pills
	var stat_sb := StyleBoxFlat.new()
	stat_sb.bg_color = Color(1, 1, 1, 0.65)
	stat_sb.corner_radius_top_left = 10
	stat_sb.corner_radius_top_right = 10
	stat_sb.corner_radius_bottom_left = 10
	stat_sb.corner_radius_bottom_right = 10

	hp_pill.add_theme_stylebox_override("panel", stat_sb)
	atk_pill.add_theme_stylebox_override("panel", stat_sb)
	def_pill.add_theme_stylebox_override("panel", stat_sb)
	spd_pill.add_theme_stylebox_override("panel", stat_sb)

	hp_label.add_theme_color_override("font_color", body_color)
	atk_label.add_theme_color_override("font_color", body_color)
	def_label.add_theme_color_override("font_color", body_color)
	spd_label.add_theme_color_override("font_color", body_color)

	# Rarity gem (small coin in header)
	var gem_sb := StyleBoxFlat.new()
	gem_sb.bg_color = rarity_accent
	gem_sb.corner_radius_top_left = 999
	gem_sb.corner_radius_top_right = 999
	gem_sb.corner_radius_bottom_left = 999
	gem_sb.corner_radius_bottom_right = 999
	gem_sb.border_width_left = 3
	gem_sb.border_width_top = 3
	gem_sb.border_width_right = 3
	gem_sb.border_width_bottom = 3
	gem_sb.border_color = Color(1, 1, 1, 0.9)
	rarity_gem.add_theme_stylebox_override("panel", gem_sb)

	# Art frame
	var art_sb := StyleBoxFlat.new()
	art_sb.bg_color = Color(1, 1, 1, 0.35)
	art_sb.border_width_left = 4
	art_sb.border_width_top = 4
	art_sb.border_width_right = 4
	art_sb.border_width_bottom = 4
	art_sb.border_color = rarity_accent
	art_sb.corner_radius_top_left = 14
	art_sb.corner_radius_top_right = 14
	art_sb.corner_radius_bottom_left = 14
	art_sb.corner_radius_bottom_right = 14
	art_frame.add_theme_stylebox_override("panel", art_sb)

	# Art overlays: subtle top gradient + vignette for card feel
	art_top_gradient.texture = _make_vertical_alpha_gradient(256, true)
	art_vignette.texture = _make_vignette_texture(256)

func _make_vertical_alpha_gradient(tex_size: int, top_dark: bool) -> Texture2D:
	var img: Image = Image.create(1, tex_size, false, Image.FORMAT_RGBA8)
	var denom: float = float(maxi(1, tex_size - 1))
	for y in range(tex_size):
		var t: float = float(y) / denom
		# alpha fades out toward bottom
		var a: float = lerpf(0.55, 0.0, t)
		var c: Color = Color(0, 0, 0, a) if top_dark else Color(1, 1, 1, a)
		img.set_pixel(0, y, c)
	img.generate_mipmaps()
	var tex: ImageTexture = ImageTexture.create_from_image(img)
	return tex

func _make_vignette_texture(tex_size: int) -> Texture2D:
	var img: Image = Image.create(tex_size, tex_size, false, Image.FORMAT_RGBA8)
	var cx: float = float(tex_size - 1) * 0.5
	var cy: float = float(tex_size - 1) * 0.5
	var maxd: float = sqrt(cx * cx + cy * cy)
	for y in range(tex_size):
		for x in range(tex_size):
			var dx: float = float(x) - cx
			var dy: float = float(y) - cy
			var d: float = sqrt(dx * dx + dy * dy) / maxd
			# darken near edges (soft)
			var a: float = clampf((d - 0.55) / 0.45, 0.0, 1.0) * 0.65
			img.set_pixel(x, y, Color(0, 0, 0, a))
	img.generate_mipmaps()
	var tex: ImageTexture = ImageTexture.create_from_image(img)
	return tex

func _on_done_pressed() -> void:
	AppState.go("res://scenes/MainMenu.tscn")
