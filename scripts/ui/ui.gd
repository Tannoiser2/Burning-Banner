class_name UI
extends RefCounted
## Helper grafici condivisi: tavolozza, font, texture delle carte e dei segnalini.

const D = preload("res://scripts/data/bb_data.gd")

const GOLD := Color("#e0a64a")
const EMBER := Color("#e2622c")
const BRASS := Color("#b8923e")
const DARK := Color("#14110c")
const PANEL := Color("#1b1712")
const PAPER := Color("#ece0c2")
const INK := Color("#2a2218")
const RED := Color("#e0553f")
const GREEN := Color("#7fd36f")
const MUTED := Color("#a89c86")

static var _tex := {}
static var _atlas := {}
static var font_title: Font
static var font_body: Font
static var font_bold: Font
static var font_italic: Font


static func init_fonts() -> void:
	if font_title != null:
		return
	var fv := FontVariation.new()
	fv.base_font = load("res://assets/fonts/Cinzel.ttf")
	fv.variation_opentype = {"wght": 700}
	font_title = fv
	font_body = load("res://assets/fonts/BarlowCondensed-Medium.ttf")
	font_bold = load("res://assets/fonts/BarlowCondensed-SemiBold.ttf")
	font_italic = load("res://assets/fonts/BarlowCondensed-BoldItalic.ttf")


static func tex(path: String) -> Texture2D:
	if not _tex.has(path):
		_tex[path] = load(path)
	return _tex[path]


static func card_tex(id: String) -> Texture2D:
	var p := "res://assets/cards/%s.jpg" % id
	if not ResourceLoader.exists(p):
		return null
	return tex(p)


static var _counters := {}


## Immagine di un segnalino (armata, eroe, mostro…) ritagliata dall'atlante.
static func counter_tex(key: String) -> Texture2D:
	if _counters.is_empty():
		var f := FileAccess.open("res://data/counters.json", FileAccess.READ)
		_counters = JSON.parse_string(f.get_as_text())
	var k := "c#" + key
	if not _atlas.has(k):
		var idx: int = int(_counters["idx"].get(key, -1))
		if idx < 0:
			return null
		var cols := int(_counters["cols"])
		var cell := int(_counters["cell"])
		var a := AtlasTexture.new()
		a.atlas = tex("res://assets/counters/atlas.webp")
		a.region = Rect2((idx % cols) * cell, (idx / cols) * cell, cell, cell)
		_atlas[k] = a
	return _atlas[k]


static func kcol(k: int) -> Color:
	return D.KINGDOMS[k]["col"] if k >= 0 and k < D.KINGDOMS.size() else Color("#888888")


static func klight(k: int) -> Color:
	return D.KINGDOMS[k]["light"] if k >= 0 and k < D.KINGDOMS.size() else Color("#cccccc")


static func panel_style(bg: Color, border: Color, bw := 1, radius := 6) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(bw)
	sb.set_corner_radius_all(radius)
	sb.set_content_margin_all(10)
	return sb


static func label(text: String, size := 20, col := Color("#eeeeee"), font: Font = null) -> Label:
	init_fonts()
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	if font != null:
		l.add_theme_font_override("font", font)
	return l


static func title(text: String, size := 40, col := GOLD) -> Label:
	init_fonts()
	var l := label(text, size, col, font_title)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	l.add_theme_constant_override("outline_size", 6)
	return l


static func rich(size := 20) -> RichTextLabel:
	var r := RichTextLabel.new()
	r.bbcode_enabled = true
	r.fit_content = true
	r.scroll_active = false
	r.add_theme_font_size_override("normal_font_size", size)
	r.add_theme_font_size_override("bold_font_size", size)
	r.add_theme_font_size_override("italics_font_size", size)
	return r


static func icon_rect(t: Texture2D, sz: Vector2) -> TextureRect:
	var r := TextureRect.new()
	r.texture = t
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	r.custom_minimum_size = sz
	r.size = sz
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r


