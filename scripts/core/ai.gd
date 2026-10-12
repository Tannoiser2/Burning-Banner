class_name BBAI
extends RefCounted
## IA di Burning Banners su tre livelli.
## - Facile: sceglie fra le mosse migliori con molto rumore, costruisce poco, non pianifica la difesa.
## - Normale: valuta ogni pila (dove muovere e cosa attaccare) con le probabilità medie dei dadi.
## - Difficile: stima i combattimenti con simulazioni, difende le Città minacciate, tiene una
##   riserva d'oro, sceglie le imboscate confrontando gli esiti e gioca le carte con giudizio.
## Non guarda mai le carte in mano agli altri.

const D = preload("res://scripts/data/bb_data.gd")

var level := 1
var rng := RandomNumberGenerator.new()
var plan := {}              # piano della pila in attivazione
var turn_key := ""
var bought := false
var skip := {}              # pile che non conviene attivare in questo turno
var sims := 0


var _tc := {}
var _enemies := {}
var _dcache := {}
var _xp := OS.get_environment("BB_AI_EXP")   # varianti per le prove di taratura


func decide(eng: BBEngine, k: int, req: Dictionary):
	_new_turn(eng, k)
	_tc.clear()
	_enemies.clear()
	eng.freeze_occ()
	var r = _decide(eng, k, req)
	eng.thaw_occ()
	return r


func _decide(eng: BBEngine, k: int, req: Dictionary):
	var t: String = req["type"]
	match t:
		"main":
			return _main(eng, k, req)
		"move":
			return _move(eng, k, req)
		"ship_move":
			return _ship_move(eng, k, req)
		"action":
			return _action(eng, k, req)
		"setup_free":
			return _best_front_hex(eng, k, req["options"])
		"setup_coven":
			return _coven_pick(eng, req["options"], true)
		"coven":
			return _coven_pick(eng, req["options"], false)
		"hero_place":
			return _hero_place(eng, k, req["options"])
		"place_ctrl":
			return true
		"conquer":
			return _conquer(eng, k, int(req["h"]))
		"ambush":
			return _ambush(eng, k, req)
		"hit":
			return _hit(eng, req["options"])
		"advance":
			return _advance(eng, k, int(req["t"]))
		"disband_siege":
			return _disband(eng, k, int(req["id"]))
		"lay_waste":
			return _lay_waste(eng, k, req["options"])
		"magic":
			return _magic(eng, k, req)
		"study":
			return _study(eng, req)
		"fear":
			return _fear(eng, k, req["options"])
		"counter":
			return level >= 1
	return null


func _new_turn(eng: BBEngine, k: int) -> void:
	var key := "%d/%d/%d/%d" % [eng.year, eng.season, eng.turn_no, k]
	if key != turn_key:
		turn_key = key
		bought = false
		skip.clear()
		plan = {}


# ================================================================== valutazioni

func _p6(m: int) -> float:
	return clampf((2.0 + m) / 6.0, 0.0, 1.0)


func _p8(m: int) -> float:
	return maxf(clampf((4.0 + m) / 8.0, 0.0, 1.0), 0.25)


## Successi attesi di un pugno di dadi.
func _exp(d: Vector2i, m: int) -> float:
	return d.x * _p6(m) + d.y * (_p8(m) + 0.25 / 3.0)


func _ud(eng: BBEngine, u: Dictionary) -> Vector2i:
	var d: Vector2i = eng.unit_dice(u)
	if eng.advanced:
		d += eng.magic.ongoing_dice(u, "a")
	return d


func _hp(eng: BBEngine, us: Array) -> int:
	var n := 0
	for u in us:
		if u["kind"] == "army":
			n += 1 if (u["weak"] or eng.has_ch(u, "fragile")) else 2
		else:
			n += 1
	return n


func _unit_val(eng: BBEngine, u: Dictionary) -> float:
	if u["kind"] == "army":
		return float(D.UNITS[u["t"]]["cost"])
	return 4.0


## Stima di un attacco della pila us da `from` contro t.
func _est(eng: BBEngine, k: int, us: Array, from: int, t: int) -> Dictionary:
	var a := Vector2i.ZERO
	var settle: bool = eng.is_settlement(t)
	for u in us:
		if u["kind"] == "army" and D.UNITS[u["t"]].get("siege", false) and not settle:
			continue
		a += _ud(eng, u)
		if u["kind"] == "army" and D.UNITS[u["t"]].get("ranger", false) and eng.is_forest(t):
			a.x += 1
	if k == D.NIGHT and eng.coven.has(t):
		a.x += 1
	var d := Vector2i.ZERO
	var dus: Array = []
	var d_hp := 1
	var mon := false
	if eng.monsters.has(t):
		var m := D.monster(eng.monsters[t]["m"])
		d = Vector2i(int(m["l"]), int(m["h"]))
		mon = true
	elif eng.advanced and eng.is_lair(t):
		d = Vector2i(2, 1)
		mon = true
	else:
		for u in eng.units_at(t):
			if eng.enemies(eng.owner(u), k):
				dus.append(u)
				d += _ud(eng, u)
		if eng.is_wild(t):
			d.x += 1
		var e: Dictionary = eng.edge(from, t)
		if int(e.get("r", 0)) > 0 and not eng.stack_has(us, "flying"):
			d.x += int(e["r"])
		if settle:
			if eng.city(t):
				d.x += 3
			elif eng.army_at(t).is_empty():
				d.x += 1
		d_hp = maxi(1, _hp(eng, dus)) if not dus.is_empty() else 1
	var mod := 0
	if settle and eng.fort(t) > 0:
		var n := 0
		for nb in eng.nbrs(t):
			var x: Dictionary = eng.army_at(nb)
			if not x.is_empty() and D.UNITS[x["t"]].get("siege", false) and (eng.owner(x) == k or eng.allies(eng.owner(x), k)):
				n += 1
		for u in us:
			if u["kind"] == "army" and D.UNITS[u["t"]].get("siege", false):
				n += 0
		mod = mini(0, -eng.fort(t) + n)
	return {"a": a, "d": d, "mod": mod, "d_hp": d_hp, "a_hp": _hp(eng, us), "dus": dus, "mon": mon,
		"a_r": eng.stack_has(us, "ranged"), "d_r": _stack_ranged(eng, dus, t)}


