extends SubViewportContainer

## A real, lit relay outpost behind the headquarters controls. Geometry is
## reusable scene content; no borrowed reference-game artwork is packaged.
var world: Node3D

func _ready() -> void:
	stretch = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1280,720)
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	viewport.msaa_3d = Viewport.MSAA_2X
	add_child(viewport)
	world = Node3D.new()
	viewport.add_child(world)
	var environment := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("102333")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("aac4d5")
	env.ambient_light_energy = 0.75
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.environment = env
	world.add_child(environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48,-25,0)
	sun.light_color = Color("ffe2a6")
	sun.light_energy = 2.1
	sun.shadow_enabled = true
	world.add_child(sun)
	var camera := Camera3D.new()
	world.add_child(camera)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 30
	camera.position = Vector3(22,24,30)
	camera.look_at(Vector3(2,0,0))
	camera.current = true
	var steel := material(Color("35505e"))
	var dark := material(Color("142c3d"))
	var white := material(Color("b9cdd3"))
	var gold := material(Color("c09959"))
	var glow := material(Color("57cfd0"),true)
	# Broad stepped terraces, roads and a connected raised central plaza.
	cylinder(Vector3(0,-1.3,0),17,15,1.6,8,dark)
	cylinder(Vector3(0,-.35,0),16,17,.4,8,steel)
	cylinder(Vector3(0,-.08,0),15.8,15.8,.18,8,material(Color("52636a")))
	for x in [-8.0,0.0,8.0]:
		box(Vector3(x,.045,0),Vector3(2.7,.06,25),dark)
		for z in range(-11,12,2): box(Vector3(x,.09,z),Vector3(.10,.035,.70),gold)
	for z in [-6.0,4.0]: box(Vector3(0,.05,z),Vector3(28,.06,2.2),dark)
	for x in [-11.0,-5.0,3.0,10.0]:
		for z in [-10.0,9.0]:
			cylinder(Vector3(x,.3,z),1.7,1.9,.5,6,white)
			cylinder(Vector3(x,.58,z),1.55,1.55,.08,6,material(Color("355b48")))
			for offset in [-.8,0.0,.8]:
				cylinder(Vector3(x+offset,1.1,z),.1,.13,1.1,6,dark)
				cylinder(Vector3(x+offset,1.9,z),.2,.75,1.4,6,material(Color("427567")))
	# Command tower: hexagonal structural layers and luminous observation deck.
	cylinder(Vector3(0,.3,0),3.3,3.7,.6,6,white)
	cylinder(Vector3(0,.68,0),3.05,3.3,.15,6,gold)
	cylinder(Vector3(0,2.0,0),2.25,2.65,2.65,6,steel)
	cylinder(Vector3(0,3.3,0),2.25,2.25,.18,6,gold)
	cylinder(Vector3(0,3.95,0),1.9,2.0,1.15,6,glow)
	cylinder(Vector3(0,4.6,0),2.35,2.35,.28,6,white)
	cylinder(Vector3(0,5.35,0),.25,1.6,1.2,6,dark)
	cylinder(Vector3(0,6.3,0),.10,.18,1.5,8,gold)
	cylinder(Vector3(0,6.95,0),.17,.17,.45,8,glow)
	for angle in range(0,360,60):
		var a := deg_to_rad(float(angle))
		var pos := Vector3(sin(a)*2.25,2.3,cos(a)*2.25)
		box(pos,Vector3(.18,3.7,.18),gold)
	# Hangars, archive and supply bays flank the operations spine.
	for spec in [[-7,-5,3.7,3.1,3.2],[6,-5,4.3,3.2,2.6],[-7,4,4.6,2.5,2.1],[5,5,3.8,3.6,3.0]]:
		var x := float(spec[0])
		var z := float(spec[1])
		var w := float(spec[2])
		var d := float(spec[3])
		var h := float(spec[4])
		box(Vector3(x,.25,z),Vector3(w+1,.5,d+1),white)
		box(Vector3(x,h*.5+.5,z),Vector3(w,h,d),steel)
		box(Vector3(x,h+.6,z),Vector3(w+.4,.24,d+.4),gold)
		box(Vector3(x,h+.86,z),Vector3(w*.85,.35,d*.88),dark)
		for i in range(4):
			box(Vector3(x-w*.34+i*w*.23,h*.7+.5,z+d*.5+.02),Vector3(w*.12,.65,.05),glow)
		box(Vector3(x,.98,z+d*.5+.08),Vector3(w*.38,1.2,.15),dark)
		box(Vector3(x,h*.5+.5,z-d*.5),Vector3(.16,h,.16),gold)
	# Signal gate and antenna machinery.
	for x in [-2.0,2.0]:
		box(Vector3(x,1.8,-9),Vector3(.65,3.6,.8),white)
		box(Vector3(x,1.8,-8.56),Vector3(.22,2.6,.08),glow)
	box(Vector3(0,3.8,-9),Vector3(4.8,.65,.8),gold)
	var ring := TorusMesh.new()
	ring.inner_radius = 1.1
	ring.outer_radius = 1.3
	var signal_ring := mesh_node(ring,Vector3(0,2.25,-9),glow)
	signal_ring.rotation_degrees.x = 90
	for i in range(7):
		box(Vector3(-11+(i%3)*1.05,.53,2+floori(i/3.0)*1.25),Vector3(.9,.95,1.05),gold if i%2 else white)
	# Evenly spaced lamps and parapets define the outpost's inhabited scale.
	for x in [-12.0,-4.0,4.0,12.0]:
		for z in [-7.0,6.0]:
			cylinder(Vector3(x,1.0,z),.06,.10,2,8,dark)
			box(Vector3(x,2.1,z),Vector3(.4,.38,.4),glow)
	for z in [-12.0,12.0]: box(Vector3(0,.55,z),Vector3(18,.7,.3),white)
	# Re-render after layout settles, then keep this static view off the frame loop.
	resized.connect(func(): viewport.render_target_update_mode = SubViewport.UPDATE_ONCE)
	await get_tree().process_frame
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE

func material(color: Color, emissive := false) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = .6
	if emissive:
		mat.emission_enabled = true
		mat.emission = color
		mat.emission_energy_multiplier = 1.25
	return mat

func mesh_node(mesh: Mesh, position_value: Vector3, mat: Material) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = mat
	instance.position = position_value
	world.add_child(instance)
	return instance

func box(position_value: Vector3, dimensions: Vector3, mat: Material) -> void:
	var mesh := BoxMesh.new()
	mesh.size = dimensions
	mesh_node(mesh,position_value,mat)

func cylinder(position_value: Vector3, top: float, bottom: float, height: float, sides: int, mat: Material) -> void:
	var mesh := CylinderMesh.new()
	mesh.top_radius = top
	mesh.bottom_radius = bottom
	mesh.height = height
	mesh.radial_segments = sides
	mesh_node(mesh,position_value,mat)
