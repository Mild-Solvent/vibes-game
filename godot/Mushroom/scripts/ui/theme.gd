extends RefCounted
## The menu look, built in code: chunky low-poly panels (corner_detail 2-3 gives faceted corners),
## wood-brown borders, forest-green buttons and cream text, like a painted sign in a Slovak village.
## Fonts are system fonts rendered as MSDF so they stay sharp when the menu layer is scaled.
##
## Type variations (set `theme_type_variation` on a control): "Plank" / "Card" / "Inset" / "KeyCap"
## (PanelContainer), "Title" / "Heading" / "Dim" / "Small" / "KeyLabel" (Label),
## "Danger" / "Tab" / "Big" (Button).

const CREAM := Color("f3e9d2")
const CREAM_DIM := Color("cbbf9f")
const INK := Color("2a1c10")
const WOOD := Color("7a4e2a")
const WOOD_LIGHT := Color("9a673b")
const WOOD_DARK := Color("3d2615")
const FOREST := Color("3f6b35")
const FOREST_HOVER := Color("558a43")
const FOREST_DARK := Color("27461f")
const MOSS := Color("1d2a19")
const NIGHT := Color("121a10")
const RED := Color("c3462c")
const RED_HOVER := Color("db5a3c")
const GOLD := Color("e8b84a")
const BASE_SIZE := 20


