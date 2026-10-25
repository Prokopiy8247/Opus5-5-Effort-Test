"""Pretty-print the nature_kit.py report lines (stdin) one prop per line. Local helper, not run inside Blender."""
import ast
import sys

for line in sys.stdin:
    line = line.replace('Code executed successfully: ', '')
    if line.startswith('{'):
        d = ast.literal_eval(line.strip())
        print(d['name'], 'h', d['height'], 'below', d['below'], 'xy', d['size_x'], d['size_y'], 'tris', d['tris'], '/',
              d['budget'], 'isl', d['islands'], 'open', d['open_islands'], 'inv', d['inverted'], 'float',
              d['floating'], d['floating_at'], 'deg', d['degenerate'])
    elif line.strip():
        print(line.strip()[:300])