static func button(text: String, w := 200.0, h := 54.0, size := 24) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(w, h)
	b.add_theme_font_size_override("font_size", size)
	return b


static func primary(b: Button) -> Button:
	b.add_theme_stylebox_override("normal", panel_style(GOLD, GOLD, 2, 6))
	b.add_theme_stylebox_override("hover", panel_style(Color("#efcf7c"), Color.WHITE, 2, 6))
	b.add_theme_color_override("font_color", DARK)
	b.add_theme_color_override("font_hover_color", DARK)
	return b


static func make_theme() -> Theme:
	init_fonts()
	var th := Theme.new()
	th.default_font = font_body
	th.default_font_size = 20
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("#2a241a")
	sb.border_color = GOLD
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(5)
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	sb.content_margin_top = 6
	sb.content_margin_bottom = 6
	th.set_stylebox("normal", "Button", sb)
	var sbh := sb.duplicate()
	sbh.bg_color = Color("#4a3c22")
	th.set_stylebox("hover", "Button", sbh)
	var sbp := sb.duplicate()
	sbp.bg_color = GOLD
	th.set_stylebox("pressed", "Button", sbp)
	var sbd := sb.duplicate()
	sbd.bg_color = Color("#1a1712")
	sbd.border_color = Color("#555048")
	th.set_stylebox("disabled", "Button", sbd)
	th.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	th.set_color("font_color", "Button", Color.WHITE)
	th.set_color("font_hover_color", "Button", GOLD)
	th.set_color("font_pressed_color", "Button", DARK)
	th.set_color("font_disabled_color", "Button", Color("#777777"))
	th.set_font("font", "Button", font_bold)
	th.set_font_size("font_size", "Button", 22)
	th.set_color("font_color", "Label", Color("#eeeeee"))
	var pn := StyleBoxFlat.new()
	pn.bg_color = PANEL
	pn.border_color = Color("#000000")
	pn.set_border_width_all(1)
	th.set_stylebox("panel", "Panel", pn)
	th.set_stylebox("panel", "PanelContainer", pn)
	th.set_font("normal_font", "RichTextLabel", font_body)
	th.set_font("bold_font", "RichTextLabel", font_bold)
	th.set_font("italics_font", "RichTextLabel", font_italic)
	th.set_font_size("normal_font_size", "RichTextLabel", 20)
	th.set_font_size("bold_font_size", "RichTextLabel", 20)
	th.set_font_size("italics_font_size", "RichTextLabel", 20)
	th.set_color("default_color", "RichTextLabel", Color("#e8e2d2"))
	th.set_font("font", "LineEdit", font_bold)
	th.set_font_size("font_size", "LineEdit", 24)
	var le := panel_style(Color("#0f0d09"), Color("#6a5a3a"), 1, 4)
	th.set_stylebox("normal", "LineEdit", le)
	th.set_stylebox("focus", "LineEdit", panel_style(Color("#0f0d09"), GOLD, 2, 4))
	th.set_font("font", "TooltipLabel", font_body)
	th.set_font_size("font_size", "TooltipLabel", 19)
	var tp := StyleBoxFlat.new()
	tp.bg_color = Color("#120f0aee")
	tp.border_color = GOLD
	tp.set_border_width_all(1)
	tp.set_content_margin_all(8)
	th.set_stylebox("panel", "TooltipPanel", tp)
	var vs := StyleBoxFlat.new()
	vs.bg_color = Color("#5a4a2a")
	vs.set_corner_radius_all(4)
	th.set_stylebox("grabber", "VScrollBar", vs)
	th.set_stylebox("grabber_highlight", "VScrollBar", vs)
	var vbg := StyleBoxFlat.new()
	vbg.bg_color = Color("#00000055")
	th.set_stylebox("scroll", "VScrollBar", vbg)
	return th
