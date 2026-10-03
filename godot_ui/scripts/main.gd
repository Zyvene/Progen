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

const RULE_NAMES: Array[String] = [
	"Yield Stress", "Buckling", "Rupture Strain", "Floor IDR",
	"Soft-Story", "Mid-Story IDR Concentration", "Directional Instability",
	"Roof Displacement", "Torsional Irregularity", "Mean Stress",
]

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

var bay_x_input: LineEdit
var bay_y_input: LineEdit
var bay_width_x_input: LineEdit
var bay_width_y_input: LineEdit
var floor_count_input: LineEdit
var story_height_input: LineEdit
var magnitude_input: LineEdit
var duration_input: LineEdit

var rule_preview_dropdown: OptionButton

var vp_label: Label
var term_vbox: VBoxContainer
var term_scroll: ScrollContainer
var terminal_panel: PanelContainer
var structure_display: StaticStructureView
var structure_camera: FreeCamera

var has_structure: bool = false
var current_params: Dictionary = {}
var current_topo: Dictionary = {}
var python_simulation_pid: int = -1
var python_simulation_running: bool = false
var python_simulation_started_ms: int = 0
var python_simulation_last_heartbeat_ms: int = 0
var current_run_dir: String = ""

var iteration_label: Label
var iteration_list: VBoxContainer
var iterations_shown: int = 0
var last_poll_ms: int = 0
var clean_runs_button: Button
var clean_runs_dialog: ConfirmationDialog

const SHAKE_DISPLAY_FRACTION := 0.04
const SHAKE_MIN_PEAK_M := 0.001
const SHAKE_MAX_MAGNIFICATION := 200.0
const LIVE_POLL_MS := 100

var shake_label: Label
var live_iteration: int = -1
var live_active: bool = false
var live_target: PackedFloat32Array = PackedFloat32Array()
var live_current: PackedFloat32Array = PackedFloat32Array()
var live_peak: float = 0.0
var live_magnification: float = 1.0
var live_dropped: Dictionary = {}
var live_carry_peak: float = 0.0

var preview_view: StaticStructureView
var preview_camera: Camera3D
var preview_hint: Label
var preview_run_dir: String = ""
var preview_index: int = -1
var preview_frames: Array = []
var preview_frame_dt: float = 0.1
var preview_time: float = 0.0
var preview_playing: bool = false
var preview_magnification: float = 1.0
var preview_ruptures: Array = []
var preview_next_rupture: int = 0
var preview_collapse_time = null
var preview_holding: bool = false

var terminal_drag_active: bool = false
var terminal_drag_start_mouse_y: float = 0.0
var terminal_drag_start_height: float = 0.0

func _process(delta: float) -> void:
	_update_live_shake(delta)
	_update_preview_playback(delta)
	if not python_simulation_running:
		return
	if not OS.is_process_running(python_simulation_pid):
		python_simulation_running = false
		clean_runs_button.disabled = false
		_poll_run()
		_stop_live_shake()
		_finish_run()
		return
	var now_ms := Time.get_ticks_msec()
	if now_ms - last_poll_ms >= LIVE_POLL_MS:
		last_poll_ms = now_ms
		_poll_run()
	if now_ms - python_simulation_last_heartbeat_ms >= 10000:
		python_simulation_last_heartbeat_ms = now_ms
		var elapsed_s := int((now_ms - python_simulation_started_ms) / 1000.0)
		_log_terminal("... OpenSeesPy NLTHA still running (%ds elapsed)" % elapsed_s)

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
	_load_w_sections()

