#!/bin/sh
# usage: tools/blender/traffic/run.sh <script.py under tools/blender/traffic> "<python globals dict items>"
# e.g.  tools/blender/traffic/run.sh van_delivery.py "'KEEP_SOLO': True"
cd "$(dirname "$0")/../../.."
P="$(pwd -W 2>/dev/null || pwd)/tools/blender/traffic/$1"
python tools/blender/mcp_call.py call execute_blender_code --timeout 900 --code "PATH=r'''$P'''
exec(compile(open(PATH, encoding='utf-8').read(), PATH, 'exec'), {'__name__': '__main__', $2})"
