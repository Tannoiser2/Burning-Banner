class_name BBData
extends RefCounted
## Dati statici di Burning Banners: regni, armate, eroi, mostri, campagne, mappa e carte.
## Le pedine e le carte vengono dal modulo Vassal 1.7 e dalle carte tradotte; la mappa è stata
## digitalizzata dalle quattro immagini del modulo (data/world.json).

# ---------------------------------------------------------------- regni

const NIGHT := 0
const EMPIRE := 1
const FJORD := 2
const GOBLIN := 3
const OATH := 4
const ORC := 5
const GUILD := 6
const MARA := 7

const INVADER := 0
const RESIST := 1

const KINGDOMS := [
	{"key": "night", "n": "Armata della Notte", "short": "Notte", "col": Color("#b8322a"), "light": Color("#ff7a68"), "hero_cost": 3, "shashka": false, "hero_back": "n_hero"},
	{"key": "empire", "n": "Impero d'Oriente", "short": "Impero", "col": Color("#6a5fb0"), "light": Color("#b4a8ff"), "hero_cost": 3, "shashka": false, "hero_back": "e_hero"},
	{"key": "fjord", "n": "Fjordland", "short": "Fjordland", "col": Color("#2f86b8"), "light": Color("#7cc8f0"), "hero_cost": 2, "shashka": false, "hero_back": "f_hero"},
	{"key": "goblin", "n": "Goblin", "short": "Goblin", "col": Color("#7a4a22"), "light": Color("#d89a5c"), "hero_cost": 2, "shashka": true, "hero_back": "g_hero"},
	{"key": "oath", "n": "Oathborn", "short": "Oathborn", "col": Color("#6d7884"), "light": Color("#c2ccd6"), "hero_cost": 3, "shashka": false, "hero_back": "o_hero"},
	{"key": "orc", "n": "Orchi", "short": "Orchi", "col": Color("#2a2a2a"), "light": Color("#a8b88a"), "hero_cost": 3, "shashka": true, "hero_back": "r_hero"},
]
const LOYAL_NAMES := {6: "Gilda degli Assassini", 7: "Mara Mitai"}
const SIDE_NAMES := ["Invasori", "Resistenza"]
const SEASONS := ["Primavera", "Estate", "Autunno", "Inverno"]
## Segnalini di controllo per regno (le Congreghe dell'Armata della Notte sono il retro degli stessi).
const CONTROL_MARKERS := 16
const MONSTER_CMD := 3

# ---------------------------------------------------------------- armate
# l/h: dadi leggeri (d6) e pesanti (d8); mv: movimento; ab: abilità; ch: caratteristiche;
# cost: costruzione; rec: recupero (−1 per le fragili, che non recuperano); n: quante pedine.

