extends Control
## Vista di gioco: la mappa in 3D a tutto schermo con sopra i pannelli 2D.
## In alto la fascia della stagione e dei regni (sempre visibile), a sinistra la plancia del regno,
## in basso il riquadro delle scelte, a destra le carte in mano e il registro.

const D = preload("res://scripts/data/bb_data.gd")
const TOP_H := 64.0
const MAT_W := 372.0
const HL_CHOOSE := Color(1.0, 0.8, 0.25, 0.95)
const HL_ATTACK := Color(1.0, 0.25, 0.15, 0.95)
const HL_MOVE := Color(0.3, 0.65, 1.0, 0.9)
const HL_BUILD := Color(0.35, 0.95, 0.4, 0.9)
const HL_MONSTER := Color(0.75, 0.4, 1.0, 0.95)
const HL_SEL := Color(1.0, 1.0, 1.0, 0.9)
const AB_NAMES := {"ranged": "A distanza", "flying": "Volante", "stealth": "Furtiva", "mage": "Magica", "siege": "Macchina d'assedio",
	"ranger": "Ranger", "regen": "Rigenerazione", "seafaring": "Navigatori", "mountaineer": "Montanari", "miner": "Minatori",
	"ghost": "Fantasmi", "fragile": "Fragile", "feral": "Ferale", "huge": "Enorme", "immobile": "Immobile"}
const TERRAIN_NAMES := {"p": "pianura", "w": "mare", "m": "montagna", "f": "foresta", "s": "palude"}
const WINDOW_NAMES := {"main": "Attivazione", "bm_a": "Battaglia magica · attaccante", "bm_b": "Battaglia magica · difensori",
	"bm_c": "Battaglia magica · attaccanti", "rolled": "Dopo il tiro dei dadi", "r_hit": "Colpo subito", "r_rolled": "Dopo il tiro dei dadi",
	"r_strike": "Assalto", "strike": "Assalto", "r_cast": "Carta giocata", "cast": "Carta giocata", "r_elim": "Unità eliminata",
	"r_moved": "Movimento", "moved": "Movimento", "r_sea": "Mare", "r_coven": "Congrega", "r_mined": "Miniera", "mined": "Miniera",
	"r_won": "Vittoria in combattimento", "won": "Vittoria in combattimento", "sea_cross": "Attraversamento del mare", "coven": "Congrega", "elim": "Unità eliminata", "hit": "Colpo subito"}

var main
var config: Dictionary
var engine: BBEngine
var online = null
var board: Board3D
var humans: Array = []
var hand_seat := -1
var pending: Dictionary = {}
var cover_for := -1
var sel_mode := ""
var lw_sel := {}
var hover_h := -1
var mat_k := -1
var mat_auto := true
var focus_key := ""

# nodi
var board_input: Control
var top: Panel
var season_lbl: Label
var turn_lbl: RichTextLabel
var vp_lbl: RichTextLabel
var kchips := {}
var mat_panel: PanelContainer
var mat_box: VBoxContainer
var hand_panel: PanelContainer
var hand_row: HBoxContainer
var hand_title: Label
var action_box: PanelContainer
var action_msg: RichTextLabel
var action_row: HFlowContainer
var info_box: PanelContainer
var info_text: RichTextLabel
var log_panel: PanelContainer
var log_text: RichTextLabel
var modal: Control
var toast: Control
var zoom: Control
var dice_panel: PanelContainer
var online_lbl: Label
var dice_t := 0.0


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	size = Vector2(1920, 1080)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	online = config.get("online", null)
	engine = BBEngine.new()
	add_child(engine)
	engine.setup(config)
	engine.ai_delay = float(config.get("ai_delay", 0.5))
	if online != null:
		humans = [online.seat]
		online.view = self
		add_child(online)
		engine.online = online
		if online.role != "host":
			online.heartbeat_loop()
	else:
		for p in engine.players:
			if not p["ai"]:
				humans.append(int(p["seat"]))
	hand_seat = humans[0] if humans.size() > 0 else -1
	engine.pause_enabled = false

	board = Board3D.new()
	add_child(board)
	board.setup(engine)
	board_input = Control.new()
	board_input.size = size
	board_input.mouse_filter = Control.MOUSE_FILTER_STOP
	board_input.gui_input.connect(_on_board_input)
	add_child(board_input)
	board.hex_clicked.connect(_on_hex_click)
	board.hex_hovered.connect(_on_hex_hover)

	_build_top()
	_build_mat()
	_build_hand()
	_build_action()
	_build_info()
	_build_log()
	_build_dice()
	zoom = Control.new()
	zoom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	zoom.visible = false
	add_child(zoom)
	modal = Control.new()
	modal.size = size
	modal.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(modal)
	toast = Control.new()
	toast.size = size
	toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(toast)
	_build_online_label()

	engine.changed.connect(refresh)
	engine.log_added.connect(_on_log)
	engine.decision_requested.connect(_on_decision)
	engine.game_ended.connect(_on_game_end)
	engine.fx.connect(_on_fx)
	refresh()
	if online != null and online.catchup:
		online_status("Riprendo la partita dal punto in cui era…")
	engine.run.call_deferred()


func _exit_tree() -> void:
	if engine != null:
		engine.abort = true


func _process(delta: float) -> void:
	if dice_panel.visible and dice_t > 0.0:
		dice_t -= delta
		if dice_t <= 0.0:
			dice_panel.visible = false


# =================================================================== costruzione

func _pstyle(bg := Color("#120d09ec"), border := Color("#4a3426"), bw := 1, r := 8) -> StyleBoxFlat:
	return UI.panel_style(bg, border, bw, r)


func _build_top() -> void:
	top = Panel.new()
	top.size = Vector2(1920, TOP_H)
	top.add_theme_stylebox_override("panel", UI.panel_style(Color("#0c0907f2"), Color("#3a2a1c"), 1, 0))
	add_child(top)
	season_lbl = UI.title("", 26)
	season_lbl.position = Vector2(16, 4)
	top.add_child(season_lbl)
	turn_lbl = UI.rich(18)
	turn_lbl.position = Vector2(18, 36)
	turn_lbl.size = Vector2(460, 26)
	turn_lbl.autowrap_mode = TextServer.AUTOWRAP_OFF
	top.add_child(turn_lbl)
	var hb := HBoxContainer.new()
	hb.position = Vector2(470, 5)
	hb.add_theme_constant_override("separation", 6)
	top.add_child(hb)
	var cw := minf(176.0, 1032.0 / engine.order.size() - 6.0)
	for k in engine.order:
		var chip := PanelContainer.new()
		chip.custom_minimum_size = Vector2(cw, 54)
		chip.mouse_filter = Control.MOUSE_FILTER_STOP
		chip.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		hb.add_child(chip)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 4)
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		chip.add_child(row)
		var ic := UI.icon_rect(UI.counter_tex("ban_%d" % int(k)), Vector2(40, 40))
		row.add_child(ic)
		var r := UI.rich(16)
		r.custom_minimum_size = Vector2(cw - 52, 0)
		r.mouse_filter = Control.MOUSE_FILTER_IGNORE
		r.autowrap_mode = TextServer.AUTOWRAP_OFF
		row.add_child(r)
		var kk := int(k)
		chip.gui_input.connect(func(ev):
			if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
				mat_k = kk
				mat_auto = false
				_refresh_mat())
		kchips[kk] = {"panel": chip, "txt": r}
	vp_lbl = UI.rich(18)
	vp_lbl.position = Vector2(1508, 4)
	vp_lbl.size = Vector2(200, 56)
	top.add_child(vp_lbl)
	var bh := HBoxContainer.new()
	bh.position = Vector2(1674, 10)
	bh.add_theme_constant_override("separation", 6)
	top.add_child(bh)
	for it in [["?", _show_rules_popup, "Regole in breve", 50], ["Diario", _toggle_log, "Registro della partita (L)", 88], ["Menu", _ask_quit, "Torna al menu", 88]]:
		var b := UI.button(it[0], it[3], 44, 21)
		b.tooltip_text = it[2]
		b.pressed.connect(it[1])
		bh.add_child(b)


func _build_mat() -> void:
	mat_panel = PanelContainer.new()
	mat_panel.position = Vector2(8, TOP_H + 8)
	mat_panel.custom_minimum_size = Vector2(MAT_W, 0)
	mat_panel.add_theme_stylebox_override("panel", _pstyle())
	add_child(mat_panel)
	mat_box = VBoxContainer.new()
	mat_box.add_theme_constant_override("separation", 6)
	mat_panel.add_child(mat_box)


