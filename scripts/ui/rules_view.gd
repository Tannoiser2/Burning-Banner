extends Control
## Regole in breve. Si apre dal menu o durante la partita.

var main
var embedded := false
var on_close: Callable


func _ready() -> void:
	size = Vector2(1920, 1080)
	var sh := ColorRect.new()
	sh.color = Color(0, 0, 0, 0.72) if embedded else Color("#0d0a08")
	sh.size = size
	sh.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(sh)
	if not embedded:
		var bg := TextureRect.new()
		bg.texture = UI.tex("res://assets/maps/fields_of_ash.jpg")
		bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		bg.size = size
		bg.modulate = Color(0.2, 0.18, 0.17)
		add_child(bg)
	var box := PanelContainer.new()
	box.add_theme_stylebox_override("panel", UI.panel_style(Color("#140f0bf8"), UI.GOLD, 2, 10))
	box.position = Vector2(60, 26)
	box.custom_minimum_size = Vector2(1800, 1028)
	box.size = Vector2(1800, 1028)
	add_child(box)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)
	box.add_child(vb)
	var hb := HBoxContainer.new()
	vb.add_child(hb)
	var t := UI.title("BURNING BANNERS · LE REGOLE IN BREVE", 34)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_child(t)
	var close := UI.button("CHIUDI" if embedded else "INDIETRO", 180, 52, 24)
	close.pressed.connect(func():
		if embedded:
			on_close.call()
		else:
			main.show_menu())
	hb.add_child(close)
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 22)
	vb.add_child(cols)
	for txt in [_col1(), _col2(), _col3()]:
		var sc := ScrollContainer.new()
		sc.custom_minimum_size = Vector2(576, 940)
		sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		cols.add_child(sc)
		var r := RichTextLabel.new()
		r.bbcode_enabled = true
		r.fit_content = true
		r.custom_minimum_size = Vector2(556, 0)
		r.add_theme_font_size_override("normal_font_size", 19)
		r.add_theme_font_size_override("bold_font_size", 19)
		r.add_theme_font_size_override("italics_font_size", 19)
		r.text = txt
		sc.add_child(r)


func _h(t: String) -> String:
	return "[font_size=23][color=#e0a64a]%s[/color][/font_size]\n" % t


func _col1() -> String:
	return _h("Scopo") + """Due schieramenti: gli [b]Invasori[/b] (Armata della Notte della Regina Strega, Orchi, Goblin) e la [b]Resistenza[/b] (Impero d'Oriente, Oathborn, Fjordland). Ogni campagna dice regni, mappe, durata e condizioni di vittoria; in generale si conta il valore degli insediamenti controllati (1 villaggio, 2 fortificato, 3 città), più per gli Invasori i segnalini Raso al Suolo (con Orchi o Goblin) e le Congreghe.

""" + _h("Il turno") + """Le stagioni vanno da Primavera a Inverno; ogni stagione ogni regno gioca un turno nell'ordine della campagna.
[b]1. Entrate[/b]
• Azioni d'entrata: smontare la Macchina d'Assedio; [color=#ff7a68]Notte[/color] tenta una Congrega (1d6, 5+ con i modificatori); [color=#b4a8ff]Impero[/color] tira per le Rivolte; [color=#d89a5c]Goblin[/color]/[color=#a8b88a]Orchi[/color] possono [i]Devastare[/i] un insediamento controllato (lo radono e saccheggiano: 3 oro, 6 se città).
• Entrate: rendita del regno (base + insediamenti controllati; gli Shashka hanno solo la base). La Notte guadagna 1 oro per Congrega; l'Impero paga le Rivolte (ogni oro mancante è una Rivolta in più); Orchi e Goblin pagano 1 oro per segnalino di controllo, o il regno crolla.
[b]2. Attivazione[/b]: tutte le unità e i mostri comandati tornano pronti. In qualunque ordine: costruire, attivare pile (movimento + un'azione), azioni gratuite, carte.
[b]3. Studio arcano[/b] (regole avanzate): glifo = fino a 3 discipline, runa = 1.
[b]Inverno[/b]: niente turni; si rimescolano i mazzi e inizia un nuovo anno.

""" + _h("Costruire") + """Si paga il costo e si mette l'unità in un esagono d'ingresso amico o in un insediamento amico non assediato (o adiacente: l'unità entra esausta). Mai dove c'è già un'armata, né in un insediamento diventato amico in questo turno. Un eroe si pesca a caso (regole avanzate). La Notte costruisce unità ferali nelle terre selvagge vicino alle sue Congreghe.

""" + _h("Muovere") + """1 PM per esagono; terre selvagge (montagna, foresta, palude) +1; fiume +1, fiume maggiore +2 (senza ponte o strada). Si può sempre fare almeno un passo. Tutto il movimento su strada dà 1 PM in più. Non si attraversano armate nemiche, insediamenti ostili, tane e mare (salvo unità volanti). Massimo un'armata e un eroe per esagono.
[b]Movimento navale[/b] (una volta per turno, prima o dopo quello terrestre): 3 punti da costa o fiume maggiore, 6 da un porto amico o da un ingresso; si attraversano mare, costa e fiume maggiore e ci si ferma su costa o fiume. Fjordland: +2 e un movimento navale gratuito."""


