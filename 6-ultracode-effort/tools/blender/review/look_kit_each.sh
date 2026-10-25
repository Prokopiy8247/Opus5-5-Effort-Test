#!/bin/sh
# usage: tools/blender/review/look_kit_each.sh <nature|roadside|buildings> Prop1 [Prop2 ...]   (review pass helper)
# One look() per prop (solo + 1.8 m ref via the kit's own look helper), PNGs -> qa_output/blender_look/rv_<Prop>.png
cd "$(dirname "$0")/../../.."
KIT="$1"; shift
export SIZE="${SIZE:-512}"
case "$KIT" in
  nature) H=tools/blender/props/look.sh ;;
  roadside) H=tools/blender/props/look_roadside.sh ;;
  buildings) H=tools/blender/props/look_buildings.sh ;;
esac
for n in "$@"; do
  echo "$n $(sh $H rv_$n $n)"
done
echo DONE