func _build_hand() -> void:
	hand_panel = PanelContainer.new()
	hand_panel.add_theme_stylebox_override("panel", _pstyle(Color("#120d09e0")))
	add_child(hand_panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	hand_panel.add_child(v)
	hand_title = UI.label("", 19, UI.GOLD, UI.font_bold)
	v.add_child(hand_title)
	hand_row = HBoxContainer.new()
	hand_row.add_theme_constant_override("separation", -34)
	v.add_child(hand_row)


func _build_action() -> void:
	action_box = PanelContainer.new()
	action_box.add_theme_stylebox_override("panel", _pstyle(Color("#140e0af4"), UI.GOLD, 2, 10))
	action_box.custom_minimum_size = Vector2(760, 0)
	add_child(action_box)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	action_box.add_child(v)
	action_msg = UI.rich(21)
	action_msg.custom_minimum_size = Vector2(740, 0)
	v.add_child(action_msg)
	action_row = HFlowContainer.new()
	action_row.add_theme_constant_override("h_separation", 8)
	action_row.add_theme_constant_override("v_separation", 8)
	action_row.custom_minimum_size = Vector2(740, 0)
	v.add_child(action_row)
	action_box.visible = false
	action_box.resized.connect(_layout_action)


func _layout_action() -> void:
	action_box.size.y = 0
	action_box.position = Vector2(MAT_W + 24, 1080 - action_box.size.y - 10)


func _build_info() -> void:
	info_box = PanelContainer.new()
	info_box.add_theme_stylebox_override("panel", _pstyle(Color("#0e0a07ee"), Color("#6a5034"), 1, 6))
	info_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	info_box.visible = false
	add_child(info_box)
	info_text = UI.rich(18)
	info_text.custom_minimum_size = Vector2(330, 0)
	info_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	info_box.add_child(info_text)


func _build_log() -> void:
	log_panel = PanelContainer.new()
	log_panel.add_theme_stylebox_override("panel", _pstyle(Color("#0e0a07ee")))
	log_panel.position = Vector2(1500, TOP_H + 8)
	log_panel.size = Vector2(412, 470)
	log_panel.custom_minimum_size = Vector2(412, 470)
	add_child(log_panel)
	var v := VBoxContainer.new()
	log_panel.add_child(v)
	v.add_child(UI.label("Registro", 20, UI.GOLD, UI.font_bold))
	var sc := ScrollContainer.new()
	sc.custom_minimum_size = Vector2(396, 420)
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(sc)
	log_text = UI.rich(17)
	log_text.custom_minimum_size = Vector2(380, 0)
	sc.add_child(log_text)
	log_text.set_meta("sc", sc)
	log_panel.visible = true


func _toggle_log() -> void:
	log_panel.visible = not log_panel.visible


func _build_dice() -> void:
	dice_panel = PanelContainer.new()
	dice_panel.add_theme_stylebox_override("panel", _pstyle(Color("#140e0af4"), UI.EMBER, 2, 10))
	dice_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dice_panel.visible = false
	add_child(dice_panel)


# =================================================================== aggiornamento

func refresh() -> void:
	if engine == null:
		return
	board.refresh()
	_refresh_top()
	_refresh_mat()
	_refresh_hand()
	_refresh_highlights()


func _kname_col(k: int) -> String:
	return "[color=#%s]%s[/color]" % [UI.klight(k).to_html(false), D.KINGDOMS[k]["short"]]


func _refresh_top() -> void:
	season_lbl.text = engine.season_text().to_upper()
	var t := ""
	if engine.cur_k >= 0:
		t = "Turno: [b]%s[/b]" % _kname_col(engine.cur_k)
		var p: Dictionary = engine.player_of(engine.cur_k)
		t += " · %s" % p["name"]
	t += " · turni rimasti %d" % engine.turns_left()
	turn_lbl.text = t
	for k in kchips:
		var c: Dictionary = kchips[k]
		var kd: Dictionary = engine.kd[k]
		var s := "[b][color=#%s]%s[/color][/b]" % [UI.klight(k).to_html(false), D.KINGDOMS[k]["short"]]
		if kd["collapsed"]:
			s += " [color=#ff6a50]CROLLATO[/color]"
		s += "\n[color=#f2c75c]%d oro[/color] +%d" % [int(kd["gold"]), engine.income(k)]
		if k == D.EMPIRE:
			s += " · [color=#ff8a70]riv %d[/color]" % int(kd["revolts"])
		elif k == D.NIGHT:
			s += " · cong %d" % engine.coven.size()
		c["txt"].text = s
		var active: bool = k == engine.cur_k
		var col: Color = UI.klight(k) if active else Color("#3a2c20")
		(c["panel"] as PanelContainer).add_theme_stylebox_override("panel", UI.panel_style(Color("#1a120ce8") if active else Color("#120d09d8"), col, 2 if active else 1, 6))
	var v0 := engine.vp(0)
	var v1 := engine.vp(1)
	vp_lbl.text = "[color=#ff8a70]Invasori %d[/color]\n[color=#8ac0f0]Resistenza %d[/color]" % [v0, v1]
	vp_lbl.tooltip_text = _vp_tip()


func _vp_tip() -> String:
	var s := ""
	for sd in [0, 1]:
		var d := engine.vp_detail(sd)
		s += "%s: %d PV (insediamenti %d" % [D.SIDE_NAMES[sd], d["tot"], d["sets"]]
		if sd == 0:
			s += ", rasi %d, congreghe %d" % [d["razed"], d["covens"]]
		s += ")\n"
	return s.strip_edges()


func _refresh_mat() -> void:
	for ch in mat_box.get_children():
		mat_box.remove_child(ch)
		ch.queue_free()
	mat_panel.reset_size.call_deferred()
	if mat_auto or mat_k < 0:
		mat_k = engine.cur_k if engine.cur_k >= 0 else int(engine.order[0])
	var k := mat_k
	var kd: Dictionary = engine.kd[k]
	var hd := HBoxContainer.new()
	hd.add_theme_constant_override("separation", 8)
	mat_box.add_child(hd)
	hd.add_child(UI.icon_rect(UI.counter_tex("ban_%d" % k), Vector2(64, 64)))
	var hv := VBoxContainer.new()
	hv.add_theme_constant_override("separation", 0)
	hd.add_child(hv)
	var nm := UI.title(str(D.KINGDOMS[k]["n"]).to_upper(), 22, UI.klight(k))
	nm.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	nm.custom_minimum_size = Vector2(270, 0)
	hv.add_child(nm)
	var p: Dictionary = engine.player_of(k)
	hv.add_child(UI.label("%s · %s" % [D.SIDE_NAMES[int(engine.side[k])], p["name"]], 17, Color("#c8bca4")))
	if not mat_auto:
		var b := UI.button("Segui il turno", 0, 30, 16)
		b.pressed.connect(func():
			mat_auto = true
			_refresh_mat())
		hv.add_child(b)
	var r := UI.rich(18)
	r.custom_minimum_size = Vector2(MAT_W - 20, 0)
	var s := "[color=#f2c75c][b]%d oro[/b][/color] · rendita %d · segnalini %d" % [int(kd["gold"]), engine.income(k), engine.markers_left(k)]
	if k == D.EMPIRE:
		s += "\nRivolte: [b]%d[/b] (reprimerne una costa %d oro)" % [int(kd["revolts"]), engine.suppress_cost()]
	if k == D.NIGHT:
		s += "\nCongreghe: [b]%d[/b]" % engine.coven.size()
	if D.KINGDOMS[k]["shashka"]:
		s += "\nShashka: 1 oro per segnalino di controllo"
	if kd["collapsed"]:
		s += "\n[color=#ff6a50][b]Il regno è crollato.[/b][/color]"
	r.text = s
	mat_box.add_child(r)
	mat_box.add_child(UI.label("Riserva e unità in mappa", 18, UI.GOLD, UI.font_bold))
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 4)
	mat_box.add_child(grid)
	for t in D.UNIT_ORDER[k]:
		var ud: Dictionary = D.UNITS[t]
		var free := engine.available(k, t).size()
		var tot := 0
		for u in engine.units:
			if int(u["k"]) == k and u["t"] == t and u["kind"] == "army":
				tot += 1
		var cell := VBoxContainer.new()
		cell.add_theme_constant_override("separation", 0)
		cell.tooltip_text = _unit_tip_t(t)
		cell.mouse_filter = Control.MOUSE_FILTER_PASS
		grid.add_child(cell)
		var ic := UI.icon_rect(UI.counter_tex(D.unit_img(t, 0)), Vector2(80, 80))
		if free == 0:
			ic.modulate = Color(0.45, 0.45, 0.45)
		cell.add_child(ic)
		var l := UI.label("%d/%d · %d oro" % [free, tot, int(ud["cost"])], 15, Color("#d8ccb4"))
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.custom_minimum_size = Vector2(80, 0)
		cell.add_child(l)
	if engine.advanced:
		var hc: Dictionary = kd["hcards"]
		if not hc.is_empty():
			mat_box.add_child(UI.label("Eroi in gioco", 18, UI.GOLD, UI.font_bold))
			var hrow := GridContainer.new()
			hrow.columns = 4
			hrow.add_theme_constant_override("h_separation", 6)
			hrow.add_theme_constant_override("v_separation", 6)
			mat_box.add_child(hrow)
			var powers: Array = []
			if pending.get("type", "") == "main" and int(pending.get("k", -1)) == k:
				powers = pending["options"].get("powers", [])
			for hid in hc:
				hrow.add_child(_card_thumb(str(hid), Vector2(84, 115), hid in powers, bool(hc[hid]["locked"])))
		mat_box.add_child(UI.label("Eroi nella riserva: %d · costo %d oro" % [kd["hero_pool"].size(), int(D.KINGDOMS[k]["hero_cost"])], 16, Color("#b8ac94")))
	var mons: Array = []
	for h in engine.monsters:
		if int(engine.monsters[h]["cmd"]) == k:
			mons.append(D.monster(engine.monsters[h]["m"])["n"])
	if not mons.is_empty():
		var ml := UI.label("Mostri comandati: " + ", ".join(mons), 16, Color("#cbb0ff"))
		ml.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		ml.custom_minimum_size = Vector2(MAT_W - 20, 0)
		mat_box.add_child(ml)