func _load_w_sections() -> void:
	var path := ProjectSettings.globalize_path("res://../w_sections.json")
	if not FileAccess.file_exists(path):
		_log_terminal("ERROR: w_sections.json not found next to simulation.py")
		return
	var file := FileAccess.open(path, FileAccess.READ)
	var parsed = JSON.parse_string(file.get_as_text())
	file.close()
	if not parsed is Dictionary or not parsed.has("sections"):
		_log_terminal("ERROR: w_sections.json is not valid")
		return
	structure_display.set_sections(parsed["sections"])
	preview_view.set_sections(parsed["sections"])

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
	logo.custom_minimum_size = Vector2(200, 150)
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
	logo.custom_minimum_size = Vector2(200, 150)
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
	bay_x_input = _app_input_field(left_vbox, "Bay X (1-10):", "3")
	bay_y_input = _app_input_field(left_vbox, "Bay Y (1-10):", "3")
	bay_width_x_input = _app_input_field(left_vbox, "Bays Width X, m (3-9):", "6")
	bay_width_y_input = _app_input_field(left_vbox, "Bays Width Y, m (3-9):", "6")
	floor_count_input = _app_input_field(left_vbox, "Floor Count (1-10):", "4")
	story_height_input = _app_input_field(left_vbox, "Story Height, m (3-5):", "3.5")

	var spacer_mid := Control.new()
	spacer_mid.custom_minimum_size = Vector2(0, 8)
	left_vbox.add_child(spacer_mid)

	left_vbox.add_child(_app_section_heading("SEISMIC INPUTS"))
	magnitude_input = _app_input_field(left_vbox, "Magnitude (1-10):", "5")
	duration_input = _app_input_field(left_vbox, "Duration, secs (10-30):", "15")

	var gen_btn := Button.new()
	gen_btn.text = "GENERATE STRUCTURE"
	gen_btn.custom_minimum_size = Vector2(0, 44)
	gen_btn.focus_mode = Control.FOCUS_NONE
	gen_btn.add_theme_font_override("font", font_poppins_bold)
	gen_btn.add_theme_font_size_override("font_size", 18)
	var gen_style := StyleBoxFlat.new()
	gen_style.bg_color = COLOR_BLUE
	set_all_corners(gen_style, 8)
	gen_btn.add_theme_stylebox_override("normal", gen_style)
	gen_btn.add_theme_color_override("font_color", COLOR_WHITE)
	gen_btn.pressed.connect(_on_generate_pressed)
	left_vbox.add_child(gen_btn)

	var sim_btn := Button.new()
	sim_btn.text = "RUN SIMULATION"
	sim_btn.custom_minimum_size = Vector2(0, 44)
	sim_btn.focus_mode = Control.FOCUS_NONE
	sim_btn.add_theme_font_override("font", font_poppins_bold)
	sim_btn.add_theme_font_size_override("font_size", 18)
	var sim_style := StyleBoxFlat.new()
	sim_style.bg_color = COLOR_ORANGE
	set_all_corners(sim_style, 8)
	sim_btn.add_theme_stylebox_override("normal", sim_style)
	sim_btn.add_theme_color_override("font_color", COLOR_WHITE)
	sim_btn.pressed.connect(_on_simulate_pressed)
	left_vbox.add_child(sim_btn)

	var reset_btn := Button.new()
	reset_btn.text = "RESET STRUCTURE"
	reset_btn.custom_minimum_size = Vector2(0, 44)
	reset_btn.focus_mode = Control.FOCUS_NONE
	reset_btn.add_theme_font_override("font", font_poppins_bold)
	reset_btn.add_theme_font_size_override("font_size", 18)
	var reset_style := StyleBoxFlat.new()
	reset_style.bg_color = COLOR_NAVY
	set_all_corners(reset_style, 8)
	reset_btn.add_theme_stylebox_override("normal", reset_style)
	reset_btn.add_theme_color_override("font_color", COLOR_WHITE)
	reset_btn.pressed.connect(_on_reset_pressed)
	left_vbox.add_child(reset_btn)

	rule_preview_dropdown = OptionButton.new()
	rule_preview_dropdown.custom_minimum_size = Vector2(0, 40)
	rule_preview_dropdown.focus_mode = Control.FOCUS_NONE
	rule_preview_dropdown.add_item("Preview a rule fix...", 0)
	for i in range(RULE_NAMES.size()):
		rule_preview_dropdown.add_item("Rule %d: %s" % [i + 1, RULE_NAMES[i]], i + 1)
	rule_preview_dropdown.select(0)
	rule_preview_dropdown.visible = false
	rule_preview_dropdown.item_selected.connect(_on_rule_preview_selected)
	left_vbox.add_child(rule_preview_dropdown)

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

	_build_viewport_3d(vp_stack)

	vp_label = Label.new()
	vp_label.text = "input parameters to generate structure.."
	vp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vp_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	vp_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vp_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
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
	ctrl_title.add_theme_font_size_override("font_size", 18)
	ctrl_title.add_theme_color_override("font_color", COLOR_BLUE)
	ctrl_vbox.add_child(ctrl_title)

	var ctrl_desc := Label.new()
	ctrl_desc.text = "W - forward\nA - left\nS - backward\nD - right\nC - down\nSpace - up\nScroll - zoom\n\nLeft Click - interact\nRight Click - angle control"
	ctrl_desc.add_theme_font_override("font", font_inter)
	ctrl_desc.add_theme_font_size_override("font_size", 16)
	ctrl_desc.add_theme_color_override("font_color", COLOR_MUTED)
	ctrl_vbox.add_child(ctrl_desc)
	controls_panel.add_child(ctrl_vbox)

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

	_build_preview_3d(preview_box)
	right_col.add_child(preview_box)

	right_col.add_child(_app_section_heading("ITERATION RECORDS"))

	var iter_label := Label.new()
	iter_label.text = "No iterations yet"
	iter_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	iter_label.add_theme_font_override("font", font_inter)
	iter_label.add_theme_font_size_override("font_size", 18)
	iter_label.add_theme_color_override("font_color", COLOR_MUTED)
	right_col.add_child(iter_label)
	iteration_label = iter_label
	iter_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	iter_label.add_theme_font_size_override("font_size", 14)

	var iteration_scroll := ScrollContainer.new()
	iteration_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	iteration_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	right_col.add_child(iteration_scroll)
	iteration_list = VBoxContainer.new()
	iteration_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	iteration_list.add_theme_constant_override("separation", 6)
	iteration_scroll.add_child(iteration_list)

	clean_runs_button = Button.new()
	clean_runs_button.text = "Clean Previous Runs"
	clean_runs_button.custom_minimum_size = Vector2(0, 32)
	clean_runs_button.focus_mode = Control.FOCUS_NONE
	clean_runs_button.add_theme_font_override("font", font_inter)
	clean_runs_button.add_theme_font_size_override("font_size", 13)
	clean_runs_button.add_theme_color_override("font_color", COLOR_LINK)
	clean_runs_button.add_theme_color_override("font_hover_color", COLOR_MUTED)
	clean_runs_button.add_theme_color_override("font_disabled_color", COLOR_BORDER)
	var clean_style := _style_box(COLOR_WHITE, COLOR_BORDER, 1, 6)
	clean_runs_button.add_theme_stylebox_override("normal", clean_style)
	clean_runs_button.add_theme_stylebox_override("hover", _style_box(COLOR_WHITE, COLOR_LINK, 1, 6))
	clean_runs_button.add_theme_stylebox_override("pressed", clean_style)
	clean_runs_button.add_theme_stylebox_override("disabled", clean_style)
	clean_runs_button.pressed.connect(_on_clean_runs_pressed)
	right_col.add_child(clean_runs_button)

	clean_runs_dialog = ConfirmationDialog.new()
	clean_runs_dialog.title = "Clean Previous Runs"
	clean_runs_dialog.ok_button_text = "Delete"
	clean_runs_dialog.confirmed.connect(_on_clean_runs_confirmed)
	app_view_container.add_child(clean_runs_dialog)

	var terminal_drag_handle := ColorRect.new()
	terminal_drag_handle.color = COLOR_BORDER
	terminal_drag_handle.custom_minimum_size = Vector2(0, 6)
	terminal_drag_handle.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	terminal_drag_handle.mouse_default_cursor_shape = Control.CURSOR_VSIZE
	terminal_drag_handle.mouse_filter = Control.MOUSE_FILTER_STOP
	terminal_drag_handle.gui_input.connect(_on_terminal_drag_handle_input)
	workspace_vbox.add_child(terminal_drag_handle)

	terminal_panel = PanelContainer.new()
	terminal_panel.custom_minimum_size = Vector2(0, 150)
	terminal_panel.size_flags_vertical = Control.SIZE_FILL
	terminal_panel.clip_contents = true
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

	term_scroll = ScrollContainer.new()
	term_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	term_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	term_margin.add_child(term_scroll)

	term_vbox = VBoxContainer.new()
	term_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	term_vbox.add_theme_constant_override("separation", 2)
	term_scroll.add_child(term_vbox)

	_reset_terminal()

