class_name WorldLayout
extends RefCounted
## Hand-authored layout of the Sunward Roads map (metres). X = east, Z = south (Godot -Z = north).
## Terrain is procedural (WorldGen.base_height); roads are spline-interpolated through these control
## points, then meandered, profiled to the terrain and carved in (cuttings/embankments/bridges/tunnels).

const SEED := 20261023
const HALF := 2048.0           # heightmap covers [-HALF, HALF] on both axes
const PLAY_HALF := 1960.0      # drivable area limit
const SEA_LEVEL := 0.0

enum RoadClass { HIGHWAY, REGIONAL, MOUNTAIN, STREET, DIRT, GRAVEL, SAND }

## Per class: width of the paved surface (m), lanes per direction, shoulder (m), speed limit (km/h),
## surface id, traffic allowed, max grade, profile smoothing window (m), markings style.
const CLASS_INFO := {
	RoadClass.HIGHWAY: {"width": 14.5, "lanes": 2, "shoulder": 1.6, "limit": 110, "surface": &"asphalt", "traffic": true, "grade": 0.065, "smooth": 260.0, "marking": 2},
	RoadClass.REGIONAL: {"width": 8.0, "lanes": 1, "shoulder": 0.9, "limit": 90, "surface": &"asphalt", "traffic": true, "grade": 0.1, "smooth": 140.0, "marking": 1},
	RoadClass.MOUNTAIN: {"width": 7.2, "lanes": 1, "shoulder": 0.6, "limit": 70, "surface": &"asphalt", "traffic": true, "grade": 0.115, "smooth": 90.0, "marking": 1},
	RoadClass.STREET: {"width": 7.0, "lanes": 1, "shoulder": 1.4, "limit": 50, "surface": &"asphalt", "traffic": true, "grade": 0.1, "smooth": 80.0, "marking": 3},
	RoadClass.DIRT: {"width": 5.5, "lanes": 1, "shoulder": 0.5, "limit": 60, "surface": &"dirt", "traffic": false, "grade": 0.14, "smooth": 60.0, "marking": 0},
	RoadClass.GRAVEL: {"width": 5.5, "lanes": 1, "shoulder": 0.5, "limit": 60, "surface": &"gravel", "traffic": false, "grade": 0.14, "smooth": 60.0, "marking": 0},
	RoadClass.SAND: {"width": 6.0, "lanes": 1, "shoulder": 0.3, "limit": 50, "surface": &"sand", "traffic": false, "grade": 0.12, "smooth": 50.0, "marking": 0},
}

const REGIONS := [
	{"id": 0, "name": "Verdant Vale", "desc": "Rolling farmland, hedgerows, forest and the river Wend", "color": Color(0.45, 0.62, 0.3)},
	{"id": 1, "name": "Ironcrest Highlands", "desc": "Alpine pass, hairpins, pine forest and snowy peaks", "color": Color(0.55, 0.58, 0.62)},
	{"id": 2, "name": "Ochre Mesa", "desc": "Desert plateau, red mesas, a deep canyon and a wind farm", "color": Color(0.82, 0.55, 0.32)},
	{"id": 3, "name": "Saltwind Coast", "desc": "Sea cliffs, beaches, a harbour hamlet and the long Estuary Bridge", "color": Color(0.35, 0.6, 0.75)},
]