func _unit_tip_t(t: String) -> String:
	var ud: Dictionary = D.UNITS[t]
	var s := "%s\nCosto %d · recupero %s · movimento %d\nDadi: %d leggeri, %d pesanti" % [ud["n"], int(ud["cost"]), str(ud["rec"]) if int(ud["rec"]) >= 0 else "—", int(ud["mv"]), int(ud["l"]), int(ud["h"])]
	var ab: Array = []
	for a in ud.get("ab", []) + ud.get("ch", []):
		ab.append(AB_NAMES.get(a, a))
	if ud.get("miner", false):
		ab.append("Minatori")
	if not ab.is_empty():
		s += "\n" + ", ".join(ab)
	return s


## Posto di cui si mostrano le carte.
func _visible_hand() -> int:
	if online != null:
		return online.seat
	if cover_for >= 0:
		return -1
	return hand_seat


func _refresh_hand() -> void:
	for ch in hand_row.get_children():
		hand_row.remove_child(ch)
		ch.queue_free()
	var s := _visible_hand()
	if not engine.advanced or s < 0:
		hand_panel.visible = false
		return
	hand_panel.visible = true
	var p: Dictionary = engine.players[s]
	hand_title.text = "Carte di %s (%d)" % [p["name"], p["hand"].size()]
	var playable: Array = []
	var my_main: bool = pending.get("type", "") == "main" and int(pending.get("seat", -1)) == s
	if my_main:
		playable = pending["options"].get("cards", [])
	var magic_ids := {}
	if pending.get("type", "") == "magic" and int(pending.get("seat", -1)) == s:
		for pl in pending["plays"]:
			magic_ids[str(pl["c"])] = true
	var cards: Array = p["hand"].duplicate()
	for c in p["owned"]:
		cards.append(c)
	var n := cards.size()
	var w := 108.0 if n <= 8 else 92.0
	for c in cards:
		var hot: bool = c in playable or magic_ids.has(c)
		var th := _card_thumb(str(c), Vector2(w, w * 1.372), hot, c in p["owned"])
		hand_row.add_child(th)
	_place_hand.call_deferred()


func _place_hand() -> void:
	if not is_instance_valid(hand_panel):
		return
	hand_panel.reset_size()
	var ms := hand_panel.get_combined_minimum_size()
	hand_panel.position = Vector2(1912 - ms.x, 1072 - ms.y)


func _card_thumb(id: String, sz: Vector2, hot: bool, dim: bool) -> Control:
	var root := Control.new()
	root.custom_minimum_size = sz
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	var tr := UI.icon_rect(UI.card_tex(id), sz)
	tr.stretch_mode = TextureRect.STRETCH_SCALE
	if dim:
		tr.modulate = Color(0.62, 0.62, 0.62)
	root.add_child(tr)
	if hot:
		var fr := Panel.new()
		fr.size = sz
		fr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0, 0, 0, 0)
		sb.border_color = Color("#ffd04a")
		sb.set_border_width_all(4)
		sb.set_corner_radius_all(6)
		fr.add_theme_stylebox_override("panel", sb)
		root.add_child(fr)
	root.mouse_entered.connect(func():
		root.z_index = 5
		_show_zoom(id, root))
	root.mouse_exited.connect(func():
		root.z_index = 0
		_hide_zoom())
	root.gui_input.connect(func(ev):
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			_on_card_click(id))
	return root


func _show_zoom(id: String, near: Control) -> void:
	for ch in zoom.get_children():
		ch.queue_free()
	var cd := D.card(id)
	var box := PanelContainer.new()
	box.add_theme_stylebox_override("panel", _pstyle(Color("#0e0a07f6"), UI.GOLD, 2, 8))
	zoom.add_child(box)
	var v := VBoxContainer.new()
	box.add_child(v)
	var img := UI.icon_rect(UI.card_tex(id), Vector2(320, 439))
	img.stretch_mode = TextureRect.STRETCH_SCALE
	v.add_child(img)
	var r := UI.rich(17)
	r.custom_minimum_size = Vector2(320, 0)
	var s := "[b]%s[/b]" % cd.get("n", id)
	var tags: Array = []
	if cd.get("cantrip", false):
		tags.append("Trucchetto")
	if cd.get("bm", false):
		tags.append("Battaglia magica")
	if cd.get("tome", false):
		tags.append("Tomo")
	if str(cd.get("range", "")) != "":
		tags.append("Raggio " + str(cd["range"]))
	if not tags.is_empty():
		s += " · [i]%s[/i]" % ", ".join(tags)
	s += "\n" + str(cd.get("it", ""))
	r.text = s
	v.add_child(r)
	zoom.visible = true
	zoom.move_to_front()
	await get_tree().process_frame
	if not is_instance_valid(box) or not is_instance_valid(near):
		return
	var gp := near.get_global_rect()
	var x := clampf(gp.position.x + gp.size.x / 2 - box.size.x / 2, 8, 1912 - box.size.x)
	var y := gp.position.y - box.size.y - 8
	if y < TOP_H:
		y = TOP_H + 8
		x = gp.end.x + 10
		if x + box.size.x > 1912:
			x = gp.position.x - box.size.x - 10
	box.position = Vector2(x, y)


func _hide_zoom() -> void:
	zoom.visible = false
	for ch in zoom.get_children():
		ch.queue_free()


# =================================================================== mappa: input, informazioni ed evidenziazioni

func _on_board_input(ev: InputEvent) -> void:
	if board.handle_input(ev):
		board_input.accept_event()


func _unhandled_key_input(ev: InputEvent) -> void:
	if not (ev is InputEventKey) or not ev.pressed:
		return
	match ev.keycode:
		KEY_ESCAPE:
			_cancel_sel()
		KEY_C:
			board.want_target = Vector3(board.bounds.get_center().x, 0, board.bounds.get_center().y)
		KEY_L:
			_toggle_log()


func _on_hex_hover(h: int) -> void:
	hover_h = h
	if h < 0 or not engine.in_map(h):
		info_box.visible = false
		return
	info_text.text = _hex_info(h)
	info_box.visible = true
	info_box.size = Vector2.ZERO
	var mp := get_viewport().get_mouse_position()
	info_box.position = Vector2(clampf(mp.x + 22, 0, 1910 - 350), clampf(mp.y + 22, TOP_H, 1070 - 220))


