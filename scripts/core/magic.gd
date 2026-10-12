class_name BBMagic
extends RefCounted
## Carte magiche (Incantesimi, Tesori, Benedizioni) e poteri degli eroi del gioco avanzato.
## Ogni carta giocabile in un certo momento («finestra») diventa una o più giocate:
## {"c": carta, "caster": id dell'unità che la lancia (−1 nessuna, −1000−esagono = mostro),
##  "t": bersaglio, "o": opzione, "tome": tomo giocato insieme, "label": testo}.
## Finestre: main (azione gratuita nel proprio turno), bm_a / bm_b / bm_c (Magia di Battaglia:
## attaccante, difensore, attaccante), e le reazioni hit, rolled, strike, cast, elim, moved,
## sea_cross, coven, mined, won.

const D = preload("res://scripts/data/bb_data.gd")

var eng: BBEngine
var played_bm := {}         # posto -> carte giocate in questa Magia di Battaglia (Bastone delle Pestilenze, Elmo)

const TOMES := ["S22", "T08", "T21", "T22", "T23", "T24", "T31"]
## Carte che si giocano nella finestra principale (azione gratuita, fuori dal combattimento).
const MAIN_CARDS := ["S04", "S05", "S06", "S08", "S11", "S12", "S17", "S20", "S21", "S23", "S24", "S27", "S29", "S31",
	"S35", "S38", "S43", "S45", "S46", "S48", "S49", "S52",
	"T02", "T04", "T05", "T06", "T13", "T17", "T18", "T19", "T25", "T28", "T29", "T30", "T32", "T35", "T36",
	"B001", "B002", "B003", "B004", "B005", "B007",
	"B101", "B102", "B103", "B104", "B105",
	"B203", "B204",
	"B303", "B304", "B309",
	"B401", "B403", "B404", "B405", "B407", "B408", "B409", "B410",
	"B501", "B503", "B504", "B506"]
## Poteri degli eroi giocabili nel proprio turno fuori combattimento.
const MAIN_POWERS := ["H012", "H111", "H112", "H214", "H317", "H413", "H512", "H514"]
## Carte e poteri di Magia di Battaglia (oltre a quelle segnate bm nei dati).
const BM_EXTRA := ["S10", "S17", "S19", "S41", "S44", "T20", "T27", "B007", "B407", "B509", "B310", "B308", "H014", "H115", "H116", "H211", "H215", "H216", "H217", "H313", "H416", "H516", "H412", "H511", "S43", "S52", "S48"]


# ================================================================== aiuti

func card(id: String) -> Dictionary:
	return D.card(id)


func is_cantrip(id: String) -> bool:
	return bool(card(id).get("cantrip", false))


func p_of(seat: int) -> Dictionary:
	return eng.players[seat]


func seat_ks(seat: int) -> Array:
	var out: Array = []
	for k in eng.players[seat]["ks"]:
		if eng.in_play(int(k)):
			out.append(int(k))
	return out


func _range(id: String, tome := "") -> Vector2i:
	var r := str(card(id).get("range", ""))
	if r == "":
		return Vector2i(0, 99)
	var a: PackedStringArray = r.split("-")
	var lo := int(a[0]) if a.size() > 1 else 0
	var hi := int(a[a.size() - 1])
	if tome == "T08":
		hi *= 2
		lo = lo
	return Vector2i(lo, hi)


func in_range(id: String, from: int, to: int, tome := "") -> bool:
	var r := _range(id, tome)
	var d: int = D.dist(from, to)
	return d >= r.x and d <= r.y


## Lanciatori possibili per una carta: eroi con Mago del giocatore (del regno giusto per le
## benedizioni) e, per gli incantesimi, i mostri con Mago che comanda.
func casters(seat: int, id: String) -> Array:
	var cd := card(id)
	var out: Array = []
	var ks := seat_ks(seat)
	var deck := str(cd["deck"])
	if deck == "hero":
		for u in eng.units:
			if u["kind"] == "hero" and u["t"] == id and int(u["h"]) >= 0 and eng.owner(u) in ks:
				out.append(int(u["id"]))
		return out
	if not cd.get("mage", false) and str(cd.get("req", "")) == "":
		return [-1]
	if str(cd.get("req", "")) == "Ranged":
		for u in eng.units:
			if int(u["h"]) >= 0 and eng.owner(u) in ks and eng.has_ab(u, "ranged") and (deck != "blessing" or eng.owner(u) == int(cd["k"])):
				out.append(int(u["id"]))
		return out
	for u in eng.units:
		if int(u["h"]) < 0 or u["kind"] == "army" or not (eng.owner(u) in ks):
			continue
		if not eng.has_ab(u, "mage"):
			continue
		if deck == "blessing" and eng.owner(u) != int(cd["k"]):
			continue
		out.append(int(u["id"]))
	if deck == "spell" and not cd.get("elim_caster", false):
		for h in eng.monsters:
			var m: Dictionary = eng.monsters[h]
			if not m["def"] and int(m["cmd"]) in ks and "mage" in D.monster(m["m"])["ab"]:
				out.append(-1000 - int(h))
	return out


func caster_hex(c: int) -> int:
	if c <= -1000:
		return -1000 - c
	if c < 0:
		return -1
	var u: Dictionary = eng.unit(c)
	return int(u["h"]) if not u.is_empty() else -1


func caster_k(c: int, seat: int) -> int:
	if c <= -1000:
		return int(eng.monsters[-1000 - c]["cmd"])
	if c >= 0:
		return eng.owner(eng.unit(c))
	return seat_ks(seat)[0] if not seat_ks(seat).is_empty() else -1


func hero_locked(hid: String) -> bool:
	var k := int(D.HEROES[hid]["k"])
	return eng.kd.has(k) and eng.kd[k]["hcards"].has(hid) and eng.kd[k]["hcards"][hid]["locked"]


func _lock(hid: String) -> void:
	var k := int(D.HEROES[hid]["k"])
	if eng.kd.has(k) and eng.kd[k]["hcards"].has(hid):
		eng.kd[k]["hcards"][hid]["locked"] = true


func hero_on_map(hid: String) -> Dictionary:
	for u in eng.units:
		if u["kind"] == "hero" and u["t"] == hid and int(u["h"]) >= 0:
			return u
	return {}


## Il giocatore può giocare questa carta adesso? (turno proprio o Cantrip; benedizioni del regno attivo)
func timing_ok(seat: int, id: String) -> bool:
	var cd := card(id)
	var ks := seat_ks(seat)
	var mine := eng.cur_k in ks
	if str(cd["deck"]) == "blessing" or str(cd["deck"]) == "hero":
		var k := int(cd["k"])
		if not k in ks:
			return false
		if eng.cur_k == k:
			return true
		return is_cantrip(id)
	return mine or is_cantrip(id)


# ================================================================== finestra principale

func main_playable(k: int) -> Array:
	var seat: int = eng.seat_of[k]
	var out: Array = []
	for c in eng.players[seat]["hand"]:
		if not c in MAIN_CARDS or not timing_ok(seat, c):
			continue
		var cd := card(c)
		if str(cd["deck"]) == "blessing" and int(cd["k"]) != k:
			continue
		var ps := plays_for(seat, c, "main", {})
		if not ps.is_empty():
			out.append(c)
	return out


func main_powers(k: int) -> Array:
	var out: Array = []
	for hid in eng.kd[k]["hcards"]:
		if hid in MAIN_POWERS and not hero_locked(hid) and not plays_for(eng.seat_of[k], hid, "main", {}).is_empty():
			out.append(hid)
	return out


func sellable(k: int) -> Array:
	var p: Dictionary = eng.player_of(k)
	var out: Array = []
	for c in p["hand"]:
		if str(card(c)["deck"]) == "treasure" and not c in ["T29", "T30", "T35", "T36"]:
			out.append(c)
	for c in p["owned"]:
		if c in ["T29", "T30"]:
			if int(eng.kd[k]["gold"]) >= 3:
				out.append(c)
		elif c not in p.get("sold_block", []):
			out.append(c)
	return out


func sell(k: int, c: String) -> void:
	var p: Dictionary = eng.player_of(k)
	if c in ["T29", "T30"] and c in p["owned"]:
		if int(eng.kd[k]["gold"]) < 3:
			return
		eng.kd[k]["gold"] -= 3
		p["owned"].erase(c)
		eng.tre_out.append(c)
		eng.log_msg("%s si libera della maledizione %s (3 oro)." % [p["name"], card(c)["n"]])
		return
	if c in p["hand"]:
		p["hand"].erase(c)
	elif c in p["owned"]:
		p["owned"].erase(c)
	else:
		return
	eng.tre_out.append(c)
	eng.kd[k]["gold"] += 2
	eng.log_msg("%s vende %s per 2 oro." % [p["name"], card(c)["n"]])


## Giocata dalla fase di attivazione: r = {"a":"card"/"power","c","caster","t","o","tome"}.
func play(k: int, r: Dictionary) -> void:
	var seat: int = eng.seat_of[k]
	var ps := plays_for(seat, str(r.get("c", "")), "main", {})
	var pick := _match_play(ps, r)
	if pick.is_empty():
		return
	await resolve(seat, pick, "main")


func _match_play(ps: Array, r: Dictionary) -> Dictionary:
	for p in ps:
		if int(p.get("caster", -1)) == int(r.get("caster", -1)) and str(p.get("t", "")) == str(r.get("t", "")) and int(p.get("o", 0)) == int(r.get("o", 0)) and str(p.get("tome", "")) == str(r.get("tome", "")):
			return p
	return ps[0] if not ps.is_empty() and not r.has("t") else {}


# ================================================================== giocate possibili

## Tutte le giocate di una carta in una finestra. Per le carte con tomo si aggiungono le varianti.
func plays_for(seat: int, id: String, w: String, ctx: Dictionary) -> Array:
	var cd := card(id)
	if cd.is_empty():
		return []
	var p: Dictionary = p_of(seat)
	var deck := str(cd["deck"])
	if deck == "hero":
		if hero_locked(id) and cd.get("lock", false):
			return []
	elif not id in p["hand"]:
		return []
	if id in TOMES:
		return []
	if not timing_ok(seat, id) and not w.begins_with("r_"):
		return []
	if cd.get("discard", false):
		var sp := eng.hand_count(p, "spell") - (1 if deck == "spell" else 0)
		if sp < 1:
			return []
	var out: Array = []
	for c in casters(seat, id):
		out.append_array(_plays(seat, id, w, ctx, int(c), ""))
	# varianti con i tomi (solo per gli incantesimi)
	if deck == "spell" and not out.is_empty():
		var extra: Array = []
		for t in p["hand"]:
			if not t in TOMES or t == id:
				continue
			if t == "S22" and eng.hand_count(p, "spell") < 2:
				continue
			for pl in out.duplicate():
				var cpy: Dictionary = pl.duplicate()
				cpy["tome"] = t
				cpy["label"] = "%s + %s" % [pl["label"], card(t)["n"]]
				extra.append(cpy)
			if t == "T08":
				for c in casters(seat, id):
					for pl in _plays(seat, id, w, ctx, int(c), "T08"):
						pl["tome"] = "T08"
						pl["label"] += " + %s" % card("T08")["n"]
						extra.append(pl)
		out.append_array(extra)
	return out


func _mk(id: String, caster: int, t, o := 0, label := "") -> Dictionary:
	var n := str(card(id)["n"])
	return {"c": id, "caster": caster, "t": t, "o": o, "tome": "", "label": n + (" · " + label if label != "" else "")}


func _combat_role_of(caster: int) -> String:
	if eng.cb.is_empty() or str(eng.cb.get("type", "")) == "strike":
		return ""
	var h := caster_hex(caster)
	if h == int(eng.cb["from"]):
		return "a"
	if h == int(eng.cb["t"]):
		return "d"
	return ""


func _role_hex(role: String) -> int:
	return int(eng.cb["from"]) if role == "a" else int(eng.cb["t"])


func _role_units(role: String) -> Array:
	return eng.side_units(role)


func _role_has(role: String, pred: Callable) -> bool:
	for u in _role_units(role):
		if pred.call(u):
			return true
	return false


func _is_army_t(u: Dictionary, types: Array) -> bool:
	return u["kind"] == "army" and u["t"] in types


