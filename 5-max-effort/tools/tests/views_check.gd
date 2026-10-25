extends Node
## QA script: free-camera screenshots of given world views (pos -> target), e.g. to inspect terrain
## carving around roads. Views are passed as --views=x,y,z>x,y,z;x,y,z>x,y,z (or use the default set).
## Run: Godot_console.exe --path . -- --fresh --qa=script --script_path=res://tools/tests/views_check.gd --out=qa_out/views

const DEFAULT := [
	[Vector3(-1150, 520, -1150), Vector3(-850, 200, -1500)],
	[Vector3(-500, 420, -1150), Vector3(-850, 180, -1550)],
	[Vector3(-1300, 360, -1750), Vector3(-900, 180, -1550)],
	[Vector3(-760, 230, -1330), Vector3(-1000, 180, -1640)],
]


func run(qa: Node) -> void:
	var views: Array = DEFAULT
	var arg := String(Game.qa_args.get("views", ""))
	if arg != "":
		views = []
		for v in arg.split(";"):
			var pr := v.split(">")
			var a := pr[0].split_floats(",")
			var b := pr[1].split_floats(",")
			views.append([Vector3(a[0], a[1], a[2]), Vector3(b[0], b[1], b[2])])
	var env := Game.environment as EnvironmentController
	env.set_time(float(Game.qa_args.get("time", "13.0")))
	env.time_frozen = true
	var rig := Game.camera_rig as CameraRig
	for k in views.size():
		var v: Array = views[k]
		var target: Vector3 = v[1]
		Game.world.call("prepare_area", target)
		Game.player_car.reset_to(Game.world.call("nearest_road_transform", target, Vector3.FORWARD))
		rig.frozen = true
		rig.camera.global_transform = Transform3D(Basis.looking_at(target - (v[0] as Vector3), Vector3.UP), v[0])
		for f in 90:
			await get_tree().process_frame
		await qa.call("_shot", "view_%02d.png" % k)
	rig.frozen = false
