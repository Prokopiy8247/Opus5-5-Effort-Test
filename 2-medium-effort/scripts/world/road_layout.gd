class_name RoadLayout
extends RefCounted
## Hand-authored road network for Verdant Ridge. Coordinates are metres, x east, z south (north = -z).
## Nodes are junctions; every road starts and ends at a node so the traffic graph stays connected.

const NODES: Dictionary = {
	"N1": Vector2(-1600, 1350), "N2": Vector2(-1650, 200), "N3": Vector2(-1550, -1200),
	"N4": Vector2(-200, -1550), "N5": Vector2(1500, -1350), "N6": Vector2(1650, -350),
	"N7": Vector2(1650, 250), "N8": Vector2(1550, 1300), "N9": Vector2(250, 1450),
	"N10": Vector2(-350, 1450), "N11": Vector2(120, -350), "N12": Vector2(120, 170),
	"N13": Vector2(250, 550), "N14": Vector2(-420, 520), "V": Vector2(-950, 120),
	"K": Vector2(-150, 0), "J": Vector2(-1100, -750),
	"END_LIGHT": Vector2(1750, 1540), "END_CASTLE": Vector2(100, -1780),
	"END_WIND": Vector2(850, 700), "END_PIER": Vector2(-300, 1610),
	"END_VIEW": Vector2(520, -1150), "END_PINE": Vector2(-700, -1180),
}

## Road classes: half lane width, lanes per direction, shoulder, speed limit km/h, surface, max grade
const CLASSES: Dictionary = {
	"highway": {"lane": 3.6, "shoulder": 2.2, "speed": 110.0, "surface": "asphalt", "grade": 0.07, "smooth": 18, "tunnel": 30.0},
	"scenic": {"lane": 3.3, "shoulder": 1.0, "speed": 90.0, "surface": "asphalt", "grade": 0.09, "smooth": 12, "tunnel": 30.0},
	"mountain": {"lane": 3.1, "shoulder": 0.6, "speed": 60.0, "surface": "asphalt", "grade": 0.11, "smooth": 7, "tunnel": 15.0},
	"concrete": {"lane": 3.3, "shoulder": 1.2, "speed": 80.0, "surface": "concrete", "grade": 0.09, "smooth": 12, "tunnel": 30.0},
	"dirt": {"lane": 2.8, "shoulder": 0.4, "speed": 50.0, "surface": "dirt", "grade": 0.13, "smooth": 6, "tunnel": 30.0},
	"gravel": {"lane": 2.9, "shoulder": 0.4, "speed": 60.0, "surface": "gravel", "grade": 0.13, "smooth": 6, "tunnel": 30.0},
}