func _opp(role: String) -> String:
	return "d" if role == "a" else "a"


## Lato del combattimento a cui appartengono le unità del giocatore (o "" se non partecipa).
func my_role(seat: int) -> String:
	if eng.cb.is_empty() or str(eng.cb.get("type", "")) == "strike":
		return ""
	var ks := seat_ks(seat)
	if int(eng.cb["k"]) in ks:
		return "a"
	var dk: int = eng._def_controller()
	if dk in ks:
		return "d"
	for k in ks:
		if eng.allies(k, int(eng.cb["k"])):
			return "a"
		if eng.enemies(k, int(eng.cb["k"])):
			return "d"
	return ""


func _bm_window(w: String) -> bool:
	return w in ["bm_a", "bm_b", "bm_c"]


## Bersagli "unità, mostro o guarnigione" di un combattimento entro la portata.
func _combat_targets(id: String, caster: int, tome: String, roles: Array) -> Array:
	var out: Array = []
	var ch := caster_hex(caster)
	for r in roles:
		var h := _role_hex(r)
		if caster == -1 or in_range(id, ch, h, tome):
			out.append(r)
	return out


func _plays(seat: int, id: String, w: String, ctx: Dictionary, caster: int, tome: String) -> Array:
	var out: Array = []
	var bm := _bm_window(w)
	var me := my_role(seat) if bm else ""
	var ch := caster_hex(caster)
	var ks := seat_ks(seat)
	var k0: int = ks[0] if not ks.is_empty() else -1
	var crole := _combat_role_of(caster) if bm else ""
	match id:
		# ---------------------------------------------------- incantesimi di Magia di Battaglia
		"S01", "S02", "S03", "S07", "S09", "S25", "S28", "S51":
			if not bm:
				return out
			for r in _combat_targets(id, caster, tome, ["a", "d"]):
				var good: bool = r == me
				if id in ["S01", "S02", "S03"]:
					good = r != me
				if not good:
					continue
				if id == "S03":
					out.append(_mk(id, caster, r, 0, "−2 dadi leggeri"))
					out.append(_mk(id, caster, r, 1, "−1 dado pesante"))
				else:
					out.append(_mk(id, caster, r, 0, "a " + ("chi attacca" if r == "a" else "chi difende")))
		"S16":
			if w == "bm_b" and me == "d":
				for r in _combat_targets(id, caster, tome, ["a"]):
					out.append(_mk(id, caster, r))
		"S18":
			if bm and crole != "" and crole == me:
				out.append(_mk(id, caster, crole))
		"S19":
			if (w == "bm_b" and me == "d") or w == "r_strike":
				if eng.hand_count(p_of(seat), "spell") >= 2:
					var t := int(eng.cb["t"]) if not eng.cb.is_empty() else -1
					if t >= 0 and in_range(id, ch, t, tome):
						out.append(_mk(id, caster, t, 0, "annulla l'attacco"))
		"S30":
			if bm:
				for r in _combat_targets(id, caster, tome, ["a", "d"]):
					if _role_has(r, func(u): return u["kind"] == "army" and eng.has_ch(u, "feral")):
						out.append(_mk(id, caster, r, 0 if r == me else 1, "+1 pesante" if r == me else "−1 pesante"))
		"S32", "T01", "T10", "T11", "T16", "T33", "B307", "B505":
			if bm and crole != "" and crole == me:
				out.append(_mk(id, caster, crole))
		"S36":
			if bm:
				for r in _combat_targets(id, caster, tome, [me]):
					var h := _role_hex(r)
					var near := eng.is_lair(h)
					for n in eng.nbrs(h):
						if eng.is_lair(n):
							near = true
					if near:
						out.append(_mk(id, caster, r))
		"S37", "B110":
			if bm and crole != "" and crole == me:
				var a: Dictionary = eng.army_at(ch)
				if not a.is_empty() and eng.unit_dice(a).x > 0:
					out.append(_mk(id, caster, crole))
		"S39":
			if bm:
				for r in _combat_targets(id, caster, tome, [me]):
					var h := _role_hex(r)
					for n in eng.nbrs(h):
						if eng.is_sea(n):
							out.append(_mk(id, caster, r))
							break
		"S40":
			if bm:
				for r in _combat_targets(id, caster, tome, [me]):
					var h := _role_hex(r)
					var ok: bool = eng.terrain(h) == "s"
					for n in eng.nbrs(h):
						if eng.terrain(n) == "s":
							ok = true
					if ok:
						out.append(_mk(id, caster, r))
		"S41", "T20":
			if bm and (crole == me or caster == -1) and me != "":
				out.append(_mk(id, caster, me))
		"S44":
			if bm and me != "":
				for r in _combat_targets(id, caster, tome, [me]):
					out.append(_mk(id, caster, r))
		"S10", "S17":
			if id == "S17" and (w == "main" or bm):
				for u in eng.units:
					if u["kind"] == "army" and u["weak"] and int(u["h"]) >= 0 and eng.owner(u) in ks and in_range(id, ch, int(u["h"]), tome):
						out.append(_mk(id, caster, int(u["id"]), 0, eng.uname(u)))
			if id == "S10" and w == "r_elim":
				var h := int(ctx.get("h", -1))
				if h >= 0 and in_range(id, ch, h, tome):
					out.append(_mk(id, caster, h))
		"S13":
			if w == "r_hit":
				var h := int(ctx.get("h", -1))
				if h >= 0 and in_range(id, ch, h, tome) and _side_mine(seat, str(ctx.get("role", ""))):
					out.append(_mk(id, caster, h))
		"S14":
			if w == "r_strike":
				var h := int(ctx.get("src_h", -1))
				if h >= 0 and in_range(id, ch, h, tome):
					out.append(_mk(id, caster, h))
		"S15", "S42", "S34", "T03":
			if w == "r_cast":
				var lc: Dictionary = eng.last_cast
				if lc.is_empty() or int(lc.get("seat", -1)) == seat:
					return out
				if id == "S34":
					if str(D.card(lc["c"])["deck"]) == "spell" and int(lc.get("caster", -1)) >= 0 and eng.is_hero(eng.unit(int(lc["caster"]))):
						if in_range(id, ch, caster_hex(int(lc["caster"])), tome):
							out.append(_mk(id, caster, int(lc["caster"])))
				elif id == "S42":
					if str(D.card(lc["c"])["deck"]) == "spell":
						out.append(_mk(id, caster, int(lc["seat"])))
				elif id == "T03":
					if str(D.card(lc["c"])["deck"]) in ["spell", "blessing"]:
						out.append(_mk(id, caster, int(lc["seat"])))
				else:
					if caster >= 0:
						out.append(_mk(id, caster, int(lc["seat"])))
		"S26":
			if w == "r_moved":
				var h := int(ctx.get("h", -1))
				if h >= 0 and in_range(id, ch, h, tome) and eng.enemies(int(ctx["k"]), k0):
					var us: Array = eng.act_units()
					if not us.is_empty() and not eng.stack_has(us, "flying"):
						out.append(_mk(id, caster, h))
		"S47":
			if w == "r_sea":
				var h := int(ctx.get("h", -1))
				if h >= 0 and in_range(id, ch, h, tome) and eng.enemies(int(ctx["k"]), k0):
					out.append(_mk(id, caster, h))
		"S33", "T07":
			if w == "r_rolled" and me != "":
				if id == "S33":
					for r in _combat_targets(id, caster, tome, [_opp(me)]):
						out.append(_mk(id, caster, r))
				else:
					var k := int(eng.cb["k"]) if me == "a" else int(eng._def_controller())
					for b in p_of(seat)["hand"]:
						if str(D.card(b)["deck"]) == "blessing" and int(D.card(b)["k"]) == k:
							out.append(_mk(id, caster, me, 0, "scarta " + str(D.card(b)["n"])))
							break
		"S50":
			if w == "r_hit" and ch >= 0 and ch == int(ctx.get("h", -2)) and _side_mine(seat, str(ctx.get("role", ""))):
				var a: Dictionary = eng.army_at(ch)
				if not a.is_empty() and (a["weak"] or eng.has_ch(a, "fragile")):
					out.append(_mk(id, caster, ch))
		"T12":
			if w == "r_hit" and ch >= 0 and ch == int(ctx.get("h", -2)) and _side_mine(seat, str(ctx.get("role", ""))):
				out.append(_mk(id, caster, ch))
		"T14":
			if w == "r_strike" and ch >= 0 and ch == int(ctx.get("t", -2)):
				out.append(_mk(id, caster, ch))
		"T15", "T26":
			if bm and crole != "" and crole == me:
				out.append(_mk(id, caster, crole))
		"T27":
			if (w == "bm_b" and me == "d" and crole == "d" and eng.fort(ch) == 0) or (w == "r_strike" and ch == int(ctx.get("t", -2))):
				out.append(_mk(id, caster, ch))
		"T09":
			if bm and me == "a" and str(eng.cb["type"]) == "set" and eng.hand_count(p_of(seat), "spell") >= 3:
				out.append(_mk(id, caster, "a"))
		"T34":
			if bm and me != "":
				out.append(_mk(id, caster, me))
		# ---------------------------------------------------- assalti
		"S04", "S05", "S06", "S08", "S31", "S43", "S48", "S52":
			if w != "main" and not bm:
				return out
			if bm and not id in ["S43", "S52", "S48"]:
				return out
			for t in _strike_hexes(id, k0, ch, tome, bm):
				out.append(_mk(id, caster, t, 0, eng.hname(t)))
				if id in ["S06", "S08"] and eng.hand_count(p_of(seat), "spell") >= 2:
					out.append(_mk(id, caster, t, 1, eng.hname(t) + ", scarta un incantesimo (+1 pesante)"))
				if id == "S05" and eng.hand_count(p_of(seat), "spell") >= 2:
					out.append(_mk(id, caster, t, 1, eng.hname(t) + ", poi scarta e colpisci ancora"))
		"S35":
			if w == "main":
				for u in eng.units:
					if eng.is_hero(u) and int(u["h"]) >= 0 and eng.enemies(eng.owner(u), k0) and in_range(id, ch, int(u["h"]), tome) and eng.fort(int(u["h"])) == 0:
						out.append(_mk(id, caster, int(u["id"]), 0, eng.uname(u)))
		"S46":
			if w == "main":
				for t in D.hexes:
					if not eng.in_map(t):
						continue
					var mon: bool = eng.monsters.has(t) and not eng.monsters[t]["def"] and eng.enemies(int(eng.monsters[t]["cmd"]), k0)
					var lair: bool = eng.is_lair(t) and not eng.monsters.has(t) and not eng.abandoned.has(t)
					if not (mon or lair):
						continue
					for s in eng.inplay:
						if eng.welcoming(s, k0) and D.dist(s, t) <= 4:
							out.append(_mk(id, caster, t, 0, eng.hname(t)))
							break
		# ---------------------------------------------------- incantesimi principali
		"S11":
			if w == "main" and ch >= 0:
				var dest: Array = _free_hexes_near(ch, 1)
				for u in eng.units:
					if u["kind"] == "army" and int(u["h"]) >= 0 and eng.owner(u) in ks and in_range(id, ch, int(u["h"]), tome) and int(u["h"]) != ch:
						for d in dest:
							out.append(_mk(id, caster, "%d>%d" % [int(u["h"]), d], 0, "%s » %s" % [eng.uname(u), eng.hname(d)]))
		"S12":
			if w == "main":
				for u in eng.units:
					if u["kind"] == "army" and int(u["h"]) >= 0 and eng.owner(u) in ks and not u["fin"] and in_range(id, ch, int(u["h"]), tome):
						out.append(_mk(id, caster, int(u["id"]), 0, eng.uname(u)))
		"S20", "B001":
			if w == "main":
				var rr := 3 if id == "S20" else 5
				for h in _wander_hexes(rr, false):
					out.append(_mk(id, caster, h, 0, eng.hname(h)))
		"S29":
			if w == "main":
				for h in _wander_hexes(0, true):
					out.append(_mk(id, caster, h, 0, eng.hname(h)))
		"S21":
			if w == "main" and caster >= 0:
				var u0: Dictionary = eng.unit(caster)
				if not u0.is_empty():
					for d in D.hexes:
						if eng.in_map(d) and d != ch and D.dist(ch, d) <= 2 and _legal_for_stack(eng.units_at(ch).filter(func(x): return eng.owner(x) == eng.owner(u0)), d):
							out.append(_mk(id, caster, d, 0, eng.hname(d)))
		"S23":
			if w == "main" and eng.hand_count(p_of(seat), "spell") - 1 < 3:
				out.append(_mk(id, caster, -1))
		"S24":
			if w == "main":
				out.append(_mk(id, caster, -1))
		"S27":
			if w == "main":
				for u in eng.units:
					if u["kind"] == "army" and int(u["h"]) >= 0 and eng.enemies(eng.owner(u), k0) and in_range(id, ch, int(u["h"]), tome):
						out.append(_mk(id, caster, int(u["id"]), 0, eng.uname(u)))
		"S38", "T06", "T13", "T28":
			if w == "main" and caster >= 0 and not eng.unit(caster)["fin"]:
				out.append(_mk(id, caster, ch))
		"S45":
			if w == "main" and caster >= 0:
				var adj := false
				for n in eng.nbrs(ch):
					if eng.is_lair(n):
						adj = true
				if adj:
					var us: Array = eng.units_at(ch).filter(func(x): return eng.owner(x) == k0)
					for l in D.hexes:
						if not eng.in_map(l) or not eng.is_lair(l) or D.dist(l, ch) <= 1:
							continue
						for n in eng.nbrs(l):
							if _legal_for_stack(us, n):
								out.append(_mk(id, caster, n, 0, eng.hname(n)))
								break
		"S49", "T32":
			if w == "main" and caster >= 0 and not eng.is_settlement(ch) and eng.unit(caster)["fin"]:
				out.append(_mk(id, caster, ch))
		# ---------------------------------------------------- tesori
		"T02", "T17", "T18", "T19":
			if w == "main":
				out.append(_mk(id, caster, -1))
		"T04":
			if w == "main" and eng.hand_count(p_of(seat), "spell") >= 3:
				out.append(_mk(id, caster, -1))
		"T05":
			if w == "main" and ch >= 0:
				for u in eng.units:
					if u["kind"] == "army" and int(u["h"]) >= 0 and (eng.owner(u) in ks or eng.allies(eng.owner(u), k0)) and int(u["h"]) != ch and D.dist(ch, int(u["h"])) <= 3:
						for d in _free_hexes_near(ch, 1):
							out.append(_mk(id, caster, "%d>%d" % [int(u["id"]), d], 0, "%s » %s" % [eng.uname(u), eng.hname(d)]))
		"T25":
			if w == "main":
				for u in eng.units:
					if u["kind"] == "army" and int(u["h"]) >= 0 and eng.owner(u) in ks:
						out.append(_mk(id, caster, int(u["id"]), 0, eng.uname(u)))
		"T29", "T30":
			if w == "main":
				for p in eng.players:
					if int(p["seat"]) != seat:
						out.append(_mk(id, caster, int(p["seat"]), 0, "a " + str(p["name"])))
		"T35", "T36":
			if w == "main" and _can_gain_hero(k0):
				out.append(_mk(id, caster, -1))
		# ---------------------------------------------------- benedizioni: Armata della Notte
		"B002", "B003", "B004":
			if w == "main" and ch >= 0:
				for u in eng.units:
					if u["kind"] == "army" and int(u["h"]) >= 0 and eng.enemies(eng.owner(u), D.NIGHT) and D.dist(ch, int(u["h"])) <= 1:
						var hu: int = int(u["h"])
						if eng.hero_at(hu).is_empty() and not eng.is_settlement(hu) and _enslaved_left() > 0:
							out.append(_mk(id, caster, int(u["id"]), 0, eng.uname(u)))
		"B005":
			if w == "main":
				out.append(_mk(id, caster, -1))
		"B006", "B008":
			if w == "r_coven":
				out.append(_mk(id, caster, int(ctx.get("h", -1))))
		"B007", "B104", "B203", "B407", "B509":
			if (w == "main" or bm) and _can_gain_hero(int(card(id)["k"])):
				if id == "B509" and not bm:
					return out
				out.append(_mk(id, caster, -1))
		"B009":
			if w == "r_elim":
				var dead: Dictionary = ctx.get("u", {})
				if not dead.is_empty() and int(dead["id"]) == caster:
					for s in eng.inplay:
						if eng.controller(s) == D.NIGHT and eng.hero_at(s).is_empty():
							out.append(_mk(id, caster, s, 0, eng.hname(s)))
		"B010":
			if bm:
				for r in _combat_targets(id, caster, tome, [me]):
					if _role_has(r, func(u): return u["kind"] == "army" and eng.has_ch(u, "feral") and eng.owner(u) == D.NIGHT):
						out.append(_mk(id, caster, r))
		# ---------------------------------------------------- Impero
		"B101":
			if w == "main" and int(eng.kd[D.EMPIRE]["revolts"]) > 0 and not eng._no_suppress():
				for x in range(1, mini(int(eng.kd[D.EMPIRE]["gold"]), (int(eng.kd[D.EMPIRE]["revolts"]) + 1) / 2) + 1):
					out.append(_mk(id, caster, x, 0, "%d oro" % x))
		"B102":
			if w == "main" and not eng.available(D.EMPIRE, "e_cata").is_empty():
				for nm in ["Placidia", "Aureliana"]:
					var h := D.hex_of(nm)
					if eng.in_map(h) and eng.controller(h) == D.EMPIRE and eng.army_at(h).is_empty():
						out.append(_mk(id, caster, h, 0, nm))
		"B103":
			if w == "main":
				for n in range(1, 5):
					out.append(_mk(id, caster, n, 0, "%d dadi" % n))
		"B105":
			if w == "main":
				if not eng.available(D.EMPIRE, "e_akri").is_empty():
					out.append(_mk(id, caster, -1, 0, "3 Akritoi gratis"))
				if int(eng.kd[D.EMPIRE]["revolts"]) > 0 and not eng._no_suppress():
					out.append(_mk(id, caster, -1, 1, "reprimi 3 rivolte"))
		"B106", "B107", "B108", "B109":
			if bm and me != "" and eng.owner(_role_units(me)[0]) == D.EMPIRE if not _role_units(me).is_empty() else false:
				var ok := false
				for u in _role_units(me):
					if u["kind"] != "army":
						if id == "B107" and eng.has_ab(u, "ranged"):
							ok = true
						continue
					if id == "B106" and u["t"] in ["e_cata", "e_kors"]:
						ok = true
					if id == "B107" and eng.has_ab(u, "ranged"):
						ok = true
					if id == "B108" and not eng.has_ch(u, "fragile"):
						ok = true
					if id == "B109":
						ok = true
				if ok:
					if id == "B109":
						for n in range(1, 4):
							out.append(_mk(id, caster, me, n, "+%d pesanti, %d rivolte" % [n, n]))
					else:
						out.append(_mk(id, caster, me))
		# ---------------------------------------------------- Fjordland
		"B201", "B202", "B205", "B206", "B207", "B208", "B209", "B210":
			if not bm or me == "":
				return out
			var us: Array = _role_units(me)
			var fj := false
			for u in us:
				if eng.owner(u) == D.FJORD:
					fj = true
			if not fj and not (id == "B207" and me == "d" and eng.controller(int(eng.cb["t"])) == D.FJORD):
				return out
			var h := _role_hex(me)
			var oh := _role_hex(_opp(me))
			match id:
				"B201":
					if caster >= 0 and in_range(id, ch, h, tome) and (eng.is_coastal(h) or bool(D.hexes[h]["mr"]) or (me == "a" and (eng.is_coastal(oh) or bool(D.hexes[oh]["mr"]) or D.hexes[oh]["lair"] == "S"))):
						out.append(_mk(id, caster, me))
				"B202":
					if caster >= 0 and in_range(id, ch, h, tome) and (eng.is_wild(h) or (me == "a" and eng.is_wild(oh))):
						out.append(_mk(id, caster, me))
				"B205":
					if crole == me:
						out.append(_mk(id, caster, me))
				"B206":
					if _role_has(me, func(u): return _is_army_t(u, ["f_bers"])):
						out.append(_mk(id, caster, me))
				"B207":
					if me == "d":
						out.append(_mk(id, caster, me))
				"B208", "B209":
					out.append(_mk(id, caster, me))
				"B210":
					if _role_has(me, func(u): return _is_army_t(u, ["f_rang"])):
						out.append(_mk(id, caster, me))
		"B204":
			if w == "main" and eng.hand_count(p_of(seat), "spell") >= 2:
				out.append(_mk(id, caster, -1))
		# ---------------------------------------------------- Goblin
		"B301", "B305", "B308", "B310":
			if not bm or me == "":
				return out
			if not _role_has(me, func(u): return eng.owner(u) == D.GOBLIN):
				return out
			match id:
				"B301":
					if _role_has(me, func(u): return _is_army_t(u, ["g_warr", "g_snea", "g_elit"]) or (u["kind"] == "hero" and eng.owner(u) == D.GOBLIN)):
						out.append(_mk(id, caster, me))
				"B305":
					if me == "a":
						out.append(_mk(id, caster, me))
				"B308":
					if _role_has(me, func(u): return _is_army_t(u, ["g_snea"])):
						out.append(_mk(id, caster, me))
				"B310":
					if eng.hand_count(p_of(seat), "spell") >= 3:
						out.append(_mk(id, caster, me))
		"B303":
			if w == "main" and _can_gain_hero(D.GOBLIN):
				for hid in eng.kd[D.GOBLIN]["hero_pool"]:
					out.append(_mk(id, caster, hid, 0, str(D.card(hid)["n"])))
		"B304", "B408", "B501":
			if w == "main":
				var kk := int(card(id)["k"])
				for u in eng.units:
					if u["kind"] == "army" and int(u["h"]) >= 0 and eng.owner(u) == kk and not u["fin"]:
						if id == "B501" and (caster < 0 or not in_range(id, ch, int(u["h"]), tome)):
							continue
						out.append(_mk(id, caster, int(u["id"]), 0, eng.uname(u)))
		"B306":
			if w == "r_elim":
				var dead: Dictionary = ctx.get("u", {})
				if not dead.is_empty() and dead["kind"] == "army" and int(dead["k"]) == D.GOBLIN and _can_gain_hero(D.GOBLIN):
					out.append(_mk(id, caster, -1))
		"B309":
			if w == "main":
				for u in eng.units:
					if u["kind"] == "army" and int(u["h"]) >= 0 and eng.owner(u) == D.GOBLIN and D.UNITS[u["t"]].get("troll", false) and eng.is_mountain(int(u["h"])):
						for n in eng.nbrs(int(u["h"])):
							var a: Dictionary = eng.army_at(n)
							if not a.is_empty() and eng.enemies(eng.owner(a), D.GOBLIN) and eng.fort(n) == 0:
								out.append(_mk(id, caster, "%d>%d" % [int(u["id"]), n], 0, eng.hname(n)))
		# ---------------------------------------------------- Oathborn
		"B401":
			if w == "main":
				for u in eng.units:
					if int(u["h"]) >= 0 and eng.owner(u) == D.OATH and not u["fin"] and u["kind"] == "army":
						out.append(_mk(id, caster, int(u["id"]), 0, eng.uname(u)))
		"B402":
			if w == "r_mined":
				out.append(_mk(id, caster, int(ctx.get("h", -1))))
		"B403":
			if w == "main" and not eng._eff_global("secret_ways"):
				out.append(_mk(id, caster, -1))
		"B404":
			if w == "main":
				for h in eng.inplay:
					if eng.loyal(h) == D.OATH and eng.army_at(h).is_empty() and not (eng.ctrl.has(h) and eng.army_at(h).size() > 0):
						for t in D.UNIT_ORDER[D.OATH]:
							if int(D.UNITS[t]["cost"]) <= 4 and not eng.available(D.OATH, t).is_empty():
								out.append(_mk(id, caster, "%d>%s" % [h, t], 0, "%s a %s" % [D.UNITS[t]["n"], eng.hname(h)]))
		"B405":
			if w == "main" and eng.khazud < 0:
				for h in D.hexes:
					if _khazud_ok(h):
						out.append(_mk(id, caster, h, 0, eng.hname(h)))
		"B406":
			if w == "r_won":
				out.append(_mk(id, caster, -1))
		"B409":
			if w == "main":
				for u in eng.units:
					if u["kind"] == "army" and u["weak"] and int(u["h"]) >= 0 and eng.owner(u) == D.OATH:
						out.append(_mk(id, caster, int(u["id"]), 0, "recupera " + eng.uname(u)))
				if _can_gain_hero(D.OATH):
					out.append(_mk(id, caster, -1, 1, "ottieni un eroe"))
		"B410":
			if w == "main":
				var n := 0
				for u in eng.units:
					if u["kind"] == "army" and int(u["h"]) >= 0 and eng.owner(u) == D.OATH and D.UNITS[u["t"]].get("miner", false) and eng.is_mine(int(u["h"])):
						n += 1
				if n > 0:
					out.append(_mk(id, caster, n))
		# ---------------------------------------------------- Orchi
		"B502":
			if bm and crole == me and me != "":
				var a: Dictionary = eng.army_at(ch)
				if not a.is_empty() and a["t"] == "r_reav" and not a["weak"]:
					out.append(_mk(id, caster, me))
		"B503":
			if w == "main":
				var seen := {}
				for u in eng.units:
					if u["kind"] == "army" and int(u["h"]) >= 0 and eng.owner(u) == D.ORC:
						for n in eng.nbrs(int(u["h"])):
							if seen.has(n):
								continue
							for x in eng.units_at(n):
								if eng.enemies(eng.owner(x), D.ORC):
									seen[n] = true
									out.append(_mk(id, caster, "%d>%d" % [int(u["id"]), n], 0, eng.hname(n)))
									break
		"B504", "B506":
			if w == "main":
				out.append(_mk(id, caster, -1))
		"B507", "B508":
			if bm and me != "" and _role_has(me, func(u): return _is_army_t(u, ["r_reav"])):
				out.append(_mk(id, caster, me))
		"B510":
			if w == "r_rolled" and me != "" and _role_has(me, func(u): return u["kind"] == "army" and eng.owner(u) == D.ORC):
				out.append(_mk(id, caster, me))
		# ---------------------------------------------------- poteri degli eroi
		"H011":
			pass
		"H012", "H317", "H413":
			if w == "main" and caster >= 0:
				for n in eng.nbrs(ch):
					if id == "H012":
						var tgt := false
						for x in eng.units_at(n):
							if eng.is_hero(x) and eng.enemies(eng.owner(x), k0):
								tgt = true
						if eng.monsters.has(n) and not eng.monsters[n]["def"] and eng.enemies(int(eng.monsters[n]["cmd"]), k0):
							tgt = true
						if tgt:
							out.append(_mk(id, caster, n, 0, eng.hname(n)))
					elif eng.strike_target_ok(k0, n):
						out.append(_mk(id, caster, n, 0, eng.hname(n)))
						if id == "H413" and eng.hand_count(p_of(seat), "spell") >= 1:
							out.append(_mk(id, caster, n, 1, eng.hname(n) + ", scarta (+1 pesante)"))
		"H111":
			if w == "main" and caster >= 0:
				for t in D.hexes:
					if eng.in_map(t) and t != ch and D.dist(ch, t) <= 2 and eng.strike_target_ok(k0, t):
						out.append(_mk(id, caster, t, 0, eng.hname(t)))
		"H112":
			if w == "main" and int(eng.kd[D.EMPIRE]["revolts"]) > 0 and not eng._no_suppress():
				out.append(_mk(id, caster, -1))
		"H214":
			if w == "main" and caster >= 0:
				for u in eng.units:
					if u["kind"] == "army" and int(u["h"]) >= 0 and eng.owner(u) == D.FJORD and D.dist(ch, int(u["h"])) <= 2 and not eng.has_ab(u, "regen"):
						out.append(_mk(id, caster, int(u["id"]), 0, eng.uname(u)))
		"H512":
			if w == "main" and caster >= 0:
				for u in eng.units:
					if u["kind"] != "army" or int(u["h"]) < 0 or not eng.enemies(eng.owner(u), D.ORC) or D.dist(ch, int(u["h"])) > 3:
						continue
					for n in eng.nbrs(int(u["h"])):
						var b: Dictionary = eng.army_at(n)
						if not b.is_empty() and eng.enemies(eng.owner(b), D.ORC) and D.dist(ch, n) <= 3 and eng.fort(n) == 0:
							out.append(_mk(id, caster, "%d>%d" % [int(u["id"]), int(b["id"])], 0, "%s colpisce %s" % [eng.uname(u), eng.uname(b)]))
		"H514":
			if w == "main" and caster >= 0:
				for n in eng.nbrs(ch):
					var a: Dictionary = eng.army_at(n)
					if not a.is_empty() and eng.enemies(eng.owner(a), D.ORC):
						out.append(_mk(id, caster, n, 0, eng.hname(n)))
		"H014":
			if bm and crole == me and me != "":
				var h := _role_hex(me) if me == "d" else int(eng.cb["t"])
				if eng.is_wild(h):
					out.append(_mk(id, caster, _opp(me), 0, "−2 leggeri all'avversario"))
					out.append(_mk(id, caster, _opp(me), 1, "−1 pesante all'avversario"))
		"H115":
			if bm and me != "":
				var oh := _role_hex(_opp(me))
				if D.dist(ch, oh) <= 1:
					out.append(_mk(id, caster, _opp(me)))
		"H116", "H217", "H416", "H211", "H216", "H215", "H516":
			if bm and crole == me and me != "":
				if id == "H216":
					var a: Dictionary = eng.army_at(ch)
					if a.is_empty() or a["t"] != "f_free":
						return out
				out.append(_mk(id, caster, me))
		"H313":
			if bm and crole == "a" and me == "a" and str(eng.cb["type"]) == "set" and eng.fort(int(eng.cb["t"])) > 0:
				out.append(_mk(id, caster, me))
		"H412":
			if bm and crole == me and me != "" and eng.hand_count(p_of(seat), "spell") >= 1:
				out.append(_mk(id, caster, me))
		"H511":
			if bm and crole == me and me != "" and eng.hand_count(p_of(seat), "spell") >= 1:
				out.append(_mk(id, caster, me))
		"H213":
			if w == "r_elim":
				var dead: Dictionary = ctx.get("u", {})
				if not dead.is_empty() and dead["kind"] == "hero" and int(dead["k"]) == D.FJORD and int(dead["h"]) >= 0 and D.dist(ch, int(dead["h"])) <= 4 and int(dead["id"]) != caster:
					for d in _free_hexes_near(ch, 1):
						if d != ch:
							out.append(_mk(id, caster, d, 0, eng.hname(d)))
							break
	# le carte di Magia di Battaglia non si giocano fuori dal combattimento
	if not bm:
		out = out.filter(func(p): return not (card(p["c"]).get("bm", false) and not p["c"] in ["T09"]))
	# Cuor di Gelo: niente incantesimi contro di lui in Magia di Battaglia
	if bm and str(card(id)["deck"]) == "spell" and me != "":
		for u in _role_units(_opp(me)):
			if u["t"] == "H114":
				return []
	return out


