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
const COLOR_PANEL_TINT := Color("#f4f8ff")
const COLOR_BLUE_SOFT := Color("#eaf2ff")
const COLOR_BLUE_LINE := Color("#d7e6ff")
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
var tex_bg_hero: Texture2D
var tex_bg_light: Texture2D
var tex_bg_blue: Texture2D
var tex_terminal_success: Texture2D
var tex_terminal_error: Texture2D
var tex_terminal_warning: Texture2D
var tex_terminal_loading: Texture2D

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
var fixed_hero_background: TextureRect

var bay_x_input: LineEdit
var bay_y_input: LineEdit
var bay_width_x_input: LineEdit
var bay_width_y_input: LineEdit
var floor_count_input: LineEdit
var story_height_input: LineEdit
var magnitude_input: LineEdit
var duration_input: LineEdit
var structural_controls: VBoxContainer
var structural_summary_box: VBoxContainer
var structural_summary_title: Label
var structural_summary_divider: HSeparator
var simulation_controls: VBoxContainer
var run_simulation_button: Button

var rule_preview_dropdown: OptionButton

var vp_label: Label
var term_vbox: VBoxContainer
var term_scroll: ScrollContainer
var terminal_panel: PanelContainer
var structure_display: StaticStructureView
var structure_camera: FreeCamera
var structure_zoom_percent: int = 100
var structure_zoom_label: Label
var structure_zoom_target: Vector3 = Vector3.ZERO
var generation_loading_overlay: PanelContainer
var ui_zoom_percent: int = 100
var ui_zoom_label: Label

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
		if is_instance_valid(clean_runs_button):
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
	_build_fixed_hero_background()

	_build_main_structure()
	_build_navbar()
	_build_hero()
	_build_features()
	_build_how_it_works()
	_build_cta()
	_build_footer()
	_build_app_view()
	get_viewport().size_changed.connect(_apply_ui_zoom_layout)
	_apply_ui_zoom_layout()
	_load_w_sections()

func _load_w_sections() -> void:
	var path := ProjectSettings.globalize_path("res://../w_sections.json")
	if not FileAccess.file_exists(path):
		push_warning("w_sections.json not found next to simulation.py")
		return
	var file := FileAccess.open(path, FileAccess.READ)
	var parsed = JSON.parse_string(file.get_as_text())
	file.close()
	if not parsed is Dictionary or not parsed.has("sections"):
		push_warning("w_sections.json is not valid")
		return
	structure_display.set_sections(parsed["sections"])
	preview_view.set_sections(parsed["sections"])

func _load_assets() -> void:
	font_inter = _load_font("res://assets/fonts/Inter-Variable.ttf")
	font_poppins_regular = _load_font("res://assets/fonts/Poppins-Regular.ttf")
	font_poppins_bold = _load_font("res://assets/fonts/Poppins-Bold.ttf")

	tex_logo = _load_texture("res://assets/images/378c25b527b93f4d537c05f5e5e176bde7944f7d.png")
	tex_hero = _load_texture_first([
		"res://assets/images/progen_hero_new.jpg",
		"res://assets/images/56cd8b20-4bf7-40c3-9106-51aef609b2a0.jpg",
		"res://assets/images/f229d4a87587b430f06eac9a1721e00ff504c72a.png",
	])
	tex_wrench = _load_texture("res://assets/images/685eb8a845267f833aafffc00ac390593e26b82c.png")
	tex_earthquakes = _load_texture("res://assets/images/4eadefe6acfaa3f5c07af4310d78a6f0b4d474dd.png")
	tex_arrows = _load_texture("res://assets/images/925fb8034affbf0e3b5285404e443337e5b0cba5.png")
	tex_design = _load_texture("res://assets/images/b5d36fae30c80b058f77ee82997855c72ab0321d.png")
	tex_chart = _load_texture("res://assets/images/f08d789c81c84549efa2f4331d2fc82a84dac85a.png")
	tex_3d = _load_texture("res://assets/images/dd653bd5aa09fcbc12b0969f9655854d3c28e400.png")

	# Terminal status icons supplied by the user.
	tex_terminal_success = _load_texture_first([
		"res://assets/images/terminal_success.png",
		"res://assets/images/line-md--circle-to-confirm-circle-transition.png",
	])
	tex_terminal_error = _load_texture_first([
		"res://assets/images/terminal_error.png",
		"res://assets/images/line-md--alert-circle.png",
	])
	tex_terminal_warning = _load_texture_first([
		"res://assets/images/terminal_warning.png",
		"res://assets/images/line-md--alert (1).png",
	])

	tex_terminal_loading = _load_texture_first([
		"res://assets/images/terminal_loading.jpg",
		"res://assets/images/terminal_loading.svg",
		"res://assets/images/eos-icons--loading.svg",
	])

	# Landing-page reference backgrounds. The helper tries a few likely filenames so
	# the script still works if the OS/project removed the upload suffix.
	tex_bg_hero = _load_texture_first([
		"res://assets/images/Minimal Blue Wireframe Architecture Background(1).png",
		"res://assets/images/Minimal Blue Wireframe Architecture Background.png",
	])
	tex_bg_light = _load_texture_first([
		"res://assets/images/Minimalist Blue Tech Grid Background(1).png",
		"res://assets/images/Minimalist Blue Tech Grid Background.png",
	])
	tex_bg_blue = _load_texture_first([
		"res://assets/images/Blue Architectural Blueprint Background(1).png",
		"res://assets/images/Blue Architectural Blueprint Background.png",
	])

func _configure_layout() -> void:
	website.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	website.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	page_layout.add_theme_constant_override("separation", 0)

func _build_fixed_hero_background() -> void:
	# This wallpaper is attached to the root Control instead of the ScrollContainer.
	# Because it is outside the scrolling content, it stays fixed on screen while
	# Hero, Powerful Features, and How ProGen Works all scroll over it
	# (similar to CSS background-attachment: fixed).
	fixed_hero_background = TextureRect.new()
	fixed_hero_background.name = "FixedHeroBackground"
	fixed_hero_background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	fixed_hero_background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fixed_hero_background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	fixed_hero_background.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	fixed_hero_background.texture = tex_bg_hero
	fixed_hero_background.z_index = -100
	add_child(fixed_hero_background)
	move_child(fixed_hero_background, 0)

func _build_main_structure() -> void:
	app_view_container = Control.new()
	app_view_container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	app_view_container.visible = false
	add_child(app_view_container)

func _switch_to_app() -> void:
	website.visible = false
	if fixed_hero_background:
		fixed_hero_background.visible = false
	app_view_container.visible = true

func _switch_to_landing() -> void:
	_set_ui_zoom(100)
	app_view_container.visible = false
	if fixed_hero_background:
		fixed_hero_background.visible = true
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
	# Do not paint the wallpaper on the scrolling Hero panel itself.
	# The fixed TextureRect behind the ScrollContainer supplies the Hero background.
	var transparent_hero_style := StyleBoxFlat.new()
	transparent_hero_style.bg_color = Color(0, 0, 0, 0)
	transparent_hero_style.border_width_left = 0
	transparent_hero_style.border_width_top = 0
	transparent_hero_style.border_width_right = 0
	transparent_hero_style.border_width_bottom = 0
	hero_panel.add_theme_stylebox_override("panel", transparent_hero_style)

	var center := CenterContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hero_panel.add_child(center)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_top", 78)
	margin.add_theme_constant_override("margin_bottom", 92)
	center.add_child(margin)

	var content := HBoxContainer.new()
	content.custom_minimum_size = Vector2(1420, 0)
	content.add_theme_constant_override("separation", 62)
	margin.add_child(content)

	# LEFT: copy and controls
	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(565, 0)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.size_flags_stretch_ratio = 0.88
	left.add_theme_constant_override("separation", 21)
	content.add_child(left)


	var title_group := VBoxContainer.new()
	title_group.add_theme_constant_override("separation", -9)
	left.add_child(title_group)

	var title_top := Label.new()
	title_top.text = "Generate
