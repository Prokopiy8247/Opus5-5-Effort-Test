"""Entry point executed through the MCP: (re)load the builder modules and build assets.

Usage from execute_blender_code:
    exec(open(r"<project>/tools/blender/run_build.py").read()); build(["SolanoCoupe"], export=True)
"""
import importlib
import os
import sys

_TOOLS = os.path.join(os.path.dirname(os.path.abspath(bpy.data.filepath)), "tools", "blender")  # noqa: F821
if _TOOLS not in sys.path:
    sys.path.insert(0, _TOOLS)

import vgk_common  # noqa: E402
import car_builder  # noqa: E402
import car_specs  # noqa: E402

for _m in (vgk_common, car_builder, car_specs):
    importlib.reload(_m)


def build(ids, export=False, category="Cars", specs=None, save=True):
    vgk_common.guard()
    specs = specs or car_specs.CARS
    out = {}
    for cid in ids:
        col, meta = car_builder.build_car(specs[cid], category=category)
        if export:
            path = os.path.join(vgk_common.PROJECT_DIR, "assets", "imported", category.lower(), cid + ".glb")
            car_builder.export_car(cid, path)
            meta["glb"] = path
        out[cid] = meta
    if save:
        vgk_common.save_master()
    return out
