"""Organise the Sunward Roads master .blend (idempotent).

Creates SUNWARD_GODOT/{Cars,Traffic,Props,Nature,Roadside,Settlements,Landmarks,Collision},
moves the default Cube/Light/Camera into a hidden `_Default_Unused` collection (never deleted)
and sets metric units at scale 1.0.

Run inside Blender (MCP execute_blender_code):
    exec(compile(open(PATH, encoding='utf-8').read(), PATH, 'exec'), {'__name__': '__main__'})
"""
import bpy

ROOT = "SUNWARD_GODOT"
CHILDREN = ["Cars", "Traffic", "Props", "Nature", "Roadside", "Settlements", "Landmarks", "Collision"]
DEFAULTS = ["Cube", "Light", "Camera"]


def ensure_collection(name, parent):
    col = bpy.data.collections.get(name)
    if col is None:
        col = bpy.data.collections.new(name)
    if col.name not in [c.name for c in parent.children]:
        parent.children.link(col)
    return col


def main():
    scene = bpy.context.scene
    root = ensure_collection(ROOT, scene.collection)
    for n in CHILDREN:
        ensure_collection(n, root)

    unused = ensure_collection("_Default_Unused", scene.collection)
    for name in DEFAULTS:
        ob = bpy.data.objects.get(name)
        if ob is None:
            continue
        for c in list(ob.users_collection):
            if c != unused:
                c.objects.unlink(ob)
        if ob.name not in unused.objects:
            unused.objects.link(ob)
    unused.hide_viewport = True
    unused.hide_render = True
    lc = bpy.context.view_layer.layer_collection.children.get("_Default_Unused")
    if lc is not None:
        lc.hide_viewport = True

    us = scene.unit_settings
    us.system = 'METRIC'
    us.scale_length = 1.0
    print("collections:", [c.name for c in root.children], "unused:", [o.name for o in unused.objects])


if __name__ == "__main__":
    main()
