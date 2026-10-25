import bpy
result = {'filepath': bpy.data.filepath, 'is_dirty': bpy.data.is_dirty, 'version': bpy.app.version_string, 'collections': [c.name for c in bpy.data.collections]}
print(result)
