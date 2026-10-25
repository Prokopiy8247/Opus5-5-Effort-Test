#!/bin/sh
# usage: tools/blender/props/look.sh <png name> <Prop1> [Prop2 ...]   (solo the props + their 1.8 m refs, look, unsolo)
cd "$(dirname "$0")/../../.."
OUT="$1"; shift
LIST=""; TGT=""
for n in "$@"; do LIST="$LIST'$n',"; TGT="$TGT\"$n\",\"QA_Ref1p8_$n\","; done
VIEWS="${VIEWS:-[\"front\",\"right\",\"three_quarter\"]}"
sh tools/blender/props/run.sh nature_kit.py "'STEP': 'solo', 'ONLY': [$LIST]" > /dev/null
python tools/blender/mcp_call.py call look --args "{\"mode\":\"angles\",\"target\":[${TGT%,}],\"views\":$VIEWS,\"shading\":\"material\",\"max_size\":${SIZE:-640}}" --image-out "qa_output/blender_look/$OUT.png" | tail -1
sh tools/blender/props/run.sh nature_kit.py "'STEP': 'unsolo'" > /dev/null