func _side_mine(seat: int, role: String) -> bool:
	return role != "" and my_role(seat) == role or (role == "d" and eng.cb.get("strike", false) and _strike_victim(seat))


func _strike_victim(seat: int) -> bool:
	var t := int(eng.cb.get("t", -1))
	for u in eng.units_at(t):
		if eng.owner(u) in seat_ks(seat):
			return true
	return false


func _strike_hexes(id: String, k: int, ch: int, tome: String, bm: bool) -> Array:
	var out: Array = []
	if bm:
		var t := int(eng.cb["t"]) if my_role(eng.seat_of[k]) == "a" else int(eng.cb["from"])
		if ch >= 0 and in_range(id, ch, t, tome) and eng.fort(t) == 0:
			out.append(t)
		return out
	for t in D.hexes:
		if not eng.in_map(t):
			continue
		if ch >= 0 and not in_range(id, ch, t, tome):
			continue
		if ch < 0 and id != "S46":
			continue
		var ok := false
		match id:
			"S04":
				for x in [t] + eng.nbrs(t):
					if eng.strike_target_ok(k, x, true) and eng.fort(x) < 2:
						ok = true
			"S05":
				var f: bool = eng.is_forest(t)
				for n in eng.nbrs(t):
					if eng.is_forest(n):
						f = true
				ok = f and eng.strike_target_ok(k, t)
			"S06":
				var sea := false
				for n in eng.nbrs(t):
					if eng.is_sea(n):
						sea = true
				ok = sea and eng.strike_target_ok(k, t)
			"S08":
				var m: bool = eng.is_mountain(t)
				for n in eng.nbrs(t):
					if eng.is_mountain(n):
						m = true
				ok = m and eng.strike_target_ok(k, t)
			_:
				ok = eng.strike_target_ok(k, t)
		if ok:
			out.append(t)
	return out


