extends RefCounted
## Hand-authored layout of Valoria: regions, coastline, mountains, river, road network, POIs.
## Coordinates in metres: +X east, +Z south, map spans -2048..2048 on both axes. Sea lies east.
## Road point formats: [x, z] | [x, z, amp, wavelength] (meander from the previous point) |
## {"ladder": [x, z], "legs": n, "width": w, "radius": r} (switchback ladder from the previous point).
## Consumed by tools/world_bake.gd (seeded, deterministic).

const SEED := 20261023

const REGIONS := [
	{"id": 0, "name": "Verdana Valley", "desc": "Rolling farmland, forests and the river"},
	{"id": 1, "name": "Pinecrest Highlands", "desc": "Alpine pass, hairpins and snow"},
	{"id": 2, "name": "Redmesa Canyons", "desc": "Arid plateau, mesas and canyons"},
	{"id": 3, "name": "Marisol Coast", "desc": "Cliffs, beaches and the harbour"},
]

const MOUNTAIN_CENTER := Vector2(-1250, -1250)
const DESERT_CENTER := Vector2(-1250, 1150)
## gaussian peaks: x, z, height, radius
const PEAKS := [
	[-1570, -1620, 330, 420],
	[-1900, -1050, 150, 320],
	[-780, -1930, 190, 320],
	[-1170, -760, 200, 190],
	[-1960, -1960, 230, 430],
]
const MESA_THRESHOLD := 0.42
const CANYON_THRESHOLD := 0.85

## coastline: x of the shore for a given z (sea is east of it)
const COAST := [
	[-2300, 1050], [-2000, 1120], [-1800, 1260], [-1500, 1520], [-1200, 1690], [-800, 1740], [-450, 1720],
	[-150, 1650], [80, 1560], [260, 1540], [450, 1600], [750, 1730], [1050, 1750], [1350, 1650],
	[1650, 1450], [1900, 1300], [2300, 1150],
]
## beaches: [z0, z1]
const BEACHES := [[180, 560], [640, 920]]

## river from the highland spur to the sea
const RIVER := [
	[-560, -560], [-380, -400], [-160, -270], [60, -90], [240, 40], [460, 150], [700, 260], [920, 380],
	[1150, 520], [1360, 680], [1560, 800], [1820, 860],
]

const ROAD_CLASSES := {
	"highway": {"lanes": 2, "lane_w": 3.6, "shoulder": 2.6, "median": 1.2, "speed": 110, "grade": 0.07, "smooth": 260.0, "bank": 4.0, "surface": 0, "traffic": 1.0},
	"regional": {"lanes": 1, "lane_w": 3.4, "shoulder": 1.1, "median": 0.0, "speed": 80, "grade": 0.115, "smooth": 120.0, "bank": 5.0, "surface": 0, "traffic": 0.8},
	"mountain": {"lanes": 1, "lane_w": 3.2, "shoulder": 0.6, "median": 0.0, "speed": 60, "grade": 0.13, "smooth": 60.0, "bank": 4.0, "surface": 0, "traffic": 0.5},
	"village": {"lanes": 1, "lane_w": 3.1, "shoulder": 0.4, "median": 0.0, "speed": 50, "grade": 0.12, "smooth": 70.0, "bank": 1.0, "surface": 0, "traffic": 0.6},
	"gravel": {"lanes": 1, "lane_w": 2.8, "shoulder": 0.3, "median": 0.0, "speed": 50, "grade": 0.15, "smooth": 50.0, "bank": 2.0, "surface": 3, "traffic": 0.15},
	"dirt": {"lanes": 1, "lane_w": 2.6, "shoulder": 0.2, "median": 0.0, "speed": 40, "grade": 0.16, "smooth": 40.0, "bank": 1.0, "surface": 2, "traffic": 0.1},
}