## Roads. "pts" are [x, z] control points. "loop": closed curve. "meander": [amplitude m, wavelength m].
## "from"/"to": optional junction attachments: the endpoint snaps onto the named road.
const ROADS := [
	{"id": "ring", "name": "Sunward Ring", "class": RoadClass.REGIONAL, "loop": true, "meander": [80.0, 560.0],
	 "pts": [
		[-200, 650], [-360, 640], [-500, 590], [-600, 500], [-700, 520], [-760, 600], [-860, 640], [-1000, 560], [-1120, 470], [-1260, 430],
		[-1400, 340], [-1520, 220], [-1640, 120], [-1720, -40], [-1700, -200], [-1640, -380],
		# Switchbacks climbing to the Highmoor plateau (4 hairpins)
		[-1600, -460], [-1440, -515],
		[-1400, -530], [-1382, -560], [-1400, -592], [-1440, -605],
		[-1720, -650],
		[-1762, -664], [-1780, -695], [-1762, -726], [-1720, -738],
		[-1440, -782],
		[-1400, -795], [-1382, -826], [-1400, -858], [-1440, -870],
		[-1700, -912],
		[-1742, -926], [-1760, -957], [-1742, -988], [-1700, -1000],
		[-1440, -1040],
		[-1400, -1052], [-1382, -1085], [-1400, -1118], [-1440, -1130],
		[-1680, -1170],
		[-1722, -1184], [-1740, -1215], [-1722, -1246], [-1680, -1258],
		[-1560, -1290], [-1460, -1300],
		# Highmoor -> alpine detour toward the snow line -> Ironcrest Pass summit
		[-1380, -1400], [-1480, -1540], [-1480, -1740], [-1330, -1860], [-1130, -1840], [-1010, -1690], [-960, -1550], [-860, -1450],
		# Winding descent east, tunnel through Ember Spur
		[-760, -1400], [-720, -1290], [-660, -1180], [-600, -1060], [-520, -1020], [-440, -1090], [-400, -1180],
		[-340, -1260], [-160, -1230], [60, -1210],
		# Ochre Mesa plateau run (sweeping S-bends)
		[260, -1150], [420, -980], [480, -720], [700, -580], [920, -760], [960, -1060], [1100, -1290], [1260, -1160],
		[1420, -1060], [1480, -1220], [1600, -1300], [1700, -1150], [1740, -980], [1820, -760], [1790, -520], [1760, -300], [1660, -60],
		# Ochre Gorge descent toward the coast
		[1580, 80], [1500, 180], [1440, 380], [1500, 520], [1440, 640], [1520, 780], [1640, 880], [1690, 1040],
		# Lighthouse headland loop, then the Saltwind cliff road heading west
		[1760, 1200], [1820, 1380], [1760, 1490], [1640, 1470], [1520, 1390], [1400, 1310], [1240, 1290], [1060, 1310], [900, 1350], [780, 1330], [640, 1380], [520, 1300], [480, 1160],
		[380, 1080], [280, 1170], [240, 1320], [120, 1400], [-40, 1380], [-160, 1420], [-300, 1430],
		# Estuary Bridge
		[-480, 1455], [-720, 1465], [-960, 1445],
		# Beach road and the west coast
		[-1150, 1400], [-1330, 1360], [-1500, 1300], [-1660, 1190], [-1760, 1020], [-1720, 860], [-1560, 780],
		# Back east through the southern vale
		[-1380, 840], [-1330, 1010], [-1220, 1170], [-1060, 1120], [-980, 960], [-900, 920], [-760, 880], [-600, 900], [-460, 860],
		[-320, 870], [-170, 830], [-80, 740],
	 ]},
	{"id": "expressway", "name": "Sunward Expressway", "class": RoadClass.HIGHWAY, "meander": [0.0, 0.0],
	 "from": "ring", "to": "ring",
	 "pts": [[-1660, 60], [-1380, 120], [-1050, 150], [-760, 130], [-420, 170], [-60, 190], [280, 120], [600, -40],
		[900, -230], [1180, -380], [1460, -470], [1780, -470]]},
	{"id": "vale_north", "name": "Wend Valley Road", "class": RoadClass.REGIONAL, "meander": [10.0, 300.0],
	 "from": "ring", "to": "expressway",
	 "pts": [[-1000, 520], [-980, 400], [-930, 260], [-900, 145]]},
	{"id": "festival_coast", "name": "Festival Lane", "class": RoadClass.REGIONAL, "meander": [8.0, 260.0],
	 "from": "ring", "to": "ring",
	 "pts": [[-260, 868], [-210, 980], [-260, 1100], [-200, 1240], [-240, 1420]]},
	{"id": "canyon_link", "name": "Canyon Link", "class": RoadClass.REGIONAL, "meander": [14.0, 340.0],
	 "from": "expressway", "to": "ring",
	 "pts": [[1150, -360], [1120, -120], [1020, 120], [960, 420], [940, 720], [1000, 1000], [1060, 1360]]},
	{"id": "lake_road", "name": "Mirror Lake Road", "class": RoadClass.REGIONAL, "meander": [12.0, 320.0],
	 "from": "expressway", "to": "ring",
	 "pts": [[300, 110], [280, -160], [210, -430], [240, -700], [320, -930], [330, -1180]]},
	{"id": "backroad", "name": "Orchard Backroad", "class": RoadClass.STREET, "meander": [8.0, 220.0],
	 "from": "ring", "to": "expressway",
	 "pts": [[-300, 643], [-230, 520], [-140, 420], [-60, 195]]},
	{"id": "millbrook_st", "name": "Millbrook High Street", "class": RoadClass.STREET, "meander": [0.0, 0.0],
	 "from": "ring", "to": "ring",
	 "pts": [[-1120, 470], [-1180, 600], [-1200, 720], [-1060, 860]]},
	{"id": "harbour_st", "name": "Gullhaven Quay", "class": RoadClass.STREET, "meander": [0.0, 0.0],
	 "from": "ring", "to": "ring",
	 "pts": [[900, 1350], [960, 1400], [1060, 1415], [1160, 1395], [1240, 1290]]},
	{"id": "lighthouse", "name": "Lighthouse Point Road", "class": RoadClass.MOUNTAIN, "meander": [6.0, 200.0],
	 "from": "ring",
	 "pts": [[1815, 1400], [1830, 1500], [1790, 1560]]},
	{"id": "desert_north", "name": "Gale Ridge Road", "class": RoadClass.REGIONAL, "meander": [16.0, 300.0],
	 "from": "ring", "to": "ring",
	 "pts": [[1745, -985], [1860, -1150], [1760, -1450], [1500, -1620], [1240, -1560], [1100, -1290]]},
	{"id": "vale_loop", "name": "Poppy Hill Road", "class": RoadClass.REGIONAL, "meander": [12.0, 260.0],
	 "from": "backroad", "to": "ring",
	 "pts": [[-140, 420], [40, 560], [120, 800], [260, 960], [380, 1080]]},
	{"id": "coast_hills", "name": "Saltwind Hills Road", "class": RoadClass.REGIONAL, "meander": [12.0, 260.0],
	 "from": "canyon_link", "to": "ring",
	 "pts": [[960, 420], [1120, 520], [1300, 560], [1440, 640]]},
	{"id": "keep_road", "name": "Old Keep Road", "class": RoadClass.MOUNTAIN, "meander": [10.0, 180.0],
	 "from": "ring",
	 "pts": [[-1560, -1290], [-1680, -1380], [-1760, -1450], [-1820, -1500]]},
	{"id": "riverside", "name": "Wend Riverside Track", "class": RoadClass.GRAVEL, "meander": [8.0, 160.0],
	 "from": "ring", "to": "ring",
	 "pts": [[-900, 920], [-850, 820], [-830, 700], [-812, 640]]},
	{"id": "riverside_n", "name": "Wend Riverside Track North", "class": RoadClass.GRAVEL, "meander": [8.0, 160.0],
	 "from": "ring", "to": "expressway",
	 "pts": [[-770, 600], [-780, 480], [-760, 380], [-720, 150]]},
	{"id": "plateau_stage", "name": "Plateau Rally Stage", "class": RoadClass.DIRT, "meander": [20.0, 200.0],
	 "from": "desert_north", "to": "ring",
	 "pts": [[1240, -1560], [1080, -1620], [900, -1560], [820, -1420], [880, -1280], [1000, -1180]]},
	# Off-road tracks (no traffic)
	{"id": "orchard_track", "name": "Orchard Track", "class": RoadClass.GRAVEL, "meander": [10.0, 180.0],
	 "from": "vale_loop", "to": "expressway",
	 "pts": [[40, 560], [200, 600], [360, 520], [440, 330], [470, 40]]},
	{"id": "rim_trail", "name": "Ochre Rim Trail", "class": RoadClass.DIRT, "meander": [14.0, 200.0],
	 "from": "canyon_link", "to": "ring",
	 "pts": [[1020, 120], [1180, 200], [1340, 180], [1500, 170]]},
	{"id": "lake_loop", "name": "Mirror Lake Shore Track", "class": RoadClass.GRAVEL, "meander": [8.0, 160.0],
	 "from": "lake_road", "to": "lake_road",
	 "pts": [[210, -430], [40, -420], [-160, -460], [-240, -620], [-150, -790], [60, -800], [240, -700]]},
	{"id": "farm_track", "name": "Hedgerow Track", "class": RoadClass.GRAVEL, "meander": [10.0, 160.0],
	 "from": "millbrook_st", "to": "ring",
	 "pts": [[-1200, 720], [-1380, 640], [-1520, 560], [-1600, 420], [-1560, 330]]},
	{"id": "mesa_cut", "name": "Mesa Cut", "class": RoadClass.DIRT, "meander": [18.0, 240.0],
	 "from": "ring", "to": "expressway",
	 "pts": [[1220, -1100], [1300, -900], [1420, -760], [1380, -600], [1460, -470]]},
	{"id": "canyon_floor", "name": "Redwall Canyon Trail", "class": RoadClass.DIRT, "meander": [14.0, 200.0],
	 "from": "expressway", "to": "canyon_link",
	 "pts": [[900, -230], [760, -20], [700, 260], [820, 520], [940, 720]]},
	# Leaves the expressway east of its river bridge and follows the Wend upstream on the east bank (>= 40 m
	# from the water, so it stays on natural ground; water clearance only applies where a road crosses).
	{"id": "forest_track", "name": "Pinewood Track", "class": RoadClass.GRAVEL, "meander": [8.0, 180.0],
	 "from": "expressway",
	 "pts": [[-690, 138], [-725, 20], [-735, -200], [-700, -440], [-612, -690], [-540, -890]]},
	{"id": "dune_track", "name": "Dune Run", "class": RoadClass.SAND, "meander": [12.0, 180.0],
	 "from": "ring", "to": "ring",
	 "pts": [[-1420, 1330], [-1300, 1520], [-1080, 1560], [-960, 1440]]},
	# Dead end on the ridge ~50 m short of the ring's alpine climb (it used to run out over the ring, 14 m above it).
	{"id": "highmoor_track", "name": "Highmoor Ridge Track", "class": RoadClass.GRAVEL, "meander": [10.0, 160.0],
	 "from": "keep_road",
	 "pts": [[-1760, -1450], [-1700, -1620], [-1580, -1760], [-1505, -1791]]},
]

