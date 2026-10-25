extends RefCounted
## Hand-designed macro layout of the 4 km x 4 km map (Godot axes: +X east, +Z south).
## The seeded generator (tools/bake_world.gd) turns this into terrain, splines, elevation
## profiles, bridges, tunnels, junctions, settlements and dressing.

const SEED := 20261023
const HALF := 2000.0
const SEA_LEVEL := 0.0
const LAKE_CENTER := Vector2(-900.0, -350.0)
const LAKE_RADII := Vector2(270.0, 220.0)
const LAKE_LEVEL := 34.0
const SNOW_LINE := 500.0

## Road classes: width (m), lanes, lane width, shoulder, speed limit (km/h), grade limit, smoothing window (m)
const CLASSES := {
	"highway": {"width": 21.0, "lanes": 4, "lane_width": 3.6, "shoulder": 2.4, "speed": 110, "grade": 0.06, "smooth": 180.0, "median": 1.2},
	"main": {"width": 9.2, "lanes": 2, "lane_width": 3.5, "shoulder": 1.1, "speed": 90, "grade": 0.085, "smooth": 90.0, "median": 0.0},
	"mountain": {"width": 7.8, "lanes": 2, "lane_width": 3.3, "shoulder": 0.6, "speed": 60, "grade": 0.105, "smooth": 50.0, "median": 0.0},
	"village": {"width": 6.8, "lanes": 2, "lane_width": 3.0, "shoulder": 0.4, "speed": 40, "grade": 0.1, "smooth": 40.0, "median": 0.0},
	"gravel": {"width": 5.6, "lanes": 1, "lane_width": 5.6, "shoulder": 0.0, "speed": 60, "grade": 0.16, "smooth": 30.0, "median": 0.0},
	"dirt": {"width": 5.0, "lanes": 1, "lane_width": 5.0, "shoulder": 0.0, "speed": 50, "grade": 0.18, "smooth": 25.0, "median": 0.0},
}

