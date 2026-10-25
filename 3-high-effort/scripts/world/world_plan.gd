class_name WorldPlan
extends RefCounted
## Hand-authored layout of the Velora map: regions, coastline, river, roads, places.
## Coordinates are metres; x = east, z = south, map spans [-2048, 2048].

const SEED := 51122
const HALF := 2048.0

enum Region { VALLEY, HIGHLANDS, MESA, COAST }
const REGION_NAMES := ["Meadowmere Valley", "Granite Crown Highlands", "Ochre Mesa", "Saltcliff Coast"]

# road classes: width of the paved/driven surface (m), lanes, speed limit (km/h), max grade
const CLASS_INFO := {
	"highway": {"width": 15.0, "lanes": 4, "speed": 110.0, "grade": 0.065, "surface": 0, "shoulder": 2.0, "markings": true},
	"regional": {"width": 8.0, "lanes": 2, "speed": 90.0, "grade": 0.09, "surface": 0, "shoulder": 1.2, "markings": true},
	"mountain": {"width": 7.0, "lanes": 2, "speed": 70.0, "grade": 0.105, "surface": 0, "shoulder": 0.8, "markings": true},
	"lane": {"width": 5.5, "lanes": 2, "speed": 60.0, "grade": 0.11, "surface": 0, "shoulder": 0.6, "markings": false},
	"dirt": {"width": 5.0, "lanes": 2, "speed": 50.0, "grade": 0.14, "surface": 2, "shoulder": 0.5, "markings": false},
	"gravel": {"width": 6.0, "lanes": 2, "speed": 60.0, "grade": 0.12, "surface": 3, "shoulder": 0.6, "markings": false},
	"sand": {"width": 6.0, "lanes": 2, "speed": 50.0, "grade": 0.14, "surface": 5, "shoulder": 0.5, "markings": false},
}

## Roads are processed in order; later roads may start/end on earlier ones (T-junctions).
const ROADS := [
	{
		"id": "festival_loop", "name": "Festival Loop", "class": "regional", "closed": true, "grade": 0.11, "wiggle": [20.0, 230.0],
		"pts": [
			[300, 1150], [480, 1330], [560, 1540], [800, 1740], [1120, 1700], [1300, 1470], [1310, 1180], [1250, 900],
			[1310, 640], [1370, 400], [1310, 160], [1270, -60], [1265, -260], [1290, -480], [1260, -720], [1330, -960],
			[1060, -880], [840, -1060], [930, -1330], [1120, -1450], [900, -1640], [640, -1720], [420, -1580],
			[330, -1300], [380, -1000], [300, -640], [60, -400], [-170, -620], [-220, -1000], [-300, -1280],
			[-480, -1420], [-660, -1580], [-860, -1720], [-1080, -1800], [-1320, -1830], [-1560, -1860],
			[-1780, -1740], [-1840, -1500], [-1760, -1370], [-1560, -1335],
			[-1500, -1330], [-1449, -1321], [-1440, -1300], [-1449, -1279], [-1500, -1270],
			[-1640, -1250], [-1670, -1250], [-1721, -1241], [-1730, -1220], [-1721, -1199], [-1670, -1190],
			[-1540, -1160], [-1360, -1060], [-1260, -870], [-1400, -700], [-1600, -760], [-1760, -820], [-1800, -640], [-1700, -420],
			[-1800, -180], [-1760, 100], [-1850, 380], [-1760, 660], [-1450, 540], [-1180, 600], [-1230, 800],
			[-1450, 920], [-1620, 1120], [-1760, 1380], [-1600, 1640], [-1320, 1780], [-1120, 1560], [-880, 1440],
			[-800, 1220], [-600, 1150], [-480, 1350], [-640, 1560], [-520, 1760], [-240, 1560], [-20, 1380], [120, 1220],
		],
	},
	{
		"id": "valley_highway", "name": "Valley Highway", "class": "highway",
		"pts": [[-1600, 1640], [-1350, 1250], [-1050, 850], [-700, 560], [-300, 300], [100, 60], [480, -200], [820, -480], [1080, -640], [1260, -720]],
		"start_on": "festival_loop", "end_on": "festival_loop",
	},
	{
		"id": "river_road", "name": "River Road", "class": "regional",
		"pts": [[-300, 300], [-100, 440], [150, 500], [420, 540], [700, 580], [960, 660], [1120, 760], [1250, 900]],
		"start_on": "valley_highway", "end_on": "festival_loop",
	},
	{
		"id": "pinewood_gravel", "name": "Pinewood Gravel", "class": "gravel",
		"pts": [[-300, -1280], [-400, -1060], [-520, -860], [-760, -660], [-1000, -520], [-1300, -470], [-1700, -420]],
		"start_on": "festival_loop", "end_on": "festival_loop",
	},
	{
		"id": "ridge_lane", "name": "Ridge Lane", "class": "lane",
		"pts": [[100, 60], [90, -180], [60, -400]],
		"start_on": "valley_highway", "end_on": "festival_loop",
	},
	{
		"id": "windmill_track", "name": "Windmill Track", "class": "gravel",
		"pts": [[640, -1720], [690, -1400], [620, -1020], [560, -620], [480, -200]],
		"start_on": "festival_loop", "end_on": "valley_highway",
	},
	{
		"id": "turbine_link", "name": "Turbine Link", "class": "dirt",
		"pts": [[620, -1020], [840, -1060]],
		"start_on": "windmill_track", "end_on": "festival_loop",
	},
	{
		"id": "lighthouse_road", "name": "Lighthouse Road", "class": "lane",
		"pts": [[1120, -1450], [1300, -1400], [1420, -1390]],
		"start_on": "festival_loop",
	},
	{
		"id": "clifftop_track", "name": "Clifftop Track", "class": "gravel",
		"pts": [[1420, -1390], [1420, -1640], [1180, -1820], [900, -1640]],
		"start_on": "lighthouse_road", "end_on": "festival_loop",
	},
	{
		"id": "harbour_lane", "name": "Harbour Lane", "class": "lane",
		"pts": [[1270, -60], [1180, -110], [1080, -150], [990, -150]],
		"start_on": "festival_loop",
	},
	{
		"id": "mesa_run", "name": "Mesa Run", "class": "regional",
		"pts": [[-1760, 100], [-1450, 250], [-1150, 330], [-900, 480], [-700, 560]],
		"start_on": "festival_loop", "end_on": "valley_highway",
	},
	{
		"id": "ochre_cutoff", "name": "Ochre Cutoff", "class": "gravel",
		"pts": [[-1150, 330], [-1230, 40], [-1440, -230], [-1700, -420]],
		"start_on": "mesa_run", "end_on": "festival_loop",
	},
	{
		"id": "dune_track", "name": "Dune Track", "class": "sand",
		"pts": [[-1450, 920], [-1300, 1080], [-1350, 1250]],
		"start_on": "festival_loop", "end_on": "valley_highway",
	},
	{
		"id": "south_lane", "name": "Orchard Lane", "class": "lane",
		"pts": [[480, 1330], [700, 1280], [900, 1230], [1100, 1060], [1250, 900]],
		"start_on": "festival_loop", "end_on": "festival_loop",
	},
	{
		"id": "hollow_track", "name": "Hollow Oak Track", "class": "dirt",
		"pts": [[900, 1230], [860, 1480], [1120, 1700]],
		"start_on": "south_lane", "end_on": "festival_loop",
	},
	{
		"id": "mill_lane", "name": "Mill Lane", "class": "lane",
		"pts": [[420, 540], [480, 820], [300, 1150]],
		"start_on": "river_road", "end_on": "festival_loop",
	},
	{
		"id": "redwell_lane", "name": "Redwell Lane", "class": "lane",
		"pts": [[-300, 300], [-220, 700], [-160, 1060], [-20, 1380]],
		"start_on": "valley_highway", "end_on": "festival_loop",
	},
	{
		"id": "ochre_speedway", "name": "Ochre Speedway", "class": "regional",
		"pts": [[-1230, 40], [-950, 120], [-700, 250], [-500, 430]],
		"start_on": "ochre_cutoff", "end_on": "valley_highway",
	},
	{
		"id": "castle_climb", "name": "Ravenhold Climb", "class": "gravel",
		"pts": [[-760, -660], [-860, -900], [-920, -1200], [-860, -1720]],
		"start_on": "pinewood_gravel", "end_on": "festival_loop",
	},
	{
		"id": "brightmoor_ridge", "name": "Brightmoor Ridge", "class": "dirt",
		"pts": [[690, -1400], [540, -1500], [420, -1580]],
		"start_on": "windmill_track", "end_on": "festival_loop",
	},
	{
		"id": "back_road", "name": "Hollow Back Road", "class": "lane",
		"pts": [[700, 580], [780, 880], [900, 1230]],
		"start_on": "river_road", "end_on": "south_lane",
	},
	{
		"id": "meadow_lane", "name": "Meadow Lane", "class": "lane",
		"pts": [[150, 500], [180, 300], [100, 60]],
		"start_on": "river_road", "end_on": "valley_highway",
	},
]

