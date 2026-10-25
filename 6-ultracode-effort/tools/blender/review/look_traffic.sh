#!/bin/sh
# usage: tools/blender/review/look_traffic.sh <car_id> [ref_x]   (review pass helper)
# Solo Traffic_<car_id> (other Cars/Traffic collections excluded), add the temporary 1.8 m reference figure beside it,
# look() at it (angles, material, SIZE px, VIEWS env overrides), then restore visibility and remove the figure.
cd "$(dirname "$0")/../../.."
CID="$1"; RX="${2:-1.6}"
VIEWS="${VIEWS:-[\"front\",\"right\",\"three_quarter\",[-0.7,-0.8,0.35]]}"
sh tools/blender/traffic/run.sh traffic_common.py "'STEP': 'solo:$CID'" > /dev/null
sh tools/blender/traffic/run.sh traffic_common.py "'STEP': 'ref:$CID', 'REF_LOC': ($RX, 0.0, 0.0)" > /dev/null
python tools/blender/mcp_call.py call look --args "{\"mode\":\"angles\",\"target\":[\"$CID\",\"QA_Ref_1.8m\"],\"views\":$VIEWS,\"shading\":\"material\",\"max_size\":${SIZE:-512}}" --image-out "qa_output/blender_look/review_$CID.png" | tail -1
sh tools/blender/traffic/run.sh traffic_common.py "'STEP': 'restore'" > /dev/null