## Each road: name, class, surface, closed loop?, control points [x, z] or [x, z, "tunnel"] marks a tunnel
## span until the next point flagged "tunnel_end". start/end may attach to another road (junction).
const ROADS := [
	{"name": "Ridgeline Loop", "class": "main", "surface": "asphalt", "loop": true, "scenic": true, "points": [
		[-640, 600], [-540, 570], [-470, 520], [-400, 465], [-330, 400], [-250, 325], [-170, 230], [-110, 150],
		[-10, 70], [80, 15], [150, -70], [225, -140], [290, -220], [345, -305], [400, -390], [430, -470], [470, -560],
		[560, -615], [700, -630], [880, -645], [980, -680], [1000, -735], [940, -765], [820, -775], [640, -778],
		[480, -790], [370, -815], [350, -870], [420, -900], [520, -905], [700, -918], [880, -935], [985, -965],
		[1000, -1025], [940, -1052], [830, -1060], [680, -1072], [560, -1090], [470, -1125], [470, -1180],
		[560, -1198], [690, -1198], [850, -1182], [960, -1170],
		[1010, -1172, "tunnel"], [1150, -1215], [1260, -1225, "tunnel_end"],
		[1400, -1190], [1560, -1150], [1700, -1110], [1800, -1070], [1830, -1020], [1790, -985], [1640, -975],
		[1450, -965], [1330, -950], [1290, -905], [1330, -870], [1490, -860], [1690, -845], [1800, -815],
		[1825, -765], [1780, -730], [1620, -715], [1480, -700], [1400, -665], [1410, -610], [1500, -580],
		[1620, -550], [1720, -485],
		[1775, -400], [1800, -300], [1740, -210], [1640, -140], [1610, -40], [1690, 60], [1750, 160], [1680, 270],
		[1630, 370], [1560, 440], [1500, 520], [1460, 640], [1470, 760], [1520, 880], [1560, 1000],
		[1660, 1080], [1780, 1180], [1850, 1350], [1820, 1520], [1720, 1680], [1550, 1780], [1350, 1790], [1150, 1720],
		[1000, 1640], [850, 1690], [700, 1720], [520, 1680], [400, 1660], [250, 1720], [100, 1760], [-20, 1700],
		[-130, 1620], [-260, 1605], [-370, 1670], [-440, 1750], [-500, 1780], [-650, 1760], [-800, 1690], [-950, 1610], [-1050, 1560],
		[-1150, 1500], [-1250, 1420], [-1330, 1330], [-1380, 1250], [-1420, 1130], [-1450, 1000], [-1440, 880],
		[-1470, 750], [-1530, 620], [-1520, 500], [-1450, 400], [-1430, 300], [-1490, 210], [-1540, 120], [-1560, 0],
		[-1590, -150], [-1580, -300], [-1550, -450], [-1545, -600], [-1575, -750], [-1580, -900], [-1550, -1050],
		[-1500, -1200], [-1420, -1330], [-1320, -1450], [-1200, -1570], [-1060, -1640], [-930, -1600],
		[-850, -1500], [-800, -1420], [-700, -1340], [-610, -1250], [-570, -1130], [-560, -1000], [-650, -880], [-800, -800],
		[-960, -730], [-1120, -650], [-1240, -500], [-1275, -330], [-1230, -170], [-1110, -80], [-960, -70],
		[-800, -60], [-690, -10], [-700, 120], [-730, 230], [-735, 330], [-720, 420], [-700, 500]]},
	{"name": "Sunline Highway", "class": "highway", "surface": "asphalt", "start_join": "Ridgeline Loop", "end_join": "Ridgeline Loop", "points": [
		[-1395, 1185], [-1150, 1120], [-850, 1090], [-560, 1075], [-250, 1010], [60, 965], [380, 930], [700, 860],
		[1000, 790], [1250, 740], [1440, 720]]},
	{"name": "Valley Link", "class": "main", "surface": "asphalt", "start_join": "Sunline Highway", "end_join": "Ridgeline Loop", "points": [
		[160, 950], [135, 760], [95, 520], [60, 300], [-5, 75]]},
	{"name": "Millbrook Lane", "class": "village", "surface": "asphalt", "start_join": "Ridgeline Loop", "end_join": "Ridgeline Loop", "points": [
		[-455, 513], [-470, 600], [-420, 680], [-320, 690], [-230, 620], [-215, 520], [-250, 440], [-330, 402]]},
	{"name": "Harbour Road", "class": "village", "surface": "asphalt", "start_join": "Ridgeline Loop", "points": [
		[-1452, 990], [-1530, 960], [-1600, 940], [-1635, 925]]},
	{"name": "Lighthouse Lane", "class": "village", "surface": "asphalt", "start_join": "Ridgeline Loop", "points": [
		[-1577, -910], [-1650, -960], [-1730, -1000], [-1770, -1030]]},
	{"name": "Summit Trail", "class": "gravel", "surface": "gravel", "start_join": "Ridgeline Loop", "points": [
		[850, -1182], [860, -1260], [960, -1310], [1050, -1360], [1010, -1430], [920, -1480], [860, -1560]]},
	{"name": "Pinewood Rally Stage", "class": "gravel", "surface": "gravel", "start_join": "Ridgeline Loop", "end_join": "Ridgeline Loop", "points": [
		[-565, -990], [-420, -960], [-260, -900], [-120, -800], [-40, -660], [-110, -520], [-260, -440],
		[-420, -400], [-560, -280], [-650, -110], [-692, -30]]},
	{"name": "Barley Track", "class": "dirt", "surface": "dirt", "start_join": "Ridgeline Loop", "end_join": "Sunline Highway", "points": [
		[100, 1750], [140, 1560], [230, 1400], [300, 1230], [330, 1080], [330, 935]]},
	{"name": "Orchard Track", "class": "dirt", "surface": "dirt", "start_join": "Ridgeline Loop", "end_join": "Sunline Highway", "points": [
		[-500, 1775], [-470, 1560], [-360, 1400], [-250, 1260], [-170, 1130], [-150, 1012]]},
	{"name": "Windmill Ridge Road", "class": "gravel", "surface": "gravel", "start_join": "Ridgeline Loop", "points": [
		[700, 1700], [760, 1520], [860, 1390], [1000, 1290], [1140, 1190]]},
	{"name": "Mesa Cutoff", "class": "dirt", "surface": "dirt", "start_join": "Ridgeline Loop", "end_join": "Eastern Valley Road", "points": [
		[1642, -80], [1450, -30], [1250, 40], [1050, 160], [930, 300], [845, 405]]},
	{"name": "Canyon Floor Run", "class": "dirt", "surface": "sand", "start_join": "Ridgeline Loop", "end_join": "Ridgeline Loop", "points": [
		[1792, -350], [1870, -250], [1900, -20], [1880, 220], [1800, 400], [1660, 440], [1560, 445]]},
	{"name": "Lakeshore Drive", "class": "main", "surface": "asphalt", "start_join": "Ridgeline Loop", "end_join": "Ridgeline Loop", "points": [
		[-1505, 240], [-1420, 160], [-1330, 80], [-1250, -20], [-1190, -118]]},
	{"name": "Castle Hill Road", "class": "village", "surface": "concrete", "start_join": "Ridgeline Loop", "points": [
		[-612, -1255], [-520, -1330], [-420, -1380], [-340, -1390]]},
	{"name": "Cliffside Trail", "class": "gravel", "surface": "gravel", "start_join": "Ridgeline Loop", "end_join": "Ridgeline Loop", "points": [
		[-1560, 2], [-1615, -150], [-1650, -380], [-1640, -600], [-1610, -820], [-1582, -895]]},
	{"name": "Northern Ridge Road", "class": "mountain", "surface": "asphalt", "start_join": "Ridgeline Loop", "end_join": "Summit Trail", "points": [
		[-800, -1420], [-560, -1560], [-300, -1660], [0, -1700], [300, -1660], [560, -1590], [760, -1560], [858, -1555]]},
	{"name": "Eastern Valley Road", "class": "main", "surface": "asphalt", "start_join": "Sunline Highway", "end_join": "Ridgeline Loop", "points": [
		[1000, 790], [930, 560], [820, 360], [680, 160], [560, -60], [470, -250], [405, -385]]},
	{"name": "Dune Beach Road", "class": "dirt", "surface": "sand", "start_join": "Ridgeline Loop", "points": [
		[-1050, 1560], [-1180, 1650], [-1330, 1720], [-1480, 1760]]},
	{"name": "Granary Road", "class": "main", "surface": "asphalt", "start_join": "Sunline Highway", "end_join": "Ridgeline Loop", "points": [
		[-560, 1078], [-590, 1250], [-630, 1440], [-650, 1600], [-650, 1758]]},
	{"name": "Quarry Road", "class": "gravel", "surface": "gravel", "start_join": "Ridgeline Loop", "points": [
		[1720, 1678], [1560, 1500], [1380, 1330], [1260, 1180], [1200, 1040]]},
	{"name": "Highland Link", "class": "mountain", "surface": "asphalt", "start_join": "Ridgeline Loop", "end_join": "Summit Trail", "points": [
		[1560, -1150], [1530, -1290], [1450, -1400], [1320, -1470], [1180, -1440], [1080, -1380], [1052, -1362]]},
	{"name": "Vineyard Lane", "class": "village", "surface": "asphalt", "start_join": "Ridgeline Loop", "end_join": "Sunline Highway", "points": [
		[520, 1680], [560, 1450], [620, 1250], [680, 1050], [700, 862]]},
	{"name": "Canyon Rim Trail", "class": "dirt", "surface": "dirt", "start_join": "Mesa Cutoff", "end_join": "Ridgeline Loop", "points": [
		[1250, 40], [1300, -200], [1380, -400], [1445, -585]]},
	{"name": "Mill Lane", "class": "village", "surface": "asphalt", "start_join": "Millbrook Lane", "end_join": "Sunline Highway", "points": [
		[-320, 690], [-330, 820], [-345, 930], [-360, 1035]]},
]

