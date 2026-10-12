# Burning Banners – adattamento digitale (Godot 4)

Versione digitale per uso personale di **Burning Banners: Rage of the Witch Queen** di Christopher Moeller
(Compass Games). Mappe, carte e segnalini © dei rispettivi autori: le immagini vengono dal modulo Vassal 1.7
e dalle carte tradotte in italiano, e non vanno distribuite pubblicamente.

**Gioca nel browser:** https://tannoiser2.github.io/Burning-Banner/

![Menu](docs/menu.png)
![Mappa in 3D](docs/mappa.png)

## Avvio
1. Apri Godot 4 (testato su 4.7) → *Importa* → seleziona `project.godot`.
2. Premi **F5**. F11 alterna schermo intero e finestra.

Il progetto usa il renderer **Compatibility** (OpenGL 3 / WebGL 2), quindi gira anche nel browser e su
schede video modeste.

## Cosa c'è
- **Sette campagne** dal *Libro delle campagne (ricostruito)*: 0 L'invasione di Drefeld (introduttiva,
  ricostruita dal salvataggio del modulo Vassal), 1 Il risveglio della Spira, 2 Fuoco sulla Costa Spezzata,
  3 La guerra dei Jarl, 4 Le colonne di Placidia, 5 La notte cala sull'Est, 6 La guerra delle Bandiere in
  Fiamme (quattro mappe, sei regni, con la versione lunga di un anno in più). Per ognuna: mappe, regni e
  schieramenti, ordine di turno, durata, rendite e oro d'apertura, unità e Congreghe gratuite, segnalini
  iniziali, insediamenti in gioco, atteggiamento dei neutrali, esagoni d'ingresso temporanei (le flotte dei
  Jarl, i rinforzi imperiali da ovest), regole speciali e condizioni di vittoria (anche quelle immediate).
- **Da 1 a 6 giocatori**: ogni regno si affida a una persona o all'IA; più regni dello stesso schieramento
  possono andare alla stessa persona (il numero del giocatore nel menu). Schieramenti **Invasori**
  (Armata della Notte, Orchi, Goblin) e **Resistenza** (Impero d'Oriente, Oathborn, Fjordland). In più
  persone sullo stesso dispositivo una schermata «passa il dispositivo» nasconde le carte in mano.
- **Regole base complete**: stagioni e inverno, ordine dei turni, azioni d'entrata e rendita (calcolata
  dagli insediamenti controllati), costruzione negli ingressi e negli insediamenti amici (anche adiacenti,
  esaurita), attivazione di pile armata+eroe, movimento con terreni, fiumi, fiumi maggiori, ponti, strade
  (con il PM in più), esagoni proibiti e di solo passaggio, movimento navale (3/6 punti, Fjordland +2 e
  gratuito, attraversamento dei fiumi), combattimento con dadi leggeri (d6) e pesanti (d8), critici e
  conferme, modificatori di terreno, fiumi, guarnigioni e Città, fortificazioni normali e magiche,
  macchine d'assedio, unità a distanza (vincono i pareggi), imboscate con assalto e contrattacco,
  assegnazione dei colpi da parte di chi li subisce, avanzata dopo il combattimento, saccheggio (×2 nelle
  Città, 3 per gli Shashka), segnalini di controllo e radere al suolo, rovine da ricostruire (2 oro),
  assedi (due armate per i porti), recupero, miniere dei Minatori, unità fragili, ferali ed enormi, dono
  d'oro agli alleati (2:1), crollo dei regni.
- **Regole dei regni**: Oathborn (miniere, la Città Perduta di Khazud), Shashka (Orchi e Goblin: rendita
  fissa, 1 oro per segnalino, Devastare, crollo senza segnalini), Armata della Notte (Congreghe con tiro e
  modificatori, rendita delle Congreghe, unità ferali costruite e recuperate vicino alle Congreghe, eroi
  assoggettati, la Spira della Luna), Impero d'Oriente (tabella delle Rivolte, +2 solo nei Fields of Ash,
  pagamento e Soppressione), Fjordland (navigazione).
