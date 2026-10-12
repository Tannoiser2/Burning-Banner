class_name Board3D
extends Node3D
## La mappa in 3D: terreno in rilievo (dalle immagini delle mappe), acqua animata, boschi,
## insediamenti, tane e miniere; le unità sono pedine di cartoncino col bordo del colore del regno e la figura
## della pedina sulla faccia; i segnalini di controllo, raso al suolo e Congrega sono pedine.
## Telecamera libera: ruota, inclina, zoom, sposta; doppio clic centra un esagono.

signal hex_clicked(h: int, button: int)
signal hex_hovered(h: int)

const D = preload("res://scripts/data/bb_data.gd")
const PX := 0.01            # pixel della mappa -> unità del mondo
const HMIN := -0.40
const HMAX := 1.40
const HSCALE := 0.62
const STEP := 8             # passo della griglia dei rilievi (pixel)
const MESH_STEP := 2        # campioni per vertice del terreno
const IMG_W := 1899
const IMG_H := 2446
const PIECE := 2.0          # scala delle pedine (rispetto all'esagono)
const TOKEN := 1.6          # scala di mostri e segnalini

var eng: BBEngine
var maps_on: Array = []
var heights := {}           # mappa -> {"w","h","d": PackedByteArray, "ox","oy"}
var terrain_mats: Array = []
var water_mat: ShaderMaterial
var hl_img: Image
var hl_tex: ImageTexture
var hl := {}
var time_s := 0.0

# telecamera
var cam: Camera3D
var target := Vector3(19, 0, 12)
var yaw := 0.0
var pitch := 52.0
var dist := 14.0
var want_target := Vector3.ZERO
var want_yaw := 0.0
var want_pitch := 52.0
var want_dist := 14.0
var drag_btn := -1
var drag_moved := 0.0
var press_pos := Vector2.ZERO
var last_click_t := 0
var hover_h := -1
var bounds := Rect2()
var input_enabled := true

# pezzi
var blocks := {}            # id unità -> Node3D
var mon_nodes := {}         # esagono -> Node3D
var mark_nodes := {}        # "c:h" / "r:h" / "v:h" -> Node3D
var set_flags := {}         # esagono -> MeshInstance3D (bandierina)
var set_ranges := {}        # esagono -> [[multimesh, da, a, colori]]
var ruins := {}
var labels := {}
var khazud_node: Node3D = null
var sel_ring: MeshInstance3D
var sel_hex := -1
var mat_cache := {}
var counters := {}
var towns := {}
var atlas: Texture2D
var block_mesh: BoxMesh
var hero_mesh: BoxMesh
var face_mesh: QuadMesh
var hero_face: QuadMesh
var disc_mesh: CylinderMesh
var disc_top: QuadMesh
var wood_tex: Texture2D


func setup(p_eng: BBEngine) -> void:
	eng = p_eng
	D.load_all()
	counters = D.counters
	atlas = load("res://assets/counters/atlas.webp")
	for m in eng.active_maps:
		maps_on.append(int(m))
	maps_on.sort()
	_load_heights()
	_env()
	_terrain()
	_water()
	_trees()
	_settlements()
	_features()
	_pieces_init()
	_camera()
	refresh()


# ================================================================== rilievo

func _load_heights() -> void:
	for mi in range(4):
		var f := FileAccess.open("res://data/height_%d.bin" % mi, FileAccess.READ)
		if f == null:
			continue
		var w := f.get_16()
		var h := f.get_16()
		var data := f.get_buffer(w * h)
		var m: Dictionary = D.maps[mi]
		heights[mi] = {"w": w, "h": h, "d": data, "ox": float(m["ox"]), "oy": float(m["oy"])}


func _hval(mi: int, gx: int, gy: int) -> float:
	var hm: Dictionary = heights[mi]
	gx = clampi(gx, 0, int(hm["w"]) - 1)
	gy = clampi(gy, 0, int(hm["h"]) - 1)
	var v: int = hm["d"][gy * int(hm["w"]) + gx]
	return (HMIN + v / 255.0 * (HMAX - HMIN)) * HSCALE


## Altezza bilineare nella mappa mi, in pixel locali dell'immagine.
func _hpx(mi: int, lx: float, ly: float) -> float:
	var fx := lx / STEP
	var fy := ly / STEP
	var x0 := int(floor(fx))
	var y0 := int(floor(fy))
	var tx := fx - x0
	var ty := fy - y0
	var a := lerpf(_hval(mi, x0, y0), _hval(mi, x0 + 1, y0), tx)
	var b := lerpf(_hval(mi, x0, y0 + 1), _hval(mi, x0 + 1, y0 + 1), tx)
	return lerpf(a, b, ty)


## Mappa vicina nel quadrato 2x2 (0 1 / 2 3) dal lato l/r/u/d, o -1.
func _nb(mi: int, side: String) -> int:
	match side:
		"l":
			return 0 if mi == 1 else (2 if mi == 3 else -1)
		"r":
			return 1 if mi == 0 else (3 if mi == 2 else -1)
		"u":
			return 0 if mi == 2 else (1 if mi == 3 else -1)
		"d":
			return 2 if mi == 0 else (3 if mi == 1 else -1)
	return -1


## Altezza del terreno della mappa mi in pixel locali, raccordata con le mappe vicine:
## verso il bordo comune le due mappe convergono alla media.
func _ty(mi: int, px: float, py: float) -> float:
	const BAND := 160.0
	var y := _hpx(mi, px, py)
	var ox: float = float(heights[mi]["ox"])
	var oy: float = float(heights[mi]["oy"])
	for sd in ["l", "r", "u", "d"]:
		var nb := _nb(mi, sd)
		if not nb in maps_on or not heights.has(nb):
			continue
		var d := 0.0
		var ex := px
		var ey := py
		match sd:
			"l":
				d = px
				ex = 0
			"r":
				d = IMG_W - px
				ex = IMG_W
			"u":
				d = py
				ey = 0
			"d":
				d = IMG_H - py
				ey = IMG_H
		if d >= BAND:
			continue
		var other := _hpx(nb, px + ox - float(heights[nb]["ox"]), py + oy - float(heights[nb]["oy"]))
		y += (other - _hpx(mi, ex, ey)) * 0.5 * (1.0 - d / BAND)
	return y


## Altezza del terreno in un punto del mondo (interpolata).
func height_at(wx: float, wz: float) -> float:
	var px := wx / PX
	var py := wz / PX
	for mi in maps_on:
		var hm: Dictionary = heights.get(mi, {})
		if hm.is_empty():
			continue
		var lx := px - float(hm["ox"])
		var ly := py - float(hm["oy"])
		if lx < -2 or ly < -2 or lx > IMG_W + 2 or ly > IMG_H + 2:
			continue
		return _ty(mi, clampf(lx, 0, IMG_W), clampf(ly, 0, IMG_H))
	return 0.0


func hex_pos(h: int) -> Vector3:
	var e: Dictionary = D.hexes.get(h, {})
	if e.is_empty():
		return Vector3.ZERO
	var x := float(e["x"]) * PX
	var z := float(e["y"]) * PX
	return Vector3(x, maxf(height_at(x, z), 0.0), z)


