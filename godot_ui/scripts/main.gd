extends Control

const COLOR_WHITE := Color("#ffffff")
const COLOR_BLUE := Color("#155dfc")
const COLOR_BLUE_DARK := Color("#003eff")
const COLOR_ORANGE := Color("#fda934")
const COLOR_NAVY := Color("#111827")
const COLOR_TEXT := Color("#111827")
const COLOR_MUTED := Color("#4b5563")
const COLOR_LINK := Color("#99a1af")
const COLOR_BORDER := Color("#e5e7eb")
const COLOR_PANEL_TINT := Color("#eff6ff")
const COLOR_CTA_TEXT := Color("#dbeafe")
const COLOR_DARK_BORDER := Color("#1e2939")

var font_inter: FontFile
var font_poppins_regular: FontFile
var font_poppins_bold: FontFile

var tex_logo: Texture2D
var tex_hero: Texture2D
var tex_wrench: Texture2D
var tex_earthquakes: Texture2D
var tex_arrows: Texture2D
var tex_design: Texture2D
var tex_chart: Texture2D
var tex_3d: Texture2D

@onready var website: ScrollContainer = %ProGenWebsite
@onready var page_layout: VBoxContainer = %PageLayout
@onready var navbar: PanelContainer = %Navbar
@onready var hero_panel: PanelContainer = %HeroPanel
@onready var features_panel: PanelContainer = %FeaturesPanel
@onready var how_panel: PanelContainer = %HowPanel
@onready var cta_area: PanelContainer = %CTA_BlueArea
@onready var footer_dark: PanelContainer = %FooterDark

var app_view_container: Control
var scroll_tween: Tween

func _ready() -> void:
	_load_assets()
	theme = _build_theme()
	_configure_layout()
	
	_build_main_structure()
	_build_navbar()
	_build_hero()
	_build_features()
	_build_how_it_works()
	_build_cta()
	_build_footer()
	_build_app_view()

func _load_assets() -> void:
	font_inter = _load_font("res://assets/fonts/Inter-Variable.ttf")
	font_poppins_regular = _load_font("res://assets/fonts/Poppins-Regular.ttf")
	font_poppins_bold = _load_font("res://assets/fonts/Poppins-Bold.ttf")

	tex_logo = _load_texture("res://assets/images/378c25b527b93f4d537c05f5e5e176bde7944f7d.png")
	tex_hero = _load_texture("res://assets/images/f229d4a87587b430f06eac9a1721e00ff504c72a.png")
	tex_wrench = _load_texture("res://assets/images/685eb8a845267f833aafffc00ac390593e26b82c.png")
	tex_earthquakes = _load_texture("res://assets/images/4eadefe6acfaa3f5c07af4310d78a6f0b4d474dd.png")
	tex_arrows = _load_texture("res://assets/images/925fb8034affbf0e3b5285404e443337e5b0cba5.png")
	tex_design = _load_texture("res://assets/images/b5d36fae30c80b058f77ee82997855c72ab0321d.png")
	tex_chart = _load_texture("res://assets/images/f08d789c81c84549efa2f4331d2fc82a84dac85a.png")
	tex_3d = _load_texture("res://assets/images/dd653bd5aa09fcbc12b0969f9655854d3c28e400.png")

func _configure_layout() -> void:
	website.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	website.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	page_layout.add_theme_constant_override("separation", 0)

func _build_main_structure() -> void:
	app_view_container = Control.new()
	app_view_container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	app_view_container.visible = false
	add_child(app_view_container)

func _switch_to_app() -> void:
	website.visible = false
	app_view_container.visible = true

func _switch_to_landing() -> void:
	app_view_container.visible = false
	website.visible = true

func _scroll_to_node(node: Control) -> void:
	if not website.visible:
		app_view_container.visible = false
		website.visible = true
		await get_tree().process_frame
	
	var target_y := int(node.global_position.y - page_layout.global_position.y)
	var max_scroll = website.get_v_scroll_bar().max_value - website.get_v_scroll_bar().page
	target_y = clampi(target_y, 0, int(max_scroll))
	
	if scroll_tween and scroll_tween.is_valid():
		scroll_tween.kill()
	
	scroll_tween = create_tween()
	scroll_tween.set_ease(Tween.EASE_OUT)
	scroll_tween.set_trans(Tween.TRANS_CUBIC)
	scroll_tween.tween_property(website, "scroll_vertical", target_y, 0.6)