func _stack_ranged(eng: BBEngine, dus: Array, t: int) -> bool:
	if eng.monsters.has(t):
		return "ranged" in D.monster(eng.monsters[t]["m"])["ab"]
	return eng.stack_has(dus, "ranged")


## Esito atteso: [prob. di eliminare il difensore, colpi attesi al difensore, colpi attesi all'attaccante].
func _odds(e: Dictionary) -> Array:
	if level >= 2:
		return _exact(e)
	var ea := _exp(e["a"], e["mod"])
	var ed := _exp(e["d"], 0)
	var diff := ea - ed
	var hd := maxf(0.0, diff) + 0.35
	var ha := maxf(0.0, -diff) + 0.35
	var p := clampf(0.5 + (diff - float(e["d_hp"]) + 0.6) / 2.6, 0.0, 1.0)
	return [p, hd, ha]


## Distribuzione esatta dei successi di un pugno di dadi (con i critici confermati).
func _dist(d: Vector2i, m: int) -> PackedFloat64Array:
	var key := "%d/%d/%d" % [d.x, d.y, m]
	if _dcache.has(key):
		return _dcache[key]
	var p6 := clampf((2.0 + m) / 6.0, 0.0, 1.0)
	var n8 := 0
	for v in range(1, 7):
		if v + m >= 5:
			n8 += 1
	var q1 := n8 / 8.0 + 2.0 / 8.0 * 2.0 / 3.0
	var q2 := 2.0 / 8.0 / 3.0
	var dist := PackedFloat64Array([1.0])
	for i in range(d.x):
		var nd := PackedFloat64Array()
		nd.resize(dist.size() + 1)
		for j in range(dist.size()):
			nd[j] += dist[j] * (1.0 - p6)
			nd[j + 1] += dist[j] * p6
		dist = nd
	for i in range(d.y):
		var nd := PackedFloat64Array()
		nd.resize(dist.size() + 2)
		for j in range(dist.size()):
			nd[j] += dist[j] * (1.0 - q1 - q2)
			nd[j + 1] += dist[j] * q1
			nd[j + 2] += dist[j] * q2
		dist = nd
	_dcache[key] = dist
	return dist


## Esito esatto di un combattimento (stessa forma di _odds).
func _exact(e: Dictionary) -> Array:
	var da := _dist(e["a"], e["mod"])
	var dd := _dist(e["d"], 0)
	var kill := 0.0
	var hd := 0.0
	var ha := 0.0
	var dhp := int(e["d_hp"])
	for i in range(da.size()):
		for j in range(dd.size()):
			var pr := da[i] * dd[j]
			if pr <= 0.0:
				continue
			var h1 := 0
			var h2 := 0
			if i > j:
				h1 = i - j
			elif j > i:
				h2 = j - i
			elif i > 0:
				if e["a_r"] and not e["d_r"]:
					h1 = 1
				elif e["d_r"] and not e["a_r"]:
					h2 = 1
			if h1 >= dhp:
				kill += pr
			hd += pr * h1
			ha += pr * h2
	return [kill, hd, ha]


func _mc(e: Dictionary, n: int) -> Array:
	var kill := 0
	var hd := 0.0
	var ha := 0.0
	for i in range(n):
		var sa := _roll_s(e["a"], e["mod"])
		var sd := _roll_s(e["d"], 0)
		var h1 := 0
		var h2 := 0
		if sa > sd:
			h1 = sa - sd
		elif sd > sa:
			h2 = sd - sa
		elif sa > 0:
			if e["a_r"] and not e["d_r"]:
				h1 = 1
			elif e["d_r"] and not e["a_r"]:
				h2 = 1
		if h1 >= int(e["d_hp"]):
			kill += 1
		hd += h1
		ha += h2
	sims += n
	return [float(kill) / n, hd / n, ha / n]


