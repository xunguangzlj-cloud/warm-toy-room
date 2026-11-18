extends RefCounted

const WOOD = "#81583c"
const HONEY = "#b38154"
const DARK = "#533b32"
const CREAM = "#f3deba"
const GOLD = "#d8ac57"
const GREEN = "#427066"
const RUST = "#b95d43"
var mats := {}
var library
var blade_mesh: ArrayMesh
var reference_door
var living_petals: Node3D
var clock_pivot: Node3D
var minute_hand: Node3D
var wind_key: Node3D
var water: Node3D
var flowers: Node3D
var valve: Node3D
var channel: Node3D
var chimes: Node3D

func group(parent: Node3D, pos: Vector3) -> Node3D:
	var n := Node3D.new()
	parent.add_child(n)
	n.position = pos
	return n

func material(color: String, finish: String) -> StandardMaterial3D:
	var id := color + finish
	if mats.has(id):
		return mats[id]
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(color)
	m.roughness = 0.86
	var family := ""
	var tiles := 1.0
	if finish == "wood":
		family = "v16/furniture_walnut" if color in [WOOD,HONEY,DARK,"#ac7954","#99765a"] else "v18/painted_wood"
		tiles = 0.82
	elif finish == "cloth":
		family = "v11/cotton_twill"
		tiles = 1.9
	elif finish == "paper":
		family = "v18/cotton_paper"
		tiles = 2.3
	elif finish == "soil":
		family = "v11/mineral_wall"
		tiles = 2.2
	elif finish == "brass":
		family = "v18/worked_metal"
		m.metallic = 0.57
		m.roughness = 0.42
		tiles = 2.4
	if family != "":
		var path := "res://room_kit/textures/"+family
		m.albedo_texture = load(path+"_albedo.png")
		m.normal_enabled = true
		m.normal_texture = load(path+"_normal.png")
		m.normal_scale = 0.33 if finish=="cloth" else 0.21
		m.roughness_texture = load(path+"_roughness.png")
		m.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
		m.uv1_triplanar = true
		m.uv1_scale = Vector3.ONE*tiles
		m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
		if family=="v16/furniture_walnut":
			m.albedo_color = Color(color).lerp(Color.WHITE,0.47)
	elif finish == "lit":
		m.emission_enabled = true
		m.emission = Color(color)
		m.emission_energy_multiplier = 0.65
	mats[id] = m
	return m

func mesh(parent: Node3D, shape: PrimitiveMesh, pos: Vector3, color: String, finish: String) -> MeshInstance3D:
	var n := MeshInstance3D.new()
	n.mesh = shape
	n.material_override = material(color,finish)
	parent.add_child(n)
	n.position = pos
	return n

func solid(parent: Node3D, pos: Vector3, size: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	body.add_child(collision)
	parent.add_child(body)
	body.position = pos
	return body

func box(p: Node3D, pos: Vector3, size: Vector3, c: String, f := "wood", hit := false) -> MeshInstance3D:
	var shape := BoxMesh.new()
	shape.size = size
	if hit:
		solid(p,pos,size)
	return mesh(p,shape,pos,c,f)

func oval(p: Node3D, pos: Vector3, size: Vector3, c: String, f := "") -> MeshInstance3D:
	var s := SphereMesh.new()
	s.radius = 0.5
	s.height = 1
	s.radial_segments = 16
	s.rings = 8
	var n := mesh(p,s,pos,c,f)
	n.scale = size
	return n

func tube(p: Node3D,pos: Vector3, top: float, bottom: float, height: float,c: String,f := "wood") -> MeshInstance3D:
	var s := CylinderMesh.new()
	s.top_radius = top
	s.bottom_radius = bottom
	s.height = height
	s.radial_segments = 24
	s.rings = 1
	return mesh(p,s,pos,c,f)

func ring(p: Node3D,pos: Vector3,r: float,width: float,c: String) -> MeshInstance3D:
	var s := TorusMesh.new()
	s.inner_radius = r-width
	s.outer_radius = r
	s.rings = 24
	s.ring_segments = 8
	var n := mesh(p,s,pos,c,"brass")
	n.rotation.x = PI/2
	return n

func nameplate(p: Node3D,words: String) -> void:
	var number := ["玩具房","客厅","庭院"].find(words)
	var im := Image.load_from_file("res://extension/plate%d.png"%number)
	im.generate_mipmaps()
	var sign := StandardMaterial3D.new()
	sign.albedo_texture = ImageTexture.create_from_image(im)
	sign.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var quad := QuadMesh.new()
	quad.size = Vector2(0.87,0.224)
	var n := MeshInstance3D.new()
	n.mesh = quad
	n.material_override = sign
	p.add_child(n)
	n.position = Vector3(0,1.72,0.071)

# 圆角软垫保留平缝和包边，让坐面与靠背在玩偶视角下有清晰的轮廓。
func cushion(p: Node3D,pos: Vector3,size: Vector3,radius: float,c: String) -> MeshInstance3D:
	var cube := BoxMesh.new()
	cube.size = Vector3.ONE*2
	cube.subdivide_width = 7
	cube.subdivide_depth = 7
	cube.subdivide_height = 7
	var data := cube.get_mesh_arrays()
	var verts: PackedVector3Array = data[Mesh.ARRAY_VERTEX]
	var norms: PackedVector3Array = data[Mesh.ARRAY_NORMAL]
	for i in verts.size():
		var point := verts[i]
		var half := size*0.5
		for axis in 3:
			var v: float = absf(point[axis])
			var span: float = half[axis]
			point[axis] = signf(point[axis])*(span-radius+radius*(v-0.25)/0.75) if v>=0.25 else 0.0
		var core := point.clamp(-half+Vector3.ONE*radius,half-Vector3.ONE*radius)
		var normal := (point-core).normalized()
		verts[i] = core + normal*radius
		norms[i] = normal
	data[Mesh.ARRAY_VERTEX] = verts
	data[Mesh.ARRAY_NORMAL] = norms
	var geometry := ArrayMesh.new()
	geometry.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,data)
	var n := MeshInstance3D.new()
	n.mesh = geometry
	n.material_override = material(c,"cloth")
	p.add_child(n)
	n.position=pos
	return n