## Esagono sotto un punto del mondo (−1 se fuori dalle mappe in gioco).
func hex_at(wx: float, wz: float) -> int:
	var px := wx / PX
	var py := wz / PX
	var c0 := int(round((px - 6.0) / D.dx))
	var best := -1
	var bd := 1e9
	for dc in [-1, 0, 1]:
		var c: int = c0 + dc
		if c < 0:
			continue
		var off := D.dy * 0.5 if c % 2 == 1 else 0.0
		var r0 := int(round((py - 23.0 - off) / D.dy))
		for dr in [-1, 0, 1]:
			var r: int = r0 + dr
			if r < 0:
				continue
			var cx := 6.0 + c * D.dx
			var cy := 23.0 + r * D.dy + off
			var d := (px - cx) * (px - cx) + (py - cy) * (py - cy)
			if d < bd:
				bd = d
				best = c * 100 + r
	if best >= 0 and eng.in_map(best):
		return best
	return -1


# ================================================================== ambiente e terreno

func _env() -> void:
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("#16110c")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("#a89c88")
	env.ambient_light_energy = 0.5
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.fog_enabled = true
	env.fog_light_color = Color("#2a2219")
	env.fog_density = 0.004
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-52, -38, 0)
	sun.light_energy = 0.92
	sun.light_color = Color("#fff1d8")
	sun.shadow_enabled = true
	sun.shadow_bias = 0.04
	sun.directional_shadow_max_distance = 40.0
	add_child(sun)
	# il tavolo sotto le mappe
	var table := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(160, 160)
	table.mesh = pm
	var tm := StandardMaterial3D.new()
	tm.albedo_color = Color("#2b1f14")
	tm.roughness = 0.9
	table.material_override = tm
	table.position = Vector3(19, -0.35, 24)
	add_child(table)


func _terrain() -> void:
	hl_img = Image.create(32, 32, false, Image.FORMAT_RGBA8)
	hl_img.fill(Color(0, 0, 0, 0))
	hl_tex = ImageTexture.create_from_image(hl_img)
	var shader: Shader = load("res://assets/shaders/terrain.gdshader")
	var minx := 1e9
	var minz := 1e9
	var maxx := -1e9
	var maxz := -1e9
	for mi in maps_on:
		var m: Dictionary = D.maps[mi]
		var hm: Dictionary = heights[mi]
		var mat := ShaderMaterial.new()
		mat.shader = shader
		mat.set_shader_parameter("albedo_tex", load("res://assets/maps/%s.jpg" % m["img"]))
		mat.set_shader_parameter("hl_tex", hl_tex)
		mat.set_shader_parameter("dx", D.dx * PX)
		mat.set_shader_parameter("dy", D.dy * PX)
		terrain_mats.append(mat)
		var gw: int = int(hm["w"])
		var gh: int = int(hm["h"])
		var nx := int(ceil((gw - 1) / float(MESH_STEP))) + 1
		var nz := int(ceil((gh - 1) / float(MESH_STEP))) + 1
		var verts := PackedVector3Array()
		var uvs := PackedVector2Array()
		var norms := PackedVector3Array()
		var idx := PackedInt32Array()
		var ox: float = float(hm["ox"])
		var oy: float = float(hm["oy"])
		var open_l: bool = _nb(mi, "l") in maps_on
		var open_r: bool = _nb(mi, "r") in maps_on
		var open_u: bool = _nb(mi, "u") in maps_on
		var open_d: bool = _nb(mi, "d") in maps_on
		for j in range(nz):
			for i in range(nx):
				var gx := mini(i * MESH_STEP, gw - 1)
				var gy := mini(j * MESH_STEP, gh - 1)
				var px: float = float(IMG_W) if i == nx - 1 else minf(gx * STEP, IMG_W)
				var py: float = float(IMG_H) if j == nz - 1 else minf(gy * STEP, IMG_H)
				var y := _ty(mi, px, py)
				# bordi esterni: il terreno scende verso il tavolo
				if (i == 0 and not open_l) or (j == 0 and not open_u) or (i == nx - 1 and not open_r) or (j == nz - 1 and not open_d):
					y = minf(y, 0.02)
				verts.append(Vector3((px + ox) * PX, y, (py + oy) * PX))
				uvs.append(Vector2(px / IMG_W, py / IMG_H))
				var hx := _hval(mi, gx + 1, gy) - _hval(mi, gx - 1, gy)
				var hz := _hval(mi, gx, gy + 1) - _hval(mi, gx, gy - 1)
				norms.append(Vector3(-hx / (2.0 * STEP * PX), 1.0, -hz / (2.0 * STEP * PX)).normalized())
		for j in range(nz - 1):
			for i in range(nx - 1):
				var a := j * nx + i
				idx.append_array([a, a + 1, a + nx, a + 1, a + nx + 1, a + nx])
		var arr := []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = verts
		arr[Mesh.ARRAY_NORMAL] = norms
		arr[Mesh.ARRAY_TEX_UV] = uvs
		arr[Mesh.ARRAY_INDEX] = idx
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		var mi_node := MeshInstance3D.new()
		mi_node.mesh = mesh
		mi_node.material_override = mat
		add_child(mi_node)
		minx = minf(minx, ox * PX)
		minz = minf(minz, oy * PX)
		maxx = maxf(maxx, (ox + IMG_W) * PX)
		maxz = maxf(maxz, (oy + IMG_H) * PX)
	bounds = Rect2(minx, minz, maxx - minx, maxz - minz)


func _water() -> void:
	water_mat = ShaderMaterial.new()
	water_mat.shader = load("res://assets/shaders/water.gdshader")
	for mi in maps_on:
		var m: Dictionary = D.maps[mi]
		var w := MeshInstance3D.new()
		var pm := PlaneMesh.new()
		pm.size = Vector2(IMG_W * PX - 0.04, IMG_H * PX - 0.04)
		pm.subdivide_width = 48
		pm.subdivide_depth = 60
		w.mesh = pm
		w.material_override = water_mat
		w.position = Vector3((float(m["ox"]) + IMG_W / 2.0) * PX, -0.03, (float(m["oy"]) + IMG_H / 2.0) * PX)
		w.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(w)


func _merge(parts: Array) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for p in parts:
		var mesh: Mesh = p[0]
		st.append_from(mesh, 0, p[1])
	st.generate_normals()
	return st.commit()