func _free_hexes_near(h: int, r: int) -> Array:
	var out: Array = []
	var cand: Array = [h]
	if r >= 1:
		cand.append_array(eng.nbrs(h))
	for n in cand:
		if eng.in_map(n) and not eng.is_sea(n) and not eng.is_lair(n) and not eng.monsters.has(n) and eng.army_at(n).is_empty() and not eng.posture(n, eng.cur_k) in ["hostile", "inert"]:
			out.append(n)
	return out


func _legal_for_stack(us: Array, h: int) -> bool:
	if us.is_empty():
		return false
	return eng.enter_kind(eng.owner(us[0]), us, h, eng.stack_has(us, "flying")) == 2


func _wander_hexes(rr: int, sea: bool) -> Array:
	var out: Array = []
	for h in D.hexes:
		if not eng.in_map(h) or eng.monsters.has(h) or eng.is_lair(h) or eng.set_idx(h) >= 0 or not eng.units_at(h).is_empty():
			continue
		if sea:
			if not eng.is_sea(h):
				continue
			var ok := false
			for n in eng.nbrs(h):
				if eng.is_coastal(n):
					ok = true
			if ok:
				out.append(h)
		else:
			if eng.is_sea(h):
				continue
			for l in D.hexes:
				if eng.in_map(l) and eng.is_lair(l) and D.hexes[l]["lair"] == "L" and D.dist(l, h) <= rr and (rr == 3 or not eng.monsters.has(l)):
					out.append(h)
					break
	return out


func _khazud_ok(h: int) -> bool:
	if not eng.in_map(h) or not eng.is_mountain(h) or eng.is_mine(h) or eng.is_lair(h) or eng.set_idx(h) >= 0:
		return false
	if not eng.units_at(h).is_empty() or eng.monsters.has(h):
		return false
	for n in eng.nbrs(h):
		if eng.set_idx(n) >= 0 or eng.is_lair(n) or not eng.edge(h, n).is_empty() and eng.edge(h, n).get("road", false):
			return false
	return true


func _enslaved_left() -> int:
	var n := 0
	for u in eng.units:
		if u["kind"] == "ehero" and int(u["h"]) >= 0:
			n += 1
	return D.ENSLAVED_NUM - n


func _can_gain_hero(k: int) -> bool:
	if not eng.kd.has(k) or eng.kd[k]["hero_pool"].is_empty():
		return false
	for u in eng.armies_on_map(k):
		if eng.hero_at(int(u["h"])).is_empty():
			return true
	return false


# ================================================================== risoluzione

func _discard_card(seat: int, id: String) -> void:
	var p: Dictionary = p_of(seat)
	var deck := str(card(id)["deck"])
	if deck == "hero":
		return
	p["hand"].erase(id)
	match deck:
		"spell":
			eng.spell_disc.append(id)
		"blessing":
			eng.bless_disc.append(id)
		"treasure":
			if card(id).get("elim_card", false):
				eng.tre_out.append(id)
			elif not id in ["T29", "T30"]:
				p["owned"].append(id)


func _discard_random_spell(seat: int) -> String:
	var p: Dictionary = p_of(seat)
	var sp: Array = []
	for c in p["hand"]:
		if str(card(c)["deck"]) == "spell":
			sp.append(c)
	if sp.is_empty():
		return ""
	var c2: String = sp[eng.rng.randi_range(0, sp.size() - 1)]
	p["hand"].erase(c2)
	eng.spell_disc.append(c2)
	return c2