const UNITS := {
	# Armata della Notte
	"n_rats": {"k": 0, "n": "Sciame di Ratti", "cost": 1, "rec": -1, "l": 0, "h": 1, "mv": 2, "ab": ["stealth"], "ch": ["fragile", "feral"], "num": 5, "img": ["n_rats"]},
	"n_wolf": {"k": 0, "n": "Branco di Lupi", "cost": 2, "rec": 1, "l": 2, "h": 0, "mv": 4, "ab": [], "ch": ["feral"], "num": 3, "img": ["n_wolf"]},
	"n_bats": {"k": 0, "n": "Pipistrelli Giganti", "cost": 5, "rec": 3, "l": 3, "h": 0, "mv": 5, "ab": ["flying"], "ch": ["feral"], "num": 3, "img": ["n_bats"]},
	"n_ghost": {"k": 0, "n": "Spettro Vendicativo", "cost": 4, "rec": -1, "l": 3, "h": 0, "mv": 3, "ab": ["flying"], "ch": ["fragile"], "num": 2, "img": ["n_ghost"]},
	"n_ghoul": {"k": 0, "n": "Ghoul", "cost": 2, "rec": 1, "l": 1, "h": 1, "mv": 1, "ab": ["regen"], "ch": [], "num": 4, "img": ["n_ghoul"]},
	"n_emis": {"k": 0, "n": "Emissarie", "cost": 3, "rec": 2, "l": 2, "h": 0, "mv": 3, "ab": ["stealth"], "ch": [], "num": 3, "img": ["n_emis"]},
	"n_vamp": {"k": 0, "n": "Cavalieri Vampiri", "cost": 9, "rec": 5, "l": 3, "h": 1, "mv": 5, "ab": ["flying"], "ch": [], "num": 2, "img": ["n_vamp"]},
	"n_siege": {"k": 0, "n": "Macchina d'Assedio", "cost": 3, "rec": -1, "l": 0, "h": 1, "mv": 2, "ab": ["flying"], "ch": ["fragile"], "num": 1, "siege": true, "img": ["n_siege"]},
	# Impero d'Oriente
	"e_akri": {"k": 1, "n": "Akritoi", "cost": 1, "rec": -1, "l": 2, "h": 0, "mv": 3, "ab": [], "ch": ["fragile"], "num": 7, "img": ["e_akri", "e_akri2"]},
	"e_psil": {"k": 1, "n": "Psiloi", "cost": 2, "rec": -1, "l": 2, "h": 0, "mv": 3, "ab": ["ranged"], "ch": ["fragile"], "num": 4, "img": ["e_psil"]},
	"e_kont": {"k": 1, "n": "Kontari", "cost": 3, "rec": 2, "l": 3, "h": 0, "mv": 3, "ab": [], "ch": [], "num": 5, "img": ["e_kont"]},
	"e_kors": {"k": 1, "n": "Korsari", "cost": 5, "rec": 3, "l": 3, "h": 0, "mv": 5, "ab": ["ranged"], "ch": [], "num": 4, "img": ["e_kors"]},
	"e_vary": {"k": 1, "n": "Varyag", "cost": 6, "rec": 3, "l": 2, "h": 2, "mv": 3, "ab": [], "ch": [], "num": 1, "img": ["e_vary"]},
	"e_cata": {"k": 1, "n": "Catafratti", "cost": 7, "rec": 4, "l": 2, "h": 2, "mv": 4, "ab": ["ranged"], "ch": [], "num": 2, "img": ["e_cata"]},
	"e_siege": {"k": 1, "n": "Macchina d'Assedio", "cost": 3, "rec": -1, "l": 0, "h": 1, "mv": 2, "ab": [], "ch": ["fragile"], "num": 1, "siege": true, "img": ["e_siege"]},
	# Fjordland
	"f_free": {"k": 2, "n": "Liberi Proprietari", "cost": 2, "rec": 1, "l": 2, "h": 0, "mv": 3, "ab": [], "ch": [], "num": 7, "img": ["f_free", "f_free2"]},
	"f_reav": {"k": 2, "n": "Predoni del Mare", "cost": 3, "rec": 2, "l": 2, "h": 1, "mv": 2, "ab": [], "ch": [], "num": 4, "img": ["f_reav"]},
	"f_rang": {"k": 2, "n": "Ranger", "cost": 4, "rec": 2, "l": 2, "h": 0, "mv": 4, "ab": ["ranged"], "ch": [], "num": 3, "ranger": true, "img": ["f_rang"]},
	"f_valk": {"k": 2, "n": "Valchirie", "cost": 5, "rec": 3, "l": 2, "h": 1, "mv": 3, "ab": ["flying"], "ch": [], "num": 2, "img": ["f_valk"]},
	"f_bers": {"k": 2, "n": "Berserkir", "cost": 6, "rec": 3, "l": 2, "h": 2, "mv": 3, "ab": [], "ch": [], "num": 2, "img": ["f_bers"]},
	"f_drak": {"k": 2, "n": "Drakken", "cost": 7, "rec": 4, "l": 1, "h": 2, "mv": 3, "ab": ["stealth", "ranged", "flying"], "ch": ["feral", "huge"], "num": 1, "img": ["f_drak"]},
	"f_siege": {"k": 2, "n": "Macchina d'Assedio", "cost": 3, "rec": -1, "l": 0, "h": 1, "mv": 2, "ab": [], "ch": ["fragile"], "num": 1, "siege": true, "img": ["f_siege"]},
	# Goblin
	"g_warr": {"k": 3, "n": "Guerrieri Goblin", "cost": 1, "rec": -1, "l": 2, "h": 0, "mv": 4, "ab": [], "ch": ["fragile"], "num": 8, "img": ["g_warr"]},
	"g_snea": {"k": 3, "n": "Goblin Furtivi", "cost": 1, "rec": -1, "l": 1, "h": 0, "mv": 4, "ab": ["stealth"], "ch": ["fragile"], "num": 4, "img": ["g_snea"]},
	"g_elit": {"k": 3, "n": "Goblin d'Élite", "cost": 2, "rec": 1, "l": 2, "h": 0, "mv": 3, "ab": ["ranged"], "ch": [], "num": 5, "img": ["g_elit"]},
	"g_hobg": {"k": 3, "n": "Hobgoblin", "cost": 3, "rec": 2, "l": 2, "h": 1, "mv": 3, "ab": [], "ch": [], "num": 3, "img": ["g_hobg"]},
	"g_flie": {"k": 3, "n": "Mosche della Peste", "cost": 2, "rec": 1, "l": 2, "h": 0, "mv": 3, "ab": ["flying"], "ch": ["feral"], "num": 3, "img": ["g_flie"]},
	"g_htro": {"k": 3, "n": "Troll delle Colline", "cost": 5, "rec": 2, "l": 1, "h": 2, "mv": 3, "ab": ["regen"], "ch": [], "num": 2, "troll": true, "img": ["g_htro"]},
	"g_mtro": {"k": 3, "n": "Troll di Montagna", "cost": 6, "rec": 3, "l": 0, "h": 3, "mv": 3, "ab": ["regen"], "ch": ["huge"], "num": 1, "troll": true, "img": ["g_mtro"]},
	"g_siege": {"k": 3, "n": "Macchina d'Assedio", "cost": 3, "rec": -1, "l": 0, "h": 1, "mv": 2, "ab": [], "ch": ["fragile"], "num": 1, "siege": true, "img": ["g_siege"]},
	# Oathborn
	"o_mine": {"k": 4, "n": "Minatori", "cost": 1, "rec": 0, "l": 1, "h": 0, "mv": 2, "ab": [], "ch": [], "num": 9, "miner": true, "img": ["o_mine", "o_mine2"]},
	"o_xbow": {"k": 4, "n": "Balestrieri del Re", "cost": 3, "rec": 2, "l": 1, "h": 1, "mv": 2, "ab": ["ranged"], "ch": [], "num": 5, "img": ["o_xbow"]},
	"o_iron": {"k": 4, "n": "Legione di Ferro", "cost": 4, "rec": 2, "l": 1, "h": 2, "mv": 2, "ab": [], "ch": [], "num": 6, "img": ["o_iron"]},
	"o_drag": {"k": 4, "n": "Ammazzadraghi", "cost": 5, "rec": 3, "l": 0, "h": 2, "mv": 3, "ab": ["stealth"], "ch": [], "num": 2, "img": ["o_drag"]},
	"o_oath": {"k": 4, "n": "Portatori del Giuramento", "cost": 5, "rec": 3, "l": 2, "h": 2, "mv": 2, "ab": [], "ch": [], "num": 2, "img": ["o_oath"]},
	"o_gian": {"k": 4, "n": "Gigante delle Tempeste", "cost": 7, "rec": 4, "l": 3, "h": 3, "mv": 2, "ab": [], "ch": ["huge"], "num": 1, "img": ["o_gian"]},
	"o_siege": {"k": 4, "n": "Macchina d'Assedio", "cost": 3, "rec": 2, "l": 0, "h": 1, "mv": 2, "ab": [], "ch": [], "num": 1, "siege": true, "img": ["o_siege"]},
	# Orchi
	"r_reav": {"k": 5, "n": "Predoni Orchi", "cost": 2, "rec": 1, "l": 1, "h": 1, "mv": 3, "ab": [], "ch": [], "num": 10, "reaver": true, "img": ["r_reav"]},
	"r_scou": {"k": 5, "n": "Esploratori Orchi", "cost": 1, "rec": -1, "l": 2, "h": 0, "mv": 3, "ab": ["ranged"], "ch": ["fragile"], "num": 5, "img": ["r_scou"]},
	"r_wolf": {"k": 5, "n": "Cavalcalupi", "cost": 4, "rec": 2, "l": 2, "h": 1, "mv": 4, "ab": [], "ch": [], "num": 3, "img": ["r_wolf"]},
	"r_axes": {"k": 5, "n": "Asce Nere", "cost": 4, "rec": 2, "l": 3, "h": 1, "mv": 3, "ab": [], "ch": [], "num": 3, "img": ["r_axes"]},
	"r_ogre": {"k": 5, "n": "Ogre", "cost": 4, "rec": 2, "l": 2, "h": 2, "mv": 2, "ab": [], "ch": [], "num": 2, "img": ["r_ogre"]},
	"r_rave": {"k": 5, "n": "Corvo Funesto", "cost": 5, "rec": 3, "l": 1, "h": 2, "mv": 4, "ab": ["flying"], "ch": ["feral", "huge"], "num": 2, "img": ["r_rave"]},
	"r_siege": {"k": 5, "n": "Macchina d'Assedio", "cost": 3, "rec": -1, "l": 0, "h": 1, "mv": 2, "ab": [], "ch": ["fragile"], "num": 1, "siege": true, "img": ["r_siege"]},
}

