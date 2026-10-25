#!/bin/sh
# usage: tools/blender/props/run.sh <script.py under tools/blender/props> "<python globals dict items>"
# e.g.  tools/blender/props/run.sh nature_kit.py "'STEP': 'build', 'ONLY': ['Tree_Oak_A']"
cd "$(dirname "$0")/../../.."
P="$(pwd -W 2>/dev/null || pwd)/tools/blender/props/$1"
python tools/blender/mcp_call.py call execute_blender_code --timeout 900 --code "PATH=r'''$P'''
exec(compile(open(PATH, encoding='utf-8').read(), PATH, 'exec'), {'__name__': '__main__', $2})"