# 把固定装饰按材质合并，同一材质只需绘制一次。活动部件保留自己的局部坐标。
func batch(p: Node3D) -> void:
	var surfaces := {}
	for child in p.get_children():
		if child is MeshInstance3D and child.mesh != null:
			var mat = child.material_override
			if not surfaces.has(mat):
				var st := SurfaceTool.new()
				st.begin(Mesh.PRIMITIVE_TRIANGLES)
				st.set_material(mat)
				surfaces[mat] = st
			surfaces[mat].append_from(child.mesh,0,child.transform)
			child.free()
	for st in surfaces.values():
		var n := MeshInstance3D.new()
		n.mesh = st.commit()
		p.add_child(n)

func lamp(p: Node3D,pos: Vector3,c: String,energy: float,reach: float) -> void:
	var light := OmniLight3D.new()
	light.light_color = Color(c)
	light.light_energy = energy
	light.omni_range = reach
	p.add_child(light)
	light.position = pos

func door(p: Node3D,pos: Vector3,yaw: float,words: String) -> Dictionary:
	var frame := group(p,pos)
	frame.rotation.y = yaw
	for x in [-0.59,0.59]:
		box(frame,Vector3(x,0.76,0),Vector3(0.15,1.52,0.22),HONEY,"wood",true)
		box(frame,Vector3(x,0.1,0),Vector3(0.22,0.2,0.28),WOOD)
	box(frame,Vector3(0,1.55,0),Vector3(1.47,0.18,0.29),WOOD,"wood",true)
	box(frame,Vector3(0,1.72,0),Vector3(0.88,0.23,0.13),GREEN)
	nameplate(frame,words)
	box(frame,Vector3(0,0.014,0),Vector3(1.18,0.028,0.34),GOLD,"brass")
	# 原版拱门的木板倒角、把手、铁箍和螺钉沿用同一套网格与材质。
	var leaf := AnimatableBody3D.new()
	leaf.sync_to_physics=false
	leaf.collision_layer=1
	leaf.collision_mask=6
	frame.add_child(leaf)
	leaf.position=Vector3(-0.51,0,0)
	var artwork:=group(leaf,Vector3.ZERO)
	var original: Node3D=reference_door.leaf
	var local_frame:=original.global_transform.affine_inverse()
	var bounds:=AABB()
	var first:=true
	for m in original.find_children("*","MeshInstance3D",true,false):
		if not m.mesh:
			continue
		var replica:=MeshInstance3D.new()
		artwork.add_child(replica)
		replica.transform=local_frame*m.global_transform
		library.copy_visual(m,replica)
		library.links.append([m,replica])
		var part: AABB=replica.transform*m.get_aabb()
		bounds=part if first else bounds.merge(part)
		first=false
	artwork.scale=Vector3(1.01/bounds.size.x,1.47/bounds.size.y,1.01/bounds.size.x)
	artwork.position=-Vector3(bounds.position.x,bounds.position.y,bounds.get_center().z)*artwork.scale
	var sheet:=BoxShape3D.new()
	sheet.size=Vector3(1.0,1.28,0.085)
	var contact:=CollisionShape3D.new()
	contact.shape=sheet
	leaf.add_child(contact)
	contact.position=Vector3(0.505,0.64,0)
	var sound:=AudioStreamPlayer3D.new()
	sound.stream=reference_door.impact.stream
	sound.volume_db=reference_door.impact.volume_db
	frame.add_child(sound)
	sound.position=Vector3(0,0.7,0)
	var block := solid(frame,Vector3(0,0.73,0),Vector3(1.03,1.46,0.12))
	batch(frame)
	return {"frame":frame,"leaf":leaf,"block":block,"sound":sound,"swing":0.0}

func stem(p: Node3D,tail: Vector3,tip: Vector3,radius: float,c: String) -> void:
	var axis := tip-tail
	var pole := tube(p,(tail+tip)*0.5,radius*0.58,radius,axis.length(),c)
	pole.quaternion = Quaternion(Vector3.UP,axis.normalized())

# 中脉略隆起，叶尖下弯，使纸艺叶片从低视角也有厚薄和纹理。
func leaf(p: Node3D,pos: Vector3,length: float,width: float,yaw: float,tilt: float,c: String) -> void:
	if blade_mesh==null:
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var ribs := [0.016,0.72,1.0,0.80,0.42,0.016]
		for i in 5:
			for side in [-1,1]:
				var corners: Array[Vector3] = []
				for j in [i,i+1]:
					var t: float = j/5.0
					var rise: float = 0.21*sin(t*PI)-0.12*t*t
					corners.append(Vector3(0,rise+0.031*ribs[j],t))
					corners.append(Vector3(side*ribs[j],rise,t))
				var order := [0,2,1,1,2,3] if side==1 else [0,1,2,1,3,2]
				for idx in order:
					st.set_uv(Vector2(corners[idx].x*0.5+0.5,corners[idx].z))
					st.add_vertex(corners[idx])
		st.generate_normals()
		st.generate_tangents()
		blade_mesh=st.commit()
	var n := MeshInstance3D.new()
	n.mesh=blade_mesh
	n.scale=Vector3(width,length,length)
	var mat := material(c,"paper")
	mat.cull_mode=BaseMaterial3D.CULL_DISABLED
	n.material_override=mat
	p.add_child(n)
	n.position=pos
	n.rotation=Vector3(tilt,yaw,0)