## Ordine di presentazione delle armate di ogni regno.
const UNIT_ORDER := [
	["n_rats", "n_wolf", "n_ghoul", "n_emis", "n_ghost", "n_bats", "n_vamp", "n_siege"],
	["e_akri", "e_psil", "e_kont", "e_kors", "e_vary", "e_cata", "e_siege"],
	["f_free", "f_reav", "f_rang", "f_valk", "f_bers", "f_drak", "f_siege"],
	["g_warr", "g_snea", "g_elit", "g_flie", "g_hobg", "g_htro", "g_mtro", "g_siege"],
	["o_mine", "o_xbow", "o_iron", "o_drag", "o_oath", "o_gian", "o_siege"],
	["r_scou", "r_reav", "r_wolf", "r_axes", "r_ogre", "r_rave", "r_siege"],
]

# ---------------------------------------------------------------- eroi (id = carta eroe)

const HEROES := {
	"H011": {"k": 0, "mv": 6, "ab": ["mage", "flying"], "l": 0, "h": 0, "enslave": 2},
	"H012": {"k": 0, "mv": 6, "ab": ["mage", "flying"], "l": 0, "h": 0},
	"H013": {"k": 0, "mv": 6, "ab": ["mage", "flying"], "l": 0, "h": 0, "enslave": 1},
	"H014": {"k": 0, "mv": 6, "ab": ["mage", "flying"], "l": 0, "h": 0},
	"H015": {"k": 0, "mv": 6, "ab": ["mage", "flying"], "l": 0, "h": 0},
	"H016": {"k": 0, "mv": 4, "ab": ["mage", "flying"], "l": 0, "h": 0},
	"H111": {"k": 1, "mv": 6, "ab": ["mage", "ranged"], "l": 0, "h": 0},
	"H112": {"k": 1, "mv": 6, "ab": ["mage"], "l": 0, "h": 0},
	"H113": {"k": 1, "mv": 6, "ab": ["mage"], "l": 0, "h": 0},
	"H114": {"k": 1, "mv": 6, "ab": ["mage"], "l": 0, "h": 0},
	"H115": {"k": 1, "mv": 4, "ab": ["mage"], "l": 0, "h": 0},
	"H116": {"k": 1, "mv": 4, "ab": ["mage"], "l": 0, "h": 0},
	"H211": {"k": 2, "mv": 6, "ab": ["mage", "ranged"], "l": 0, "h": 0},
	"H212": {"k": 2, "mv": 6, "ab": ["mage"], "l": 0, "h": 0},
	"H213": {"k": 2, "mv": 8, "ab": ["mage", "flying"], "l": 0, "h": 0},
	"H214": {"k": 2, "mv": 6, "ab": ["mage"], "l": 0, "h": 0},
	"H215": {"k": 2, "mv": 6, "ab": ["mage"], "l": 0, "h": 0},
	"H216": {"k": 2, "mv": 4, "ab": ["mage"], "l": 0, "h": 0},
	"H217": {"k": 2, "mv": 4, "ab": ["mage"], "l": 0, "h": 0},
	"H311": {"k": 3, "mv": 6, "ab": ["mage"], "l": 0, "h": 0},
	"H312": {"k": 3, "mv": 6, "ab": ["mage"], "l": 0, "h": 0},
	"H313": {"k": 3, "mv": 3, "ab": ["mage"], "l": 0, "h": 0},
	"H314": {"k": 3, "mv": 6, "ab": ["mage"], "l": 0, "h": 0},
	"H315": {"k": 3, "mv": 6, "ab": ["mage"], "l": 0, "h": 0},
	"H316": {"k": 3, "mv": 4, "ab": ["mage"], "l": 0, "h": 0},
	"H317": {"k": 3, "mv": 4, "ab": ["mage"], "l": 0, "h": 0},
	"H411": {"k": 4, "mv": 6, "ab": ["mage"], "l": 0, "h": 0},
	"H412": {"k": 4, "mv": 6, "ab": ["mage"], "l": 0, "h": 0},
	"H413": {"k": 4, "mv": 6, "ab": ["mage"], "l": 0, "h": 0},
	"H414": {"k": 4, "mv": 6, "ab": ["mage"], "l": 0, "h": 0},
	"H415": {"k": 4, "mv": 4, "ab": ["mage"], "l": 0, "h": 0},
	"H416": {"k": 4, "mv": 4, "ab": ["mage"], "l": 0, "h": 0},
	"H511": {"k": 5, "mv": 6, "ab": ["mage"], "l": 0, "h": 0},
	"H512": {"k": 5, "mv": 6, "ab": ["mage"], "l": 0, "h": 0},
	"H513": {"k": 5, "mv": 6, "ab": ["mage"], "l": 0, "h": 1},
	"H514": {"k": 5, "mv": 6, "ab": ["mage"], "l": 0, "h": 0},
	"H515": {"k": 5, "mv": 4, "ab": ["mage"], "l": 0, "h": 0},
	"H516": {"k": 5, "mv": 4, "ab": ["mage"], "l": 0, "h": 0},
}
## Eroe Assoggettato (Armata della Notte): prende movimento e abilità dell'armata che controlla.
const ENSLAVED_NUM := 3

