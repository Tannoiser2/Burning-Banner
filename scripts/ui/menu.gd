extends Control
## Menu principale: la campagna, chi guida ogni regno (persona o IA, e quale giocatore),
## regole avanzate, livello e velocità dell'IA, il gioco online.

const D = preload("res://scripts/data/bb_data.gd")
const MAP_NAMES := ["Broken Coast", "Wildlands", "Imperial Heartland", "Fields of Ash"]

var main
var camp := 1
var mode := {}          # regno -> 0 persona, 1 IA
var who := {}           # regno -> numero del giocatore (1..6) per i regni guidati da persone
var advanced := 1
var long_game := 0
var level := 1
var speed := 1
var msg: Label
var camp_btns: Array = []
var camp_title: Label
var camp_desc: Label
var camp_info: RichTextLabel
var tiles_box: GridContainer
var long_row: Control


func _ready() -> void:
	size = Vector2(1920, 1080)
	D.load_all()
	if main.menu_state.has("camp"):
		var st: Dictionary = main.menu_state
		camp = st["camp"]
		mode = st["mode"].duplicate()
		who = st["who"].duplicate()
		advanced = st["advanced"]
		long_game = st["long"]
		level = st["level"]
		speed = st["speed"]
	var bg := TextureRect.new()
	bg.texture = UI.tex("res://assets/maps/wildlands.jpg")
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	bg.size = Vector2(1920, 1080)
	bg.modulate = Color(0.26, 0.22, 0.2)
	add_child(bg)
	var shade := TextureRect.new()
	var grad := GradientTexture2D.new()
	var g := Gradient.new()
	g.set_color(0, Color(0.04, 0.02, 0.02, 0.55))
	g.set_color(1, Color(0.04, 0.02, 0.02, 0.95))
	grad.gradient = g
	grad.fill_from = Vector2(0, 0)
	grad.fill_to = Vector2(1, 1)
	shade.texture = grad
	shade.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	shade.stretch_mode = TextureRect.STRETCH_SCALE
	shade.size = Vector2(1920, 1080)
	add_child(shade)

	var cover := TextureRect.new()
	cover.texture = UI.tex("res://assets/cover.jpg")
	cover.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	cover.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	cover.size = Vector2(330, 375)
	cover.position = Vector2(56, 28)
	add_child(cover)
	var st2 := UI.label("La rabbia della Regina Strega · conversione digitale", 21, Color("#d8cdb4"), UI.font_italic)
	st2.position = Vector2(58, 404)
	add_child(st2)

	var head := UI.title("CAMPAGNA", 30)
	head.position = Vector2(58, 444)
	add_child(head)
	var cv := VBoxContainer.new()
	cv.position = Vector2(56, 490)
	cv.add_theme_constant_override("separation", 8)
	add_child(cv)
	for i in range(D.CAMPAIGNS.size()):
		var c: Dictionary = D.CAMPAIGNS[i]
		var b := Button.new()
		b.text = "%d · %s" % [i, c["n"]] if i > 0 else "0 · %s" % c["n"]
		b.custom_minimum_size = Vector2(380, 50)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.add_theme_font_size_override("font_size", 21)
		b.pressed.connect(func(): _set_camp(i))
		cv.add_child(b)
		camp_btns.append(b)

	# centro: la campagna scelta e i regni
	var mid := PanelContainer.new()
	mid.add_theme_stylebox_override("panel", UI.panel_style(Color("#0d0a08dd"), Color("#4a3426"), 1, 8))
	mid.position = Vector2(470, 40)
	mid.custom_minimum_size = Vector2(880, 840)
	add_child(mid)
	var mv := VBoxContainer.new()
	mv.add_theme_constant_override("separation", 10)
	mid.add_child(mv)
	camp_title = UI.title("", 38)
	mv.add_child(camp_title)
	camp_desc = UI.label("", 22, Color("#ddd2bc"))
	camp_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	camp_desc.custom_minimum_size = Vector2(850, 0)
	mv.add_child(camp_desc)
	camp_info = UI.rich(20)
	camp_info.custom_minimum_size = Vector2(850, 0)
	mv.add_child(camp_info)
	mv.add_child(HSeparator.new())
	var hint := UI.label("Clicca su un regno per affidarlo a una persona o all'IA; il numero indica il giocatore\n(più regni dello stesso schieramento possono andare allo stesso giocatore).", 19, Color("#b8ab94"))
	mv.add_child(hint)
	tiles_box = GridContainer.new()
	tiles_box.columns = 3
	tiles_box.add_theme_constant_override("h_separation", 12)
	tiles_box.add_theme_constant_override("v_separation", 12)
	mv.add_child(tiles_box)

	# destra: opzioni
	var box := PanelContainer.new()
	box.add_theme_stylebox_override("panel", UI.panel_style(Color("#0d0a08dd"), Color("#4a3426"), 1, 8))
	box.position = Vector2(1380, 40)
	box.custom_minimum_size = Vector2(486, 0)
	add_child(box)
	var ov := VBoxContainer.new()
	ov.add_theme_constant_override("separation", 10)
	box.add_child(ov)
	ov.add_child(UI.label("Regole", 26, Color.WHITE, UI.font_bold))
	ov.add_child(_segmented(["Base", "Avanzate"], advanced, func(k): advanced = k, 220))
	var adv_note := UI.label("Avanzate: eroi, mostri, incantesimi, benedizioni,\ntesori e studio arcano.", 18, Color("#a89c86"))
	ov.add_child(adv_note)
	long_row = VBoxContainer.new()
	long_row.add_child(UI.label("Durata", 26, Color.WHITE, UI.font_bold))
	long_row.add_child(_segmented(["Normale", "Lunga (un anno in più)"], long_game, func(k): long_game = k, 220))
	ov.add_child(long_row)
	ov.add_child(HSeparator.new())
	ov.add_child(UI.label("Livello IA", 26, Color.WHITE, UI.font_bold))
	ov.add_child(_segmented(["Facile", "Normale", "Difficile"], level, func(k): level = k, 146))
	ov.add_child(UI.label("Velocità IA", 26, Color.WHITE, UI.font_bold))
	ov.add_child(_segmented(["Lenta", "Normale", "Veloce", "Subito"], speed, func(k): speed = k, 108))
	ov.add_child(HSeparator.new())
	var keys := UI.label("Mappa: trascina per spostare, tasto destro per ruotare,\nrotella per lo zoom, doppio clic per centrare.\nWASD/frecce spostano, Q/E ruotano, R/F inclinano.", 18, Color("#a89c86"))
	ov.add_child(keys)

	msg = UI.label("", 24, UI.RED, UI.font_bold)
	msg.position = Vector2(470, 892)
	add_child(msg)

	var btns := HBoxContainer.new()
	btns.add_theme_constant_override("separation", 18)
	btns.position = Vector2(470, 932)
	add_child(btns)
	var b_start := _big_button("INIZIA PARTITA", 420, true)
	b_start.pressed.connect(_on_start)
	btns.add_child(b_start)
	var b_rules := _big_button("REGOLE", 230)
	b_rules.pressed.connect(func():
		_store()
		main.show_rules())
	btns.add_child(b_rules)
	if not OS.has_feature("web"):
		var b_quit := _big_button("ESCI", 180)
		b_quit.pressed.connect(func(): get_tree().quit())
		btns.add_child(b_quit)
	var b_online := _big_button("GIOCA ONLINE", 486)
	b_online.position = Vector2(1380, 932)
	b_online.pressed.connect(_online_panel)
	add_child(b_online)
	var on_note := UI.label("Con gli amici, ognuno dal suo dispositivo:\ncrea una stanza e condividi il codice.", 20, Color("#bdb5a5"))
	on_note.position = Vector2(1382, 862)
	add_child(on_note)

	var credits := UI.label("Adattamento digitale non ufficiale per uso personale · Burning Banners: Rage of the Witch Queen di Christopher Moeller · © Compass Games · F11 schermo intero", 17, Color("#8a8478"))
	credits.position = Vector2(58, 1044)
	add_child(credits)
	_set_camp(camp)
	if not main.lobby.is_empty():
		_online_panel.call_deferred()