func _hex_info(h: int) -> String:
	var e: Dictionary = D.hexes[h]
	var s := ""
	var sd := engine.sdata(h)
	var terr: String = TERRAIN_NAMES.get(str(e["t"]), str(e["t"]))
	if not sd.is_empty():
		var kind := "Città" if sd["city"] else ("Fortezza" if int(sd["fort"]) > 0 else "Villaggio")
		s += "[b]%s[/b] · %s (%d PV)" % [sd["n"], kind, engine.set_value(h)]
		if not engine.inplay.has(h):
			s += "\n[i]Fuori gioco in questa campagna[/i]"
		else:
			var c := engine.controller(h)
			if engine.razed.has(h):
				s += "\n[color=#ff8a60]Raso al suolo[/color]"
			elif c >= 0:
				s += "\nControllo: %s" % _kname_col(c)
			else:
				s += "\nNeutrale"
			if engine.coven.has(h):
				s += " · [color=#ff7a68]Congrega[/color]"
			if engine.cur_k >= 0 and not engine.razed.has(h):
				s += " · per %s è %s" % [D.KINGDOMS[engine.cur_k]["short"], {"friend": "amico", "ally": "alleato", "welcome": "accogliente", "hostile": "ostile", "inert": "inerte"}.get(engine.posture(h, engine.cur_k), "?")]
		if int(sd["fort"]) > 0:
			s += "\nFortificato%s" % (" (magico)" if int(sd["fort"]) > 1 else "")
		if sd["port"]:
			s += " · porto"
	elif str(e["lair_n"]) != "":
		s += "[b]%s[/b] · tana" % e["lair_n"]
	elif str(e["name"]) != "":
		s += "[b]%s[/b]" % e["name"]
	else:
		s += "[b]%s[/b]" % terr.capitalize()
	if not sd.is_empty() or str(e["lair_n"]) != "":
		s += "\nTerreno: %s" % terr
	if engine.is_mine(h):
		s += " · miniera"
	var eo := engine.entry_owner(h)
	if eo >= 0:
		s += "\nIngresso di %s" % _kname_col(eo)
	if engine.monsters.has(h):
		var m: Dictionary = engine.monsters[h]
		var md := D.monster(m["m"])
		if m["def"]:
			s += "\nMostro ignoto (si scopre attaccando la tana)"
		else:
			s += "\n[color=#cbb0ff]%s[/color] %dL/%dP" % [md["n"], int(md["l"]), int(md["h"])]
			if int(m["cmd"]) >= 0:
				s += " · comandato da %s" % _kname_col(int(m["cmd"]))
	for u in engine.units_at(h):
		var k: int = engine.owner(u)
		var d: Vector2i = engine.unit_dice(u)
		s += "\n• %s [color=#%s]%s[/color] %dL/%dP%s%s" % [D.KINGDOMS[k]["short"], UI.klight(k).to_html(false), engine.uname(u), d.x, d.y,
			" [i]indebolita[/i]" if u["weak"] else "", " · esausta" if u["fin"] else ""]
	return s


func _refresh_highlights() -> void:
	var d := {}
	var req := pending
	if not req.is_empty() and cover_for < 0:
		var o = req.get("options", null)
		match str(req["type"]):
			"main":
				if sel_mode.begins_with("build:"):
					for h in o["builds"].get(sel_mode.substr(6), []):
						d[h] = HL_BUILD
				elif sel_mode == "hero":
					for h in o["hero"]:
						d[h] = HL_BUILD
				elif sel_mode == "unraze":
					for h in o["unraze"]:
						d[h] = HL_CHOOSE
				elif sel_mode == "rm_coven":
					for h in o["rm_coven"]:
						d[h] = HL_CHOOSE
				elif sel_mode.begins_with("monster:"):
					var mh := int(sel_mode.substr(8))
					d[mh] = HL_SEL
					for h in engine.monster_targets(int(req["k"]), mh):
						d[h] = HL_ATTACK
				else:
					for h in o["acts"]:
						d[h] = HL_CHOOSE
					for h in o["monsters"]:
						d[h] = HL_MONSTER
			"move":
				for h in o["reach"]:
					d[int(h)] = HL_MOVE
				d[int(req["h"])] = HL_SEL
			"ship_move":
				for h in o:
					d[int(h)] = HL_MOVE
				d[int(req["h"])] = HL_SEL
			"action":
				for h in o["attack"]:
					d[int(h)] = HL_ATTACK
				d[int(req["h"])] = HL_SEL
			"setup_free", "setup_coven", "coven", "fear":
				for h in o:
					d[int(h)] = HL_CHOOSE
			"hero_place":
				for id in o:
					d[int(engine.unit(int(id))["h"])] = HL_CHOOSE
			"lay_waste":
				for h in o:
					d[int(h)] = HL_ATTACK if lw_sel.has(int(h)) else HL_CHOOSE
			"conquer", "place_ctrl", "advance":
				d[int(req.get("h", req.get("t", -1)))] = HL_SEL
			"ambush", "counter", "hit":
				if req.has("t"):
					d[int(req["t"])] = HL_ATTACK
	board.set_highlights(d)


# =================================================================== decisioni

func _on_decision(req: Dictionary) -> void:
	pending = req
	sel_mode = ""
	lw_sel.clear()
	var s := int(req["seat"])
	if online == null and humans.size() > 1 and s != hand_seat and _shows_hand(req):
		hand_seat = s
		cover_for = s
		_cover(s)
		refresh()
		return
	if _shows_hand(req):
		hand_seat = s
	_show_decision()
	refresh()
	if req["type"] in ["move", "action"]:
		var fh := int(req.get("h", -1))
		if fh >= 0:
			board.focus(fh)
	elif req["type"] in ["main", "setup_free", "setup_coven"]:
		# a inizio turno la telecamera va sulle forze del regno (una volta per turno)
		var key := "%d/%d/%d" % [engine.turn_no, int(req["k"]), 1 if req.get("opening", false) else 0]
		if key != focus_key:
			focus_key = key
			var hs: Array = []
			if req["type"] == "main":
				hs = req["options"]["acts"].duplicate()
				if hs.is_empty():
					for t in req["options"]["builds"]:
						hs.append_array(req["options"]["builds"][t])
			else:
				hs = req["options"].duplicate()
			if not hs.is_empty():
				var c := Vector3.ZERO
				for h in hs:
					c += board.hex_pos(int(h))
				c /= hs.size()
				var far := 0.0
				for h in hs:
					far = maxf(far, c.distance_to(board.hex_pos(int(h))))
				board.want_target = Vector3(c.x, 0, c.z)
				board.want_dist = clampf(far * 2.6 + 8.0, 10.0, 40.0)


func _shows_hand(req: Dictionary) -> bool:
	return req["type"] in ["main", "magic", "study"]


func _cover(s: int) -> void:
	var vb := _open_modal("TOCCA A %s" % str(engine.players[s]["name"]).to_upper(), 680)
	var ks: Array = []
	for k in engine.players[s]["ks"]:
		ks.append(D.KINGDOMS[int(k)]["n"])
	vb.add_child(UI.label("Regni: %s.\nPassa il dispositivo: le carte in mano sono nascoste." % ", ".join(ks), 22))
	var b := UI.primary(UI.button("SONO %s, MOSTRA LE CARTE" % str(engine.players[s]["name"]).to_upper(), 640, 64, 24))
	b.pressed.connect(func():
		cover_for = -1
		_clear_modal()
		_show_decision()
		refresh())
	vb.add_child(b)


func _who(k: int) -> String:
	return "[b]%s[/b]" % _kname_col(k)


