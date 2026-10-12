class_name BBEngine
extends Node
## Motore delle regole di Burning Banners: Rage of the Witch Queen (Compass Games), gioco base e
## avanzato. Nessuna dipendenza dall'interfaccia: ogni scelta passa da `decide()`. L'IA risponde
## subito; per le persone viene emesso `decision_requested` e si attende `provide_decision()`.
## Online le scelte passano dal registro di mosse (OnlineSession) e, con lo stesso seme, ogni
## dispositivo ottiene la stessa partita.

signal changed
signal log_added(text: String)
signal decision_requested(req: Dictionary)
signal decision_provided(result)
signal game_ended(results: Dictionary)
signal fx(kind: String, data: Dictionary)
signal pause_requested(req: Dictionary)

const D = preload("res://scripts/data/bb_data.gd")
const MagicScript = preload("res://scripts/core/magic.gd")

var rng := RandomNumberGenerator.new()
var ai_delay := 0.0
var headless := false
var ais := {}
var online = null
var abort := false
var pause_enabled := false
var magic                                # BBMagic: carte e poteri degli eroi

# ------------------------------------------------------------------ stato
var advanced := false
var camp: Dictionary = {}
var long_game := false
var players: Array = []                  # posti: {"name","ai","level","ks":[regni],"hand":[],"owned":[]}
var seat_of := {}                        # regno -> posto
var side := {}                           # regno -> 0 invasori / 1 resistenza
var order: Array = []                    # ordine di turno
var kd := {}                             # regno -> stato del regno
var units: Array = []
var uid_next := 1
var ctrl := {}                           # esagono -> regno con il segnalino di controllo
var razed := {}                          # esagono -> true
var coven := {}                          # esagono -> true
var monsters := {}                       # esagono -> {"m","def","cmd","fin","wander"}
var abandoned := {}
var pool_land: Array = []
var pool_sea: Array = []
var active_maps := {}
var inplay := {}                         # esagoni degli insediamenti in gioco
var welcome := {}                        # esagono -> schieramento per cui è accogliente
var temp_entry := {}                     # esagono -> regno
var khazud := -1                         # esagono della Città Perduta di Khazud
var year := 1
var season := 0
var end_year := 2
var end_season := 2
var turn_no := 0
var cur_k := -1
var phase := ""
var game_over := false
var results := {}
var log_lines: Array = []
var made_friendly := {}                  # insediamenti diventati amici in questo turno (non vi si costruisce)
var sea_built := {}                      # unità costruite in un esagono d'ingresso di mare
var winner := -1
var win_reason := ""
# carte (gioco avanzato)
var spell_deck: Array = []
var spell_disc: Array = []
var tre_deck: Array = []
var tre_out: Array = []                  # tesori eliminati o venduti (tornano nel mazzo d'inverno)
var bless_deck := {}                     # regno -> mazzo
var bless_disc: Array = []
var study_pool: Array = []               # segnalini di Studio Arcano in gioco ("glyph"/"churn")
var autumn_in := false
var study := {}                          # regno -> segnalino del turno
var effects: Array = []                  # effetti temporanei delle carte
# attivazione e combattimento in corso
var act := {}                            # pila attiva: {"k","h","ids","ship_used","mp_used","road"}
var cb := {}                             # combattimento in corso
var last_cast := {}                      # ultima carta giocata (per Negazione, Risacca…)
var _occ = null                          # occupazione congelata (calcoli di raggiungibilità e IA)
var _uidx := {}


# ================================================================== preparazione

## config: {"campaign": int, "advanced": bool, "long": bool, "seed": int,
##          "seats": [{"name","ai","level","ks":[regni]}]}
func setup(config: Dictionary) -> void:
	D.load_all()
	if config.has("seed"):
		rng.seed = int(config["seed"])
	else:
		rng.randomize()
	advanced = bool(config.get("advanced", false))
	long_game = bool(config.get("long", false))
	camp = D.CAMPAIGNS[int(config.get("campaign", 0))]
	magic = MagicScript.new()
	magic.eng = self
	players.clear()
	seat_of.clear()
	ais.clear()
	var seats: Array = config["seats"]
	for i in range(seats.size()):
		var s: Dictionary = seats[i]
		var a := BBAI.new()
		a.level = int(s.get("level", 1))
		a.rng.seed = int(config.get("seed", 1)) * 7 + i * 131 + 17
		ais[i] = a
		players.append({"seat": i, "name": str(s.get("name", "Giocatore %d" % (i + 1))), "ai": bool(s.get("ai", true)),
			"level": int(s.get("level", 1)), "ks": s["ks"].duplicate(), "hand": [], "owned": []})
		for k in s["ks"]:
			seat_of[int(k)] = i
	side.clear()
	for k in camp["sides"]:
		side[int(k)] = int(camp["sides"][k])
	order = camp["order"].duplicate()
	active_maps.clear()
	for m in camp["maps"]:
		active_maps[int(m)] = true
	year = int(camp["start"][0])
	season = int(camp["start"][1])
	var en: Array = camp["long_end"] if long_game and camp.has("long_end") else camp["end"]
	end_year = int(en[0])
	end_season = int(en[1])
	# insediamenti in gioco e atteggiamento
	inplay.clear()
	welcome.clear()
	for s in D.settlements:
		if not in_map(s["h"]):
			continue
		if camp.has("inplay") and not (s["n"] in camp["inplay"]):
			continue
		inplay[s["h"]] = true
	for nm in camp["welcome"]:
		var h := D.hex_of(nm)
		if h >= 0:
			welcome[h] = int(camp["welcome"][nm])
	temp_entry.clear()
	for k in camp.get("temp_entry", {}):
		var what: String = camp["temp_entry"][k]
		for h in D.hexes:
			var e: Dictionary = D.hexes[h]
			if not in_map(h):
				continue
			if what == "north_sea" and e["m"] == 2 and D.row(h) <= 16 and e["t"] == "w" and _local_row(h) == 0:
				temp_entry[h] = int(k)
			elif what == "foa_west" and e["m"] == 3 and D.col(h) == 14 and e["t"] != "w":
				temp_entry[h] = int(k)
	# regni
	kd.clear()
	units.clear()
	uid_next = 1
	for k in side:
		kd[k] = {"gold": 0, "base": 0, "collapsed": false, "revolts": 0, "ever_ctrl": false, "heroes": [], "hcards": {},
			"cmd": 0, "khazud_played": false, "hero_pool": []}
		for u in D.UNIT_ORDER[k]:
			for n in range(int(D.UNITS[u]["num"])):
				_new_unit(k, "army", u, n)
		if advanced:
			var pool: Array = []
			for hid in D.HEROES:
				if int(D.HEROES[hid]["k"]) == k:
					pool.append(hid)
			_shuffle(pool)
			kd[k]["hero_pool"] = pool
	ctrl.clear()
	razed.clear()
	coven.clear()
	monsters.clear()
	abandoned.clear()
	for e in camp["ctrl"]:
		var h := D.hex_of(e[1])
		ctrl[h] = int(e[0])
		kd[int(e[0])]["ever_ctrl"] = true
	for nm in camp.get("razed", []):
		razed[D.hex_of(nm)] = true
	# rendita: base = rendita iniziale meno gli insediamenti già controllati
	for k in side:
		kd[k]["base"] = int(camp["income"].get(k, 0)) - _controlled_count(k)
		kd[k]["gold"] = 0
	pool_land.clear()
	pool_sea.clear()
	for m in D.MONSTERS:
		if m.get("sea", false):
			pool_sea.append(m["id"])
		else:
			pool_land.append(m["id"])
	_shuffle(pool_land)
	_shuffle(pool_sea)
	log_lines.clear()
	game_over = false
	results = {}
	winner = -1


func _local_row(h: int) -> int:
	var e: Dictionary = D.hexes[h]
	return D.row(h) - (15 if e["m"] >= 2 else 0)


func _new_unit(k: int, kind: String, t: String, variant := 0) -> Dictionary:
	var u := {"id": uid_next, "k": k, "kind": kind, "t": t, "h": -1, "weak": false, "fin": false, "v": variant}
	uid_next += 1
	units.append(u)
	_uidx[int(u["id"])] = u
	return u


## Congela l'occupazione degli esagoni (finché nessuna unità si muove): rende veloci le ricerche.
func freeze_occ() -> void:
	var o := {}
	for u in units:
		var h := int(u["h"])
		if h >= 0:
			if not o.has(h):
				o[h] = []
			o[h].append(u)
	_occ = o


func thaw_occ() -> void:
	_occ = null