func _trees() -> void:
	var f := FileAccess.open("res://data/trees.bin", FileAccess.READ)
	if f == null:
		return
	var n := f.get_32()
	var pts: Array = []
	for i in range(n):
		var x := f.get_float()
		var y := f.get_float()
		var s := f.get_float()
		var h := hex_at(x * PX, y * PX)
		if h < 0:
			continue
		pts.append([x, y, s])
	var cone := CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = 0.075
	cone.height = 0.2
	cone.radial_segments = 7
	cone.rings = 1
	var cone2 := CylinderMesh.new()
	cone2.top_radius = 0.0
	cone2.bottom_radius = 0.058
	cone2.height = 0.15
	cone2.radial_segments = 7
	cone2.rings = 1
	var trunk := CylinderMesh.new()
	trunk.top_radius = 0.012
	trunk.bottom_radius = 0.016
	trunk.height = 0.07
	trunk.radial_segments = 5
	trunk.rings = 1
	var mesh := _merge([[trunk, Transform3D(Basis(), Vector3(0, 0.035, 0))], [cone, Transform3D(Basis(), Vector3(0, 0.15, 0))], [cone2, Transform3D(Basis(), Vector3(0, 0.24, 0))]])
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = mesh
	mm.instance_count = pts.size()
	var r := RandomNumberGenerator.new()
	r.seed = 99
	for i in range(pts.size()):
		var p: Array = pts[i]
		var wx: float = p[0] * PX
		var wz: float = p[1] * PX
		var s: float = p[2] * 1.15
		var b := Basis().rotated(Vector3.UP, r.randf() * TAU).scaled(Vector3(s, s * r.randf_range(0.85, 1.25), s))
		mm.set_instance_transform(i, Transform3D(b, Vector3(wx, height_at(wx, wz) - 0.01, wz)))
		var g := r.randf_range(0.0, 1.0)
		mm.set_instance_color(i, Color(0.16 + g * 0.08, 0.30 + g * 0.12, 0.14 + g * 0.05))
	var node := MultiMeshInstance3D.new()
	node.multimesh = mm
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.albedo_color = Color.WHITE
	mat.roughness = 0.95
	node.material_override = mat
	add_child(node)


# ================================================================== insediamenti, tane, miniere

func _settlements() -> void:
	var tf := FileAccess.open("res://data/towns.json", FileAccess.READ)
	if tf != null:
		towns = JSON.parse_string(tf.get_as_text())
	var r := RandomNumberGenerator.new()
	r.seed = 7
	var body := BoxMesh.new()
	body.size = Vector3(1, 1, 1)
	var roof := PrismMesh.new()
	roof.size = Vector3(1, 1, 1)
	var tower := CylinderMesh.new()
	tower.top_radius = 0.5
	tower.bottom_radius = 0.55
	tower.height = 1.0
	tower.radial_segments = 8
	tower.rings = 1
	var cap := CylinderMesh.new()
	cap.top_radius = 0.0
	cap.bottom_radius = 0.62
	cap.height = 1.0
	cap.radial_segments = 8
	cap.rings = 1
	var parts := {"body": [], "roof": [], "tower": [], "cap": []}
	var spire := -1
	for s in D.settlements:
		var h := int(s["h"])
		if not eng.in_map(h):
			continue
		var c := hex_pos(h) + Vector3(0, 0, -0.2)
		var start := {}
		for k in parts:
			start[k] = parts[k].size()
		var n_h := 3 + (6 if s["city"] else 0) + (1 if s["fort"] > 0 else 0)
		if s["n"] == "Spire of the Moon":
			spire = h
			n_h = 2
		# case e torri ricalcate dall'illustrazione della mappa (data/towns.json)
		var tw: Dictionary = towns.get(s["n"], {})
		var drawn: bool = s["n"] != "Spire of the Moon" and (not tw.get("h", []).is_empty() or not tw.get("t", []).is_empty())
		if drawn:
			n_h = 0
			var hc := hex_pos(h)
			var wall := Color(0.93, 0.87, 0.72) if not s["fort"] else Color(0.86, 0.82, 0.74)
			for e in tw.get("h", []):
				var px := hc.x + float(e[0]) * PX
				var pz := hc.z + float(e[1]) * PX
				var y := height_at(px, pz)
				var w := float(e[2]) * PX * 1.2
				var hh := w * 0.8
				var rcol := Color(float(e[3]), float(e[4]), float(e[5]))
				rcol = Color.from_hsv(rcol.h, minf(1.0, rcol.s * 1.45), minf(1.0, rcol.v * 1.18))
				var b := Basis().rotated(Vector3.UP, r.randf_range(-0.25, 0.25))
				parts["body"].append([Transform3D(b.scaled(Vector3(w, hh, w * 0.8)), Vector3(px, y + hh / 2, pz)), wall.darkened(r.randf() * 0.12)])
				parts["roof"].append([Transform3D(b.scaled(Vector3(w * 1.15, hh * 0.85, w * 0.88)), Vector3(px, y + hh + hh * 0.42, pz)), rcol])
			for e in tw.get("t", []):
				var px2 := hc.x + float(e[0]) * PX
				var pz2 := hc.z + float(e[1]) * PX
				var y2 := height_at(px2, pz2)
				var rad := float(e[2]) * PX * 0.75
				var th := float(e[3]) * PX * 0.75
				var scol := Color(float(e[4]), float(e[5]), float(e[6])).lightened(0.1)
				parts["tower"].append([Transform3D(Basis().scaled(Vector3(rad, th, rad)), Vector3(px2, y2 + th / 2, pz2)), scol])
				parts["cap"].append([Transform3D(Basis().scaled(Vector3(rad * 1.1, rad * 1.1, rad * 1.1)), Vector3(px2, y2 + th + rad * 0.55, pz2)), Color("#7a3a2a") if s["city"] else Color("#3e4a5c")])
		var rad := 0.26 if s["city"] else 0.16
		for i in range(n_h):
			var a := r.randf() * TAU
			var d := r.randf_range(0.05, rad)
			var px := c.x + cos(a) * d
			var pz := c.z + sin(a) * d
			var y := height_at(px, pz)
			var w := r.randf_range(0.06, 0.09)
			var hh := r.randf_range(0.05, 0.075)
			var rot := r.randf() * TAU
			var b := Basis().rotated(Vector3.UP, rot)
			parts["body"].append([Transform3D(b.scaled(Vector3(w, hh, w * 0.8)), Vector3(px, y + hh / 2, pz)), Color(0.86, 0.80, 0.68).darkened(r.randf() * 0.2)])
			parts["roof"].append([Transform3D(b.scaled(Vector3(w * 1.15, hh * 0.7, w * 0.85)), Vector3(px, y + hh + hh * 0.35, pz)), [Color("#8a3a26"), Color("#5a4636"), Color("#4b5560")][r.randi() % 3]])
		if (s["fort"] > 0 or s["city"]) and not drawn:
			var nt := 4 if s["city"] else 1
			for i in range(nt):
				var a2 := TAU * i / nt + 0.4
				var d2 := 0.27 if s["city"] else 0.06
				var px2 := c.x + cos(a2) * d2
				var pz2 := c.z + sin(a2) * d2
				var y2 := height_at(px2, pz2)
				var th := 0.19 if s["fort"] > 0 else 0.12
				parts["tower"].append([Transform3D(Basis().scaled(Vector3(0.07, th, 0.07)), Vector3(px2, y2 + th / 2, pz2)), Color("#9a958c")])
				parts["cap"].append([Transform3D(Basis().scaled(Vector3(0.08, 0.08, 0.08)), Vector3(px2, y2 + th + 0.04, pz2)), Color("#3e4a5c") if s["fort"] < 2 else Color("#5a2a7a")])
		var rng_list := []
		for k in parts:
			rng_list.append([k, start[k], parts[k].size()])
		set_ranges[h] = rng_list
		# bandierina del controllo
		var pole := MeshInstance3D.new()
		var pmesh := BoxMesh.new()
		pmesh.size = Vector3(0.012, 0.32, 0.012)
		pole.mesh = pmesh
		var flag := MeshInstance3D.new()
		var fm := BoxMesh.new()
		fm.size = Vector3(0.12, 0.075, 0.008)
		flag.mesh = fm
		flag.position = Vector3(0.06, 0.12, 0)
		var fmat := StandardMaterial3D.new()
		fmat.albedo_color = Color.WHITE
		flag.material_override = fmat
		pole.add_child(flag)
		var pmat := StandardMaterial3D.new()
		pmat.albedo_color = Color("#3a2a1a")
		pole.material_override = pmat
		pole.position = c + Vector3(0.0, 0.16 + (0.1 if s["city"] else 0.0), -0.05)
		add_child(pole)
		set_flags[h] = flag
		# porto: un pontile e una barca verso l'acqua
		if s["port"]:
			var best := Vector3.ZERO
			var bh := 9.0
			for i in range(12):
				var a3 := TAU * i / 12.0
				var p := c + Vector3(cos(a3), 0, sin(a3)) * 0.55
				var y3 := height_at(p.x, p.z)
				if y3 < bh:
					bh = y3
					best = p
			if bh < 0.0:
				var dir := (best - c).normalized()
				var dock := MeshInstance3D.new()
				var dm := BoxMesh.new()
				dm.size = Vector3(0.05, 0.02, 0.34)
				dock.mesh = dm
				var dmat := StandardMaterial3D.new()
				dmat.albedo_color = Color("#6b4a2a")
				dock.material_override = dmat
				var mid := c + dir * 0.36
				dock.position = Vector3(mid.x, 0.03, mid.z)
				dock.rotation.y = atan2(dir.x, dir.z)
				add_child(dock)
				add_child(_boat(c + dir * 0.52 + dir.cross(Vector3.UP) * 0.08, atan2(dir.x, dir.z)))
		# nome
		var lb := Label3D.new()
		lb.text = s["n"]
		lb.font_size = 44
		lb.outline_size = 10
		lb.modulate = Color("#f4ead2")
		lb.outline_modulate = Color(0, 0, 0, 0.85)
		lb.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		lb.pixel_size = 0.0028
		lb.position = c + Vector3(0, 0.5 + (0.1 if s["city"] else 0.0), 0.0)
		lb.no_depth_test = false
		add_child(lb)
		labels[h] = lb
	for k in parts:
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.mesh = {"body": body, "roof": roof, "tower": tower, "cap": cap}[k]
		mm.instance_count = parts[k].size()
		for i in range(parts[k].size()):
			mm.set_instance_transform(i, parts[k][i][0])
			mm.set_instance_color(i, parts[k][i][1])
		var node := MultiMeshInstance3D.new()
		node.multimesh = mm
		var mat := StandardMaterial3D.new()
		mat.vertex_color_use_as_albedo = true
		mat.roughness = 0.85
		node.material_override = mat
		node.set_meta("kind", k)
		add_child(node)
		for h in set_ranges:
			for rr in set_ranges[h]:
				if rr[0] == k:
					rr.append(node)
					rr.append([])
					for i in range(int(rr[1]), int(rr[2])):
						rr[4].append(parts[k][i][1])
	if spire >= 0:
		var c2 := hex_pos(spire)
		var sp := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.0
		cm.bottom_radius = 0.13
		cm.height = 1.6
		cm.radial_segments = 6
		sp.mesh = cm
		var smat := StandardMaterial3D.new()
		smat.albedo_color = Color("#1a1420")
		smat.emission_enabled = true
		smat.emission = Color("#6a2a9a")
		smat.emission_energy_multiplier = 0.35
		sp.material_override = smat
		sp.position = c2 + Vector3(0, 0.8, 0)
		add_child(sp)
		var glow := OmniLight3D.new()
		glow.light_color = Color("#a050ff")
		glow.omni_range = 1.4
		glow.light_energy = 1.2
		glow.position = c2 + Vector3(0, 1.7, 0)
		add_child(glow)