func _show_decision() -> void:
	var req := pending
	_clear_actions()
	if req.is_empty():
		action_box.visible = false
		return
	action_box.visible = true
	var k := int(req["k"])
	var t: String = req["type"]
	var o = req.get("options", null)
	var msg := ""
	match t:
		"main":
			msg = _main_ui(req)
		"move":
			msg = "%s · [b]Movimento[/b] di %s: clicca un esagono azzurro (PM rimasti %d)." % [_who(k), _stack_txt(req["ids"]), int(o["mp"])]
			if o["ship"]:
				_add_btn("Movimento navale", func(): _provide({"ship": true}))
			_add_btn("Resta qui", func(): _provide({"to": -1}), true)
		"ship_move":
			msg = "%s · [b]Movimento navale[/b] di %s: clicca la destinazione." % [_who(k), _stack_txt(req["ids"])]
			_add_btn("Rinuncia", func(): _provide(-1))
		"action":
			msg = "%s · [b]Azione[/b] di %s." % [_who(k), _stack_txt(req["ids"])]
			if not o["attack"].is_empty():
				msg += " Clicca un esagono rosso per attaccare."
			if req.get("again", "") != "":
				msg += " [i](Secondo attacco: %s)[/i]" % ("Furia" if req["again"] == "fury" else "Sofia")
			if o.get("ship", false):
				_add_btn("Movimento navale", func(): _provide({"a": "ship"}))
			if o.get("recover", false):
				_add_btn("Recupera la piena forza", func(): _provide({"a": "recover"}))
			if o.get("mine", false):
				_add_btn("Lavora la miniera (+1 oro)", func(): _provide({"a": "mine"}))
			_add_btn("Nessuna azione", func(): _provide({"a": "pass"}), true)
		"setup_free":
			msg = "%s · schiera gratis [b]%s[/b]: clicca uno degli esagoni evidenziati." % [_who(k), D.UNITS[req["u"]]["n"]]
		"setup_coven":
			msg = "%s · nascondi una [b]Congrega[/b]: clicca un insediamento evidenziato." % _who(k)
		"coven":
			msg = "%s · puoi tentare di piazzare una [b]Congrega[/b] (1d6, 5+ con i modificatori): clicca un insediamento." % _who(k)
			_add_btn("Nessuna Congrega", func(): _provide(null), true)
		"hero_place":
			msg = "%s · un nuovo [b]eroe[/b] si unisce a un'armata: clicca l'armata evidenziata." % _who(k)
		"place_ctrl":
			msg = "%s · mettere un [b]segnalino di controllo[/b] a %s?" % [_who(k), engine.hname(int(req["h"]))]
			_add_btn("Sì, controllalo", func(): _provide(true), true)
			_add_btn("No", func(): _provide(false))
		"conquer":
			msg = "%s · %s è tuo: [b]controllarlo[/b] o [b]raderlo al suolo[/b]?" % [_who(k), engine.hname(int(req["h"]))]
			_add_btn("Segnalino di controllo", func(): _provide("ctrl"), true)
			_add_btn("Radi al suolo", func(): _provide("raze"))
		"ambush":
			if req["role"] == "atk":
				msg = "%s · dichiari un'[b]imboscata[/b] contro %s?" % [_who(k), engine.hname(int(req["t"]))]
			else:
				msg = "%s · %s è attaccato: rispondi con un'[b]imboscata[/b]?" % [_who(k), engine.hname(int(req["t"]))]
			_add_btn("Sì, imboscata", func(): _provide(true), true)
			_add_btn("No, combattimento normale", func(): _provide(false))
		"hit":
			msg = "%s · [b]assegna un colpo[/b] (ne restano %d): scegli l'unità." % [_who(k), int(req["left"])]
			for id in o:
				var u := engine.unit(int(id))
				var lab := "Guarnigione" if int(id) < 0 else "%s%s" % [engine.uname(u), " (indebolita)" if not u.is_empty() and u["weak"] else ""]
				var iid := int(id)
				_add_btn(lab, func(): _provide(iid))
		"advance":
			msg = "%s · [b]avanzare[/b] dopo il combattimento in %s?" % [_who(k), engine.hname(int(req["t"]))]
			_add_btn("Avanza", func(): _provide(true), true)
			_add_btn("Resta", func(): _provide(false))
		"disband_siege":
			msg = "%s · smontare la [b]Macchina d'Assedio[/b] per ricostruirla altrove?" % _who(k)
			_add_btn("Smonta", func(): _provide(true))
			_add_btn("Tienila", func(): _provide(false), true)
		"lay_waste":
			msg = "%s · [b]Devastare[/b]: clicca gli insediamenti da radere al suolo e saccheggiare (3 oro, 6 le città), poi conferma." % _who(k)
			_add_btn("Conferma (%d)" % lw_sel.size(), func(): _provide(lw_sel.keys()), true)
			_add_btn("Nessuno", func(): _provide([]))
		"magic":
			msg = _magic_ui(req)
		"study":
			msg = _study_ui(req)
		"fear":
			msg = "%s · [b]Paura[/b]: %s può arretrare in un esagono evidenziato, altrimenti subisce il colpo." % [_who(k), engine.uname(engine.unit(int(req["id"])))]
			_add_btn("Subisci il colpo", func(): _provide(-1))
		"counter":
			msg = "%s · contrattaccare subito %s?" % [_who(k), engine.hname(int(req["t"]))]
			_add_btn("Contrattacca", func(): _provide(true), true)
			_add_btn("No", func(): _provide(false))
		_:
			msg = "Decisione: %s" % t
			_add_btn("Continua", func(): _provide(null))
	action_msg.text = msg
	_fit_action()


func _stack_txt(ids: Array) -> String:
	var parts: Array = []
	for id in ids:
		var u := engine.unit(int(id))
		if not u.is_empty():
			parts.append(engine.uname(u))
	return "[b]%s[/b]" % " + ".join(parts)


func _main_ui(req: Dictionary) -> String:
	var k := int(req["k"])
	var o: Dictionary = req["options"]
	var opening: bool = req.get("opening", false)
	var msg := "%s · " % _who(k)
	if opening:
		msg += "[b]Schieramento iniziale[/b]: costruisci con l'oro di partenza (%d)." % int(engine.kd[k]["gold"])
	else:
		msg += "[b]Attivazione[/b] (%d oro): clicca una pila gialla per attivarla" % int(engine.kd[k]["gold"])
		if not o["monsters"].is_empty():
			msg += ", un mostro viola per farlo agire"
		msg += ", oppure costruisci."
	if sel_mode.begins_with("build:"):
		var t := sel_mode.substr(6)
		msg += "\nCostruisci [b]%s[/b] (%d oro): clicca un esagono verde. Tasto destro per annullare." % [D.UNITS[t]["n"], int(D.UNITS[t]["cost"])]
	elif sel_mode == "hero":
		msg += "\nNuovo [b]eroe[/b]: clicca un esagono verde."
	elif sel_mode == "unraze":
		msg += "\nRicostruisci le rovine (2 oro): clicca un esagono evidenziato."
	elif sel_mode == "rm_coven":
		msg += "\nRitira una Congrega: clicca un insediamento evidenziato."
	elif sel_mode.begins_with("monster:"):
		var mh := int(sel_mode.substr(8))
		var md := D.monster(engine.monsters[mh]["m"])
		msg += "\n[color=#cbb0ff]%s[/color]: clicca un bersaglio rosso per l'Assalto, oppure sgattaiola via o passa." % md["n"]
		_add_btn("Sgattaiola via", func(): _provide({"a": "monster", "h": mh, "do": "slink"}))
		_add_btn("Passa", func(): _provide({"a": "monster", "h": mh, "do": "pass"}))
		_add_btn("Annulla", _cancel_sel)
		return msg
	for t in o["builds"]:
		var tt: String = t
		var b := _add_btn("%s · %d" % [D.UNITS[t]["n"], int(D.UNITS[t]["cost"])], func(): _set_sel("build:" + tt), false, 18)
		b.icon = UI.counter_tex(D.unit_img(t, 0))
		b.expand_icon = true
		b.custom_minimum_size = Vector2(0, 50)
		b.add_theme_constant_override("icon_max_width", 40)
		b.tooltip_text = _unit_tip_t(t)
		if sel_mode == "build:" + t:
			UI.primary(b)
	if not o["hero"].is_empty():
		var hb := _add_btn("Eroe · %d" % int(D.KINGDOMS[k]["hero_cost"]), func(): _set_sel("hero"), false, 18)
		if sel_mode == "hero":
			UI.primary(hb)
	if not o["unraze"].is_empty():
		_add_btn("Ricostruisci rovine · 2", func(): _set_sel("unraze"), false, 18)
	for id in o["regen"]:
		var u := engine.unit(int(id))
		var iid := int(id)
		_add_btn("Rigenera %s · %d" % [engine.uname(u), int(D.UNITS[u["t"]]["rec"])], func(): _provide({"a": "regen", "id": iid}), false, 18)
	if int(o["suppress"]) > 0:
		_add_btn("Reprimi una rivolta · 1", func(): _provide({"a": "suppress", "n": 1}), false, 18)
	if not o["gift"].is_empty():
		_add_btn("Dona oro", func(): _gift_ui(k, o["gift"]), false, 18)
	if not o["rm_coven"].is_empty():
		_add_btn("Ritira una Congrega", func(): _set_sel("rm_coven"), false, 18)
	if not o["sell"].is_empty():
		_add_btn("Vendi un tesoro", func(): _sell_ui(o["sell"]), false, 18)
	if not o["cards"].is_empty() or not o["powers"].is_empty():
		msg += "\nCarte giocabili evidenziate in oro (mano e plancia)."
	_add_btn("FINE SCHIERAMENTO" if opening else "FINE TURNO", func(): _confirm_end(), true, 20)
	return msg


