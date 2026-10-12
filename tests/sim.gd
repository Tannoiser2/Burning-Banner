extends SceneTree
## Partite IA contro IA senza grafica:
## godot --headless -s res://tests/sim.gd -- <partite> <campagna 0-6> <livello invasori> <livello resistenza> [avanzato 0/1]
## BB_LOG=1 stampa il diario.

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var games := int(args[0]) if args.size() > 0 else 4
	var camp := int(args[1]) if args.size() > 1 else 0
	var li := int(args[2]) if args.size() > 2 else 1
	var lr := int(args[3]) if args.size() > 3 else 1
	var adv := args.size() > 4 and args[4] == "1"
	var seed0 := int(OS.get_environment("BB_SEED")) if OS.get_environment("BB_SEED") != "" else 1000
	var wins := [0, 0]
	var t0 := Time.get_ticks_msec()
	BBData.load_all()
	var c: Dictionary = BBData.CAMPAIGNS[camp]
	for g in range(games):
		var eng := BBEngine.new()
		eng.headless = true
		root.add_child(eng)
		var seats := []
		for k in c["order"]:
			var s := int(c["sides"][k])
			seats.append({"ai": true, "name": BBData.KINGDOMS[k]["short"], "level": li if s == 0 else lr, "ks": [k]})
		eng.setup({"campaign": camp, "advanced": adv, "seed": seed0 + g, "seats": seats})
		if OS.get_environment("BB_LOG") != "":
			eng.log_added.connect(func(t): print("  ", t))
		await eng.run()
		var r: Dictionary = eng.results
		wins[int(r["winner"])] += 1
		print("partita %d: vince %s (%s) · PV %d/%d · turni %d" % [g, BBData.SIDE_NAMES[int(r["winner"])], r["reason"], r["vp"][0]["tot"], r["vp"][1]["tot"], r["turns"]])
		eng.queue_free()
	print("Invasori %d, Resistenza %d · %d ms" % [wins[0], wins[1], Time.get_ticks_msec() - t0])
	quit()