func _store() -> void:
	main.menu_state = {"camp": camp, "mode": mode.duplicate(), "who": who.duplicate(), "advanced": advanced,
		"long": long_game, "level": level, "speed": speed}


func _kingdoms() -> Array:
	return D.CAMPAIGNS[camp]["order"]


func _set_camp(i: int) -> void:
	camp = i
	var c: Dictionary = D.CAMPAIGNS[i]
	for j in range(camp_btns.size()):
		var on: bool = j == i
		var b: Button = camp_btns[j]
		b.add_theme_stylebox_override("normal", UI.panel_style(Color("#5a2414") if on else Color("#1c1610"), UI.GOLD if on else Color("#4a3a2a"), 2, 4))
		b.add_theme_color_override("font_color", Color.WHITE if on else Color("#d8d0c0"))
	camp_title.text = str(c["n"]).to_upper()
	camp_desc.text = c["desc"]
	var maps: Array = []
	for m in c["maps"]:
		maps.append(MAP_NAMES[int(m)])
	var inv: Array = []
	var res: Array = []
	for k in c["order"]:
		var nm := "[color=#%s]%s[/color]" % [UI.klight(int(k)).to_html(false), D.kname(int(k))]
		if int(c["sides"][k]) == 0:
			inv.append(nm)
		else:
			res.append(nm)
	var en: Array = c["end"]
	camp_info.text = "[b]Mappe:[/b] %s   [b]Durata:[/b] da %s %d a %s %d\n[b]Invasori:[/b] %s   [b]Resistenza:[/b] %s" % [
		", ".join(maps), D.season_name(int(c["start"][1])), int(c["start"][0]), D.season_name(int(en[1])), int(en[0]),
		", ".join(inv), ", ".join(res)]
	long_row.visible = c.has("long_end")
	if not c.has("long_end"):
		long_game = 0
	# assegnazioni predefinite: il primo regno della Resistenza a una persona
	var ks: Array = _kingdoms()
	var any_set := false
	for k in ks:
		if mode.has(k):
			any_set = true
	if not any_set:
		for k in ks:
			mode[k] = 1
			who[k] = 1
		for k in ks:
			if int(c["sides"][k]) == 1:
				mode[k] = 0
				break
	for k in ks:
		if not mode.has(k):
			mode[k] = 1
		if not who.has(k):
			who[k] = 1
	_build_tiles()
	msg.text = ""