func _build_theme() -> Theme:
	var progen_theme := Theme.new()
	progen_theme.default_font = font_inter
	progen_theme.default_font_size = 18
	progen_theme.set_font("font", "Label", font_inter)
	progen_theme.set_font("font_bold", "Label", font_poppins_bold)
	progen_theme.set_font("font", "Button", font_inter)
	progen_theme.set_font("font_bold", "Button", font_inter)

	var btn_primary := _style_box(COLOR_BLUE, COLOR_BLUE, 0, 8)
	progen_theme.set_stylebox("normal", "Button", btn_primary)
	progen_theme.set_stylebox("hover", "Button", btn_primary)
	progen_theme.set_stylebox("pressed", "Button", btn_primary)
	progen_theme.set_color("font_color", "Button", COLOR_WHITE)

	var btn_outline := _style_box(COLOR_WHITE, COLOR_BLUE, 2, 8)
	progen_theme.set_stylebox("normal", "OutlineButton", btn_outline)
	progen_theme.set_stylebox("hover", "OutlineButton", _style_box(COLOR_PANEL_TINT, COLOR_BLUE, 2, 8))
	progen_theme.set_stylebox("pressed", "OutlineButton", _style_box(COLOR_PANEL_TINT, COLOR_BLUE, 2, 8))
	progen_theme.set_color("font_color", "OutlineButton", COLOR_BLUE)

	progen_theme.set_stylebox("panel", "PanelContainer", _style_box(COLOR_WHITE, COLOR_BORDER, 1, 0))
	progen_theme.set_stylebox("panel", "FeatureCard", _style_box(COLOR_WHITE, COLOR_BORDER, 1, 12))

	return progen_theme

func _build_navbar() -> void:
	_clear_children(navbar)
	var nav_style := _style_box(COLOR_WHITE, COLOR_BORDER, 1, 0, 0)
	nav_style.shadow_size = 0 
	navbar.add_theme_stylebox_override("panel", nav_style)
	navbar.clip_contents = true 
	
	var center := CenterContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	navbar.add_child(center)

	var row := HBoxContainer.new()
	row.custom_minimum_size = Vector2(1400, 100) 
	row.add_theme_constant_override("separation", 0) 
	center.add_child(row)

	var logo := TextureRect.new()
	logo.texture = tex_logo
	logo.custom_minimum_size = Vector2(170, 50) 
	logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED 
	logo.size_flags_vertical = Control.SIZE_SHRINK_CENTER 
	row.add_child(logo)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)

	var right_group := HBoxContainer.new()
	right_group.add_theme_constant_override("separation", 32)
	right_group.size_flags_vertical = Control.SIZE_SHRINK_CENTER 
	row.add_child(right_group)

	var f_link = _nav_button("Features")
	f_link.pressed.connect(func(): _scroll_to_node(features_panel))
	right_group.add_child(f_link)

	var h_link = _nav_button("How It Works")
	h_link.pressed.connect(func(): _scroll_to_node(how_panel))
	right_group.add_child(h_link)

	var btn = _primary_button("Launch App", Vector2(140, 48))
	btn.pressed.connect(_switch_to_app)
	right_group.add_child(btn)

func _nav_button(text: String) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.flat = true
	btn.add_theme_font_override("font", font_inter)
	btn.add_theme_font_size_override("font_size", 16)
	btn.add_theme_color_override("font_color", COLOR_MUTED)
	btn.add_theme_color_override("font_hover_color", COLOR_TEXT)
	btn.add_theme_color_override("font_pressed_color", COLOR_BLUE)
	return btn