## Roads in bake order (earlier roads own junction elevations).
const ROADS := [
	{"id": "loop", "name": "Festival Loop", "class": "regional", "closed": true, "scenic": true,
		"pts": [[300, 430], [480, 390, 45, 320], [660, 380], [880, 380, 45, 300], [1100, 450, 40, 300], [1300, 360],
			[1420, 250], [1460, 60], [1500, -150],
			[1470, -400, 75, 400], [1520, -760, 85, 430], [1490, -1060, 75, 400], [1410, -1310], [1290, -1520], [1110, -1700],
			[850, -1810, 80, 420], [700, -1640, 40, 300], [540, -1860, 60, 360], [230, -1830, 85, 430], [-50, -1760, 70, 380], [-260, -1690],
			{"ladder": [-960, -1300], "legs": 10, "width": 400, "radius": 18.0},
			[-1080, -1230],
			{"ladder": [-1720, -820], "legs": 8, "width": 280, "radius": 18.0},
			[-1820, -560, 60, 400], [-1780, -260, 85, 420], [-1810, 100, 140, 440], [-1760, 440, 140, 440], [-1800, 780, 140, 440],
			[-1730, 1100, 115, 430], [-1560, 1380, 50, 360],
			[-1300, 1600, 70, 360], [-1000, 1760, 75, 380], [-650, 1830, 50, 360],
			[-300, 1850, 110, 420], [50, 1800, 110, 420], [350, 1690, 90, 400], [600, 1520],
			[850, 1400, 60, 380], [1100, 1300], [1380, 1250], [1520, 1060], [1480, 860], [1340, 780],
			[1150, 860, 40, 320], [950, 800, 55, 360], [760, 760], [560, 720, 45, 340], [420, 610]]},
	{"id": "highway", "name": "Valoria Expressway", "class": "highway", "overpass": true,
		"pts": [[-2040, 1640], [-1520, 1330], [-1050, 1010], [-620, 700], [-250, 420], [60, 170], [380, -120],
			[640, -520], [800, -960], [880, -1400], [920, -2040]]},
	{"id": "avenue", "name": "Festival Avenue", "class": "village", "start_on": "loop",
		"pts": [[300, 430], [180, 380], [100, 260], [60, 170]], "end_on": "highway"},
	{"id": "valley", "name": "Riverside Road", "class": "regional", "allow_tunnel": true, "start_on": "loop",
		"pts": [[-1820, -560], [-1640, -600], [-1450, -650], [-1250, -700], [-1050, -720], [-850, -690], [-640, -600],
			[-420, -480], [-200, -360], [20, -200], [150, 90]], "end_on": "highway"},
	{"id": "summit", "name": "Summit Road", "class": "mountain", "start_on": "loop",
		"pts": [[-1080, -1230], [-1170, -1320], {"ladder": [-1390, -1490], "legs": 6, "width": 230, "radius": 15.0}, [-1430, -1510]]},
	{"id": "forest", "name": "Pine Forest Track", "class": "gravel", "start_on": "valley",
		"pts": [[-640, -600], [-700, -850, 30, 260], [-760, -1050], [-880, -1180], [-960, -1300]], "end_on": "loop"},
	{"id": "castle", "name": "Castle Lane", "class": "gravel", "start_on": "valley",
		"pts": [[-420, -480], [-450, -560], [-480, -630]]},
	{"id": "canyon", "name": "Canyon Trail", "class": "dirt", "start_on": "loop",
		"pts": [[-1810, 100], [-1500, 180, 40, 300], [-1250, 330], [-1000, 520, 40, 300], [-850, 800], [-760, 1000]], "end_on": "highway"},
	{"id": "mesa", "name": "Mesa Ridge Road", "class": "gravel", "start_on": "canyon",
		"pts": [[-1250, 330], [-1450, 600], [-1350, 900], [-1100, 1050], [-900, 950], [-850, 800]], "end_on": "canyon"},
	{"id": "harbour", "name": "Harbour Road", "class": "village", "start_on": "loop",
		"pts": [[1420, 250], [1470, 330], [1500, 395]]},
	{"id": "lighthouse", "name": "Lighthouse Road", "class": "village", "start_on": "loop",
		"pts": [[1410, -1310], [1500, -1330], [1580, -1335]]},
	{"id": "cliffs", "name": "Cliff Top Lane", "class": "village", "start_on": "lighthouse",
		"pts": [[1500, -1330], [1600, -1150, 25, 260], [1640, -900], [1630, -650, 25, 260], [1560, -500]], "end_on": "loop"},
	{"id": "windfarm", "name": "Windfarm Track", "class": "gravel", "start_on": "loop",
		"pts": [[1470, -400], [1300, -520], [1150, -700], [1000, -800], [850, -850]], "end_on": "highway"},
	{"id": "orchard", "name": "Orchard Lane", "class": "village", "start_on": "highway",
		"pts": [[380, -120], [600, -60, 30, 300], [800, 0], [1000, 150], [1100, 450]], "end_on": "loop"},
	{"id": "sunfield", "name": "Sunfield Lane", "class": "dirt", "start_on": "loop",
		"pts": [[950, 800], [980, 980], [1060, 1120], [1100, 1300]], "end_on": "loop"},
	{"id": "vineyard", "name": "Vineyard Road", "class": "village", "start_on": "highway",
		"pts": [[-250, 420], [-100, 620, 40, 300], [100, 800], [300, 1000, 40, 300], [420, 1250], [600, 1520]], "end_on": "loop"},
	{"id": "plains", "name": "Southern Plains Road", "class": "regional", "start_on": "vineyard",
		"pts": [[100, 800], [350, 870, 40, 340], [620, 940], [800, 960], [980, 980]], "end_on": "sunfield"},
	{"id": "fuel", "name": "Redmesa Fuel Road", "class": "regional", "start_on": "loop",
		"pts": [[-1760, 440], [-1550, 560, 40, 320], [-1300, 760], [-1050, 1010]], "end_on": "highway"},

	{"id": "beach", "name": "Beach Road", "class": "village", "start_on": "loop",
		"pts": [[1480, 860], [1580, 820], [1650, 790]]},
]
## Points of interest. flat: radius of the levelled pad (levelled to the nearby road height).
const POIS := [
	{"id": "hub", "name": "Valoria Festival Grounds", "type": "festival", "pos": [190, 360], "flat": 60.0, "region": 0},
	{"id": "village", "name": "Bellacqua Village", "type": "village", "pos": [660, 380], "flat": 0.0, "region": 0},
	{"id": "harbour", "name": "Porto Lume Harbour", "type": "harbour", "pos": [1490, 400], "flat": 0.0, "region": 3},
	{"id": "lighthouse", "name": "Capo Faro Lighthouse", "type": "lighthouse", "pos": [1605, -1325], "flat": 20.0, "region": 3},
	{"id": "castle", "name": "Rocca Vecchia Ruins", "type": "castle", "pos": [-490, -665], "flat": 26.0, "region": 0},
	{"id": "windfarm", "name": "Marisol Wind Farm", "type": "windfarm", "pos": [1120, -760], "flat": 0.0, "region": 3},
	{"id": "gas_desert", "name": "Redmesa Fuel Stop", "type": "gas", "pos": [-1700, 470], "flat": 28.0, "region": 2},
	{"id": "diner", "name": "Expressway Diner", "type": "diner", "pos": [730, -560], "flat": 26.0, "region": 0},
	{"id": "gas_highway", "name": "Valley Fuel", "type": "gas", "pos": [-560, 720], "flat": 26.0, "region": 0},
	{"id": "summit", "name": "Pinecrest Summit Viewpoint", "type": "viewpoint", "pos": [-1440, -1515], "flat": 18.0, "region": 1},
	{"id": "pass", "name": "Pinecrest Pass", "type": "pass", "pos": [-1020, -1265], "flat": 0.0, "region": 1},
	{"id": "farm1", "name": "Sunfield Farm", "type": "farm", "pos": [1060, 1040], "flat": 0.0, "region": 0},
	{"id": "farm2", "name": "Orchard Farm", "type": "farm", "pos": [820, 60], "flat": 0.0, "region": 0},
	{"id": "canyon_view", "name": "Canyon Overlook", "type": "viewpoint", "pos": [-1080, 1090], "flat": 14.0, "region": 2},
	{"id": "beach", "name": "Marisol Beach", "type": "beach", "pos": [1650, 790], "flat": 0.0, "region": 3},
	{"id": "hamlet", "name": "Alpe Rosa Hamlet", "type": "hamlet", "pos": [-1600, -620], "flat": 0.0, "region": 1},
]