func blossom(p: Node3D,pos: Vector3,r: float,color: String) -> void:
	for j in 7:
		var angle := TAU*j/7.0
		var petal := oval(p,pos+Vector3(sin(angle)*r,cos(angle)*r,0.025),Vector3(r*1.06,r*1.45,0.055),color,"paper")
		petal.rotation=Vector3(-0.18*cos(angle),0.18*sin(angle),-angle)
	oval(p,pos+Vector3(0,0,0.053),Vector3(r*1.24,r*1.24,0.074),GOLD,"paper")
	for j in 7:
		var angle := TAU*j/7.0
		oval(p,pos+Vector3(sin(angle)*r*0.37,cos(angle)*r*0.37,0.091),Vector3.ONE*r*0.15,HONEY)

func living(p: Node3D) -> void:
	solid(p,Vector3(0,-0.1,0),Vector3(12,0.2,11))
	var underlay := PlaneMesh.new()
	underlay.size = Vector2(12.05,11.05)
	var oak := StandardMaterial3D.new()
	oak.albedo_texture=preload("res://assets/toy_room_v5_wood_floor_worn_Diffuse.jpg")
	oak.normal_enabled=true
	oak.normal_texture=preload("res://assets/toy_room_v5_wood_floor_worn_nor_gl.jpg")
	oak.normal_scale=0.24
	oak.roughness_texture=preload("res://assets/toy_room_v5_wood_floor_worn_Rough.png")
	oak.uv1_scale=Vector3(2.0,2.0,1.0)
	oak.texture_filter=BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	var boards:=MeshInstance3D.new()
	boards.mesh=underlay
	boards.material_override=oak
	p.add_child(boards)
	boards.position.y=-0.011
	library.furnish(p,"Props/Floor",Vector3(0,-0.002,0),Vector3(12,0,11),false,true)
	for side in [-1,1]:
		solid(p,Vector3(side*6,2.4,0),Vector3(0.16,4.8,11.1))
		solid(p,Vector3(0,2.4,side*5.5),Vector3(12,4.8,0.16))
	library.furnish(p,"Architecture/BackWall",Vector3(0,0,-5.51),Vector3(12.18,4.8,0.26))
	library.furnish(p,"Architecture/FrontWall",Vector3(0,0,5.51),Vector3(12.18,4.8,0.26))
	library.furnish(p,"Architecture/WestWall",Vector3(-6,0,0),Vector3(0.24,4.8,11.22))
	library.furnish(p,"Architecture/EastWall",Vector3(6,0,0),Vector3(0.24,4.8,11.22))
	# 墙角内侧补连续灰泥底衬，遮住墙板之间透出的细缝。
	box(p,Vector3(-5.974,3.15,-5.478),Vector3(0.166,2.86,0.166),"#b4aa99","paper")
	# 原版墙板上方接两层压线和暖灰灰泥顶，低机位能看见墙顶的厚度。
	var plaster:=material("#e4d6bd","paper").duplicate() as StandardMaterial3D
	plaster.emission_enabled=true
	plaster.emission=Color("#b1a794")
	plaster.emission_energy_multiplier=0.42
	var ceiling:=BoxMesh.new()
	ceiling.size=Vector3(12.2,0.13,11.2)
	var lid:=MeshInstance3D.new()
	lid.mesh=ceiling
	lid.material_override=plaster
	lid.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	var lid_root:=group(p,Vector3(0,4.84,0))
	lid_root.add_child(lid)
	for side in [-1,1]:
		for course in [[4.54,0.058,0.12,"#a7997f"],[4.63,0.13,0.19,"#ded0b1"],[4.72,0.055,0.30,"#ede1c9"]]:
			box(p,Vector3(0,course[0],side*5.38),Vector3(12.05,course[1],course[2]),course[3])
			box(p,Vector3(side*5.88,course[0],0),Vector3(course[2],course[1],10.9),course[3])
	library.furnish(p,"Architecture/Window sky",Vector3(-1.68,1.15,-5.72),Vector3(6.5,3.6,0))
	library.furnish(p,"Props/Curtains",Vector3(-1.68,1.45,-5.24),Vector3(4.36,2.77,0.28))
	library.furnish(p,"Props/WhalePicture",Vector3(1.74,3.24,-5.26),Vector3(1.32,0,0),false,false,true)
	box(p,Vector3(-1.3,0.33,-3.7),Vector3(3.85,0.35,1.34),WOOD,"wood",true)
	box(p,Vector3(-1.3,0.98,-4.23),Vector3(3.65,1.12,0.29),GREEN,"cloth",true)
	for x in [-2.47,-1.3,-0.13]:
		cushion(p,Vector3(x,0.64,-3.65),Vector3(1.13,0.28,1.10),0.105,"#75998a")
		cushion(p,Vector3(x,0.60,-3.65),Vector3(1.14,0.09,1.11),0.040,"#b4b899")
		solid(p,Vector3(x,0.57,-3.65),Vector3(1.14,0.28,1.18))
		cushion(p,Vector3(x,1.08,-4.04),Vector3(1.13,0.84,0.35),0.15,"#648c80").rotation.x=-0.11
	for x in [-3.26,0.66]:
		cushion(p,Vector3(x,0.78,-3.71),Vector3(0.41,0.68,1.40),0.16,GREEN)
	for x in [-2.56,0.03]:
		cushion(p,Vector3(x,0.97 if x<0 else 1.03,-3.75),Vector3(0.56,0.49 if x<0 else 0.53,0.24),0.11,RUST).rotation.z = -0.32 if x<0 else 0.24
	library.furnish(p,"Props/Rug",Vector3(-0.6,0.002,0),Vector3(5.65,0.023,3.48))
	solid(p,Vector3(-0.6,0.009,0),Vector3(5.43,0.018,3.25))
	library.furnish(p,"Props/BookRoute",Vector3(-4.35,0.026,2.84),Vector3(1.98,0,0),true,false,true)
	# 压线外露出一小截双色短穗，沿着地毯前后两边收口。
	for side in [-1,1]:
		for i in 95:
			var x:float=-3.38+i*0.059
			var z:float=side*1.733
			var strand:=box(p,Vector3(x,0.013,z+side*0.024),Vector3(0.012,0.009,0.071+0.020*sin(i*5.2)),"#bd9c74" if i%3 else "#d8c7a8","cloth")
			strand.rotation.y=0.19*sin(i*1.72)
	var book_positions := [Vector3(-2.92,0.026,0.77),Vector3(-3.48,0.026,0.38),Vector3(1.38,0.028,-0.47),Vector3(1.96,0.026,-0.72)]
	for j in book_positions.size():
		var stack:=group(p,book_positions[j])
		stack.rotation.y=[0.14,-0.19,-0.32,0.21][j]
		var h: float=[0.18,0.30,0.17,0.22][j]
		var bind: String = [RUST,GREEN,"#425661","#754437"][j]
		box(stack,Vector3(0,h*0.5,0),Vector3(0.86,h,0.58),CREAM,"paper",true)
		for y in [0.012,h]:
			box(stack,Vector3(0,y,0),Vector3(0.91,0.025,0.63),bind,"cloth")
		box(stack,Vector3(-0.44,h*0.5,0),Vector3(0.044,h,0.62),bind,"cloth")
		for k in 5:
			box(stack,Vector3(0,h*(k+1)/6.0,0.292),Vector3(0.84,0.003,0.003),"#bbaa89","paper")
		for x in [-0.34,0.34]:
			box(stack,Vector3(x,h+0.014,0),Vector3(0.006,0.002,0.49),GOLD,"brass")
		for z in [-0.245,0.245]:
			box(stack,Vector3(0,h+0.014,z),Vector3(0.68,0.002,0.006),GOLD,"brass")
		batch(stack)
	for x in [-4.25,-3.70]:
		for z in [-0.34,0.20]:
			tube(p,Vector3(x,0.21,z),0.06,0.095,0.42,WOOD)
	box(p,Vector3(-3.98,0.46,-0.07),Vector3(1.05,0.19,1.02),"#ac7954","wood",true)
	oval(p,Vector3(-3.98,0.58,-0.07),Vector3(1.19,0.25,1.10),"#d5ae6b","cloth")
	wind_key = group(p,Vector3(-3.98,0.83,-0.07))
	ring(wind_key,Vector3(0,0.065,0),0.13,0.045,GOLD)
	box(wind_key,Vector3(0,-0.105,0),Vector3(0.058,0.18,0.045),GOLD,"brass")
	box(wind_key,Vector3(0.045,-0.17,0),Vector3(0.1,0.052,0.05),GOLD,"brass")
	batch(wind_key)
	for x in [-2.47,-1.3,-0.13]:
		for offset in [-0.30,0.0,0.30]:
			oval(p,Vector3(x+offset,1.13,-3.85),Vector3(0.065,0.065,0.025),"#51766c","cloth")
	for x in [-2.96,0.34]:
		for z in [-4.22,-3.18]:
			tube(p,Vector3(x,0.17,z),0.12,0.085,0.32,WOOD)
	for x in [-3.10,-2.92,-1.92,-0.72,0.27,0.45]:
		oval(p,Vector3(x,0.37,-3.017),Vector3(0.022,0.022,0.009),"#916f49","brass")
	# 铃架夹在扶手内侧，流苏垂到右侧坐垫旁。
	var bracket:=group(p,Vector3(0.55,1.08,-3.79))
	oval(bracket,Vector3(0,0.025,0),Vector3(0.16,0.075,0.14),GOLD,"brass")
	tube(bracket,Vector3(0,0.22,0),0.036,0.048,0.4,WOOD,"wood")
	oval(bracket,Vector3(0,0.44,0),Vector3(0.089,0.085,0.089),HONEY,"wood")
	box(bracket,Vector3(-0.095,0.4,0),Vector3(0.23,0.035,0.047),GOLD,"brass")
	oval(bracket,Vector3(-0.19,0.34,0),Vector3(0.115,0.12,0.115),GOLD,"brass")
	tube(bracket,Vector3(-0.19,0.30,0),0.052,0.080,0.064,GOLD,"brass")
	tube(bracket,Vector3(-0.19,0.219,0),0.010,0.012,0.12,"#73553b","cloth")
	ring(bracket,Vector3(-0.19,0.15,0),0.032,0.009,GOLD)
	tube(bracket,Vector3(-0.19,0.094,0),0.021,0.043,0.085,RUST,"cloth")
	batch(bracket)
	var clock := group(p,Vector3(2.75,0,-3.72))
	for row in [[0.13,1.12,0.26,0.8],[0.32,0.95,0.18,0.66],[1.12,0.76,1.57,0.56],[1.99,1.03,0.21,0.69],[2.43,0.98,0.79,0.66],[2.86,1.17,0.12,0.81]]:
		box(clock,Vector3(0,row[0],0),Vector3(row[1],row[2],row[3]),WOOD,"wood",true)
	box(clock,Vector3(0,1.15,0.29),Vector3(0.58,1.45,0.055),DARK)
	oval(clock,Vector3(0,2.89,0),Vector3(0.87,0.46,0.48),HONEY)
	oval(clock,Vector3(0,2.45,0.345),Vector3(0.84,0.84,0.07),CREAM)
	ring(clock,Vector3(0,2.45,0.39),0.43,0.035,GOLD)
	for k in 12:
		var a := k*TAU/12.0
		var tick := box(clock,Vector3(sin(a)*0.33,2.45+cos(a)*0.33,0.4),Vector3(0.021,0.058,0.016),DARK)
		tick.rotation.z = -a
	box(clock,Vector3(-0.08,2.48,0.43),Vector3(0.19,0.032,0.015),DARK).rotation.z=-0.35
	minute_hand = group(clock,Vector3(0,2.45,0.44))
	box(minute_hand,Vector3(0,0.115,0),Vector3(0.029,0.25,0.018),DARK)
	clock_pivot = group(clock,Vector3(0,1.77,0.35))
	box(clock_pivot,Vector3(0,-0.43,0),Vector3(0.039,0.86,0.04),GOLD,"brass")
	oval(clock_pivot,Vector3(0,-0.86,0),Vector3(0.33,0.34,0.075),GOLD,"brass")
	for side in [-1,1]:
		tube(clock,Vector3(side*0.382,1.19,0.31),0.048,0.052,1.39,HONEY)
		for y in [0.49,0.57,1.84,1.91]:
			tube(clock,Vector3(side*0.382,y,0.31),0.072,0.072,0.056,GOLD,"brass")
		for y in [0.23,2.04,2.84]:
			box(clock,Vector3(0,y,0.355),Vector3(0.92,0.024,0.022),GOLD,"brass")
	var dial := QuadMesh.new()
	dial.size=Vector2(0.77,0.77)
	var face := StandardMaterial3D.new()
	var artwork := Image.load_from_file("res://extension/clock.png")
	artwork.generate_mipmaps()
	face.albedo_texture=ImageTexture.create_from_image(artwork)
	face.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	face.roughness=0.84
	var dial_face := MeshInstance3D.new()
	dial_face.mesh=dial
	dial_face.material_override=face
	clock.add_child(dial_face)
	dial_face.position=Vector3(0,2.45,0.416)
	# 客厅花瓶与庭院使用同一朵花；引水开花后，窗边的花枝也会开放。
	var table := group(p,Vector3(0.99,0,-3.95))
	tube(table,Vector3(0,0.37,0),0.10,0.16,0.70,WOOD)
	tube(table,Vector3(0,0.72,0),0.40,0.42,0.10,HONEY)
	solid(table,Vector3(0,0.73,0),Vector3(0.68,0.12,0.63))
	oval(table,Vector3(0,0.90,0),Vector3(0.29,0.30,0.29),"#809998","brass")
	tube(table,Vector3(0,1.035,0),0.082,0.068,0.08,GOLD,"brass")
	living_petals=group(table,Vector3.ZERO)
	for j in 3:
		var point := Vector3((j-1)*0.13,1.40+0.09*sin(j*2),0.04*j)
		stem(table,Vector3(0,1.03,0),point,0.013,"#5d764e")
		leaf(table,point-Vector3.UP*0.15,0.17,0.042,j*1.9,-0.26,"#819468")
		blossom(living_petals,point,0.071,["#e8b54c","#f4dbb2","#d67b61"][j])
	batch(table)
	batch(living_petals)
	living_petals.hide()
	batch(clock)
	tube(p,Vector3(-4.12,0.08,-3.8),0.35,0.41,0.16,WOOD)
	tube(p,Vector3(-4.12,1.08,-3.8),0.045,0.055,2.0,GOLD,"brass")
	tube(p,Vector3(-4.12,2.15,-3.8),0.33,0.57,0.62,"#e9c689","lit")
	lamp(p,Vector3(-4.12,2.04,-3.65),"#ffdb9a",0.77,4.2)
	lamp(p,Vector3(0,3,1),"#fff2d4",0.80,10)
	var shade:=StandardMaterial3D.new()
	shade.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	shade.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA
	var mask:=Image.load_from_file("res://extension/furniture-shade.png")
	mask.generate_mipmaps()
	shade.albedo_texture=ImageTexture.create_from_image(mask)
	var st:=SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_material(shade)
	for corner in [Vector2(0,0),Vector2(1,0),Vector2(0,1),Vector2(0,1),Vector2(1,0),Vector2(1,1)]:
		st.set_uv(corner)
		st.set_normal(Vector3.UP)
		st.add_vertex(Vector3(-6+corner.x*12,0.004,-5.35+2.88*corner.y))
	var shadow_plane:=MeshInstance3D.new()
	shadow_plane.mesh=st.commit()
	shadow_plane.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	group(p,Vector3.ZERO).add_child(shadow_plane)
	var window_light := SpotLight3D.new()
	p.add_child(window_light)
	window_light.position=Vector3(-1.5,3.5,-4.6)
	window_light.look_at(p.to_global(Vector3(0,0,0.5)))
	window_light.light_color=Color("#ffe0ae")
	window_light.light_energy=1.05
	window_light.spot_range=9
	window_light.spot_angle=53
	window_light.shadow_enabled=true
	batch(p)