func _confirm_end() -> void:
	var o: Dictionary = pending["options"]
	if not o["acts"].is_empty():
		var vb := _open_modal("FINIRE IL TURNO?", 620)
		vb.add_child(UI.label("Hai ancora %d pile pronte da attivare." % o["acts"].size(), 22))
		var hb := HBoxContainer.new()
		hb.add_theme_constant_override("separation", 12)
		vb.add_child(hb)
		hb.add_child(_modal_btn("SÌ, FINE TURNO", func(): _provide({"a": "end"})))
		hb.add_child(_modal_btn("NO", func(): pass))
		return
	_provide({"a": "end"})


func _set_sel(m: String) -> void:
	sel_mode = "" if sel_mode == m else m
	_show_decision()
	_refresh_highlights()


func _cancel_sel() -> void:
	if sel_mode != "":
		sel_mode = ""
		_show_decision()
		_refresh_highlights()


func _gift_ui(k: int, to: Array) -> void:
	var vb := _open_modal("DONA ORO A UN ALLEATO", 640)
	vb.add_child(UI.label("Ogni oro donato ne costa 2 (hai %d oro)." % int(engine.kd[k]["gold"]), 21))
	for a in to:
		var aa := int(a)
		vb.add_child(_modal_btn("1 oro a %s" % D.KINGDOMS[aa]["n"], func(): _provide({"a": "gift", "to": aa, "n": 1})))
	vb.add_child(_modal_btn("Annulla", func(): pass))


func _sell_ui(cards: Array) -> void:
	var vb := _open_modal("VENDI UN TESORO", 900)
	vb.add_child(UI.label("Un tesoro si vende per 2 oro (liberarsi di una maledizione costa 3).", 21))
	var hb := HFlowContainer.new()
	hb.add_theme_constant_override("h_separation", 10)
	vb.add_child(hb)
	for c in cards:
		var cc := str(c)
		var v := VBoxContainer.new()
		hb.add_child(v)
		var tr := UI.icon_rect(UI.card_tex(cc), Vector2(150, 206))
		tr.stretch_mode = TextureRect.STRETCH_SCALE
		v.add_child(tr)
		v.add_child(_modal_btn("Vendi", func(): _provide({"a": "sell", "c": cc})))
	vb.add_child(_modal_btn("Annulla", func(): pass))


func _play_label(pl: Dictionary) -> String:
	var s := str(pl.get("label", D.card(str(pl["c"])).get("n", pl["c"])))
	var t = pl.get("t", null)
	if (t is int or t is float) and int(t) >= 0 and D.hexes.has(int(t)) and engine.in_map(int(t)):
		s += " » %s" % engine.hname(int(t))
	var c := int(pl.get("caster", -1))
	if c >= 0:
		var u := engine.unit(c)
		if not u.is_empty():
			s += " (lancia %s)" % engine.uname(u)
	if str(pl.get("tome", "")) != "":
		s += " + tomo %s" % D.card(str(pl["tome"])).get("n", pl["tome"])
	return s


func _on_card_click(id: String) -> void:
	if pending.is_empty() or cover_for >= 0:
		return
	var s := int(pending["seat"])
	if s != _visible_hand():
		return
	if pending["type"] == "main":
		var o: Dictionary = pending["options"]
		var a := ""
		if id in o["cards"]:
			a = "card"
		elif id in o["powers"]:
			a = "power"
		if a == "":
			return
		var ps: Array = engine.magic.plays_for(s, id, "main", {})
		if ps.is_empty():
			return
		if ps.size() == 1:
			var r: Dictionary = ps[0].duplicate()
			r["a"] = a
			_provide(r)
			return
		var vb := _open_modal(str(D.card(id)["n"]).to_upper(), 760)
		vb.add_child(UI.label("Scegli come giocarla:", 21))
		for pl in ps:
			var r2: Dictionary = pl.duplicate()
			r2["a"] = a
			vb.add_child(_modal_btn(_play_label(pl), func(): _provide(r2)))
		vb.add_child(_modal_btn("Annulla", func(): pass))
	elif pending["type"] == "magic":
		var mine: Array = []
		for pl in pending["plays"]:
			if str(pl["c"]) == id:
				mine.append(pl)
		if mine.size() == 1:
			_provide(mine[0])
		elif mine.size() > 1:
			var vb2 := _open_modal(str(D.card(id)["n"]).to_upper(), 760)
			for pl in mine:
				var p2: Dictionary = pl
				vb2.add_child(_modal_btn(_play_label(pl), func(): _provide(p2)))
			vb2.add_child(_modal_btn("Annulla", func(): pass))


func _magic_ui(req: Dictionary) -> String:
	var k := int(req["k"])
	var w := str(req["window"])
	var msg := "%s · [b]%s[/b]: puoi giocare una carta." % [_who(k), WINDOW_NAMES.get(w, w.capitalize())]
	if not engine.cb.is_empty() and engine.cb.has("t"):
		msg += " Combattimento a %s." % engine.hname(int(engine.cb["t"]))
	var seen := {}
	for pl in req["plays"]:
		var p2: Dictionary = pl
		var b := _add_btn(_play_label(pl), func(): _provide(p2), false, 18)
		var cid := str(pl["c"])
		b.mouse_entered.connect(func(): _show_zoom(cid, b))
		b.mouse_exited.connect(_hide_zoom)
		seen[cid] = true
	_add_btn("Passa", func(): _provide({"pass": true}), true)
	return msg


func _study_ui(req: Dictionary) -> String:
	var n := int(req["n"])
	var o: Dictionary = req["options"]
	var msg := "[b]Studio arcano[/b] per %s: scegli fino a %d disciplin%s." % [engine.players[int(req["seat"])]["name"], n, "a" if n == 1 else "e"]
	var picks := {"s": false, "b": false, "t": ""}
	var order: Array = []
	var redo := func(): pass
	var bs := _add_btn("Incantesimi: pesca fino a 3", func(): pass)
	var bb := _add_btn("Benedizioni: cambiane una", func(): pass)
	var tbtns: Array = []
	for c in o["treasure"]:
		tbtns.append([str(c), _add_btn("Riprendi in mano %s" % D.card(str(c))["n"], func(): pass)])
	var paint := func():
		bs.add_theme_stylebox_override("normal", UI.panel_style(UI.GOLD if picks["s"] else Color("#2a241a"), UI.GOLD, 2, 5))
		bs.add_theme_color_override("font_color", UI.DARK if picks["s"] else Color.WHITE)
		bb.add_theme_stylebox_override("normal", UI.panel_style(UI.GOLD if picks["b"] else Color("#2a241a"), UI.GOLD, 2, 5))
		bb.add_theme_color_override("font_color", UI.DARK if picks["b"] else Color.WHITE)
		for tb in tbtns:
			var on: bool = picks["t"] == tb[0]
			tb[1].add_theme_stylebox_override("normal", UI.panel_style(UI.GOLD if on else Color("#2a241a"), UI.GOLD, 2, 5))
			tb[1].add_theme_color_override("font_color", UI.DARK if on else Color.WHITE)
	var toggle := func(key: String, val):
		if key == "t":
			if picks["t"] == val:
				picks["t"] = ""
				order.erase("t")
			elif order.size() < n or order.has("t"):
				picks["t"] = val
				if not order.has("t"):
					order.append("t")
		else:
			if picks[key]:
				picks[key] = false
				order.erase(key)
			elif order.size() < n:
				picks[key] = true
				order.append(key)
		paint.call()
	bs.pressed.connect(func(): toggle.call("s", true))
	bb.pressed.connect(func(): toggle.call("b", true))
	for tb in tbtns:
		var cid: String = tb[0]
		tb[1].pressed.connect(func(): toggle.call("t", cid))
	paint.call()
	_add_btn("Conferma", func(): _provide({"s": picks["s"], "b": picks["b"], "t": picks["t"], "sd": "", "bd": "", "order": order}), true)
	return msg


func _add_btn(text: String, cb: Callable, primary := false, fs := 20) -> Button:
	var b := UI.button(text, 0, 46, fs)
	if primary:
		UI.primary(b)
	b.pressed.connect(cb)
	action_row.add_child(b)
	return b


