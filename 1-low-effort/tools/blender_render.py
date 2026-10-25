import bpy, os, math
from mathutils import Vector
P = os.path.dirname(bpy.data.filepath)
sc = bpy.context.scene
cam = bpy.data.objects["Camera"]
cam.data.lens = 35
sc.render.engine = "BLENDER_EEVEE"
sc.render.resolution_x, sc.render.resolution_y = 1600, 900
w = sc.world or bpy.data.worlds.new("W"); sc.world = w; w.use_nodes = True
w.node_tree.nodes["Background"].inputs[0].default_value = (0.6, 0.7, 0.85, 1)
w.node_tree.nodes["Background"].inputs[1].default_value = 1.0
sun = bpy.data.objects.get("Light"); sun.data.type = "SUN"; sun.data.energy = 3; sun.rotation_euler = (0.8, 0.2, 0.6)
def shot(target, dist, name, elev=0.35, az=-0.8):
    t = Vector(target)
    cam.location = t + Vector((math.cos(az) * dist, math.sin(az) * dist, dist * elev))
    d = t - cam.location
    cam.rotation_euler = d.to_track_quat("-Z", "Y").to_euler()
    sc.render.filepath = os.path.join(P, "screenshots", name)
    bpy.ops.render.render(write_still=True)
shot((0, 6, 0.6), 44, "bl_lineup.png", 0.45, -1.2)
shot((-24, 0, 0.7), 8, "bl_car01.png", 0.25, -0.6)
shot((11, 0, 0.6), 8, "bl_car06.png", 0.25, -0.6)
print("rendered")
shot((-10, 0, 0.7), 8, "bl_car03.png", 0.2, 0.7)