- **Regole avanzate** (scelta nel menu): eroi con le loro carte potere (pronte, bloccate, sempre attive),
  eroi solitari, mostri nelle tane con la riserva di terra e di mare, comando dei mostri (massimo 3 per
  regno), assalti dei mostri entro il loro raggio, sgattaiolare via, mostri erranti, ricompense in oro e
  tesori; i mazzi di **incantesimi** (52), **tesori** (36) e **benedizioni** dei sei regni (60), con
  trucchetti giocati nei turni avversari, battaglia magica nell'ordine attaccante → difensori →
  attaccanti, tomi, raggio, requisiti e la finestra di reazione di ogni carta; lo **studio arcano** con i
  segnalini glifo e runa.
- **Mappa vera in 3D**: le quattro mappe del modulo in un quadrato 2×2, con il rilievo ricavato dalle
  immagini (montagne e colline in rilievo), foreste di alberi in volume, acqua animata, insediamenti con
  case, torri e mura (le Città più grandi, i porti con pontile e barca, la Spira della Luna che brilla di
  viola), tane e miniere riconoscibili. Griglia esagonale presa dal `buildFile` del modulo e allineata
  alle immagini. Telecamera libera: trascina per spostarti, tasto destro per ruotare e inclinare, rotella
  per lo zoom, doppio clic per centrare un esagono; tastiera WASD/frecce, Q/E, R/F, C per ricentrare.
- **Blocchetti di legno**: ogni unità è un blocchetto del colore del regno con la figura del segnalino
  sulla faccia; un'armata indebolita è inclinata all'indietro e mostra il lato debole, le unità esauste
  sono più scure e ruotate. Gli eroi sono blocchetti più alti e stretti con la corona, i mostri pedine
  esagonali con l'anello del regno che li comanda. Le pile si leggono affiancate; in un assedio chi
  difende sta dietro. Segnalini di controllo, Congreghe e rovine fumanti sono pedine 3D; la bandierina
  di ogni insediamento prende il colore di chi lo controlla.
- **Interfaccia** sopra la mappa: fascia sempre visibile con stagione, anno, turni rimasti, regno di
  turno, oro, rendita, rivolte e Congreghe di ogni regno e punti di ciascuno schieramento (passa il mouse
  per il dettaglio); **plancia del regno** con riserva, unità in mappa, eroi in gioco e mostri comandati
  (clic sulle schede in alto per vedere un altro regno); **carte in mano** con ingrandimento e testo
  italiano; **registro** della partita; **regole in breve**; riquadro delle scelte; dadi del combattimento
  a schermo; informazioni sull'esagono sotto il mouse; schermata finale con i punti vittoria.
- **IA** su tre livelli (Facile, Normale, Difficile) per ogni regno: valuta valore degli insediamenti,
  rendita, bottino, difesa delle Città vitali, minacce, probabilità di vittoria di ogni attacco (Difficile:
  calcolo esatto della distribuzione dei dadi con critici), imboscate, carte e poteri degli eroi, studio
  arcano. Non guarda le carte degli altri.

## Comandi
- **Attivazione**: le pile pronte sono evidenziate in giallo, i mostri comandati in viola. Clic su una pila
  per attivarla (se c'è anche un eroe si sceglie chi si muove), poi clic su un esagono azzurro per
  muovere; gli esagoni rossi sono i bersagli d'attacco. Gli altri comandi (movimento navale, recupero,
  miniera, nessuna azione) sono nel riquadro in basso.
- **Costruire**: pulsante dell'unità (con il costo) e poi clic su un esagono verde. Tasto destro o Esc
  annullano.
