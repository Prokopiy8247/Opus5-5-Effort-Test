#!/bin/sh
# usage: tools/blender/props/look_roadside.sh <png name> <Prop1> [Prop2 ...]
# Solo the roadside props + their 1.8 m refs (ref_on first), look() at them, unsolo.
cd "$(dirname "$0")/../../.."
OUT="$1"; shift
LIST=""; TGT=""
for n in "$@"; do LIST="$LIST'$n',"; TGT="$TGT\"$n\",\"QA_Ref1p8_$n\","; done
VIEWS="${VIEWS:-[[0,1,0.12],[1,0.25,0.25],[0.55,1,0.4],[-0.6,-1,0.35]]}"
sh tools/blender/props/run.sh roadside_kit.py "'STEP': 'solo', 'ONLY': [$LIST]" > /dev/null
python tools/blender/mcp_call.py call look --args "{\"mode\":\"angles\",\"target\":[${TGT%,}],\"views\":$VIEWS,\"shading\":\"material\",\"max_size\":${SIZE:-640}}" --image-out "qa_output/blender_look/$OUT.png" | tail -1
sh tools/blender/props/run.sh roadside_kit.py "'STEP': 'unsolo'" > /dev/null