func _shuffle(a: Array) -> void:
	for i in range(a.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var t = a[i]
		a[i] = a[j]
		a[j] = t


func d6() -> int:
	return rng.randi_range(1, 6)


func d8() -> int:
	return rng.randi_range(1, 8)


func log_msg(t: String) -> void:
	log_lines.append(t)
	if log_lines.size() > 800:
		log_lines.pop_front()
	log_added.emit(t)


func kn(k: int) -> String:
	return D.kname(k)


func pname(seat: int) -> String:
	return players[seat]["name"]


func player_of(k: int) -> Dictionary:
	return players[seat_of[k]]


func any_local_human() -> bool:
	if online != null:
		return true
	for p in players:
		if not p["ai"]:
			return true
	return false


# ================================================================== decisioni

func decide(k: int, req: Dictionary):
	var seat: int = seat_of.get(k, 0)
	req["k"] = k
	req["seat"] = seat
	if abort:
		return ais[seat].decide(self, k, req)
	if online != null:
		var r0 = await online.decide(self, seat, req)
		return r0
	if players[seat]["ai"]:
		if ai_delay > 0.0 and not headless and is_inside_tree() and req.get("slow", true):
			await get_tree().create_timer(ai_delay).timeout
		return ais[seat].decide(self, k, req)
	decision_requested.emit(req)
	var r = await decision_provided
	return r


## Risposta numerica di una decisione (o d se non lo è: una risposta malformata non blocca la partita).
static func _as_int(v, d := -1) -> int:
	return int(v) if (v is int or v is float) else d


func provide_decision(r) -> void:
	decision_provided.emit(r)


func pause_point(req: Dictionary) -> void:
	if headless or abort or not pause_enabled:
		return
	if online != null and online.catchup:
		return
	if not any_local_human():
		return
	pause_requested.emit(req)
	await decision_provided


# ================================================================== interrogazioni sulla mappa

func in_map(h: int) -> bool:
	return D.hexes.has(h) and active_maps.has(int(D.hexes[h]["m"]))


func hexd(h: int) -> Dictionary:
	return D.hexes.get(h, {})


func set_idx(h: int) -> int:
	var e: Dictionary = D.hexes.get(h, {})
	return int(e.get("s", -1)) if not e.is_empty() else -1


func sdata(h: int) -> Dictionary:
	if h == khazud and khazud >= 0:
		return {"n": "Khazud", "h": h, "loy": D.OATH, "city": true, "port": false, "fort": 2, "wild": "mountain"}
	var si := set_idx(h)
	return D.settlements[si] if si >= 0 else {}


## Insediamento in gioco e non raso al suolo.
func is_settlement(h: int) -> bool:
	return (inplay.has(h) or h == khazud) and not razed.has(h)


## Insediamento fuori gioco (Drefeld): non si attacca né si occupa.
func is_inert(h: int) -> bool:
	return set_idx(h) >= 0 and in_map(h) and not inplay.has(h) and not razed.has(h)


func terrain(h: int) -> String:
	return str(D.hexes[h]["t"]) if D.hexes.has(h) else "w"


func is_sea(h: int) -> bool:
	return terrain(h) == "w"


func is_wild(h: int) -> bool:
	return terrain(h) in ["f", "m", "s"]


func is_forest(h: int) -> bool:
	return terrain(h) == "f"


func is_mountain(h: int) -> bool:
	return terrain(h) == "m"


func is_coastal(h: int) -> bool:
	return bool(D.hexes[h]["coast"]) if D.hexes.has(h) else false


func is_wet(h: int) -> bool:
	if not D.hexes.has(h):
		return false
	var e: Dictionary = D.hexes[h]
	return e["t"] == "w" or e["coast"] or e["mr"]


func is_lair(h: int) -> bool:
	return D.hexes.has(h) and str(D.hexes[h]["lair"]) != ""


func is_mine(h: int) -> bool:
	return D.hexes.has(h) and str(D.hexes[h]["mine"]) != ""


func city(h: int) -> bool:
	return is_settlement(h) and bool(sdata(h).get("city", false))


func fort(h: int) -> int:
	return int(sdata(h).get("fort", 0)) if is_settlement(h) else 0


func is_port(h: int) -> bool:
	return is_settlement(h) and bool(sdata(h).get("port", false))


func loyal(h: int) -> int:
	return int(sdata(h).get("loy", -1))


func nbrs(h: int) -> Array:
	var out: Array = []
	for n in D.neighbors(h):
		if in_map(n):
			out.append(n)
	return out


func edge(a: int, b: int) -> Dictionary:
	return D.edge(a, b)


func sea_side(a: int, b: int) -> bool:
	return bool(edge(a, b).get("sea", false))


func entry_owner(h: int) -> int:
	if temp_entry.has(h):
		return int(temp_entry[h])
	var e := str(D.hexes[h]["entry"]) if D.hexes.has(h) else ""
	if e == "g" and side.has(D.GOBLIN):
		return D.GOBLIN
	if e == "o" and side.has(D.ORC):
		return D.ORC
	return -1


func in_play(k: int) -> bool:
	return kd.has(k) and not kd[k]["collapsed"]


func enemies(a: int, b: int) -> bool:
	return side.has(a) and side.has(b) and side[a] != side[b]


func allies(a: int, b: int) -> bool:
	return side.has(a) and side.has(b) and side[a] == side[b]


# ------------------------------------------------------------------ controllo e atteggiamento

## Regno che controlla l'insediamento (−1 nessuno).
func controller(h: int) -> int:
	if not is_settlement(h):
		return -1
	if ctrl.has(h):
		return int(ctrl[h])
	var l := loyal(h)
	if in_play(l):
		return l
	return -1


## "friend", "ally", "welcome", "hostile", "inert" o "" se non è un insediamento.
func posture(h: int, k: int) -> String:
	if is_inert(h):
		return "inert"
	if not is_settlement(h):
		return ""
	var c := controller(h)
	if c >= 0:
		if c == k:
			return "friend"
		if allies(c, k):
			return "ally"
		return "hostile"
	var l := loyal(h)
	if kd.has(l) and kd[l]["collapsed"]:
		return "welcome" if allies(l, k) else "hostile"
	if welcome.has(h) and int(welcome[h]) == side.get(k, -1):
		return "welcome"
	return "hostile"


func welcoming(h: int, k: int) -> bool:
	return posture(h, k) in ["friend", "ally", "welcome"]


func hostile(h: int, k: int) -> bool:
	return posture(h, k) in ["hostile", "inert"]


func _controlled_count(k: int) -> int:
	var n := 0
	for h in inplay:
		if controller(h) == k:
			n += 1
	if khazud >= 0 and controller(khazud) == k:
		n += 1
	return n


func control_markers(k: int) -> int:
	var n := 0
	for h in ctrl:
		if int(ctrl[h]) == k:
			n += 1
	if k == D.NIGHT:
		n += coven.size()
	return n


func markers_left(k: int) -> int:
	return D.CONTROL_MARKERS - control_markers(k)


## Rendita attuale: base della campagna + insediamenti controllati (per i Shashka solo la base:
## i loro segnalini di controllo costano 1 oro a turno invece di rendere).
func income(k: int) -> int:
	if not kd.has(k):
		return 0
	if D.KINGDOMS[k]["shashka"]:
		return maxi(0, int(kd[k]["base"]))
	return maxi(0, int(kd[k]["base"]) + _controlled_count(k))


func cities_of(k: int) -> Array:
	var out: Array = []
	for h in inplay:
		if loyal(h) == k and bool(sdata(h)["city"]):
			out.append(h)
	if khazud >= 0 and k == D.OATH:
		out.append(khazud)
	return out


# ------------------------------------------------------------------ unità

func unit(id: int) -> Dictionary:
	var u = _uidx.get(id, null)
	if u != null and u in units:
		return u
	return {}


func owner(u: Dictionary) -> int:
	if u.is_empty():
		return -1
	return int(u.get("ctl", u["k"]))


func units_at(h: int) -> Array:
	if _occ != null:
		return _occ.get(h, []).duplicate()
	var out: Array = []
	for u in units:
		if int(u["h"]) == h:
			out.append(u)
	return out


func army_at(h: int) -> Dictionary:
	if _occ != null:
		for u in _occ.get(h, []):
			if u["kind"] == "army":
				return u
		return {}
	for u in units:
		if int(u["h"]) == h and u["kind"] == "army":
			return u
	return {}


func hero_at(h: int) -> Dictionary:
	if _occ != null:
		for u in _occ.get(h, []):
			if u["kind"] != "army":
				return u
		return {}
	for u in units:
		if int(u["h"]) == h and u["kind"] != "army":
			return u
	return {}


func is_hero(u: Dictionary) -> bool:
	return u["kind"] != "army"


func uname(u: Dictionary) -> String:
	if u["kind"] == "army":
		return D.UNITS[u["t"]]["n"]
	if u["kind"] == "ehero":
		return "Eroe Assoggettato"
	return str(D.card(u["t"]).get("hero", u["t"]))


func udata(u: Dictionary) -> Dictionary:
	if u["kind"] == "army":
		return D.UNITS[u["t"]]
	if u["kind"] == "ehero":
		return {"l": 0, "h": 0, "mv": 0, "ab": ["mage"], "ch": []}
	return D.HEROES[u["t"]]


func has_ch(u: Dictionary, c: String) -> bool:
	return c in udata(u).get("ch", []) or _eff_has(u, "ch_" + c)


func unit_abs(u: Dictionary) -> Array:
	var a: Array = udata(u)["ab"].duplicate()
	if u["kind"] == "ehero":
		var ar := army_at(int(u["h"]))
		if not ar.is_empty():
			for x in unit_abs(ar):
				if not x in a:
					a.append(x)
	for e in effects:
		if int(e.get("u", -1)) == int(u["id"]) and str(e.get("ab", "")) != "" and not e["ab"] in a:
			a.append(e["ab"])
	return a


func has_ab(u: Dictionary, ab: String) -> bool:
	return ab in unit_abs(u)


## Abilità di una pila: Volo solo se ce l'hanno tutte le unità.
func stack_has(us: Array, ab: String) -> bool:
	if us.is_empty():
		return false
	if ab == "flying":
		for u in us:
			if not has_ab(u, "flying"):
				return false
		return true
	for u in us:
		if has_ab(u, ab):
			return true
	return false


## Un'armata ferina senza un eroe non ferino nella pila.
func feral_limited(us: Array) -> bool:
	var fer := false
	var hero_ok := false
	for u in us:
		if u["kind"] == "army" and has_ch(u, "feral"):
			fer = true
		if is_hero(u) and not has_ch(u, "feral"):
			hero_ok = true
	return fer and not hero_ok


func huge_in(us: Array) -> bool:
	for u in us:
		if has_ch(u, "huge"):
			return true
	return false


func base_mv(u: Dictionary) -> int:
	if u["kind"] == "ehero":
		var ar := army_at(int(u["h"]))
		return base_mv(ar) if not ar.is_empty() else 0
	var m := int(udata(u)["mv"])
	for e in effects:
		if int(e.get("u", -1)) == int(u["id"]) and e.has("mv"):
			m += int(e["mv"])
		if int(e.get("u", -1)) == int(u["id"]) and e.has("mv_set"):
			m = int(e["mv_set"])
	if u["kind"] == "army" and has_ab(u, "flying"):
		var hh := hero_at(int(u["h"]))
		if not hh.is_empty() and hh["t"] == "H015":
			m += 1
	return m


func _eff_has(u: Dictionary, key: String) -> bool:
	for e in effects:
		if int(e.get("u", -1)) == int(u["id"]) and e.get(key, false):
			return true
	return false


## Dadi base di un'unità (senza terreno né carte).
func unit_dice(u: Dictionary) -> Vector2i:
	var d := udata(u)
	return Vector2i(int(d["l"]), int(d["h"]))


func on_map(k: int) -> Array:
	var out: Array = []
	for u in units:
		if owner(u) == k and int(u["h"]) >= 0:
			out.append(u)
	return out


func armies_on_map(k: int) -> Array:
	var out: Array = []
	for u in units:
		if owner(u) == k and int(u["h"]) >= 0 and u["kind"] == "army":
			out.append(u)
	return out


func available(k: int, t: String) -> Array:
	var out: Array = []
	for u in units:
		if int(u["k"]) == k and u["t"] == t and int(u["h"]) == -1 and u["kind"] == "army":
			out.append(u)
	return out


func enemy_army_at(h: int, k: int) -> bool:
	var a := army_at(h)
	return not a.is_empty() and enemies(owner(a), k)


## Esagono assediato per chi lo controlla (10.3): un'armata nemica adiacente (due per un porto,
## tre se c'è Horne); non contano le armate separate da un lato che non possono attraversare.
func besieged(h: int, k: int) -> bool:
	if not is_settlement(h):
		return false
	var need := 2 if is_port(h) else 1
	var hh := hero_at(h)
	if not hh.is_empty() and hh["t"] == "H414":
		need = 3
	var n := 0
	for nb in nbrs(h):
		var a := army_at(nb)
		if a.is_empty() or not enemies(owner(a), k):
			continue
		if sea_side(h, nb) and not has_ab(a, "flying"):
			continue
		n += 1
	return n >= need


# ================================================================== partita

func run() -> void:
	await _setup_game()
	_check_victory_now()
	while not game_over and not abort:
		turn_no += 1
		_distribute_study()
		for k in order.duplicate():
			if game_over or abort:
				break
			if not in_play(k):
				continue
			await _kingdom_turn(k)
			if game_over or abort:
				break
			if advanced:
				await _arcane_study(k)
		if game_over or abort:
			break
		if year == end_year and season == end_season:
			break
		await _advance_season()
	if abort:
		return
	_final_scoring()


func season_text() -> String:
	return "%s dell'anno %d" % [D.season_name(season), year]


func turns_left() -> int:
	var n := 0
	var y := year
	var s := season
	while y < end_year or (y == end_year and s <= end_season):
		n += 1
		s += 1
		if s >= 3:
			s = 0
			y += 1
	return n


func _advance_season() -> void:
	season += 1
	if season == 2 and advanced and not autumn_in:
		study_pool.append("churn")
		autumn_in = true
	if season >= 3:
		if advanced:
			await _winter()
		season = 0
		year += 1
	log_msg("[b]— %s —[/b]" % season_text())
	fx.emit("season", {"year": year, "season": season})
	changed.emit()


# ------------------------------------------------------------------ preparazione della campagna

func _setup_game() -> void:
	phase = "setup"
	log_msg("[b]%s[/b] · %s · %s" % [camp["n"], "gioco avanzato" if advanced else "gioco base", season_text()])
	if advanced:
		_setup_decks()
	changed.emit()
	for k in order:
		cur_k = k
		kd[k]["gold"] = int(camp["gold"].get(k, 0))
		# unità gratuite
		for f in camp["free"]:
			if int(f["k"]) != k:
				continue
			var opts := _free_spots(k, f)
			if opts.is_empty():
				continue
			var h: int = opts[0]
			if opts.size() > 1:
				h = _as_int(await decide(k, {"type": "setup_free", "u": f["u"], "options": opts}))
				if not h in opts:
					h = opts[0]
			var av := available(k, str(f["u"]))
			if av.is_empty():
				continue
			_place(av[0], h, false)
			log_msg("%s schiera %s (gratuita) a %s." % [kn(k), uname(av[0]), hname(h)])
		if k == D.NIGHT:
			for i in range(int(camp.get("covens", 0))):
				var opts2 := coven_targets(true)
				if opts2.is_empty():
					break
				var h2 := _as_int(await decide(k, {"type": "setup_coven", "options": opts2}))
				if not h2 in opts2:
					h2 = opts2[0]
				coven[h2] = true
				log_msg("L'Armata della Notte nasconde una Congrega a %s." % hname(h2))
				changed.emit()
		# costruzioni d'apertura
		phase = "opening"
		await _activation(k, true)
		phase = "setup"
	if advanced:
		for k in order:
			await _opening_hero(k)
		for p in players:
			for i in range(3):
				_draw_spell(p)
			for k in p["ks"]:
				if in_play(int(k)):
					_draw_blessing(p, int(k))
		study_pool.clear()
		var nk := order.size()
		var g := 2 if nk <= 2 else (3 if nk == 3 else 4)
		var c := 1 if nk <= 3 else 2
		for i in range(g):
			study_pool.append("glyph")
		for i in range(c):
			study_pool.append("churn")
		autumn_in = season == 2
		if autumn_in:
			study_pool.append("churn")
	phase = ""
	log_msg("[b]— %s —[/b]" % season_text())
	changed.emit()


func _free_spots(k: int, f: Dictionary) -> Array:
	var out: Array = []
	for at in f["at"]:
		if at == "@entry":
			for h in D.hexes:
				if in_map(h) and entry_owner(h) == k and army_at(h).is_empty() and not is_sea(h):
					out.append(h)
		else:
			var h := D.hex_of(at)
			if h >= 0 and army_at(h).is_empty():
				out.append(h)
	out.sort()
	return out


func _opening_hero(k: int) -> void:
	var arms := armies_on_map(k)
	if arms.is_empty() or kd[k]["hero_pool"].is_empty():
		return
	var opts: Array = []
	for a in arms:
		if hero_at(int(a["h"])).is_empty():
			opts.append(int(a["id"]))
	if opts.is_empty():
		return
	var r := _as_int(await decide(k, {"type": "hero_place", "options": opts}))
	if not r in opts:
		r = opts[0]
	var a2 := unit(r)
	var hu := _take_hero(k)
	if hu.is_empty():
		return
	_place(hu, int(a2["h"]), false)
	log_msg("%s: l'eroe %s si unisce a %s." % [kn(k), uname(hu), uname(a2)])


## Pesca un eroe a caso dalla riserva del regno (pedina coperta).
func _take_hero(k: int, chosen := "") -> Dictionary:
	var pool: Array = kd[k]["hero_pool"]
	if pool.is_empty():
		return {}
	var hid: String = chosen if chosen != "" and chosen in pool else pool[0]
	pool.erase(hid)
	var u := _new_unit(k, "hero", hid)
	kd[k]["hcards"][hid] = {"locked": false}
	return u


func _place(u: Dictionary, h: int, finished: bool) -> void:
	u["h"] = h
	u["fin"] = finished
	u["weak"] = false
	fx.emit("place", {"id": u["id"], "h": h})
	changed.emit()


# ------------------------------------------------------------------ turno di un regno

func _kingdom_turn(k: int) -> void:
	cur_k = k
	made_friendly.clear()
	sea_built.clear()
	effects = effects.filter(func(e): return e.get("dur", "") == "game")
	log_msg("[color=#%s][b]Turno: %s[/b][/color]" % [D.KINGDOMS[k]["light"].to_html(false), kn(k)])
	fx.emit("turn", {"k": k})
	phase = "income"
	changed.emit()
	await _income_actions(k)
	if not in_play(k) or game_over:
		return
	_income_step(k)
	if not in_play(k) or game_over:
		_check_victory_now()
		return
	phase = "activation"
	for u in units:
		if owner(u) == k:
			u["fin"] = false
	for h in monsters:
		if int(monsters[h]["cmd"]) == k:
			monsters[h]["fin"] = false
	for hid in kd[k]["hcards"]:
		kd[k]["hcards"][hid]["locked"] = false
	changed.emit()
	await _activation(k, false)
	if game_over:
		return
	# unità costruite in un ingresso di mare e rimaste lì
	for id in sea_built:
		var u := unit(int(id))
		if not u.is_empty() and int(u["h"]) == int(sea_built[id]):
			log_msg("%s non ha lasciato l'esagono d'ingresso di mare e torna sulla plancia." % uname(u))
			_eliminate(u, "")
	# le unità Enormi non restano negli insediamenti
	for u in units.duplicate():
		if owner(u) == k and int(u["h"]) >= 0 and has_ch(u, "huge") and is_settlement(int(u["h"])) and u["kind"] == "army":
			_huge_in_settlement(u)
	_collapse_checks(k)
	effects = effects.filter(func(e): return e.get("dur", "") == "game")
	_check_victory_now()
	changed.emit()


func _income_actions(k: int) -> void:
	# macchina d'assedio: smontarla per ricostruirla altrove
	for u in on_map(k):
		if u["kind"] == "army" and D.UNITS[u["t"]].get("siege", false):
			var r = await decide(k, {"type": "disband_siege", "id": u["id"], "slow": false})
			if r is bool and r:
				log_msg("%s smonta la Macchina d'Assedio." % kn(k))
				_remove_from_map(u)
	if k == D.NIGHT and markers_left(k) > 0:
		var opts := coven_targets(false)
		if not opts.is_empty():
			var r2 = await decide(k, {"type": "coven", "options": opts})
			if r2 is int and int(r2) in opts:
				await _try_coven(int(r2))
	if k == D.EMPIRE:
		var roll := d6()
		if active_maps.size() == 1 and active_maps.has(3):
			roll += 2
		var row: Dictionary = D.REVOLT_TABLE[clampi(roll, 1, 6) - 1]
		log_msg("Impero, tabella delle rivolte: %d » %s%s." % [roll, row["n"], (" (+%d rivolte)" % row["r"]) if row["r"] > 0 else ""])
		fx.emit("dice", {"k": k, "what": "revolt", "rolls": [roll]})
		for i in range(int(row["r"])):
			_revolt()
			if game_over or not in_play(k):
				return
	if D.KINGDOMS[k]["shashka"]:
		var opts3: Array = []
		for h in ctrl:
			if int(ctrl[h]) == k:
				opts3.append(h)
		if not opts3.is_empty():
			var r3 = await decide(k, {"type": "lay_waste", "options": opts3})
			if r3 is Array:
				for h in r3:
					if int(h) in opts3:
						_lay_waste(k, int(h))
	changed.emit()


func _income_step(k: int) -> void:
	var inc := income(k)
	var gain := inc
	if k == D.NIGHT:
		gain += coven.size()
	kd[k]["gold"] += gain
	log_msg("%s incassa %d oro%s (ora %d)." % [kn(k), gain, (" (%d dalle Congreghe)" % coven.size()) if k == D.NIGHT and coven.size() > 0 else "", kd[k]["gold"]])
	if k == D.EMPIRE:
		var need := int(kd[k]["revolts"])
		if need > 0:
			var paid := mini(need, int(kd[k]["gold"]))
			kd[k]["gold"] -= paid
			log_msg("L'Impero paga %d oro per le rivolte." % paid)
			for i in range(need - paid):
				_revolt()
				if not in_play(k):
					return
	if D.KINGDOMS[k]["shashka"]:
		var n := control_markers(k)
		if n > 0:
			if int(kd[k]["gold"]) >= n:
				kd[k]["gold"] -= n
				log_msg("%s paga %d oro per i segnalini di controllo." % [kn(k), n])
			elif kd[k]["ever_ctrl"]:
				log_msg("%s non può pagare i suoi segnalini di controllo!" % kn(k))
				_collapse(k)
	changed.emit()


func _revolt() -> void:
	var r := int(kd[D.EMPIRE]["revolts"])
	if r >= 19:
		log_msg("[b]Le rivolte travolgono l'Impero![/b]")
		_collapse(D.EMPIRE)
		return
	kd[D.EMPIRE]["revolts"] = r + 1


func suppress_cost() -> int:
	return 1


# ------------------------------------------------------------------ fase di attivazione

func _activation(k: int, opening: bool) -> void:
	var guard := 0
	while not game_over and not abort and in_play(k):
		guard += 1
		if guard > 400:
			break
		var opts := main_options(k, opening)
		var r = await decide(k, {"type": "main", "opening": opening, "options": opts})
		if not (r is Dictionary) or str(r.get("a", "end")) == "end":
			break
		var a: String = r["a"]
		match a:
			"build":
				_do_build(k, str(r["u"]), int(r["h"]), opening)
			"hero":
				_do_build_hero(k, int(r["h"]))
			"act":
				await _activate(k, int(r["h"]), r.get("ids", []))
			"unraze":
				_unraze(k, int(r["h"]))
			"suppress":
				var n := clampi(int(r.get("n", 1)), 1, int(kd[k]["gold"]))
				if n > 0 and kd[k]["revolts"] > 0:
					n = mini(n, int(kd[k]["revolts"]))
					kd[k]["gold"] -= n
					kd[k]["revolts"] -= n
					log_msg("L'Impero reprime %d rivolt%s." % [n, "a" if n == 1 else "e"])
			"gift":
				_gift(k, int(r["to"]), int(r["n"]))
			"regen":
				_regen(k, int(r["id"]))
			"rm_coven":
				coven.erase(int(r["h"]))
				log_msg("L'Armata della Notte ritira la Congrega di %s." % hname(int(r["h"])))
			"monster":
				await _monster_action(k, int(r["h"]), r)
			"card":
				await magic.play(k, r)
			"power":
				await magic.play(k, r)
			"sell":
				magic.sell(k, str(r["c"]))
		changed.emit()
		_check_victory_now()


## Opzioni della fase di attivazione (per l'interfaccia e per l'IA).
func main_options(k: int, opening: bool) -> Dictionary:
	var o := {"builds": {}, "hero": [], "acts": [], "unraze": [], "regen": [], "gift": [], "rm_coven": [], "monsters": [],
		"suppress": 0, "cards": [], "powers": [], "sell": []}
	var gold := int(kd[k]["gold"])
	for t in D.UNIT_ORDER[k]:
		if int(D.UNITS[t]["cost"]) > gold or available(k, t).is_empty():
			continue
		var hs := build_hexes(k, t, opening)
		if not hs.is_empty():
			o["builds"][t] = hs
	if advanced and not kd[k]["hero_pool"].is_empty() and int(D.KINGDOMS[k]["hero_cost"]) <= gold:
		o["hero"] = hero_build_hexes(k, opening)
	if opening:
		return o
	var seen := {}
	for u in units:
		if owner(u) != k or int(u["h"]) < 0 or u["fin"]:
			continue
		var h := int(u["h"])
		if seen.has(h):
			continue
		seen[h] = true
		o["acts"].append(h)
	for u in units:
		if owner(u) != k or int(u["h"]) < 0:
			continue
		var h := int(u["h"])
		if u["kind"] == "army" and razed.has(h) and gold >= 2 and _unraze_ok(k, h) and not h in o["unraze"]:
			o["unraze"].append(h)
		if u["kind"] == "army" and u["weak"] and has_ab(u, "regen") and gold >= int(D.UNITS[u["t"]]["rec"]) and not besieged_in(u):
			o["regen"].append(int(u["id"]))
	if gold >= 2:
		for a in side:
			if a != k and allies(a, k) and in_play(a):
				o["gift"].append(a)
	if k == D.NIGHT:
		o["rm_coven"] = coven.keys()
	if k == D.EMPIRE and int(kd[k]["revolts"]) > 0 and not _no_suppress():
		o["suppress"] = mini(gold, int(kd[k]["revolts"]))
	for h in monsters:
		var m: Dictionary = monsters[h]
		if int(m["cmd"]) == k and not m["def"] and not m["fin"]:
			o["monsters"].append(h)
	if advanced:
		o["cards"] = magic.main_playable(k)
		o["powers"] = magic.main_powers(k)
		o["sell"] = magic.sellable(k)
	return o


func _no_suppress() -> bool:
	for e in effects:
		if e.get("no_suppress", false):
			return true
	return false


func besieged_in(u: Dictionary) -> bool:
	var h := int(u["h"])
	return is_settlement(h) and besieged(h, owner(u))


# ------------------------------------------------------------------ costruire

## Esagoni dove il regno può costruire un'armata del tipo t.
func build_hexes(k: int, t: String, opening := false) -> Array:
	var ud: Dictionary = D.UNITS[t]
	var out: Array = []
	var cand := {}
	for h in D.hexes:
		if not in_map(h):
			continue
		if entry_owner(h) == k:
			cand[h] = true
	var friendly: Array = []
	for h in inplay:
		if controller(h) == k and (opening or not besieged(h, k)) and not made_friendly.has(h) and not is_inert(h):
			friendly.append(h)
	if khazud >= 0 and controller(khazud) == k and (opening or not besieged(khazud, k)):
		friendly.append(khazud)
	for h in friendly:
		cand[h] = true
		for n in nbrs(h):
			if sea_side(h, n) and not "flying" in ud["ab"]:
				continue
			cand[n] = true
	if k == D.NIGHT and "feral" in ud["ch"]:
		for h in coven:
			for n in nbrs(h):
				if is_wild(n) and not is_settlement(n):
					cand[n] = true
	for h in cand:
		if not _build_ok(k, h, ud):
			continue
		out.append(h)
	out.sort()
	return out


func _build_ok(k: int, h: int, ud: Dictionary) -> bool:
	if not in_map(h) or not army_at(h).is_empty():
		return false
	if is_lair(h) or monsters.has(h):
		return false
	if is_sea(h) and entry_owner(h) != k:
		return false
	var eo := entry_owner(h)
	if eo >= 0 and eo != k:
		return false
	var p := posture(h, k)
	if p in ["hostile", "inert", "welcome", "ally"]:
		return false
	if "huge" in ud["ch"] and is_settlement(h):
		return false
	if hero_at(h).size() > 0 and enemies(owner(hero_at(h)), k):
		return false
	# nessun nemico dell'Armata della Notte costruisce accanto alla Spira (12.3.6)
	if k != D.NIGHT:
		var sp := D.hex_of("Spire of the Moon")
		if sp >= 0 and in_map(sp) and enemies(k, D.NIGHT) and in_play(D.NIGHT) and D.dist(h, sp) == 1:
			return false
	return true


func hero_build_hexes(k: int, opening := false) -> Array:
	var out: Array = []
	var cand := {}
	for h in D.hexes:
		if in_map(h) and entry_owner(h) == k:
			cand[h] = true
	for h in inplay:
		if controller(h) == k and (opening or not besieged(h, k) or _horne_build(k)):
			cand[h] = true
			for n in nbrs(h):
				cand[n] = true
	for h in cand:
		if not in_map(h) or is_sea(h) or is_lair(h) or monsters.has(h):
			continue
		if not hero_at(h).is_empty():
			continue
		var a := army_at(h)
		if not a.is_empty() and owner(a) != k:
			continue
		var p := posture(h, k)
		if p in ["hostile", "inert", "ally", "welcome"]:
			continue
		var eo := entry_owner(h)
		if eo >= 0 and eo != k:
			continue
		out.append(h)
	out.sort()
	return out


func _horne_build(_k: int) -> bool:
	return false


func _do_build(k: int, t: String, h: int, opening: bool) -> void:
	var ud: Dictionary = D.UNITS[t]
	var av := available(k, t)
	if av.is_empty() or int(ud["cost"]) > int(kd[k]["gold"]) or not h in build_hexes(k, t, opening):
		return
	kd[k]["gold"] -= int(ud["cost"])
	var u: Dictionary = av[0]
	var ready := entry_owner(h) == k or is_settlement(h)
	if k == D.NIGHT and "feral" in ud["ch"] and not ready:
		ready = false
	_place(u, h, not ready)
	var hh := hero_at(h)
	if not hh.is_empty() and hh["fin"]:
		u["fin"] = true
	if is_sea(h):
		sea_built[u["id"]] = h
	log_msg("%s costruisce %s a %s (%d oro)%s." % [kn(k), uname(u), hname(h), int(ud["cost"]), "" if ready else ", esaurita"])
	fx.emit("build", {"id": u["id"], "h": h})


func _do_build_hero(k: int, h: int) -> void:
	var cost := int(D.KINGDOMS[k]["hero_cost"])
	if cost > int(kd[k]["gold"]) or not h in hero_build_hexes(k, phase == "opening"):
		return
	var u := _take_hero(k)
	if u.is_empty():
		return
	kd[k]["gold"] -= cost
	var ready := entry_owner(h) == k or is_settlement(h)
	var a := army_at(h)
	if not a.is_empty() and a["fin"]:
		ready = false
	_place(u, h, not ready)
	log_msg("%s recluta l'eroe %s a %s (%d oro)." % [kn(k), uname(u), hname(h), cost])
	fx.emit("build", {"id": u["id"], "h": h})


func _unraze_ok(k: int, h: int) -> bool:
	if not razed.has(h) or not (inplay.has(h) or h == khazud):
		return false
	if army_at(h).is_empty() or owner(army_at(h)) != k:
		return false
	# deve diventare accogliente una volta tolto il segnalino
	razed.erase(h)
	var ok := welcoming(h, k)
	razed[h] = true
	return ok


func _unraze(k: int, h: int) -> void:
	if not _unraze_ok(k, h) or int(kd[k]["gold"]) < 2:
		return
	kd[k]["gold"] -= 2
	razed.erase(h)
	log_msg("%s ricostruisce %s (2 oro)." % [kn(k), hname(h)])
	fx.emit("unraze", {"h": h})
	# se è un insediamento neutrale accogliente si può subito porre il segnalino
	var a := army_at(h)
	if not a.is_empty() and posture(h, k) == "welcome" and markers_left(k) > 0 and not feral_limited(units_at(h)):
		ctrl[h] = k
		made_friendly[h] = true
		_ever(k)
		log_msg("%s pone un segnalino di controllo a %s." % [kn(k), hname(h)])
	_check_covens()


func _gift(k: int, to: int, n: int) -> void:
	n = clampi(n, 1, int(kd[k]["gold"]) / 2)
	if n <= 0 or not allies(k, to):
		return
	kd[k]["gold"] -= n * 2
	kd[to]["gold"] += n
	log_msg("%s trasferisce %d oro a %s (spende %d)." % [kn(k), n, kn(to), n * 2])


func _regen(k: int, id: int) -> void:
	var u := unit(id)
	if u.is_empty() or owner(u) != k or not u["weak"] or not has_ab(u, "regen") or besieged_in(u):
		return
	var c := int(D.UNITS[u["t"]]["rec"])
	if c > int(kd[k]["gold"]):
		return
	kd[k]["gold"] -= c
	u["weak"] = false
	log_msg("%s si rigenera (%d oro)." % [uname(u), c])
	fx.emit("recover", {"id": id})


func hname(h: int) -> String:
	var s := sdata(h)
	if not s.is_empty():
		return s["n"]
	var e: Dictionary = D.hexes.get(h, {})
	if e.is_empty():
		return "?"
	if str(e["lair_n"]) != "":
		return str(e["lair_n"])
	if str(e["mine"]) != "":
		return str(e["mine"])
	if str(e["name"]) != "":
		return "%s (%d.%02d)" % [e["name"], D.col(h), D.row(h)]
	return "%s %d.%02d" % [D.TERRAIN_NAMES[e["t"]].to_lower(), D.col(h), D.row(h)]


# ================================================================== attivazione di una pila

## Attiva una pila (armata e/o eroe) in h: movimento (via terra; per Fjordland anche via mare come
## azione gratuita) e poi un'azione. ids vuoto = tutte le unità pronte del regno nell'esagono.
func _activate(k: int, h: int, ids: Array) -> void:
	var us: Array = []
	for u in units_at(h):
		if owner(u) == k and not u["fin"] and (ids.is_empty() or int(u["id"]) in ids):
			us.append(u)
	if us.is_empty():
		return
	var id_list: Array = []
	for u in us:
		id_list.append(int(u["id"]))
	act = {"k": k, "h": h, "ids": id_list, "ship_used": false, "mp_used": 0, "road": true, "moved": false, "start": h}
	fx.emit("activate", {"h": h, "ids": id_list})
	changed.emit()
	var fjord_free := k == D.FJORD
	var guard := 0
	# movimento
	while not game_over and guard < 20:
		guard += 1
		us = act_units()
		if us.is_empty():
			break
		var reach := land_reach(k, us, int(act["h"]), int(act["mp_used"]), bool(act["road"]))
		var ship_ok := false
		if (fjord_free or magic.free_ship(us)) and not act["ship_used"] and can_ship(us):
			ship_ok = not ship_reach(k, us, int(act["h"])).is_empty()
		var opts := {"reach": _reach_costs(reach), "ship": ship_ok, "mp": stack_mv(us) - int(act["mp_used"])}
		if reach.is_empty() and not ship_ok:
			break
		var r = await decide(k, {"type": "move", "h": act["h"], "ids": act["ids"], "options": opts})
		if r is Dictionary and r.get("ship", false) and ship_ok:
			await _ship_move(k, us)
			act["ship_used"] = true
			if not fjord_free:
				pass
			continue
		var to := int(r.get("to", -1)) if r is Dictionary else -1
		if to < 0 or not reach.has(to):
			break
		var path: Array = reach[to]["path"]
		act["mp_used"] = int(reach[to]["c"])
		act["road"] = bool(reach[to]["road"])
		act["moved"] = true
		await _move_along(k, us, path, false)
		if not fjord_free:
			break
	await _after_move(k)
	# azione
	us = act_units()
	if not us.is_empty() and not game_over:
		await _action(k, us)
	_end_activation(k)


func act_units() -> Array:
	var out: Array = []
	for id in act.get("ids", []):
		var u := unit(int(id))
		if not u.is_empty() and int(u["h"]) >= 0 and owner(u) == int(act["k"]):
			out.append(u)
	return out


func stack_mv(us: Array) -> int:
	var m := 99
	for u in us:
		m = mini(m, base_mv(u))
	return 0 if m == 99 else m


func can_ship(us: Array) -> bool:
	for u in us:
		if u["kind"] == "army" and has_ch(u, "huge") and not magic.free_ship(us):
			return false
	if feral_limited(us) and not magic.free_ship(us):
		return false
	return true


func _reach_costs(reach: Dictionary) -> Dictionary:
	var out := {}
	for h in reach:
		out[h] = int(reach[h]["c"])
	return out


## Possibilità di entrare in un esagono: 0 vietato, 1 solo di passaggio, 2 ci si può fermare.
func enter_kind(k: int, us: Array, h: int, flying: bool, ship := false) -> int:
	if not in_map(h):
		return 0
	if is_lair(h) or monsters.has(h):
		return 0 if not magic.ignore_block(us) else 1
	var has_army := false
	var has_hero := false
	for u in us:
		if u["kind"] == "army":
			has_army = true
		else:
			has_hero = true
	var res := 2
	if is_sea(h):
		if ship or flying:
			res = 1
		else:
			return 0
	var a := army_at(h)
	var blockers_fly := false
	for u in units_at(h):
		if enemies(owner(u), k) and (has_ab(u, "flying") or has_ab(u, "ranged")):
			blockers_fly = true
	if not a.is_empty():
		if enemies(owner(a), k):
			if magic.ignore_block(us) or magic.pass_enemies(us):
				res = mini(res, 1)
			elif flying and not blockers_fly and not ship:
				res = mini(res, 1)
			else:
				return 0
		elif has_army:
			res = mini(res, 1)
		elif owner(a) != k:
			res = mini(res, 1)
	var p := posture(h, k)
	if p == "hostile" or p == "inert":
		if magic.ignore_block(us):
			res = mini(res, 1)
		elif flying and not blockers_fly and not ship:
			res = mini(res, 1)
		else:
			return 0
	var hh := hero_at(h)
	if not hh.is_empty():
		if owner(hh) == k or allies(owner(hh), k):
			if has_hero or owner(hh) != k:
				res = mini(res, 1)
		elif a.is_empty():
			# eroe nemico solitario: un'armata lo elimina entrando, un eroe può solo passare
			if not has_army:
				res = mini(res, 1)
	var eo := entry_owner(h)
	if eo >= 0 and eo != k:
		res = mini(res, 1)
	if huge_in(us) and is_settlement(h) and has_army:
		res = mini(res, 1)
	return res


func _mountaineer(u: Dictionary) -> bool:
	var k := int(u["k"])
	if not (k == D.OATH or k == D.GOBLIN):
		return false
	return not (u["kind"] == "army" and D.UNITS[u["t"]].get("siege", false))


## Costo per entrare in h da a (via terra), −1 se il lato è vietato. road: il lato ha strada o ponte.
func step_cost(us: Array, a: int, h: int, flying: bool) -> Vector2i:
	if flying:
		return Vector2i(1, 0)
	var e := edge(a, h)
	if e.get("sea", false):
		return Vector2i(-1, 0)
	if e.get("road", false):
		return Vector2i(1, 1)
	if magic.ignore_terrain(us):
		return Vector2i(1, 0)
	var c := 1
	if not is_settlement(h):
		var t := terrain(h)
		if t in ["f", "m", "s"]:
			c = 2
			if t == "m":
				var all_m := true
				for u in us:
					if not _mountaineer(u):
						all_m = false
				if all_m:
					c = 1
			if t == "f":
				for u in us:
					if u["kind"] == "army" and D.UNITS[u["t"]].get("ranger", false):
						c = 1
	c += int(e.get("r", 0))
	return Vector2i(c, 0)


## Esagoni raggiungibili via terra: {esagono: {"c": costo, "p": precedente, "road": tutto su strada}}.
## Solo esagoni dove la pila può fermarsi.
func land_reach(k: int, us: Array, from: int, used: int, road_so_far: bool) -> Dictionary:
	var was_frozen: bool = _occ != null
	if not was_frozen:
		freeze_occ()
	var res := _land_reach(k, us, from, used, road_so_far)
	if not was_frozen:
		thaw_occ()
	return res


func _land_reach(k: int, us: Array, from: int, used: int, road_so_far: bool) -> Dictionary:
	var flying := stack_has(us, "flying")
	var mv := stack_mv(us)
	var best := {}       # stato (h*2+road) -> costo
	var parent := {}
	var start := from * 2 + (1 if road_so_far else 0)
	best[start] = used
	var out := {}
	# coda a secchi: i costi sono piccoli interi
	var buckets := {used: [start]}
	var cur := used
	var maxc := used + 40
	while cur <= maxc:
		if not buckets.has(cur) or buckets[cur].is_empty():
			cur += 1
			continue
		var st: int = buckets[cur].pop_back()
		if int(best.get(st, 999)) < cur:
			continue
		var h := st / 2
		var road := st % 2 == 1
		var c := int(best[st])
		for n in nbrs(h):
			var sc := step_cost(us, h, n, flying)
			if sc.x < 0:
				continue
			var kind := enter_kind(k, us, n, flying)
			if kind == 0:
				continue
			var nroad := road and sc.y == 1 and not flying
			var nc := c + sc.x
			var budget := mv + (1 if nroad else 0)
			if nc > budget:
				# minimo un esagono: sempre possibile se non ci si è ancora mossi
				if not (used == 0 and h == from and kind == 2):
					continue
			var ns: int = n * 2 + (1 if nroad else 0)
			if best.has(ns) and int(best[ns]) <= nc:
				continue
			best[ns] = nc
			parent[ns] = st
			if nc <= budget:
				if not buckets.has(nc):
					buckets[nc] = []
				buckets[nc].append(ns)
			if kind == 2 and n != from:
				if not out.has(n) or int(out[n]["c"]) > nc:
					out[n] = {"c": nc, "ps": ns, "road": nroad}
	# percorsi
	for n in out:
		var chain: Array = []
		var s: int = out[n]["ps"]
		var g := 0
		while parent.has(s) and g < 60:
			g += 1
			chain.push_front(s / 2)
			s = parent[s]
		out[n]["path"] = chain
		out[n]["p"] = chain[chain.size() - 2] if chain.size() >= 2 else from
	return out


## Movimento navale: {esagono: {"c","path"}} con i soli esagoni dove ci si può fermare.
func ship_reach(k: int, us: Array, from: int) -> Dictionary:
	var was_frozen: bool = _occ != null
	if not was_frozen:
		freeze_occ()
	var res := _ship_reach(k, us, from)
	if not was_frozen:
		thaw_occ()
	return res


func _ship_reach(k: int, us: Array, from: int) -> Dictionary:
	var rating := 3
	var eo := entry_owner(from)
	if (is_port(from) and (controller(from) == k or allies(controller(from), k))) or eo == k:
		rating = 6
	if k == D.FJORD:
		rating += 2
	var best := {from: 0}
	var parent := {}
	var open: Array = [from]
	var stop := {}           # esagoni raggiunti attraversando un fiume (il movimento finisce lì)
	var out := {}
	while not open.is_empty():
		var bi := 0
		for i in range(1, open.size()):
			if int(best[open[i]]) < int(best[open[bi]]):
				bi = i
		var h: int = open[bi]
		open.remove_at(bi)
		var c := int(best[h])
		if c >= rating or stop.has(h):
			continue
		for n in nbrs(h):
			var e := edge(h, n)
			var water := bool(e.get("sea", false)) or (is_wet(h) and is_wet(n) and int(e.get("w", 0)) >= 20)
			var river := int(e.get("r", 0)) > 0
			if not water and not river:
				continue
			var kind := enter_kind(k, us, n, false, true)
			if kind == 0:
				continue
			var crosses_river := river and not water
			if not crosses_river and not is_wet(n):
				continue
			var nc := c + 1
			if best.has(n) and int(best[n]) <= nc:
				continue
			best[n] = nc
			parent[n] = h
			if crosses_river:
				stop[n] = true
			else:
				open.append(n)
			var can_end := kind == 2 and not is_sea(n) and (crosses_river or is_coastal(n) or bool(D.hexes[n]["mr"]))
			if can_end and n != from:
				out[n] = {"c": nc}
	for n in out:
		var chain: Array = [n]
		var s = n
		var g := 0
		while parent.has(s) and g < 40:
			g += 1
			s = parent[s]
			chain.push_front(s)
		chain.pop_front()
		out[n]["path"] = chain
		out[n]["p"] = parent.get(n, from)
	return out


func _ship_move(k: int, us: Array) -> void:
	var reach := ship_reach(k, us, int(act["h"]))
	if reach.is_empty():
		return
	var r = await decide(k, {"type": "ship_move", "h": act["h"], "ids": act["ids"], "options": _reach_costs(reach)})
	var to := int(r) if (r is int or r is float) else -1
	if not reach.has(to):
		return
	act["ship_used"] = true
	act["moved"] = true
	log_msg("%s salpa via mare verso %s." % [_stack_name(us), hname(to)])
	await _move_along(k, us, reach[to]["path"], true)


func _stack_name(us: Array) -> String:
	var names: Array = []
	for u in us:
		names.append(uname(u))
	return " e ".join(names)


## Muove la pila lungo il percorso (esagoni dopo quello di partenza).
func _move_along(k: int, us: Array, path: Array, ship: bool) -> void:
	var prev := int(act["h"])
	for h in path:
		if game_over:
			return
		# Furia di Moryana: chi attraversa un lato di mare via nave può essere colpito
		if ship and sea_side(prev, int(h)) and advanced:
			await magic.window("sea_cross", {"k": k, "h": prev, "to": int(h), "ids": act["ids"]})
			us = act_units()
			if us.is_empty():
				return
		for u in us:
			u["h"] = int(h)
		act["h"] = int(h)
		# un'armata che entra nell'esagono di un eroe nemico solitario lo elimina
		var has_army := false
		for u in us:
			if u["kind"] == "army":
				has_army = true
		var hh := hero_at(int(h))
		if has_army and not hh.is_empty() and enemies(owner(hh), k):
			log_msg("%s viene sorpreso da solo e cade." % uname(hh))
			await _kill(hh, "da solo")
		fx.emit("move", {"ids": act["ids"], "from": prev, "to": int(h), "ship": ship})
		prev = int(h)
	changed.emit()


## Fine del movimento: Terra in Fango, scoperta delle Congreghe.
func _after_move(k: int) -> void:
	var h := int(act["h"])
	if act.get("moved", false) and advanced:
		await magic.window("moved", {"k": k, "h": h, "ids": act["ids"]})
	var a := army_at(h)
	if coven.has(h) and not a.is_empty() and enemies(owner(a), D.NIGHT) and in_play(D.NIGHT):
		await _coven_hide(h)


func _action(k: int, us: Array) -> void:
	var h := int(act["h"])
	var opts := action_options(k, us, h)
	if opts["attack"].is_empty() and not opts["ship"] and not opts["recover"] and not opts["mine"]:
		return
	var r = await decide(k, {"type": "action", "h": h, "ids": act["ids"], "options": opts})
	var a := str(r.get("a", "pass")) if r is Dictionary else "pass"
	match a:
		"attack":
			var t := int(r.get("t", -1))
			if t in opts["attack"]:
				await attack(k, us, h, t)
		"ship":
			if opts["ship"]:
				await _ship_move(k, us)
		"recover":
			if opts["recover"]:
				for u in us:
					if u["kind"] == "army" and u["weak"]:
						var c := int(D.UNITS[u["t"]]["rec"])
						kd[k]["gold"] -= c
						u["weak"] = false
						log_msg("%s recupera la piena forza (%d oro)." % [uname(u), c])
						fx.emit("recover", {"id": u["id"]})
		"mine":
			if opts["mine"]:
				kd[k]["gold"] += 1
				log_msg("I Minatori lavorano la miniera di %s (+1 oro)." % hname(h))
				fx.emit("mine", {"h": h})
				if advanced:
					await magic.window("mined", {"k": k, "h": h, "ids": act["ids"]})


func action_options(k: int, us: Array, h: int) -> Dictionary:
	var o := {"attack": attack_targets(k, us, h), "ship": false, "recover": false, "mine": false}
	if not act.get("ship_used", false) and k != D.FJORD and can_ship(us):
		o["ship"] = not ship_reach(k, us, h).is_empty()
	for u in us:
		if u["kind"] != "army":
			continue
		if u["weak"] and int(D.UNITS[u["t"]]["rec"]) >= 0 and int(D.UNITS[u["t"]]["rec"]) <= int(kd[k]["gold"]) and recover_spot(k, u, h):
			o["recover"] = true
		if D.UNITS[u["t"]].get("miner", false) and is_mine(h) and in_map(h):
			o["mine"] = true
	return o


## Luogo dove un'armata indebolita può recuperare: ingresso amico, oppure in o accanto a un
## insediamento accogliente non assediato (o, per le armate ferine della Notte, accanto a una Congrega).
func recover_spot(k: int, u: Dictionary, h: int) -> bool:
	if entry_owner(h) == k:
		return true
	var cand: Array = [h]
	cand.append_array(nbrs(h))
	for s in cand:
		if is_settlement(s) and welcoming(s, k) and not besieged(s, controller(s) if controller(s) >= 0 else k):
			return true
		if is_settlement(s) and controller(s) == k and magic.secret_ways(k):
			return true
	if k == D.NIGHT and has_ch(u, "feral") and is_wild(h):
		for n in nbrs(h):
			if coven.has(n):
				return true
	return false


## Bersagli d'attacco adiacenti.
func attack_targets(k: int, us: Array, h: int) -> Array:
	var out: Array = []
	var army := {}
	for u in us:
		if u["kind"] == "army":
			army = u
	if army.is_empty():
		return out
	var siege_only := true
	for u in us:
		if not (u["kind"] == "army" and D.UNITS[u["t"]].get("siege", false)):
			siege_only = false
	var flying := stack_has(us, "flying")
	for n in nbrs(h):
		var sea := sea_side(h, n)
		if monsters.has(n):
			var m: Dictionary = monsters[n]
			if m["def"] or not enemies(int(m["cmd"]), k):
				continue
			if sea and not flying and not D.monster(m["m"]).get("sea", false):
				continue
			if not siege_only:
				out.append(n)
			continue
		if advanced and is_lair(n) and not abandoned.has(n):
			if sea and not flying and D.hexes[n]["lair"] != "S":
				continue
			if not siege_only:
				out.append(n)
			continue
		if sea and not flying:
			continue
		var a := army_at(n)
		if not a.is_empty() and enemies(owner(a), k):
			if siege_only and not is_settlement(n):
				continue
			out.append(n)
			continue
		if a.is_empty() and posture(n, k) == "hostile":
			out.append(n)
	return out


func _end_activation(k: int) -> void:
	for id in act.get("ids", []):
		var u := unit(int(id))
		if not u.is_empty():
			u["fin"] = true
	var h := int(act.get("h", -1))
	if h >= 0:
		await _settle(k, h)
	var ids: Array = act.get("ids", [])
	effects = effects.filter(func(e): return e.get("dur", "") != "act" and not (e.get("dur", "") == "next" and int(e.get("u", -1)) in ids))
	act = {}
	changed.emit()


## Fine dell'attivazione in un insediamento neutrale accogliente: si può porre il segnalino di controllo.
func _settle(k: int, h: int) -> void:
	var a := army_at(h)
	if a.is_empty() or owner(a) != k or not is_settlement(h):
		return
	if posture(h, k) != "welcome":
		return
	if markers_left(k) <= 0 or feral_limited(units_at(h)) or huge_in(units_at(h)):
		return
	var r = await decide(k, {"type": "place_ctrl", "h": h, "slow": false})
	if r is bool and r:
		ctrl[h] = k
		made_friendly[h] = true
		_ever(k)
		log_msg("%s pone un segnalino di controllo a %s." % [kn(k), hname(h)])
		fx.emit("ctrl", {"h": h, "k": k})
		_check_covens()


func _ever(k: int) -> void:
	kd[k]["ever_ctrl"] = true


# ================================================================== combattimento

## Attacco della pila us (in h) contro l'esagono adiacente t.
func attack(k: int, us: Array, h: int, t: int) -> void:
	var ids: Array = []
	for u in us:
		ids.append(int(u["id"]))
	cb = {"k": k, "a": ids, "from": h, "t": t, "type": "", "dk": -1, "mods": {"a": {}, "d": {}}, "canceled": false,
		"hits_a": 0, "hits_d": 0, "garrison_down": false, "mon_down": false, "amb": -1, "log": []}
	if monsters.has(t):
		cb["type"] = "mon"
		cb["dk"] = int(monsters[t]["cmd"])
	elif advanced and is_lair(t):
		if not await _lair_monster(t, k):
			cb = {}
			return
		cb["type"] = "mon"
		cb["dk"] = int(monsters[t]["cmd"])
	else:
		var a := army_at(t)
		cb["type"] = "set" if is_settlement(t) else "army"
		if not a.is_empty():
			cb["dk"] = owner(a)
		else:
			var c := controller(t)
			cb["dk"] = c if c >= 0 else loyal(t)
	var tname := _target_name(t)
	log_msg("%s attacca %s." % [_stack_name(us), tname])
	fx.emit("combat", {"from": h, "t": t, "k": k})
	changed.emit()
	if advanced:
		await magic.battle_magic()
	if cb.is_empty() or cb["canceled"]:
		log_msg("Il combattimento è annullato.")
		cb = {}
		return
	# dichiarazione d'imboscata (9.6)
	var a_st := _side_stealth("a")
	var d_st := _side_stealth("d")
	var amb := -1
	if a_st and not d_st and not (cb["type"] == "set" and fort(t) > 0):
		var r = await decide(k, {"type": "ambush", "role": "atk", "t": t, "slow": false})
		if r is bool and r:
			amb = 0
	if amb < 0 and d_st and not a_st:
		var dk := _def_controller()
		if dk >= 0 and side.has(dk):
			var r2 = await decide(dk, {"type": "ambush", "role": "def", "t": t, "from": h, "slow": false})
			if r2 is bool and r2:
				amb = 1
		elif dk == -2:
			amb = 1
	cb["amb"] = amb
	if amb >= 0:
		await _ambush(amb == 0)
	else:
		await _battle()
	var won := int(cb.get("won", -1))
	if advanced:
		await magic.after_combat()
		if won >= 0:
			await magic.window("won", {"role": "a" if won == 0 else "d"})
	var again := ""
	if advanced and won == 0 and cb.get("fury", false):
		again = "fury"
	var sofia := false
	for u in side_units("a"):
		if u["t"] == "H113":
			sofia = true
	var haga := false
	if advanced and won == 1:
		for u in side_units("d"):
			if u["t"] == "H411":
				haga = true
	var dpos := int(cb["t"])
	await _after_combat()
	var adv_done := false
	for u in side_units("a"):
		if int(u["h"]) == t:
			adv_done = true
	cb = {}
	changed.emit()
	if game_over or act.get("again", false):
		return
	if advanced and sofia and adv_done and again == "":
		again = "sofia"
	if again != "":
		act["again"] = true
		var us2 := act_units()
		var tg := attack_targets(k, us2, int(us2[0]["h"])) if not us2.is_empty() else []
		if not tg.is_empty():
			var r3 = await decide(k, {"type": "action", "h": us2[0]["h"], "ids": act["ids"], "options": {"attack": tg, "ship": false, "recover": false, "mine": false}, "again": again})
			if r3 is Dictionary and str(r3.get("a", "")) == "attack" and int(r3.get("t", -1)) in tg:
				if again == "fury":
					for u in us2:
						if u["kind"] == "army":
							effects.append({"dur": "act", "u": int(u["id"]), "dice_h": 1})
				await attack(k, us2, int(us2[0]["h"]), int(r3["t"]))
	elif haga:
		var dh: Dictionary = {}
		for u in units_at(dpos):
			if u["t"] == "H411":
				dh = u
		var att: Array = []
		for u in units_at(h):
			if owner(u) == k:
				att.append(u)
		if not dh.is_empty() and not att.is_empty():
			var dk := owner(dh)
			var mine: Array = units_at(dpos).filter(func(x): return owner(x) == dk)
			var r4 = await decide(dk, {"type": "counter", "t": h, "slow": false})
			if r4 is bool and r4:
				var saved_act := act
				act = {"k": dk, "h": dpos, "ids": mine.map(func(x): return int(x["id"])), "again": true}
				await attack(dk, mine, dpos, h)
				act = saved_act


func _target_name(t: int) -> String:
	if monsters.has(t):
		return "%s (%s)" % [D.monster(monsters[t]["m"])["n"], hname(t)]
	var a := army_at(t)
	if not a.is_empty():
		return "%s di %s a %s" % [uname(a), kn(owner(a)), hname(t)]
	return "la guarnigione di %s" % hname(t)


## Regno che decide per il difensore (−2 = mostro senza padrone umano, decide l'IA del comandante).
func _def_controller() -> int:
	if cb["type"] == "mon":
		var c := int(monsters[int(cb["t"])]["cmd"])
		return c if c >= 0 else -2
	var a := army_at(int(cb["t"]))
	if not a.is_empty():
		return owner(a)
	var hh := hero_at(int(cb["t"]))
	if not hh.is_empty():
		return owner(hh)
	return -1


func side_units(role: String) -> Array:
	if not cb.has("t") or not cb.has("from"):
		return []
	if role == "a":
		var out: Array = []
		for id in cb.get("a", []):
			var u := unit(int(id))
			if not u.is_empty() and int(u["h"]) == int(cb["from"]):
				out.append(u)
		return out
	var out2: Array = []
	if cb.get("type", "") == "mon":
		return out2
	for u in units_at(int(cb["t"])):
		if enemies(owner(u), int(cb["k"])):
			out2.append(u)
	return out2


func _side_stealth(role: String) -> bool:
	if cb["mods"][role].get("stealth", false):
		return true
	if role == "d" and cb["type"] == "mon":
		return "stealth" in D.monster(monsters[int(cb["t"])]["m"])["ab"]
	return stack_has(side_units(role), "stealth")


func _side_ranged(role: String) -> bool:
	if cb["mods"][role].get("ranged", false):
		return true
	if role == "d" and cb["type"] == "mon":
		return "ranged" in D.monster(monsters[int(cb["t"])]["m"])["ab"]
	return stack_has(side_units(role), "ranged")


## Dadi di un lato del combattimento: Vector2i(leggeri, pesanti). strike: senza terreno né guarnigione.
func combat_dice(role: String, strike := false) -> Vector2i:
	var t := int(cb["t"])
	var l := 0
	var hv := 0
	var us := side_units(role)
	if role == "d" and cb["type"] == "mon":
		var m := D.monster(monsters[t]["m"])
		l = int(m["l"])
		hv = int(m["h"])
	else:
		for u in us:
			if u["kind"] == "army" and D.UNITS[u["t"]].get("siege", false):
				if role == "a" and not (is_settlement(t) and cb["type"] == "set"):
					continue
			var dd := unit_dice(u)
			l += dd.x
			hv += dd.y
			var od: Vector2i = magic.ongoing_dice(u, role)
			l += od.x
			hv += od.y
	var t_forest := is_forest(t)
	if role == "a" and t_forest:
		for u in us:
			if u["kind"] == "army" and D.UNITS[u["t"]].get("ranger", false):
				l += 1
	if role == "d" and t_forest:
		for u in us:
			if u["kind"] == "army" and D.UNITS[u["t"]].get("ranger", false):
				l += 1
	if role == "a" and int(cb["k"]) == D.NIGHT and coven.has(t):
		l += 1
	if role == "d" and not strike and cb["type"] != "mon":
		if is_wild(t):
			l += 1
		var e := edge(int(cb["from"]), t)
		if int(e.get("r", 0)) > 0 and not stack_has(side_units("a"), "flying"):
			l += int(e["r"])
		if is_settlement(t):
			if city(t):
				l += 3
			elif army_at(t).is_empty():
				l += 1
		l += int(cb["mods"]["d"].get("garr", 0))
	var md: Dictionary = cb["mods"][role]
	l += int(md.get("l", 0))
	hv += int(md.get("h", 0))
	if md.get("x2l", false):
		l *= 2
	var conv := mini(int(md.get("conv", 0)), l)
	l -= conv
	hv += conv
	l = maxi(0, l - int(md.get("minus_l", 0)))
	hv = maxi(0, hv - int(md.get("minus_h", 0)))
	return Vector2i(l, hv)


## Modificatore ai tiri dell'attaccante contro una fortificazione (4.4, 9.11).
func fort_mod() -> int:
	var t := int(cb["t"])
	if cb["type"] != "set" or not is_settlement(t):
		return 0
	var f := fort(t)
	if f <= 0:
		return 0
	var n := 0
	for nb in nbrs(t):
		var a := army_at(nb)
		if not a.is_empty() and D.UNITS[a["t"]].get("siege", false) and (owner(a) == int(cb["k"]) or allies(owner(a), int(cb["k"]))):
			n += 1
		var hh := hero_at(nb)
		if not hh.is_empty() and hh["t"] == "H313" and _eff_has(hh, "siege") and owner(hh) == int(cb["k"]):
			n += 1
	return mini(0, -f + n)


## Tira i dadi: successi su 5+ (con il modificatore), critici sui d8 da 7 in su, confermati con 1d6 (5+).
func roll(dice: Vector2i, mod: int, role: String) -> Dictionary:
	var md: Dictionary = cb.get("mods", {}).get(role, {}) if not cb.is_empty() else {}
	var crit_th := 6 if md.get("crit6", false) else 7
	var rolls: Array = []
	var s := 0
	var crits := 0
	var golem := int(md.get("golem", 0))
	for i in range(dice.x):
		var v := d6()
		var ok := v + mod >= 5
		rolls.append({"d": 6, "v": v, "ok": ok})
		if ok:
			s += 1
	for i in range(dice.y):
		var v := d8()
		var m := mod
		if golem > 0:
			golem -= 1
			m = 0
		var c := v >= crit_th
		var ok := c or v + m >= 5
		rolls.append({"d": 8, "v": v, "ok": ok, "crit": c})
		if c:
			crits += 1
		if ok:
			s += 1
	if md.get("darts", false):
		crits = s
	if md.get("reroll", false):
		var again := 0
		for rr in rolls:
			if not rr["ok"]:
				again += 1
		for rr in rolls:
			if not rr["ok"]:
				var v2 := d6() if rr["d"] == 6 else d8()
				rr["v"] = v2
				rr["ok"] = v2 + mod >= 5 or (rr["d"] == 8 and v2 >= crit_th)
				if rr["ok"]:
					s += 1
					if rr["d"] == 8 and v2 >= crit_th:
						crits += 1
	var conf: Array = []
	var extra := 0
	for i in range(crits):
		if md.get("diamond", false):
			var v := d8()
			conf.append(v)
			if v >= 5:
				extra += 1
			if v >= 7:
				crits += 1
				if crits > 30:
					break
		elif md.get("fester", false) and i == 0:
			for j in range(3):
				var v := d6()
				conf.append(v)
				if v >= 5:
					extra += 1
		else:
			var v := d6()
			conf.append(v)
			if v >= 5:
				extra += 1
	return {"s": s, "crit": crits, "extra": extra, "rolls": rolls, "conf": conf, "mod": mod}


func _battle() -> void:
	var t := int(cb["t"])
	var da := combat_dice("a")
	var dd := combat_dice("d")
	var ra := roll(da, fort_mod() + int(cb["mods"]["a"].get("rmod", 0)), "a")
	var rd := roll(dd, int(cb["mods"]["d"].get("rmod", 0)), "d")
	cb["ra"] = ra
	cb["rd"] = rd
	if advanced:
		await magic.window("rolled", {"k": cb["k"]})
		ra = cb["ra"]
		rd = cb["rd"]
	var sa := int(ra["s"]) + int(ra["extra"]) + int(cb["mods"]["a"].get("succ", 0)) - int(cb["mods"]["a"].get("nsucc", 0))
	var sd := int(rd["s"]) + int(rd["extra"]) + int(cb["mods"]["d"].get("succ", 0)) - int(cb["mods"]["d"].get("nsucc", 0))
	sa = maxi(0, sa)
	sd = maxi(0, sd)
	_log_roll("Attaccante", da, ra, sa)
	_log_roll("Difensore", dd, rd, sd)
	fx.emit("dice", {"what": "battle", "a": ra, "d": rd, "sa": sa, "sd": sd, "t": t})
	var ha := 0
	var hd := 0
	if sa > sd:
		hd = sa - sd
	elif sd > sa:
		ha = sd - sa
	elif sa > 0:
		var ar := _side_ranged("a")
		var dr := _side_ranged("d")
		if ar and not dr:
			hd = 1
			log_msg("Parità: vince chi ha l'Attacco a Distanza.")
		elif dr and not ar:
			ha = 1
			log_msg("Parità: vince chi ha l'Attacco a Distanza.")
		else:
			log_msg("Parità: nessun colpo.")
	else:
		if _has_hero("a", "H312"):
			hd = 1
		elif _has_hero("d", "H312"):
			ha = 1
		else:
			log_msg("Nessun successo da entrambe le parti.")
	cb["won"] = 0 if hd > 0 else (1 if ha > 0 else -1)
	if hd > 0:
		await apply_hits("d", hd, false)
	if ha > 0:
		await apply_hits("a", ha, false)


func _has_hero(role: String, hid: String) -> bool:
	for u in side_units(role):
		if u["t"] == hid:
			return true
	return false


func _log_roll(who: String, dice: Vector2i, r: Dictionary, s: int) -> void:
	var parts: Array = []
	for x in r["rolls"]:
		parts.append(("%d" % x["v"]) + ("*" if x.get("crit", false) else ""))
	var conf := ""
	if not r["conf"].is_empty():
		conf = " · conferme %s" % str(r["conf"])
	log_msg("%s: %dd6 + %dd8%s » [%s]%s = %d successi." % [who, dice.x, dice.y, (" (mod. %d)" % r["mod"]) if int(r["mod"]) != 0 else "", ", ".join(parts), conf, s])


## Imboscata (9.6): chi la dichiara colpisce per primo; se il bersaglio sopravvive colpisce a sua volta.
func _ambush(attacker_first: bool) -> void:
	var first := "a" if attacker_first else "d"
	var second := "d" if attacker_first else "a"
	log_msg("[b]Imboscata[/b] di %s!" % ("chi attacca" if attacker_first else "chi difende"))
	var hits := await _strike_in_combat(first)
	if hits > 0:
		await apply_hits(second, hits, true)
	if _side_alive(second) and not cb["canceled"]:
		var hits2 := await _strike_in_combat(second)
		if hits2 > 0:
			await apply_hits(first, hits2, true)
	cb["won"] = -1


func _side_alive(role: String) -> bool:
	if role == "d" and cb["type"] == "mon":
		return not cb["mon_down"]
	if role == "d" and cb["type"] == "set" and side_units("d").is_empty():
		return not cb["garrison_down"]
	return not side_units(role).is_empty()


func _strike_in_combat(role: String) -> int:
	var dice := combat_dice(role, true)
	var mod := 0
	if role == "a" and cb["amb"] == 0:
		mod = fort_mod()
	var r := roll(dice, mod, role)
	var s := int(r["s"])
	var who := "Attaccante" if role == "a" else "Difensore"
	_log_roll(who + " (assalto)", dice, r, s)
	fx.emit("dice", {"what": "strike", role: r, "t": cb["t"]})
	if cb["mods"][role].get("cancel_strike", false):
		log_msg("L'assalto è annullato dalla magia.")
		return 0
	if s <= 0:
		return 0
	if cb["mods"][role].get("axes", false):
		return s + int(r["extra"])
	return 1 + int(r["extra"])


## Applica n colpi a un lato: chi li subisce sceglie come distribuirli (9.2.1).
func apply_hits(role: String, n: int, strike: bool) -> void:
	if n <= 0:
		return
	var t := int(cb["t"])
	if advanced:
		n = await magic.hit_reactions(role, n, strike)
	if role == "d":
		cb["hits_d"] = int(cb["hits_d"]) + n
	else:
		cb["hits_a"] = int(cb["hits_a"]) + n
	for i in range(n):
		if role == "d" and cb["type"] == "mon":
			cb["mon_down"] = true
			break
		var us := side_units(role)
		var opts: Array = []
		for u in us:
			opts.append(int(u["id"]))
		if opts.is_empty():
			if role == "d" and cb["type"] == "set":
				cb["garrison_down"] = true
			break
		var pick: int = opts[0]
		if role == "d" and cb["type"] == "set" and army_at(t).is_empty():
			# guarnigione comandata da un eroe solitario: il primo colpo elimina l'eroe
			for u in us:
				await _kill(u, "")
			cb["garrison_down"] = true
			break
		if opts.size() > 1:
			var who := owner(us[0])
			var r = await decide(who, {"type": "hit", "options": opts, "left": n - i, "t": t, "slow": false})
			if _as_int(r) in opts:
				pick = _as_int(r)
		var u := unit(pick)
		await _hit_unit(u)
	changed.emit()


func _hit_unit(u: Dictionary) -> void:
	if is_hero(u):
		log_msg("%s viene ucciso." % uname(u))
		await _kill(u, "colpo")
		return
	if u["weak"] or has_ch(u, "fragile"):
		log_msg("%s di %s è eliminata." % [uname(u), kn(owner(u))])
		await _kill(u, "colpo")
	else:
		u["weak"] = true
		log_msg("%s di %s è indebolita." % [uname(u), kn(owner(u))])
		fx.emit("weak", {"id": u["id"]})


func _after_combat() -> void:
	if cb.is_empty():
		return
	var k := int(cb["k"])
	var t := int(cb["t"])
	if cb["type"] == "mon":
		if cb["mon_down"]:
			var us := side_units("a")
			await _monster_defeated(t, k, not feral_limited(us) and not us.is_empty(), true)
		else:
			log_msg("Il mostro resiste.")
		return
	var att := side_units("a")
	var has_army := false
	for u in att:
		if u["kind"] == "army":
			has_army = true
	if not has_army or int(cb["hits_d"]) <= 0:
		return
	var en := army_at(t)
	if not en.is_empty() and enemies(owner(en), k):
		return
	var must: bool = cb["type"] == "set" and posture(t, k) in ["hostile"]
	if not must and cb["type"] == "set" and is_settlement(t) and posture(t, k) == "hostile":
		must = true
	var go: bool = must
	if not must:
		if not _can_advance(att, t):
			return
		var r = await decide(k, {"type": "advance", "t": t, "slow": false})
		go = r is bool and r
	if go:
		await advance(k, att, t)


func _can_advance(us: Array, t: int) -> bool:
	if is_sea(t) or is_lair(t) or monsters.has(t):
		return false
	var a := army_at(t)
	if not a.is_empty():
		return false
	return true


## Avanzata dopo il combattimento (9.3): la pila entra nell'esagono; un insediamento ostile viene saccheggiato.
func advance(k: int, us: Array, t: int) -> void:
	if not _can_advance(us, t):
		return
	var hostile_set := is_settlement(t) and posture(t, k) == "hostile"
	if huge_in(us) and is_settlement(t) and not hostile_set:
		return
	var from := int(us[0]["h"])
	for u in us:
		u["h"] = t
	if not act.is_empty():
		act["h"] = t
	fx.emit("move", {"ids": cb.get("a", []), "from": from, "to": t, "ship": false})
	var hh := hero_at(t)
	if not hh.is_empty() and enemies(owner(hh), k):
		log_msg("%s viene travolto." % uname(hh))
		await _kill(hh, "")
	if hostile_set:
		await enter_hostile(k, t)
	changed.emit()


## Una pila entra in un insediamento ostile sconfitto (4.8, 4.9.2).
func enter_hostile(k: int, t: int) -> void:
	var us: Array = []
	for u in units_at(t):
		if owner(u) == k:
			us.append(u)
	if feral_limited(us) or huge_in(us):
		if ctrl.has(t) and enemies(int(ctrl[t]), k):
			log_msg("%s scaccia il presidio nemico da %s." % [_stack_name(us), hname(t)])
			ctrl.erase(t)
			fx.emit("ctrl", {"h": t, "k": -1})
		else:
			_raze(t, "%s devasta %s." % [_stack_name(us), hname(t)])
		_check_covens()
		return
	var g := 3 if D.KINGDOMS[k]["shashka"] else 2
	if city(t):
		g *= 2
	g += magic.loot_bonus(k)
	kd[k]["gold"] += g
	log_msg("%s saccheggia %s: +%d oro." % [kn(k), hname(t), g])
	fx.emit("loot", {"h": t, "k": k, "g": g})
	if ctrl.has(t):
		ctrl.erase(t)
	var l := loyal(t)
	if in_play(l) and (l == k or allies(l, k)):
		log_msg("%s torna a %s." % [hname(t), kn(l)])
		made_friendly[t] = true
		fx.emit("ctrl", {"h": t, "k": l})
		_check_covens()
		return
	var choice := "raze"
	if markers_left(k) > 0:
		var r = await decide(k, {"type": "conquer", "h": t, "slow": false})
		choice = "raze" if (r is String and r == "raze") else "ctrl"
	if choice == "ctrl":
		ctrl[t] = k
		made_friendly[t] = true
		_ever(k)
		log_msg("%s pone il suo segnalino di controllo a %s." % [kn(k), hname(t)])
		fx.emit("ctrl", {"h": t, "k": k})
	else:
		_raze(t, "%s rade al suolo %s." % [kn(k), hname(t)])
	_check_covens()


func _raze(h: int, why: String) -> void:
	if razed.has(h):
		return
	razed[h] = true
	ctrl.erase(h)
	coven.erase(h)
	if why != "":
		log_msg(why)
	fx.emit("raze", {"h": h})


func _huge_in_settlement(u: Dictionary) -> void:
	var h := int(u["h"])
	for n in nbrs(h):
		if enter_kind(owner(u), [u], n, has_ab(u, "flying")) == 2 and not is_settlement(n):
			u["h"] = n
			log_msg("%s esce da %s." % [uname(u), hname(h)])
			fx.emit("move", {"ids": [u["id"]], "from": h, "to": n, "ship": false})
			return
	log_msg("%s non trova spazio e torna sulla plancia." % uname(u))
	_eliminate(u, "")


# ------------------------------------------------------------------ eliminazione

## Elimina un'unità passando dalle reazioni magiche (Freyja, Mutare Forma, Necromanzia…).
func _kill(u: Dictionary, why: String) -> void:
	if u.is_empty() or int(u["h"]) < 0:
		return
	if advanced:
		var saved: bool = await magic.on_eliminate(u, why)
		if saved:
			return
	_eliminate(u, why)


func _eliminate(u: Dictionary, _why: String) -> void:
	var h := int(u["h"])
	var k := int(u["k"])
	fx.emit("elim", {"id": u["id"], "h": h})
	if u["kind"] == "army":
		# un'armata assoggettata torna al suo regno solo se è l'eroe a cadere; se cade l'armata, l'eroe va via
		if u.has("ctl"):
			u.erase("ctl")
			var eh := hero_at(h)
			if not eh.is_empty() and eh["kind"] == "ehero":
				eh["h"] = -1
				units.erase(eh)
		u["h"] = -1
		u["weak"] = false
		u["fin"] = false
		u.erase("ctl")
	else:
		if u["kind"] == "ehero":
			var ar := army_at(h)
			if not ar.is_empty() and ar.has("ctl"):
				ar.erase("ctl")
				log_msg("%s si libera dall'incantesimo e torna a %s." % [uname(ar), kn(int(ar["k"]))])
				if is_settlement(h) and welcoming(h, D.NIGHT):
					var moved := false
					for n in nbrs(h):
						if enter_kind(int(ar["k"]), [ar], n, false) == 2:
							ar["h"] = n
							moved = true
							break
					if not moved:
						ar["h"] = -1
		else:
			kd[k]["hcards"].erase(u["t"])
			if kd.has(k):
				var pool: Array = kd[k]["hero_pool"]
				pool.append(u["t"])
				_shuffle(pool)
		u["h"] = -1
		units.erase(u)
	changed.emit()


func _remove_from_map(u: Dictionary) -> void:
	u["h"] = -1
	u["weak"] = false
	u["fin"] = false
	changed.emit()


# ================================================================== mostri (15)

func monster_count(k: int) -> int:
	var n := 0
	for h in monsters:
		if int(monsters[h]["cmd"]) == k and not monsters[h]["def"]:
			n += 1
	return n


## Esplorazione di una tana: si pesca un mostro, lo comanda un avversario di chi attacca.
func _lair_monster(t: int, k: int) -> bool:
	var sea: bool = D.hexes[t]["lair"] == "S"
	var pool: Array = pool_sea if sea else pool_land
	if pool.is_empty():
		log_msg("La tana di %s è vuota." % hname(t))
		return false
	var mid: String = pool.pop_front()
	var cmd := await _pick_commander(k)
	monsters[t] = {"m": mid, "def": false, "cmd": cmd, "fin": true, "wander": false}
	log_msg("Nella tana di %s si risveglia: [b]%s[/b]%s." % [hname(t), D.monster(mid)["n"], (" (lo comanda %s)" % kn(cmd)) if cmd >= 0 else ""])
	fx.emit("monster", {"h": t})
	changed.emit()
	return true


## Un avversario di k prende il comando del mostro (15.3): chi ne comanda meno; con tre già in campo
## uno dei suoi mostri torna nella riserva.
func _pick_commander(k: int) -> int:
	var best := -1
	var bn := 99
	for c in order:
		if not in_play(c) or not enemies(c, k):
			continue
		var n := monster_count(c)
		if n < bn:
			bn = n
			best = c
	if best < 0:
		return -1
	if bn >= D.MONSTER_CMD:
		for h in monsters.keys():
			if int(monsters[h]["cmd"]) == best and not monsters[h]["def"]:
				_slink(h)
				break
	return best


func _slink(h: int) -> void:
	var m: Dictionary = monsters[h]
	var md := D.monster(m["m"])
	(pool_sea if md.get("sea", false) else pool_land).append(m["m"])
	monsters.erase(h)
	log_msg("%s si dilegua." % md["n"])
	fx.emit("monster", {"h": h})


func _monster_defeated(t: int, k: int, reward: bool, in_combat: bool) -> void:
	var m: Dictionary = monsters[t]
	var md := D.monster(m["m"])
	log_msg("[b]%s è sconfitto![/b]" % md["n"])
	if is_lair(t) and not m["wander"]:
		m["def"] = true
		m["cmd"] = -1
	else:
		(pool_sea if md.get("sea", false) else pool_land).append(m["m"])
		monsters.erase(t)
	if reward and in_combat:
		var g := int(md["gold"]) - int(cb.get("reward_minus", 0)) if not cb.is_empty() else int(md["gold"])
		g = maxi(0, g)
		kd[k]["gold"] += g
		var tr := ""
		if not m["wander"]:
			var c := _draw_treasure(player_of(k))
			if c != "":
				tr = " e un Tesoro"
		log_msg("%s ottiene %d oro%s." % [kn(k), g, tr])
	fx.emit("monster", {"h": t})
	changed.emit()


func monster_range(mid: String) -> int:
	var md := D.monster(mid)
	if md.get("sea", false):
		return 4
	if "flying" in md["ab"]:
		return 3
	if "mage" in md["ab"]:
		return 2
	return 1


func monster_targets(k: int, h: int) -> Array:
	var m: Dictionary = monsters[h]
	var rg := monster_range(m["m"])
	var sea: bool = D.monster(m["m"]).get("sea", false)
	var out: Array = []
	for t in D.hexes:
		if not in_map(t) or t == h or D.dist(h, t) > rg:
			continue
		if sea and not is_wet(t):
			continue
		if strike_target_ok(k, t):
			out.append(t)
	return out


## Bersaglio valido per un assalto fuori combattimento: pila nemica, mostro nemico o insediamento ostile
## (non fortificato: gli assalti non colpiscono le fortificazioni).
func strike_target_ok(k: int, t: int, allow_fort := false) -> bool:
	if is_settlement(t) and fort(t) > 0 and not allow_fort:
		return false
	for u in units_at(t):
		if enemies(owner(u), k):
			return true
	if monsters.has(t) and not monsters[t]["def"] and enemies(int(monsters[t]["cmd"]), k):
		return true
	if is_settlement(t) and posture(t, k) == "hostile" and army_at(t).is_empty():
		return true
	return false


func _monster_action(k: int, h: int, r: Dictionary) -> void:
	if not monsters.has(h) or int(monsters[h]["cmd"]) != k:
		return
	var m: Dictionary = monsters[h]
	m["fin"] = true
	var what := str(r.get("do", "pass"))
	if what == "slink":
		_slink(h)
	elif what == "strike":
		var t := int(r.get("t", -1))
		if t in monster_targets(k, h):
			var md := D.monster(m["m"])
			log_msg("%s colpisce %s." % [md["n"], hname(t)])
			await strike(k, Vector2i(int(md["l"]), int(md["h"])), t, {"src": "monster", "h": h})
	changed.emit()


## Assalto fuori combattimento (9.7, 16.9): tira solo chi colpisce; un successo = un colpo
## (più i critici confermati). Un insediamento ostile rimasto vuoto perde il segnalino o è raso.
func strike(k: int, dice: Vector2i, t: int, opts: Dictionary) -> int:
	var saved_cb := cb
	cb = {"k": k, "a": [], "from": int(opts.get("h", t)), "t": t, "type": "strike", "dk": -1, "mods": {"a": {}, "d": {}},
		"canceled": false, "hits_a": 0, "hits_d": 0, "garrison_down": false, "mon_down": false, "amb": -1, "strike": true}
	if advanced and not opts.get("no_react", false):
		await magic.window("strike", {"k": k, "t": t, "src": opts.get("src", "")})
	if cb["canceled"]:
		log_msg("L'assalto è annullato.")
		cb = saved_cb
		return 0
	var mod := 0 if opts.get("no_fort", true) else -fort(t)
	var r := roll(dice + Vector2i(int(cb["mods"]["a"].get("l", 0)), int(cb["mods"]["a"].get("h", 0))), mod, "a")
	var s := int(r["s"])
	_log_roll("Assalto", dice, r, s)
	fx.emit("dice", {"what": "strike", "a": r, "t": t})
	var hits := 0
	if s > 0:
		hits = 1 + int(r["extra"])
	if hits > 0:
		if monsters.has(t) and not monsters[t]["def"] and enemies(int(monsters[t]["cmd"]), k):
			await _monster_defeated(t, k, opts.get("reward", false), opts.get("reward", false))
		else:
			var us: Array = []
			for u in units_at(t):
				if enemies(owner(u), k):
					us.append(u)
			if not us.is_empty():
				cb["type"] = "army"
				await apply_hits("d", hits, true)
			if is_settlement(t) and posture(t, k) == "hostile" and army_at(t).is_empty():
				if ctrl.has(t):
					log_msg("Il segnalino di controllo di %s è tolto." % hname(t))
					ctrl.erase(t)
				else:
					_raze(t, "%s è raso al suolo." % hname(t))
				_check_covens()
	else:
		log_msg("L'assalto non va a segno.")
	cb = saved_cb
	changed.emit()
	return hits


# ================================================================== Congreghe (12.3)

func coven_targets(_free: bool) -> Array:
	var out: Array = []
	for h in inplay:
		if razed.has(h) or coven.has(h) or is_inert(h):
			continue
		if posture(h, D.NIGHT) == "hostile":
			out.append(h)
	out.sort()
	return out


func coven_bonus(h: int) -> int:
	var b := 0
	if army_at(h).is_empty():
		b += 1
	if fort(h) == 0:
		b += 1
	var w := is_wild(h)
	for n in nbrs(h):
		if is_wild(n):
			w = true
	if w:
		b += 1
	return b


func _try_coven(h: int) -> void:
	var auto := false
	for u in on_map(D.NIGHT):
		if u["t"] == "H013" and D.dist(int(u["h"]), h) <= 5:
			auto = true
	if auto:
		coven[h] = true
		log_msg("Dominia insedia senza fatica una Congrega a %s." % hname(h))
	else:
		var v := d6()
		var tot := v + coven_bonus(h)
		fx.emit("dice", {"what": "coven", "rolls": [v]})
		if tot >= 5:
			coven[h] = true
			log_msg("Una Congrega si insedia a %s (%d+%d)." % [hname(h), v, coven_bonus(h)])
		else:
			log_msg("La Congrega non riesce a insediarsi a %s (%d+%d)." % [hname(h), v, coven_bonus(h)])
	fx.emit("coven", {"h": h})
	changed.emit()


## Nascondersi nelle Ombre (12.3.5): un'armata nemica si ferma nell'insediamento della Congrega.
func _coven_hide(h: int) -> void:
	if cb.get("hidden_ok", {}).has(h) or _eff_global("covens_hidden"):
		return
	if advanced:
		var played: bool = await magic.coven_found(h)
		if played or not coven.has(h):
			return
	var v := d6()
	if magic.siskar_reroll(v):
		v = d6()
	fx.emit("dice", {"what": "hide", "rolls": [v]})
	if v >= 5:
		log_msg("La Congrega di %s resta nascosta (%d)." % [hname(h), v])
		effects.append({"dur": "turn", "hidden": h})
	else:
		log_msg("La Congrega di %s è scoperta e dispersa (%d)." % [hname(h), v])
		coven.erase(h)
		fx.emit("coven", {"h": h})


func _eff_global(key: String) -> bool:
	for e in effects:
		if e.get(key, false):
			return true
	return false


func _check_covens() -> void:
	for h in coven.keys():
		if razed.has(h) or not is_settlement(h) or welcoming(h, D.NIGHT):
			coven.erase(h)
			log_msg("La Congrega di %s svanisce." % hname(h))
			fx.emit("coven", {"h": h})


# ================================================================== Shashka, crollo, vittoria

func _lay_waste(k: int, h: int) -> void:
	if int(ctrl.get(h, -1)) != k:
		return
	var g := 3 * (2 if city(h) else 1)
	ctrl.erase(h)
	kd[k]["gold"] += g
	_raze(h, "%s devasta %s e ne trae %d oro." % [kn(k), hname(h), g])
	fx.emit("loot", {"h": h, "k": k, "g": g})
	_check_covens()


func _collapse_checks(k: int) -> void:
	if not in_play(k):
		return
	if D.KINGDOMS[k]["shashka"]:
		if kd[k]["ever_ctrl"] and control_markers(k) == 0:
			log_msg("%s non controlla più alcun insediamento." % kn(k))
			_collapse(k)
		return
	var cs := cities_of(k)
	if cs.is_empty():
		return
	for h in cs:
		if not razed.has(h) and controller(h) == k:
			return
	log_msg("Tutte le Città di %s sono cadute." % kn(k))
	_collapse(k)


func _collapse(k: int) -> void:
	if not kd.has(k) or kd[k]["collapsed"]:
		return
	kd[k]["collapsed"] = true
	log_msg("[b][color=#ff7a68]%s crolla![/color][/b]" % kn(k))
	for u in units.duplicate():
		if int(u["h"]) >= 0 and (owner(u) == k or int(u["k"]) == k):
			_eliminate(u, "")
	for h in ctrl.keys():
		if int(ctrl[h]) == k:
			ctrl.erase(h)
	if k == D.NIGHT:
		coven.clear()
	for h in monsters.keys():
		if int(monsters[h]["cmd"]) == k and not monsters[h]["def"]:
			_slink(h)
	fx.emit("collapse", {"k": k})
	_check_covens()
	changed.emit()
	_check_victory_now()


func side_kingdoms(s: int) -> Array:
	var out: Array = []
	for k in side:
		if int(side[k]) == s:
			out.append(k)
	return out


func _win(s: int, why: String) -> void:
	if game_over:
		return
	winner = s
	win_reason = why
	game_over = true
	log_msg("[b]Vince %s: %s[/b]" % [D.SIDE_NAMES[s], why])


## Vittorie immediate (campagne e crollo di uno schieramento).
func _check_victory_now() -> void:
	if game_over or phase == "setup":
		return
	for s in [0, 1]:
		var alive := false
		for k in side_kingdoms(s):
			if in_play(k):
				alive = true
		if not alive:
			_win(1 - s, "tutti i regni avversari sono crollati")
			return
	var id := int(camp["id"])
	match id:
		0:
			if cur_k >= 0 and phase == "activation":
				var s := int(side[cur_k])
				var all_mine := true
				for h in inplay:
					var c := controller(h)
					if c < 0 or int(side.get(c, -1)) != s:
						all_mine = false
				if all_mine:
					_win(s, "controlla tutti e sei gli insediamenti")
		1:
			var sp := D.hex_of("Spire of the Moon")
			if in_play(D.NIGHT) and (razed.has(sp) or controller(sp) != D.NIGHT):
				log_msg("La Spira della Luna è caduta!")
				_collapse(D.NIGHT)
		3:
			var vik := D.hex_of("Vikensinger Fortress")
			if controller(vik) == D.EMPIRE or (razed.has(vik) and in_play(D.FJORD)):
				_win(1, "l'Impero ha preso Vikensinger Fortress")
				return
			var aur := D.hex_of("Aureliana")
			if cur_k == D.EMPIRE and phase == "activation" and controller(aur) == D.FJORD:
				_win(0, "Fjordland tiene Aureliana alla fine di un turno dell'Impero")
		5:
			for k in side_kingdoms(1):
				if kd[k]["collapsed"]:
					_win(0, "è crollato un regno della Resistenza")
					return
		6:
			var n := 0
			for k in side_kingdoms(1):
				if kd[k]["collapsed"]:
					n += 1
			if n >= 2:
				_win(0, "sono crollati due regni della Resistenza")


func set_value(h: int) -> int:
	if city(h):
		return 3
	if fort(h) > 0:
		return 2
	return 1


## Punti vittoria di uno schieramento (regole comuni 1–3).
func vp(s: int) -> int:
	return vp_detail(s)["tot"]


func vp_detail(s: int) -> Dictionary:
	var sets := 0
	var raz := 0
	var cov := 0
	var hs: Array = inplay.keys()
	if khazud >= 0:
		hs.append(khazud)
	for h in hs:
		if razed.has(h):
			continue
		var c := controller(h)
		if c >= 0 and int(side.get(c, -1)) == s:
			sets += set_value(h)
	if s == 0:
		if side.has(D.ORC) or side.has(D.GOBLIN):
			for h in razed:
				if inplay.has(h) or h == khazud:
					raz += 1
		cov = coven.size()
	return {"sets": sets, "razed": raz, "covens": cov, "tot": sets + raz + cov}


## Punti degli insediamenti controllati da un singolo regno (più i rasi, per gli Shashka).
func kingdom_vp(k: int, loyal_to := -1, with_razed := false) -> int:
	var n := 0
	for h in inplay:
		if razed.has(h):
			if with_razed:
				n += 1
			continue
		if controller(h) == k and (loyal_to < 0 or loyal(h) == loyal_to):
			n += set_value(h)
	return n


func _final_scoring() -> void:
	phase = "end"
	var v0 := vp(0)
	var v1 := vp(1)
	var id := int(camp["id"])
	if not game_over:
		match id:
			0:
				if v0 > v1:
					_win(0, "%d PV contro %d" % [v0, v1])
				else:
					_win(1, "%d PV contro %d%s" % [v1, v0, " (parità: vincono gli Oathborn)" if v0 == v1 else ""])
			1, 5:
				if v0 > v1:
					_win(0, "%d PV contro %d" % [v0, v1])
				else:
					_win(1, "gli Invasori hanno %d PV contro %d" % [v0, v1])
			2:
				var g := kingdom_vp(D.GOBLIN, -1, true)
				if g >= 8:
					_win(0, "i Goblin hanno %d PV (ne servivano 8)" % g)
				else:
					_win(1, "i Goblin si fermano a %d PV su 8" % g)
			3:
				var f := kingdom_vp(D.FJORD, D.EMPIRE)
				if f >= 6:
					_win(0, "Fjordland controlla %d PV di insediamenti imperiali" % f)
				else:
					_win(1, "Fjordland ha solo %d PV di insediamenti imperiali su 6" % f)
			4:
				var o := kingdom_vp(D.ORC, -1, true)
				var pl := D.hex_of("Placidia")
				var dr := D.hex_of("Drakenhold")
				var fell := razed.has(pl) or controller(pl) == D.ORC or razed.has(dr) or controller(dr) == D.ORC
				if o >= 10 or fell:
					_win(0, "gli Orchi hanno %d PV%s" % [o, " e una delle grandi città è caduta" if fell else ""])
				else:
					_win(1, "gli Orchi si fermano a %d PV su 10 e Placidia e Drakenhold resistono" % o)
			6:
				var need := int(ceil(v1 / 2.0))
				if v0 >= need:
					_win(0, "%d PV, almeno metà dei %d della Resistenza" % [v0, v1])
				else:
					_win(1, "gli Invasori hanno %d PV, ne servivano %d" % [v0, need])
	results = {"winner": winner, "reason": win_reason, "vp": [vp_detail(0), vp_detail(1)], "turns": turn_no}
	game_over = true
	changed.emit()
	game_ended.emit(results)


## Impronta della partita (per verificare che online tutti i dispositivi coincidano).
func fingerprint() -> String:
	var parts: Array = ["%d/%d" % [year, season]]
	for k in side:
		parts.append("%d:%d:%d:%s" % [k, kd[k]["gold"], income(k), "x" if kd[k]["collapsed"] else ""])
	var ul: Array = []
	for u in units:
		if int(u["h"]) >= 0:
			ul.append("%d@%d%s" % [u["id"], u["h"], "w" if u["weak"] else ""])
	parts.append(",".join(ul))
	parts.append(str(ctrl.keys()))
	parts.append(str(razed.keys()))
	return "|".join(parts).md5_text()


# ================================================================== carte e Studio Arcano (13, 16, 17)

func _setup_decks() -> void:
	spell_deck.clear()
	tre_deck.clear()
	bless_deck.clear()
	for c in D.card_list:
		match str(c["deck"]):
			"spell":
				spell_deck.append(c["id"])
			"treasure":
				tre_deck.append(c["id"])
			"blessing":
				var k := int(c["k"])
				if side.has(k):
					if not bless_deck.has(k):
						bless_deck[k] = []
					bless_deck[k].append(c["id"])
	_shuffle(spell_deck)
	_shuffle(tre_deck)
	for k in bless_deck:
		_shuffle(bless_deck[k])
	spell_disc.clear()
	bless_disc.clear()
	tre_out.clear()


func _draw_spell(p: Dictionary) -> String:
	if spell_deck.is_empty():
		spell_deck = spell_disc.duplicate()
		spell_disc.clear()
		_shuffle(spell_deck)
	if spell_deck.is_empty():
		return ""
	var c: String = spell_deck.pop_front()
	p["hand"].append(c)
	return c


func _draw_blessing(p: Dictionary, k: int) -> String:
	if not bless_deck.has(k):
		return ""
	if bless_deck[k].is_empty():
		for c in bless_disc.duplicate():
			if int(D.card(c)["k"]) == k:
				bless_disc.erase(c)
				bless_deck[k].append(c)
		_shuffle(bless_deck[k])
	if bless_deck[k].is_empty():
		return ""
	var c2: String = bless_deck[k].pop_front()
	p["hand"].append(c2)
	return c2


func _draw_treasure(p: Dictionary) -> String:
	if tre_deck.is_empty():
		tre_deck = tre_out.duplicate()
		tre_out.clear()
		_shuffle(tre_deck)
	if tre_deck.is_empty():
		return ""
	var c: String = tre_deck.pop_front()
	p["hand"].append(c)
	fx.emit("card", {"seat": p["seat"], "c": c, "draw": true})
	return c


func hand_count(p: Dictionary, deck: String, k := -1) -> int:
	var n := 0
	for c in p["hand"]:
		var cd := D.card(c)
		if str(cd["deck"]) == deck and (k < 0 or int(cd["k"]) == k):
			n += 1
	return n


func _distribute_study() -> void:
	study.clear()
	if not advanced:
		return
	var pool := study_pool.duplicate()
	_shuffle(pool)
	var i := 0
	for k in order:
		if not in_play(k):
			continue
		study[k] = pool[i] if i < pool.size() else "churn"
		i += 1


## Fase di Studio Arcano dopo il turno di un regno: tutti studiano 3 discipline (Glifo) o 1 (Turbine).
func _arcane_study(k: int) -> void:
	var m: String = study.get(k, "churn")
	var n := 3 if m == "glyph" else 1
	log_msg("Studio Arcano: %s (%d disciplin%s)." % ["Glifo" if m == "glyph" else "Turbine", n, "a" if n == 1 else "e"])
	fx.emit("study", {"k": k, "m": m})
	for p in players:
		var mine := false
		for kk in p["ks"]:
			if in_play(int(kk)):
				mine = true
		if not mine:
			continue
		var anyk: int = -1
		for kk in p["ks"]:
			if in_play(int(kk)):
				anyk = int(kk)
				break
		var r = await decide(anyk, {"type": "study", "n": n, "slow": false, "options": study_options(p)})
		study_apply(p, r if r is Dictionary else {}, n)
	changed.emit()


func study_options(p: Dictionary) -> Dictionary:
	return {"treasure": p["owned"].filter(func(c): return not str(c).begins_with("T29") and not str(c).begins_with("T30")),
		"spells": hand_count(p, "spell"), "blessings": hand_count(p, "blessing")}


## r: {"t": tesoro da riprendere o "", "s": bool studia incantesimi, "sd": incantesimo da scartare,
##     "b": bool benedizioni, "bd": benedizione da scartare}
func study_apply(p: Dictionary, r: Dictionary, n: int) -> void:
	var done := 0
	var order_d: Array = r.get("order", ["s", "b", "t"])
	for d in order_d:
		if done >= n:
			break
		match d:
			"s":
				if not r.get("s", true):
					continue
				var sd := str(r.get("sd", ""))
				if sd != "" and sd in p["hand"] and str(D.card(sd)["deck"]) == "spell":
					p["hand"].erase(sd)
					spell_disc.append(sd)
				var drew := 0
				while hand_count(p, "spell") < 3 and drew < 3:
					if _draw_spell(p) == "":
						break
					drew += 1
				done += 1
			"b":
				if not r.get("b", true):
					continue
				var bd := str(r.get("bd", ""))
				if bd != "" and bd in p["hand"] and str(D.card(bd)["deck"]) == "blessing":
					p["hand"].erase(bd)
					bless_disc.append(bd)
				for kk in p["ks"]:
					if in_play(int(kk)) and hand_count(p, "blessing", int(kk)) < 1:
						_draw_blessing(p, int(kk))
				done += 1
			"t":
				var t := str(r.get("t", ""))
				if t == "" or not t in p["owned"]:
					continue
				var reps := 2 if "T02" in p["owned"] else 1
				for i in range(reps):
					if t in p["owned"]:
						if _owns_curse(p) and int(kd[_any_k(p)]["gold"]) >= 1:
							kd[_any_k(p)]["gold"] -= 1
						elif _owns_curse(p):
							break
						p["owned"].erase(t)
						p["hand"].append(t)
					t = ""
					for c in p["owned"]:
						if c != "T02" and c != "T29" and c != "T30":
							t = c
							break
					if t == "":
						break
				done += 1


func _owns_curse(p: Dictionary) -> bool:
	return "T29" in p["owned"] or "T30" in p["owned"]


func _any_k(p: Dictionary) -> int:
	for kk in p["ks"]:
		if in_play(int(kk)):
			return int(kk)
	return int(p["ks"][0])


## Inverno (13.2.2): i mostri sconfitti lasciano le tane, si vendono i tesori in eccesso,
## si rimescolano gli scarti.
func _winter() -> void:
	phase = "winter"
	log_msg("[b]Inverno[/b]: le tane si ripopolano, i mazzi si rimescolano.")
	autumn_in = false
	study_pool.erase("churn")
	var nk := 0
	for k in order:
		if in_play(k):
			nk += 1
	var c := 1 if nk <= 3 else 2
	var have := study_pool.count("churn")
	for i in range(c - have):
		study_pool.append("churn")
	for h in monsters.keys():
		if monsters[h]["def"]:
			var md := D.monster(monsters[h]["m"])
			(pool_sea if md.get("sea", false) else pool_land).append(monsters[h]["m"])
			monsters.erase(h)
	_shuffle(pool_land)
	_shuffle(pool_sea)
	for p in players:
		var tr: Array = []
		for x in p["hand"]:
			if str(D.card(x)["deck"]) == "treasure":
				tr.append(x)
		for x in p["owned"]:
			if not x in ["T29", "T30"]:
				tr.append(x)
		var keep := 2
		if "T02" in p["owned"]:
			keep = 4
		while tr.size() > keep:
			var x: String = tr.pop_back()
			p["hand"].erase(x)
			p["owned"].erase(x)
			tre_out.append(x)
			kd[_any_k(p)]["gold"] += 2
			log_msg("%s vende %s per 2 oro." % [p["name"], D.card(x)["n"]])
	spell_deck.append_array(spell_disc)
	spell_disc.clear()
	_shuffle(spell_deck)
	for x in bless_disc:
		var k := int(D.card(x)["k"])
		if bless_deck.has(k):
			bless_deck[k].append(x)
	bless_disc.clear()
	for k in bless_deck:
		_shuffle(bless_deck[k])
	tre_deck.append_array(tre_out)
	tre_out.clear()
	_shuffle(tre_deck)
	changed.emit()