func _discard_chosen_spell(seat: int, keep: String) -> void:
	var p: Dictionary = p_of(seat)
	for c in p["hand"]:
		if str(card(c)["deck"]) == "spell" and c != keep:
			p["hand"].erase(c)
			eng.spell_disc.append(c)
			return


func _mod(role: String, key: String, v) -> void:
	var m: Dictionary = eng.cb["mods"][role]
	if v is bool:
		m[key] = v
	else:
		m[key] = int(m.get(key, 0)) + int(v)


func _gain_hero(k: int, chosen := "", army_id := -1) -> Dictionary:
	var arms: Array = []
	for a in eng.armies_on_map(k):
		if eng.hero_at(int(a["h"])).is_empty():
			arms.append(a)
	if arms.is_empty():
		return {}
	var target: Dictionary = arms[0]
	if army_id >= 0:
		for a in arms:
			if int(a["id"]) == army_id:
				target = a
	elif not eng.cb.is_empty() and str(eng.cb.get("type", "")) != "strike":
		for a in arms:
			if int(a["h"]) == int(eng.cb["from"]) or int(a["h"]) == int(eng.cb["t"]):
				target = a
	var hu: Dictionary = eng._take_hero(k, chosen)
	if hu.is_empty():
		return {}
	hu["h"] = int(target["h"])
	hu["fin"] = target["fin"]
	eng.log_msg("%s ottiene l'eroe %s, che si unisce a %s." % [eng.kn(k), eng.uname(hu), eng.uname(target)])
	eng.fx.emit("build", {"id": hu["id"], "h": hu["h"]})
	return hu


func _kill_caster(caster: int) -> void:
	if caster >= 0:
		var u: Dictionary = eng.unit(caster)
		if not u.is_empty():
			eng.log_msg("%s si sacrifica." % eng.uname(u))
			eng._eliminate(u, "")


## Gioca una carta: la toglie dalla mano, la annuncia, apre la reazione «cast» agli avversari
## e, se non è annullata, ne applica l'effetto.
func resolve(seat: int, pl: Dictionary, w: String) -> void:
	var id := str(pl["c"])
	var cd := card(id)
	var p: Dictionary = p_of(seat)
	var caster := int(pl.get("caster", -1))
	var deck := str(cd["deck"])
	if deck == "hero":
		if cd.get("lock", false):
			_lock(id)
	_discard_card(seat, id)
	if cd.get("discard", false):
		_discard_chosen_spell(seat, "")
	var tome := str(pl.get("tome", ""))
	if tome != "" and tome in p["hand"]:
		_discard_card(seat, tome)
	var who := str(p["name"])
	eng.log_msg("• %s gioca [b]%s[/b]%s%s." % [who, cd["n"], (" (lanciata da %s)" % _caster_name(caster)) if caster != -1 else "", (" con %s" % card(tome)["n"]) if tome != "" else ""])
	eng.fx.emit("card", {"seat": seat, "c": id, "caster": caster})
	if _bm_window(w):
		if not played_bm.has(seat):
			played_bm[seat] = []
		played_bm[seat].append(id)
	eng.last_cast = {"seat": seat, "c": id, "caster": caster, "canceled": false}
	if deck != "hero" and id != "S15":
		await window("cast", {"seat": seat})
	if eng.last_cast.get("canceled", false):
		eng.log_msg("L'effetto di %s è annullato." % cd["n"])
		return
	# Lilith: quando lancia un incantesimo o una benedizione con Mago pesca una carta dello stesso tipo
	if caster >= 0 and eng.unit(caster).get("t", "") == "H011" and cd.get("mage", false) and deck in ["spell", "blessing"] and not hero_locked("H011"):
		_lock("H011")
		if deck == "spell":
			eng._draw_spell(p)
		else:
			eng._draw_blessing(p, D.NIGHT)
		eng.log_msg("Lilith attinge alla Marea Silenziosa e pesca una carta.")
	await _effect(seat, pl, w)
	if tome != "":
		await _tome(seat, tome, pl)
	_clean_cb()
	eng.changed.emit()


## Un effetto da combattimento giocato fuori da un combattimento non deve lasciare un combattimento "fantasma".
func _clean_cb() -> void:
	if not eng.cb.is_empty() and not eng.cb.has("t"):
		eng.cb = {}


func _caster_name(c: int) -> String:
	if c <= -1000:
		return D.monster(eng.monsters[-1000 - c]["m"])["n"]
	var u: Dictionary = eng.unit(c)
	return eng.uname(u) if not u.is_empty() else "?"


func _tome(seat: int, tome: String, pl: Dictionary) -> void:
	var p: Dictionary = p_of(seat)
	match tome:
		"S22":
			eng._draw_spell(p)
			var k := _seat_k(seat)
			eng._draw_blessing(p, k)
		"T21":
			for q in eng.players:
				if int(q["seat"]) != seat and _seat_enemy(seat, int(q["seat"])):
					var c := ""
					for x in q["hand"]:
						if str(card(x)["deck"]) in ["spell", "blessing"]:
							c = x
							break
					if c != "":
						q["hand"].erase(c)
						(eng.spell_disc if str(card(c)["deck"]) == "spell" else eng.bless_disc).append(c)
						eng.log_msg("%s deve scartare %s." % [q["name"], card(c)["n"]])
					break
		"T22", "T31":
			if not eng.cb.is_empty() and _combat_role_of(int(pl["caster"])) != "":
				_mod(_combat_role_of(int(pl["caster"])), "l", 1)
		"T23":
			eng._draw_spell(p)
		"T24":
			eng._draw_blessing(p, _seat_k(seat))


func _seat_k(seat: int) -> int:
	var ks := seat_ks(seat)
	return ks[0] if not ks.is_empty() else int(eng.players[seat]["ks"][0])


func _seat_enemy(a: int, b: int) -> bool:
	var ka := _seat_k(a)
	var kb := _seat_k(b)
	return eng.enemies(ka, kb)


func _eff(e: Dictionary) -> void:
	eng.effects.append(e)