func _boat(p: Vector3, rot: float) -> Node3D:
	var n := Node3D.new()
	var hull := MeshInstance3D.new()
	var pm := PrismMesh.new()
	pm.size = Vector3(0.06, 0.04, 0.16)
	hull.mesh = pm
	hull.rotation_degrees = Vector3(180, 0, 0)
	var m := StandardMaterial3D.new()
	m.albedo_color = Color("#5a3a20")
	hull.material_override = m
	n.add_child(hull)
	var mast := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.008, 0.12, 0.008)
	mast.mesh = bm
	mast.position = Vector3(0, 0.07, 0)
	n.add_child(mast)
	var sail := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(0.07, 0.07)
	sail.mesh = qm
	var sm := StandardMaterial3D.new()
	sm.albedo_color = Color("#e8dcc0")
	sm.cull_mode = BaseMaterial3D.CULL_DISABLED
	sail.material_override = sm
	sail.position = Vector3(0, 0.08, 0)
	sail.rotation_degrees = Vector3(0, 90, 0)
	n.add_child(sail)
	n.position = Vector3(p.x, 0.0, p.z)
	n.rotation.y = rot
	return n


## Tane (rocce scure con una luce arancione) e miniere (ingresso con travi).
func _features() -> void:
	for h in D.hexes:
		if not eng.in_map(h):
			continue
		var e: Dictionary = D.hexes[h]
		var c := hex_pos(h)
		if str(e["lair"]) != "":
			var n := Node3D.new()
			var sea: bool = e["lair"] == "S"
			if sea:
				var tor := MeshInstance3D.new()
				var tm := TorusMesh.new()
				tm.inner_radius = 0.16
				tm.outer_radius = 0.24
				tor.mesh = tm
				var mat := StandardMaterial3D.new()
				mat.albedo_color = Color("#1b4a5a")
				mat.emission_enabled = true
				mat.emission = Color("#30c0ff")
				mat.emission_energy_multiplier = 0.6
				tor.material_override = mat
				n.add_child(tor)
				n.position = Vector3(c.x, 0.02, c.z)
				n.set_meta("spin", true)
			else:
				var r := RandomNumberGenerator.new()
				r.seed = h
				for i in range(4):
					var rock := MeshInstance3D.new()
					var bm := BoxMesh.new()
					var s := r.randf_range(0.07, 0.14)
					bm.size = Vector3(s, s * r.randf_range(1.0, 2.4), s)
					rock.mesh = bm
					var a := TAU * i / 4.0 + r.randf()
					rock.position = Vector3(cos(a) * 0.15, bm.size.y / 2, sin(a) * 0.15)
					rock.rotation = Vector3(r.randf() * 0.4, r.randf() * TAU, r.randf() * 0.4)
					var mat2 := StandardMaterial3D.new()
					mat2.albedo_color = Color("#2a2622")
					rock.material_override = mat2
					n.add_child(rock)
				var orb := MeshInstance3D.new()
				var sm := SphereMesh.new()
				sm.radius = 0.05
				sm.height = 0.1
				orb.mesh = sm
				var om := StandardMaterial3D.new()
				om.albedo_color = Color("#ff8a2a")
				om.emission_enabled = true
				om.emission = Color("#ff6a10")
				om.emission_energy_multiplier = 2.0
				orb.material_override = om
				orb.position = Vector3(0, 0.3, 0)
				n.add_child(orb)
				n.position = c
				n.set_meta("bob", orb)
			add_child(n)
			var lb := Label3D.new()
			lb.text = str(e["lair_n"])
			lb.font_size = 34
			lb.outline_size = 8
			lb.modulate = Color("#ffb070") if not sea else Color("#9fe0ff")
			lb.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			lb.pixel_size = 0.0026
			lb.position = c + Vector3(0, 0.55, 0.3)
			add_child(lb)
			labels[h] = lb
		if str(e["mine"]) != "":
			var n2 := Node3D.new()
			var wood := StandardMaterial3D.new()
			wood.albedo_color = Color("#6a4a28")
			for x in [-0.06, 0.06]:
				var post := MeshInstance3D.new()
				var pm := BoxMesh.new()
				pm.size = Vector3(0.02, 0.13, 0.02)
				post.mesh = pm
				post.position = Vector3(x, 0.065, 0)
				post.material_override = wood
				n2.add_child(post)
			var lint := MeshInstance3D.new()
			var lm := BoxMesh.new()
			lm.size = Vector3(0.16, 0.025, 0.025)
			lint.mesh = lm
			lint.position = Vector3(0, 0.135, 0)
			lint.material_override = wood
			n2.add_child(lint)
			var hole := MeshInstance3D.new()
			var hm := BoxMesh.new()
			hm.size = Vector3(0.1, 0.11, 0.03)
			hole.mesh = hm
			hole.position = Vector3(0, 0.055, -0.01)
			var black := StandardMaterial3D.new()
			black.albedo_color = Color("#080605")
			hole.material_override = black
			n2.add_child(hole)
			n2.position = c + Vector3(0.22, 0, 0.18)
			add_child(n2)
			var lb2 := Label3D.new()
			lb2.text = "Miniera: " + str(e["mine"])
			lb2.font_size = 30
			lb2.outline_size = 8
			lb2.modulate = Color("#ffe08a")
			lb2.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			lb2.pixel_size = 0.0024
			lb2.position = c + Vector3(0.2, 0.42, 0.25)
			add_child(lb2)
			labels[-h - 1] = lb2


