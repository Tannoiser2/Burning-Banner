extends SceneTree
## Prova rapida della mappa 3D: godot --path . -s res://tests/board_shot.gd -- <campagna>

func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var c := int(args[0]) if args.size() > 0 else 6
	BBData.load_all()
	var eng := BBEngine.new()
	eng.headless = true
	root.add_child(eng)
	var seats: Array = []
	for k in BBData.CAMPAIGNS[c]["sides"]:
		seats.append({"name": "x", "ai": true, "level": 1, "ks": [int(k)]})
	eng.setup({"campaign": c, "advanced": true, "seed": 3, "seats": seats})
	await eng._setup_game()
	var b := Board3D.new()
	root.add_child(b)
	b.setup(eng)
	b.refresh()
	DirAccess.make_dir_recursive_absolute(OS.get_user_data_dir() + "/shots")
	for i in range(30):
		await process_frame
	_save("board_all")
	var h := BBData.hex_of("Fort Gorod") if c != 6 else BBData.hex_of("Placidia")
	b.want_dist = 6
	b.want_pitch = 40
	b.focus(h)
	for i in range(80):
		await process_frame
	_save("board_close")
	b.want_dist = 3
	b.want_pitch = 30
	for i in range(80):
		await process_frame
	_save("board_vclose")
	quit()


func _save(n: String) -> void:
	var img := root.get_viewport().get_texture().get_image()
	img.save_png(OS.get_user_data_dir() + "/shots/" + n + ".png")
	print("saved ", n)