func _build_hero() -> void:
	_clear_children(hero_panel)
	_set_panel_texture_bg(hero_panel, _linear_gradient_texture([COLOR_PANEL_TINT, COLOR_WHITE, COLOR_PANEL_TINT], [0.0, 0.5, 1.0]))

	var center := CenterContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hero_panel.add_child(center)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_top", 100)
	margin.add_theme_constant_override("margin_bottom", 120)
	center.add_child(margin)

	var content := HBoxContainer.new()
	content.custom_minimum_size = Vector2(1400, 0)
	content.add_theme_constant_override("separation", 40)
	margin.add_child(content)

	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.size_flags_stretch_ratio = 1.0
	left.custom_minimum_size = Vector2(750, 0) 
	left.add_theme_constant_override("separation", 24)
	content.add_child(left)

	var title_group := VBoxContainer.new()
	title_group.add_theme_constant_override("separation", -12)
	left.add_child(title_group)

	var title_top := Label.new()
	title_top.text = "Generate\nStructural Design"
	title_top.add_theme_font_override("font", font_poppins_bold)
	title_top.add_theme_font_size_override("font_size", 72)
	title_top.add_theme_color_override("font_color", COLOR_TEXT)
	title_group.add_child(title_top)

	var brand_row := HBoxContainer.new()
	brand_row.add_theme_constant_override("separation", 0)
	title_group.add_child(brand_row)

	var title_with := Label.new()
	title_with.text = "with "
	title_with.add_theme_font_override("font", font_poppins_bold)
	title_with.add_theme_font_size_override("font_size", 72)
	title_with.add_theme_color_override("font_color", COLOR_TEXT)
	brand_row.add_child(title_with)

	var pro_label = _brand_label("Pro", COLOR_ORANGE)
	pro_label.add_theme_font_size_override("font_size", 72)
	brand_row.add_child(pro_label)

	var gen_label = _brand_label("Gen", COLOR_BLUE)
	gen_label.add_theme_font_size_override("font_size", 72)
	brand_row.add_child(gen_label)

	var body := Label.new()
	body.text = "ProGen is a closed-loop rule-based procedural generation system that creates optimized 3D structural models and refines them using seismic simulation feedback. Generate, simulate, evaluate, and refine—all in one platform."
	body.add_theme_font_override("font", font_inter)
	body.add_theme_font_size_override("font_size", 20)
	body.add_theme_color_override("font_color", COLOR_MUTED)
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	left.add_child(body)

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 20)
	left.add_child(buttons)

	var get_started_btn := _primary_button("Get Started", Vector2(170, 60))
	get_started_btn.pressed.connect(func(): _scroll_to_node(features_panel))
	buttons.add_child(get_started_btn)

	var learn_more_btn := _outline_button("Learn More", Vector2(170, 60))
	learn_more_btn.pressed.connect(func(): _scroll_to_node(how_panel))
	buttons.add_child(learn_more_btn)

	var right := PanelContainer.new()
	right.theme_type_variation = "PanelContainer"
	right.add_theme_stylebox_override("panel", _style_box(COLOR_WHITE, COLOR_WHITE, 0, 0))
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.size_flags_stretch_ratio = 1.0
	content.add_child(right)

	var hero_image := TextureRect.new()
	hero_image.texture = tex_hero
	hero_image.custom_minimum_size = Vector2(600, 450)
	hero_image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	hero_image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	right.add_child(hero_image)

func _build_features() -> void:
	_clear_children(features_panel)
	features_panel.add_theme_stylebox_override("panel", _style_box(COLOR_WHITE, COLOR_WHITE, 0, 0))
	
	var center := CenterContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	features_panel.add_child(center)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_top", 80)
	margin.add_theme_constant_override("margin_bottom", 80)
	center.add_child(margin)

	var content := VBoxContainer.new()
	content.custom_minimum_size = Vector2(1400, 0)
	content.add_theme_constant_override("separation", 64)
	margin.add_child(content)

	content.add_child(_section_title("Powerful Features", "Everything you need to design and optimize structures"))

	var grid := GridContainer.new()
	grid.columns = 3
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 32)
	grid.add_theme_constant_override("v_separation", 32)
	content.add_child(grid)

	var specs := [
		["Procedural Generation", "Automatically generate beam-column structures based on your specifications.", tex_wrench],
		["Seismic Simulation", "Simulate real-world seismic behavior with customizable magnitude and duration parameters.", tex_earthquakes],
		["Iterative Refinement", "Automatically refine structures through 10 iterations based on seismic performance feedback.", tex_arrows],
		["3D Visualization", "Interactive 3D viewport with full camera controls. Rotate, zoom, and pan.", tex_3d],
		["Performance Metrics", "Track key metrics like drift ratio, safety factor, and material usage.", tex_chart],
		["Design Constraints", "Define custom design constraints and safety thresholds.", tex_design],
	]

	for spec in specs:
		grid.add_child(_feature_card(spec[0], spec[1], spec[2]))

func _build_how_it_works() -> void:
	_clear_children(how_panel)
	_set_panel_texture_bg(how_panel, _linear_gradient_texture([COLOR_PANEL_TINT, COLOR_WHITE], [0.0, 1.0]))
	
	var center := CenterContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	how_panel.add_child(center)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_top", 80)
	margin.add_theme_constant_override("margin_bottom", 80)
	center.add_child(margin)

	var content := VBoxContainer.new()
	content.custom_minimum_size = Vector2(1400, 0)
	content.add_theme_constant_override("separation", 48)
	margin.add_child(content)

	content.add_child(_section_title("How ProGen Works", "A three-stage process for intelligent structural design"))

	var stages_wrapper := Control.new()
	stages_wrapper.custom_minimum_size = Vector2(1400, 320)
	stages_wrapper.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_child(stages_wrapper)

	var stages := HBoxContainer.new()
	stages.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	stages.add_theme_constant_override("separation", 32)
	stages_wrapper.add_child(stages)

	stages.add_child(_stage_card("1", "Input Stage", "Define your structural parameters:", ["Bay X & Y (column spacing)", "Bay widths (dimensions)", "Floor count & story height", "Seismic magnitude & duration"]))
	stages.add_child(_stage_card("2", "Generation & Simulation", "ProGen processes your inputs:", ["Generate beam-column model", "Run seismic simulation", "Evaluate performance", "Detect structural weaknesses"]))
	stages.add_child(_stage_card("3", "Refinement & Output", "Iterative optimization:", ["10 refinement iterations", "Automatic optimization", "Safety threshold validation", "Final optimized structure"]))