func _build_tiles() -> void:
	for ch in tiles_box.get_children():
		ch.queue_free()
	var c: Dictionary = D.CAMPAIGNS[camp]
	for k in _kingdoms():
		var kd: Dictionary = D.KINGDOMS[int(k)]
		var human: bool = mode[k] == 0
		var p := PanelContainer.new()
		p.add_theme_stylebox_override("panel", UI.panel_style(Color("#140f0be8"), kd["light"] if human else Color("#4a3e30"), 3 if human else 1, 8))
		p.custom_minimum_size = Vector2(278, 230)
		p.mouse_filter = Control.MOUSE_FILTER_STOP
		tiles_box.add_child(p)
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", 4)
		v.mouse_filter = Control.MOUSE_FILTER_IGNORE
		p.add_child(v)
		var top := HBoxContainer.new()
		top.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.add_child(top)
		var ban := UI.icon_rect(UI.counter_tex("ban_%d" % int(k)), Vector2(84, 84))
		if not human:
			ban.modulate = Color(0.7, 0.7, 0.7)
		top.add_child(ban)
		var tv := VBoxContainer.new()
		tv.mouse_filter = Control.MOUSE_FILTER_IGNORE
		top.add_child(tv)
		var nm := UI.label(str(kd["n"]), 23, kd["light"], UI.font_bold)
		nm.custom_minimum_size = Vector2(170, 0)
		nm.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		tv.add_child(nm)
		tv.add_child(UI.label(D.SIDE_NAMES[int(c["sides"][k])], 19, Color("#e0846a") if int(c["sides"][k]) == 0 else Color("#8ab8e0")))
		var inc := UI.label("Rendita %d · Oro %d" % [int(c["income"][k]), int(c["gold"][k])], 18, Color("#b0a690"))
		v.add_child(inc)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		v.add_child(row)
		for m in range(2):
			var b := Button.new()
			b.text = ["PERSONA", "IA"][m]
			b.custom_minimum_size = Vector2(124, 46)
			b.add_theme_font_size_override("font_size", 21)
			var sel: bool = mode[k] == m
			b.add_theme_stylebox_override("normal", UI.panel_style(UI.GOLD if sel else Color("#1c1812"), UI.GOLD if sel else Color("#4a4236"), 2, 4))
			b.add_theme_color_override("font_color", UI.DARK if sel else Color("#dddddd"))
			b.add_theme_color_override("font_hover_color", UI.DARK if sel else UI.GOLD)
			b.pressed.connect(func():
				mode[k] = m
				msg.text = ""
				_build_tiles())
			row.add_child(b)
		var prow := HBoxContainer.new()
		prow.add_theme_constant_override("separation", 4)
		v.add_child(prow)
		if human:
			prow.add_child(UI.label("Giocatore", 19, Color("#cfc6b4")))
			for n in range(1, 7):
				var bn := Button.new()
				bn.text = str(n)
				bn.custom_minimum_size = Vector2(26, 34)
				bn.add_theme_font_size_override("font_size", 18)
				var on: bool = int(who[k]) == n
				bn.add_theme_stylebox_override("normal", UI.panel_style(kd["col"] if on else Color("#1c1812"), kd["light"] if on else Color("#4a4236"), 1, 4))
				bn.pressed.connect(func():
					who[k] = n
					msg.text = ""
					_build_tiles())
				prow.add_child(bn)
		else:
			prow.add_child(UI.label("Lo guida l'IA", 19, Color("#8a8070"), UI.font_italic))


