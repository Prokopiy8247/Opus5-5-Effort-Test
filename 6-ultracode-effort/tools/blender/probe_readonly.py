import bpy, sys
print("FILEPATH=" + bpy.data.filepath)
print("IS_DIRTY=" + str(bpy.data.is_dirty))
print("BLENDER_VERSION=" + bpy.app.version_string)
print("OBJECTS=" + ",".join(o.name for o in bpy.data.objects))
print("COLLECTIONS=" + ",".join(c.name for c in bpy.data.collections))
print("ADDONS=" + ",".join(sorted(a.module for a in bpy.context.preferences.addons)))
print("PY=" + sys.version)