func _build_cta() -> void:
	_clear_children(cta_area)
	cta_area.add_theme_stylebox_override("panel", _style_box(COLOR_BLUE_DARK, COLOR_BLUE_DARK, 0, 0))
	
	var center := CenterContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cta_area.add_child(center)

	var cta_margin := MarginContainer.new()
	cta_margin.add_theme_constant_override("margin_top", 80)
	cta_margin.add_theme_constant_override("margin_bottom", 80)
	center.add_child(cta_margin)

	var content := VBoxContainer.new()
	content.alignment = BoxContainer.ALIGNMENT_CENTER
	content.custom_minimum_size = Vector2(1400, 0)
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 24)
	cta_margin.add_child(content)

	content.add_child(_center_label("Ready to Optimize Your Structures?", font_poppins_bold, 36, COLOR_WHITE))
	content.add_child(_center_label("Start designing smarter, safer structures today with ProGen", font_inter, 20, COLOR_CTA_TEXT))

	var btn_center := CenterContainer.new()
	btn_center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	
	var btn := Button.new()
	btn.text = "Launch ProGen App"
	btn.custom_minimum_size = Vector2(253, 60)
	btn.add_theme_font_override("font", font_poppins_bold)
	btn.add_theme_font_size_override("font_size", 18)
	
	var white_btn_style := StyleBoxFlat.new()
	white_btn_style.bg_color = COLOR_WHITE
	set_all_corners(white_btn_style, 8)
	btn.add_theme_stylebox_override("normal", white_btn_style)
	
	var white_btn_hover := StyleBoxFlat.new()
	white_btn_hover.bg_color = COLOR_PANEL_TINT
	set_all_corners(white_btn_hover, 8)
	btn.add_theme_stylebox_override("hover", white_btn_hover)
	btn.add_theme_stylebox_override("pressed", white_btn_hover)
	
	btn.add_theme_color_override("font_color", COLOR_BLUE)
	btn.add_theme_color_override("font_hover_color", COLOR_BLUE)
	btn.add_theme_color_override("font_pressed_color", COLOR_BLUE)
	
	btn.pressed.connect(_switch_to_app)
	btn_center.add_child(btn)
	
	var btn_margin := MarginContainer.new()
	btn_margin.add_theme_constant_override("margin_top", 12)
	content.add_child(btn_margin)
	btn_margin.add_child(btn_center)

func _build_footer() -> void:
	_clear_children(footer_dark)
	footer_dark.add_theme_stylebox_override("panel", _style_box(COLOR_NAVY, COLOR_NAVY, 0, 0))

	var center := CenterContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer_dark.add_child(center)

	var footer_margin := MarginContainer.new()
	footer_margin.add_theme_constant_override("margin_top", 64)
	footer_margin.add_theme_constant_override("margin_bottom", 64)
	center.add_child(footer_margin)

	var content := VBoxContainer.new()
	content.custom_minimum_size = Vector2(1400, 0)
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 48)
	footer_margin.add_child(content)

	var links := HBoxContainer.new()
	links.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	links.add_theme_constant_override("separation", 100)
	content.add_child(links)

	links.add_child(_footer_column("Product", ["Features", "How It Works", "Benefits"]))
	links.add_child(_footer_column("Company", ["About", "Blog", "Contact"]))
	links.add_child(_footer_column("Resources", ["Documentation", "Tutorials", "Support"]))
	links.add_child(_footer_column("Legal", ["Privacy", "Terms", "License"]))

	var divider := ColorRect.new()
	divider.color = COLOR_DARK_BORDER
	divider.custom_minimum_size = Vector2(0, 1)
	content.add_child(divider)

	content.add_child(_center_label("© 2026 ProGen. All rights reserved. GENERATE • OPTIMIZE • BUILD", font_inter, 14, COLOR_LINK))