func _segmented(items: Array, cur: int, cb: Callable, w := 200) -> HBoxContainer:
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 6)
	var btns := []
	for k in range(items.size()):
		var b := Button.new()
		b.text = items[k]
		b.custom_minimum_size = Vector2(w, 48)
		b.add_theme_font_size_override("font_size", 21)
		hb.add_child(b)
		btns.append(b)
	var paint := func(sel: int):
		for k in range(btns.size()):
			var on: bool = k == sel
			btns[k].add_theme_stylebox_override("normal", UI.panel_style(UI.GOLD if on else Color("#1c1812"), UI.GOLD if on else Color("#4a4236"), 2, 4))
			btns[k].add_theme_color_override("font_color", UI.DARK if on else Color("#dddddd"))
			btns[k].add_theme_color_override("font_hover_color", UI.DARK if on else UI.GOLD)
	for k in range(btns.size()):
		btns[k].pressed.connect(func():
			cb.call(k)
			paint.call(k))
	paint.call(cur)
	return hb


func _big_button(text: String, w: float, primary := false) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(w, 82)
	b.add_theme_font_override("font", UI.font_title)
	b.add_theme_font_size_override("font_size", 32)
	if primary:
		UI.primary(b)
	return b


## Posti della partita: un posto per ogni giocatore umano (con i suoi regni) e un posto IA
## per ogni schieramento. Restituisce "" se va bene, altrimenti il motivo.
func _seats() -> Array:
	var c: Dictionary = D.CAMPAIGNS[camp]
	var seats: Array = []
	var by_player := {}
	for k in _kingdoms():
		if mode[k] == 0:
			var n := int(who[k])
			if not by_player.has(n):
				by_player[n] = []
			by_player[n].append(int(k))
	var nums: Array = by_player.keys()
	nums.sort()
	for n in nums:
		seats.append({"name": "Giocatore %d" % n, "ai": false, "level": level, "ks": by_player[n]})
	for sd in [0, 1]:
		var ks: Array = []
		for k in _kingdoms():
			if mode[k] == 1 and int(c["sides"][k]) == sd:
				ks.append(int(k))
		if not ks.is_empty():
			seats.append({"name": "IA · %s" % D.SIDE_NAMES[sd], "ai": true, "level": level, "ks": ks})
	return seats


