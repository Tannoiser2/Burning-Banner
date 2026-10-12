"""Prova della versione web nel browser (Playwright + Chromium, WebGL2 software).
Uso: python3 tests/web_test.py [cartella dell'esportazione web]  (predefinita build/web)
Apre il gioco, aspetta il menu, avvia una partita (campagna predefinita) e lascia giocare l'IA
qualche secondo: la prova fallisce se nella console compaiono errori."""
import functools, http.server, sys, threading, time, os
from playwright.sync_api import sync_playwright

root = sys.argv[1] if len(sys.argv) > 1 else "build/web"
out = os.environ.get("BB_WEB_SHOTS", "/tmp")
handler = functools.partial(http.server.SimpleHTTPRequestHandler, directory=root)
handler.log_message = lambda *a: None
srv = http.server.ThreadingHTTPServer(("127.0.0.1", 8765), handler)
threading.Thread(target=srv.serve_forever, daemon=True).start()

errors, logs = [], []
IGNORE = ("favicon", "AudioContext", "audio", "GL_INVALID", "WebGL: ", "GPU stall", "Automatic fallback to software WebGL")

with sync_playwright() as p:
    b = p.chromium.launch(args=["--use-angle=swiftshader", "--enable-unsafe-swiftshader", "--ignore-gpu-blocklist", "--enable-webgl"])
    pg = b.new_page(viewport={"width": 1280, "height": 720})
    def on_console(m):
        logs.append(f"[{m.type}] {m.text}")
        if m.type == "error" and not any(s in m.text for s in IGNORE):
            errors.append(m.text)
    pg.on("console", on_console)
    pg.on("pageerror", lambda e: errors.append(f"pageerror: {e}"))
    pg.goto("http://127.0.0.1:8765/index.html")
    t0 = time.time()
    # attesa del caricamento (il pacchetto è grande e WebGL è software)
    while time.time() - t0 < 240:
        if any("Burning Banners" in l or "Godot Engine" in l for l in logs):
            break
        time.sleep(1)
    time.sleep(25)
    pg.screenshot(path=f"{out}/web_menu.png", timeout=180000)
    # "INIZIA PARTITA" (1920x1080 -> 1280x720)
    pg.mouse.click(680 * 2 / 3, 973 * 2 / 3)
    time.sleep(60)
    pg.screenshot(path=f"{out}/web_game.png", timeout=180000)
    b.close()
srv.shutdown()
print("\n".join(logs[-25:]))
if errors:
    print("ERRORI NELLA CONSOLE:")
    print("\n".join(errors))
    sys.exit(1)
print("OK: nessun errore nella console")