Structural Design"
	title_top.add_theme_font_override("font", font_poppins_bold)
	title_top.add_theme_font_size_override("font_size", 62)
	title_top.add_theme_color_override("font_color", Color("#07142e"))
	title_top.add_theme_constant_override("line_spacing", -7)
	title_group.add_child(title_top)

	var brand_row := HBoxContainer.new()
	brand_row.add_theme_constant_override("separation", 0)
	title_group.add_child(brand_row)
	var title_with := Label.new()
	title_with.text = "with "
	title_with.add_theme_font_override("font", font_poppins_bold)
	title_with.add_theme_font_size_override("font_size", 62)
	title_with.add_theme_color_override("font_color", Color("#07142e"))
	brand_row.add_child(title_with)
	var pro_label = _brand_label("Pro", Color("#ff9d1f"))
	pro_label.add_theme_font_size_override("font_size", 62)
	brand_row.add_child(pro_label)
	var gen_label = _brand_label("Gen", Color("#1367ff"))
	gen_label.add_theme_font_size_override("font_size", 62)
	brand_row.add_child(gen_label)

	var body := _body_label("ProGen is a closed-loop rule-based procedural generation system that creates optimized 3D structural models and refines them using seismic simulation feedback. Generate, simulate, evaluate, and refine—all in one platform.", 17)
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.custom_minimum_size = Vector2(560, 0)
	left.add_child(body)

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 16)
	left.add_child(buttons)
	var get_started_btn := _primary_button("Get Started", Vector2(205, 58))
	get_started_btn.pressed.connect(func(): _scroll_to_node(features_panel))
	buttons.add_child(get_started_btn)
	var learn_more_btn := _outline_button("Learn More", Vector2(158, 58))
	learn_more_btn.pressed.connect(func(): _scroll_to_node(how_panel))
	buttons.add_child(learn_more_btn)


	# RIGHT: app preview, matching the large rounded reference card.
	var right := PanelContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	right.size_flags_stretch_ratio = 1.12
	var right_style := _style_box(Color(1, 1, 1, 0.96), Color("#d6e6fb"), 1, 16, 9)
	right_style.shadow_color = Color(0.05, 0.27, 0.72, 0.12)
	right_style.shadow_size = 18
	right.add_theme_stylebox_override("panel", right_style)
	content.add_child(right)

	var hero_image := TextureRect.new()
	hero_image.texture = tex_hero
	hero_image.custom_minimum_size = Vector2(690, 430)
	hero_image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	hero_image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	right.add_child(hero_image)

