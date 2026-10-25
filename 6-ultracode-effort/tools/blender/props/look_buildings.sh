#!/bin/sh
# usage: tools/blender/props/look_buildings.sh <png name> <Prop1> [Prop2 ...]
# Solo the buildings-kit props (+ their 1.8 m refs; other kits, Cars and Traffic hidden), look() at them, unsolo.
# VIEWS env var overrides the view directions (target -> eye). Front of the props is +Y.
cd "$(dirname "$0")/../../.."
OUT="$1"; shift
LIST=""; TGT=""
for n in "$@"; do LIST="$LIST'$n',"; TGT="$TGT\"$n\",\"QA_Ref1p8_$n\","; done
VIEWS="${VIEWS:-[[0.15,1,0.25],[1,0.1,0.2],[0.7,0.8,0.5],[-0.6,-0.9,0.35]]}"
sh tools/blender/props/run.sh buildings_kit.py "'STEP': 'solo', 'ONLY': [$LIST]" > /dev/null
python tools/blender/mcp_call.py call look --args "{\"mode\":\"angles\",\"target\":[${TGT%,}],\"views\":$VIEWS,\"shading\":\"material\",\"max_size\":${SIZE:-640}}" --image-out "qa_output/blender_look/$OUT.png" | tail -1
sh tools/blender/props/run.sh buildings_kit.py "'STEP': 'unsolo'" > /dev/null