# ---------------------------------------------------------------- mostri

const MONSTERS := [
	{"id": "m_baba_ti", "n": "Baba Ti", "l": 2, "h": 1, "ab": ["mage", "stealth"], "gold": 5},
	{"id": "m_banshee", "n": "Banshee", "l": 0, "h": 1, "ab": ["flying", "mage"], "gold": 3},
	{"id": "m_basilisk", "n": "Basilisco", "l": 1, "h": 1, "ab": [], "gold": 2},
	{"id": "m_black_tide_assassins", "n": "Assassini della Marea Nera", "l": 2, "h": 0, "ab": ["mage", "stealth"], "gold": 2},
	{"id": "m_colossal_worm", "n": "Verme Colossale", "l": 0, "h": 3, "ab": ["stealth"], "gold": 6},
	{"id": "m_corpse_golem", "n": "Golem di Cadaveri", "l": 1, "h": 0, "ab": [], "gold": 1},
	{"id": "m_dire_wolf", "n": "Lupo Feroce", "l": 3, "h": 0, "ab": [], "gold": 3},
	{"id": "m_djinn", "n": "Djinn", "l": 2, "h": 0, "ab": ["stealth"], "gold": 2},
	{"id": "m_droghir", "n": "Droghir", "l": 3, "h": 1, "ab": ["mage", "ranged", "flying", "stealth"], "gold": 7},
	{"id": "m_feral_orcs", "n": "Orchi Selvaggi", "l": 2, "h": 0, "ab": [], "gold": 1},
	{"id": "m_fey_hunters", "n": "Cacciatori Fatati", "l": 2, "h": 0, "ab": ["flying", "stealth"], "gold": 3},
	{"id": "m_fire_scarabs", "n": "Scarabei di Fuoco", "l": 1, "h": 0, "ab": ["ranged"], "gold": 1},
	{"id": "m_floating_eye", "n": "Occhio Fluttuante", "l": 3, "h": 0, "ab": ["mage", "ranged"], "gold": 4},
	{"id": "m_ghost_bear", "n": "Orso Fantasma", "l": 3, "h": 0, "ab": [], "gold": 3},
	{"id": "m_giant_spiders", "n": "Ragni Giganti", "l": 1, "h": 0, "ab": ["stealth"], "gold": 1},
	{"id": "m_granny_wink_and_soot", "n": "Nonna Wink e Fuliggine", "l": 2, "h": 0, "ab": ["mage"], "gold": 0},
	{"id": "m_gray_slime", "n": "Melma Grigia", "l": 1, "h": 0, "ab": ["stealth"], "gold": 1},
	{"id": "m_great_white_ape", "n": "Grande Scimmia Bianca", "l": 1, "h": 0, "ab": [], "gold": 1},
	{"id": "m_harpy", "n": "Arpia", "l": 1, "h": 0, "ab": ["flying"], "gold": 1},
	{"id": "m_hill_giant", "n": "Gigante delle Colline", "l": 2, "h": 2, "ab": [], "gold": 5},
	{"id": "m_karfang", "n": "Karfang", "l": 1, "h": 2, "ab": ["mage", "stealth", "ranged", "flying"], "gold": 7},
	{"id": "m_kobolds", "n": "Coboldi", "l": 1, "h": 0, "ab": ["stealth"], "gold": 1},
	{"id": "m_marsh_troll", "n": "Troll di Palude", "l": 3, "h": 0, "ab": [], "gold": 4},
	{"id": "m_osterlich", "n": "Osterlich", "l": 1, "h": 2, "ab": ["mage"], "gold": 6},
	{"id": "m_plague_rats", "n": "Ratti della Peste", "l": 0, "h": 1, "ab": ["stealth"], "gold": 1},
	{"id": "m_red_mask_assassins", "n": "Assassini della Maschera Rossa", "l": 2, "h": 0, "ab": ["ranged"], "gold": 2},
	{"id": "m_the_blue_wizard", "n": "Il Mago Blu", "l": 1, "h": 0, "ab": ["mage"], "gold": 1},
	{"id": "m_wight", "n": "Spettro dei Tumuli", "l": 2, "h": 0, "ab": ["mage"], "gold": 3},
	{"id": "m_xaraxxes", "n": "Xaraxxes", "l": 1, "h": 2, "ab": ["flying", "mage"], "gold": 6},
	{"id": "m_ao_bishi", "n": "Ao-Bishi", "l": 2, "h": 2, "ab": ["mage", "stealth"], "gold": 7, "sea": true},
	{"id": "m_bearshark", "n": "Orsosqualo", "l": 1, "h": 1, "ab": [], "gold": 3, "sea": true},
	{"id": "m_hammerhead_walrus", "n": "Tricheco Martello", "l": 3, "h": 0, "ab": [], "gold": 3, "sea": true},
	{"id": "m_kraken", "n": "Kraken", "l": 2, "h": 1, "ab": [], "gold": 4, "sea": true},
	{"id": "m_kupa_raiders", "n": "Predoni Kupa", "l": 2, "h": 0, "ab": ["ranged"], "gold": 3, "sea": true},
	{"id": "m_leviathan", "n": "Leviatano", "l": 1, "h": 2, "ab": ["stealth"], "gold": 5, "sea": true},
	{"id": "m_siren", "n": "Sirena", "l": 2, "h": 0, "ab": ["mage"], "gold": 2, "sea": true},
]

