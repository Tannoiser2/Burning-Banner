extends SceneTree
## Controllo di compilazione degli script: godot --headless -s res://tests/chk.gd
func _init() -> void:
	for f in ["res://scripts/data/bb_data.gd", "res://scripts/core/engine.gd", "res://scripts/core/magic.gd", "res://scripts/core/ai.gd",
			"res://scripts/ui/ui.gd", "res://scripts/ui/board3d.gd", "res://scripts/ui/menu.gd", "res://scripts/ui/rules_view.gd",
			"res://scripts/ui/game_view.gd", "res://scripts/ui/main.gd", "res://scripts/net/net.gd", "res://scripts/net/online_session.gd"]:
		var s = load(f)
		print(f, " → ", "ok" if s != null and s.can_instantiate() else "ERRORE")
	quit()