func _roll_s(d: Vector2i, m: int) -> int:
	var s := 0
	for i in range(d.x):
		if rng.randi_range(1, 6) + m >= 5:
			s += 1
	for i in range(d.y):
		var v := rng.randi_range(1, 8)
		if v >= 7:
			s += 1
			if rng.randi_range(1, 6) >= 5:
				s += 1
		elif v + m >= 5:
			s += 1
	return s


## Valore di un insediamento per il regno k: PV, rendita per i turni rimasti, bottino.
func _set_val(eng: BBEngine, k: int, h: int) -> float:
	if not eng.is_settlement(h):
		return 0.0
	var v: float = eng.set_value(h) * 4.0
	var tl: int = eng.turns_left()
	if not D.KINGDOMS[k]["shashka"]:
		v += minf(tl, 6) * 1.0
	var loot := 3 if D.KINGDOMS[k]["shashka"] else 2
	if eng.city(h):
		loot *= 2
	v += loot
	# obiettivi speciali delle campagne
	var nm: String = eng.sdata(h).get("n", "")
	if nm in ["Placidia", "Drakenhold"] and int(eng.camp["id"]) == 4:
		v += 25.0
	if nm in ["Aureliana", "Vikensinger Fortress"] and int(eng.camp["id"]) == 3:
		v += 25.0
	if nm == "Spire of the Moon":
		v += 30.0
	if eng.loyal(h) >= 0 and eng.loyal(h) < 6 and eng.cities_of(eng.loyal(h)).has(h) and eng.enemies(eng.loyal(h), k):
		v += 10.0
	return v


func _attack_value(eng: BBEngine, k: int, us: Array, from: int, t: int) -> float:
	var e := _est(eng, k, us, from, t)
	var o := _odds(e)
	var p: float = o[0]
	var hd: float = o[1]
	var ha: float = o[2]
	var gain := 0.0
	if e["mon"]:
		var g := 3.0
		if eng.monsters.has(t):
			g = float(D.monster(eng.monsters[t]["m"])["gold"])
		gain = p * (g + 3.0) - 1.5
	else:
		var tv := 0.0
		for u in e["dus"]:
			tv += _unit_val(eng, u)
		var per_hit := tv / maxf(1.0, float(e["d_hp"])) if tv > 0 else 0.0
		gain += minf(hd, float(e["d_hp"])) * per_hit
		if eng.is_settlement(t) and eng.posture(t, k) == "hostile":
			gain += p * _set_val(eng, k, t)
	var mv := 0.0
	for u in us:
		mv += _unit_val(eng, u)
	var loss := ha * mv / maxf(1.0, float(e["a_hp"]))
	if ha >= float(e["a_hp"]) - 0.2:
		loss += mv * 0.5
	var caution := (0.6 if int(eng.side.get(k, 1)) == 0 else 1.0) if level >= 2 else 0.7
	return gain - loss * caution


## Obiettivi verso cui marciare.
func _targets(eng: BBEngine, k: int) -> Array:
	if _tc.has(k):
		return _tc[k]
	var out: Array = []
	for h in eng.inplay:
		var p: String = eng.posture(h, k)
		if p == "hostile" or p == "welcome":
			out.append(h)
	for u in eng.units:
		if u["kind"] == "army" and int(u["h"]) >= 0 and eng.enemies(eng.owner(u), k):
			out.append(int(u["h"]))
	var tv := []
	for t in out:
		tv.append([t, _set_val(eng, k, t) if eng.is_settlement(t) else 3.0])
	_tc[k] = out
	_tc["v%d" % k] = tv
	return out


func _threats(eng: BBEngine, k: int, h: int, r: int) -> float:
	if not _enemies.has(k):
		var l := []
		for u in eng.units:
			if int(u["h"]) >= 0 and u["kind"] == "army" and eng.enemies(eng.owner(u), k):
				var dd := _ud(eng, u)
				l.append([int(u["h"]), dd.x * 0.35 + dd.y * 0.6])
		_enemies[k] = l
	var s := 0.0
	for e in _enemies[k]:
		var d: int = D.dist(h, int(e[0]))
		if d <= r:
			s += float(e[1]) * (1.0 if d <= 2 else 0.5)
	return s


## Città vitali: le poche Città ancora in mano al regno la cui perdita lo farebbe crollare.
func _vital(eng: BBEngine, k: int) -> Array:
	var key := "vital%d" % k
	if _tc.has(key):
		return _tc[key]
	var out: Array = []
	for c in eng.cities_of(k):
		if eng.is_settlement(c) and not eng.razed.has(c) and eng.controller(c) == k:
			out.append(c)
	if out.size() > 2:
		out = []
	# Shashka: senza segnalini di controllo il regno crolla (dopo averne avuto uno)
	if D.KINGDOMS[k]["shashka"] and eng.kd[k]["ever_ctrl"] and eng.control_markers(k) <= 2:
		for h in eng.ctrl:
			if int(eng.ctrl[h]) == k and not h in out:
				out.append(h)
	_tc[key] = out
	return out