- **Carte**: in basso a destra. Passa il mouse per ingrandirle; quelle giocabili hanno il bordo dorato:
  un clic per giocarle (se ci sono più modi si sceglie dall'elenco). Nelle finestre di reazione le carte
  giocabili sono anche fra i pulsanti, con PASSA.
- **FINE TURNO** chiude l'attivazione del regno (con conferma se restano pile pronte).

## Gioco online
Dal menu, **GIOCA ONLINE** (anche dalla versione web). Usa lo stesso progetto Firebase degli altri giochi
(`flammerouge-f8669`, Realtime Database, piano gratuito), con le stanze sotto `burningbanners/rooms`.

- **Chi crea la stanza** sceglie prima nel menu campagna, regole e livello dell'IA, e affida a PERSONE i
  regni degli amici con numeri di giocatore diversi (il giocatore 1 è lui). Scrive il nome, preme
  *Crea una stanza* e comunica il codice di 4 lettere. Quando ci sono tutti preme *Inizia online*: i posti
  liberi li gioca l'IA.
- **Gli amici** scrivono il nome e il codice e premono *Entra*.
- Ognuno vede soltanto le proprie carte.
- Ogni decisione è una mossa numerata nel database (`acts/0`, `acts/1`, …): tutti i dispositivi fanno
  girare lo stesso motore con lo stesso seme e applicano le stesse mosse, quindi la partita è identica
  ovunque. I regni dell'IA li gioca il dispositivo di chi ha creato la stanza.
- **Se cade la linea** si rientra con lo stesso codice e *Entra* (anche a partita iniziata). Se un
  giocatore tace per un minuto, al suo posto gioca l'IA finché non rientra.
- Nota: come negli altri giochi online fra amici senza server, le carte degli altri sono nascoste
  dall'interfaccia, non dalla rete.

**Configurazione Firebase.** Le regole sono in `firebase/database.rules.json` e comprendono anche quelle
degli altri giochi (Ultimo chilometro, Snow Tails, STATUS, World Order, Kingsburg, Churchill) più la nuova
sezione `burningbanners`: vanno pubblicate nella console di Firebase (Realtime Database → Regole) al posto
delle precedenti. Senza questo passaggio la creazione della stanza risponde "Permission denied".

**Prove senza Firebase.** `tests/firebase_mock.py` è un finto Firebase locale che applica le stesse regole.
Con `BB_DB_URL`, `BB_AUTH_URL` e `BB_REFRESH_URL` che puntano lì, `tests/online_play.gd` fa giocare una
partita intera a due istanze (`BB_ROLE=host` con il primo regno della Resistenza, `guest` con il primo
degli Invasori, gli altri all'IA; con `BB_PHASE=drop` e poi `back` l'ospite esce a metà e rientra). Alla
fine ognuna stampa l'impronta della partita, che deve coincidere, e controlla che si vedano solo le
proprie carte. Nella versione web il finto Firebase si sceglie con `?bbdb=<indirizzo>`.

## Struttura
```
data/world.json              esagoni (terreno, mappa, coste, fiumi maggiori, tane, miniere, ingressi), insediamenti, lati (fiumi, strade, mare)
data/cards.json              le 186 carte (incantesimi, tesori, benedizioni, eroi) con testo italiano e dati di gioco
data/counters.json           indice dell'atlante dei segnalini
data/height_*.bin, trees.bin rilievo delle quattro mappe e posizioni degli alberi (ricavati dalle immagini)
scripts/data/bb_data.gd      regni, armate, eroi, mostri, tabella delle rivolte, campagne, caricamento dei dati
scripts/core/engine.gd       motore delle regole (nessuna dipendenza dalla grafica)
scripts/core/magic.gd        carte, poteri degli eroi e finestre di reazione
scripts/core/ai.gd           IA (tre livelli)
scripts/net/                 Firebase (REST) e partita online in lockstep
scripts/ui/board3d.gd        mappa 3D: terreno, acqua, alberi, insediamenti, blocchetti, telecamera
scripts/ui/                  menu, vista di gioco, regole in breve
assets/shaders/              terreno (griglia ed evidenziazioni calcolate sul rilievo) e acqua
tests/sim.gd                 godot --headless -s res://tests/sim.gd -- 20 1 2 1 1   (partite IA: partite, campagna, livello Invasori, livello Resistenza, avanzate)
tests/shot.gd                xvfb-run godot -s res://tests/shot.gd -- game 1 1      (screenshot di una partita intera giocata dall'interfaccia)
tests/online_play.gd         prova online con tests/firebase_mock.py
tests/web_test.py            prova della versione web nel browser (Playwright): nessun errore in console
tests/chk.gd                 controllo di compilazione di tutti gli script
```

Le texture delle mappe e dell'atlante dei segnalini sono importate in **Basis Universal** (si
trasformano al caricamento nel formato compresso supportato dalla scheda video, anche su telefono), le
carte in WebP con perdita.