static func build() -> Theme:
	var t := Theme.new()
	t.default_font = body_font()
	t.default_font_size = BASE_SIZE

	# Labels
	t.set_color("font_color", "Label", CREAM)
	t.set_color("font_outline_color", "Label", Color(0, 0, 0, 0.55))
	t.set_constant("outline_size", "Label", 0)
	t.set_constant("line_spacing", "Label", 3)
	_label_variation(t, "Title", 74, GOLD, WOOD_DARK, 16, heading_font())
	_label_variation(t, "Heading", 32, CREAM, WOOD_DARK, 8, heading_font())
	_label_variation(t, "Dim", 18, CREAM_DIM, Color(0, 0, 0, 0), 0, null)
	_label_variation(t, "Small", 16, CREAM_DIM, Color(0, 0, 0, 0), 0, null)
	_label_variation(t, "KeyLabel", 18, INK, Color(0, 0, 0, 0), 0, heading_font())

	# Panels
	t.set_stylebox("panel", "PanelContainer", box(MOSS.lerp(Color.BLACK, 0.1), WOOD, 6, 18, 3, 28, 0.94))
	(t.get_stylebox("panel", "PanelContainer") as StyleBoxFlat).shadow_size = 18
	(t.get_stylebox("panel", "PanelContainer") as StyleBoxFlat).shadow_color = Color(0, 0, 0, 0.45)
	t.set_stylebox("panel", "Panel", box(MOSS, WOOD, 6, 18, 3, 0))
	_panel_variation(t, "Plank", _plank())
	_panel_variation(t, "Card", box(Color("26381f"), Color("3d5a2f"), 3, 12, 2, 18))
	_panel_variation(t, "Inset", box(NIGHT, WOOD_DARK, 3, 10, 2, 14, 0.9))
	var cap := box(CREAM, CREAM_DIM.darkened(0.35), 2, 7, 2, 0)
	cap.border_width_bottom = 5
	cap.content_margin_left = 12
	cap.content_margin_right = 12
	cap.content_margin_top = 4
	cap.content_margin_bottom = 6
	_panel_variation(t, "KeyCap", cap)

	# Buttons
	_button_styles(t, "Button", FOREST, FOREST_HOVER, FOREST_DARK)
	t.set_font_size("font_size", "Button", 22)
	for c in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"]:
		t.set_color(c, "Button", CREAM)
	t.set_color("font_disabled_color", "Button", Color(CREAM, 0.4))
	t.set_constant("h_separation", "Button", 10)
	t.set_type_variation("Danger", "Button")
	_button_styles(t, "Danger", RED.darkened(0.15), RED_HOVER, RED.darkened(0.4))
	t.set_type_variation("Big", "Button")
	t.set_font_size("font_size", "Big", 26)
	t.set_font("font", "Big", heading_font())
	t.set_type_variation("Tab", "Button")
	_button_styles(t, "Tab", WOOD_DARK, WOOD, WOOD_LIGHT)
	t.set_stylebox("hover_pressed", "Tab", t.get_stylebox("pressed", "Tab"))
	t.set_font_size("font_size", "Tab", 20)

	# Text input
	var edit := box(NIGHT, WOOD_DARK, 3, 8, 2, 0, 0.95)
	_margins(edit, 14, 8)
	var edit_focus := edit.duplicate() as StyleBoxFlat
	edit_focus.border_color = GOLD
	t.set_stylebox("normal", "LineEdit", edit)
	t.set_stylebox("focus", "LineEdit", edit_focus)
	t.set_stylebox("read_only", "LineEdit", edit)
	t.set_color("font_color", "LineEdit", CREAM)
	t.set_color("font_placeholder_color", "LineEdit", Color(CREAM, 0.35))
	t.set_color("caret_color", "LineEdit", GOLD)
	t.set_color("selection_color", "LineEdit", Color(FOREST_HOVER, 0.7))
	t.set_font_size("font_size", "LineEdit", 22)

	# Sliders
	var track := box(NIGHT, WOOD_DARK, 2, 6, 2, 0)
	track.content_margin_top = 5
	track.content_margin_bottom = 5
	var fill := box(FOREST_HOVER, FOREST_DARK, 2, 6, 2, 0)
	fill.content_margin_top = 5
	fill.content_margin_bottom = 5
	t.set_stylebox("slider", "HSlider", track)
	t.set_stylebox("grabber_area", "HSlider", fill)
	t.set_stylebox("grabber_area_highlight", "HSlider", fill)
	t.set_icon("grabber", "HSlider", _knob(CREAM))
	t.set_icon("grabber_highlight", "HSlider", _knob(GOLD))
	t.set_icon("grabber_disabled", "HSlider", _knob(CREAM_DIM))

	# Toggles
	t.set_icon("checked", "CheckButton", _switch(true))
	t.set_icon("unchecked", "CheckButton", _switch(false))
	t.set_icon("checked_disabled", "CheckButton", _switch(true))
	t.set_icon("unchecked_disabled", "CheckButton", _switch(false))
	var flat := StyleBoxEmpty.new()
	_margins(flat, 4, 4)
	var flat_focus := box(Color(0, 0, 0, 0), GOLD, 2, 8, 2, 0)
	for s in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
		t.set_stylebox(s, "CheckButton", flat)
	t.set_stylebox("focus", "CheckButton", flat_focus)
	for c in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"]:
		t.set_color(c, "CheckButton", CREAM)
	t.set_font_size("font_size", "CheckButton", 20)

	# Dropdowns
	_button_styles(t, "OptionButton", WOOD_DARK, WOOD, WOOD_DARK.darkened(0.2))
	t.set_font_size("font_size", "OptionButton", 20)
	for c in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		t.set_color(c, "OptionButton", CREAM)
	var popup := box(MOSS, WOOD, 3, 8, 2, 8)
	t.set_stylebox("panel", "PopupMenu", popup)
	t.set_stylebox("hover", "PopupMenu", box(FOREST, FOREST, 0, 6, 2, 6))
	t.set_color("font_color", "PopupMenu", CREAM)
	t.set_color("font_hover_color", "PopupMenu", CREAM)
	t.set_font_size("font_size", "PopupMenu", 20)
	t.set_constant("v_separation", "PopupMenu", 10)

	# Progress (mic meter)
	t.set_stylebox("background", "ProgressBar", box(NIGHT, WOOD_DARK, 2, 6, 2, 0))
	t.set_stylebox("fill", "ProgressBar", box(FOREST_HOVER, FOREST_HOVER, 0, 6, 2, 0))

	# Scroll bars
	var sb := box(Color(0, 0, 0, 0.35), Color(0, 0, 0, 0), 0, 6, 2, 0)
	_margins(sb, 4, 4)
	t.set_stylebox("scroll", "VScrollBar", sb)
	t.set_stylebox("grabber", "VScrollBar", box(WOOD, WOOD, 0, 6, 2, 0))
	t.set_stylebox("grabber_highlight", "VScrollBar", box(WOOD_LIGHT, WOOD_LIGHT, 0, 6, 2, 0))
	t.set_stylebox("grabber_pressed", "VScrollBar", box(GOLD, GOLD, 0, 6, 2, 0))

	# Rich text (credits)
	t.set_color("default_color", "RichTextLabel", CREAM)
	t.set_font("bold_font", "RichTextLabel", heading_font())
	t.set_font_size("normal_font_size", "RichTextLabel", 18)
	t.set_font_size("bold_font_size", "RichTextLabel", 20)
	t.set_constant("line_separation", "RichTextLabel", 4)

	t.set_constant("separation", "VBoxContainer", 12)
	t.set_constant("separation", "HBoxContainer", 12)
	return t


## A StyleBoxFlat with faceted ("low-poly") corners.
static func box(bg: Color, border: Color, border_w: int, radius: int, detail: int, margin: int,
		alpha := 1.0) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(bg, bg.a * alpha)
	s.border_color = border
	s.set_border_width_all(border_w)
	s.set_corner_radius_all(radius)
	s.corner_detail = detail
	s.anti_aliasing = true
	s.set_content_margin_all(margin)
	return s