func _pos_value(eng: BBEngine, k: int, us: Array, pos: int, from: int) -> float:
	var v := 0.0
	var has_army := false
	for u in us:
		if u["kind"] == "army":
			has_army = true
	if eng.is_settlement(pos) and eng.posture(pos, k) == "welcome" and has_army and not eng.feral_limited(us) and not eng.huge_in(us):
		v += _set_val(eng, k, pos) * 0.9
	# avvicinarsi agli obiettivi
	var bv := 0.0
	_targets(eng, k)
	for tv in _tc["v%d" % k]:
		var d: int = D.dist(pos, int(tv[0]))
		var score: float = float(tv[1]) / (1.0 + d)
		if score > bv:
			bv = score
	v += bv * 1.2
	# difesa delle proprie città (Normale e Difficile)
	if level >= 1:
		for c in eng.cities_of(k):
			if not eng.is_settlement(c):
				continue
			var th := _threats(eng, k, c, 3)
			if th > 0.5:
				var d2: int = D.dist(pos, c)
				if d2 == 0:
					v += th * (3.0 if level >= 2 else 1.5) + 4.0
				elif d2 == 1:
					v += th * 0.8
		# Città vitali: perderle fa crollare il regno
		if has_army:
			for c in _vital(eng, k):
				if pos == c:
					var th3 := _threats(eng, k, c, 6)
					if th3 > 0.3:
						v += (6.0 + th3 * 2.0) if level >= 2 else (3.0 + th3)
		# insediamenti propri senza difesa vicini al nemico
		if level >= 2 and eng.is_settlement(pos) and eng.controller(pos) == k and _threats(eng, k, pos, 2) > 1.0 and eng.army_at(pos).is_empty():
			v += 2.5
	# pericolo: fermarsi accanto a nemici forti
	if level >= 2 and not _xp.contains("nodanger"):
		var mine := Vector2i.ZERO
		for u in us:
			mine += _ud(eng, u)
		var my := mine.x * 0.35 + mine.y * 0.6
		var th2 := _threats(eng, k, pos, 1)
		if th2 > my + 0.5 and not eng.is_settlement(pos):
			v -= (th2 - my) * (0.8 if _xp.contains("halfdanger") else 1.5)
	if pos == from:
		v += 0.05
	return v


## Piano per una pila: dove andare e cosa fare.
func _plan_stack(eng: BBEngine, k: int, h: int, us: Array) -> Dictionary:
	var reach: Dictionary = eng.land_reach(k, us, h, 0, true)
	var positions: Array = [h]
	for p in reach:
		positions.append(int(p))
	var best := {"score": -999.0, "to": h, "act": {"a": "pass"}}
	var gold := int(eng.kd[k]["gold"])
	for pos in positions:
		var base := _pos_value(eng, k, us, pos, h)
		var acts: Array = [[{"a": "pass"}, 0.0]]
		for t in eng.attack_targets(k, us, pos):
			if eng.advanced and eng.is_lair(t) and not eng.monsters.has(t):
				var tot := Vector2i.ZERO
				for u in us:
					tot += _ud(eng, u)
				if tot.x + tot.y * 2 < 4:
					continue
			acts.append([{"a": "attack", "t": t}, _attack_value(eng, k, us, pos, t)])
		for u in us:
			if u["kind"] == "army" and u["weak"] and int(D.UNITS[u["t"]]["rec"]) >= 0 and int(D.UNITS[u["t"]]["rec"]) <= gold and eng.recover_spot(k, u, pos):
				acts.append([{"a": "recover"}, float(D.UNITS[u["t"]]["cost"]) * 0.6])
			if u["kind"] == "army" and D.UNITS[u["t"]].get("miner", false) and eng.is_mine(pos):
				acts.append([{"a": "mine"}, 1.2])
		for a in acts:
			var s: float = base + float(a[1])
			if level == 0:
				s += rng.randf_range(-3.0, 3.0)
			if s > float(best["score"]):
				best = {"score": s, "to": pos, "act": a[0]}
	# movimento navale verso un obiettivo lontano
	if eng.can_ship(us) and level >= 1:
		var sr: Dictionary = eng.ship_reach(k, us, h)
		if not sr.is_empty():
			var cur := _pos_value(eng, k, us, h, h)
			for p in sr:
				var s2 := _pos_value(eng, k, us, int(p), h) - 0.5
				if s2 > float(best["score"]) and s2 > cur + 1.0:
					best = {"score": s2, "to": int(p), "act": {"a": "pass"}, "ship": true}
	best["stay"] = _pos_value(eng, k, us, h, h)
	return best


# ================================================================== fase principale

func _reserve(eng: BBEngine, k: int) -> int:
	var r := 0
	if k == D.EMPIRE:
		r += int(eng.kd[k]["revolts"]) + 1
	if D.KINGDOMS[k]["shashka"]:
		r += eng.control_markers(k) + 1
	if level == 0:
		r = 0
	return r