func _app_section_heading(text: String) -> Label:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_override("font", font_poppins_bold)
	lbl.add_theme_font_size_override("font_size", 12)
	lbl.add_theme_color_override("font_color", COLOR_BLUE)
	return lbl

func _app_input_field(parent: Control, label_text: String, default_value: String) -> LineEdit:
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)

	var lbl := Label.new()
	lbl.text = label_text
	lbl.add_theme_font_override("font", font_inter)
	lbl.add_theme_font_size_override("font_size", 18)
	lbl.add_theme_color_override("font_color", COLOR_TEXT)
	vbox.add_child(lbl)

	var line_edit := LineEdit.new()
	line_edit.text = default_value
	line_edit.custom_minimum_size = Vector2(0, 38)
	line_edit.add_theme_font_override("font", font_inter)
	line_edit.add_theme_font_size_override("font_size", 18)
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

	parent.add_child(vbox)
	return line_edit

func _build_viewport_3d(parent: Control) -> void:
	var svc := SubViewportContainer.new()
	svc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	svc.stretch = true
	parent.add_child(svc)

	var sub_viewport := SubViewport.new()
	sub_viewport.own_world_3d = true
	svc.add_child(sub_viewport)

	_add_scene_lighting(sub_viewport, Color("#eef2f7"))

	structure_camera = FreeCamera.new()
	structure_camera.far = 500.0
	sub_viewport.add_child(structure_camera)
	structure_camera.current = true
	structure_camera.position = Vector3(20, 16, 24)
	structure_camera.look_at(Vector3(10, 6, 10), Vector3.UP)
	structure_camera.sync_look_from_rotation()

	structure_display = StaticStructureView.new()
	sub_viewport.add_child(structure_display)

	shake_label = Label.new()
	shake_label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	shake_label.offset_left = 12
	shake_label.offset_top = -36
	shake_label.offset_bottom = -12
	shake_label.add_theme_font_override("font", font_inter)
	shake_label.add_theme_font_size_override("font_size", 14)
	shake_label.add_theme_color_override("font_color", COLOR_TEXT)
	shake_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	shake_label.visible = false
	parent.add_child(shake_label)

func _add_scene_lighting(sub_viewport: SubViewport, background: Color) -> void:
	var env_node := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = background
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("#ffffff")
	environment.ambient_light_energy = 0.6
	env_node.environment = environment
	sub_viewport.add_child(env_node)

	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-50, -30, 0)
	light.light_energy = 1.1
	sub_viewport.add_child(light)

func _build_preview_3d(parent: Control) -> void:
	var svc := SubViewportContainer.new()
	svc.stretch = true
	svc.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	svc.gui_input.connect(_on_preview_input)
	parent.add_child(svc)

	var sub_viewport := SubViewport.new()
	sub_viewport.own_world_3d = true
	sub_viewport.handle_input_locally = false
	svc.add_child(sub_viewport)
	_add_scene_lighting(sub_viewport, Color("#e0f2fe"))

	preview_camera = Camera3D.new()
	preview_camera.far = 500.0
	sub_viewport.add_child(preview_camera)
	preview_camera.current = true

	preview_view = StaticStructureView.new()
	sub_viewport.add_child(preview_view)

	preview_hint = Label.new()
	preview_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	preview_hint.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	preview_hint.size_flags_vertical = Control.SIZE_SHRINK_END
	preview_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	preview_hint.add_theme_font_override("font", font_inter)
	preview_hint.add_theme_font_size_override("font_size", 12)
	preview_hint.add_theme_color_override("font_color", COLOR_MUTED)
	preview_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	preview_hint.text = "Select an iteration to preview its seismic performance"
	parent.add_child(preview_hint)

func _validate_inputs() -> Dictionary:
	var errors: Array[String] = []
	var params := {}

	var bay_x := int(bay_x_input.text)
	if bay_x < 1 or bay_x > 10:
		errors.append("Bay X must be between 1 and 10 (got %s)" % bay_x_input.text)
	params["bay_count_x"] = bay_x

	var bay_y := int(bay_y_input.text)
	if bay_y < 1 or bay_y > 10:
		errors.append("Bay Y must be between 1 and 10 (got %s)" % bay_y_input.text)
	params["bay_count_y"] = bay_y

	var bay_width_x := float(bay_width_x_input.text)
	if bay_width_x < 3.0 or bay_width_x > 9.0:
		errors.append("Bay Width X must be between 3 and 9 m (got %s)" % bay_width_x_input.text)
	params["bay_width_x"] = bay_width_x

	var bay_width_y := float(bay_width_y_input.text)
	if bay_width_y < 3.0 or bay_width_y > 9.0:
		errors.append("Bay Width Y must be between 3 and 9 m (got %s)" % bay_width_y_input.text)
	params["bay_width_y"] = bay_width_y

	var floor_count := int(floor_count_input.text)
	if floor_count < 1 or floor_count > 10:
		errors.append("Floor Count must be between 1 and 10 (got %s)" % floor_count_input.text)
	params["floor_count"] = floor_count

	var story_height := float(story_height_input.text)
	if story_height < 3.0 or story_height > 5.0:
		errors.append("Story Height must be between 3 and 5 m (got %s)" % story_height_input.text)
	params["story_height"] = story_height

	var magnitude := float(magnitude_input.text)
	if magnitude < 1.0 or magnitude > 10.0:
		errors.append("Magnitude must be between 1 and 10 (got %s)" % magnitude_input.text)
	params["magnitude"] = magnitude

	var duration := float(duration_input.text)
	if duration < 10.0 or duration > 30.0:
		errors.append("Duration must be between 10 and 30 secs (got %s)" % duration_input.text)
	params["duration"] = duration

	return {"ok": errors.is_empty(), "params": params, "errors": errors}

func _log_terminal(text: String) -> void:
	if term_vbox == null:
		return
	var line := Label.new()
	line.text = "> " + text
	line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.add_theme_font_override("font", font_inter)
	line.add_theme_font_size_override("font_size", 18)
	line.add_theme_color_override("font_color", COLOR_MUTED)
	term_vbox.add_child(line)
	_scroll_terminal_to_bottom()

func _scroll_terminal_to_bottom() -> void:
	if term_scroll == null:
		return
	await get_tree().process_frame
	term_scroll.scroll_vertical = int(term_scroll.get_v_scroll_bar().max_value)