func _build_features() -> void:
	_clear_children(features_panel)
	# Keep this section transparent so the same fixed landing-page wallpaper
	# remains visible while the user scrolls through Powerful Features.
	var transparent_features_style := StyleBoxFlat.new()
	transparent_features_style.bg_color = Color(0, 0, 0, 0)
	transparent_features_style.border_width_left = 0
	transparent_features_style.border_width_top = 0
	transparent_features_style.border_width_right = 0
	transparent_features_style.border_width_bottom = 0
	features_panel.add_theme_stylebox_override("panel", transparent_features_style)

	var center := CenterContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	features_panel.add_child(center)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_top", 58)
	margin.add_theme_constant_override("margin_bottom", 58)
	center.add_child(margin)

	var content := VBoxContainer.new()
	content.custom_minimum_size = Vector2(1400, 0)
	content.add_theme_constant_override("separation", 30)
	margin.add_child(content)

	var heading := VBoxContainer.new()
	heading.add_theme_constant_override("separation", 8)
	heading.add_child(_center_label("Everything you need to generate,
test, and optimize", font_poppins_bold, 40, Color("#07142e")))
	content.add_child(heading)

	var grid := GridContainer.new()
	grid.columns = 3
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 22)
	grid.add_theme_constant_override("v_separation", 20)
	content.add_child(grid)

	var specs := [
		["01", "Procedural Generation", "Automatically generate beam-column
structures based on your specifications.", tex_wrench],
		["02", "Seismic Simulation", "Simulate real-world seismic behavior with
customizable magnitude and duration parameters.", tex_earthquakes],
		["03", "Iterative Refinement", "Automatically refine structures through 10
iterations based on seismic performance feedback.", tex_arrows],
		["04", "3D Visualization", "Interactive 3D viewport with full camera controls.
Rotate, zoom, and pan.", tex_3d],
		["05", "Performance Metrics", "Track key metrics like drift ratio, safety factor,
and material usage.", tex_chart],
		["06", "Design Constraints", "Define custom design constraints and safety
thresholds.", tex_design],
	]
	for spec in specs:
		grid.add_child(_numbered_feature_card(spec[0], spec[1], spec[2], spec[3]))

	# Compact proof strip below the feature cards. Give it an explicit width so
	# the HBox never collapses into a narrow column on wide/HiDPI layouts.
	var proof_center := CenterContainer.new()
	proof_center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_child(proof_center)

	var proof := PanelContainer.new()
	proof.custom_minimum_size = Vector2(780, 58)
	proof.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var proof_style := _style_box(Color(0.98, 0.995, 1.0, 0.96), Color("#dce9fb"), 1, 16, 14)
	proof_style.shadow_color = Color(0.04, 0.22, 0.60, 0.035)
	proof_style.shadow_size = 6
	proof.add_theme_stylebox_override("panel", proof_style)
	proof_center.add_child(proof)

	var proof_row := HBoxContainer.new()
	proof_row.alignment = BoxContainer.ALIGNMENT_CENTER
	proof_row.add_theme_constant_override("separation", 34)
	proof.add_child(proof_row)
	proof_row.add_child(_compact_proof_item("⚙", "Rule-based generation"))
	proof_row.add_child(_compact_proof_item("◇", "Seismic-aware optimization"))
	proof_row.add_child(_compact_proof_item("□", "Interactive 3D analysis"))

func _build_how_it_works() -> void:
	_clear_children(how_panel)
	# Keep this section transparent so the fixed wallpaper also stays visible
	# behind How ProGen Works.
	var transparent_how_style := StyleBoxFlat.new()
	transparent_how_style.bg_color = Color(0, 0, 0, 0)
	transparent_how_style.border_width_left = 0
	transparent_how_style.border_width_top = 0
	transparent_how_style.border_width_right = 0
	transparent_how_style.border_width_bottom = 0
	how_panel.add_theme_stylebox_override("panel", transparent_how_style)

	var center := CenterContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	how_panel.add_child(center)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_top", 66)
	margin.add_theme_constant_override("margin_bottom", 64)
	center.add_child(margin)

	var content := VBoxContainer.new()
	content.custom_minimum_size = Vector2(1400, 0)
	content.add_theme_constant_override("separation", 40)
	margin.add_child(content)

	# Use one RichTextLabel for the title instead of four expanding Labels.
	# The old HBox allowed each label to expand, which could squeeze every word
	# into a few pixels and make the title render vertically.
	var title_box := VBoxContainer.new()
	title_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_box.add_theme_constant_override("separation", 8)

	var title := RichTextLabel.new()
	title.bbcode_enabled = true
	title.fit_content = false
	title.scroll_active = false
	title.autowrap_mode = TextServer.AUTOWRAP_OFF
	title.custom_minimum_size = Vector2(0, 58)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_font_override("normal_font", font_poppins_bold)
	title.add_theme_font_override("bold_font", font_poppins_bold)
	title.add_theme_font_size_override("normal_font_size", 37)
	title.add_theme_font_size_override("bold_font_size", 37)
	title.text = "[center][color=#07142e]How [/color][color=#ff9d1f]Pro[/color][color=#155dfc]Gen[/color][color=#07142e] Works[/color][/center]"
	title_box.add_child(title)

	var subtitle := _center_label("A three-stage process for intelligent structural design", font_inter, 17, COLOR_MUTED)
	subtitle.autowrap_mode = TextServer.AUTOWRAP_OFF
	subtitle.custom_minimum_size = Vector2(0, 28)
	title_box.add_child(subtitle)
	content.add_child(title_box)

	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 16)
	content.add_child(row)

	var stage_data := [
		["▤", "Input Stage", "Define your structural parameters:", ["Bay X & Y (column spacing)", "Bay widths (dimensions)", "Floor count & story height", "Seismic magnitude & duration"]],
		["⚙", "Generation & Simulation", "ProGen processes your inputs:", ["Generate beam-column model", "Run seismic simulation", "Evaluate performance", "Detect structural weaknesses"]],
		["↻", "Refinement & Output", "Iterative optimization:", ["10 refinement iterations", "Automatic optimization", "Safety threshold validation", "Final optimized structure"]],
	]
	for i in range(stage_data.size()):
		row.add_child(_simple_stage_card(stage_data[i][0], stage_data[i][1], stage_data[i][2], stage_data[i][3]))
		if i < stage_data.size() - 1:
			var arrow_wrap := CenterContainer.new()
			arrow_wrap.custom_minimum_size = Vector2(44, 0)
			var arrow := Label.new()
			arrow.text = "→"
			arrow.add_theme_font_override("font", font_poppins_bold)
			arrow.add_theme_font_size_override("font_size", 34)
			arrow.add_theme_color_override("font_color", COLOR_BLUE)
			arrow_wrap.add_child(arrow)
			row.add_child(arrow_wrap)

func _build_cta() -> void:
	_clear_children(cta_area)
	if tex_bg_blue:
		_set_panel_texture_bg(cta_area, tex_bg_blue)
	else:
		_set_panel_texture_bg(cta_area, _linear_gradient_texture([Color("#1167ff"), Color("#003eff"), Color("#1769ff")], [0.0, 0.55, 1.0]))

	var center := CenterContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cta_area.add_child(center)

	var cta_margin := MarginContainer.new()
	cta_margin.add_theme_constant_override("margin_top", 62)
	cta_margin.add_theme_constant_override("margin_bottom", 62)
	center.add_child(cta_margin)

	var content := VBoxContainer.new()
	content.alignment = BoxContainer.ALIGNMENT_CENTER
	content.custom_minimum_size = Vector2(1400, 0)
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 17)
	cta_margin.add_child(content)

	content.add_child(_center_label("Ready to Optimize Your Structures?", font_poppins_bold, 35, COLOR_WHITE))
	content.add_child(_center_label("Start designing smarter, safer structures today with ProGen.", font_inter, 17, Color("#e2ecff")))

	var btn_center := CenterContainer.new()
	btn_center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var btn := Button.new()
	btn.text = "Launch ProGen App"
	btn.custom_minimum_size = Vector2(250, 58)
	btn.add_theme_font_override("font", font_poppins_bold)
	btn.add_theme_font_size_override("font_size", 16)
	btn.add_theme_color_override("font_color", COLOR_BLUE)
	btn.add_theme_color_override("font_hover_color", COLOR_BLUE)
	var btn_style := _style_box(COLOR_WHITE, COLOR_WHITE, 0, 9)
	btn_style.shadow_color = Color(0.02, 0.15, 0.45, 0.20)
	btn_style.shadow_size = 8
	btn.add_theme_stylebox_override("normal", btn_style)
	btn.add_theme_stylebox_override("hover", _style_box(Color("#f4f8ff"), COLOR_WHITE, 0, 9))
	btn.pressed.connect(_switch_to_app)
	btn_center.add_child(btn)
	content.add_child(btn_center)

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
	# Polished reference-style dashboard.
	var app_root := VBoxContainer.new()
	app_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	app_root.add_theme_constant_override("separation", 0)
	app_view_container.add_child(app_root)

	# Header
	var app_nav := PanelContainer.new()
	app_nav.custom_minimum_size = Vector2(0, 104)
	var nav_style := _style_box(COLOR_WHITE, Color("#edf2f8"), 1, 0, 0)
	nav_style.shadow_size = 0
	app_nav.add_theme_stylebox_override("panel", nav_style)
	app_root.add_child(app_nav)

	var nav_margin := MarginContainer.new()
	nav_margin.add_theme_constant_override("margin_left", 44)
	nav_margin.add_theme_constant_override("margin_right", 44)
	nav_margin.add_theme_constant_override("margin_top", 8)
	nav_margin.add_theme_constant_override("margin_bottom", 8)
	app_nav.add_child(nav_margin)

	var nav_row := HBoxContainer.new()
	nav_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nav_row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	nav_margin.add_child(nav_row)

	var logo := TextureRect.new()
	logo.texture = tex_logo
	logo.custom_minimum_size = Vector2(300, 82)
	logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	# KEEP_ASPECT (rather than CENTERED) keeps the actual logo artwork against
	# the left side of its header slot instead of floating in the middle.
	logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT
	logo.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	logo.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	nav_row.add_child(logo)


	var nav_spacer := Control.new()
	nav_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nav_row.add_child(nav_spacer)

	# Whole-UI zoom controls beside Back to Home.
	var ui_zoom_group := HBoxContainer.new()
	ui_zoom_group.add_theme_constant_override("separation", 4)
	ui_zoom_group.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	nav_row.add_child(ui_zoom_group)

	var ui_zoom_out := Button.new()
	ui_zoom_out.text = "−"
	ui_zoom_out.tooltip_text = "Zoom interface out"
	ui_zoom_out.custom_minimum_size = Vector2(34, 34)
	ui_zoom_out.focus_mode = Control.FOCUS_NONE
	ui_zoom_out.add_theme_font_override("font", font_poppins_bold)
	ui_zoom_out.add_theme_font_size_override("font_size", 17)
	ui_zoom_out.add_theme_color_override("font_color", COLOR_BLUE)
	ui_zoom_out.add_theme_stylebox_override("normal", _style_box(Color("#ffffff"), Color("#d6e4f6"), 1, 8, 4))
	ui_zoom_out.add_theme_stylebox_override("hover", _style_box(Color("#eef5ff"), COLOR_BLUE, 1, 8, 4))
	ui_zoom_out.pressed.connect(func(): _change_ui_zoom(-10))
	ui_zoom_group.add_child(ui_zoom_out)

	ui_zoom_label = Label.new()
	ui_zoom_label.text = "100%"
	ui_zoom_label.custom_minimum_size = Vector2(58, 34)
	ui_zoom_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ui_zoom_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	ui_zoom_label.add_theme_font_override("font", font_poppins_bold)
	ui_zoom_label.add_theme_font_size_override("font_size", 12)
	ui_zoom_label.add_theme_color_override("font_color", COLOR_NAVY)
	ui_zoom_label.add_theme_stylebox_override("normal", _style_box(Color("#ffffff"), Color("#d6e4f6"), 1, 8, 4))
	ui_zoom_group.add_child(ui_zoom_label)

	var ui_zoom_in := Button.new()
	ui_zoom_in.text = "+"
	ui_zoom_in.tooltip_text = "Zoom interface in"
	ui_zoom_in.custom_minimum_size = Vector2(34, 34)
	ui_zoom_in.focus_mode = Control.FOCUS_NONE
	ui_zoom_in.add_theme_font_override("font", font_poppins_bold)
	ui_zoom_in.add_theme_font_size_override("font_size", 17)
	ui_zoom_in.add_theme_color_override("font_color", COLOR_BLUE)
	ui_zoom_in.add_theme_stylebox_override("normal", _style_box(Color("#ffffff"), Color("#d6e4f6"), 1, 8, 4))
	ui_zoom_in.add_theme_stylebox_override("hover", _style_box(Color("#eef5ff"), COLOR_BLUE, 1, 8, 4))
	ui_zoom_in.pressed.connect(func(): _change_ui_zoom(10))
	ui_zoom_group.add_child(ui_zoom_in)

	var back_btn := Button.new()
	back_btn.text = "←  Back to Home"
	back_btn.custom_minimum_size = Vector2(122, 34)
	back_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	back_btn.size_flags_horizontal = Control.SIZE_SHRINK_END
	back_btn.focus_mode = Control.FOCUS_NONE
	back_btn.add_theme_font_override("font", font_poppins_bold)
	back_btn.add_theme_font_size_override("font_size", 12)
	back_btn.add_theme_color_override("font_color", COLOR_NAVY)
	back_btn.add_theme_color_override("font_hover_color", COLOR_BLUE)
	back_btn.add_theme_stylebox_override("normal", _style_box(Color("#ffffff"), Color("#dbe8f7"), 1, 7, 2))
	back_btn.add_theme_stylebox_override("hover", _style_box(Color("#f8fbff"), Color("#bdd6fb"), 1, 7, 2))
	back_btn.add_theme_stylebox_override("pressed", _style_box(Color("#eef5ff"), Color("#94bdf8"), 1, 7, 2))
	back_btn.pressed.connect(_switch_to_landing)
	nav_row.add_child(back_btn)

	# Main body
	var body_panel := PanelContainer.new()
	body_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var body_style := StyleBoxFlat.new()
	body_style.bg_color = Color("#f4f8fe")
	body_panel.add_theme_stylebox_override("panel", body_style)
	app_root.add_child(body_panel)

	var body_margin := MarginContainer.new()
	body_margin.add_theme_constant_override("margin_left", 20)
	body_margin.add_theme_constant_override("margin_right", 20)
	body_margin.add_theme_constant_override("margin_top", 12)
	body_margin.add_theme_constant_override("margin_bottom", 14)
	body_panel.add_child(body_margin)

	var workspace_vbox := VBoxContainer.new()
	workspace_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	workspace_vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	workspace_vbox.add_theme_constant_override("separation", 10)
	body_margin.add_child(workspace_vbox)

	var main_hbox := HBoxContainer.new()
	main_hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	main_hbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main_hbox.add_theme_constant_override("separation", 12)
	workspace_vbox.add_child(main_hbox)

	# LEFT CARD — Structural inputs
	var left_card := PanelContainer.new()
	left_card.custom_minimum_size = Vector2(310, 0)
	left_card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var left_style := _style_box(Color("#ffffff"), Color("#e1eaf5"), 1, 12, 16)
	left_style.shadow_color = Color(0.05, 0.16, 0.34, 0.055)
	left_style.shadow_size = 8
	left_card.add_theme_stylebox_override("panel", left_style)
	main_hbox.add_child(left_card)

	var left_scroll := ScrollContainer.new()
	left_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	left_card.add_child(left_scroll)

	var left_vbox := VBoxContainer.new()
	left_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left_vbox.add_theme_constant_override("separation", 9)
	left_scroll.add_child(left_vbox)

	# Initial state: show only the structural generation form.
	structural_controls = VBoxContainer.new()
	structural_controls.add_theme_constant_override("separation", 9)
	left_vbox.add_child(structural_controls)

	var structural_title := Label.new()
	structural_title.text = "▣   Structural Inputs"
	structural_title.add_theme_font_override("font", font_poppins_bold)
	structural_title.add_theme_font_size_override("font_size", 17)
	structural_title.add_theme_color_override("font_color", COLOR_BLUE)
	structural_controls.add_child(structural_title)

	bay_x_input = _app_input_field(structural_controls, "Bay X (1–10)", "3")
	bay_y_input = _app_input_field(structural_controls, "Bay Y (1–10)", "3")
	bay_width_x_input = _app_input_field(structural_controls, "Bays Width X, m (3–9)", "6")
	bay_width_y_input = _app_input_field(structural_controls, "Bays Width Y, m (3–9)", "6")
	floor_count_input = _app_input_field(structural_controls, "Floor Count (1–10)", "4")
	story_height_input = _app_input_field(structural_controls, "Story Height, m (3–5)", "3.5")

	var generate_btn := Button.new()
	generate_btn.text = "⚙   Generate Structure   →"
	generate_btn.custom_minimum_size = Vector2(0, 56)
	generate_btn.focus_mode = Control.FOCUS_NONE
	generate_btn.add_theme_font_override("font", font_poppins_bold)
	generate_btn.add_theme_font_size_override("font_size", 15)
	generate_btn.add_theme_color_override("font_color", COLOR_WHITE)
	var generate_normal := _style_box(Color("#0865f8"), Color("#0865f8"), 0, 9, 14)
	generate_normal.shadow_color = Color(0.03, 0.28, 0.85, 0.18)
	generate_normal.shadow_size = 9
	generate_btn.add_theme_stylebox_override("normal", generate_normal)
	generate_btn.add_theme_stylebox_override("hover", _style_box(Color("#0057e8"), Color("#0057e8"), 0, 9, 14))
	generate_btn.add_theme_stylebox_override("pressed", _style_box(Color("#004dcc"), Color("#004dcc"), 0, 9, 14))
	generate_btn.pressed.connect(_on_generate_pressed)
	structural_controls.add_child(generate_btn)

	# After successful generation this replaces the editable structural form.
	# It shows the generated structural values as a read-only summary together
	# with the seismic inputs that the user can configure.
	simulation_controls = VBoxContainer.new()
	simulation_controls.add_theme_constant_override("separation", 10)
	simulation_controls.visible = false
	left_vbox.add_child(simulation_controls)

	structural_summary_title = Label.new()
	structural_summary_title.text = "▣   Your Structural Inputs"
	structural_summary_title.visible = false
	structural_summary_title.add_theme_font_override("font", font_poppins_bold)
	structural_summary_title.add_theme_font_size_override("font_size", 17)
	structural_summary_title.add_theme_color_override("font_color", COLOR_BLUE)
	simulation_controls.add_child(structural_summary_title)

	structural_summary_box = VBoxContainer.new()
	structural_summary_box.add_theme_constant_override("separation", 5)
	structural_summary_box.visible = false
	simulation_controls.add_child(structural_summary_box)

	structural_summary_divider = HSeparator.new()
	structural_summary_divider.add_theme_constant_override("separation", 6)
	structural_summary_divider.visible = false
	simulation_controls.add_child(structural_summary_divider)

	var sim_title := Label.new()
	sim_title.text = "⌁   Your Seismic Inputs"
	sim_title.add_theme_font_override("font", font_poppins_bold)
	sim_title.add_theme_font_size_override("font_size", 17)
	sim_title.add_theme_color_override("font_color", COLOR_BLUE)
	simulation_controls.add_child(sim_title)

	var sim_help := Label.new()
	sim_help.text = "Set the seismic parameters for the generated structure."
	sim_help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sim_help.add_theme_font_override("font", font_inter)
	sim_help.add_theme_font_size_override("font_size", 12)
	sim_help.add_theme_color_override("font_color", COLOR_MUTED)
	simulation_controls.add_child(sim_help)

	magnitude_input = _app_input_field(simulation_controls, "Magnitude (1–10)", "5")
	duration_input = _app_input_field(simulation_controls, "Duration, sec (10–30)", "15")

	run_simulation_button = Button.new()
	run_simulation_button.text = "▶   Run Simulation"
	run_simulation_button.custom_minimum_size = Vector2(0, 52)
	run_simulation_button.focus_mode = Control.FOCUS_NONE
	run_simulation_button.add_theme_font_override("font", font_poppins_bold)
	run_simulation_button.add_theme_font_size_override("font_size", 15)
	run_simulation_button.add_theme_color_override("font_color", COLOR_WHITE)
	run_simulation_button.add_theme_stylebox_override("normal", _style_box(COLOR_ORANGE, COLOR_ORANGE, 0, 9, 14))
	run_simulation_button.add_theme_stylebox_override("hover", _style_box(Color("#f59b23"), Color("#f59b23"), 0, 9, 14))
	run_simulation_button.add_theme_stylebox_override("pressed", _style_box(Color("#e98c12"), Color("#e98c12"), 0, 9, 14))
	run_simulation_button.pressed.connect(_on_simulate_pressed)
	simulation_controls.add_child(run_simulation_button)

	var seismic_reset_btn := Button.new()
	seismic_reset_btn.text = "↻   Reset Structure"
	seismic_reset_btn.custom_minimum_size = Vector2(0, 48)
	seismic_reset_btn.focus_mode = Control.FOCUS_NONE
	seismic_reset_btn.add_theme_font_override("font", font_poppins_bold)
	seismic_reset_btn.add_theme_font_size_override("font_size", 14)
	seismic_reset_btn.add_theme_color_override("font_color", COLOR_BLUE)
	seismic_reset_btn.add_theme_stylebox_override("normal", _style_box(Color("#ffffff"), Color("#1267f4"), 1, 9, 12))
	seismic_reset_btn.add_theme_stylebox_override("hover", _style_box(Color("#f5f9ff"), Color("#1267f4"), 1, 9, 12))
	seismic_reset_btn.add_theme_stylebox_override("pressed", _style_box(Color("#edf4ff"), Color("#1267f4"), 1, 9, 12))
	seismic_reset_btn.pressed.connect(_on_reset_pressed)
	simulation_controls.add_child(seismic_reset_btn)

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

	# CENTER — 3D workspace
	var viewport_panel := PanelContainer.new()
	viewport_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	viewport_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var vp_style := _style_box(Color("#f6fbff"), Color("#dce9f7"), 1, 12, 0)
	vp_style.shadow_color = Color(0.05, 0.16, 0.34, 0.045)
	vp_style.shadow_size = 8
	viewport_panel.add_theme_stylebox_override("panel", vp_style)
	main_hbox.add_child(viewport_panel)

	var vp_stack := Control.new()
	vp_stack.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	viewport_panel.add_child(vp_stack)

	_build_viewport_3d(vp_stack)

	vp_label = Label.new()
	vp_label.text = "Enter structural parameters and click “Generate Structure” to begin."
	vp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vp_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	vp_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vp_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vp_label.add_theme_font_override("font", font_inter)
	vp_label.add_theme_font_size_override("font_size", 14)
	vp_label.add_theme_color_override("font_color", Color("#64748b"))
	vp_stack.add_child(vp_label)

	var controls_panel := PanelContainer.new()
	controls_panel.custom_minimum_size = Vector2(205, 246)
	var ctrl_style := _style_box(Color(1, 1, 1, 0.92), Color("#e0e9f4"), 1, 10, 14)
	ctrl_style.shadow_color = Color(0.04, 0.16, 0.34, 0.05)
	ctrl_style.shadow_size = 6
	controls_panel.add_theme_stylebox_override("panel", ctrl_style)
	controls_panel.position = Vector2(14, 14)
	vp_stack.add_child(controls_panel)

	var ctrl_vbox := VBoxContainer.new()
	ctrl_vbox.add_theme_constant_override("separation", 4)
	controls_panel.add_child(ctrl_vbox)

	var ctrl_title := Label.new()
	ctrl_title.text = "◎  Camera Controls"
	ctrl_title.add_theme_font_override("font", font_poppins_bold)
	ctrl_title.add_theme_font_size_override("font_size", 16)
	ctrl_title.add_theme_color_override("font_color", COLOR_BLUE)
	ctrl_vbox.add_child(ctrl_title)

	var ctrl_desc := Label.new()
	ctrl_desc.text = "W – forward\nA – left\nS – backward\nD – right\nC – down\nSpace – up\nScroll – zoom\n\nLeft Click – interact\nRight Click – angle control"
	ctrl_desc.add_theme_font_override("font", font_inter)
	ctrl_desc.add_theme_font_size_override("font_size", 13)
	ctrl_desc.add_theme_color_override("font_color", Color("#3d5270"))
	ctrl_vbox.add_child(ctrl_desc)


	# RIGHT COLUMN
	var right_col := VBoxContainer.new()
	right_col.custom_minimum_size = Vector2(340, 0)
	right_col.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right_col.add_theme_constant_override("separation", 12)
	main_hbox.add_child(right_col)

	var preview_card := PanelContainer.new()
	preview_card.custom_minimum_size = Vector2(0, 300)
	var preview_card_style := _style_box(COLOR_WHITE, Color("#e0e9f4"), 1, 12, 14)
	preview_card_style.shadow_color = Color(0.04, 0.16, 0.34, 0.045)
	preview_card_style.shadow_size = 7
	preview_card.add_theme_stylebox_override("panel", preview_card_style)
	right_col.add_child(preview_card)

	var preview_vbox := VBoxContainer.new()
	preview_vbox.add_theme_constant_override("separation", 10)
	preview_card.add_child(preview_vbox)
	var preview_title := Label.new()
	preview_title.text = "◉   Simulation Preview"
	preview_title.add_theme_font_override("font", font_poppins_bold)
	preview_title.add_theme_font_size_override("font_size", 16)
	preview_title.add_theme_color_override("font_color", COLOR_BLUE)
	preview_vbox.add_child(preview_title)

	var preview_box := PanelContainer.new()
	preview_box.custom_minimum_size = Vector2(0, 180)
	preview_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var prev_style := _style_box(Color("#eaf6ff"), Color("#d8eafa"), 1, 10, 0)
	preview_box.add_theme_stylebox_override("panel", prev_style)
	_build_preview_3d(preview_box)
	preview_vbox.add_child(preview_box)

	var iteration_card := PanelContainer.new()
	iteration_card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var iteration_card_style := _style_box(COLOR_WHITE, Color("#e0e9f4"), 1, 12, 14)
	iteration_card_style.shadow_color = Color(0.04, 0.16, 0.34, 0.045)
	iteration_card_style.shadow_size = 7
	iteration_card.add_theme_stylebox_override("panel", iteration_card_style)
	right_col.add_child(iteration_card)

	var iteration_vbox := VBoxContainer.new()
	iteration_vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	iteration_vbox.add_theme_constant_override("separation", 6)
	iteration_card.add_child(iteration_vbox)

	var iteration_title := Label.new()
	iteration_title.text = "◴   Iteration Records"
	iteration_title.add_theme_font_override("font", font_poppins_bold)
	iteration_title.add_theme_font_size_override("font_size", 16)
	iteration_title.add_theme_color_override("font_color", COLOR_BLUE)
	iteration_vbox.add_child(iteration_title)

	iteration_label = Label.new()
	iteration_label.text = "No iterations yet\nRun a simulation to see results here."
	iteration_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	iteration_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	iteration_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	iteration_label.custom_minimum_size = Vector2(0, 52)
	iteration_label.add_theme_font_override("font", font_inter)
	iteration_label.add_theme_font_size_override("font_size", 13)
	iteration_label.add_theme_color_override("font_color", COLOR_MUTED)
	iteration_vbox.add_child(iteration_label)

	var iteration_scroll := ScrollContainer.new()
	iteration_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	iteration_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	iteration_vbox.add_child(iteration_scroll)

	iteration_list = VBoxContainer.new()
	iteration_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	iteration_list.add_theme_constant_override("separation", 6)
	iteration_scroll.add_child(iteration_list)

	# Clear Previous Runs button
	clean_runs_button = Button.new()
	clean_runs_button.text = "⌫   Clear Previous Runs"
	clean_runs_button.custom_minimum_size = Vector2(0, 42)
	clean_runs_button.focus_mode = Control.FOCUS_NONE
	clean_runs_button.add_theme_font_override("font", font_inter)
	clean_runs_button.add_theme_font_size_override("font_size", 13)
	clean_runs_button.add_theme_color_override("font_color", COLOR_MUTED)
	clean_runs_button.add_theme_color_override("font_hover_color", Color("#dc2626"))
	clean_runs_button.add_theme_color_override("font_pressed_color", Color("#b91c1c"))
	clean_runs_button.add_theme_color_override("font_disabled_color", Color("#b8c4d4"))
	clean_runs_button.add_theme_stylebox_override(
		"normal", _style_box(Color("#ffffff"), Color("#dfe7f1"), 1, 8, 8)
	)
	clean_runs_button.add_theme_stylebox_override(
		"hover", _style_box(Color("#fff7f7"), Color("#fca5a5"), 1, 8, 8)
	)
	clean_runs_button.add_theme_stylebox_override(
		"pressed", _style_box(Color("#fff1f1"), Color("#ef4444"), 1, 8, 8)
	)
	clean_runs_button.add_theme_stylebox_override(
		"disabled", _style_box(Color("#f8fafc"), Color("#e2e8f0"), 1, 8, 8)
	)
	clean_runs_button.pressed.connect(_on_clean_runs_pressed)
	iteration_vbox.add_child(clean_runs_button)

	clean_runs_dialog = ConfirmationDialog.new()
	clean_runs_dialog.title = "Clean Previous Runs"
	clean_runs_dialog.ok_button_text = "Delete"
	clean_runs_dialog.confirmed.connect(_on_clean_runs_confirmed)
	app_view_container.add_child(clean_runs_dialog)

	# Bottom terminal panel
	terminal_panel = PanelContainer.new()
	terminal_panel.custom_minimum_size = Vector2(0, 160)
	terminal_panel.size_flags_vertical = Control.SIZE_FILL
	terminal_panel.clip_contents = true
	var terminal_outer_style := _style_box(Color("#ffffff"), Color("#e0e9f4"), 1, 12, 12)
	terminal_panel.add_theme_stylebox_override("panel", terminal_outer_style)
	workspace_vbox.add_child(terminal_panel)

	var terminal_outer := VBoxContainer.new()
	terminal_outer.add_theme_constant_override("separation", 5)
	terminal_panel.add_child(terminal_outer)

	# Drag handle: drag upward to maximize, downward to minimize.
	var terminal_drag_handle := Control.new()
	terminal_drag_handle.custom_minimum_size = Vector2(0, 12)
	terminal_drag_handle.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	terminal_drag_handle.mouse_filter = Control.MOUSE_FILTER_STOP
	terminal_drag_handle.mouse_default_cursor_shape = Control.CURSOR_VSIZE
	terminal_drag_handle.tooltip_text = "Drag up or down to resize Terminal"
	terminal_drag_handle.gui_input.connect(_on_terminal_drag_handle_input)
	terminal_outer.add_child(terminal_drag_handle)

	var grip_center := CenterContainer.new()
	grip_center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	grip_center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	terminal_drag_handle.add_child(grip_center)

	var grip := ColorRect.new()
	grip.custom_minimum_size = Vector2(54, 4)
	grip.color = Color("#c7d2e0")
	grip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	grip_center.add_child(grip)

	var terminal_header := HBoxContainer.new()
	terminal_header.add_theme_constant_override("separation", 8)
	terminal_outer.add_child(terminal_header)

	var terminal_title := Label.new()
	terminal_title.text = "▣   Terminal"
	terminal_title.add_theme_font_override("font", font_poppins_bold)
	terminal_title.add_theme_font_size_override("font_size", 15)
	terminal_title.add_theme_color_override("font_color", COLOR_NAVY)
	terminal_header.add_child(terminal_title)
	var term_header_spacer := Control.new()
	term_header_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	terminal_header.add_child(term_header_spacer)

	var clear_btn := Button.new()
	clear_btn.text = "⌫  Clear"
	clear_btn.flat = true
	clear_btn.focus_mode = Control.FOCUS_NONE
	clear_btn.add_theme_font_override("font", font_inter)
	clear_btn.add_theme_font_size_override("font_size", 12)
	clear_btn.add_theme_color_override("font_color", COLOR_MUTED)
	clear_btn.pressed.connect(_reset_terminal)
	terminal_header.add_child(clear_btn)

	var console_panel := PanelContainer.new()
	console_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	console_panel.add_theme_stylebox_override("panel", _style_box(Color("#fbfdff"), Color("#d9e4f2"), 1, 10, 10))
	terminal_outer.add_child(console_panel)

	var console_margin := MarginContainer.new()
	console_margin.add_theme_constant_override("margin_left", 12)
	console_margin.add_theme_constant_override("margin_right", 12)
	console_margin.add_theme_constant_override("margin_top", 8)
	console_margin.add_theme_constant_override("margin_bottom", 8)
	console_panel.add_child(console_margin)

	term_scroll = ScrollContainer.new()
	term_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	term_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	term_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	term_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	term_scroll.mouse_filter = Control.MOUSE_FILTER_STOP
	console_margin.add_child(term_scroll)

	term_vbox = VBoxContainer.new()
	term_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	term_vbox.add_theme_constant_override("separation", 6)
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
	lbl.add_theme_font_size_override("font_size", 15)
	lbl.add_theme_color_override("font_color", Color("#223550"))
	vbox.add_child(lbl)

	var line_edit := LineEdit.new()
	line_edit.text = default_value
	line_edit.caret_blink = true
	line_edit.caret_blink_interval = 0.55
	line_edit.focus_mode = Control.FOCUS_ALL
	line_edit.editable = true
	line_edit.custom_minimum_size = Vector2(0, 40)
	# Keep the insertion caret clearly visible against the white input background.
	line_edit.add_theme_color_override("caret_color", Color("#155dfc"))
	line_edit.add_theme_color_override("selection_color", Color("#cfe0ff"))
	line_edit.add_theme_font_override("font", font_inter)
	line_edit.add_theme_font_size_override("font_size", 13)
	line_edit.add_theme_color_override("font_color", Color("#223550"))

	var normal_style := _style_box(Color("#ffffff"), Color("#d8e2ef"), 1, 7, 10)
	var focus_style := _style_box(Color("#ffffff"), Color("#5e9cf8"), 1, 7, 10)
	line_edit.add_theme_stylebox_override("normal", normal_style)
	line_edit.add_theme_stylebox_override("focus", focus_style)
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



	# Loading overlay shown during the intentional 2-second generation step.
	generation_loading_overlay = PanelContainer.new()
	generation_loading_overlay.set_anchors_preset(Control.PRESET_CENTER)
	generation_loading_overlay.offset_left = -112
	generation_loading_overlay.offset_top = -45
	generation_loading_overlay.offset_right = 112
	generation_loading_overlay.offset_bottom = 45
	generation_loading_overlay.visible = false
	var loading_style := _style_box(Color(1, 1, 1, 0.96), Color("#d7e5f6"), 1, 12, 16)
	loading_style.shadow_color = Color(0.03, 0.15, 0.32, 0.10)
	loading_style.shadow_size = 10
	generation_loading_overlay.add_theme_stylebox_override("panel", loading_style)
	parent.add_child(generation_loading_overlay)

	var loading_row := HBoxContainer.new()
	loading_row.alignment = BoxContainer.ALIGNMENT_CENTER
	loading_row.add_theme_constant_override("separation", 10)
	generation_loading_overlay.add_child(loading_row)

	if tex_terminal_loading != null:
		var loading_icon := TextureRect.new()
		loading_icon.texture = tex_terminal_loading
		loading_icon.custom_minimum_size = Vector2(26, 26)
		loading_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		loading_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		loading_row.add_child(loading_icon)
	else:
		var loading_fallback := Label.new()
		loading_fallback.text = "◌"
		loading_fallback.custom_minimum_size = Vector2(26, 26)
		loading_fallback.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		loading_fallback.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		loading_fallback.add_theme_font_override("font", font_poppins_bold)
		loading_fallback.add_theme_font_size_override("font_size", 22)
		loading_fallback.add_theme_color_override("font_color", COLOR_BLUE)
		loading_row.add_child(loading_fallback)

	var loading_text := Label.new()
	loading_text.text = "Generating structure..."
	loading_text.add_theme_font_override("font", font_inter)
	loading_text.add_theme_font_size_override("font_size", 14)
	loading_text.add_theme_color_override("font_color", Color("#374151"))
	loading_row.add_child(loading_text)

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

func _validate_inputs(include_simulation: bool = true) -> Dictionary:
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

	if include_simulation:
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

	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 9)

	var display_text := text
	var lower := text.to_lower()
	var status := "success"

	# Explicit semantic ordering prevents FAIL messages from receiving success icons.
	if text.begins_with("ERROR:") or lower.contains("fail") or lower.contains("failed"):
		status = "error"
		display_text = display_text.trim_prefix("ERROR:").strip_edges()
	elif text.begins_with("WARNING:") or lower.contains("warning"):
		status = "warning"
		display_text = display_text.trim_prefix("WARNING:").strip_edges()
	elif text.begins_with("INITIALIZING:") or lower.contains("initializing") or lower.contains("running") or lower.contains("simulating") or lower.contains("starting") or lower.contains("still running") or text == "...":
		status = "loading"
		display_text = display_text.trim_prefix("INITIALIZING:").strip_edges()
	elif text.begins_with("SUCCESS:") or lower.contains("pass") or lower.contains("complete") or lower.contains("generated") or lower.contains("saved") or lower.contains("valid"):
		status = "success"
		display_text = display_text.trim_prefix("SUCCESS:").strip_edges()

	var status_texture: Texture2D = tex_terminal_success
	match status:
		"error":
			status_texture = tex_terminal_error
		"warning":
			status_texture = tex_terminal_warning
		"loading":
			status_texture = tex_terminal_loading
		_:
			status_texture = tex_terminal_success

	if status_texture != null:
		var icon := TextureRect.new()
		icon.texture = status_texture
		icon.custom_minimum_size = Vector2(20, 20)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(icon)
	else:
		var fallback_icon := Label.new()
		fallback_icon.text = "◌" if status == "loading" else "•"
		fallback_icon.custom_minimum_size = Vector2(20, 20)
		fallback_icon.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		fallback_icon.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		fallback_icon.add_theme_font_override("font", font_poppins_bold)
		fallback_icon.add_theme_font_size_override("font_size", 18)
		fallback_icon.add_theme_color_override("font_color", COLOR_BLUE)
		row.add_child(fallback_icon)

	var line := Label.new()
	line.text = display_text
	line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.add_theme_font_override("font", font_inter)
	line.add_theme_font_size_override("font_size", 14)
	line.add_theme_color_override("font_color", Color("#374151"))
	row.add_child(line)

	term_vbox.add_child(row)
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
	_log_terminal("ProGen terminal ready")
	_log_terminal("Enter structural parameters, then generate a structure.")


func _on_terminal_drag_handle_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			terminal_drag_active = true
			terminal_drag_start_mouse_y = event.global_position.y
			terminal_drag_start_height = terminal_panel.custom_minimum_size.y
		else:
			terminal_drag_active = false
	elif event is InputEventMouseMotion and terminal_drag_active:
		# event.global_position is in viewport pixels, while the dashboard is
		# laid out in pre-scale logical pixels. Convert before resizing.
		var zoom_factor: float = maxf(0.01, float(ui_zoom_percent) / 100.0)
		var delta_y: float = (event.global_position.y - terminal_drag_start_mouse_y) / zoom_factor
		var new_height: float = terminal_drag_start_height - delta_y
		var logical_viewport_height: float = float(get_viewport_rect().size.y) / zoom_factor
		var max_height: float = maxf(220.0, logical_viewport_height - 220.0)
		# 62 px keeps the drag handle + Terminal header visible when minimized.
		terminal_panel.custom_minimum_size.y = clampf(new_height, 62.0, max_height)

func _add_structural_summary_row(label_text: String, value_text: String) -> void:
	if structural_summary_box == null:
		return

	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 8)

	var key_label := Label.new()
	key_label.text = label_text
	key_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	key_label.add_theme_font_override("font", font_inter)
	key_label.add_theme_font_size_override("font_size", 12)
	key_label.add_theme_color_override("font_color", COLOR_MUTED)
	row.add_child(key_label)

	var value_label := Label.new()
	value_label.text = value_text
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	value_label.add_theme_font_override("font", font_poppins_bold)
	value_label.add_theme_font_size_override("font_size", 12)
	value_label.add_theme_color_override("font_color", COLOR_TEXT)
	row.add_child(value_label)

	structural_summary_box.add_child(row)

func _refresh_structural_summary(params: Dictionary) -> void:
	if structural_summary_box == null:
		return
	_clear_children(structural_summary_box)

	_add_structural_summary_row("Bay X", str(params.get("bay_count_x", "-")))
	_add_structural_summary_row("Bay Y", str(params.get("bay_count_y", "-")))
	_add_structural_summary_row("Bay Width X", "%.2f m" % float(params.get("bay_width_x", 0.0)))
	_add_structural_summary_row("Bay Width Y", "%.2f m" % float(params.get("bay_width_y", 0.0)))
	_add_structural_summary_row("Floor Count", str(params.get("floor_count", "-")))
	_add_structural_summary_row("Story Height", "%.2f m" % float(params.get("story_height", 0.0)))

func _on_generate_pressed() -> void:
	var validation := _validate_inputs(false)
	if not validation["ok"]:
		for e in validation["errors"]:
			_log_terminal("ERROR: %s" % e)
		_show_toast("Please correct the structural inputs.", "error")
		return

	if not structure_display.has_sections():
		_log_terminal("ERROR: W-shape sections are not loaded; cannot draw the structure")
		_show_toast("Structural section data is not loaded.", "error")
		return

	var params: Dictionary = validation["params"]
	var topo := StructureGenerator.generate(params)
	var check := StructureValidator.validate(params, topo)
	if not check["ok"]:
		for e in check["errors"]:
			_log_terminal("ERROR: %s" % e)
		_show_toast("Structure validation failed.", "error")
		return

	_show_toast("Generating structure...", "info")
	_log_terminal("INITIALIZING: generating structure")
	if generation_loading_overlay:
		generation_loading_overlay.visible = true
	vp_label.visible = false

	# Intentional 2-second generation/loading state requested for the UI.
	await get_tree().create_timer(2.0).timeout

	current_params = params
	current_topo = topo
	has_structure = true

	# After Generate, show only Your Seismic Inputs.
	if structural_summary_title:
		structural_summary_title.visible = false
	if structural_summary_box:
		structural_summary_box.visible = false
	if structural_summary_divider:
		structural_summary_divider.visible = false
	if structural_controls:
		structural_controls.visible = false
	if simulation_controls:
		simulation_controls.visible = true
	_stop_live_shake()
	_clear_preview()
	structure_display.build(topo)
	_frame_camera_on_structure(params)
	rule_preview_dropdown.select(0)
	rule_preview_dropdown.visible = true
	if generation_loading_overlay:
		generation_loading_overlay.visible = false

	var nodes: Dictionary = topo["nodes"]
	_log_terminal(
		"SUCCESS: generated %d nodes, %d columns, %d beams (all members %s)" % [
			nodes.size(), (topo["columns"] as Array).size(), (topo["beams"] as Array).size(),
			StaticStructureView.STARTING_SECTION
		]
	)
	for w in check["warnings"]:
		_log_terminal("WARNING: %s" % w)
	_show_toast("Structure generated successfully.", "success")

func _frame_camera_on_structure(params: Dictionary) -> void:
	if structure_camera == null:
		return
	var width_x: float = params["bay_count_x"] * params["bay_width_x"]
	var width_z: float = params["bay_count_y"] * params["bay_width_y"]
	var height_y: float = params["floor_count"] * params["story_height"]
	var extents := Vector3(width_x, height_y, width_z)
	var center := extents / 2.0
	structure_zoom_target = center
	_reset_structure_zoom()

	var bounding_radius := extents.length() / 2.0
	var half_fov_rad := deg_to_rad(structure_camera.fov) / 2.0
	var distance: float = max(bounding_radius / sin(half_fov_rad) * 1.35, 6.0)

	var direction := Vector3(1.0, 0.7, 1.0).normalized()
	structure_camera.global_position = center + direction * distance
	structure_camera.look_at(center, Vector3.UP)
	structure_camera.sync_look_from_rotation()

func _change_ui_zoom(delta_percent: int) -> void:
	_set_ui_zoom(ui_zoom_percent + delta_percent)

func _set_ui_zoom(percent: int) -> void:
	ui_zoom_percent = clampi(percent, 70, 130)
	if ui_zoom_label:
		ui_zoom_label.text = "%d%%" % ui_zoom_percent

	# Scale only the dashboard instead of changing the Window content scale.
	# This preserves correct mouse-wheel scrolling and drag coordinates.
	var window := get_window()
	if window:
		window.content_scale_factor = 1.0

	_apply_ui_zoom_layout()
	_show_toast("Interface zoom: %d%%" % ui_zoom_percent, "info")

func _apply_ui_zoom_layout() -> void:
	if app_view_container == null:
		return

	var factor: float = maxf(0.01, float(ui_zoom_percent) / 100.0)
	var viewport_size := get_viewport_rect().size

	# Give the dashboard an inverse logical size, then visually scale it.
	# Result: browser-like UI zoom while Control input transforms remain valid.
	app_view_container.set_anchors_preset(Control.PRESET_TOP_LEFT)
	app_view_container.position = Vector2.ZERO
	app_view_container.scale = Vector2(factor, factor)
	app_view_container.size = viewport_size / factor

func _zoom_structure(delta_percent: int) -> void:
	if structure_camera == null or not has_structure:
		return

	var new_percent: int = clampi(structure_zoom_percent + delta_percent, 40, 200)
	if new_percent == structure_zoom_percent:
		return

	# Higher percent = camera moves closer to the structure target.
	var old_scale := 100.0 / float(structure_zoom_percent)
	var new_scale := 100.0 / float(new_percent)
	var direction := structure_camera.global_position - structure_zoom_target
	if direction.length() < 0.001:
		return
	var base_vector := direction / old_scale
	structure_camera.global_position = structure_zoom_target + base_vector * new_scale
	structure_camera.look_at(structure_zoom_target, Vector3.UP)
	structure_camera.sync_look_from_rotation()

	structure_zoom_percent = new_percent
	if structure_zoom_label:
		structure_zoom_label.text = "%d%%" % structure_zoom_percent

func _reset_structure_zoom() -> void:
	structure_zoom_percent = 100
	if structure_zoom_label:
		structure_zoom_label.text = "100%"

func _show_toast(message: String, kind: String = "success") -> void:
	if app_view_container == null:
		return

	var toast := PanelContainer.new()
	toast.z_index = 5000
	toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	toast.modulate.a = 0.0

	# Center the notification horizontally near the top-middle of the dashboard.
	toast.set_anchors_preset(Control.PRESET_CENTER_TOP)
	toast.offset_left = -230
	toast.offset_top = 28
	toast.offset_right = 230
	toast.offset_bottom = 96

	var border := Color("#86efac")
	var bg := Color("#ecfdf5")
	var fg := Color("#166534")
	var icon_text := "✓"
	if kind == "info":
		border = Color("#93c5fd")
		bg = Color("#eaf3ff")
		fg = COLOR_BLUE
		icon_text = "•"
	elif kind == "warning":
		border = Color("#facc15")
		bg = Color("#fff8d6")
		fg = Color("#b45309")
		icon_text = "!"
	elif kind == "error":
		border = Color("#f87171")
		bg = Color("#fff0f0")
		fg = Color("#b91c1c")
		icon_text = "!"

	var st := _style_box(bg, border, 2, 12, 16)
	st.shadow_color = Color(0.02, 0.08, 0.18, 0.22)
	st.shadow_size = 16
	toast.add_theme_stylebox_override("panel", st)
	app_view_container.add_child(toast)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	toast.add_child(row)

	var icon := Label.new()
	icon.text = icon_text
	icon.add_theme_font_override("font", font_poppins_bold)
	icon.add_theme_font_size_override("font_size", 20)
	icon.add_theme_color_override("font_color", fg)
	row.add_child(icon)

	var lbl := Label.new()
	lbl.text = message
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.add_theme_font_override("font", font_inter)
	lbl.add_theme_font_size_override("font_size", 13)
	lbl.add_theme_color_override("font_color", Color("#374151"))
	row.add_child(lbl)

	var tween := create_tween()
	tween.tween_property(toast, "modulate:a", 1.0, 0.16)
	tween.tween_interval(2.0)
	tween.tween_property(toast, "modulate:a", 0.0, 0.28)
	tween.tween_callback(toast.queue_free)

func _on_simulate_pressed() -> void:
	if not has_structure:
		_log_terminal("ERROR: generate a structure before running the simulation")
		return

	var validation := _validate_inputs()
	if not validation["ok"]:
		for e in validation["errors"]:
			_log_terminal("ERROR: %s" % e)
		return

	# When Run Simulation is clicked, reveal the generated structural inputs
	# above Your Seismic Inputs.
	_refresh_structural_summary(current_params)
	if structural_summary_title:
		structural_summary_title.visible = true
	if structural_summary_box:
		structural_summary_box.visible = true
	if structural_summary_divider:
		structural_summary_divider.visible = true

	# Once the simulation is launched, hide Run Simulation so the only
	# action left in this state is Reset Structure.
	if run_simulation_button:
		run_simulation_button.visible = false

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
	_show_toast("Simulation started.", "info")
	_start_python_nltha(sim_params, run_dir)
	_log_terminal(
		"INITIALIZING: seismic simulation — magnitude %.1f, duration %.1fs" % [
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
	if is_instance_valid(clean_runs_button):
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
	var final_status := str(summary.get("final_status", "?"))
	var terminal_prefix := "SUCCESS:" if final_status.to_upper() == "PASS" else "ERROR:"
	_log_terminal("%s run complete: %d iteration(s) saved, stopped because: %s, final result: %s" % [terminal_prefix,
		int(summary.get("iterations_completed", 0)), str(summary.get("stop_reason", "unknown")),
		final_status
	])
	iteration_label.text = "Completed: %d iteration(s) -- %s" % [
		int(summary.get("iterations_completed", 0)), str(summary.get("stop_reason", "unknown"))]

func _add_iteration_entry(index: int, record: Dictionary) -> void:
	var rules: Array[String] = []
	var evaluation = record.get("evaluation")
	if evaluation is Dictionary:
		for entry in evaluation.get("triggered_rules", []):
			rules.append(str(int(entry.get("rule", 0))))

	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 6)

	var button := Button.new()
	button.text = "Iteration %d  %s%s" % [index, record.get("overall_status", "?"),
		("  (rules " + ", ".join(rules) + ")") if not rules.is_empty() else ""]
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
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
	row.add_child(button)

	var download_btn := Button.new()
	download_btn.text = "⬇"
	download_btn.tooltip_text = "Download iteration %d record" % index
	download_btn.custom_minimum_size = Vector2(44, 40)
	download_btn.focus_mode = Control.FOCUS_NONE
	download_btn.add_theme_font_override("font", font_poppins_bold)
	download_btn.add_theme_font_size_override("font_size", 24)
	download_btn.add_theme_color_override("font_color", Color("#0755e9"))
	download_btn.add_theme_color_override("font_hover_color", Color("#003fc4"))
	download_btn.add_theme_color_override("font_pressed_color", Color("#00349f"))
	download_btn.add_theme_color_override("font_focus_color", Color("#0755e9"))
	download_btn.add_theme_stylebox_override("normal", _style_box(Color("#eaf2ff"), Color("#8bb5ff"), 2, 8, 4))
	download_btn.add_theme_stylebox_override("hover", _style_box(Color("#d8e7ff"), Color("#0755e9"), 2, 8, 4))
	download_btn.add_theme_stylebox_override("pressed", _style_box(Color("#c5dcff"), Color("#003fc4"), 2, 8, 4))
	download_btn.pressed.connect(func(): _download_iteration_record(run_dir, index))
	row.add_child(download_btn)

	iteration_list.add_child(row)

func _download_iteration_record(run_dir: String, index: int) -> void:
	var record_path := run_dir.path_join("iteration_%d" % index).path_join("record.json")
	var record = _read_json(record_path)
	if not record is Dictionary:
		_log_terminal("ERROR: iteration %d record could not be found" % index)
		return

	var json_text := JSON.stringify(record, "\t")
	var filename := "ProGen_iteration_%d_record.json" % index

	if OS.has_feature("web"):
		JavaScriptBridge.download_buffer(json_text.to_utf8_buffer(), filename, "application/json")
		_log_terminal("downloaded iteration %d record" % index)
		return

	var save_path := "user://%s" % filename
	var file := FileAccess.open(save_path, FileAccess.WRITE)
	if file == null:
		_log_terminal("ERROR: could not save iteration %d record" % index)
		return
	file.store_string(json_text)
	file.close()
	_log_terminal("saved iteration %d record to %s" % [index, save_path])


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
	if simulation_controls:
		simulation_controls.visible = false
	if structural_summary_title:
		structural_summary_title.visible = false
	if structural_summary_box:
		structural_summary_box.visible = false
	if structural_summary_divider:
		structural_summary_divider.visible = false
	if structural_controls:
		structural_controls.visible = true
	if run_simulation_button:
		run_simulation_button.visible = true
	current_params = {}
	current_topo = {}
	vp_label.visible = true
	rule_preview_dropdown.select(0)
	rule_preview_dropdown.visible = false
	_reset_terminal()
	_reset_structure_zoom()
	_show_toast("Structure reset.", "info")

func _on_rule_preview_selected(index: int) -> void:
	structure_display.build(current_topo)
	if index <= 0:
		return
	var rule_label := rule_preview_dropdown.get_item_text(index)
	var description := structure_display.preview_rule(index, current_topo)
	_log_terminal(
		"preview: %s -- %s (visual mock-up only; no section data changed, no re-analysis run)" % [rule_label, description]
	)

func _numbered_feature_card(number: String, title: String, description: String, icon: Texture2D) -> PanelContainer:
	var card := PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.custom_minimum_size = Vector2(0, 178)
	var st := _style_box(Color(1, 1, 1, 0.94), Color("#d9e7f8"), 1, 13, 22)
	st.shadow_color = Color(0.04, 0.22, 0.60, 0.055)
	st.shadow_size = 9
	card.add_theme_stylebox_override("panel", st)
	var inner := VBoxContainer.new()
	inner.add_theme_constant_override("separation", 10)
	card.add_child(inner)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 12)
	inner.add_child(top)
	var num := Label.new()
	num.text = "  %s  " % number
	num.add_theme_font_override("font", font_poppins_bold)
	num.add_theme_font_size_override("font_size", 13)
	num.add_theme_color_override("font_color", COLOR_BLUE)
	num.add_theme_stylebox_override("normal", _style_box(COLOR_BLUE_SOFT, COLOR_BLUE_SOFT, 0, 14, 6))
	top.add_child(num)
	var icon_rect := TextureRect.new()
	icon_rect.texture = icon
	icon_rect.custom_minimum_size = Vector2(34, 34)
	icon_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	top.add_child(icon_rect)
	inner.add_child(_left_label(title, font_poppins_bold, 18, COLOR_TEXT))
	var d := _body_label(description, 14)
	d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	inner.add_child(d)
	return card

func _compact_proof_item(icon_text: String, text: String) -> HBoxContainer:
	var item := HBoxContainer.new()
	item.custom_minimum_size = Vector2(220, 30)
	item.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	item.alignment = BoxContainer.ALIGNMENT_CENTER
	item.add_theme_constant_override("separation", 8)

	var icon := Label.new()
	icon.text = icon_text
	icon.custom_minimum_size = Vector2(24, 24)
	icon.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	icon.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	icon.add_theme_font_override("font", font_poppins_bold)
	icon.add_theme_font_size_override("font_size", 15)
	icon.add_theme_color_override("font_color", COLOR_BLUE)
	item.add_child(icon)

	var label := Label.new()
	label.text = text + "  ✓"
	label.autowrap_mode = TextServer.AUTOWRAP_OFF
	label.add_theme_font_override("font", font_inter)
	label.add_theme_font_size_override("font_size", 12)
	label.add_theme_color_override("font_color", COLOR_TEXT)
	item.add_child(label)
	return item

func _simple_stage_card(icon_text: String, title: String, subtitle: String, bullets: Array) -> PanelContainer:
	var card := PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.custom_minimum_size = Vector2(0, 250)
	var st := _style_box(Color(1, 1, 1, 0.96), Color("#d9e7f8"), 1, 13, 26)
	st.shadow_color = Color(0.04, 0.22, 0.60, 0.06)
	st.shadow_size = 9
	card.add_theme_stylebox_override("panel", st)

	var inner := VBoxContainer.new()
	inner.add_theme_constant_override("separation", 10)
	card.add_child(inner)

	# Left-aligned icon + title on one line.
	var top := HBoxContainer.new()
	top.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.alignment = BoxContainer.ALIGNMENT_BEGIN
	top.add_theme_constant_override("separation", 10)
	inner.add_child(top)

	var icon := Label.new()
	icon.text = icon_text
	icon.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	icon.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	icon.custom_minimum_size = Vector2(42, 42)
	icon.add_theme_font_override("font", font_poppins_bold)
	icon.add_theme_font_size_override("font_size", 22)
	icon.add_theme_color_override("font_color", COLOR_BLUE)
	icon.add_theme_stylebox_override("normal", _style_box(COLOR_BLUE_SOFT, COLOR_BLUE_SOFT, 0, 21))
	top.add_child(icon)

	var title_label := Label.new()
	title_label.text = title
	title_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title_label.add_theme_font_override("font", font_poppins_bold)
	title_label.add_theme_font_size_override("font_size", 19)
	title_label.add_theme_color_override("font_color", COLOR_TEXT)
	top.add_child(title_label)

	var subtitle_label := _left_label(subtitle, font_inter, 14, COLOR_MUTED)
	subtitle_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	subtitle_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inner.add_child(subtitle_label)

	for bullet in bullets:
		var bullet_label := _left_label("•  %s" % bullet, font_inter, 13, COLOR_MUTED)
		inner.add_child(bullet_label)
	return card


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

func _load_texture_first(paths: Array[String]) -> Texture2D:
	for path in paths:
		if ResourceLoader.exists(path):
			var texture := load(path) as Texture2D
			if texture:
				return texture
	return null

func _clear_children(node: Node) -> void:
	for child in node.get_children():
		node.remove_child(child)
		child.queue_free()

func _set_panel_texture_bg(panel: PanelContainer, texture: Texture2D) -> void:
	var style := StyleBoxTexture.new()
	style.texture = texture
	panel.add_theme_stylebox_override("panel", style)