func _main(eng: BBEngine, k: int, req: Dictionary):
	var o: Dictionary = req["options"]
	var gold := int(eng.kd[k]["gold"])
	if req.get("opening", false):
		var b = _buy(eng, k, o, true)
		return b if b != null else {"a": "end"}
	# repressione delle rivolte
	if int(o.get("suppress", 0)) > 0 and level >= 1:
		var rv := int(eng.kd[k]["revolts"])
		var keep := 3 if level >= 2 else 6
		var n := mini(rv, gold - keep)
		if n > 0:
			return {"a": "suppress", "n": n}
	for id in o.get("regen", []):
		return {"a": "regen", "id": id}
	if level >= 1:
		for h in o.get("unraze", []):
			if eng.loyal(h) == k or (eng.set_value(h) >= 2 and gold >= 6):
				return {"a": "unraze", "h": h}
	# carte (gioco avanzato)
	if eng.advanced and level >= 1:
		var cp = _main_card(eng, k, o)
		if cp != null:
			return cp
	# mostri comandati
	for h in o.get("monsters", []):
		var tg: Array = eng.monster_targets(k, h)
		if tg.is_empty():
			return {"a": "monster", "h": h, "do": "pass"}
		var bt: int = tg[0]
		var bs := -1.0
		for t in tg:
			var s := 1.0
			var a: Dictionary = eng.army_at(t)
			if not a.is_empty():
				s = _unit_val(eng, a) * (2.0 if (a["weak"] or eng.has_ch(a, "fragile")) else 1.0)
			elif eng.is_settlement(t):
				s = 2.0 + eng.set_value(t)
			if s > bs:
				bs = s
				bt = t
		return {"a": "monster", "h": h, "do": "strike", "t": bt}
	# acquisti prima di muovere (le armate costruite in un insediamento possono attivarsi subito)
	if not bought:
		var b2 = _buy(eng, k, o, false)
		if b2 != null:
			return b2
		bought = true
	# attivazioni
	var best := {}
	var bs2 := -999.0
	for h in o.get("acts", []):
		if skip.has(h):
			continue
		var us: Array = []
		for u in eng.units_at(h):
			if eng.owner(u) == k and not u["fin"]:
				us.append(u)
		if us.is_empty():
			continue
		var pl := _plan_stack(eng, k, h, us)
		var gain := float(pl["score"]) - float(pl["stay"])
		if pl["act"]["a"] != "pass":
			gain += 0.5
		if gain > bs2:
			bs2 = gain
			best = pl
			best["h"] = h
			best["ids"] = us.map(func(x): return int(x["id"]))
	if not best.is_empty() and (bs2 > -0.5 or best["act"]["a"] != "pass" or int(best["to"]) != int(best["h"])):
		if bs2 <= 0.01 and best["act"]["a"] == "pass" and int(best["to"]) == int(best["h"]):
			skip[best["h"]] = true
		else:
			plan = best
			skip[best["h"]] = true
			return {"a": "act", "h": best["h"], "ids": best["ids"]}
	# spese finali
	var b3 = _buy(eng, k, eng.main_options(k, false), false)
	if b3 != null:
		return b3
	if eng.advanced and level >= 1:
		for c in o.get("sell", []):
			if c in ["T29", "T30"] and gold >= 6:
				return {"a": "sell", "c": c}
	return {"a": "end"}


## Acquisto di un'armata o di un eroe; null se non conviene.
func _buy(eng: BBEngine, k: int, o: Dictionary, opening: bool):
	var gold := int(eng.kd[k]["gold"])
	var budget := gold - (0 if opening else _reserve(eng, k))
	if level == 0 and rng.randf() < 0.35:
		return null
	if budget <= 0:
		return null
	var builds: Dictionary = o.get("builds", {})
	var best_t := ""
	var best_s := -1.0
	for t in builds:
		var ud: Dictionary = D.UNITS[t]
		var c := int(ud["cost"])
		if c > budget:
			continue
		if ud.get("siege", false):
			if not _want_siege(eng, k):
				continue
		if ud.get("miner", false):
			var free_mine := false
			for h in builds[t]:
				if eng.is_mine(h) and eng.army_at(h).is_empty():
					free_mine = true
			if not free_mine and level >= 1:
				continue
		var val: float = ud["l"] * 1.0 + ud["h"] * 1.7 + ud["mv"] * 0.25
		if "ranged" in ud["ab"]:
			val += 0.6
		if "stealth" in ud["ab"]:
			val += 0.5
		if "flying" in ud["ab"]:
			val += 0.8
		if "regen" in ud["ab"]:
			val += 0.5
		if "fragile" in ud["ch"]:
			val *= 0.55
		var eff := val - 0.55 * c if level >= 1 else val / float(c)
		if ud.get("miner", false):
			eff += 2.0
		if level == 0:
			eff += rng.randf_range(0.0, 0.5)
		if eff > best_s:
			best_s = eff
			best_t = t
	var hero_ok: bool = not o.get("hero", []).is_empty() and int(D.KINGDOMS[k]["hero_cost"]) <= budget and level >= 1
	if hero_ok and (best_t == "" or rng.randf() < 0.3):
		var hs: Array = []
		for h in o["hero"]:
			var a: Dictionary = eng.army_at(h)
			if not a.is_empty() and eng.owner(a) == k:
				hs.append(h)
		if not hs.is_empty():
			return {"a": "hero", "h": _best_front_hex(eng, k, hs)}
	if best_t == "":
		return null
	var h2 := _best_front_hex(eng, k, builds[best_t], best_t)
	return {"a": "build", "u": best_t, "h": h2}