func _reset_terminal() -> void:
	if term_vbox == null:
		return
	_clear_children(term_vbox)
	var term_title := Label.new()
	term_title.text = "TERMINAL"
	term_title.add_theme_font_override("font", font_poppins_bold)
	term_title.add_theme_font_size_override("font_size", 18)
	term_title.add_theme_color_override("font_color", COLOR_BLUE)
	term_vbox.add_child(term_title)
	_log_terminal("welcome to ProGen")
	_log_terminal("...")

func _on_terminal_drag_handle_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			terminal_drag_active = true
			terminal_drag_start_mouse_y = event.global_position.y
			terminal_drag_start_height = terminal_panel.custom_minimum_size.y
		else:
			terminal_drag_active = false
	elif event is InputEventMouseMotion and terminal_drag_active:
		var delta_y: float = event.global_position.y - terminal_drag_start_mouse_y
		var new_height: float = terminal_drag_start_height - delta_y
		var max_height: float = max(150.0, get_viewport_rect().size.y - 300.0)
		terminal_panel.custom_minimum_size.y = clamp(new_height, 90.0, max_height)

func _on_generate_pressed() -> void:
	var validation := _validate_inputs()
	if not validation["ok"]:
		for e in validation["errors"]:
			_log_terminal("ERROR: %s" % e)
		return

	if not structure_display.has_sections():
		_log_terminal("ERROR: W-shape sections are not loaded; cannot draw the structure")
		return

	var params: Dictionary = validation["params"]
	var topo := StructureGenerator.generate(params)
	var check := StructureValidator.validate(params, topo)
	if not check["ok"]:
		for e in check["errors"]:
			_log_terminal("ERROR: %s" % e)
		return

	current_params = params
	current_topo = topo
	has_structure = true
	vp_label.visible = false
	_stop_live_shake()
	_clear_preview()
	structure_display.build(topo)
	_frame_camera_on_structure(params)
	rule_preview_dropdown.select(0)
	rule_preview_dropdown.visible = true

	var nodes: Dictionary = topo["nodes"]
	_log_terminal(
		"generated %d nodes, %d columns, %d beams (all members %s)" % [
			nodes.size(), (topo["columns"] as Array).size(), (topo["beams"] as Array).size(),
			StaticStructureView.STARTING_SECTION
		]
	)
	for w in check["warnings"]:
		_log_terminal("WARNING: %s" % w)

func _frame_camera_on_structure(params: Dictionary) -> void:
	if structure_camera == null:
		return
	var width_x: float = params["bay_count_x"] * params["bay_width_x"]
	var width_z: float = params["bay_count_y"] * params["bay_width_y"]
	var height_y: float = params["floor_count"] * params["story_height"]
	var extents := Vector3(width_x, height_y, width_z)
	var center := extents / 2.0

	var bounding_radius := extents.length() / 2.0
	var half_fov_rad := deg_to_rad(structure_camera.fov) / 2.0
	var distance: float = max(bounding_radius / sin(half_fov_rad) * 1.35, 6.0)

	var direction := Vector3(1.0, 0.7, 1.0).normalized()
	structure_camera.global_position = center + direction * distance
	structure_camera.look_at(center, Vector3.UP)
	structure_camera.sync_look_from_rotation()

func _on_simulate_pressed() -> void:
	if not has_structure:
		_log_terminal("ERROR: generate a structure before running the simulation")
		return

	var validation := _validate_inputs()
	if not validation["ok"]:
		for e in validation["errors"]:
			_log_terminal("ERROR: %s" % e)
		return

	if python_simulation_running:
		_log_terminal("OpenSeesPy NLTHA is already running")
		return

	var sim_params: Dictionary = current_params.duplicate()
	sim_params["magnitude"] = validation["params"]["magnitude"]
	sim_params["duration"] = validation["params"]["duration"]

	rule_preview_dropdown.select(0)
	rule_preview_dropdown.visible = false
	_clear_preview()
	structure_display.build(current_topo)

	var run_dir := _create_run_dir()
	if run_dir == "":
		_log_terminal("ERROR: could not create a run folder under runs/")
		return
	if not _export_topology_for_python(sim_params, run_dir):
		return
	_clear_iteration_list()
	current_run_dir = run_dir
	_start_python_nltha(sim_params, run_dir)
	_log_terminal(
		"running seismic simulation: magnitude %.1f, duration %.1fs" % [
			sim_params["magnitude"], sim_params["duration"]
		]
	)

func _runs_root() -> String:
	return ProjectSettings.globalize_path("res://..").path_join("runs")

func _create_run_dir() -> String:
	var stamp := Time.get_datetime_string_from_system().replace("T", "_").replace(":", "-")
	var base := _runs_root().path_join("run_" + stamp)
	var run_dir := base
	var suffix := 2
	while DirAccess.dir_exists_absolute(run_dir):
		run_dir = "%s_%d" % [base, suffix]
		suffix += 1
	if DirAccess.make_dir_recursive_absolute(run_dir) != OK:
		return ""
	return run_dir

func _export_topology_for_python(params: Dictionary, run_dir: String) -> bool:
	var topology := {
		"building_id": 9001,
		"units": "m",
		"floor_count": params["floor_count"],
		"story_height": params["story_height"],
		"bay_count_x": params["bay_count_x"],
		"bay_width_x": params["bay_width_x"],
		"bay_count_y": params["bay_count_y"],
		"bay_width_y": params["bay_width_y"],
		"floor_load_kpa": 6.0,
		"roof_load_kpa": 3.0,
		"magnitude": params["magnitude"],
		"duration": params["duration"],
	}
	var output_path := run_dir.path_join("input.json")
	var file := FileAccess.open(output_path, FileAccess.WRITE)
	if file == null:
		_log_terminal("ERROR: could not write input.json for OpenSeesPy")
		return false
	file.store_string(JSON.stringify(topology, "  ") + "\n")
	file.close()
	_log_terminal("run folder: runs/%s" % run_dir.get_file())
	return true