const ABILITY_NAMES := {"stealth": "Furtività", "ranged": "Attacco a Distanza", "flying": "Volo", "regen": "Rigenerazione", "mage": "Mago"}
const CHAR_NAMES := {"feral": "Ferino", "fragile": "Fragile", "huge": "Enorme"}
const TERRAIN_NAMES := {"p": "Pianura", "f": "Bosco", "m": "Montagna", "s": "Palude", "w": "Mare"}

# ---------------------------------------------------------------- tabella delle rivolte (12.4.3)

const REVOLT_TABLE := [
	{"r": 4, "n": "Una stagione di fuoco e terrore"},
	{"r": 3, "n": "Nobili traditori formano una fazione"},
	{"r": 2, "n": "Un comandante tenta il colpo di stato"},
	{"r": 1, "n": "Rivolta contadina"},
	{"r": 1, "n": "Rivolta contadina"},
	{"r": 0, "n": "Imperium in Aeternum"},
]

# ---------------------------------------------------------------- campagne
# Dal «Libro delle campagne (ricostruito)». maps: 0 Broken Coast, 1 Wildlands, 2 Imperial Heartland,
# 3 Fields of Ash. start/end: [anno, stagione] (0 primavera … 2 autunno). Le stagioni contano dalla
# prima all'ultima compresa. welcome: insediamento -> schieramento per cui è accogliente (ostile all'altro).
# Gli insediamenti neutrali o fedeli a regni non giocabili non elencati sono ostili a tutti.