func read_surface(file: FileAccess, mat: Material) -> ArrayMesh:
	var count:=file.get_32()
	var arrays: Array=[]
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX]=file.get_buffer(count*12).to_vector3_array()
	arrays[Mesh.ARRAY_NORMAL]=file.get_buffer(count*12).to_vector3_array()
	arrays[Mesh.ARRAY_COLOR]=file.get_buffer(count*16).to_color_array()
	arrays[Mesh.ARRAY_TEX_UV]=file.get_buffer(count*8).to_vector2_array()
	var result:=ArrayMesh.new()
	result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	result.surface_set_material(0,mat)
	if mat is StandardMaterial3D and mat.normal_enabled and mat.normal_texture!=null and not mat.uv1_triplanar:
		var tangent_builder:=SurfaceTool.new()
		tangent_builder.create_from(result,0)
		tangent_builder.generate_tangents()
		return tangent_builder.commit()
	return result

func orchard(p: Node3D,rng: RandomNumberGenerator) -> void:
	var bark:=material("#9b8468","wood").duplicate() as StandardMaterial3D
	bark.vertex_color_use_as_albedo=true
	var foliage:=ShaderMaterial.new()
	foliage.shader=preload("res://extension/canopy.gdshader")
	var trees: Array=[]
	for i in 3:
		var file:=FileAccess.open("res://extension/orchard%d.meshbin"%i,FileAccess.READ)
		trees.append([read_surface(file,bark),read_surface(file,foliage)])
	# 分成近处舒展的老树、稍远的直树和低矮树丛，给栅栏后留出纵深。
	var layout: Array = [
		[-9.45,-7.6,0.90,0.88,-0.15],[-2.3,-12.1,0.68,0.91,0.09],
		[1.65,-9.5,1.05,1.01,-0.15],[9.65,-12.8,0.91,1.40,0.08],
		[8.5,-4.6,1.06,0.97,0.12],[10.3,-1.8,0.69,1.20,-0.10],
		[8.7,3.9,1.31,0.97,0.05],[5.3,9.2,0.85,1.24,-0.12],
		[-0.8,9.9,1.28,0.88,0.18],[-6.2,8.4,0.90,1.16,-0.09],
		[-8.1,3.3,1.32,0.90,0.09],[-10.4,-0.6,0.68,1.36,-0.04]]
	for i in layout.size():
		var row: Array=layout[i]
		var tree:=group(p,Vector3(row[0],-0.06,row[1]))
		tree.rotation=Vector3(0.03*sin(i),i*2.23,row[4])
		tree.scale=Vector3(row[2],row[3],row[2]*(1.12 if i%2 else 0.91))
		for geometry in trees[i%3]:
			var part:=MeshInstance3D.new()
			part.mesh=geometry
			tree.add_child(part)
	var shrubs: Array=[]
	for i in 2:
		var file:=FileAccess.open("res://extension/shrub%d.meshbin"%i,FileAccess.READ)
		shrubs.append([read_surface(file,bark),read_surface(file,foliage)])
	var border_rng:=RandomNumberGenerator.new()
	border_rng.seed=583
	for j in 52:
		var angle:=TAU*j/52.0+0.045*sin(j*1.8)
		var back:=border_rng.randf_range(0,2.4)
		var hedge:=group(p,Vector3(sin(angle)*(7.1+back),-0.09,cos(angle)*(6.4+back)))
		hedge.scale=Vector3(1.15+0.35*sin(j),0.92+border_rng.randf()*0.85,1.16)
		if hedge.position.z < -4.8:
			var opening:=smoothstep(0.55,1.75,absf(hedge.position.x+3.7))
			hedge.scale.y*=lerpf(0.22,0.73,opening)
			var pump_gap:=smoothstep(0.65,1.9,absf(hedge.position.x-5.4))
			hedge.scale.y*=lerpf(0.32,1.0,pump_gap)
			hedge.scale.x*=lerpf(0.74,1.0,opening)
		hedge.scale.y*=0.86+0.36*cos(angle*6.0+0.4)+0.19*sin(angle*9.0)
		hedge.rotation.y=j*1.6
		for geometry in shrubs[j%2]:
			var part:=MeshInstance3D.new()
			part.mesh=geometry
			hedge.add_child(part)
	# 远景连续起伏，围栏的缝隙也能看到同一个地平线。
	for band in 2:
		var st:=SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var tint:=StandardMaterial3D.new()
		tint.vertex_color_use_as_albedo=true
		tint.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
		tint.cull_mode=BaseMaterial3D.CULL_DISABLED
		st.set_material(tint)
		for j in 100:
			var quad: Array[Vector3]=[]
			for k in [j,j+1]:
				var a: float = TAU*k/100.0
				var radius:=16.0+band*6.0
				var top:=0.94+band*1.1+0.75*sin(a*3.0+band)+0.27*cos(a*7.0)+0.15*sin(a*23.0)
				quad.append(Vector3(sin(a)*radius,-2.4,cos(a)*radius))
				quad.append(Vector3(sin(a)*(radius+2),top,cos(a)*(radius+2)))
			for index in [0,1,2,2,1,3]:
				st.set_color((Color("#8e9e81") if band==0 else Color("#bdc2a5")) if index%2==1 else (Color("#64765e") if band==0 else Color("#9aa98d")))
				st.add_vertex(quad[index])
		var ridge:=MeshInstance3D.new()
		ridge.mesh=st.commit()
		ridge.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var backdrop:=group(p,Vector3.ZERO)
		backdrop.add_child(ridge)