# ================================================================== pezzi

func _pieces_init() -> void:
	block_mesh = BoxMesh.new()
	block_mesh.size = Vector3(0.27, 0.29, 0.1)
	hero_mesh = BoxMesh.new()
	hero_mesh.size = Vector3(0.2, 0.37, 0.085)
	face_mesh = QuadMesh.new()
	face_mesh.size = Vector2(0.245, 0.245)
	hero_face = QuadMesh.new()
	hero_face.size = Vector2(0.18, 0.18)
	disc_mesh = CylinderMesh.new()
	disc_mesh.top_radius = 0.13
	disc_mesh.bottom_radius = 0.13
	disc_mesh.height = 0.035
	disc_mesh.radial_segments = 18
	disc_mesh.rings = 1
	disc_top = QuadMesh.new()
	disc_top.size = Vector2(0.24, 0.24)
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_CELLULAR
	noise.frequency = 0.02
	var nt := NoiseTexture2D.new()
	nt.width = 128
	nt.height = 128
	nt.noise = noise
	nt.seamless = true
	wood_tex = nt
	sel_ring = MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.33
	tm.outer_radius = 0.38
	sel_ring.mesh = tm
	var sm := StandardMaterial3D.new()
	sm.albedo_color = Color("#ffd86a")
	sm.emission_enabled = true
	sm.emission = Color("#ffc43a")
	sm.emission_energy_multiplier = 1.4
	sel_ring.material_override = sm
	sel_ring.visible = false
	add_child(sel_ring)


func _face_mat(key: String, dimmed := false) -> StandardMaterial3D:
	var ck := key + ("#d" if dimmed else "")
	if mat_cache.has(ck):
		return mat_cache[ck]
	var m := StandardMaterial3D.new()
	m.albedo_texture = atlas
	var idx: int = int(counters["idx"].get(key, 0))
	var cols := int(counters["cols"])
	var rows := int(ceil(195.0 / cols))
	var tw := float(atlas.get_width())
	var th := float(atlas.get_height())
	var cell := float(counters["cell"])
	m.uv1_scale = Vector3(cell / tw, cell / th, 1)
	m.uv1_offset = Vector3((idx % cols) * cell / tw, (idx / cols) * cell / th, 0)
	m.roughness = 0.8
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	m.alpha_scissor_threshold = 0.4
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	# un po' di luce propria: la faccia stampata si legge anche in ombra
	m.emission_enabled = true
	m.emission_texture = atlas
	m.emission = Color(1, 1, 1)
	m.emission_energy_multiplier = 0.05 if dimmed else 0.15
	if dimmed:
		m.albedo_color = Color(0.55, 0.55, 0.55)
	rows = rows
	mat_cache[ck] = m
	return m


func _wood_mat(col: Color, dimmed := false) -> StandardMaterial3D:
	var ck := "w" + col.to_html() + ("d" if dimmed else "")
	if mat_cache.has(ck):
		return mat_cache[ck]
	var m := StandardMaterial3D.new()
	m.albedo_texture = wood_tex
	m.albedo_color = (col.lerp(Color("#c8a070"), 0.18)) * (0.6 if dimmed else 1.0)
	m.albedo_color.a = 1.0
	m.roughness = 0.7
	m.uv1_scale = Vector3(0.6, 2.2, 1)
	mat_cache[ck] = m
	return m


func _unit_key(u: Dictionary) -> String:
	if u["kind"] == "army":
		var img: String = D.unit_img(u["t"], int(u.get("v", 0)))
		if u["weak"] and counters["idx"].has(img + "_b"):
			return img + "_b"
		return img
	if u["kind"] == "ehero":
		return "n_ensl"
	return u["t"]


## Pedina di cartoncino: quadrato con gli angoli arrotondati, spessa qualche millimetro.
## Superficie 0: la faccia stampata (UV 0..1 sul quadrato); superficie 1: bordi e retro.
func _counter_mesh(side: float, thick: float, rad: float) -> ArrayMesh:
	var key := "cm%.3f/%.3f" % [side, thick]
	if mat_cache.has(key):
		return mat_cache[key]
	var outline := PackedVector2Array()
	var hs := side / 2.0 - rad
	var corners := [Vector2(hs, hs), Vector2(-hs, hs), Vector2(-hs, -hs), Vector2(hs, -hs)]
	for ci in range(4):
		for j in range(6):
			var a := (ci + j / 5.0) * PI / 2.0
			outline.append(corners[ci] + Vector2(cos(a), sin(a)) * rad)
	var n := outline.size()
	var mesh := ArrayMesh.new()
	# faccia
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(n):
		var p0 := outline[i]
		var p1 := outline[(i + 1) % n]
		for q in [Vector2.ZERO, p1, p0]:
			st.set_normal(Vector3.UP)
			st.set_uv(Vector2(q.x / side + 0.5, q.y / side + 0.5))
			st.add_vertex(Vector3(q.x, thick, q.y))
	st.commit(mesh)
	# bordi e retro
	var sb := SurfaceTool.new()
	sb.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(n):
		var p0 := outline[i]
		var p1 := outline[(i + 1) % n]
		var nm := Vector3(p0.x + p1.x, 0, p0.y + p1.y).normalized()
		for v in [Vector3(p0.x, 0, p0.y), Vector3(p1.x, 0, p1.y), Vector3(p1.x, thick, p1.y), Vector3(p0.x, 0, p0.y), Vector3(p1.x, thick, p1.y), Vector3(p0.x, thick, p0.y)]:
			sb.set_normal(nm)
			sb.add_vertex(v)
		for q in [Vector2.ZERO, p0, p1]:
			sb.set_normal(Vector3.DOWN)
			sb.add_vertex(Vector3(q.x, 0, q.y))
	sb.commit(mesh)
	mat_cache[key] = mesh
	return mesh