func _check(seats: Array) -> String:
	var c: Dictionary = D.CAMPAIGNS[camp]
	for s in seats:
		var sd := -1
		for k in s["ks"]:
			if sd >= 0 and int(c["sides"][k]) != sd:
				return "%s guida regni di schieramenti opposti: ogni giocatore sta con gli Invasori o con la Resistenza." % s["name"]
			sd = int(c["sides"][k])
	return ""


## Configurazione scelta nel menu (anche quella che, online, viaggia agli altri).
func _config() -> Dictionary:
	var speeds := [1.1, 0.55, 0.18, 0.0]
	return {"campaign": camp, "advanced": advanced == 1, "long": long_game == 1, "seats": _seats(),
		"ai_level": level, "ai_delay": speeds[speed], "seed": 1 + randi() % 2000000000}


func _on_start() -> void:
	var cfg := _config()
	var err := _check(cfg["seats"])
	if err != "":
		msg.text = err
		return
	_store()
	main.start_game(cfg)


# =================================================================== online

var on_panel: Control
var on_name: LineEdit
var on_code: LineEdit
var on_lbl: Label
var on_start: Button


func _online_panel() -> void:
	if is_instance_valid(on_panel):
		on_panel.queue_free()
	on_panel = Control.new()
	on_panel.size = Vector2(1920, 1080)
	on_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(on_panel)
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.75)
	shade.size = on_panel.size
	on_panel.add_child(shade)
	var box := PanelContainer.new()
	box.add_theme_stylebox_override("panel", UI.panel_style(Color("#15100cf4"), UI.GOLD, 2, 8))
	box.position = Vector2(540, 120)
	box.custom_minimum_size = Vector2(840, 0)
	on_panel.add_child(box)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 16)
	box.add_child(vb)
	vb.add_child(UI.title("GIOCA ONLINE", 46))
	var info := UI.label("Chi crea la stanza sceglie prima nel menu la campagna, le regole e il livello dell'IA: i regni affidati a una PERSONA diventano i posti per gli amici (il giocatore 1 è chi crea la stanza; il numero del giocatore raggruppa i regni). Gli amici entrano con il codice. I posti rimasti liberi li gioca l'IA. Ognuno vede soltanto le proprie carte.", 22, Color("#cccccc"))
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.custom_minimum_size = Vector2(800, 0)
	vb.add_child(info)
	var ses: Dictionary = main.get_net().load_session()
	on_name = _line("Il tuo nome", 20)
	on_name.text = str(ses.get("name", ""))
	vb.add_child(on_name)
	var b_create := Button.new()
	b_create.text = "CREA UNA STANZA"
	b_create.custom_minimum_size = Vector2(0, 60)
	b_create.add_theme_font_size_override("font_size", 28)
	b_create.pressed.connect(_online_create)
	vb.add_child(b_create)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	on_code = _line("Codice", 4)
	on_code.custom_minimum_size.x = 220
	on_code.text_changed.connect(func(t):
		on_code.text = t.to_upper()
		on_code.caret_column = t.length())
	row.add_child(on_code)
	var b_join := Button.new()
	b_join.text = "ENTRA"
	b_join.custom_minimum_size = Vector2(200, 60)
	b_join.add_theme_font_size_override("font_size", 28)
	b_join.pressed.connect(_online_join)
	row.add_child(b_join)
	vb.add_child(row)
	on_lbl = UI.label("", 24, Color.WHITE)
	on_lbl.custom_minimum_size = Vector2(800, 120)
	on_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(on_lbl)
	var row2 := HBoxContainer.new()
	row2.add_theme_constant_override("separation", 12)
	on_start = _big_button("INIZIA ONLINE", 420, true)
	on_start.pressed.connect(_online_start)
	on_start.visible = main.lobby.get("role", "") == "host"
	row2.add_child(on_start)
	var b_close := _big_button("INDIETRO", 300)
	b_close.pressed.connect(func():
		on_panel.queue_free())
	row2.add_child(b_close)
	vb.add_child(row2)
	if not main.lobby.is_empty():
		on_code.text = main.lobby["code"]
		on_lbl.text = "Stanza %s…" % main.lobby["code"]
	elif str(ses.get("room", "")) != "":
		on_code.text = str(ses["room"])
		on_lbl.text = "Eri nella stanza %s: premi ENTRA per rientrare." % ses["room"]


