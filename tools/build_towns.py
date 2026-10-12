"""Ricava dalle illustrazioni delle mappe le case e le torri di ogni insediamento (posizione, grandezza, colore),
così i modellini 3D ricalcano quelli disegnati. Uscita: data/towns.json"""
import json, colorsys
import numpy as np
from PIL import Image
from sklearn.cluster import KMeans

import os
R = os.path.dirname(os.path.dirname(os.path.abspath(__file__))) + "/"
w = json.load(open(R + "data/world.json"))
H = {h["h"]: h for h in w["hexes"]}
M = w["maps"]
imgs = {}
out = {}
for s in w["settlements"]:
    h = H[s["h"]]; m = M[h["m"]]
    if m["img"] not in imgs:
        imgs[m["img"]] = np.asarray(Image.open(R + "assets/maps/%s.jpg" % m["img"]).convert("RGB")).astype(np.float32) / 255.0
    a = imgs[m["img"]]
    cx = h["x"] - m["ox"]; cy = h["y"] - m["oy"]
    x0, x1 = int(max(0, cx - 72)), int(min(a.shape[1], cx + 72))
    y0, y1 = int(max(0, cy - 88)), int(min(a.shape[0], cy + 18))
    win = a[y0:y1, x0:x1]
    hsv = np.array([colorsys.rgb_to_hsv(*p) for p in win.reshape(-1, 3)]).reshape(win.shape)
    hh, ss, vv = hsv[..., 0] * 360, hsv[..., 1], hsv[..., 2]
    yy, xx = np.mgrid[y0:y1, x0:x1]
    # distanza ellittica dal centro del disegno (le illustrazioni stanno un po' sopra il centro dell'esagono)
    d = ((xx - cx) / 72.0) ** 2 + ((yy - (cy - 35)) / 55.0) ** 2
    inside = d < 1.0
    roof = inside & (ss > 0.38) & (vv > 0.35) & ((hh < 55) | (hh > 340))
    stone = inside & (ss < 0.16) & (vv > 0.35) & (vv < 0.72)
    res = {"h": [], "t": []}
    pts = np.argwhere(roof)
    if len(pts) >= 12:
        cap = 28 if s["city"] else (12 if s["fort"] else 8)
        n = int(np.clip(len(pts) / 50, 4, cap))
        km = KMeans(n_clusters=n, n_init=3, random_state=1).fit(pts)
        for k in range(n):
            sel = pts[km.labels_ == k]
            if len(sel) < 6:
                continue
            py, px = sel.mean(axis=0)
            col = win[sel[:, 0], sel[:, 1]].mean(axis=0)
            size = float(np.clip(np.sqrt(len(sel)) * 1.5, 7, 22))
            res["h"].append([round(float(px + x0 - cx), 1), round(float(py + y0 - cy), 1), round(size, 1)] + [round(float(c), 3) for c in col])
    sp = np.argwhere(stone)
    if (s["fort"] or s["city"]) and len(sp) >= 40:
        n = int(np.clip(len(sp) / 450, 1, 6 if s["city"] else 3))
        km = KMeans(n_clusters=n, n_init=3, random_state=1).fit(sp)
        for k in range(n):
            sel = sp[km.labels_ == k]
            if len(sel) < 25:
                continue
            py, px = sel.mean(axis=0)
            col = win[sel[:, 0], sel[:, 1]].mean(axis=0)
            hgt = float(np.clip(sel[:, 0].max() - sel[:, 0].min(), 14, 50))
            size = float(np.clip(np.sqrt(len(sel)) * 0.9, 8, 20))
            res["t"].append([round(float(px + x0 - cx), 1), round(float(py + y0 - cy), 1), round(size, 1), round(hgt, 1)] + [round(float(c), 3) for c in col])
    out[s["n"]] = res
json.dump(out, open(R + "data/towns.json", "w"), separators=(",", ":"))
print(len(out), sum(len(v["h"]) for v in out.values()), sum(len(v["t"]) for v in out.values()))
for n in ["Placidia", "Gorpin", "Megas", "Dwelfholm", "Arulud"]:
    print(n, len(out[n]["h"]), len(out[n]["t"]), out[n]["h"][:2], out[n]["t"][:1])