func _want_siege(eng: BBEngine, k: int) -> bool:
	for h in eng.inplay:
		if eng.posture(h, k) == "hostile" and eng.fort(h) > 0 and _near_my_units(eng, k, h, 6):
			return true
	return false


func _near_my_units(eng: BBEngine, k: int, h: int, r: int) -> bool:
	for u in eng.units:
		if int(u["h"]) >= 0 and eng.owner(u) == k and D.dist(h, int(u["h"])) <= r:
			return true
	return false


func _nearest_friendly(eng: BBEngine, k: int, h: int) -> int:
	var best := h
	var bd := 999
	for s in eng.inplay:
		if eng.controller(s) == k:
			var d: int = D.dist(h, s)
			if d < bd:
				bd = d
				best = s
	return best


## Esagono più utile fra quelli dati: vicino agli obiettivi o a una città minacciata.
func _best_front_hex(eng: BBEngine, k: int, hs: Array, t := "") -> int:
	if hs.is_empty():
		return -1
	var best: int = hs[0]
	var bs := -999.0
	var tg := _targets(eng, k)
	for h in hs:
		var s := 0.0
		for x in tg:
			var d: int = D.dist(h, x)
			var w := _set_val(eng, k, x) if eng.is_settlement(x) else 2.0
			s = maxf(s, w / (1.0 + d))
		for c in eng.cities_of(k):
			var th := _threats(eng, k, c, 3)
			if th > 0.5 and D.dist(h, c) <= 1:
				s += th
		if t != "" and D.UNITS[t].get("miner", false) and eng.is_mine(h):
			s += 5.0
		if level >= 1 and (t == "" or not D.UNITS[t].get("miner", false)):
			for c in _vital(eng, k):
				if h == c and eng.army_at(c).is_empty():
					var th3 := _threats(eng, k, c, 6)
					if th3 > 0.3:
						s += (6.0 + th3 * 2.0) if level >= 2 else (3.0 + th3)
		if eng.is_settlement(h) or eng.entry_owner(h) == k:
			s += 0.3
		if level == 0:
			s += rng.randf_range(0.0, 1.0)
		if s > bs:
			bs = s
			best = h
	return best


# ================================================================== movimento e azione

func _move(eng: BBEngine, k: int, req: Dictionary):
	var o: Dictionary = req["options"]
	var reach: Dictionary = o["reach"]
	var h := int(req["h"])
	if plan.is_empty() or int(plan.get("h", -1)) != int(eng.act.get("start", h)):
		var us: Array = eng.act_units()
		plan = _plan_stack(eng, k, h, us)
		plan["h"] = int(eng.act.get("start", h))
	if plan.get("ship", false) and o.get("ship", false) and not plan.get("ship_done", false):
		plan["ship_done"] = true
		return {"ship": true}
	var to := int(plan.get("to", h))
	if to != h and reach.has(to):
		return {"to": to}
	return {"to": -1}


func _ship_move(eng: BBEngine, k: int, req: Dictionary):
	var o: Dictionary = req["options"]
	var to := int(plan.get("to", -1))
	if o.has(to):
		plan["ship_done"] = true
		return to
	var best := -1
	var bs := -999.0
	var us: Array = eng.act_units()
	for p in o:
		var s := _pos_value(eng, k, us, int(p), int(req["h"]))
		if s > bs:
			bs = s
			best = int(p)
	return best


func _action(eng: BBEngine, k: int, req: Dictionary):
	var o: Dictionary = req["options"]
	var h := int(req["h"])
	var us: Array = eng.act_units()
	var a: Dictionary = plan.get("act", {"a": "pass"})
	if req.has("again"):
		a = {"a": "pass"}
	if a.get("a", "") == "attack" and int(a.get("t", -1)) in o["attack"] and int(plan.get("to", h)) == h:
		if _attack_value(eng, k, us, h, int(a["t"])) > -1.0:
			return a
	# rivaluta sul posto
	var best := {"a": "pass"}
	var bs := 0.3
	for t in o["attack"]:
		var v := _attack_value(eng, k, us, h, int(t))
		if v > bs:
			bs = v
			best = {"a": "attack", "t": t}
	if best["a"] == "pass":
		if o.get("recover", false):
			return {"a": "recover"}
		if o.get("mine", false):
			return {"a": "mine"}
		if o.get("ship", false) and plan.get("ship", false) and not plan.get("ship_done", false):
			return {"a": "ship"}
	return best


func _conquer(eng: BBEngine, k: int, h: int):
	if D.KINGDOMS[k]["shashka"]:
		if eng.control_markers(k) == 0:
			return "ctrl"
		if eng.set_value(h) >= 2 or level == 0:
			return "ctrl"
		var counts_razed: bool = eng.side.has(D.ORC) or eng.side.has(D.GOBLIN)
		if counts_razed and _threats(eng, k, h, 2) > 1.5:
			return "raze"
		return "ctrl"
	return "ctrl"