func _build_app_view() -> void:
	var app_root := VBoxContainer.new()
	app_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	app_root.add_theme_constant_override("separation", 0)
	app_view_container.add_child(app_root)

	# App Navbar spanning full width edge-to-edge
	var app_nav := PanelContainer.new()
	app_nav.custom_minimum_size = Vector2(0, 77)
	var nav_style := _style_box(COLOR_WHITE, COLOR_BORDER, 1, 0, 0)
	nav_style.shadow_size = 0
	app_nav.add_theme_stylebox_override("panel", nav_style)
	app_root.add_child(app_nav)

	var nav_margin := MarginContainer.new()
	nav_margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	nav_margin.add_theme_constant_override("margin_left", 32)
	nav_margin.add_theme_constant_override("margin_right", 32)
	app_nav.add_child(nav_margin)

	var nav_row := HBoxContainer.new()
	nav_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nav_row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	nav_margin.add_child(nav_row)

	var logo := TextureRect.new()
	logo.texture = tex_logo
	logo.custom_minimum_size = Vector2(170, 50)
	logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	logo.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	nav_row.add_child(logo)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nav_row.add_child(spacer)

	var back_btn := Button.new()
	back_btn.text = "← Back to Home"
	back_btn.flat = true
	back_btn.add_theme_font_override("font", font_inter)
	back_btn.add_theme_font_size_override("font_size", 16)
	back_btn.add_theme_color_override("font_color", COLOR_TEXT)
	back_btn.add_theme_color_override("font_hover_color", COLOR_BLUE)
	back_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	back_btn.pressed.connect(_switch_to_landing)
	nav_row.add_child(back_btn)

	# Main App Workspace Body
	var body_panel := PanelContainer.new()
	body_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var body_style := StyleBoxFlat.new()
	body_style.bg_color = COLOR_WHITE
	body_panel.add_theme_stylebox_override("panel", body_style)
	app_root.add_child(body_panel)

	var body_margin := MarginContainer.new()
	body_margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	body_margin.add_theme_constant_override("margin_left", 24)
	body_margin.add_theme_constant_override("margin_right", 24)
	body_margin.add_theme_constant_override("margin_top", 16)
	body_margin.add_theme_constant_override("margin_bottom", 16)
	body_panel.add_child(body_margin)

	var workspace_vbox := VBoxContainer.new()
	workspace_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	workspace_vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	workspace_vbox.add_theme_constant_override("separation", 16)
	body_margin.add_child(workspace_vbox)

	var main_hbox := HBoxContainer.new()
	main_hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	main_hbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main_hbox.add_theme_constant_override("separation", 20)
	workspace_vbox.add_child(main_hbox)

	# Left Sidebar: Inputs & Controls
	var left_scroll := ScrollContainer.new()
	left_scroll.custom_minimum_size = Vector2(300, 0)
	left_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	main_hbox.add_child(left_scroll)

	var left_vbox := VBoxContainer.new()
	left_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left_vbox.add_theme_constant_override("separation", 12)
	left_scroll.add_child(left_vbox)

	left_vbox.add_child(_app_section_heading("STRUCTURAL INPUTS"))
	left_vbox.add_child(_app_input_field("Bay X:"))
	left_vbox.add_child(_app_input_field("Bay Y:"))
	left_vbox.add_child(_app_input_field("Bays Width X:"))
	left_vbox.add_child(_app_input_field("Bays Width Y:"))
	left_vbox.add_child(_app_input_field("Floor Count:"))
	left_vbox.add_child(_app_input_field("Story Height:"))

	var spacer_mid := Control.new()
	spacer_mid.custom_minimum_size = Vector2(0, 8)
	left_vbox.add_child(spacer_mid)

	left_vbox.add_child(_app_section_heading("SEISMIC INPUTS"))
	left_vbox.add_child(_app_input_field("Magnitude (1-10):"))
	left_vbox.add_child(_app_input_field("Duration (10-30 secs):"))

	var gen_btn := Button.new()
	gen_btn.text = "GENERATE STRUCTURE"
	gen_btn.custom_minimum_size = Vector2(0, 44)
	gen_btn.add_theme_font_override("font", font_poppins_bold)
	gen_btn.add_theme_font_size_override("font_size", 13)
	var gen_style := StyleBoxFlat.new()
	gen_style.bg_color = COLOR_BLUE
	set_all_corners(gen_style, 8)
	gen_btn.add_theme_stylebox_override("normal", gen_style)
	gen_btn.add_theme_color_override("font_color", COLOR_WHITE)
	left_vbox.add_child(gen_btn)

	var reset_btn := Button.new()
	reset_btn.text = "RESET STRUCTURE"
	reset_btn.custom_minimum_size = Vector2(0, 44)
	reset_btn.add_theme_font_override("font", font_poppins_bold)
	reset_btn.add_theme_font_size_override("font_size", 13)
	var reset_style := StyleBoxFlat.new()
	reset_style.bg_color = COLOR_NAVY
	set_all_corners(reset_style, 8)
	reset_btn.add_theme_stylebox_override("normal", reset_style)
	reset_btn.add_theme_color_override("font_color", COLOR_WHITE)
	left_vbox.add_child(reset_btn)

	# Center Column: Viewport & Camera Controls Overlay
	var viewport_panel := PanelContainer.new()
	viewport_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	viewport_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var vp_style := StyleBoxFlat.new()
	vp_style.bg_color = Color("#f8fafc")
	vp_style.border_color = COLOR_BORDER
	vp_style.set_border_width_all(1)
	set_all_corners(vp_style, 8)
	viewport_panel.add_theme_stylebox_override("panel", vp_style)
	main_hbox.add_child(viewport_panel)

	var vp_stack := Control.new()
	vp_stack.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	viewport_panel.add_child(vp_stack)

	var vp_label := Label.new()
	vp_label.text = "input parameters to generate structure.."
	vp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vp_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	vp_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vp_label.add_theme_font_override("font", font_inter)
	vp_label.add_theme_font_size_override("font_size", 16)
	vp_label.add_theme_color_override("font_color", COLOR_MUTED)
	vp_stack.add_child(vp_label)

	var controls_panel := PanelContainer.new()
	controls_panel.custom_minimum_size = Vector2(230, 175)
	var ctrl_style := StyleBoxFlat.new()
	ctrl_style.bg_color = COLOR_WHITE
	ctrl_style.border_color = COLOR_BORDER
	ctrl_style.set_border_width_all(1)
	set_all_corners(ctrl_style, 8)
	ctrl_style.content_margin_left = 14
	ctrl_style.content_margin_right = 14
	ctrl_style.content_margin_top = 14
	ctrl_style.content_margin_bottom = 14
	controls_panel.add_theme_stylebox_override("panel", ctrl_style)
	controls_panel.position = Vector2(16, 16)
	vp_stack.add_child(controls_panel)
	
	var ctrl_vbox := VBoxContainer.new()
	ctrl_vbox.add_theme_constant_override("separation", 4)
	var ctrl_title := Label.new()
	ctrl_title.text = "Camera Controls:"
	ctrl_title.add_theme_font_override("font", font_poppins_bold)
	ctrl_title.add_theme_font_size_override("font_size", 13)
	ctrl_title.add_theme_color_override("font_color", COLOR_BLUE)
	ctrl_vbox.add_child(ctrl_title)

	var ctrl_desc := Label.new()
	ctrl_desc.text = "W - forward\nA - left\nS - backward\nD - right\nC - down\nSpace - up\nScroll - zoom\n\nLeft Click - interact\nRight Click - angle control"
	ctrl_desc.add_theme_font_override("font", font_inter)
	ctrl_desc.add_theme_font_size_override("font_size", 11)
	ctrl_desc.add_theme_color_override("font_color", COLOR_MUTED)
	ctrl_vbox.add_child(ctrl_desc)
	controls_panel.add_child(ctrl_vbox)

	# Right Column: Simulation Preview & Iteration Records
	var right_col := VBoxContainer.new()
	right_col.custom_minimum_size = Vector2(260, 0)
	right_col.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right_col.add_theme_constant_override("separation", 16)
	main_hbox.add_child(right_col)

	right_col.add_child(_app_section_heading("SIMULATION PREVIEW"))
	
	var preview_box := PanelContainer.new()
	preview_box.custom_minimum_size = Vector2(0, 140)
	var prev_style := StyleBoxFlat.new()
	prev_style.bg_color = Color("#e0f2fe")
	set_all_corners(prev_style, 8)
	preview_box.add_theme_stylebox_override("panel", prev_style)
	
	var prev_center := CenterContainer.new()
	prev_center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	preview_box.add_child(prev_center)
	
	var icon_lbl := Label.new()
	icon_lbl.text = "👁"
	icon_lbl.add_theme_font_size_override("font_size", 28)
	prev_center.add_child(icon_lbl)
	right_col.add_child(preview_box)

	right_col.add_child(_app_section_heading("ITERATION RECORDS"))
	
	var iter_label := Label.new()
	iter_label.text = "No iterations yet"
	iter_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	iter_label.add_theme_font_override("font", font_inter)
	iter_label.add_theme_font_size_override("font_size", 13)
	iter_label.add_theme_color_override("font_color", COLOR_MUTED)
	right_col.add_child(iter_label)

	# Bottom Terminal Section
	var terminal_panel := PanelContainer.new()
	terminal_panel.custom_minimum_size = Vector2(0, 100)
	var term_style := StyleBoxFlat.new()
	term_style.bg_color = COLOR_WHITE
	term_style.border_color = COLOR_BORDER
	term_style.border_width_top = 1
	terminal_panel.add_theme_stylebox_override("panel", term_style)
	workspace_vbox.add_child(terminal_panel)

	var term_margin := MarginContainer.new()
	term_margin.add_theme_constant_override("margin_left", 0)
	term_margin.add_theme_constant_override("margin_top", 10)
	term_margin.add_theme_constant_override("margin_bottom", 10)
	terminal_panel.add_child(term_margin)

	var term_vbox := VBoxContainer.new()
	term_vbox.add_theme_constant_override("separation", 2)
	term_margin.add_child(term_vbox)

	var term_title := Label.new()
	term_title.text = "TERMINAL"
	term_title.add_theme_font_override("font", font_poppins_bold)
	term_title.add_theme_font_size_override("font_size", 11)
	term_title.add_theme_color_override("font_color", COLOR_BLUE)
	term_vbox.add_child(term_title)

	var line1 := Label.new()
	line1.text = "> welcome to ProGen"
	line1.add_theme_font_override("font", font_inter)
	line1.add_theme_font_size_override("font_size", 12)
	line1.add_theme_color_override("font_color", COLOR_MUTED)
	term_vbox.add_child(line1)

	var line2 := Label.new()
	line2.text = "> ..."
	line2.add_theme_font_override("font", font_inter)
	line2.add_theme_font_size_override("font_size", 12)
	line2.add_theme_color_override("font_color", COLOR_MUTED)
	term_vbox.add_child(line2)