## Points of interest: teleport targets, settlements, landmarks. Positions are [x, z].
const POIS := [
	{"name": "Sunward Festival", "kind": "hub", "pos": [-180, 745], "region": 0},
	{"name": "Millbrook", "kind": "village", "pos": [-1150, 640], "region": 0},
	{"name": "Wend Farm", "kind": "farm", "pos": [-1480, 520], "region": 0},
	{"name": "Crossroads Diner", "kind": "diner", "pos": [-780, 200], "region": 0},
	{"name": "Mirror Lake", "kind": "landmark", "pos": [60, -600], "region": 0},
	{"name": "Highmoor", "kind": "hamlet", "pos": [-1530, -1340], "region": 1},
	{"name": "Ironcrest Pass", "kind": "viewpoint", "pos": [-930, -1490], "region": 1},
	{"name": "Ember Spur Tunnel", "kind": "landmark", "pos": [-260, -1250], "region": 1},
	{"name": "Old Keep Ruins", "kind": "castle", "pos": [-1850, -1500], "region": 1},
	{"name": "Mesa Fuel", "kind": "gas", "pos": [1240, -420], "region": 2},
	{"name": "Dustwater", "kind": "hamlet", "pos": [1080, -60], "region": 2},
	{"name": "Gale Ridge Wind Farm", "kind": "landmark", "pos": [1100, -1500], "region": 2},
	{"name": "Redwall Canyon", "kind": "landmark", "pos": [760, 250], "region": 2},
	{"name": "Gullhaven", "kind": "harbour", "pos": [1060, 1400], "region": 3},
	{"name": "Saltwind Lighthouse", "kind": "lighthouse", "pos": [1780, 1520], "region": 3},
	{"name": "Estuary Bridge", "kind": "landmark", "pos": [-720, 1460], "region": 3},
	{"name": "Seabreak Diner", "kind": "diner", "pos": [280, 1330], "region": 3},
	{"name": "Coast Fuel", "kind": "gas", "pos": [-1650, 1120], "region": 3},
]

## Rivers / lakes (water surfaces). River control points [x, z, water_y].
const RIVER := [[-560, -1000, 120.0], [-640, -760, 70.0], [-760, -480, 42.0], [-820, -180, 30.0], [-790, 120, 22.0],
	[-720, 420, 15.0], [-700, 700, 10.0], [-690, 1000, 5.0], [-710, 1300, 1.0], [-720, 1600, -0.5]]
const LAKES := [
	{"name": "Mirror Lake", "pos": [-40, -600], "radius": 150.0, "level": 0.0},  # level filled by the generator
]

## Spur ridge the ring road tunnels through (centre x, z, radius, extra height).
const TUNNEL_SPUR := [-260, -1250, 260.0, 80.0]
## No meander inside these circles [x, z, radius]: hand-shaped switchbacks and tunnel approaches.
const NO_MEANDER_ZONES := [[-1580.0, -880.0, 470.0], [-260.0, -1250.0, 330.0]]
## Roads may only tunnel inside these circles [x, z, radius]; elsewhere the profile limits cutting depth.
const TUNNEL_ZONES := [[-260, -1250, 230.0]]
const MAX_CUT := 12.0
