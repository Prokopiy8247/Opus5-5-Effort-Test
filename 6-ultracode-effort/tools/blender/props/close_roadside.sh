#!/bin/sh
# usage: tools/blender/props/close_roadside.sh <png name> <Prop> "<x, y, z local>" <box size m|auto> [views json]
# Close-up look() at one roadside prop (solo, then unsolo). With a size: auto-framed on a face-less QA_Focus box of
# that size around the local point; with "auto": the prop alone, auto-framed.
cd "$(dirname "$0")/../../.."
OUT="$1"; NAME="$2"; AT="$3"; SIZE="$4"
VIEWS="${5:-[[0,1,0.08],[0.7,1,0.35],[-0.8,-1,0.3]]}"
sh tools/blender/props/run.sh roadside_kit.py "'STEP': 'solo', 'ONLY': ['$NAME']" > /dev/null
if [ "$SIZE" = "auto" ]; then
  TGT="\"$NAME\""
else
  sh tools/blender/props/run.sh roadside_kit.py "'STEP': 'focus', 'ONLY': ['$NAME'], 'AT': ($AT), 'SIZE': $SIZE" > /dev/null
  TGT="\"QA_Focus\""
fi
python tools/blender/mcp_call.py call look --args "{\"mode\":\"angles\",\"target\":[$TGT],\"views\":$VIEWS,\"shading\":\"material\",\"max_size\":640}" --image-out "qa_output/blender_look/$OUT.png" | tail -1
sh tools/blender/props/run.sh roadside_kit.py "'STEP': 'unsolo'" > /dev/null