func _app_section_heading(text: String) -> Label:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_override("font", font_poppins_bold)
	lbl.add_theme_font_size_override("font_size", 12)
	lbl.add_theme_color_override("font_color", COLOR_BLUE)
	return lbl

func _app_input_field(label_text: String) -> VBoxContainer:
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	
	var lbl := Label.new()
	lbl.text = label_text
	lbl.add_theme_font_override("font", font_inter)
	lbl.add_theme_font_size_override("font_size", 13)
	lbl.add_theme_color_override("font_color", COLOR_TEXT)
	vbox.add_child(lbl)

	var line_edit := LineEdit.new()
	line_edit.text = "Value"
	line_edit.custom_minimum_size = Vector2(0, 38)
	line_edit.add_theme_font_override("font", font_inter)
	line_edit.add_theme_font_size_override("font_size", 13)
	line_edit.add_theme_color_override("font_color", COLOR_MUTED)
	
	var le_style := StyleBoxFlat.new()
	le_style.bg_color = COLOR_WHITE
	le_style.border_color = COLOR_BORDER
	le_style.set_border_width_all(1)
	set_all_corners(le_style, 6)
	le_style.content_margin_left = 12
	line_edit.add_theme_stylebox_override("normal", le_style)
	line_edit.add_theme_stylebox_override("focus", le_style)
	vbox.add_child(line_edit)

	return vbox