func _line(ph: String, maxlen: int) -> LineEdit:
	var le := LineEdit.new()
	le.placeholder_text = ph
	le.max_length = maxlen
	le.custom_minimum_size = Vector2(0, 60)
	le.add_theme_font_size_override("font_size", 28)
	return le


func _say(t: String) -> void:
	if is_instance_valid(on_lbl):
		on_lbl.text = t


func _seat_label(room: Dictionary, idx: int) -> String:
	var ks: Array = []
	var labels = room.get("labels", [])
	if labels is Array and idx < labels.size():
		return str(labels[idx])
	return "Posto %d" % (idx + 1)


func _seats_text(room: Dictionary) -> String:
	var seats := Net._as_dict(room.get("seats", {}))
	var parts := []
	for idx in room.get("open", []):
		var k := str(int(idx))
		var nm := str(seats[k].get("name", "?")) if seats.has(k) and seats[k] is Dictionary else "libero"
		parts.append("%s: %s" % [_seat_label(room, int(idx)), nm])
	return ", ".join(parts)


func _online_create() -> void:
	var nm := on_name.text.strip_edges()
	if nm == "":
		_say("Scrivi il tuo nome.")
		return
	var cfg := _config()
	var err := _check(cfg["seats"])
	if err != "":
		_say(err)
		return
	var seats := []
	for i in range(cfg["seats"].size()):
		if not cfg["seats"][i]["ai"]:
			seats.append(i)
	if seats.size() < 2:
		_say("Servono almeno due giocatori: affida i regni a PERSONE con numeri di giocatore diversi (il giocatore 1 sei tu, gli altri sono i posti per gli amici).")
		return
	_store()
	_say("Creo la stanza…")
	var net: Net = main.get_net()
	var code := await net.create_room(nm, seats)
	if code == "":
		_say("Non riesco a creare la stanza.\n%s" % net.last_error)
		return
	var labels: Array = []
	for s in cfg["seats"]:
		var names: Array = []
		for k in s["ks"]:
			names.append(D.KINGDOMS[int(k)]["short"])
		labels.append(" + ".join(names))
	await net.db_patch(Net.ROOT + "/" + code, {"labels": labels})
	main.lobby = {"role": "host", "code": code, "seat": seats[0]}
	net.remember_room(code, seats[0])
	net._save({"name": nm})
	if is_instance_valid(on_code):
		on_code.text = code
	if is_instance_valid(on_start):
		on_start.visible = true
	_lobby_poll(code)