## Equilibrio e IA
Risultati di partite IA contro IA con le regole avanzate (`tests/sim.gd`, 12 partite per riga, stessi semi
nelle due direzioni). *Difficile contro Normale*: quante partite vince il livello Difficile sommando le
due direzioni (Difficile con gli Invasori e Difficile con la Resistenza).

| Campagna | Invasori Difficile · Resistenza Normale | Invasori Normale · Resistenza Difficile | Vittorie Difficile | Vittorie Normale |
|---|---|---|---|---|
| 0 Drefeld | Invasori 4 – Resistenza 8 | Invasori 2 – Resistenza 10 | **14** | 10 |
| 1 La Spira | 11 – 1 | 6 – 6 | **17** | 7 |
| 2 Costa Spezzata | 6 – 6 | 6 – 6 | 12 | 12 |
| 3 Guerra dei Jarl | 7 – 5 | 4 – 8 | **15** | 9 |
| 4 Placidia | 7 – 5 | 7 – 5 | 12 | 12 |
| 5 La notte sull'Est | 12 – 0 | 11 – 1 | **13** | 11 |
| 6 Bandiere in Fiamme (4+4 partite) | 4 – 0 | 2 – 2 | **6** | 2 |
| **Totale** | | | **89** | **63** |

Il livello Difficile vince più partite del Normale in cinque campagne su sette e pareggia nelle altre
due. Il livello Facile (scelte in parte casuali, niente difesa delle Città vitali) perde nettamente
contro il Normale. Le partite mostrano anche **squilibri delle campagne**: nella 1 (la Spira) e nella 5
(la notte sull'Est) gli Invasori vincono quasi sempre, nella 0 (Drefeld) è favorita la Resistenza;
sono i primi numeri da ritoccare nel libro delle campagne.

## Scelte da verificare
- **Nome del repository**: il repository richiesto, `Tannoiser2/BurningBanners`, non esisteva e da qui non
  si poteva creare; il gioco è pubblicato in `Tannoiser2/Burning-Banner` (già esistente e vuoto). Per
  spostarlo basta rinominare il repository su GitHub e aggiornare il link della ludoteca.
- **Libro delle campagne**: i numeri (rendite, oro, unità gratuite, soglie) sono quelli del libro
  ricostruito, senza ritocchi, anche dove le partite fra IA mostrano uno squilibrio (vedi la tabella).
- **Segnalini di controllo**: 16 per regno (le Congreghe della Notte sono il retro degli stessi segnalini e
  contano nel limite).
- **Valore degli insediamenti** (regola comune 1 del libro): 1 PV, 2 se fortificato, 3 una Città. Lo
  stesso valore guida l'IA.
- **Shashka**: la rendita resta quella di base della campagna (gli insediamenti controllati non la
  aumentano) e si paga 1 oro per segnalino; senza segnalini, dopo averne avuto almeno uno, il regno crolla.
- **Crollo**: contano solo le Città sulle mappe in uso e in gioco (regola comune 4). Nel Risveglio della
  Spira gli Oathborn crollano se perdono Dwelfholm, l'Armata della Notte se perde la Spira. Se tutti i
  regni di uno schieramento crollano l'altro vince subito.
- **Trucchetti nei turni altrui**: si possono giocare nelle finestre di reazione previste (battaglia
  magica, colpo subito, dopo il tiro, carta giocata, eliminazione, movimento, Congrega, miniera, vittoria
  in combattimento), non in un momento qualsiasi.
- **Durata degli effetti**: «finché l'unità o la pila attiva non diventa esausta» vale fino alla fine
  dell'attivazione in corso; gli effetti «fino alla fine del turno» scadono a fine turno del regno.
- **Comando dei mostri**: lo prende l'avversario di chi esplora la tana; con più avversari, il regno che
  comanda meno mostri (poi il primo nell'ordine di turno).
- **Guarnigione e imboscata**: la guarnigione di un insediamento non partecipa agli assalti di
  un'imboscata (si difende solo nel combattimento normale).
- **Unità enormi** non si costruiscono negli insediamenti.
- **Raccogliere e lasciare unità durante il movimento** e lo **scambio di posizione** non sono gestiti:
  una pila si attiva tutta insieme o un'unità alla volta (si sceglie all'attivazione).
- **Diamante Nero e Ferite Infette** si giocano prima del tiro e modificano le conferme dei critici.
- **Enciclopedia** semplificata: permette di pescare un incantesimo in più e scartarne uno.
- **Haga-Tor** contrattacca subito, prima che il combattimento si chiuda; **Siskar** ripete un dado una
  volta per combattimento; la costruzione di **Maestro Fabbro Horne** in un insediamento assediato non è
  gestita.
- **Digitalizzazione delle mappe**: terreni, coste, fiumi, fiumi maggiori, ponti e strade sono stati letti
  dalle immagini delle mappe (una persona dovrebbe controllare soprattutto i fiumi e le strade). Placidia,
  tagliata fra Imperial Heartland e Fields of Ash, è nell'esagono dei Fields of Ash.
- **Insediamenti selvaggi**: per Blackstone Fortress, Urbicus, Khalesh e Darhad l'icona sulla mappa indica
  la foresta, mentre il libro li dà come montagna: vale l'icona della mappa.
- **IA online**: i regni dell'IA li gioca il dispositivo di chi ha creato la stanza; un posto per persone
  rimasto vuoto all'avvio passa all'IA. In locale i regni affidati all'IA dello stesso schieramento
  formano un unico giocatore IA (mano di carte comune), come un giocatore che guida più regni.
- **Hotseat**: la schermata «passa il dispositivo» compare per le decisioni che mostrano le carte
  (attivazione, carte, studio arcano); le scelte rapide durante un combattimento (colpi, imboscate,
  avanzata) si fanno senza coprire lo schermo.
- **Rilievo**: l'altezza del terreno è ricavata dai colori e dalle ombre delle illustrazioni (montagne e
  colline in rilievo, mare più basso), non da dati del gioco; serve solo all'aspetto.