func _ambush(eng: BBEngine, k: int, req: Dictionary):
	if level == 0:
		return rng.randf() < 0.6
	if level == 1:
		return true
	# Difficile: confronta lo scambio di colpi atteso
	if eng.cb.is_empty():
		return true
	var role: String = "a" if req["role"] == "atk" else "d"
	var mine: Vector2i = eng.combat_dice(role, true)
	var theirs: Vector2i = eng.combat_dice("d" if role == "a" else "a", false)
	var normal: Vector2i = eng.combat_dice(role, false)
	var ea := _exp(mine, 0)
	var et := _exp(theirs, 0)
	var en := _exp(normal, 0)
	return ea + 0.6 >= en - et * 0.5 or ea >= et


func _hit(eng: BBEngine, opts: Array):
	var best: int = opts[0]
	var bl := 999.0
	for id in opts:
		var u: Dictionary = eng.unit(int(id))
		var loss := 0.0
		if eng.is_hero(u):
			loss = 6.0
		elif u["weak"] or eng.has_ch(u, "fragile"):
			loss = float(D.UNITS[u["t"]]["cost"])
		else:
			loss = maxf(1.0, float(D.UNITS[u["t"]]["rec"]))
		if loss < bl:
			bl = loss
			best = int(id)
	return best


func _advance(eng: BBEngine, k: int, t: int):
	if level == 0:
		return true
	var from := int(eng.cb.get("from", -1))
	if from >= 0 and from in _vital(eng, k) and _threats(eng, k, from, 6) > 0.3:
		return false
	if from >= 0 and eng.is_settlement(from) and eng.controller(from) == k and _threats(eng, k, from, 2) > 1.0 and level >= 2:
		return false
	if level >= 2 and not eng.is_settlement(t):
		var us: Array = eng.act_units()
		var mine := Vector2i.ZERO
		for u in us:
			mine += _ud(eng, u)
		var my := mine.x * 0.35 + mine.y * 0.6
		if _threats(eng, k, t, 1) > my + 1.0:
			return false
	return true


func _disband(eng: BBEngine, k: int, id: int):
	var u: Dictionary = eng.unit(id)
	if u.is_empty():
		return false
	for h in eng.inplay:
		if eng.posture(h, k) == "hostile" and eng.fort(h) > 0 and D.dist(h, int(u["h"])) <= 5:
			return false
	return level >= 1 and int(eng.kd[k]["gold"]) >= 6


func _lay_waste(eng: BBEngine, k: int, opts: Array):
	var out: Array = []
	var keep := 2 if level >= 1 else 1
	if level >= 2:
		keep = 3
	var left := opts.size()
	for h in opts:
		if left <= keep:
			break
		var th := _threats(eng, k, h, 2)
		var poor := int(eng.kd[k]["gold"]) < opts.size() + 2
		if th > 1.5 or (level >= 2 and poor and eng.set_value(h) == 1) or (level == 0 and rng.randf() < 0.2):
			out.append(h)
			left -= 1
	return out


func _coven_pick(eng: BBEngine, opts: Array, free: bool):
	if opts.is_empty():
		return -1
	var best: int = opts[0]
	var bs := -999.0
	for h in opts:
		var s := 0.0 if free else float(eng.coven_bonus(h)) * 2.0
		s += eng.set_value(h)
		if eng.city(h):
			s += 2.0
		for u in eng.units:
			if int(u["h"]) >= 0 and eng.owner(u) == D.NIGHT and D.dist(h, int(u["h"])) <= 3:
				s += 0.5
		if level == 0:
			s += rng.randf_range(0.0, 3.0)
		if s > bs:
			bs = s
			best = h
	if not free and eng.coven_bonus(best) == 0 and level >= 2:
		return best
	return best


func _hero_place(eng: BBEngine, k: int, opts: Array):
	var best: int = opts[0]
	var bs := -1.0
	for id in opts:
		var u: Dictionary = eng.unit(int(id))
		var d := _ud(eng, u)
		var s: float = d.x + d.y * 1.6 + _best_score_at(eng, k, int(u["h"]))
		if s > bs:
			bs = s
			best = int(id)
	return best


func _best_score_at(eng: BBEngine, k: int, h: int) -> float:
	var s := 0.0
	for t in _targets(eng, k):
		s = maxf(s, 3.0 / (1.0 + D.dist(h, t)))
	return s


func _fear(eng: BBEngine, k: int, opts: Array):
	if opts.is_empty():
		return -1
	var best: int = opts[0]
	var bs := -999.0
	for h in opts:
		var s := -_threats(eng, k, h, 1)
		if eng.is_settlement(h) and eng.welcoming(h, k):
			s += 2.0
		if s > bs:
			bs = s
			best = h
	return best


# ================================================================== carte

func _main_card(eng: BBEngine, k: int, o: Dictionary):
	var seat: int = eng.seat_of[k]
	var ids: Array = o.get("cards", []).duplicate()
	ids.append_array(o.get("powers", []))
	var best = null
	var bs := 0.8
	for c in ids:
		var ps: Array = eng.magic.plays_for(seat, c, "main", {})
		for p in ps:
			var s := _play_score(eng, k, p, "main")
			if s > bs:
				bs = s
				best = p
	if best == null:
		return null
	var r: Dictionary = best.duplicate()
	r["a"] = "power" if str(D.card(best["c"])["deck"]) == "hero" else "card"
	return r