## name, class, from, to, interior control points, loop flag
const ROADS: Array = [
	# ---- Grand scenic loop (in order) ----
	["West Coast Road", "scenic", "N1", "N2", [Vector2(-1720, 1180), Vector2(-1600, 1000), Vector2(-1740, 820), Vector2(-1610, 640), Vector2(-1730, 450), Vector2(-1660, 330)], true],
	["Cliffside Climb", "scenic", "N2", "N3", [Vector2(-1560, 0), Vector2(-1680, -200), Vector2(-1600, -420), Vector2(-1700, -640), Vector2(-1620, -860), Vector2(-1680, -1040)], true],
	["Highland Pass", "mountain", "N3", "N4", [Vector2(-1380, -1250), Vector2(-1200, -1180), Vector2(-1050, -1250), Vector2(-1030, -1350), Vector2(-1150, -1390), Vector2(-1260, -1450), Vector2(-1220, -1550), Vector2(-1020, -1530), Vector2(-800, -1600), Vector2(-650, -1500), Vector2(-570, -1390), Vector2(-430, -1350), Vector2(-310, -1440)], true],
	["Summit Descent", "mountain", "N4", "N5", [Vector2(0, -1480), Vector2(200, -1600), Vector2(420, -1480), Vector2(600, -1400), Vector2(800, -1300), Vector2(950, -1450), Vector2(1150, -1350), Vector2(1330, -1480)], true],
	["Mesa Run", "scenic", "N5", "N6", [Vector2(1680, -1250), Vector2(1580, -1100), Vector2(1450, -950), Vector2(1600, -820), Vector2(1740, -700), Vector2(1640, -540)], true],
	["Canyon Road", "scenic", "N6", "N11", [Vector2(1450, -180), Vector2(1250, -420), Vector2(1050, -260), Vector2(850, -420), Vector2(650, -290), Vector2(400, -380)], true],
	["Border Lane", "scenic", "N11", "N12", [Vector2(50, -220), Vector2(170, -80), Vector2(60, 60)], true],
	["Sunset Straight", "scenic", "N12", "N7", [Vector2(400, 120), Vector2(650, 60), Vector2(850, 220), Vector2(1050, 60), Vector2(1250, 230), Vector2(1450, 100)], true],
	["Desert Expressway", "highway", "N7", "N8", [Vector2(1720, 500), Vector2(1680, 800), Vector2(1740, 1050)], true],
	["Seacliff Drive", "scenic", "N8", "N9", [Vector2(1350, 1440), Vector2(1200, 1260), Vector2(1000, 1210), Vector2(850, 1350), Vector2(700, 1460), Vector2(500, 1500)], true],
	["Orchard Climb", "scenic", "N9", "N13", [Vector2(330, 1320), Vector2(220, 1160), Vector2(370, 990), Vector2(220, 830), Vector2(320, 690)], true],
	["River Crossing", "scenic", "N13", "N14", [Vector2(100, 620), Vector2(-100, 520), Vector2(-280, 590)], true],
	["Meadow Road", "scenic", "N14", "N10", [Vector2(-560, 700), Vector2(-440, 880), Vector2(-600, 1080), Vector2(-460, 1280)], true],
	["Harbour Coast Road", "scenic", "N10", "N1", [Vector2(-550, 1540), Vector2(-780, 1420), Vector2(-1000, 1550), Vector2(-1200, 1410), Vector2(-1400, 1540), Vector2(-1520, 1450)], true],
	# ---- Network roads ----
	["Estuary Bridge", "concrete", "N9", "N10", [Vector2(80, 1530), Vector2(-150, 1530)], false],
	["Valley Highway", "highway", "N2", "V", [Vector2(-1400, 170), Vector2(-1150, 60)], false],
	["Valley Highway East", "highway", "V", "K", [Vector2(-700, 30), Vector2(-450, 90)], false],
	["Central Highway", "highway", "K", "N12", [Vector2(-20, 90)], false],
	["North Switchbacks", "mountain", "K", "N4", [Vector2(-100, -250), Vector2(-200, -500), Vector2(-120, -750), Vector2(-260, -950), Vector2(-150, -1100), Vector2(-300, -1250), Vector2(-180, -1400)], false],
	["Mill Road", "scenic", "K", "N14", [Vector2(-250, 200), Vector2(-330, 360)], false],
	["Quarry Road", "scenic", "N11", "K", [Vector2(0, -200)], false],
	["Farm Track", "dirt", "V", "N1", [Vector2(-1050, 400), Vector2(-1000, 650), Vector2(-1200, 900), Vector2(-1300, 1150)], false],
	["Badlands Trail", "gravel", "N5", "N11", [Vector2(1250, -1150), Vector2(1100, -950), Vector2(900, -850), Vector2(750, -650)], false],
	["Dune Track", "dirt", "N7", "N9", [Vector2(1350, 500), Vector2(1150, 750), Vector2(900, 900), Vector2(700, 1150), Vector2(450, 1250)], false],
	["Lighthouse Lane", "scenic", "N8", "END_LIGHT", [Vector2(1650, 1420)], false],
	["Castle Climb", "gravel", "N4", "END_CASTLE", [Vector2(-100, -1680)], false],
	["Windfarm Track", "gravel", "N13", "END_WIND", [Vector2(600, 600)], false],
	["Harbour Pier", "concrete", "N10", "END_PIER", [Vector2(-330, 1530)], false],
	["Pine Forest Track", "dirt", "N3", "J", [Vector2(-1300, -950)], false],
	["Lakeside Lane", "dirt", "J", "K", [Vector2(-900, -550), Vector2(-700, -260), Vector2(-400, -150)], false],
	["Hedgerow Lane", "dirt", "V", "J", [Vector2(-1100, -100), Vector2(-1250, -350), Vector2(-1150, -550)], false],
	["Vineyard Lane", "scenic", "N14", "V", [Vector2(-600, 450), Vector2(-800, 330)], false],
	["Foothill Road", "scenic", "N11", "END_VIEW", [Vector2(300, -500), Vector2(550, -650), Vector2(400, -900), Vector2(560, -1050)], false],
	["Ridgeback Road", "gravel", "N2", "J", [Vector2(-1450, -50), Vector2(-1350, -400)], false],
	["Eastern Rim Trail", "gravel", "N6", "N7", [Vector2(1830, -150), Vector2(1850, 100)], false],
	["Station Link", "scenic", "N12", "N13", [Vector2(200, 330)], false],
	["Pine Ridge Road", "mountain", "J", "END_PINE", [Vector2(-950, -950), Vector2(-780, -1050)], false],
	["Canyon Rim Road", "scenic", "N11", "N6", [Vector2(650, -600), Vector2(900, -680), Vector2(1150, -600), Vector2(1400, -560)], false],
]

## Named teleport / point-of-interest locations (x, z)
const POIS: Dictionary = {
	"farmland": Vector2(-950, 120), "village": Vector2(-950, 120), "mountains": Vector2(-600, -1560),
	"summit": Vector2(-200, -1550), "desert": Vector2(1450, -250), "canyon": Vector2(1050, -300),
	"coast": Vector2(950, 1470), "harbour": Vector2(-350, 1450), "lighthouse": Vector2(1700, 1480),
	"castle": Vector2(80, -1760), "lake": Vector2(-700, -260), "windfarm": Vector2(800, 680),
	"expressway": Vector2(1650, 250), "highway": Vector2(-1400, 170), "bridge": Vector2(80, 1530),
	"gasstation": Vector2(200, 160),
}