func _feature_card(title: String, description: String, icon: Texture2D) -> PanelContainer:
	var card := PanelContainer.new()
	card.theme_type_variation = "FeatureCard"
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 32)
	margin.add_theme_constant_override("margin_right", 32)
	margin.add_theme_constant_override("margin_top", 32)
	margin.add_theme_constant_override("margin_bottom", 32)
	card.add_child(margin)

	var inner := VBoxContainer.new()
	inner.add_theme_constant_override("separation", 14)
	margin.add_child(inner)

	var icon_rect := TextureRect.new()
	icon_rect.texture = icon
	icon_rect.custom_minimum_size = Vector2(45, 45)
	icon_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	inner.add_child(icon_rect)

	inner.add_child(_left_label(title, font_poppins_bold, 20, COLOR_TEXT))
	inner.add_child(_body_label(description, 16))
	return card

func _stage_card(number: String, title: String, subtitle: String, bullets: Array) -> Control:
	var container := Control.new()
	container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	container.size_flags_vertical = Control.SIZE_EXPAND_FILL

	var card := PanelContainer.new()
	card.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	card.offset_top = 24 
	
	var card_style := StyleBoxFlat.new()
	card_style.bg_color = COLOR_WHITE
	card_style.border_color = COLOR_BLUE
	card_style.set_border_width_all(2)
	set_all_corners(card_style, 12)
	card_style.content_margin_left = 32
	card_style.content_margin_right = 32
	card_style.content_margin_top = 40
	card_style.content_margin_bottom = 32
	card.add_theme_stylebox_override("panel", card_style)
	container.add_child(card)

	var inner := VBoxContainer.new()
	inner.add_theme_constant_override("separation", 12)
	card.add_child(inner)

	inner.add_child(_left_label(title, font_poppins_bold, 20, COLOR_TEXT))
	inner.add_child(_body_label(subtitle, 16))
	
	for bullet in bullets:
		inner.add_child(_bullet_label(bullet))

	var badge := Label.new()
	badge.text = number
	badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	badge.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	badge.add_theme_font_override("font", font_poppins_bold)
	badge.add_theme_font_size_override("font_size", 18)
	badge.add_theme_color_override("font_color", COLOR_WHITE)
	badge.custom_minimum_size = Vector2(48, 48)
	
	var badge_style := StyleBoxFlat.new()
	badge_style.bg_color = COLOR_ORANGE
	set_all_corners(badge_style, 24) 
	badge.add_theme_stylebox_override("normal", badge_style)
	
	badge.position = Vector2(24, 0) 
	container.add_child(badge)

	return container