func _col2() -> String:
	return _h("Combattimento") + """Si attacca un esagono adiacente (non tana, non attraverso il mare).
[b]Dadi[/b]: d6 leggeri e d8 pesanti. 5+ è un successo; 7+ sul d8 è un critico, che si conferma con 1d6 (5+) per un successo in più.
[b]Modificatori[/b]: difensore in terre selvagge +1d6; attacco da un lato di fiume +1d6 al difensore (fiume maggiore +2d6); guarnigione +1d6 (se non c'è un'armata), guarnigione di città +3d6; fortificazione −1 al tiro (−2 se magica), annullato da una Macchina d'Assedio adiacente (due per la fortificazione magica). Ranger in foresta +1d6.
[b]Risultato[/b]: chi fa più successi vince e il perdente subisce la differenza in colpi: un'armata piena si indebolisce, una debole (o una fragile) è eliminata, una guarnigione, un eroe o un mostro sono eliminati. Pareggio: non succede nulla (le unità a distanza vincono i pareggi con 1 colpo).
[b]Avanzata[/b]: se l'esagono resta libero l'attaccante può entrare; in un insediamento ostile deve entrare.
[b]Imboscata[/b]: chi ha un'unità furtiva (e l'altro no) può dichiararla; non contro insediamenti fortificati. Ognuno fa un [i]Assalto[/i]: tira solo chi colpisce, un successo = un colpo (più i critici confermati), senza terreno. Prima l'imboscata, poi il contrattacco se il bersaglio sopravvive.
[b]Battaglia magica[/b]: prima l'attaccante (ogni carta), poi i difensori e di nuovo gli attaccanti (solo trucchetti).

""" + _h("Insediamenti") + """[b]Accogliente[/b]: si entra e ci si ferma; se è neutrale vi si mette un segnalino di controllo. [b]Ostile[/b]: bisogna sconfiggerlo. Entrandovi un'armata [b]saccheggia[/b] (2 oro, 3 per Orchi e Goblin, il doppio nelle città), poi a fine attivazione mette un segnalino di controllo o lo [b]rade al suolo[/b]. Le unità ferali o enormi lo radono sempre.
Un insediamento raso non ha lealtà: un'armata in un insediamento accogliente può togliere le rovine per 2 oro.
[b]Assedio[/b]: un'armata ostile adiacente (due per un porto) assedia l'insediamento: dentro non si costruisce né si recupera.
[b]Recupero[/b]: pagando il costo un'armata debole torna piena in un ingresso amico o in o accanto a un insediamento accogliente non assediato.
[b]Miniere[/b]: i Minatori Oathborn in una miniera fanno 1 oro.
[b]Crollo[/b]: un regno crolla quando perde tutte le sue città in gioco (gli Oathborn e la Spira secondo la campagna; Orchi e Goblin senza segnalini; l'Impero con le Rivolte al massimo)."""


func _col3() -> String:
	return _h("Regole avanzate") + """[b]Eroi[/b]: viaggiano con un'armata del proprio regno (ne prendono le abilità). Un eroe solitario non attacca e non può essere attaccato: se un nemico entra nel suo esagono è eliminato. Ogni eroe ha una carta potere.
[b]Mostri[/b]: attaccando una tana se ne pesca il mostro, che comanda l'avversario (al massimo 3 per regno). Ogni turno un mostro comandato può fare un Assalto entro il suo raggio (4 marini, 3, 2, gli altri 1), passare o sgattaiolare via. Sconfitto in combattimento dà oro e un tesoro.
[b]Incantesimi, benedizioni e tesori[/b]: si giocano rispettando i requisiti (un'unità magica entro il raggio, un eroe…). I trucchetti anche nei turni avversari e nella battaglia magica; i tomi si giocano insieme a una seconda carta. I tesori si vendono per 2 oro.
[b]Studio arcano[/b]: pescare incantesimi fino a 3, cambiare benedizioni, riprendere un tesoro.

""" + _h("Regni") + """[color=#ff7a68][b]Armata della Notte[/b][/color]: Congreghe (rendita e PV), unità ferali, assoggettati, la Spira della Luna.
[color=#b4a8ff][b]Impero d'Oriente[/b][/color]: tracciato delle Rivolte, Soppressione (1 oro = −1).
[color=#7cc8f0][b]Fjordland[/b][/color]: navigatori, movimento navale gratuito e potenziato.
[color=#d89a5c][b]Goblin[/b][/color] e [color=#a8b88a][b]Orchi[/b][/color] (Shashka): rendita fissa, pagano i segnalini, devastano.
[color=#c2ccd6][b]Oathborn[/b][/color]: miniere e la Città Perduta di Khazud.

""" + _h("Comandi") + """[b]Mappa 3D[/b]: trascina con il tasto sinistro per spostarti, con il destro (o Maiusc + sinistro) per ruotare e inclinare; rotella per lo zoom; doppio clic per centrare un esagono. Tastiera: WASD/frecce, Q/E ruotano, R/F inclinano, C centra la mappa.
[b]Giocare[/b]: gli esagoni evidenziati sono le scelte possibili. Clic su una tua pila per attivarla, poi clic sulla destinazione; le altre scelte sono nei pulsanti del riquadro in basso. Tasto destro o Esc annullano la selezione.
[b]Carte[/b]: in basso a destra; passa sopra per ingrandirle, clicca per giocarle quando sono evidenziate.
[b]Plancia del regno[/b]: le schede in alto mostrano oro, rendita, rivolte e unità di ogni regno; clicca per vedere la riserva."""