## Effetto di ogni carta.
func _effect(seat: int, pl: Dictionary, w: String) -> void:
	var id := str(pl["c"])
	var caster := int(pl.get("caster", -1))
	var t = pl.get("t", -1)
	var o := int(pl.get("o", 0))
	var p: Dictionary = p_of(seat)
	var k := _seat_k(seat)
	var ck := caster_k(caster, seat)
	var ch := caster_hex(caster)
	var tome := str(pl.get("tome", ""))
	match id:
		"S01":
			_mod(str(t), "minus_h", 1)
		"S02":
			_mod(str(t), "minus_l", 1)
		"S03":
			_mod(str(t), "minus_l" if o == 0 else "minus_h", 2 if o == 0 else 1)
		"S07":
			_mod(str(t), "l", 1)
			_mod(str(t), "ranged", true)
		"S09":
			_mod(str(t), "l", 1)
			_mod(str(t), "stealth", true)
		"S25":
			_mod(str(t), "conv", 1)
		"S28", "S36":
			_mod(str(t), "h", 1)
		"S51":
			_mod(str(t), "l", 1)
		"S16":
			eng.cb["canceled"] = true
			for u in eng.side_units("a"):
				u["fin"] = true
			eng.log_msg("L'armata che attaccava si addormenta.")
		"S18":
			_mod(str(t), "l", 1)
			_mod(str(t), "h", 1)
			_kill_caster(caster)
		"S19":
			eng.cb["canceled"] = true
		"S30":
			_mod(str(t), "h" if o == 0 else "minus_h", 1)
		"S32":
			_mod(str(t), "l", 2)
		"S37", "B110":
			_mod(str(t), "x2l", true)
		"S39":
			_mod(str(t), "l", 3)
		"S40":
			_mod(str(t), "h", 2)
		"S41":
			_mod(str(t), "darts", true)
		"T20":
			_mod(str(t), "diamond", true)
		"S44":
			_mod(str(t), "fester", true)
		"S10":
			eng._draw_spell(p)
			for u in eng.units:
				if u["kind"] == "army" and u["weak"] and int(u["h"]) >= 0 and eng.owner(u) in seat_ks(seat):
					u["weak"] = false
					eng.log_msg("%s torna a piena forza." % eng.uname(u))
					break
		"S17":
			var u2: Dictionary = eng.unit(int(t))
			if not u2.is_empty():
				u2["weak"] = false
				eng.log_msg("%s guarisce." % eng.uname(u2))
				eng.fx.emit("recover", {"id": u2["id"]})
		"S13":
			var neg := 0
			for i in range(3):
				if eng.d6() >= 5:
					neg += 1
			if not eng.cb.is_empty():
				eng.cb["negate"] = int(eng.cb.get("negate", 0)) + neg
			eng.log_msg("Il Riparo della Marea annulla %d colp%s." % [neg, "o" if neg == 1 else "i"])
		"S50", "T12":
			if not eng.cb.is_empty():
				eng.cb["negate"] = int(eng.cb.get("negate", 0)) + 1
			if id == "T12" and caster >= 0:
				var u3: Dictionary = eng.unit(caster)
				for d in _free_hexes_near(int(u3["h"]), 1):
					if d != int(u3["h"]) and eng.hero_at(d).is_empty():
						u3["h"] = d
						eng.fx.emit("move", {"ids": [caster], "from": ch, "to": d, "ship": false})
						break
		"S14":
			eng.cb["canceled"] = true
		"S15":
			eng.last_cast["canceled"] = true
			_kill_caster(caster)
		"T03":
			eng.last_cast["canceled"] = true
			var victim: Dictionary = eng.players[int(eng.last_cast["seat"])]
			var dk := str(card(eng.last_cast["c"])["deck"])
			if dk == "spell":
				eng._draw_spell(victim)
			else:
				eng._draw_blessing(victim, int(card(eng.last_cast["c"])["k"]))
		"S42":
			var c2 := _discard_random_spell(int(t))
			if c2 != "":
				eng.log_msg("%s scarta a caso %s." % [eng.players[int(t)]["name"], card(c2)["n"]])
		"S34":
			var hu: Dictionary = eng.unit(int(t))
			if not hu.is_empty():
				eng.log_msg("%s è trascinato a Meji." % eng.uname(hu))
				eng._eliminate(hu, "")
		"S26":
			for u in eng.act_units():
				u["fin"] = true
			eng.act["mud"] = true
			eng.log_msg("La terra diventa fango: la pila non può più agire.")
		"S47":
			var us: Array = eng.act_units()
			if not us.is_empty():
				var a3: Dictionary = eng.army_at(int(us[0]["h"]))
				var tgt: Dictionary = a3 if not a3.is_empty() else us[0]
				await eng._hit_unit(tgt)
		"S33":
			var r: Dictionary = eng.cb["ra"] if str(t) == "a" else eng.cb["rd"]
			_mod(str(t), "nsucc", 1)
			r["weak"] = true
		"T07":
			for b in p["hand"]:
				if str(D.card(b)["deck"]) == "blessing":
					p["hand"].erase(b)
					eng.bless_disc.append(b)
					break
			_reroll(str(t))
		"B510":
			_reroll(str(t))
			eng.cb["after_hit_" + str(t)] = "orc"
		# assalti
		"S04":
			for x in [int(t)] + eng.nbrs(int(t)):
				if eng.strike_target_ok(ck, x, true) and eng.fort(x) < 2:
					await eng.strike(ck, Vector2i(2, 0), x, {"src": "spell", "h": ch, "no_react": true})
		"S05":
			await eng.strike(ck, Vector2i(1, 1), int(t), {"src": "spell", "h": ch})
			if o == 1 and eng.hand_count(p, "spell") >= 1 and eng.strike_target_ok(ck, int(t)):
				_discard_chosen_spell(seat, "")
				await eng.strike(ck, Vector2i(1, 1), int(t), {"src": "spell", "h": ch})
		"S06", "S08":
			if o == 1:
				_discard_chosen_spell(seat, "")
			await eng.strike(ck, Vector2i(0, 2 + o), int(t), {"src": "spell", "h": ch})
		"S31":
			await eng.strike(ck, Vector2i(2, 0), int(t), {"src": "spell", "h": ch})
		"S43":
			await _strike_or_combat(ck, Vector2i(0, 1), int(t), ch)
		"S48":
			await _strike_or_combat(ck, Vector2i(2, 0), int(t), ch)
		"S52":
			await _strike_or_combat(ck, Vector2i(1, 0), int(t), ch)
		"S35":
			var hu2: Dictionary = eng.unit(int(t))
			if not hu2.is_empty():
				var hh := int(hu2["h"])
				var r2: Dictionary = eng.roll(Vector2i(2, 0), 0, "a")
				var hits := 0 if int(r2["s"]) == 0 else 1 + int(r2["extra"])
				eng._log_roll("Possessione", Vector2i(2, 0), r2, int(r2["s"]))
				if hits > 0:
					eng.log_msg("%s è posseduto e cade." % eng.uname(hu2))
					await eng._kill(hu2, "")
					_gain_hero(ck)
				else:
					eng.log_msg("La possessione fallisce.")
					_kill_caster(caster)
				eng.changed.emit()
				hh = hh
		"S46":
			eng.cb = {"k": ck, "a": [], "from": int(t), "t": int(t), "type": "strike", "mods": {"a": {}, "d": {}}, "canceled": false, "reward_minus": 1}
			if not eng.monsters.has(int(t)):
				await eng._lair_monster(int(t), ck)
			if eng.monsters.has(int(t)):
				var r3: Dictionary = eng.roll(Vector2i(0, 2), 0, "a")
				eng._log_roll("Pugno a Quattro Dita", Vector2i(0, 2), r3, int(r3["s"]))
				if int(r3["s"]) > 0:
					await eng._monster_defeated(int(t), ck, true, true)
			eng.cb = {}
		# movimento e posizionamento
		"S11", "T05":
			var parts: PackedStringArray = str(t).split(">")
			var from := int(parts[0])
			var dest := int(parts[1])
			var us2: Array = []
			if id == "T05":
				var a4: Dictionary = eng.unit(from)
				if not a4.is_empty():
					us2 = [a4]
					var hh2: Dictionary = eng.hero_at(int(a4["h"]))
					if not hh2.is_empty() and eng.owner(hh2) == eng.owner(a4):
						us2.append(hh2)
			else:
				for u in eng.units_at(from):
					if eng.owner(u) in seat_ks(seat):
						us2.append(u)
			if not us2.is_empty() and _legal_for_stack(us2, dest):
				var fr := int(us2[0]["h"])
				for u in us2:
					u["h"] = dest
				eng.fx.emit("move", {"ids": us2.map(func(x): return x["id"]), "from": fr, "to": dest, "ship": false})
				eng.log_msg("%s compare a %s." % [eng._stack_name(us2), eng.hname(dest)])
		"S12":
			_eff({"dur": "next", "u": int(t), "freeship": true})
		"S20", "B001", "S29":
			var pool: Array = eng.pool_sea if id == "S29" else eng.pool_land
			if not pool.is_empty():
				var mid: String = pool.pop_front()
				eng.monsters[int(t)] = {"m": mid, "def": false, "cmd": ck, "fin": false, "wander": true}
				eng.log_msg("Un mostro errante compare a %s: %s, al comando di %s." % [eng.hname(int(t)), D.monster(mid)["n"], eng.kn(ck)])
				eng.fx.emit("monster", {"h": int(t)})
		"S21", "S45":
			var us3: Array = []
			for u in eng.units_at(ch):
				if eng.owner(u) == ck:
					us3.append(u)
			for u in us3:
				u["h"] = int(t)
				if id == "S45":
					u["fin"] = true
			eng.fx.emit("move", {"ids": us3.map(func(x): return x["id"]), "from": ch, "to": int(t), "ship": false})
			eng.log_msg("%s si sposta a %s." % [eng._stack_name(us3), eng.hname(int(t))])
		"S23":
			_kill_caster(caster)
			while eng.hand_count(p, "spell") < 3:
				if eng._draw_spell(p) == "":
					break
		"S24":
			_kill_caster(caster)
			eng._draw_blessing(p, k)
			eng._draw_blessing(p, k)
		"S27":
			var u4: Dictionary = eng.unit(int(t))
			if not u4.is_empty():
				await _fear(u4)
		"S38":
			for u in eng.units_at(ch):
				if eng.owner(u) == ck:
					_eff({"dur": "next", "u": int(u["id"]), "mv": 2})
		"S49", "T32":
			for u in eng.units_at(ch):
				if eng.owner(u) == ck:
					u["fin"] = false
			eng.log_msg("La pila di %s è di nuovo pronta." % _caster_name(caster))
		"T06":
			for u in eng.units_at(ch):
				if eng.owner(u) == ck:
					_eff({"dur": "next", "u": int(u["id"]), "ab": "flying", "ch_feral": true})
		"T13":
			_eff({"dur": "turn", "u": caster, "ab": "flying", "ch_feral": true})
			_eff({"dur": "turn", "u": caster, "dice_l": 1})
		"T28":
			for u in eng.units_at(ch):
				if eng.owner(u) == ck:
					_eff({"dur": "next", "u": int(u["id"]), "mv": 2, "ch_feral": true})
		"T25":
			_eff({"dur": "turn", "u": int(t), "ab": "regen"})
		"T02":
			pass
		"T04":
			_discard_random_spell(seat)
			eng.kd[k]["gold"] += 2
		"T17", "T18", "T19":
			eng.kd[k]["gold"] += {"T17": 3, "T18": 4, "T19": 5}[id]
		"T29", "T30":
			p["owned"].erase(id)
			eng.players[int(t)]["owned"].append(id)
			eng._draw_treasure(p)
			eng.log_msg("%s passa la maledizione a %s." % [p["name"], eng.players[int(t)]["name"]])
		"T35", "T36":
			_gain_hero(k)
			eng._draw_treasure(p)
		"T01":
			var vs := _vs_hero_or_monster(str(t))
			_mod(str(t), "h" if vs else "l", 1)
		"T10":
			_mod(str(t), "l", 1 + (2 if _vs_hero(str(t)) else 0))
		"T11":
			_mod(str(t), "l", 1 + (1 if _vs_hero_or_monster(str(t)) else 0))
			_mod(str(t), "ranged", true)
		"T16":
			_mod(str(t), "stealth", true)
			_mod(str(t), "ranged", true)
			if _vs_hero_or_monster(str(t)):
				_mod(str(t), "h", 1)
		"T33":
			_mod(str(t), "h", 1)
		"T15":
			eng.cb["plagues"] = str(t)
		"T26":
			eng.cb["helm"] = str(t)
		"T27":
			if not eng.cb.is_empty():
				_mod("a" if eng.cb.get("strike", false) else "a", "rmod", -1)
		"T09":
			_discard_random_spell(seat)
			_mod("a", "succ", 1)
		"T34":
			_mod(str(t), "h", 1)
			_mod(str(t), "golem", 1)
		# Notte
		"B002", "B003", "B004":
			var tgt2: Dictionary = eng.unit(int(t))
			var bonus := 0
			if caster >= 0:
				bonus = int(D.HEROES.get(eng.unit(caster)["t"], {}).get("enslave", 0))
			var v := eng.d6()
			eng.fx.emit("dice", {"what": "enslave", "rolls": [v]})
			if v + bonus >= 5 and not tgt2.is_empty():
				var eh: Dictionary = eng._new_unit(D.NIGHT, "ehero", "ensl")
				eh["h"] = int(tgt2["h"])
				tgt2["ctl"] = D.NIGHT
				tgt2["fin"] = false
				eh["fin"] = false
				eng.log_msg("[b]%s è assoggettata all'Armata della Notte![/b] (%d%s)" % [eng.uname(tgt2), v, ("+%d" % bonus) if bonus > 0 else ""])
				eng.fx.emit("build", {"id": eh["id"], "h": eh["h"]})
			else:
				eng.log_msg("L'assoggettamento fallisce (%d)." % v)
				if caster >= 0 and not hero_locked(eng.unit(caster)["t"]) and eng.kd[D.NIGHT]["hcards"].has(eng.unit(caster)["t"]):
					_lock(eng.unit(caster)["t"])
					eng.bless_disc.erase(id)
					p["hand"].append(id)
		"B005":
			eng.study_apply(p, {"order": ["s", "b", "t"], "s": true, "b": true, "t": p["owned"][0] if not p["owned"].is_empty() else ""}, 1)
		"B006":
			_eff({"dur": "turn", "covens_hidden": true})
			eng.cb["coven_saved"] = true
		"B008":
			var h3 := int(t)
			var us4: Array = []
			for u in eng.units_at(h3):
				if eng.enemies(eng.owner(u), D.NIGHT):
					us4.append(u)
			var r4: Dictionary = eng.roll(Vector2i(0, 2), 0, "a")
			eng._log_roll("Coltelli nel Buio", Vector2i(0, 2), r4, int(r4["s"]))
			if int(r4["s"]) > 0 and not us4.is_empty():
				var a5: Dictionary = eng.army_at(h3)
				var tg: Dictionary = a5 if not a5.is_empty() else us4[0]
				for i in range(1 + int(r4["extra"])):
					if int(tg.get("h", -1)) < 0:
						break
					await eng._hit_unit(tg)
			var left := false
			for u in eng.units_at(h3):
				if eng.enemies(eng.owner(u), D.NIGHT):
					left = true
			eng.coven.erase(h3)
			if not left and eng.markers_left(D.NIGHT) > 0 and eng.is_settlement(h3):
				eng.ctrl[h3] = D.NIGHT
				eng.log_msg("La Congrega esce dall'ombra e prende %s!" % eng.hname(h3))
			eng.cb["coven_saved"] = true
		"B007", "B104", "B203", "B407":
			_gain_hero(int(card(id)["k"]))
		"B509":
			var hu3 := _gain_hero(D.ORC)
			if not hu3.is_empty():
				_eff({"dur": "act", "u": int(hu3["id"]), "dice_h": 1})
		"B009":
			var dead: Dictionary = eng.unit(caster)
			if not dead.is_empty():
				dead["h"] = int(t)
				eng.cb["saved"] = true
				eng.log_msg("%s muta forma e riappare a %s." % [eng.uname(dead), eng.hname(int(t))])
		"B010":
			_mod(str(t), "h", 1)
		# Impero
		"B101":
			var x := int(t)
			eng.kd[D.EMPIRE]["gold"] -= x
			eng.kd[D.EMPIRE]["revolts"] = maxi(0, int(eng.kd[D.EMPIRE]["revolts"]) - 2 * x)
			eng.log_msg("Pane e circhi: %d rivolte placate." % (2 * x))
		"B102":
			var av: Array = eng.available(D.EMPIRE, "e_cata")
			if not av.is_empty() and eng.army_at(int(t)).is_empty():
				eng._place(av[0], int(t), false)
				eng.log_msg("I Catafratti della Guardia giungono a %s." % eng.hname(int(t)))
			eng._revolt()
		"B103":
			var tot := 0
			var rolls: Array = []
			for i in range(int(t)):
				var v2 := eng.d6()
				rolls.append(v2)
				tot += v2
			eng.kd[D.EMPIRE]["gold"] += tot
			eng.log_msg("La Mano dell'Imperatore raccoglie %d oro %s." % [tot, str(rolls)])
			for i in range(int(t)):
				eng._revolt()
			_eff({"dur": "turn", "no_suppress": true})
		"B105":
			if o == 0:
				for i in range(3):
					var av2: Array = eng.available(D.EMPIRE, "e_akri")
					if av2.is_empty():
						break
					var hs: Array = eng.build_hexes(D.EMPIRE, "e_akri")
					if hs.is_empty():
						break
					var best: int = hs[0]
					var bd := 999
					for h4 in hs:
						var dd := 999
						for u in eng.units:
							if int(u["h"]) >= 0 and eng.enemies(eng.owner(u), D.EMPIRE):
								dd = mini(dd, D.dist(h4, int(u["h"])))
						if dd < bd:
							bd = dd
							best = h4
					eng._place(av2[0], best, not (eng.is_settlement(best) or eng.entry_owner(best) == D.EMPIRE))
					eng.log_msg("Coscritti Akritoi a %s." % eng.hname(best))
			else:
				eng.kd[D.EMPIRE]["revolts"] = maxi(0, int(eng.kd[D.EMPIRE]["revolts"]) - 3)
		"B106":
			_mod(str(t), "l", 1)
			_mod(str(t), "h", 1)
		"B107":
			_mod(str(t), "l", 2)
		"B108":
			_mod(str(t), "h", 1)
		"B109":
			_mod(str(t), "h", o)
			for i in range(o):
				eng._revolt()
		# Fjordland
		"B201":
			_mod(str(t), "h", 1)
		"B202":
			_mod(str(t), "l", 2)
		"B205":
			var v3 := eng.d6()
			_mod(str(t), "l", 1)
			if v3 >= 5:
				var av3: Array = eng.available(D.FJORD, "f_valk")
				if not av3.is_empty():
					for d in _free_hexes_near(ch, 1):
						if eng.army_at(d).is_empty():
							eng._place(av3[0], d, false)
							eng.log_msg("Le Valchirie scendono a %s!" % eng.hname(d))
							break
		"B206":
			_mod(str(t), "stealth", true)
			_mod(str(t), "crit6", true)
		"B207":
			_mod(str(t), "h", 1)
		"B208":
			_mod(str(t), "l", 1)
			var h5 := _role_hex(str(t))
			if eng.is_coastal(h5) or bool(D.hexes[h5]["mr"]):
				_mod(str(t), "h", 1)
		"B209":
			_mod(str(t), "l", 1)
			if eng.is_wild(_role_hex(str(t))):
				_mod(str(t), "l", 2)
		"B210":
			_mod(str(t), "stealth", true)
			var h6 := int(eng.cb["t"])
			if eng.is_forest(_role_hex(str(t))) or (str(t) == "a" and eng.is_forest(h6)):
				_mod(str(t), "conv", 2)
		"B204":
			_discard_chosen_spell(seat, "")
			_discard_chosen_spell(seat, "")
			eng._draw_treasure(p)
		# Goblin
		"B301":
			_mod(str(t), "x2l", true)
		"B305":
			_mod(str(t), "l", 1)
			eng.cb["spy"] = seat
		"B307":
			_mod(str(t), "l", 1)
			_mod(str(t), "stealth", true)
		"B308":
			_mod(str(t), "l", 1)
			eng.kd[D.GOBLIN]["gold"] += 1
		"B310":
			_discard_random_spell(seat)
			eng.log_msg("I Goblin si infiltrano oltre le difese!")
			await eng.apply_hits(_opp(str(t)), 1, true)
		"B303":
			_gain_hero(D.GOBLIN, str(t))
		"B304":
			var u5: Dictionary = eng.unit(int(t))
			var hh3: Dictionary = eng.hero_at(int(u5["h"]))
			var withh := not hh3.is_empty() and eng.owner(hh3) == D.GOBLIN
			for u in eng.units_at(int(u5["h"])):
				if eng.owner(u) == D.GOBLIN:
					_eff({"dur": "next", "u": int(u["id"]), "mv": 2 if withh else 1, "quick": withh})
		"B309":
			var parts2: PackedStringArray = str(t).split(">")
			await eng.strike(D.GOBLIN, Vector2i(0, 1), int(parts2[1]), {"src": "troll", "h": int(eng.unit(int(parts2[0]))["h"])})
		# Oathborn
		"B401":
			var u6: Dictionary = eng.unit(int(t))
			for u in eng.units_at(int(u6["h"])):
				if eng.owner(u) == D.OATH:
					_eff({"dur": "next", "u": int(u["id"]), "mv_set": 5, "deep": true})
		"B402":
			var v4 := eng.d6()
			var h7 := int(t)
			if v4 == 1:
				var m: Dictionary = eng.army_at(h7)
				if not m.is_empty():
					eng.log_msg("La miniera crolla sui Minatori!")
					eng._eliminate(m, "")
			elif v4 == 6:
				eng.kd[D.OATH]["gold"] += 2
				eng._draw_treasure(p)
				eng.log_msg("Una vena ricchissima: +2 oro e un Tesoro!")
			else:
				eng.bless_disc.erase(id)
				p["hand"].append(id)
		"B403":
			_eff({"dur": "turn", "secret_ways": true})
		"B404":
			var parts3: PackedStringArray = str(t).split(">")
			var h8 := int(parts3[0])
			var av4: Array = eng.available(D.OATH, parts3[1])
			if not av4.is_empty() and eng.army_at(h8).is_empty():
				eng.razed.erase(h8)
				eng.ctrl.erase(h8)
				eng._place(av4[0], h8, false)
				eng.log_msg("I corvi volano: %s si radunano a %s." % [eng.uname(av4[0]), eng.hname(h8)])
				eng._check_covens()
		"B405":
			eng.khazud = int(t)
			eng.log_msg("[b]La Città Perduta di Khazud riappare tra le montagne![/b]")
			eng.fx.emit("ctrl", {"h": int(t), "k": D.OATH})
		"B406":
			eng.cb["fury"] = true
		"B408":
			var u7: Dictionary = eng.unit(int(t))
			_eff({"dur": "next", "u": int(t), "mv": 2})
			_eff({"dur": "next", "u": int(t), "dice_l": 2})
			u7 = u7
		"B409":
			if o == 1:
				_gain_hero(D.OATH)
			else:
				var u8: Dictionary = eng.unit(int(t))
				if not u8.is_empty():
					u8["weak"] = false
		"B410":
			for i in range(int(t)):
				eng._draw_spell(p)
			while eng.hand_count(p, "spell") > 3:
				_discard_chosen_spell(seat, "")
		# Orchi
		"B501":
			var u9: Dictionary = eng.unit(int(t))
			for u in eng.units_at(int(u9["h"])):
				if eng.owner(u) == D.ORC:
					_eff({"dur": "next", "u": int(u["id"]), "mv": 2})
		"B502":
			_mod(str(t), "h", 3)
			eng.cb["forge_" + str(t)] = caster
		"B503":
			var parts4: PackedStringArray = str(t).split(">")
			var orc: Dictionary = eng.unit(int(parts4[0]))
			var tg2 := int(parts4[1])
			var v5 := eng.d6()
			if v5 >= 5:
				eng.log_msg("La pestilenza si ritorce contro gli Orchi (%d)." % v5)
				await eng._hit_unit(orc)
			else:
				eng.log_msg("La pestilenza colpisce %s (%d)." % [eng.hname(tg2), v5])
				var a6: Dictionary = eng.army_at(tg2)
				if not a6.is_empty():
					await eng._hit_unit(a6)
				elif not eng.hero_at(tg2).is_empty():
					await eng._hit_unit(eng.hero_at(tg2))
		"B504":
			var n := 0
			for h9 in eng.inplay:
				if eng.controller(h9) == D.ORC:
					n += 1
			eng.kd[D.ORC]["gold"] += n + 2
			eng.log_msg("Nuove reclute: +%d oro." % (n + 2))
		"B505":
			_mod(str(t), "stealth", true)
		"B506":
			for u in eng.units:
				if u["kind"] == "army" and int(u["h"]) >= 0 and eng.owner(u) == D.ORC and u["weak"]:
					u["weak"] = false
			eng.log_msg("Gli Orchi si rifocillano: tutte le armate indebolite si riprendono.")
		"B507":
			_mod(str(t), "h", 2)
			eng.cb["after_hit_" + str(t)] = "reaver"
		"B508":
			_mod(str(t), "h", 1)
		# poteri
		"H012":
			var r5: Dictionary = eng.roll(Vector2i(0, 1), 0, "a")
			if int(r5["s"]) > 0:
				for u in eng.units_at(int(t)):
					if eng.is_hero(u) and eng.enemies(eng.owner(u), D.NIGHT):
						eng.log_msg("Luna elimina %s." % eng.uname(u))
						await eng._kill(u, "")
						return
				if eng.monsters.has(int(t)):
					await eng._monster_defeated(int(t), D.NIGHT, false, false)
			else:
				eng.log_msg("Luna manca il bersaglio.")
				if _discard_random_spell(seat) == "":
					_kill_caster(caster)
		"H111":
			var tg3 := int(t)
			var feral := false
			var a7: Dictionary = eng.army_at(tg3)
			if not a7.is_empty() and eng.has_ch(a7, "feral"):
				feral = true
			await eng.strike(D.EMPIRE, Vector2i(1, 1 if feral else 0), tg3, {"src": "hero", "h": ch})
		"H112":
			eng.kd[D.EMPIRE]["revolts"] = maxi(0, int(eng.kd[D.EMPIRE]["revolts"]) - 1)
			eng.log_msg("Anna Lontius placa una rivolta.")
		"H214":
			_eff({"dur": "turn", "u": int(t), "ab": "regen"})
		"H317":
			await eng.strike(D.GOBLIN, Vector2i(1, 0), int(t), {"src": "hero", "h": ch})
		"H413":
			if o == 1:
				_discard_chosen_spell(seat, "")
			await eng.strike(D.OATH, Vector2i(1, o), int(t), {"src": "hero", "h": ch})
		"H512":
			var parts5: PackedStringArray = str(t).split(">")
			var src: Dictionary = eng.unit(int(parts5[0]))
			var dst: Dictionary = eng.unit(int(parts5[1]))
			if not src.is_empty() and not dst.is_empty():
				eng.log_msg("Kagash semina la discordia: %s colpisce %s." % [eng.uname(src), eng.uname(dst)])
				await eng.strike(D.ORC, eng.unit_dice(src), int(dst["h"]), {"src": "hero", "h": int(src["h"])})
		"H514":
			var v6 := eng.d6()
			if v6 >= 5:
				var a8: Dictionary = eng.army_at(int(t))
				if not a8.is_empty():
					await _fear(a8)
			else:
				eng.log_msg("Kovat non spaventa nessuno (%d)." % v6)
		"H014":
			_mod(str(t), "minus_l" if o == 0 else "minus_h", 2 if o == 0 else 1)
		"H115":
			_mod(str(t), "minus_l", 1)
		"H116", "H217", "H416":
			_mod(str(t), "l", 1)
		"H211", "H216":
			_mod(str(t), "h", 1)
		"H215":
			_mod(str(t), "h", 2)
			_kill_caster(caster)
		"H516":
			_mod(str(t), "l", 2)
			_kill_caster(caster)
		"H313":
			var hu4: Dictionary = eng.unit(caster)
			_eff({"dur": "act", "u": caster, "siege": true})
			hu4 = hu4
		"H412":
			eng._draw_spell(p)
			_discard_chosen_spell(seat, "")
		"H511":
			_discard_chosen_spell(seat, "")
			_mod(str(t), "axes", true)
		"H213":
			var dead2: Dictionary = eng.cb.get("dying", {})
			if not dead2.is_empty():
				dead2["h"] = int(t)
				eng.cb["saved"] = true
				eng.log_msg("Freyja porta in salvo %s." % eng.uname(dead2))
	eng.changed.emit()