func _start_python_nltha(params: Dictionary, run_dir: String) -> void:
	var project_root := ProjectSettings.globalize_path("res://..")
	var python_path := project_root.path_join(".venv-1/Scripts/python.exe")
	var script_path := project_root.path_join("simulation.py")
	var topology_path := run_dir.path_join("input.json")
	var args := PackedStringArray([
		script_path,
		"--topology", topology_path,
		"--duration", str(params["duration"]),
		"--magnitude", str(params["magnitude"]),
		"--run-dir", run_dir,
	])
	python_simulation_pid = OS.create_process(python_path, args)
	if python_simulation_pid == -1:
		_log_terminal("ERROR: could not start Python/OpenSeesPy")
		return
	python_simulation_running = true
	clean_runs_button.disabled = true
	python_simulation_started_ms = Time.get_ticks_msec()
	python_simulation_last_heartbeat_ms = python_simulation_started_ms
	_log_terminal("closed-loop run started: Iteration 0, then feedback and re-simulation automatically")
	_log_terminal("(larger structures can take a minute or more per iteration -- iterations appear on the right as they finish)")
	iterations_shown = 0
	live_iteration = -1
	live_peak = 0.0
	live_carry_peak = 0.0
	live_magnification = 0.0
	last_poll_ms = 0
	iteration_label.text = "Starting..."

func _read_json(path: String):
	if not FileAccess.file_exists(path):
		return null
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return null
	var parsed = JSON.parse_string(file.get_as_text())
	file.close()
	return parsed

func _poll_run() -> void:
	if current_run_dir == "":
		return
	while DirAccess.dir_exists_absolute(current_run_dir.path_join("iteration_%d" % iterations_shown)):
		var record = _read_json(current_run_dir.path_join("iteration_%d" % iterations_shown).path_join("record.json"))
		if not record is Dictionary:
			return
		if iterations_shown == live_iteration:
			live_carry_peak = live_peak if record.get("collapse_phase") == null else live_carry_peak
			_stop_live_shake()
		_add_iteration_entry(iterations_shown, record)
		_show_iteration(current_run_dir, iterations_shown, record)
		iterations_shown += 1
	var progress = _read_json(current_run_dir.path_join("progress.json"))
	if progress is Dictionary and python_simulation_running:
		var phase: String = progress.get("phase", "")
		var total := int(progress.get("total_steps", 0))
		var iteration := int(progress.get("iteration", 0))
		if phase == "simulating" and total > 0:
			iteration_label.text = "Iteration %d: simulating step %d/%d" % [
				iteration, int(progress.get("step", 0)), total]
		elif phase == "feedback":
			iteration_label.text = "Iteration %d: applying feedback rules" % iteration
		else:
			iteration_label.text = "Iteration %d: %s" % [iteration, phase]
		if phase == "simulating" and progress.get("frame") is Array and iteration >= iterations_shown and has_structure:
			if iteration != live_iteration:
				_begin_live_shake(iteration)
			if live_active and iteration == live_iteration:
				_set_live_target(progress["frame"], float(progress.get("time_s", 0.0)), progress.get("ruptures", []))
		elif live_active and phase != "simulating":
			_stop_live_shake()

func _shake_magnification(peak_m: float) -> float:
	var height: float = float(current_params.get("floor_count", 1)) * float(current_params.get("story_height", 3.0))
	return clamp(SHAKE_DISPLAY_FRACTION * height / max(peak_m, SHAKE_MIN_PEAK_M), 1.0, SHAKE_MAX_MAGNIFICATION)

func _frame_peak(values: PackedFloat32Array) -> float:
	var peak := 0.0
	for i in range(values.size() / 2):
		peak = max(peak, Vector2(values[2 * i], values[2 * i + 1]).length())
	return peak

func _begin_live_shake(iteration: int) -> void:
	var live = _read_json(current_run_dir.path_join("live_state.json"))
	if not live is Dictionary or int(live.get("iteration", -1)) != iteration:
		return
	var state = live.get("model_state")
	structure_display.build_state(current_topo, state if state is Dictionary else {}, live.get("highlighted", []))
	structure_display.set_frame_nodes(live.get("node_keys", []))
	live_iteration = iteration
	live_active = true
	live_dropped = {}
	live_peak = live_carry_peak
	live_magnification = 0.0
	live_target = PackedFloat32Array()
	live_current = PackedFloat32Array()

func _set_live_target(frame: Array, time_s: float, ruptures: Array) -> void:
	live_target = PackedFloat32Array(frame)
	if live_current.size() != live_target.size():
		live_current = PackedFloat32Array()
		live_current.resize(live_target.size())
	live_peak = max(live_peak, _frame_peak(live_target))
	var magnification := _shake_magnification(live_peak)
	live_magnification = magnification if live_magnification <= 0.0 else min(live_magnification, magnification)
	for rupture in ruptures:
		var key := str(rupture.get("nodes", []))
		if not live_dropped.has(key):
			live_dropped[key] = true
			structure_display.drop_member(rupture.get("nodes", []))
	var rupture_note := ""
	if not live_dropped.is_empty():
		rupture_note = "   %d member(s) past rupture strain" % live_dropped.size()
	shake_label.text = "Iteration %d live shake   t = %.1f s   displacements x%.0f%s" % [live_iteration, time_s, live_magnification, rupture_note]
	shake_label.visible = true

func _update_live_shake(delta: float) -> void:
	if not live_active:
		return
	structure_display.update_falls(delta)
	if live_target.is_empty() or live_current.size() != live_target.size():
		return
	var blend := 1.0 - exp(-delta / 0.08)
	for i in range(live_current.size()):
		live_current[i] = lerp(live_current[i], live_target[i], blend)
	structure_display.apply_frame(live_current, live_magnification)

func _stop_live_shake() -> void:
	if live_active:
		structure_display.reset_frame()
	live_active = false
	live_target = PackedFloat32Array()
	live_current = PackedFloat32Array()
	if shake_label != null:
		shake_label.visible = false