## River from the highland foothills to the sea (x, z); width grows downstream.
const RIVER := [[1050, -650], [930, -470], [820, -300], [700, -120], [560, 50], [400, 190], [250, 300],
	[100, 410], [-50, 520], [-230, 660], [-400, 800], [-600, 950], [-800, 1100], [-980, 1230], [-1150, 1350],
	[-1330, 1490], [-1500, 1620], [-1640, 1680], [-1800, 1720]]

## Settlements and points of interest (x, z). Buildings/props are scattered by the generator.
const SETTLEMENTS := [
	{"name": "Millbrook", "kind": "village", "pos": [-340, 540], "radius": 170, "houses": 26},
	{"name": "Saltwind Harbour", "kind": "harbour", "pos": [-1560, 950], "radius": 110, "houses": 12},
	{"name": "Copperbend Farm", "kind": "farm", "pos": [260, 1320], "radius": 70, "houses": 4},
	{"name": "Hollyfield Farm", "kind": "farm", "pos": [-330, 1330], "radius": 70, "houses": 4},
	{"name": "Larkspur Farm", "kind": "farm", "pos": [-1000, 1300], "radius": 60, "houses": 3},
	{"name": "Redrock Fuel Stop", "kind": "gas", "pos": [1430, 560], "radius": 45, "houses": 1},
	{"name": "Valley Fuel & Diner", "kind": "gas", "pos": [-560, 1110], "radius": 45, "houses": 1},
	{"name": "Pass Viewpoint", "kind": "viewpoint", "pos": [860, -1560], "radius": 30, "houses": 0},
	{"name": "Lakeside Hamlet", "kind": "hamlet", "pos": [-1030, -40], "radius": 80, "houses": 7},
	{"name": "Festival Hub", "kind": "festival", "pos": [-760, 640], "radius": 90, "houses": 0},
]

const LANDMARKS := [
	{"name": "Saltwind Lighthouse", "kind": "lighthouse", "pos": [-1800, -1040]},
	{"name": "Old Crown Castle", "kind": "castle", "pos": [-300, -1410]},
	{"name": "Windmill Ridge", "kind": "windfarm", "pos": [1150, 1190]},
	{"name": "Mirror Lake", "kind": "lake", "pos": [-900, -350]},
]

## Teleport targets for the console / benchmark menu: name -> [x, z, heading_x, heading_z]
const TELEPORTS := {
	"festival": [-640, 600, 0.9, -0.45],
	"farmland": [-330, 400, 0.65, -0.75],
	"highlands": [470, -560, 0.6, -0.8],
	"pass": [960, -1110, 0.5, -0.85],
	"canyon": [1720, -250, -0.3, 0.95],
	"desert": [1505, 950, -0.3, 0.95],
	"coast": [-1470, 750, -0.1, -1.0],
	"lighthouse": [-1577, -910, -0.8, -0.5],
	"lake": [-950, -80, 1.0, 0.0],
	"highway": [-1150, 1120, 1.0, -0.2],
	"village": [-420, 680, 1.0, 0.0],
	"summit": [990, -1300, 0.6, -0.6],
	"rally": [-260, -900, 0.85, 0.5],
	"loop_start": [-640, 600, 0.9, -0.45],
}