## Settlements: buildings are scattered along roads near these centres.
const SETTLEMENTS := [
	{"poi": "village", "radius": 240.0, "count": 22, "kits": ["house_a", "house_b", "house_c", "shop", "church"]},
	{"poi": "harbour", "radius": 170.0, "count": 9, "kits": ["house_a", "house_c", "shed", "boathouse"]},
	{"poi": "hamlet", "radius": 160.0, "count": 7, "kits": ["chalet", "house_b", "barn"]},
	{"poi": "farm1", "radius": 110.0, "count": 4, "kits": ["farmhouse", "barn", "silo", "shed"]},
	{"poi": "farm2", "radius": 110.0, "count": 4, "kits": ["farmhouse", "barn", "silo", "shed"]},
	{"poi": "gas_desert", "radius": 60.0, "count": 1, "kits": ["gas_station"]},
	{"poi": "gas_highway", "radius": 60.0, "count": 1, "kits": ["gas_station"]},
	{"poi": "diner", "radius": 140.0, "count": 1, "kits": ["diner"]},
]

## Races by fraction of road length
const RACES := [
	["loop", 0.035, 0.2, "Marisol Coastal Sprint"],
	["loop", 0.27, 0.43, "Pinecrest Hairpin Climb"],
	["loop", 0.45, 0.62, "Redmesa Plateau Run"],
	["canyon", 0.02, 0.98, "Canyon Trail Rally"],
	["highway", 0.06, 0.94, "Expressway Dash"],
]

const SPAWN := {"road": "loop", "s": 70.0}