func _edge_mat(col: Color) -> StandardMaterial3D:
	var ck := "e" + col.to_html()
	if mat_cache.has(ck):
		return mat_cache[ck]
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = 0.85
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat_cache[ck] = m
	return m


func _make_block(u: Dictionary) -> Node3D:
	var root := Node3D.new()
	var hero: bool = u["kind"] != "army"
	var c := MeshInstance3D.new()
	c.mesh = _counter_mesh(0.215 if hero else 0.25, 0.034, 0.028)
	c.name = "Counter"
	root.add_child(c)
	root.set_meta("hero", hero)
	add_child(root)
	_style_block(root, u)
	return root


func _style_block(root: Node3D, u: Dictionary) -> void:
	var own: int = eng.owner(u)
	var col: Color = D.KINGDOMS[own]["col"]
	var fin: bool = u["fin"] and own == eng.cur_k
	var c: MeshInstance3D = root.get_node("Counter")
	c.set_surface_override_material(0, _face_mat(_unit_key(u), fin))
	var edge: Color = Color("#d9b45a") if root.get_meta("hero") else col.darkened(0.25)
	if fin:
		edge = edge.darkened(0.4)
	c.set_surface_override_material(1, _edge_mat(edge))
	root.set_meta("weak", u["weak"])
	root.set_meta("fin", fin)


func _make_monster(h: int) -> Node3D:
	var m: Dictionary = eng.monsters[h]
	var root := Node3D.new()
	var plate := MeshInstance3D.new()
	plate.mesh = _counter_mesh(0.25, 0.034, 0.028)
	plate.name = "Face"
	var key: String = m["m"] if not m["def"] else ("m_sea" if D.monster(m["m"]).get("sea", false) else "m_land")
	plate.set_surface_override_material(0, _face_mat(key, m["def"]))
	plate.set_surface_override_material(1, _edge_mat(Color("#2a2622")))
	root.add_child(plate)
	if int(m["cmd"]) >= 0:
		var ring := MeshInstance3D.new()
		var tm := TorusMesh.new()
		tm.inner_radius = 0.19
		tm.outer_radius = 0.215
		ring.mesh = tm
		var rm := StandardMaterial3D.new()
		rm.albedo_color = D.KINGDOMS[int(m["cmd"])]["light"]
		rm.emission_enabled = true
		rm.emission = D.KINGDOMS[int(m["cmd"])]["light"]
		rm.emission_energy_multiplier = 0.5
		ring.material_override = rm
		ring.position = Vector3(0, 0.012, 0)
		root.add_child(ring)
	root.set_meta("mon", m["m"] + str(m["def"]) + str(m["cmd"]))
	add_child(root)
	return root


func _make_marker(kind: String, h: int, k: int) -> Node3D:
	var root := Node3D.new()
	var disc := MeshInstance3D.new()
	disc.mesh = disc_mesh
	disc.position = Vector3(0, 0.0175, 0)
	var dm := StandardMaterial3D.new()
	match kind:
		"c":
			dm.albedo_color = D.KINGDOMS[k]["col"]
		"v":
			dm.albedo_color = Color("#3a1440")
		"r":
			dm.albedo_color = Color("#1a1512")
	disc.material_override = dm
	root.add_child(disc)
	var top := MeshInstance3D.new()
	top.mesh = disc_top
	top.rotation_degrees = Vector3(-90, 0, 0)
	top.position = Vector3(0, 0.037, 0)
	var key := "razed"
	if kind == "c":
		key = "c_%d" % k
	elif kind == "v":
		key = "coven"
	top.material_override = _face_mat(key)
	root.add_child(top)
	if kind == "r":
		var smoke := CPUParticles3D.new()
		smoke.amount = 10
		smoke.lifetime = 2.6
		smoke.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
		smoke.emission_sphere_radius = 0.12
		smoke.direction = Vector3(0, 1, 0)
		smoke.spread = 12.0
		smoke.initial_velocity_min = 0.08
		smoke.initial_velocity_max = 0.16
		smoke.gravity = Vector3(0.02, 0.02, 0)
		smoke.scale_amount_min = 0.6
		smoke.scale_amount_max = 1.2
		var sm := SphereMesh.new()
		sm.radius = 0.05
		sm.height = 0.1
		smoke.mesh = sm
		var pmat := StandardMaterial3D.new()
		pmat.albedo_color = Color(0.2, 0.18, 0.16, 0.45)
		pmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		pmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		smoke.material_override = pmat
		smoke.position = Vector3(0, 0.2, 0)
		root.add_child(smoke)
	add_child(root)
	return root


## Rialzo delle pedine dove il terreno o gli alberi potrebbero nasconderle.
func _lift(h: int) -> float:
	if eng.is_mountain(h):
		return 0.12
	if eng.is_forest(h):
		return 0.16
	return 0.01


## Altezza massima del terreno sotto l'impronta di un pezzo (così non affonda nei pendii).
func _foot_h(p: Vector3, r: float) -> float:
	var y := maxf(height_at(p.x, p.z), 0.0)
	for o in [Vector2(r, 0), Vector2(-r, 0), Vector2(0, r), Vector2(0, -r), Vector2(r, r) * 0.7, Vector2(-r, -r) * 0.7, Vector2(r, -r) * 0.7, Vector2(-r, r) * 0.7]:
		y = maxf(y, height_at(p.x + o.x, p.z + o.y))
	return y


## Posizione di un pezzo nell'esagono h. slot: "army", "hero", "c", "v", "r", "mon".
func _slot(h: int, slot: String) -> Vector3:
	var c := hex_pos(h)
	var off := Vector3.ZERO
	match slot:
		"army":
			off = Vector3(0.0, 0, 0.36)
		"hero":
			off = Vector3(0.24, 0, 0.18)
		"c":
			off = Vector3(-0.38, 0, -0.26)
		"v":
			off = Vector3(0.36, 0, -0.26)
		"r":
			off = Vector3(-0.02, 0, -0.38)
		"mon":
			off = Vector3(0.0, 0, 0.0)
	var p := c + off
	p.y = _foot_h(p, 0.12)
	if eng.is_settlement(h) or (D.hexes.has(h) and int(D.hexes[h]["s"]) >= 0):
		p.y = maxf(p.y, c.y)
	return p