func garden(p: Node3D) -> void:
	library.furnish(p,"Props/WickerBasket",Vector3(4.90,0.01,-3.70),Vector3(1.31,0,0),true,false,true)
	library.furnish(p,"Props/Bunting",Vector3(-3.25,1.88,-3.32),Vector3(3.50,0,0),false,false,true)
	var rng := RandomNumberGenerator.new()
	rng.seed = 1987
	solid(p,Vector3(0,-0.15,0),Vector3(13,0.3,11.8))
	for side in [-1,1]:
		solid(p,Vector3(side*6.23,1.4,0),Vector3(0.22,2.8,11.8))
		solid(p,Vector3(0,1.4,side*5.7),Vector3(12.6,2.8,0.18))
		for j in 31:
			var x := -6.15+j*0.41
			var z: float = side*5.67
			box(p,Vector3(x,0.56,z),Vector3(0.29,1.12,0.13),"#bbcab0")
			oval(p,Vector3(x,1.09,z),Vector3(0.29,0.25,0.13),"#bbcab0")
		for j in 27:
			box(p,Vector3(side*6.2,0.57,-5.41+j*0.416),Vector3(0.13,1.14,0.29),"#b5c7aa")
		for y in [0.28,0.79]:
			box(p,Vector3(0,y,side*5.71),Vector3(12.65,0.12,0.13),GREEN)
			box(p,Vector3(side*6.24,y,0),Vector3(0.13,0.12,11.5),GREEN)
	# 门旁的育苗盆让角色一出门就有尺寸参照。泥土、卷边与排水碟分开塑形。
	for j in 3:
		var pot:=group(p,Vector3(2.22+j*0.56+(0.15 if j==1 else 0.0),0,2.72-j*0.59+(-0.29 if j==1 else 0.0)))
		pot.rotation.y=[0.12,-0.92,0.65][j]
		var radius:=0.23+0.04*j
		var height:=0.34+0.07*j
		tube(pot,Vector3(0,0.036,0),radius*1.06,radius,0.07,"#af7353","soil")
		tube(pot,Vector3(0,height*0.52+0.04,0),radius,radius*0.68,height,"#bd7955","soil")
		tube(pot,Vector3(0,height+0.02,0),radius*1.11,radius*1.08,0.071,"#c68969","soil")
		tube(pot,Vector3(0,height+0.061,0),radius*0.92,radius*0.92,0.012,"#30281c","soil")
		for grain in 16+j*4:
			var angle:float=grain*2.4+j*1.61
			var distance:float=radius*0.83*sqrt((grain+0.5)/(16.0+j*4.0))
			var grit:=0.010+0.009*(0.5+0.5*sin(grain*7.3))
			oval(pot,Vector3(cos(angle)*distance,height+0.070,sin(angle)*distance),Vector3(grit*1.7,grit*0.6,grit),"#483625" if grain%3 else "#655037","soil")
		var pot_body:=StaticBody3D.new()
		pot.add_child(pot_body)
		var shape:=CylinderShape3D.new()
		shape.height=height+0.06
		shape.radius=radius
		var cs:=CollisionShape3D.new()
		cs.shape=shape
		pot_body.add_child(cs)
		cs.position.y=shape.height*0.5
		for l in 6+j*2:
			var azimuth:float=l*2.4+j*1.73
			var tip:=Vector3(cos(azimuth)*(0.09+0.022*j),height+0.14+j*0.028+0.09*sin(l*1.8+j),sin(azimuth)*0.12)
			stem(pot,Vector3(0,height+0.04,0),tip,0.009,"#758455")
			leaf(pot,tip,0.15+0.06*sin(l*0.87+j),0.044+j*0.005,azimuth,-0.49-0.11*j,"#879861" if l%2 else "#72895c")
		batch(pot)
	# 地表纹理和踩出的泥边使用同一套石板轮廓。
	var path_group:=group(p,Vector3.ZERO)
	for layer in ["gardenfloor","path","grassedge"]:
		var mat:=StandardMaterial3D.new()
		mat.roughness=0.96
		mat.metallic_specular=0.18
		if layer!="grassedge":
			var file_name: String="gardenfloor.jpg" if layer=="gardenfloor" else "flagstones.jpg"
			var im:=Image.load_from_file("res://extension/"+file_name)
			im.generate_mipmaps()
			mat.albedo_texture=ImageTexture.create_from_image(im)
			mat.texture_filter=BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
		if layer=="path":
			var relief_image:=Image.load_from_file("res://extension/flagstone-relief.jpg")
			relief_image.generate_mipmaps()
			mat.normal_enabled=true
			mat.normal_texture=ImageTexture.create_from_image(relief_image)
			mat.normal_scale=0.38
		if layer!="gardenfloor":
			mat.vertex_color_use_as_albedo=true
			mat.vertex_color_is_srgb=true
		if layer=="grassedge":
			mat.cull_mode=BaseMaterial3D.CULL_DISABLED
		var data:=FileAccess.open("res://extension/"+layer+".meshbin",FileAccess.READ)
		while data.get_position()<data.get_length():
			var detail:=MeshInstance3D.new()
			detail.mesh=read_surface(data,mat)
			if layer=="grassedge":
				var blades:=ShaderMaterial.new()
				blades.shader=preload("res://extension/grass.gdshader")
				detail.material_override=blades
				detail.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			path_group.add_child(detail)
			if layer=="path":
				detail.create_trimesh_collision()
	orchard(p,rng)
	# 花圃、叶片和花心分别建模，晚开的花随最后一次互动展开。
	box(p,Vector3(-3.28,0.1,-2.35),Vector3(3.25,0.22,1.55),"#745740","soil",true)
	for side in [-1,1]:
		box(p,Vector3(-3.28,0.18,-2.35+side*0.77),Vector3(3.42,0.35,0.12),HONEY,"wood",true)
		box(p,Vector3(-3.28+side*1.63,0.18,-2.35),Vector3(0.13,0.35,1.65),HONEY,"wood",true)
	flowers = group(p,Vector3(-3.28,0.18,-2.35))
	for k in 17:
		var x := (k%6)*0.51-1.28+rng.randf_range(-0.08,0.08)
		var z := floorf(k/6.0)*0.40-0.41
		var h := 0.39+rng.randf()*0.46+0.13*sin(k*2.1)
		var root:=Vector3(-3.28+x,0.18,-2.35+z)
		var tip:=root+Vector3(0.13*sin(k*1.8),h,0.093*cos(k*0.7))
		var middle:=root.lerp(tip,0.48)-Vector3(0.031*sin(k),0,0)
		stem(p,root,middle,0.023,"#4e7954")
		stem(p,middle,tip,0.017,"#4e7954")
		for side in [-1,1]:
			oval(p,middle+Vector3(side*0.069,0.02,0),Vector3(0.24,0.07,0.11),"#5d8758").rotation.z=side*0.58
		oval(p,tip,Vector3(0.09,0.13,0.1),"#82934f")
		var c: String = ["#e8b54c","#f4dbb2","#d67b61","#e5a3a6"][k%4]
		blossom(flowers,tip-Vector3(-3.28,0.18,-2.35),0.113,c)
		leaf(p,middle,0.25,0.061,k*2.2,-0.55,"#74905c")
	batch(flowers)
	flowers.hide()
	# 带手轮的铸铁水泵。
	var pump := group(p,Vector3(3.53,0,-2.42))
	tube(pump,Vector3(0,0.12,0),0.52,0.61,0.23,"#b1ab91","soil")
	tube(pump,Vector3(0,0.65,0),0.22,0.30,0.91,GREEN,"brass")
	tube(pump,Vector3(0,1.12,0),0.31,0.29,0.16,GREEN,"brass")
	oval(pump,Vector3(0,1.26,0),Vector3(0.49,0.34,0.49),GREEN,"brass")
	box(pump,Vector3(-0.34,0.86,0),Vector3(0.52,0.17,0.18),GREEN,"brass")
	tube(pump,Vector3(-0.58,0.77,0),0.10,0.11,0.23,GREEN,"brass")
	valve = group(pump,Vector3(0,0.83,0.29))
	ring(valve,Vector3.ZERO,0.30,0.054,RUST)
	for j in 3:
		box(valve,Vector3.ZERO,Vector3(0.046,0.5,0.037),RUST,"brass").rotation.z = j*PI/3
	oval(valve,Vector3(0,0,0.03),Vector3(0.12,0.12,0.08),GOLD,"brass")
	solid(pump,Vector3(0,0.53,0),Vector3(0.53,1.05,0.51))
	for j in 6:
		var angle:=j*TAU/6.0
		tube(pump,Vector3(sin(angle)*0.40,0.235,cos(angle)*0.40),0.035,0.035,0.032,GOLD,"brass")
	for h in [0.31,0.96,1.06]:
		tube(pump,Vector3(0,h,0),0.268,0.268,0.035,GOLD,"brass")
	batch(pump)
	batch(valve)
	for z in [-2.29,-2.59]:
		box(p,Vector3(0.75,0.095,z),Vector3(4.62,0.16,0.079),"#99765a","wood",true)
	box(p,Vector3(0.75,0.038,-2.44),Vector3(4.60,0.077,0.24),"#705f4d")
	channel=group(p,Vector3(0.17,0.12,-2.44))
	box(channel,Vector3(0,0.11,0),Vector3(0.10,0.34,0.34),HONEY)
	box(channel,Vector3(0,0.31,0),Vector3(0.34,0.09,0.10),RUST)
	water=group(p,Vector3(2.96,0.105,-2.44))
	box(water,Vector3(-2.26,0,0),Vector3(4.52,0.034,0.22),"#78bdb8","lit")
	for k in 13:
		box(water,Vector3(-0.11-k*0.34,0.020,0.04*sin(k)),Vector3(0.12,0.005,0.019),"#d4e8d4","lit")
	batch(water)
	water.hide()
	# 藤架上挂着风铃，灌溉完成后会随花田一同回应。
	for x in [-4.88,-1.72]:
		box(p,Vector3(x,1.08,-3.4),Vector3(0.14,2.16,0.15),HONEY)
	box(p,Vector3(-3.30,2.22,-3.4),Vector3(3.69,0.18,0.23),WOOD)
	chimes=group(p,Vector3(-3.0,2.12,-3.4))
	for j in 5:
		var x := (j-2)*0.16
		box(chimes,Vector3(x,-0.17,0),Vector3(0.012,0.34,0.012),CREAM)
		tube(chimes,Vector3(x,-0.44,0),0.042,0.042,0.36+j*0.045,GOLD,"brass")
	batch(chimes)
	for j in 32:
		var t:=j/31.0
		var tip:=Vector3(-4.98+3.32*t,2.36+sin(t*TAU*3)*0.09,-3.36)
		if j>0:
			stem(p,tip-Vector3(0.13,0.023*cos(t*TAU*3),0),tip,0.025,"#62734c")
		leaf(p,tip,0.23+0.08*sin(j),0.065,j*1.83,-0.2+0.46*sin(j),"#84935f")
	for k in 155:
		var x := rng.randf_range(-5.87,5.87)
		var z := rng.randf_range(-5.25,5.25)
		if absf(x)<4.8 and absf(z)<3.8:
			continue
		for j in 3:
			leaf(p,Vector3(x+j*0.030,0.01,z),0.17+rng.randf()*0.13,0.025,k+j*2.2,-0.89+0.22*j,["#708862","#849963","#9ca56b"][j])
	lamp(p,Vector3(0,4.5,0),"#fff3d9",2.2,14)
	batch(p)