static func body_font() -> Font:
	var f := SystemFont.new()
	f.font_names = PackedStringArray(["Trebuchet MS", "Segoe UI", "Verdana", "DejaVu Sans", "sans-serif"])
	f.font_weight = 600
	f.multichannel_signed_distance_field = true
	f.msdf_pixel_range = 12
	return f


static func heading_font() -> Font:
	var f := SystemFont.new()
	f.font_names = PackedStringArray(["Georgia", "Cambria", "Bookman Old Style", "DejaVu Serif", "serif"])
	f.font_weight = 800
	f.multichannel_signed_distance_field = true
	f.msdf_pixel_range = 16
	return f


static func _label_variation(t: Theme, n: String, size: int, color: Color, outline: Color, outline_size: int,
		font: Font) -> void:
	t.set_type_variation(n, "Label")
	t.set_font_size("font_size", n, size)
	t.set_color("font_color", n, color)
	t.set_color("font_outline_color", n, outline)
	t.set_constant("outline_size", n, outline_size)
	if font:
		t.set_font("font", n, font)


static func _panel_variation(t: Theme, n: String, style: StyleBox) -> void:
	t.set_type_variation(n, "PanelContainer")
	t.set_stylebox("panel", n, style)


static func _plank() -> StyleBoxFlat:
	var s := box(WOOD, WOOD_DARK, 0, 8, 2, 0)
	s.border_width_bottom = 6
	s.border_width_top = 2
	s.border_color = WOOD_DARK
	s.content_margin_left = 26
	s.content_margin_right = 26
	s.content_margin_top = 6
	s.content_margin_bottom = 10
	s.shadow_color = Color(0, 0, 0, 0.35)
	s.shadow_size = 6
	s.shadow_offset = Vector2(0, 3)
	return s


static func _button_styles(t: Theme, type: String, base: Color, hover: Color, pressed: Color) -> void:
	var normal := _chunky(base)
	var over := _chunky(hover)
	var down := _chunky(pressed)
	down.border_width_bottom = 2
	down.content_margin_top += 3
	down.content_margin_bottom -= 3
	var off := _chunky(base.lerp(Color("404040"), 0.6))
	off.bg_color.a = 0.6
	var focus := box(Color(0, 0, 0, 0), GOLD, 3, 9, 2, 0)
	focus.expand_margin_left = 3
	focus.expand_margin_right = 3
	focus.expand_margin_top = 3
	focus.expand_margin_bottom = 3
	t.set_stylebox("normal", type, normal)
	t.set_stylebox("hover", type, over)
	t.set_stylebox("pressed", type, down)
	t.set_stylebox("hover_pressed", type, down)
	t.set_stylebox("disabled", type, off)
	t.set_stylebox("focus", type, focus)


static func _chunky(c: Color) -> StyleBoxFlat:
	var s := box(c, c.darkened(0.45), 2, 9, 2, 0)
	s.border_width_bottom = 5
	s.content_margin_left = 22
	s.content_margin_right = 22
	s.content_margin_top = 9
	s.content_margin_bottom = 11
	return s


static func _margins(s: StyleBox, h: float, v: float) -> void:
	s.content_margin_left = h
	s.content_margin_right = h
	s.content_margin_top = v
	s.content_margin_bottom = v


## A round slider knob with a wood rim.
static func _knob(c: Color) -> Texture2D:
	var n := 26
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	var mid := (n - 1) / 2.0
	for y in n:
		for x in n:
			var d := Vector2(x - mid, y - mid).length()
			var a := clampf(mid - d + 0.5, 0.0, 1.0)
			var col := WOOD_DARK if d > mid - 3.5 else c
			img.set_pixel(x, y, Color(col, a))
	return ImageTexture.create_from_image(img)


## An on/off pill switch for CheckButton.
static func _switch(on: bool) -> Texture2D:
	var w := 52
	var h := 28
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var r := h / 2.0
	var track := FOREST_HOVER if on else Color("4a4033")
	var knob_x := w - r if on else r
	for y in h:
		for x in w:
			var p := Vector2(x + 0.5, y + 0.5)
			var cx := clampf(p.x, r, w - r)
			var d := p.distance_to(Vector2(cx, r))
			var a := clampf(r - d, 0.0, 1.0)
			var col := WOOD_DARK if d > r - 2.5 else track
			var kd := p.distance_to(Vector2(knob_x, r))
			if kd < r - 4.0:
				col = CREAM
				a = clampf(r - 4.0 - kd, 0.0, 1.0) + a * (1.0 - clampf(r - 4.0 - kd, 0.0, 1.0))
			img.set_pixel(x, y, Color(col, a))
	return ImageTexture.create_from_image(img)