## Posizione di ogni pedina: le armate dello stesso regno in fila, gli eroi a lato;
## con due regni nello stesso esagono (assedio) chi controlla l'insediamento sta dietro.
func _stack_places() -> Dictionary:
	var by_hex := {}
	for u in eng.units:
		var h := int(u["h"])
		if h < 0:
			continue
		if not by_hex.has(h):
			by_hex[h] = []
		by_hex[h].append(u)
	var out := {}
	for h in by_hex:
		var us: Array = by_hex[h]
		var owners: Array = []
		for u in us:
			var o: int = eng.owner(u)
			if not o in owners:
				owners.append(o)
		var ctl: int = eng.controller(h) if eng.is_settlement(h) else -1
		owners.sort_custom(func(a, b): return (1 if a == ctl else 0) < (1 if b == ctl else 0))
		var base := _slot(h, "army")
		for oi in range(owners.size()):
			var row: Array = us.filter(func(x): return eng.owner(x) == owners[oi])
			var arm: Array = row.filter(func(x): return x["kind"] == "army")
			var her: Array = row.filter(func(x): return x["kind"] != "army")
			var n := arm.size() + her.size()
			var z := 0.0 if owners.size() == 1 else (0.1 - 0.42 * oi)
			var i := 0
			for u in arm + her:
				var x := (i - (n - 1) / 2.0) * (0.58 if n <= 2 else 0.4)
				var p := base + Vector3(x, 0, z)
				p.y = maxf(_foot_h(p, 0.3), base.y) + _lift(h)
				out[int(u["id"])] = p
				i += 1
	return out


## Sincronizza pedine e segnalini con lo stato del motore.
func refresh() -> void:
	if eng == null:
		return
	var seen := {}
	var places := _stack_places()
	for u in eng.units:
		var h := int(u["h"])
		if h < 0:
			continue
		var id := int(u["id"])
		seen[id] = true
		var b: Node3D = blocks.get(id, null)
		var p: Vector3 = places.get(id, _slot(h, "army"))
		if b == null:
			b = _make_block(u)
			b.position = p + Vector3(0, 0.6, 0)
			b.scale = Vector3.ONE * 0.2 * PIECE
			blocks[id] = b
		elif b.get_meta("weak") != u["weak"] or b.get_meta("fin") != (u["fin"] and eng.owner(u) == eng.cur_k) or b.get_meta("own", -1) != eng.owner(u):
			_style_block(b, u)
		b.set_meta("own", eng.owner(u))
		b.set_meta("target", p)
		b.set_meta("hex", h)
	for id in blocks.keys():
		if not seen.has(id):
			var b2: Node3D = blocks[id]
			blocks.erase(id)
			var tw := b2.create_tween()
			tw.tween_property(b2, "scale", Vector3(0.05, 0.05, 0.05), 0.35)
			tw.tween_callback(b2.queue_free)
	# mostri
	var mseen := {}
	for h in eng.monsters:
		mseen[h] = true
		var key := str(eng.monsters[h]["m"]) + str(eng.monsters[h]["def"]) + str(eng.monsters[h]["cmd"])
		var n: Node3D = mon_nodes.get(h, null)
		if n != null and n.get_meta("mon") != key:
			n.queue_free()
			n = null
		if n == null:
			n = _make_monster(h)
			n.scale = Vector3.ONE * TOKEN
			n.position = _slot(h, "mon") + Vector3(0, _lift(h), 0)
			mon_nodes[h] = n
	for h in mon_nodes.keys():
		if not mseen.has(h):
			mon_nodes[h].queue_free()
			mon_nodes.erase(h)
	# segnalini
	var want := {}
	for h in eng.ctrl:
		want["c:%d" % h] = int(eng.ctrl[h])
	for h in eng.coven:
		want["v:%d" % h] = 0
	for h in eng.razed:
		if eng.in_map(h):
			want["r:%d" % h] = -1
	for key in mark_nodes.keys():
		var n2: Node3D = mark_nodes[key]
		if not want.has(key) or int(n2.get_meta("k", -9)) != int(want[key]):
			n2.queue_free()
			mark_nodes.erase(key)
	for key in want:
		if mark_nodes.has(key):
			continue
		var parts: PackedStringArray = key.split(":")
		var h2 := int(parts[1])
		var n3 := _make_marker(parts[0], h2, int(want[key]))
		n3.scale = Vector3.ONE * TOKEN
		n3.position = _slot(h2, parts[0])
		n3.set_meta("k", int(want[key]))
		mark_nodes[key] = n3
	# bandierine e rovine
	for h in set_flags:
		var flag: MeshInstance3D = set_flags[h]
		var c: int = eng.controller(h)
		var fm: StandardMaterial3D = flag.material_override
		if eng.razed.has(h) or not (eng.inplay.has(h)):
			flag.get_parent().visible = false
		else:
			flag.get_parent().visible = true
			fm.albedo_color = D.KINGDOMS[c]["light"] if c >= 0 else Color("#e0d8c8")
		_burn(h, eng.razed.has(h) or not eng.inplay.has(h), not eng.inplay.has(h))
	if eng.khazud >= 0 and khazud_node == null:
		khazud_node = _make_marker("c", eng.khazud, D.OATH)
		var kz := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.1
		cm.bottom_radius = 0.2
		cm.height = 0.45
		cm.radial_segments = 8
		kz.mesh = cm
		var km := StandardMaterial3D.new()
		km.albedo_color = Color("#b8c4d0")
		kz.material_override = km
		kz.position = Vector3(0, 0.25, 0)
		khazud_node.add_child(kz)
		khazud_node.position = hex_pos(eng.khazud)


func _burn(h: int, burnt: bool, grey: bool) -> void:
	var key := ("g" if grey else ("b" if burnt else "n"))
	if ruins.get(h, "n") == key:
		return
	ruins[h] = key
	for rr in set_ranges.get(h, []):
		if rr.size() < 5:
			continue
		var node: MultiMeshInstance3D = rr[3]
		var cols: Array = rr[4]
		for i in range(int(rr[1]), int(rr[2])):
			var c: Color = cols[i - int(rr[1])]
			if grey:
				c = c.lerp(Color(0.5, 0.5, 0.5), 0.6)
			elif burnt:
				c = c.darkened(0.75)
			node.multimesh.set_instance_color(i, c)


# ================================================================== evidenziazioni

func set_highlights(d: Dictionary) -> void:
	hl = d
	hl_img.fill(Color(0, 0, 0, 0))
	for h in d:
		var c: int = int(h) / 100
		var r: int = int(h) % 100
		if c < 32 and r < 32:
			hl_img.set_pixel(c, r, d[h])
	hl_tex.update(hl_img)


func clear_highlights() -> void:
	set_highlights({})


func select_hex(h: int) -> void:
	sel_hex = h
	sel_ring.visible = h >= 0
	if h >= 0:
		sel_ring.position = hex_pos(h) + Vector3(0, 0.03, 0)


# ================================================================== telecamera e input