func _vs_hero(role: String) -> bool:
	for u in _role_units(_opp(role)):
		if eng.is_hero(u):
			return true
	return false


func _vs_hero_or_monster(role: String) -> bool:
	if role == "a" and str(eng.cb["type"]) == "mon":
		return true
	return _vs_hero(role)


func _reroll(role: String) -> void:
	var key := "ra" if role == "a" else "rd"
	var r: Dictionary = eng.cb[key]
	var mod := int(r["mod"])
	var add := 0
	for x in r["rolls"]:
		if not x["ok"]:
			var v := eng.d6() if int(x["d"]) == 6 else eng.d8()
			x["v"] = v
			x["ok"] = v + mod >= 5 or (int(x["d"]) == 8 and v >= 7)
			if x["ok"]:
				add += 1
	r["s"] = int(r["s"]) + add
	eng.log_msg("Si ritirano i fallimenti: +%d successi." % add)


## Paura / Il Terrore lo Precede: chi controlla l'armata la sposta di un esagono (non accanto a
## un'armata nemica) oppure subisce un colpo.
func _fear(u: Dictionary) -> void:
	var k: int = eng.owner(u)
	var opts: Array = []
	for n in eng.nbrs(int(u["h"])):
		if eng.enter_kind(k, [u], n, eng.has_ab(u, "flying")) != 2:
			continue
		var adj_enemy := false
		for m in eng.nbrs(n):
			if eng.enemy_army_at(m, k):
				adj_enemy = true
		if not adj_enemy:
			opts.append(n)
	var r = -1
	if not opts.is_empty():
		r = await eng.decide(k, {"type": "fear", "id": u["id"], "options": opts, "slow": false})
	if r is int and int(r) in opts:
		var from := int(u["h"])
		u["h"] = int(r)
		var hh: Dictionary = eng.hero_at(from)
		if not hh.is_empty() and eng.owner(hh) == k:
			hh["h"] = int(r)
		eng.log_msg("%s arretra a %s." % [eng.uname(u), eng.hname(int(r))])
		eng.fx.emit("move", {"ids": [u["id"]], "from": from, "to": int(r), "ship": false})
	else:
		await eng._hit_unit(u)