func _finish_run() -> void:
	var reuse = _read_json(current_run_dir.path_join("reuse.json"))
	if reuse is Dictionary and reuse.has("reuse_run"):
		var existing: String = str(reuse["reuse_run"]).replace("\\", "/")
		_delete_dir_recursive(current_run_dir)
		current_run_dir = existing
		_clear_iteration_list()
		_log_terminal("loaded existing run runs/%s (identical inputs and tool version) -- no simulation needed" % existing.get_file())
		_poll_run()
	var summary = _read_json(current_run_dir.path_join("run_summary.json"))
	if summary is Dictionary:
		var replaced: Array = summary.get("replaced_runs", [])
		if not replaced.is_empty() and not (reuse is Dictionary):
			_log_terminal("replaced %d earlier run(s) with identical inputs (older tool version or incomplete): %s" % [
				replaced.size(), ", ".join(PackedStringArray(replaced))])
	if not summary is Dictionary:
		_log_terminal("ERROR: the run finished without run_summary.json")
		iteration_label.text = "Run failed"
		return
	if summary.get("status", "") == "error":
		_log_terminal("ERROR: %s" % summary.get("error", "unknown error"))
	elif summary.get("status", "") != "completed":
		_log_terminal("ERROR: the simulation process stopped unexpectedly after %d iteration(s)" % int(summary.get("iterations_completed", 0)))
		iteration_label.text = "Stopped unexpectedly after %d iteration(s)" % int(summary.get("iterations_completed", 0))
		return
	_log_terminal("===== run complete: %d iteration(s) saved, stopped because: %s, final result: %s =====" % [
		int(summary.get("iterations_completed", 0)), str(summary.get("stop_reason", "unknown")),
		str(summary.get("final_status", "?"))
	])
	iteration_label.text = "Completed: %d iteration(s) -- %s" % [
		int(summary.get("iterations_completed", 0)), str(summary.get("stop_reason", "unknown"))]

func _add_iteration_entry(index: int, record: Dictionary) -> void:
	var rules: Array[String] = []
	var evaluation = record.get("evaluation")
	if evaluation is Dictionary:
		for entry in evaluation.get("triggered_rules", []):
			rules.append(str(int(entry.get("rule", 0))))
	var button := Button.new()
	button.text = "Iteration %d  %s%s" % [index, record.get("overall_status", "?"),
		("  (rules " + ", ".join(rules) + ")") if not rules.is_empty() else ""]
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_font_override("font", font_inter)
	button.add_theme_font_size_override("font_size", 14)
	button.add_theme_color_override("font_color", COLOR_TEXT)
	button.add_theme_color_override("font_hover_color", COLOR_BLUE)
	button.add_theme_stylebox_override("normal", _style_box(COLOR_PANEL_TINT, COLOR_BORDER, 1, 6, 6))
	button.add_theme_stylebox_override("hover", _style_box(COLOR_PANEL_TINT, COLOR_BLUE, 1, 6, 6))
	button.add_theme_stylebox_override("pressed", _style_box(COLOR_PANEL_TINT, COLOR_BLUE, 1, 6, 6))
	var run_dir := current_run_dir
	button.pressed.connect(func(): _on_iteration_pressed(run_dir, index))
	iteration_list.add_child(button)

func _on_iteration_pressed(run_dir: String, index: int) -> void:
	var record = _read_json(run_dir.path_join("iteration_%d" % index).path_join("record.json"))
	if not record is Dictionary:
		_log_terminal("ERROR: iteration %d is no longer on disk" % index)
		return
	_show_iteration(run_dir, index, record)

func _show_iteration(run_dir: String, index: int, record: Dictionary) -> void:
	if has_structure:
		var highlighted: Array = []
		var applied = record.get("applied_feedback")
		if applied is Dictionary:
			for action in applied.get("actions", []):
				highlighted.append(action.get("target", ""))
		var state = record.get("model_state")
		var model_state: Dictionary = state if state is Dictionary else {}
		if not live_active:
			structure_display.build_state(current_topo, model_state, highlighted)
		_set_preview(run_dir, index, model_state, highlighted)
	_log_record(record)

func _set_preview(run_dir: String, index: int, model_state: Dictionary, highlighted: Array) -> void:
	preview_playing = false
	preview_holding = false
	preview_frames = []
	preview_run_dir = run_dir
	preview_index = index
	preview_view.build_state(current_topo, model_state, highlighted)
	_frame_preview_camera()
	preview_hint.text = "Iteration %d  -  click to play shake" % index
	if not live_active:
		shake_label.visible = false

func _clear_preview() -> void:
	preview_playing = false
	preview_holding = false
	preview_frames = []
	preview_run_dir = ""
	preview_index = -1
	if preview_view != null:
		preview_view.clear()
	if preview_hint != null:
		preview_hint.text = "Select an iteration to preview its seismic performance"
	if shake_label != null and not live_active:
		shake_label.visible = false

func _frame_preview_camera() -> void:
	var width_x: float = float(current_params["bay_count_x"]) * float(current_params["bay_width_x"])
	var width_z: float = float(current_params["bay_count_y"]) * float(current_params["bay_width_y"])
	var height_y: float = float(current_params["floor_count"]) * float(current_params["story_height"])
	var extents := Vector3(width_x, height_y, width_z)
	var center := extents / 2.0
	var half_fov_rad := deg_to_rad(preview_camera.fov) / 2.0
	var distance: float = max(extents.length() / 2.0 / sin(half_fov_rad) * 1.2, 6.0)
	preview_camera.global_position = center + Vector3(1.0, 0.7, 1.0).normalized() * distance
	preview_camera.look_at(center, Vector3.UP)

func _on_preview_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT):
		return
	if preview_index < 0:
		return
	if python_simulation_running:
		preview_hint.text = "Iteration %d  -  playback is available after the run" % preview_index
		return
	var data = _read_json(preview_run_dir.path_join("iteration_%d" % preview_index).path_join("frames.json"))
	if not data is Dictionary or (data.get("frames", []) as Array).is_empty():
		preview_hint.text = "Iteration %d  -  no shake frames saved (collapsed under gravity)" % preview_index
		return
	for view in [preview_view, structure_display]:
		view.reset_frame()
		view.set_frame_nodes(data.get("node_keys", []))
	preview_ruptures = data.get("ruptures", [])
	preview_next_rupture = 0
	preview_collapse_time = data.get("collapse_time_s")
	preview_holding = false
	preview_frames = []
	var peak := 0.0
	for frame in data["frames"]:
		var values := PackedFloat32Array(frame)
		peak = max(peak, _frame_peak(values))
		preview_frames.append(values)
	preview_frame_dt = max(float(data.get("dt_s", 0.1)), 0.001)
	preview_magnification = _shake_magnification(peak)
	preview_time = 0.0
	preview_playing = true