func _online_join() -> void:
	var code := on_code.text.strip_edges().to_upper()
	var nm := on_name.text.strip_edges()
	if nm == "" or code.length() != 4:
		_say("Scrivi il tuo nome e il codice di 4 lettere.")
		return
	_say("Entro nella stanza %s…" % code)
	var net: Net = main.get_net()
	var seat := await net.join_room(code, nm)
	if seat == -2:
		_say("Stanza %s non trovata, oppure la partita è già iniziata.%s" % [code, ("\n" + net.last_error) if net.last_error != "" else ""])
		return
	if seat == -1:
		_say("Nella stanza %s non ci sono posti liberi." % code)
		return
	var room: Dictionary = net.last_room
	main.lobby = {"role": "host" if room.get("host", "") == net.uid else "guest", "code": code, "seat": seat}
	net.remember_room(code, seat)
	net._save({"name": nm})
	if room.get("status", "") in ["playing", "over"] and room.has("game"):
		_say("Rientro nella partita della stanza %s…" % code)
		_begin(room["game"], true)
		return
	if is_instance_valid(on_start):
		on_start.visible = main.lobby["role"] == "host"
	_lobby_poll(code)


func _lobby_poll(code: String) -> void:
	var net: Net = main.get_net()
	while is_inside_tree() and main.lobby.get("code", "") == code:
		var room := await net.room(code)
		if not is_inside_tree() or main.lobby.get("code", "") != code:
			return
		if room.is_empty():
			_say("La stanza %s non esiste più." % code)
			main.lobby = {}
			return
		if main.lobby["role"] == "host":
			_say("Stanza [ %s ]: dai il codice ai tuoi amici.\nPosti: %s.\nQuando ci siete tutti premi INIZIA ONLINE: i posti liberi li gioca l'IA." % [code, _seats_text(room)])
		else:
			if room.get("status", "") == "playing" and room.has("game"):
				_begin(room["game"], false)
				return
			_say("Sei nella stanza [ %s ] (%s).\nPosti: %s.\nAspetta che chi l'ha creata avvii la partita." % [code, _seat_label(room, int(main.lobby["seat"])), _seats_text(room)])
		await get_tree().create_timer(2.0).timeout


## Chi ha creato la stanza avvia: campagna, regni, regole e seme valgono per tutti.
func _online_start() -> void:
	var code: String = main.lobby["code"]
	var net: Net = main.get_net()
	var room := await net.room(code)
	if room.is_empty():
		_say("La stanza %s non esiste più." % code)
		main.lobby = {}
		return
	var seats_db := Net._as_dict(room.get("seats", {}))
	var cfg := _config()
	var my_seat := int(main.lobby["seat"])
	var open: Array = room.get("open", [])
	var humans := 0
	for s in cfg["seats"]:
		if not s["ai"]:
			humans += 1
	if humans != open.size() or my_seat >= cfg["seats"].size() or cfg["seats"][my_seat]["ai"]:
		_say("Hai cambiato i regni dopo aver creato la stanza: creane una nuova.")
		return
	for i in range(cfg["seats"].size()):
		var k := str(i)
		if seats_db.has(k) and seats_db[k] is Dictionary and not cfg["seats"][i]["ai"]:
			cfg["seats"][i]["name"] = str(seats_db[k].get("name", cfg["seats"][i]["name"]))
		elif not cfg["seats"][i]["ai"]:
			cfg["seats"][i]["ai"] = true
			cfg["seats"][i]["name"] = "IA · " + cfg["seats"][i]["name"]
	var g := {"cfg": var_to_str(cfg)}
	if not await net.start_room(code, g):
		_say("Non riesco ad avviare la partita (%s)." % net.last_error)
		return
	_begin(g, false)


## Avvio (o rientro) della partita online.
func _begin(g: Dictionary, rejoin: bool) -> void:
	var net: Net = main.get_net()
	var lob: Dictionary = main.lobby
	var backlog: Array = []
	if rejoin:
		backlog = await net.get_acts(lob["code"])
		net.set_away(lob["code"], int(lob["seat"]), false)
	var cfg = str_to_var(str(g.get("cfg", "")))
	if not (cfg is Dictionary):
		_say("Configurazione della partita non valida.")
		return
	var ses := OnlineSession.new()
	ses.setup(net, lob["code"], int(lob["seat"]), lob["role"], backlog)
	cfg["online"] = ses
	main.lobby = {}
	main.start_game(cfg)