const CAMPAIGNS := [
	{
		"id": 0, "n": "L'invasione di Drefeld", "short": "Drefeld",
		"desc": "Campagna introduttiva: Fjordland invade il sud delle Wildlands difeso dagli Oathborn. Sei insediamenti in palio.",
		"maps": [1], "sides": {2: 0, 4: 1}, "order": [4, 2], "start": [1, 0], "end": [2, 2],
		"income": {4: 2, 2: 3}, "gold": {4: 12, 2: 12},
		"free": [{"k": 4, "u": "o_mine", "at": ["Dwarven Falls", "The Endless Paths"]}],
		"ctrl": [[2, "Norstead"], [2, "Far Tumed"], [4, "Shaded Vale"]],
		"inplay": ["Fort Gorod", "Zarinbar", "Shaded Vale", "Barlas on the Lake", "Norstead", "Far Tumed"],
		"welcome": {}, "players": [1, 2],
	},
	{
		"id": 1, "n": "Il risveglio della Spira", "short": "La Spira",
		"desc": "La Spira della Luna si risveglia: le Congreghe della Regina Strega si infiltrano nei villaggi delle Wildlands, i nani difendono le rocche del nord.",
		"maps": [1], "sides": {0: 0, 4: 1}, "order": [0, 4], "start": [1, 0], "end": [2, 2],
		"income": {0: 3, 4: 4}, "gold": {0: 15, 4: 12},
		"free": [{"k": 0, "u": "n_vamp", "at": ["Spire of the Moon"]}, {"k": 4, "u": "o_mine", "at": ["The Trollshaft"]}, {"k": 4, "u": "o_mine", "at": ["Black Deep"]}],
		"covens": 2, "ctrl": [],
		"welcome": {"Barlas on the Lake": 1}, "players": [1, 2],
	},
	{
		"id": 2, "n": "Fuoco sulla Costa Spezzata", "short": "Costa Spezzata",
		"desc": "Le tribù goblin scendono dalle Oskolton verso i fiordi: Fjordland deve tenerle lontane dai suoi porti.",
		"maps": [0], "sides": {3: 0, 2: 1}, "order": [3, 2], "start": [1, 0], "end": [2, 2],
		"income": {3: 4, 2: 8}, "gold": {3: 18, 2: 8},
		"free": [{"k": 3, "u": "g_htro", "at": ["@entry"]}, {"k": 3, "u": "g_warr", "at": ["@entry"]}, {"k": 3, "u": "g_warr", "at": ["@entry"]},
			{"k": 2, "u": "f_rang", "at": ["Belgunot"]}, {"k": 2, "u": "f_free", "at": ["The Bjornfoss"]}],
		"ctrl": [],
		"welcome": {"Gorpin": 1, "The Heinburg": 1, "Highgarden": 1, "Nordhome": 1, "Seekirk": 1, "Barzirak": 1}, "players": [1, 2],
	},
	{
		"id": 3, "n": "La guerra dei Jarl", "short": "Guerra dei Jarl",
		"desc": "Quattordici anni prima della guerra, Fjordland si ribella all'Impero: i Jarl sbarcano nel cuore dell'Impero.",
		"maps": [2], "sides": {2: 0, 1: 1}, "order": [2, 1], "start": [1, 0], "end": [2, 2],
		"income": {2: 5, 1: 9}, "gold": {2: 20, 1: 10},
		"free": [{"k": 2, "u": "f_bers", "at": ["Vikensinger Fortress"]}, {"k": 2, "u": "f_reav", "at": ["Vikensinger Fortress"]},
			{"k": 1, "u": "e_kont", "at": ["Aureliana"]}, {"k": 1, "u": "e_kont", "at": ["Feodorus"]}],
		"ctrl": [], "temp_entry": {2: "north_sea"},
		"welcome": {}, "players": [1, 2],
	},
	{
		"id": 4, "n": "Le colonne di Placidia", "short": "Placidia",
		"desc": "Le orde degli Orchi attraversano il Deepwater e dilagano nei Fields of Ash: Impero e Oathborn difendono insieme Placidia e le rocche dei nani.",
		"maps": [3], "sides": {5: 0, 1: 1, 4: 1}, "order": [5, 1, 4], "start": [1, 1], "end": [3, 0],
		"income": {5: 5, 1: 4, 4: 4}, "gold": {5: 20, 1: 10, 4: 10},
		"free": [{"k": 5, "u": "r_ogre", "at": ["@entry"]}, {"k": 5, "u": "r_reav", "at": ["@entry"]}, {"k": 5, "u": "r_reav", "at": ["@entry"]},
			{"k": 1, "u": "e_kont", "at": ["Placidia"]},
			{"k": 4, "u": "o_iron", "at": ["Drakenhold"]}, {"k": 4, "u": "o_mine", "at": ["Flowstone"]}, {"k": 4, "u": "o_mine", "at": ["Cascades"]}],
		"ctrl": [],
		"welcome": {"Highbridge": 1, "Southbridge": 1, "Muffin Town": 1, "Pewter Falls": 1, "Shadowglen": 1, "Darhad": 1, "Port Lark": 1, "Khotan Khong": 1, "Port Gilder": 1},
		"players": [1, 3],
	},
	{
		"id": 5, "n": "La notte cala sull'Est", "short": "La notte sull'Est",
		"desc": "La Regina Strega stringe un patto con gli Orchi: le orde premono da est, le Congreghe minano le città. Nani e Impero devono reggere su due mappe.",
		"maps": [1, 3], "sides": {0: 0, 5: 0, 4: 1, 1: 1}, "order": [0, 4, 5, 1], "start": [1, 0], "end": [3, 2],
		"income": {0: 3, 5: 5, 4: 8, 1: 6}, "gold": {0: 15, 5: 20, 4: 8, 1: 12},
		"free": [{"k": 0, "u": "n_vamp", "at": ["Spire of the Moon"]},
			{"k": 5, "u": "r_ogre", "at": ["@entry"]}, {"k": 5, "u": "r_reav", "at": ["@entry"]}, {"k": 5, "u": "r_reav", "at": ["@entry"]},
			{"k": 4, "u": "o_iron", "at": ["Dwelfholm"]}, {"k": 4, "u": "o_iron", "at": ["Drakenhold"]},
			{"k": 1, "u": "e_kont", "at": ["Placidia"]}],
		"covens": 3, "ctrl": [], "temp_entry": {1: "foa_west"},
		"welcome": {"Barlas on the Lake": 1}, "players": [1, 4],
	},
	{
		"id": 6, "n": "La guerra delle Bandiere in Fiamme", "short": "Bandiere in Fiamme",
		"desc": "La grande campagna: quattro mappe e sei regni. Regina Strega, Orchi e Goblin attaccano insieme; Impero, Oathborn e Fjordland mettono da parte le vecchie rivalità.",
		"maps": [0, 1, 2, 3], "sides": {0: 0, 5: 0, 3: 0, 1: 1, 4: 1, 2: 1}, "order": [3, 2, 0, 1, 5, 4], "start": [1, 0], "end": [3, 2], "long_end": [4, 2],
		"income": {1: 13, 2: 11, 4: 9, 5: 6, 3: 5, 0: 4}, "gold": {1: 10, 2: 10, 4: 10, 0: 16, 5: 22, 3: 20},
		"free": [{"k": 1, "u": "e_kont", "at": ["Aureliana"]}, {"k": 1, "u": "e_kont", "at": ["Placidia"]},
			{"k": 2, "u": "f_rang", "at": ["Belgunot"]}, {"k": 4, "u": "o_iron", "at": ["Drakenhold"]},
			{"k": 0, "u": "n_vamp", "at": ["Spire of the Moon"]},
			{"k": 5, "u": "r_ogre", "at": ["@entry"]}, {"k": 5, "u": "r_reav", "at": ["@entry"]}, {"k": 5, "u": "r_reav", "at": ["@entry"]},
			{"k": 3, "u": "g_htro", "at": ["@entry"]}, {"k": 3, "u": "g_warr", "at": ["@entry"]}, {"k": 3, "u": "g_warr", "at": ["@entry"]}],
		"covens": 3, "ctrl": [],
		"welcome": {}, "players": [1, 6],
	},
]