func _magic(eng: BBEngine, k: int, req: Dictionary):
	if level == 0 and rng.randf() < 0.5:
		return {"pass": true}
	var best = null
	var bs := 0.9 if level >= 2 else 0.5
	for p in req["plays"]:
		var s := _play_score(eng, k, p, str(req["window"]))
		if s > bs:
			bs = s
			best = p
	if best == null:
		return {"pass": true}
	return best


## Valore stimato di una giocata (in "oro").
func _play_score(eng: BBEngine, k: int, p: Dictionary, w: String) -> float:
	var c := str(p["c"])
	var t = p.get("t", -1)
	var tome := str(p.get("tome", ""))
	var s := 0.0
	var cd := D.card(c)
	var bm := w.begins_with("bm_")
	var imp := 1.0
	if bm and not eng.cb.is_empty():
		var tt := int(eng.cb["t"])
		imp = 1.0 + (_set_val(eng, int(eng.cb["k"]), tt) / 10.0 if eng.is_settlement(tt) else 0.0)
	match c:
		"S01", "S28", "B108", "B201", "B207", "B010", "B508", "H211", "H216", "S36", "T33", "T34", "S30":
			s = 1.6 * imp
		"S02", "S07", "S51", "B106", "H116", "H217", "H416", "H115", "T01", "T10", "T11", "T16", "S09", "B307", "B305", "B308":
			s = 1.1 * imp
		"S03", "S25", "S32", "B202", "B107", "S39", "S40", "B206", "B210", "H014", "B208", "B209", "B507", "B109":
			s = 2.0 * imp
		"S37", "B110", "B301":
			s = 2.4 * imp
		"S18", "H215", "H516", "B502":
			s = 1.2 * imp
		"S16", "S19":
			s = 3.0 if bm else 2.0
		"S41", "T20", "S44", "T15", "T26", "T27", "B505", "H313", "H412", "H511", "T09", "B310":
			s = 1.4 * imp
		"S13", "S50", "T12", "B006", "B008", "S14", "B009", "H213", "S10", "B306":
			s = 3.0
		"S15", "T03", "S34", "S42":
			s = 1.5 if level >= 2 else 0.6
		"S33", "T07", "B510":
			s = 1.5
		"S26", "S47":
			s = 2.5
		"B406":
			s = 2.5
		"B402":
			s = 1.0
		"S04", "S05", "S06", "S08", "S31", "S43", "S48", "S52", "H111", "H317", "H413", "B309", "H012":
			var tg := int(t) if (t is int or t is float) else -1
			if t is String and "a" == t or t is String and "d" == t:
				s = 1.4
			elif tg >= 0:
				s = _strike_val(eng, k, tg)
		"S35":
			s = 2.5
		"S46":
			s = 2.0
		"S11", "S21", "S45", "T05":
			s = 0.3
		"S12", "S38", "T06", "T28", "B304", "B408", "B501", "B401", "T13":
			s = 0.9 if level >= 2 else 0.4
		"S17", "B409", "B506":
			s = 2.0
		"S20", "B001", "S29":
			s = 1.0
		"S23", "S24", "B204", "B410", "B005", "T04":
			s = 1.2
		"S27", "H514":
			s = 1.5
		"S49", "T32":
			s = 1.0
		"T02", "T17", "T18", "T19", "T35", "T36", "B504", "B007", "B104", "B203", "B407", "B509", "B303", "B103":
			s = 3.0
		"T25", "H214":
			s = 0.5
		"T29", "T30":
			s = 2.5
		"B002", "B003", "B004":
			var u: Dictionary = eng.unit(int(t))
			s = float(D.UNITS[u["t"]]["cost"]) * 0.5 if not u.is_empty() else 0.0
		"B101":
			s = 1.5
		"B102":
			s = 4.0
		"B105":
			s = 2.5
		"B403":
			s = 0.2
		"B404":
			s = 3.0
		"B405":
			s = 6.0
		"H112":
			s = 1.2
		"H512":
			s = 2.0
	if tome != "":
		s += 0.6
	if c in ["S16", "S19"] and bm:
		var mine: String = eng.magic.my_role(eng.seat_of[k])
		if mine == "d":
			s = 3.0
	if level == 0:
		s *= rng.randf_range(0.5, 1.3)
	return s


func _strike_val(eng: BBEngine, k: int, t: int) -> float:
	var a: Dictionary = eng.army_at(t)
	if not a.is_empty() and eng.enemies(eng.owner(a), k):
		var v := float(D.UNITS[a["t"]]["cost"])
		return v * (0.7 if (a["weak"] or eng.has_ch(a, "fragile")) else 0.35)
	if eng.monsters.has(t):
		return 1.0
	if eng.is_settlement(t):
		return 1.0 + eng.set_value(t) * 0.5
	return 0.3


func _study(eng: BBEngine, req: Dictionary):
	var r := {"s": true, "b": true, "t": "", "order": ["s", "b", "t"]}
	var o: Dictionary = req["options"]
	if not o["treasure"].is_empty():
		r["t"] = o["treasure"][0]
		if int(req["n"]) == 1 and o["spells"] >= 2:
			r["order"] = ["t", "s", "b"]
	return r