## Places: villages, POIs, festival site. type drives what the dresser builds.
const PLACES := [
	{"id": "festival", "name": "Velora Festival", "type": "festival", "pos": [400, 1080], "r": 60.0},
	{"id": "meadowmere", "name": "Meadowmere", "type": "village", "pos": [300, 610], "r": 110.0},
	{"id": "saltcliff", "name": "Saltcliff Harbour", "type": "harbour", "pos": [1000, -150], "r": 70.0},
	{"id": "pinecross", "name": "Pinecross", "type": "village", "pos": [-260, -1200], "r": 90.0},
	{"id": "redwell", "name": "Redwell", "type": "hamlet", "pos": [-280, 760], "r": 70.0},
	{"id": "gas_mesa", "name": "Mesa Fuel", "type": "gas", "pos": [-1300, 230], "r": 40.0},
	{"id": "gas_valley", "name": "Valley Services", "type": "gas", "pos": [130, 0], "r": 40.0},
	{"id": "diner", "name": "Coastline Diner", "type": "diner", "pos": [1270, 450], "r": 35.0},
	{"id": "farm_east", "name": "Hollow Oak Farm", "type": "farm", "pos": [880, 1500], "r": 70.0},
	{"id": "farm_west", "name": "Brookfield Farm", "type": "farm", "pos": [-480, 640], "r": 60.0},
	{"id": "lighthouse", "name": "Saltcliff Light", "type": "lighthouse", "pos": [1440, -1420], "r": 30.0},
	{"id": "castle", "name": "Ravenhold Ruins", "type": "castle", "pos": [-960, -1010], "r": 45.0},
	{"id": "windfarm", "name": "Brightmoor Wind Farm", "type": "windfarm", "pos": [720, -1100], "r": 300.0},
	{"id": "summit", "name": "Crown Summit Viewpoint", "type": "viewpoint", "pos": [-1680, -1800], "r": 30.0},
]

const RIVER := [[-900, -700], [-640, -420], [-380, -180], [-150, 60], [80, 260], [260, 390], [520, 430], [800, 470], [1060, 560], [1300, 600], [1600, 640]]