func _section_title(title: String, subtitle: String) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 10)
	box.add_child(_center_label(title, font_poppins_bold, 36, COLOR_TEXT))
	box.add_child(_center_label(subtitle, font_inter, 18, COLOR_MUTED))
	return box

func _footer_column(title: String, items: Array) -> VBoxContainer:
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 12)
	
	var title_lbl := _left_label(title, font_poppins_bold, 16, COLOR_WHITE)
	column.add_child(title_lbl)
	
	for item in items:
		var item_lbl := _left_label(item, font_inter, 14, COLOR_LINK)
		column.add_child(item_lbl)
		
	return column

func _primary_button(text: String, size: Vector2) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = size
	button.add_theme_font_override("font", font_poppins_bold)
	button.add_theme_font_size_override("font_size", 16)
	button.add_theme_color_override("font_color", COLOR_WHITE)
	button.add_theme_color_override("font_hover_color", COLOR_WHITE)
	button.add_theme_color_override("font_pressed_color", COLOR_WHITE)
	button.theme_type_variation = "Button"
	return button

func _outline_button(text: String, size: Vector2) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = size
	button.add_theme_font_override("font", font_poppins_bold)
	button.add_theme_font_size_override("font_size", 16)
	
	var custom_outline := _style_box(COLOR_WHITE, COLOR_BLUE, 2, 8)
	button.add_theme_stylebox_override("normal", custom_outline)
	
	var custom_hover := _style_box(COLOR_PANEL_TINT, COLOR_BLUE, 2, 8)
	button.add_theme_stylebox_override("hover", custom_hover)
	button.add_theme_stylebox_override("pressed", custom_hover)
	
	button.add_theme_color_override("font_color", COLOR_BLUE)
	button.add_theme_color_override("font_hover_color", COLOR_BLUE)
	button.add_theme_color_override("font_pressed_color", COLOR_BLUE)
	
	return button

func _brand_label(text: String, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_override("font", font_poppins_bold)
	label.add_theme_font_size_override("font_size", 48)
	label.add_theme_color_override("font_color", color)
	return label

func _center_label(text: String, font: Font, size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_override("font", font)
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return label

func _left_label(text: String, font: Font, size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_override("font", font)
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return label

func _body_label(text: String, size: int) -> Label:
	return _left_label(text, font_inter, size, COLOR_MUTED)

func _bullet_label(text: String) -> Label:
	return _left_label("• %s" % text, font_inter, 14, COLOR_MUTED)

func _style_box(bg: Color, border: Color, border_width: int, radius: int, content_margin: int = 0) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.border_color = border
	style.border_width_left = border_width
	style.border_width_top = border_width
	style.border_width_right = border_width
	style.border_width_bottom = border_width
	style.corner_radius_top_left = radius
	style.corner_radius_top_right = radius
	style.corner_radius_bottom_right = radius
	style.corner_radius_bottom_left = radius
	style.content_margin_left = float(content_margin)
	style.content_margin_right = float(content_margin)
	style.content_margin_top = float(content_margin)
	style.content_margin_bottom = float(content_margin)
	return style

func set_all_corners(stylebox: StyleBoxFlat, radius: int) -> void:
	stylebox.corner_radius_top_left = radius
	stylebox.corner_radius_top_right = radius
	stylebox.corner_radius_bottom_right = radius
	stylebox.corner_radius_bottom_left = radius

func _linear_gradient_texture(colors: Array[Color], offsets: Array[float]) -> Texture2D:
	var gradient := Gradient.new()
	for i in range(colors.size()):
		gradient.add_point(offsets[i], colors[i])
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill_from = Vector2(0, 0)
	texture.fill_to = Vector2(1, 1)
	return texture

func _load_font(path: String) -> FontFile:
	var font := FontFile.new()
	font.load_dynamic_font(path)
	return font

func _load_texture(path: String) -> Texture2D:
	return load(path) as Texture2D

func _clear_children(node: Node) -> void:
	for child in node.get_children():
		node.remove_child(child)
		child.queue_free()

func _set_panel_texture_bg(panel: PanelContainer, texture: Texture2D) -> void:
	var style := StyleBoxTexture.new()
	style.texture = texture
	panel.add_theme_stylebox_override("panel", style)