# ---------------------------------------------------------------- mappa (data/world.json)

static var hexes := {}            # h -> dati statici dell'esagono
static var settlements: Array = []
static var set_by_name := {}
static var edges := {}            # chiave a*10000+b (a<b) -> {"r":0/1/2,"road":bool,"sea":bool}
static var maps: Array = []
static var dx := 139.92
static var dy := 161.4
static var cards := {}            # id -> carta
static var card_list: Array = []
static var counters := {}
static var loaded := false


static func load_all() -> void:
	if loaded:
		return
	loaded = true
	var w = JSON.parse_string(FileAccess.get_file_as_string("res://data/world.json"))
	dx = float(w["dx"])
	dy = float(w["dy"])
	maps = w["maps"]
	for h in w["hexes"]:
		var e := {"h": int(h["h"]), "t": str(h["t"]), "m": int(h["m"]), "x": float(h["x"]), "y": float(h["y"]),
			"coast": int(h.get("c", 0)) == 1, "mr": int(h.get("mr", 0)) == 1, "s": int(h.get("s", -1)),
			"lair": str(h.get("l", "")), "lair_n": str(h.get("ln", "")), "mine": str(h.get("mi", "")), "entry": str(h.get("e", "")),
			"name": str(h.get("n", ""))}
		hexes[e["h"]] = e
	settlements = []
	for s in w["settlements"]:
		var e := {"n": str(s["n"]), "h": int(s["h"]), "loy": int(s["loy"]), "city": int(s["city"]) == 1, "port": int(s["port"]) == 1,
			"fort": int(s["fort"]), "wild": str(s["wild"])}
		settlements.append(e)
		set_by_name[e["n"]] = settlements.size() - 1
	for e in w["edges"]:
		var a := int(e[0])
		var b := int(e[1])
		edges[a * 10000 + b] = {"r": int(e[2]), "road": int(e[3]) == 1, "sea": int(e[4]) == 1, "w": int(e[5]) if e.size() > 5 else 0}
	var cl = JSON.parse_string(FileAccess.get_file_as_string("res://data/cards.json"))
	card_list = cl
	for c in cl:
		cards[str(c["id"])] = c
	counters = JSON.parse_string(FileAccess.get_file_as_string("res://data/counters.json"))