## Da verificare (dal Libro delle campagne)
- **Disposizione delle mappe**: il quadrato due per due è dedotto dai bordi (ingressi Goblin a nord, Orchi
  a est, Placidia tagliata fra Heartland e Fields of Ash).
- **Simboli degli insediamenti**: Città, fortificato, porto e selvaggio sono letti dalle icone sotto i
  nomi, alla risoluzione del modulo. In particolare va controllato se la Spire of the Moon è fortificata
  con la magia (lo dice la regola 12.3.6): qui lo è.
- **Crollo con Città fuori mappa**: segue la scheda di riferimento italiana («crollano solo se tutte le
  loro Città sono in gioco»); il regolamento inglese non lo dice in modo esplicito.
- **Drefeld**: durata, rendita, oro e vittoria sono proposte del libro. Il modulo mette il segnalino Fine
  campagna nell'Inverno dell'anno 3 e le posizioni dei segnalini rendita non sono leggibili con certezza.
- **Rendite di base** di Orchi, Goblin e Armata della Notte: senza insediamenti iniziali, questi regni
  vivrebbero solo di saccheggi. Il valore di base è una scelta del libro.
- **Soglie di vittoria**: 8 PV per i Goblin, 6 per Fjordland nella guerra dei Jarl, 10 per gli Orchi, metà
  dei PV della Resistenza nella grande campagna.
- Le soglie di vittoria, le rendite di base e l'oro d'apertura non sono mai stati provati al tavolo: i
  risultati delle partite fra IA qui sopra sono un primo indizio di dove ritoccarli.