func _camera() -> void:
	cam = Camera3D.new()
	cam.fov = 40
	cam.near = 0.05
	cam.far = 200
	add_child(cam)
	cam.current = true
	var span := maxf(bounds.size.x, bounds.size.y)
	target = Vector3(bounds.get_center().x - span * 0.03, 0, bounds.get_center().y + bounds.size.y * 0.06)
	dist = clampf(maxf(bounds.size.y * 1.3, bounds.size.x * 1.0), 6, 68)
	want_target = target
	want_dist = dist
	_place_cam()


func focus(h: int, zoom := -1.0) -> void:
	if h < 0:
		return
	want_target = hex_pos(h)
	if zoom > 0:
		want_dist = zoom


func _place_cam() -> void:
	var p := deg_to_rad(pitch)
	var y := deg_to_rad(yaw)
	var off := Vector3(sin(y) * cos(p), sin(p), cos(y) * cos(p)) * dist
	cam.position = target + off
	cam.look_at(target, Vector3.UP)


func _process(delta: float) -> void:
	time_s += delta
	for m in terrain_mats:
		m.set_shader_parameter("time_s", time_s)
	if water_mat != null:
		water_mat.set_shader_parameter("time_s", time_s)
	var t := 1.0 - exp(-delta * 9.0)
	target = target.lerp(want_target, t)
	yaw = lerpf(yaw, want_yaw, t)
	pitch = lerpf(pitch, want_pitch, t)
	dist = lerpf(dist, want_dist, t)
	if cam != null:
		_place_cam()
	var kb := Vector3.ZERO
	if input_enabled and not _text_focus():
		if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
			kb.z -= 1
		if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
			kb.z += 1
		if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
			kb.x -= 1
		if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
			kb.x += 1
		if Input.is_key_pressed(KEY_Q):
			want_yaw += 70 * delta
		if Input.is_key_pressed(KEY_E):
			want_yaw -= 70 * delta
		if Input.is_key_pressed(KEY_R):
			want_pitch = clampf(want_pitch + 40 * delta, 18, 86)
		if Input.is_key_pressed(KEY_F):
			want_pitch = clampf(want_pitch - 40 * delta, 18, 86)
	if kb != Vector3.ZERO:
		_pan_world(kb.normalized() * dist * 0.9 * delta)
	# pedine: scivolano verso la loro posizione e si girano verso la telecamera
	var cy := deg_to_rad(yaw)
	for id in blocks:
		var b: Node3D = blocks[id]
		var p: Vector3 = b.get_meta("target", b.position)
		b.position = b.position.lerp(p, 1.0 - exp(-delta * 7.0))
		b.scale = b.scale.lerp(Vector3.ONE * PIECE, 1.0 - exp(-delta * 8.0))
		var fin_rot := 0.35 if b.get_meta("fin", false) else 0.0
		b.rotation = Vector3(0, cy + fin_rot, 0)
	for h in mon_nodes:
		var n: Node3D = mon_nodes[h]
		var f: Node3D = n.get_node_or_null("Face")
		if f != null:
			f.rotation = Vector3(0, cy, 0)
	# etichette visibili solo da vicino
	var show := dist < 16
	for k in labels:
		labels[k].visible = show
	if sel_ring.visible:
		sel_ring.rotation.y += delta


func _text_focus() -> bool:
	var f := get_viewport().gui_get_focus_owner()
	return f is LineEdit or f is TextEdit


func _pan_world(v: Vector3) -> void:
	var y := deg_to_rad(want_yaw)
	var fwd := Vector3(sin(y), 0, cos(y))
	var right := Vector3(cos(y), 0, -sin(y))
	want_target += right * v.x + fwd * v.z
	want_target.x = clampf(want_target.x, bounds.position.x, bounds.end.x)
	want_target.z = clampf(want_target.z, bounds.position.y, bounds.end.y)


func screen_to_hex(pos: Vector2) -> int:
	if cam == null:
		return -1
	var o := cam.project_ray_origin(pos)
	var d := cam.project_ray_normal(pos)
	if absf(d.y) < 0.0001:
		return -1
	var y := 0.0
	var p := Vector3.ZERO
	for i in range(4):
		var t := (y - o.y) / d.y
		p = o + d * t
		y = maxf(height_at(p.x, p.z), 0.0)
	return hex_at(p.x, p.z)


func handle_input(ev: InputEvent) -> bool:
	if not input_enabled:
		return false
	if ev is InputEventMouseButton:
		var mb := ev as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			want_dist = clampf(want_dist * 0.88, 2.2, 70)
			return true
		if mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			want_dist = clampf(want_dist * 1.13, 2.2, 70)
			return true
		if mb.pressed:
			drag_btn = mb.button_index
			drag_moved = 0.0
			press_pos = mb.position
			return true
		if not mb.pressed and mb.button_index == drag_btn:
			var was := drag_btn
			drag_btn = -1
			if drag_moved < 6.0 and (was == MOUSE_BUTTON_LEFT or was == MOUSE_BUTTON_RIGHT):
				var h := screen_to_hex(mb.position)
				var now := Time.get_ticks_msec()
				if was == MOUSE_BUTTON_LEFT and now - last_click_t < 320 and h >= 0:
					focus(h, minf(want_dist, 7.0))
				last_click_t = now
				hex_clicked.emit(h, was)
			return true
	elif ev is InputEventMouseMotion:
		var mm := ev as InputEventMouseMotion
		if drag_btn >= 0:
			drag_moved += mm.relative.length()
			if drag_moved < 6.0:
				return true
			if drag_btn == MOUSE_BUTTON_RIGHT or (drag_btn == MOUSE_BUTTON_LEFT and mm.shift_pressed):
				want_yaw -= mm.relative.x * 0.3
				want_pitch = clampf(want_pitch + mm.relative.y * 0.25, 18, 86)
			else:
				var f := dist * 0.0016
				_pan_world(Vector3(-mm.relative.x * f, 0, -mm.relative.y * f))
			return true
		var h2 := screen_to_hex(mm.position)
		if h2 != hover_h:
			hover_h = h2
			for m in terrain_mats:
				m.set_shader_parameter("hover", Vector2(h2 / 100, h2 % 100) if h2 >= 0 else Vector2(-99, -99))
			hex_hovered.emit(h2)
	elif ev is InputEventPanGesture:
		var pg := ev as InputEventPanGesture
		_pan_world(Vector3(pg.delta.x, 0, pg.delta.y) * dist * 0.02)
		return true
	elif ev is InputEventMagnifyGesture:
		var mg := ev as InputEventMagnifyGesture
		want_dist = clampf(want_dist / mg.factor, 2.2, 70)
		return true
	return false


## Piccolo lampo in un esagono (combattimenti, saccheggi).
func flash(h: int, col: Color) -> void:
	if h < 0:
		return
	var l := OmniLight3D.new()
	l.light_color = col
	l.omni_range = 1.6
	l.light_energy = 3.0
	l.position = hex_pos(h) + Vector3(0, 0.6, 0)
	add_child(l)
	var tw := l.create_tween()
	tw.tween_property(l, "light_energy", 0.0, 0.8)
	tw.tween_callback(l.queue_free)