static func hex_of(name: String) -> int:
	if set_by_name.has(name):
		return settlements[set_by_name[name]]["h"]
	for h in hexes:
		var e: Dictionary = hexes[h]
		if e["mine"] == name or e["lair_n"] == name:
			return h
	return -1


static func col(h: int) -> int:
	return h / 100


static func row(h: int) -> int:
	return h % 100


## I sei vicini nell'ordine N, NE, SE, S, SW, NW (colonne dispari spostate in basso).
static func neighbors(h: int) -> Array:
	var c := h / 100
	var r := h % 100
	var odd := c % 2 == 1
	var out := [c * 100 + r - 1,
		(c + 1) * 100 + (r if odd else r - 1),
		(c + 1) * 100 + (r + 1 if odd else r),
		c * 100 + r + 1,
		(c - 1) * 100 + (r + 1 if odd else r),
		(c - 1) * 100 + (r if odd else r - 1)]
	return out


static func edge(a: int, b: int) -> Dictionary:
	var k := mini(a, b) * 10000 + maxi(a, b)
	return edges.get(k, {})


static func cube(h: int) -> Vector3i:
	var c := h / 100
	var r := h % 100
	var q := c
	var rr := r - (c - (c & 1)) / 2
	return Vector3i(q, rr, -q - rr)


static func dist(a: int, b: int) -> int:
	var x := cube(a)
	var y := cube(b)
	return (absi(x.x - y.x) + absi(x.y - y.y) + absi(x.z - y.z)) / 2


static func unit_img(u: String, variant := 0) -> String:
	var imgs: Array = UNITS[u]["img"]
	return imgs[variant % imgs.size()]


static func card(id: String) -> Dictionary:
	return cards.get(id, {})


static func kname(k: int) -> String:
	if k >= 0 and k < 6:
		return KINGDOMS[k]["n"]
	return LOYAL_NAMES.get(k, "neutrale")


static func season_name(s: int) -> String:
	return SEASONS[s % 4]


static func monster(id: String) -> Dictionary:
	for m in MONSTERS:
		if m["id"] == id:
			return m
	return {}