func _update_preview_playback(delta: float) -> void:
	var views := [preview_view, structure_display]
	if preview_holding:
		for view in views:
			view.update_falls(delta)
		return
	if not preview_playing:
		return
	preview_time += delta
	while preview_next_rupture < preview_ruptures.size() and float(preview_ruptures[preview_next_rupture].get("time_s", 0.0)) <= preview_time:
		for view in views:
			view.drop_member(preview_ruptures[preview_next_rupture].get("nodes", []))
		preview_next_rupture += 1
	for view in views:
		view.update_falls(delta)
	var cursor := preview_time / preview_frame_dt
	var index := int(cursor)
	if index >= preview_frames.size() - 1:
		preview_playing = false
		preview_holding = true
		for view in views:
			view.apply_frame(preview_frames[preview_frames.size() - 1], preview_magnification)
		while preview_next_rupture < preview_ruptures.size():
			for view in views:
				view.drop_member(preview_ruptures[preview_next_rupture].get("nodes", []))
			preview_next_rupture += 1
		if preview_collapse_time != null:
			preview_hint.text = "Iteration %d  collapse at t = %.2f s  -  click to replay" % [preview_index, float(preview_collapse_time)]
			shake_label.text = "Iteration %d replay   collapse at t = %.2f s (analysis stopped)" % [preview_index, float(preview_collapse_time)]
		else:
			preview_hint.text = "Iteration %d  -  click to replay shake" % preview_index
			shake_label.text = "Iteration %d replay   end of record   displacements x%.0f" % [preview_index, preview_magnification]
		return
	var a: PackedFloat32Array = preview_frames[index]
	var b: PackedFloat32Array = preview_frames[index + 1]
	var t := cursor - index
	var values := PackedFloat32Array()
	values.resize(a.size())
	for i in range(a.size()):
		values[i] = lerp(a[i], b[i], t)
	for view in views:
		view.apply_frame(values, preview_magnification)
	preview_hint.text = "Iteration %d   t = %.1f s   x%.0f" % [preview_index, (index + t) * preview_frame_dt, preview_magnification]
	shake_label.text = "Iteration %d replay   t = %.1f s   displacements x%.0f" % [preview_index, (index + t) * preview_frame_dt, preview_magnification]
	shake_label.visible = true

func _log_record(parsed: Dictionary) -> void:
	var header := "Iteration %d" % int(parsed.get("iteration", 0)) if parsed.has("iteration") else "NLTHA results"
	_log_terminal("----- %s: building %d -----" % [header, int(parsed.get("building_id", 0))])
	var applied = parsed.get("applied_feedback")
	if applied is Dictionary:
		var counts := {}
		for action in applied.get("actions", []):
			var kind: String = action.get("action", "")
			var text: String = kind
			if action.has("from"):
				text = "%s %s -> %s" % [kind, action.get("from", ""), action.get("to", "")]
			elif action.has("to"):
				text = "%s (%s)" % [kind, action.get("to", "")]
			counts[text] = int(counts.get(text, 0)) + 1
		var parts: Array[String] = []
		for text in counts:
			parts.append("%s x%d" % [text, counts[text]])
		_log_terminal("feedback applied from iteration %d (sizing: %s): %s" % [
			int(applied.get("from_iteration", 0)), str(applied.get("sizing_mode", "demand ratio")), ", ".join(parts)])
		var limited: Array = applied.get("section_limit_reached", [])
		if not limited.is_empty():
			_log_terminal("  section limit reached (already W36X529) for %d member(s)" % limited.size())
	_log_terminal("analysis: %s   time step: %.4fs   steps completed: %d" % [
		parsed.get("analysis", "?"), parsed.get("time_step_s", 0.0), parsed.get("steps", 0)
	])
	if parsed.has("input_magnitude"):
		_log_terminal("seismic input: magnitude %.1f -> %.4fg PGA, strong-shaking duration %.1fs, record length %.1fs" % [
			parsed["input_magnitude"], parsed.get("input_pga_g", 0.0),
			parsed.get("input_duration_s", 0.0), parsed.get("record_length_s", 0.0)
		])
	if parsed.get("fundamental_period_s") != null:
		_log_terminal("fundamental period T = %.3fs -> NSCP drift limit %.3f (%.1f%%)" % [
			parsed["fundamental_period_s"], parsed.get("drift_limit", 0.0), parsed.get("drift_limit", 0.0) * 100.0
		])

	var overall_status: String = parsed.get("overall_status", "FAIL")
	_log_terminal("RESULT: %s -- %s under gravity plus this seismic input" % [
		overall_status, ("all evaluation checks pass" if overall_status == "PASS" else "one or more evaluation checks fail")
	])

	var converged: bool = parsed.get("converged", true)
	if not converged:
		if parsed.get("collapse_phase", "seismic") == "gravity":
			_log_terminal("  did not converge -- structure failed under gravity load alone, before any seismic excitation")
		else:
			var ct = parsed.get("collapse_time_s")
			_log_terminal("  did not converge at t=%.3fs -- structure likely collapsed (%d steps completed)" % [
				(0.0 if ct == null else ct), parsed.get("steps", 0)
			])
			_log_terminal("  note: the peak values below include the response leading up to the collapse")

	var evaluation = parsed.get("evaluation")
	if evaluation is Dictionary:
		var el: Dictionary = evaluation.get("element_level") if evaluation.get("element_level") is Dictionary else {}
		var st: Dictionary = evaluation.get("structure_level") if evaluation.get("structure_level") is Dictionary else {}
		if evaluation.get("gravity_fallback", false):
			_log_terminal("  gravity check (linear-elastic, used because the nonlinear model collapsed under gravity):")
		var el_over := (el.get("overstressed_elements", []) as Array).size()
		var el_buckled := (el.get("buckled_elements", []) as Array).size()
		var el_rupt := (el.get("ruptured_elements", []) as Array).size()
		_log_terminal("  element-level:   %s (%d overstressed, %d buckled, %d ruptured, of %d members)" % [
			("PASS" if el.get("pass", false) else "FAIL"), el_over, el_buckled, el_rupt, el.get("total_elements", 0)
		])
		if evaluation.get("floor_level") is Dictionary:
			var fl: Dictionary = evaluation["floor_level"]
			var exceeding := (fl.get("exceeding_floors", []) as Array)
			var soft := (fl.get("soft_story_floors", []) as Array)
			var mid_conc := (fl.get("mid_story_concentration_floors", []) as Array)
			var directional := (fl.get("directional_instability_floors", []) as Array)
			_log_terminal("  floor-level:     %s (IDR>limit: %s, soft-story: %s, mid-story: %s, X/Y imbalance: %s)" % [
				("PASS" if fl.get("pass", false) else "FAIL"),
				_floor_list(exceeding), _floor_list(soft), _floor_list(mid_conc), _floor_list(directional),
			])
			_log_terminal("  structure-level: %s (roof disp %s limit, torsion ratio %.2f%s, mean stress %.1f MPa)" % [
				("PASS" if st.get("pass", false) else "FAIL"),
				("exceeds" if st.get("roof_displacement_exceeds_limit", false) else "within"),
				st.get("max_torsional_irregularity_ratio", 1.0),
				(" (irregular)" if st.get("torsional_irregularity", false) else ""),
				st.get("mean_stress_mpa", 0.0)
			])
		else:
			_log_terminal("  floor-level:     not evaluated (no seismic analysis)")
			_log_terminal("  structure-level: mean stress %.1f MPa (%s)" % [
				st.get("mean_stress_mpa", 0.0), ("PASS" if st.get("pass", false) else "FAIL")])
		var triggered: Array = evaluation.get("triggered_rules", [])
		if triggered.is_empty():
			_log_terminal("  triggered rules: none")
		else:
			var parts: Array[String] = []
			for entry in triggered:
				parts.append("Rule %d %s x%d (max ratio %.2f)" % [
					int(entry.get("rule", 0)), entry.get("name", ""), int(entry.get("count", 0)), entry.get("max_ratio", 0.0)
				])
			_log_terminal("  triggered rules: " + ", ".join(parts))

	if parsed.get("peak_stress_mpa") != null:
		_log_terminal("peak stress:         %.3f MPa" % parsed.get("peak_stress_mpa", 0.0))
		_log_terminal("peak displacement X: %.5f m" % parsed.get("peak_displacement_m", 0.0))
		_log_terminal("peak displacement Y: %.5f m" % parsed.get("peak_displacement_y_m", 0.0))
		_log_terminal("peak deformation:    %.5f m" % parsed.get("peak_deformation_m", 0.0))
		_log_terminal("max story drift:     %.5f m" % parsed.get("maximum_story_drift_m", 0.0))
		var idr_note := ""
		if parsed.get("idr_exceeds_limit", false):
			idr_note = "  (exceeds the %.1f%% NSCP limit)" % (parsed.get("drift_limit", 0.0) * 100.0)
		_log_terminal("max IDR:             %.5f%s" % [parsed.get("maximum_idr", 0.0), idr_note])
		_log_terminal("max IDR in %%:        %.2f%%%s" % [parsed.get("maximum_idr", 0.0) * 100.0, idr_note])
	_log_terminal("topology valid: %s" % ("yes" if parsed.get("topology_valid", false) else "no"))
	_log_terminal("time history: iteration_%d/history.csv (%d steps)" % [int(parsed.get("iteration", 0)), parsed.get("steps", 0)])