func _strike_or_combat(k: int, dice: Vector2i, t: int, ch: int) -> void:
	if not eng.cb.is_empty() and str(eng.cb.get("type", "")) != "strike" and (t == int(eng.cb["t"]) or t == int(eng.cb["from"])):
		var role := "d" if t == int(eng.cb["t"]) else "a"
		var r: Dictionary = eng.roll(dice, 0, role)
		eng._log_roll("Assalto magico", dice, r, int(r["s"]))
		if int(r["s"]) > 0:
			await eng.apply_hits(role, 1 + int(r["extra"]), true)
		return
	await eng.strike(k, dice, t, {"src": "spell", "h": ch})


# ================================================================== finestre di gioco

## Magia di Battaglia (16.7.3): attaccante (qualsiasi carta), difensore (Cantrip), attaccante (Cantrip);
## gli alleati di ciascuno possono giocare Cantrip quando tocca a lui.
func battle_magic() -> void:
	played_bm.clear()
	for step in ["bm_a", "bm_b", "bm_c"]:
		var side_k := int(eng.cb["k"]) if step != "bm_b" else -1
		var seats: Array = []
		for p in eng.players:
			var s := int(p["seat"])
			var r := my_role(s)
			if r == "":
				continue
			if step == "bm_b" and r == "d":
				seats.append(s)
			elif step != "bm_b" and r == "a":
				seats.append(s)
		await _offer(seats, step, {})
		if eng.cb.is_empty() or eng.cb["canceled"]:
			return
		side_k = side_k
	# Bastone delle Pestilenze ed Elmo del Dominio contano le carte dell'avversario
	for key in ["plagues", "helm"]:
		if eng.cb.has(key):
			var role := str(eng.cb[key])
			var opp := _opp(role)
			var n := 0
			for s in played_bm:
				if my_role(int(s)) == opp:
					for c in played_bm[s]:
						if str(card(c)["deck"]) in ["spell", "treasure"]:
							n += 1
			if key == "plagues":
				_mod(opp, "minus_l", n)
			else:
				_mod(role, "h", n)


## Chiede a ciascun posto, a giro, se vuole giocare una carta nella finestra; finisce quando tutti passano.
func _offer(seats: Array, w: String, ctx: Dictionary) -> void:
	var rounds := 0
	var passed := {}
	while rounds < 12:
		rounds += 1
		var any := false
		for s in seats:
			if passed.has(s):
				continue
			if eng.cb.is_empty() and _bm_window(w):
				return
			var ps := all_plays(s, w, ctx)
			if ps.is_empty():
				passed[s] = true
				continue
			var k := _seat_k(s)
			var r = await eng.decide(k, {"type": "magic", "window": w, "plays": ps, "slow": false})
			if not (r is Dictionary) or r.get("pass", false):
				passed[s] = true
				continue
			var pick := _match_play(ps, r)
			if pick.is_empty():
				passed[s] = true
				continue
			any = true
			await resolve(s, pick, w)
			if _bm_window(w) and (eng.cb.is_empty() or eng.cb["canceled"]):
				return
			if w.begins_with("r_") and _single_shot(w):
				return
		if not any:
			break


func _single_shot(w: String) -> bool:
	return w in ["r_elim", "r_coven"] and (eng.cb.get("saved", false) or eng.cb.get("coven_saved", false))


func all_plays(seat: int, w: String, ctx: Dictionary) -> Array:
	var out: Array = []
	var p: Dictionary = p_of(seat)
	var ids: Array = p["hand"].duplicate()
	for k in seat_ks(seat):
		for hid in eng.kd[k]["hcards"]:
			ids.append(hid)
	for id in ids:
		var cd := card(id)
		if cd.is_empty():
			continue
		if _bm_window(w):
			if not (cd.get("bm", false) or id in BM_EXTRA or (w != "bm_a" and is_cantrip(id))):
				continue
			if w != "bm_a" and not is_cantrip(id):
				continue
			if w == "bm_a" and _seat_k(seat) != int(eng.cb["k"]) and not is_cantrip(id):
				continue
		elif w.begins_with("r_"):
			if not is_cantrip(id) and not id in ["B402", "B406", "B008", "B006", "B009", "B306", "H213"]:
				continue
		out.append_array(plays_for(seat, id, w, ctx))
	return out


## Reazioni: chi ha carte adatte può giocarle. ctx dipende dalla finestra.
func window(name: String, ctx: Dictionary) -> void:
	if not eng.advanced:
		return
	var w := "r_" + name
	match name:
		"sea_cross":
			w = "r_sea"
	var seats: Array = []
	for p in eng.players:
		seats.append(int(p["seat"]))
	match name:
		"cast":
			seats.erase(int(ctx.get("seat", -1)))
		"moved", "sea_cross":
			seats = seats.filter(func(s): return _seat_enemy(s, eng.seat_of[int(ctx["k"])]))
		"mined":
			seats = [eng.seat_of[int(ctx["k"])]]
		"rolled":
			seats = seats.filter(func(s): return my_role(s) != "")
		"won":
			seats = seats.filter(func(s): return my_role(s) == str(ctx.get("role", "")))
	await _offer(seats, w, ctx)


## Reazioni ai colpi: Riparo della Marea, Sigillo del Coraggio, Anello dell'Invisibilità,
## Tagliadita (ignora un colpo se con un'armata fragile, non contro gli assalti).
func hit_reactions(role: String, n: int, strike: bool) -> int:
	var h := _role_hex(role) if not eng.cb.get("strike", false) else int(eng.cb["t"])
	if not strike and not eng.cb.get("fc_used_" + role, false):
		var hh: Dictionary = eng.hero_at(h)
		var a: Dictionary = eng.army_at(h)
		if not hh.is_empty() and hh["t"] == "H311" and not a.is_empty() and eng.has_ch(a, "fragile"):
			eng.cb["fc_used_" + role] = true
			eng.log_msg("Tagliadita rattoppa i suoi: un colpo ignorato.")
			n -= 1
	if n <= 0 or eng.cb.is_empty():
		return maxi(n, 0)
	eng.cb["negate"] = 0
	var seats: Array = []
	for p in eng.players:
		seats.append(int(p["seat"]))
	await _offer(seats, "r_hit", {"h": h, "role": role, "n": n})
	if eng.cb.is_empty():
		return n
	var neg := int(eng.cb.get("negate", 0))
	eng.cb["negate"] = 0
	return maxi(0, n - neg)


## Reazioni all'eliminazione di un'unità: Freyja, Mutare Forma, Necromanzia, Selezione Naturale.
func on_eliminate(u: Dictionary, _why: String) -> bool:
	var saved_cb: Dictionary = eng.cb
	var tmp := saved_cb.is_empty()
	if tmp:
		eng.cb = {"mods": {"a": {}, "d": {}}, "type": "strike", "t": int(u["h"]), "from": int(u["h"]), "k": eng.cur_k}
	eng.cb["saved"] = false
	eng.cb["dying"] = u
	var seats: Array = []
	for p in eng.players:
		seats.append(int(p["seat"]))
	await _offer(seats, "r_elim", {"u": u, "h": int(u["h"])})
	var saved: bool = eng.cb.get("saved", false)
	if tmp:
		eng.cb = {}
	else:
		eng.cb.erase("dying")
		eng.cb["saved"] = false
	return saved


func coven_found(h: int) -> bool:
	var tmp: bool = eng.cb.is_empty()
	if tmp:
		eng.cb = {"mods": {"a": {}, "d": {}}, "type": "strike", "t": h, "from": h, "k": eng.cur_k}
	eng.cb["coven_saved"] = false
	var s: int = eng.seat_of.get(D.NIGHT, -1)
	if s >= 0:
		await _offer([s], "r_coven", {"h": h})
	var saved: bool = eng.cb.get("coven_saved", false)
	if tmp:
		eng.cb = {}
	return saved


# ================================================================== effetti continui

## Dadi aggiunti dai poteri sempre attivi degli eroi e dagli effetti di durata.
func ongoing_dice(u: Dictionary, _role: String) -> Vector2i:
	var l := 0
	var hv := 0
	var h := int(u["h"])
	for e in eng.effects:
		if int(e.get("u", -1)) == int(u["id"]):
			l += int(e.get("dice_l", 0))
			hv += int(e.get("dice_h", 0))
	if not eng.advanced or not eng.is_hero(u):
		return Vector2i(l, hv)
	var a: Dictionary = eng.army_at(h)
	match str(u["t"]):
		"H016":
			if not a.is_empty() and eng.has_ch(a, "feral"):
				l += 1
		"H314":
			if not a.is_empty() and a["t"] == "g_elit":
				l += 1
		"H415":
			if not a.is_empty() and D.UNITS[a["t"]].get("miner", false):
				l += 1
		"H515":
			if eng.is_forest(h):
				l += 1
		"H212":
			if eng.is_coastal(h) and not a.is_empty() and eng.unit_dice(a).x > 0:
				l -= 1
				hv += 1
	return Vector2i(l, hv)


func free_ship(us: Array) -> bool:
	for u in us:
		if eng._eff_has(u, "freeship"):
			return true
	return false


func ignore_block(us: Array) -> bool:
	for u in us:
		if eng._eff_has(u, "deep"):
			return true
	return false


func ignore_terrain(us: Array) -> bool:
	return ignore_block(us)


func pass_enemies(us: Array) -> bool:
	for u in us:
		if eng._eff_has(u, "quick"):
			return true
	return false


func secret_ways(_k: int) -> bool:
	return eng._eff_global("secret_ways")


## Abbiamo i Nostri Metodi: quando un'armata goblin saccheggia, +1d6 oro (si gioca da sola se in mano).
func loot_bonus(k: int) -> int:
	if not eng.advanced or k != D.GOBLIN:
		return 0
	var p: Dictionary = eng.player_of(k)
	if "B302" in p["hand"]:
		p["hand"].erase("B302")
		eng.bless_disc.append("B302")
		var v := eng.d6()
		eng.log_msg("• Abbiamo i Nostri Metodi: altri %d oro." % v)
		return v
	return 0


## Siskar (Trovatore di Khark): nel turno dei Goblin fa ritirare un tiro riuscito di un avversario.
func siskar_reroll(v: int) -> bool:
	if not eng.advanced or eng.cur_k != D.GOBLIN or v < 5:
		return false
	var u := hero_on_map("H316")
	if u.is_empty() or hero_locked("H316"):
		return false
	_lock("H316")
	eng.log_msg("Siskar strimpella: il dado si ritira.")
	return true


## Dopo il combattimento: Furia degli Antenati, Odio Infinito, Travolgimento, Forgia di Grom, Rete di Spie.
func after_combat() -> void:
	if eng.cb.is_empty():
		return
	for role in ["a", "d"]:
		var what := str(eng.cb.get("after_hit_" + role, ""))
		if what != "":
			for u in eng.side_units(role):
				if u["kind"] == "army" and (what == "orc" or u["t"] == "r_reav"):
					await eng._hit_unit(u)
					break
		if eng.cb.has("forge_" + role):
			for u in eng.side_units(role):
				if u["kind"] == "army" and u["t"] == "r_reav":
					eng._eliminate(u, "")
					break
			_kill_caster(int(eng.cb["forge_" + role]))
	if eng.cb.has("spy") and int(eng.cb["hits_d"]) > 0:
		var s := int(eng.cb["spy"])
		if "B305" in eng.bless_disc:
			eng.bless_disc.erase("B305")
			p_of(s)["hand"].append("B305")
			eng.log_msg("La Rete di Spie torna in mano.")