func _clear_actions() -> void:
	for c in action_row.get_children():
		action_row.remove_child(c)
		c.queue_free()


func _fit_action() -> void:
	await get_tree().process_frame
	if is_instance_valid(action_box):
		_layout_action()


func _provide(r) -> void:
	if pending.is_empty():
		return
	pending = {}
	sel_mode = ""
	lw_sel.clear()
	_clear_actions()
	_clear_modal()
	_hide_zoom()
	action_box.visible = false
	engine.provide_decision(r)
	refresh()


func _on_hex_click(h: int, button: int) -> void:
	if button == MOUSE_BUTTON_RIGHT:
		_cancel_sel()
		return
	if h < 0 or pending.is_empty() or cover_for >= 0:
		return
	var req := pending
	var o = req.get("options", null)
	var k := int(req["k"])
	match str(req["type"]):
		"main":
			if sel_mode.begins_with("build:"):
				var t := sel_mode.substr(6)
				if h in o["builds"].get(t, []):
					_provide({"a": "build", "u": t, "h": h})
				else:
					_cancel_sel()
			elif sel_mode == "hero":
				if h in o["hero"]:
					_provide({"a": "hero", "h": h})
				else:
					_cancel_sel()
			elif sel_mode == "unraze":
				if h in o["unraze"]:
					_provide({"a": "unraze", "h": h})
				else:
					_cancel_sel()
			elif sel_mode == "rm_coven":
				if h in o["rm_coven"]:
					_provide({"a": "rm_coven", "h": h})
				else:
					_cancel_sel()
			elif sel_mode.begins_with("monster:"):
				var mh := int(sel_mode.substr(8))
				if h in engine.monster_targets(k, mh):
					_provide({"a": "monster", "h": mh, "do": "strike", "t": h})
				elif h in o["monsters"]:
					_set_sel("monster:%d" % h)
				else:
					_cancel_sel()
			elif h in o["acts"]:
				_activate_ui(k, h)
			elif h in o["monsters"]:
				_set_sel("monster:%d" % h)
		"move":
			if o["reach"].has(h):
				_provide({"to": h})
		"ship_move":
			if o.has(h):
				_provide(h)
		"action":
			if h in o["attack"]:
				_provide({"a": "attack", "t": h})
		"setup_free", "setup_coven", "coven", "fear":
			if h in o:
				_provide(h)
		"hero_place":
			for id in o:
				if int(engine.unit(int(id))["h"]) == h:
					_provide(int(id))
					return
		"lay_waste":
			if h in o:
				if lw_sel.has(h):
					lw_sel.erase(h)
				else:
					lw_sel[h] = true
				_show_decision()
				_refresh_highlights()


func _activate_ui(k: int, h: int) -> void:
	var us: Array = []
	for u in engine.units_at(h):
		if engine.owner(u) == k and not u["fin"]:
			us.append(u)
	if us.size() <= 1:
		_provide({"a": "act", "h": h, "ids": []})
		return
	var vb := _open_modal("ATTIVA A %s" % engine.hname(h).to_upper(), 620)
	vb.add_child(UI.label("Chi si muove?", 22))
	vb.add_child(_modal_btn("Tutta la pila (%s)" % " + ".join(us.map(func(x): return engine.uname(x))), func(): _provide({"a": "act", "h": h, "ids": []})))
	for u in us:
		var id := int(u["id"])
		vb.add_child(_modal_btn("Solo %s" % engine.uname(u), func(): _provide({"a": "act", "h": h, "ids": [id]})))
	vb.add_child(_modal_btn("Annulla", func(): pass))


# =================================================================== modali

func _clear_modal() -> void:
	for c in modal.get_children():
		c.queue_free()
	modal.mouse_filter = Control.MOUSE_FILTER_IGNORE


func _open_modal(title_text: String, w := 640.0, dim := true) -> VBoxContainer:
	_clear_modal()
	modal.mouse_filter = Control.MOUSE_FILTER_STOP
	modal.move_to_front()
	if dim:
		var sh := ColorRect.new()
		sh.color = Color(0, 0, 0, 0.55)
		sh.size = size
		modal.add_child(sh)
	var box := PanelContainer.new()
	box.add_theme_stylebox_override("panel", UI.panel_style(Color("#150f0bf8"), UI.GOLD, 2, 10))
	box.custom_minimum_size = Vector2(w, 0)
	modal.add_child(box)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 12)
	box.add_child(vb)
	vb.add_child(UI.title(title_text, 30))
	_center_box.call_deferred(box)
	return vb


func _center_box(box: Control) -> void:
	if is_instance_valid(box):
		box.position = (size - box.size) / 2


func _modal_btn(text: String, cb: Callable) -> Button:
	var b := UI.button(text, 0, 54, 21)
	b.pressed.connect(func():
		_clear_modal()
		cb.call())
	return b


# =================================================================== effetti e registro

func _on_log(t: String) -> void:
	var line := t
	for k in engine.kd:
		var n: String = D.KINGDOMS[k]["n"]
		if line.contains(n):
			line = line.replace(n, "[color=#%s]%s[/color]" % [UI.klight(k).to_html(false), n])
	log_text.append_text(line + "\n")
	var sc: ScrollContainer = log_text.get_meta("sc")
	await get_tree().process_frame
	if is_instance_valid(sc):
		sc.scroll_vertical = int(sc.get_v_scroll_bar().max_value)


func _on_fx(kind: String, data: Dictionary) -> void:
	match kind:
		"combat":
			board.flash(int(data["t"]), Color("#ff6a30"))
			if engine.any_local_human() or engine.ai_delay > 0.2:
				board.focus(int(data["t"]))
		"dice":
			if data.get("what", "") == "battle":
				_show_battle_dice(data)
			elif data.get("what", "") == "strike":
				_show_strike_dice(data)
		"raze":
			board.flash(int(data["h"]), Color("#ff3a10"))
			_toast("%s è raso al suolo!" % engine.hname(int(data["h"])), UI.EMBER)
		"loot":
			_toast("%s saccheggia %s: +%d oro" % [D.KINGDOMS[int(data["k"])]["short"], engine.hname(int(data["h"])), int(data["g"])], Color("#f2c75c"))
		"collapse":
			_toast("%s crolla!" % D.KINGDOMS[int(data["k"])]["n"], UI.RED)
		"season":
			_toast(engine.season_text().to_upper(), UI.GOLD)
		"turn":
			if mat_auto:
				mat_k = int(data["k"])
		"monster":
			board.flash(int(data["h"]), Color("#a050ff"))
		"coven":
			board.flash(int(data["h"]), Color("#ff3050"))
	board.refresh()


func _dice_row(rolls: Array) -> HFlowContainer:
	var hb := HFlowContainer.new()
	hb.add_theme_constant_override("h_separation", 4)
	hb.custom_minimum_size = Vector2(250, 0)
	for rr in rolls:
		var p := PanelContainer.new()
		var ok: bool = rr["ok"]
		var crit: bool = rr.get("crit", false)
		var bgc := Color("#e8dcc0") if int(rr["d"]) == 6 else Color("#2a2a30")
		var bc := Color("#3fae4a") if ok else Color("#6a5a4a")
		if crit:
			bc = Color("#ffd04a")
		p.add_theme_stylebox_override("panel", UI.panel_style(bgc, bc, 3, 5 if int(rr["d"]) == 6 else 12))
		p.custom_minimum_size = Vector2(38, 38)
		var l := UI.label(str(rr["v"]), 22, Color("#201a12") if int(rr["d"]) == 6 else Color("#f0f0f0"), UI.font_bold)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		p.add_child(l)
		hb.add_child(p)
	return hb


