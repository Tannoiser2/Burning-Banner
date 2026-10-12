extends SceneTree
## Screenshot automatici dell'interfaccia (serve un display: xvfb-run).
## godot --path . -s res://tests/shot.gd -- <modo: menu|rules|game> [campagna] [avanzate 0/1]
## In modalità game si gioca una partita intera dall'interfaccia: le decisioni dei regni umani
## le prende l'IA ma passano dai clic sulla mappa e dai pulsanti della vista, come farebbe una persona.

var main
var n := 0
var ai := BBAI.new()
var shots := {}


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(OS.get_user_data_dir() + "/shots")
	main = load("res://scenes/Main.tscn").instantiate()
	root.add_child(main)
	_run.call_deferred()


func shot(name: String) -> void:
	await process_frame
	await process_frame
	await process_frame
	var img := root.get_viewport().get_texture().get_image()
	n += 1
	img.save_png(OS.get_user_data_dir() + "/shots/%02d_%s.png" % [n, name])
	print("shot ", name)


func wait(f := 10) -> void:
	for i in range(f):
		await process_frame


func gv():
	return main.current


## Risponde alla decisione in corso usando l'interfaccia (clic sulla mappa e sui pulsanti).
func ui_answer() -> void:
	var g = gv()
	var req: Dictionary = g.pending
	if req.is_empty():
		return
	if g.cover_for >= 0:
		g.cover_for = -1
		g._clear_modal()
		g._show_decision()
		return
	var r = ai.decide(g.engine, int(req["k"]), req)
	match str(req["type"]):
		"main":
			if r is Dictionary:
				match str(r.get("a", "")):
					"build":
						g._set_sel("build:" + str(r["u"]))
						g._on_hex_click(int(r["h"]), MOUSE_BUTTON_LEFT)
					"act":
						if (r.get("ids", []) as Array).is_empty():
							g._on_hex_click(int(r["h"]), MOUSE_BUTTON_LEFT)
							if not g.pending.is_empty():
								g._provide(r)
		"move":
			if r is Dictionary and int(r.get("to", -1)) >= 0:
				g._on_hex_click(int(r["to"]), MOUSE_BUTTON_LEFT)
		"action":
			if r is Dictionary and str(r.get("a", "")) == "attack":
				g._on_hex_click(int(r["t"]), MOUSE_BUTTON_LEFT)
		"setup_free", "setup_coven":
			g._on_hex_click(int(r), MOUSE_BUTTON_LEFT)
	if not g.pending.is_empty() and g.pending == req:
		g._provide(r)


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var mode := args[0] if args.size() > 0 else "menu"
	await wait(20)
	if mode == "menu":
		await shot("menu")
		main.current._set_camp(6)
		await wait(5)
		await shot("menu_c6")
		main.current._online_panel()
		await wait(5)
		await shot("menu_online")
		quit()
		return
	if mode == "rules":
		main.show_rules()
		await wait(10)
		await shot("rules")
		quit()
		return
	var camp := int(args[1]) if args.size() > 1 else 0
	var adv := int(args[2]) if args.size() > 2 else 1
	ai.level = 1
	BBData.load_all()
	var c: Dictionary = BBData.CAMPAIGNS[camp]
	var seats: Array = []
	var first := true
	for k in c["order"]:
		var human: bool = first and int(c["sides"][k]) == 1
		if human:
			first = false
		seats.append({"name": "Stefano" if human else "IA", "ai": not human, "level": 1, "ks": [int(k)]})
	main.start_game({"campaign": camp, "advanced": adv == 1, "seats": seats, "ai_delay": 0.0, "seed": 11})
	await wait(30)
	await shot("game_start")
	var g = gv()
	if mode == "start":
		# solo l'apertura: la mappa intera e la prima decisione del regno umano
		var w := 0
		while w < 3000 and (g.pending.is_empty() or str(g.pending["type"]) != "main" or g.pending.get("opening", false)):
			if not g.pending.is_empty():
				ui_answer()
			await process_frame
			w += 1
		await wait(60)
		await shot("start_turn")
		quit()
		return
	var steps := 0
	var t0 := Time.get_ticks_msec()
	while not g.engine.game_over and steps < 6000 and Time.get_ticks_msec() - t0 < 1500000:
		steps += 1
		if not g.pending.is_empty():
			if not shots.has("decision") and str(g.pending["type"]) == "main" and not g.pending.get("opening", false):
				shots["decision"] = true
				await wait(4)
				await shot("decision")
				# vista ravvicinata della mappa
				var h := int(g.pending["options"]["acts"][0]) if not g.pending["options"]["acts"].is_empty() else -1
				if h >= 0:
					g.board.want_dist = 5.0
					g.board.want_pitch = 42.0
					g.board.focus(h)
					await wait(50)
					g._on_hex_hover(h)
					await shot("map_close")
					g.board.want_dist = 14.0
			if not shots.has("magic") and str(g.pending["type"]) == "magic":
				shots["magic"] = true
				await wait(4)
				await shot("magic")
			ui_answer()
		if g.dice_panel.visible and not shots.has("combat"):
			shots["combat"] = true
			await wait(3)
			await shot("combat")
		await process_frame
	await wait(20)
	await shot("end")
	print("fine: game_over=", g.engine.game_over, " passi=", steps, " vincitore=", g.engine.winner, " ", g.engine.win_reason)
	quit()