func _floor_list(floors: Array) -> String:
	if floors.is_empty():
		return "none"
	var names: Array[String] = []
	for floor_number in floors:
		names.append(str(int(floor_number)))
	return "floor " + ", ".join(names)

func _list_run_dirs() -> PackedStringArray:
	var found := PackedStringArray()
	var root_dir := _runs_root()
	if not DirAccess.dir_exists_absolute(root_dir):
		return found
	for name in DirAccess.get_directories_at(root_dir):
		if name.begins_with("run_"):
			found.append(root_dir.path_join(name))
	return found

func _dir_size_bytes(path: String) -> int:
	var total := 0
	for name in DirAccess.get_files_at(path):
		var file := FileAccess.open(path.path_join(name), FileAccess.READ)
		if file != null:
			total += file.get_length()
			file.close()
	for name in DirAccess.get_directories_at(path):
		total += _dir_size_bytes(path.path_join(name))
	return total

func _delete_dir_recursive(path: String) -> bool:
	for name in DirAccess.get_files_at(path):
		if DirAccess.remove_absolute(path.path_join(name)) != OK:
			return false
	for name in DirAccess.get_directories_at(path):
		if not _delete_dir_recursive(path.path_join(name)):
			return false
	return DirAccess.remove_absolute(path) == OK

func _on_clean_runs_pressed() -> void:
	if python_simulation_running:
		_log_terminal("cannot clean runs while a simulation is running")
		return
	var runs := _list_run_dirs()
	if runs.is_empty():
		_log_terminal("no previous runs to clean")
		return
	var total_bytes := 0
	for run_dir in runs:
		total_bytes += _dir_size_bytes(run_dir)
	clean_runs_dialog.dialog_text = "Delete %d previous run%s (%.1f MB)? This cannot be undone." % [
		runs.size(), "" if runs.size() == 1 else "s", total_bytes / 1048576.0
	]
	clean_runs_dialog.popup_centered()

func _on_clean_runs_confirmed() -> void:
	if python_simulation_running:
		return
	var deleted := 0
	var failed := 0
	for run_dir in _list_run_dirs():
		if _delete_dir_recursive(run_dir):
			deleted += 1
		else:
			failed += 1
	current_run_dir = ""
	_clear_iteration_list()
	_clear_preview()
	if failed > 0:
		_log_terminal("deleted %d run(s); %d could not be deleted" % [deleted, failed])
	else:
		_log_terminal("deleted %d previous run(s)" % deleted)

func _clear_iteration_list() -> void:
	_clear_children(iteration_list)
	iterations_shown = 0
	iteration_label.text = "No iterations yet"

func _on_reset_pressed() -> void:
	_stop_live_shake()
	_clear_preview()
	structure_display.clear()
	MemberVisual.clear_caches()
	if not python_simulation_running:
		_clear_iteration_list()
	has_structure = false
	current_params = {}
	current_topo = {}
	vp_label.visible = true
	rule_preview_dropdown.select(0)
	rule_preview_dropdown.visible = false
	_reset_terminal()

func _on_rule_preview_selected(index: int) -> void:
	structure_display.build(current_topo)
	if index <= 0:
		return
	var rule_label := rule_preview_dropdown.get_item_text(index)
	var description := structure_display.preview_rule(index, current_topo)
	_log_terminal(
		"preview: %s -- %s (visual mock-up only; no section data changed, no re-analysis run)" % [rule_label, description]
	)

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