func _show_battle_dice(d: Dictionary) -> void:
	for c in dice_panel.get_children():
		c.queue_free()
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 6)
	dice_panel.add_child(vb)
	var ak := int(engine.cb.get("k", engine.cur_k)) if not engine.cb.is_empty() else engine.cur_k
	var dk := engine._def_controller() if not engine.cb.is_empty() else -1
	vb.add_child(UI.title("COMBATTIMENTO A %s" % engine.hname(int(d["t"])).to_upper(), 24, UI.EMBER))
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 26)
	vb.add_child(hb)
	for side in [["Attacco", ak, d["a"], int(d["sa"])], ["Difesa", dk, d["d"], int(d["sd"])]]:
		var col := VBoxContainer.new()
		hb.add_child(col)
		var who: String = D.KINGDOMS[side[1]]["short"] if int(side[1]) >= 0 else ("Mostro" if engine.monsters.has(int(d["t"])) else "Guarnigione")
		col.add_child(UI.label("%s · %s" % [side[0], who], 20, UI.klight(int(side[1])) if int(side[1]) >= 0 else Color("#d0c8b8"), UI.font_bold))
		col.add_child(_dice_row(side[2]["rolls"]))
		var extra := ""
		if not side[2]["conf"].is_empty():
			extra = " (conferme critici: %s)" % ", ".join(side[2]["conf"].map(func(x): return str(x)))
		if int(side[2]["mod"]) != 0:
			extra += " · modificatore %+d" % int(side[2]["mod"])
		col.add_child(UI.label("%d successi%s" % [side[3], extra], 19, Color.WHITE))
	var res := ""
	if int(d["sa"]) > int(d["sd"]):
		res = "Vince l'attaccante: %d colp%s" % [int(d["sa"]) - int(d["sd"]), "o" if int(d["sa"]) - int(d["sd"]) == 1 else "i"]
	elif int(d["sd"]) > int(d["sa"]):
		res = "Vince il difensore: %d colp%s" % [int(d["sd"]) - int(d["sa"]), "o" if int(d["sd"]) - int(d["sa"]) == 1 else "i"]
	else:
		res = "Pareggio"
	vb.add_child(UI.label(res, 22, UI.GOLD, UI.font_bold))
	_place_dice()


func _show_strike_dice(d: Dictionary) -> void:
	for c in dice_panel.get_children():
		c.queue_free()
	var vb := VBoxContainer.new()
	dice_panel.add_child(vb)
	var r: Dictionary = d.get("a", d.get("d", {}))
	if r.is_empty():
		return
	vb.add_child(UI.title("ASSALTO A %s" % engine.hname(int(d["t"])).to_upper(), 24, UI.EMBER))
	vb.add_child(_dice_row(r["rolls"]))
	vb.add_child(UI.label("%d successi" % (int(r["s"]) + int(r["extra"])), 20, Color.WHITE))
	_place_dice()


func _place_dice() -> void:
	dice_panel.visible = true
	dice_panel.move_to_front()
	dice_t = 5.0 if engine.any_local_human() else 2.5
	dice_panel.size = Vector2.ZERO
	await get_tree().process_frame
	if is_instance_valid(dice_panel):
		dice_panel.position = Vector2((1920 - dice_panel.size.x) / 2 + 120, TOP_H + 14)


func _toast(t: String, col: Color) -> void:
	for c in toast.get_children():
		c.queue_free()
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", UI.panel_style(Color("#100b08ee"), col, 2, 8))
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	toast.add_child(p)
	var l := UI.title(t, 28, col)
	p.add_child(l)
	toast.move_to_front()
	await get_tree().process_frame
	if not is_instance_valid(p):
		return
	p.position = Vector2((1920 - p.size.x) / 2 + 120, 330)
	var tw := p.create_tween()
	tw.tween_interval(1.6)
	tw.tween_property(p, "modulate:a", 0.0, 0.6)
	tw.tween_callback(p.queue_free)


func _input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_RIGHT and sel_mode != "":
		if not board_input.get_global_rect().has_point(ev.position):
			_cancel_sel()


# =================================================================== fine partita

func _on_game_end(res: Dictionary) -> void:
	pending = {}
	action_box.visible = false
	if online != null:
		online.finish()
		online_status("")
	var w := int(res["winner"])
	var vb := _open_modal("FINE DELLA PARTITA", 1180)
	var col := Color("#ff8a70") if w == 0 else Color("#8ac0f0")
	vb.add_child(UI.title("VINCONO %s" % (D.SIDE_NAMES[w].to_upper() if w >= 0 else "NESSUNO"), 44, col))
	var ks: Array = []
	for k in engine.side:
		if int(engine.side[k]) == w:
			ks.append(D.KINGDOMS[k]["n"])
	var how := UI.label("%s · %s" % [", ".join(ks), res.get("reason", "")], 23, Color("#e8e0d0"))
	how.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	how.custom_minimum_size = Vector2(1140, 0)
	vb.add_child(how)
	vb.add_child(UI.label("Campagna: %s · %d turni giocati" % [engine.camp["n"], int(res.get("turns", engine.turn_no))], 20, UI.MUTED))
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 16)
	vb.add_child(hb)
	for sd in [0, 1]:
		var pc := PanelContainer.new()
		pc.add_theme_stylebox_override("panel", UI.panel_style(Color("#1d1611"), Color("#ff8a70") if sd == 0 else Color("#8ac0f0"), 3 if sd == w else 1, 8))
		pc.custom_minimum_size = Vector2(560, 0)
		hb.add_child(pc)
		var cv := VBoxContainer.new()
		pc.add_child(cv)
		cv.add_child(UI.title(D.SIDE_NAMES[sd].to_upper(), 28, Color("#ff8a70") if sd == 0 else Color("#8ac0f0")))
		var vpd: Dictionary = res["vp"][sd]
		var r := UI.rich(19)
		r.custom_minimum_size = Vector2(530, 0)
		var s := "Insediamenti controllati: [b]%d[/b] PV" % int(vpd["sets"])
		if sd == 0:
			s += "\nInsediamenti rasi al suolo: [b]%d[/b] PV\nCongreghe: [b]%d[/b] PV" % [int(vpd["razed"]), int(vpd["covens"])]
		s += "\n[b]Totale: %d PV[/b]\n" % int(vpd["tot"])
		for k in engine.side:
			if int(engine.side[k]) != sd:
				continue
			s += "\n[color=#%s]%s[/color]: %d PV di insediamenti, %d oro%s" % [UI.klight(k).to_html(false), D.KINGDOMS[k]["n"], engine.kingdom_vp(k), int(engine.kd[k]["gold"]), " · crollato" if engine.kd[k]["collapsed"] else ""]
		r.text = s
		cv.add_child(r)
	var bh := HBoxContainer.new()
	bh.add_theme_constant_override("separation", 12)
	vb.add_child(bh)
	var b1 := UI.primary(UI.button("MENU", 260, 60, 26))
	b1.pressed.connect(func(): main.show_menu())
	bh.add_child(b1)
	var b2 := UI.button("RIVEDI LA MAPPA", 300, 60, 22)
	b2.pressed.connect(func(): _clear_modal())
	bh.add_child(b2)


func _ask_quit() -> void:
	var vb := _open_modal("TORNARE AL MENU?", 600)
	vb.add_child(UI.label("La partita in corso andrà persa." if online == null else "Potrai rientrare nella stanza con lo stesso codice.", 22))
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 12)
	vb.add_child(hb)
	var y := UI.primary(UI.button("SÌ, AL MENU", 240, 56, 22))
	y.pressed.connect(func():
		if online != null:
			main.get_net().set_away(online.code, online.seat, true)
		main.show_menu())
	hb.add_child(y)
	var n := UI.button("NO", 160, 56, 22)
	n.pressed.connect(func():
		_clear_modal()
		if cover_for >= 0:
			_cover(cover_for))
	hb.add_child(n)


func _show_rules_popup() -> void:
	var r := preload("res://scripts/ui/rules_view.gd").new()
	r.main = main
	r.embedded = true
	r.on_close = func(): r.queue_free()
	add_child(r)


# =================================================================== online

func _build_online_label() -> void:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", UI.panel_style(Color("#0b0907ee"), UI.GOLD, 1, 6))
	p.position = Vector2(MAT_W + 24, TOP_H + 10)
	add_child(p)
	online_lbl = UI.label("", 20, Color.WHITE)
	p.add_child(online_lbl)
	p.visible = false
	online_lbl.set_meta("box", p)


func online_status(t: String) -> void:
	if online_lbl == null:
		return
	online_lbl.text = t
	var b: Control = online_lbl.get_meta("box")
	b.visible = t != ""
	b.move_to_front()


func online_waiting(seat: int, is_slow: bool) -> void:
	if seat < 0:
		online_status("")
		return
	var t := "Online · stanza %s · tocca a %s" % [online.code, engine.players[seat]["name"]]
	if is_slow:
		t += " (non risponde da un po')"
	online_status(t)


func online_caught_up() -> void:
	online_status("")
	refresh()


func online_cancel_decision(t: String) -> void:
	pending = {}
	_clear_modal()
	action_box.visible = false
	online_status(t)
