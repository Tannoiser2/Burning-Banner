extends SceneTree
## Prova del gioco online: due istanze di Burning Banners (chi crea la stanza guida il primo regno della
## Resistenza, un amico il primo regno degli Invasori) giocano una partita intera sul finto Firebase
## (tests/firebase_mock.py); gli altri regni li gioca l'IA. Le persone sono simulate dall'IA.
## BB_ROLE=host|guest, BB_CODEFILE=file per il codice della stanza, BB_CAMP=campagna, BB_ADV=1 regole avanzate,
## BB_PHASE=drop: l'ospite esce a metà (per provare il rientro con BB_PHASE=back).
## Alla fine ognuno stampa l'impronta della partita: devono coincidere.

var main
var t0 := 0
var ai := BBAI.new()


func _init() -> void:
	main = load("res://scenes/Main.tscn").instantiate()
	root.add_child(main)
	t0 = Time.get_ticks_msec()
	_run()


func _wait(s: float) -> void:
	await create_timer(s).timeout


func _run() -> void:
	await _wait(0.5)
	var role := OS.get_environment("BB_ROLE")
	var cf := OS.get_environment("BB_CODEFILE")
	var phase := OS.get_environment("BB_PHASE")
	var camp := int(OS.get_environment("BB_CAMP")) if OS.get_environment("BB_CAMP") != "" else 0
	var menu = main.current
	menu._set_camp(camp)
	var c: Dictionary = BBData.CAMPAIGNS[camp]
	var got := {0: false, 1: false}
	for k in c["order"]:
		var sd := int(c["sides"][k])
		menu.mode[k] = 1
		if not got[sd]:
			got[sd] = true
			menu.mode[k] = 0
			menu.who[k] = 1 if sd == 1 else 2
	menu.advanced = 1 if OS.get_environment("BB_ADV") != "0" else 0
	menu.speed = 3
	menu._online_panel()
	menu.on_name.text = "Host" if role == "host" else "Ospite"
	if role == "host":
		await menu._online_create()
		var code: String = main.lobby.get("code", "")
		print("BBTEST stanza ", code)
		var f := FileAccess.open(cf, FileAccess.WRITE)
		f.store_string(code)
		f.close()
		while true:
			var room: Dictionary = await main.net.room(code)
			if Net._as_dict(room.get("seats", {})).size() >= 2:
				break
			await _wait(0.5)
		await menu._online_start()
	else:
		var code := ""
		while code == "":
			if FileAccess.file_exists(cf):
				code = FileAccess.get_file_as_string(cf).strip_edges()
			await _wait(0.3)
		menu.on_code.text = code
		await menu._online_join()
	var hidden_ok := true
	while true:
		await process_frame
		if Time.get_ticks_msec() - t0 > 1500000:
			print("BBTEST tempo scaduto")
			quit(2)
			return
		var view = main.current
		if view == null or not ("engine" in view) or view.engine == null:
			continue
		var e: BBEngine = view.engine
		# la vista mostra solo la mano del proprio posto
		if view._visible_hand() != view.online.seat:
			hidden_ok = false
		var req: Dictionary = view.pending
		if not req.is_empty() and view.online._mine_pending:
			view._provide(ai.decide(e, int(req["k"]), req))
		if phase == "drop" and e.turn_no >= 3:
			print("BBTEST esco a metà partita, mossa ", view.online.n)
			quit(0)
			return
		if e.game_over:
			await _wait(0.5)
			print("BBTEST mani nascoste: ", hidden_ok)
			print("BBTEST impronta ", view.online.n, " | ", e.fingerprint())
			quit(0)
			return
