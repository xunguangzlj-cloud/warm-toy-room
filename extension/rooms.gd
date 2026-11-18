extends "res://room.gd"

const ORIGINS := [Vector3.ZERO, Vector3(100,0,0), Vector3(200,0,0)]
const PLACES := ["玩具房","客厅","庭院"]
const CLOCK_ROUTE := ["跳上沙发旁的脚凳，取下黄铜发条","把发条装进落地钟","跳上右侧沙发垫，拉响报时绳","落地钟已报时"]
const FLOWER_ROUTE := ["转动石径右侧水泵的红色手轮","沿水渠找到木闸，把水引向花圃","到花圃旁轻摇风铃，让花朵舒展","花圃已盛开"]
const STATIONS := [
	[Vector3(-3.98,0.78,-0.07),Vector3(2.75,0.4,-3.13),Vector3(0.37,1.18,-3.80)],
	[Vector3(3.53,0.5,-2.02),Vector3(0.17,0.25,-2.20),Vector3(-3.0,0.45,-3.31)]
]
const ACTIONS := [["取下发条","装上发条","拉动报时绳"],["转动手轮","提起木闸","摇响风铃"]]
var scenery = preload("res://extension/scenery.gd").new()
var maps: Array[Node3D] = []
var doors: Array[Dictionary] = []
var opened := [false,false]
var stages := [0,0]
var place := 0
var map_spawn := Vector3.ZERO
var prior_actor: CharacterBody3D
var prior_position := Vector3.ZERO
var old_patrol := {}
var original_title := ""
var original_objective := ""
var garden_sky := Sky.new()
var room_sky: Sky
var room_background: int
var loose_previous := {}
var waiting_props := {}
var map_font := FontFile.new()
var action_hint: Label
var transfer_delay := 0.0

func _ready() -> void:
	super._ready()
	map_font.data = FileAccess.get_file_as_bytes("res://extension/extension.otf")
	map_font.fallbacks = [preload("res://web/noto_sans_sc.ttf")]
	action_hint = _label(objective.get_parent(),objective.position+Vector2(0,28),"",15,map_font)
	action_hint.modulate = Color("#f4ce86")
	for origin in ORIGINS:
		maps.append(scenery.group(self,origin))
	for person in [actor,companion]:
		var mind = person.get_node("WanderMind")
		old_patrol[person] = mind.patrol.duplicate()
	scenery.library = preload("res://extension/furnishings.gd").new(self)
	scenery.reference_door = mouse_house.door
	room_sky = environment.sky
	room_background = environment.background_mode
	var sky_mat:=ShaderMaterial.new()
	sky_mat.shader=preload("res://extension/afternoon.gdshader")
	garden_sky.sky_material = sky_mat
	add_door(0,Vector3(-1.48,0.025,0.68),0.0,"客厅",0)
	maps[1].hide()
	maps[2].hide()

# 基类在场景就绪后延迟调用此方法。先装好首帧光照，避免先画一次未烘焙的房间。
func _initialize_gi() -> void:
	if ResourceLoader.exists("res://assets/lightmaps/room_v8.lmbake"):
		var baked: LightmapGIData = load("res://assets/lightmaps/room_v8.lmbake")
		var missing := PackedStringArray()
		for index in baked.get_user_count():
			if lightmap.get_node_or_null(baked.get_user_path(index)) == null:
				missing.append(str(baked.get_user_path(index)))
		if baked.get_user_count() > 0 and not baked.lightmap_textures.is_empty() and missing.is_empty():
			lightmap.light_data = _probe_lit_thin_details(baked)
			gi.visible = false
			for lamp in get_children():
				if lamp is Light3D and lamp.name != "WindowSun" and lamp.name != "WindowFill":
					lamp.shadow_enabled = false
		elif not missing.is_empty():
			push_warning("烘焙光照缺少场景节点：" + str(missing))
	if lightmap.light_data == null:
		lightmap.visible = false
	lightmap.specular_intensity = 0.55
	if light_controls != null:
		light_controls.history.sync_baked_shadows()
		light_controls.apply_values()
	# 初始化动作和碰撞体，让可操作的第一帧直接显示房间，实际碰撞时再播放特效。
	for person in [actor, companion]:
		person.prepare_action_effects()
	await RenderingServer.frame_post_draw
	ready_to_play = true
	actor.can_control = true
	_show_toast("寻找星光，探索墙后的小屋 · Alt 切换同伴",5)
	print("ROOM_READY visual_scale=0.405 lightmap=",lightmap.light_data!=null," gi_fallback=",gi.visible)

func _build_room() -> void:
	super._build_room()
	# 在原交互管理器初始化前登记，拾取、蓄力、碰撞声音与原件走同一条路径。
	var supplies := [
		[1,"cotton_reel",Vector3(-2.30,0.19,1.66)],
		[1,"marble_2",Vector3(-1.45,0.13,2.45)],
		[1,"yellow_pencil",Vector3(2.11,0.08,-1.15)],
		[2,"cotton_reel",Vector3(4.30,0.19,-2.90)],
		[2,"marble_3",Vector3(1.28,0.13,2.36)]
	]
	for row in supplies:
		var prototype: RigidBody3D = get_node(row[1])
		var body: RigidBody3D = prototype.duplicate(Node.DUPLICATE_SCRIPTS)
		body.name = "Map%d_%s" % [row[0],row[1]]
		body.position = ORIGINS[row[0]]+row[2]
		body.freeze = true
		add_child(body)
		body.set_meta("spawn_transform",body.transform)
		waiting_props[body] = row[0]
		physics_props.append(body)

func add_door(zone: int, point: Vector3, yaw: float, nameplate: String, link: int) -> void:
	var door: Dictionary = scenery.door(maps[zone],point,yaw,nameplate)
	door.zone = zone
	door.link = link
	doors.append(door)

func build_map(zone: int) -> void:
	if maps[zone].get_child_count()>0:
		return
	if zone==1:
		scenery.living(maps[1])
		add_door(1,Vector3(-1.08,0.025,4.85),PI,"玩具房",0)
		add_door(1,Vector3(4.15,0.025,-4.70),0.0,"庭院",1)
	elif zone==2:
		scenery.garden(maps[2])
		add_door(2,Vector3(0,0.025,5.02),PI,"客厅",1)

	for body in waiting_props.keys():
		if waiting_props[body]==zone:
			body.freeze = false
			body.sleeping = false
			waiting_props.erase(body)

func other_door(d: Dictionary) -> Dictionary:
	var dest := 1 if d.zone!=1 else (0 if d.link==0 else 2)
	build_map(dest)
	for candidate in doors:
		if candidate.zone==dest and candidate.link==d.link:
			return candidate
	return {}

# 越过门槛时用同一个刚体，只转换坐标、方向和速度。质量与接触材质仍由原物体持有。
func pass_loose_props() -> void:
	for body in physics_props:
		var now := body.global_position
		var previous: Vector3 = loose_previous.get(body,now)
		loose_previous[body] = now
		if body==prop_interaction.held or body.freeze or body.sleeping or previous.distance_squared_to(now)>4.0:
			continue
		for d in doors:
			if not opened[d.link] or d.block.collision_layer!=0 or now.distance_squared_to(d.frame.global_position)>3.8:
				continue
			var before: Vector3 = d.frame.to_local(previous)
			var after: Vector3 = d.frame.to_local(now)
			if before.z<=0 or after.z>0:
				continue
			var crossing := before.lerp(after,before.z/(before.z-after.z))
			if absf(crossing.x)>0.50 or crossing.y<0.015 or crossing.y>1.44:
				continue
			var peer := other_door(d)
			var turn: Basis = peer.frame.global_basis * Basis(Vector3.UP,PI) * d.frame.global_basis.inverse()
			var pose := Transform3D(turn*body.global_basis,peer.frame.to_global(Vector3(-after.x,after.y,0.25-after.z)))
			var velocity := turn*body.linear_velocity
			var spin := turn*body.angular_velocity
			body.global_transform=pose
			PhysicsServer3D.body_set_state(body.get_rid(),PhysicsServer3D.BODY_STATE_TRANSFORM,pose)
			body.linear_velocity=velocity
			body.angular_velocity=spin
			body.reset_physics_interpolation()
			loose_previous[body]=pose.origin
			break

func local_actor() -> Vector3:
	return actor.global_position - ORIGINS[place]

func nearby_door() -> Dictionary:
	for d in doors:
		if d.zone!=place:
			continue
		var pos: Vector3 = d.frame.to_local(actor.global_position)
		if absf(pos.x)<0.88 and pos.y>-0.18 and pos.y<1.45 and pos.z>-0.32 and pos.z<1.18:
			return d
	return {}

func at_station() -> bool:
	if place==0 or stages[place-1]>=3:
		return false
	var index := place-1
	var stage: int = stages[index]
	var pos := local_actor()
	var target: Vector3 = STATIONS[index][stage]
	if index==0 and ((stage==0 and pos.y<0.29) or (stage==2 and pos.y<0.49)):
		return false
	return (pos+Vector3.UP*0.23).distance_to(target)<(0.83 if index==0 and stage==0 else 1.03)

func extension_action() -> bool:
	if not ready_to_play or paused or web_layout_active or not actor.can_control or puzzles.book_open:
		return false
	var d := nearby_door()
	if not d.is_empty():
		var link: int = d.link
		var local: Vector3 = d.frame.to_local(actor.global_position)
		if opened[link] and absf(local.z)<0.24 and absf(local.x)<0.55:
			_show_toast("退开一步，就能关门",2)
			return true
		opened[link] = not opened[link]
		if sounds_enabled:
			d.sound.pitch_scale=1.15 if opened[link] else 0.9
			d.sound.play()
		return true
	if not at_station():
		return false
	var index := place-1
	stages[index] += 1
	if place==1:
		if stages[0]==1:
			scenery.wind_key.hide()
			_show_toast("发条到手了，落地钟在沙发右边",3)
		elif stages[0]==2:
			scenery.wind_key.position = Vector3(2.75,1.26,-3.30)
			scenery.wind_key.rotation.y = 0.0
			scenery.wind_key.show()
			_show_toast("发条咬住了齿轮，跳上沙发去拉报时绳",3)
		else:
			_show_toast("钟摆动起来了，客厅响起整点钟声",5)
	elif stages[1]==1:
		scenery.water.show()
		scenery.water.scale.x = 0.61
		scenery.valve.rotation.z = PI/3
		_show_toast("泵口出水了，木闸还拦着水流",3)
	elif stages[1]==2:
		scenery.water.scale.x = 1.0
		scenery.channel.position.y += 0.25
		_show_toast("水流进了花圃，去摇响架上的风铃",3)
	else:
		scenery.flowers.show()
		scenery.living_petals.show()
		_show_toast("风铃轻响，庭院的花都开了",5)
	if stages[index]==3:
		_victory_song()
	else:
		_tone(495+stages[index]*88,0.18,0.65)
	show_objective()
	return true

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode==KEY_E:
		if extension_action():
			get_viewport().set_input_as_handled()
			return
	super._unhandled_input(event)

func _web_context_action() -> void:
	if not extension_action():
		super._web_context_action()

func show_objective() -> void:
	var display_font: Font = preload("res://web/noto_sans_sc.ttf") if place==0 else map_font
	for widget in [title,objective,toast]:
		widget.add_theme_font_override("font",display_font)
	playground.quest.visible = place==0
	if place==0:
		title.text = original_title
		objective.text = original_objective
	else:
		title.text = PLACES[place]
		var route: Array = CLOCK_ROUTE if place==1 else FLOWER_ROUTE
		var step: int = stages[place-1]
		objective.text = ("%s  ·  %s" % ["午后的钟声" if place==1 else "风铃花圃", route[step]])

func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	if not ready_to_play or paused:
		return
	transfer_delay = maxf(0.0,transfer_delay-delta)
	for d in doors:
		var is_open: bool = opened[d.link]
		d.swing=move_toward(d.swing,1.0 if is_open else 0.0,delta/0.62)
		var angle: float = deg_to_rad(88.0)*smoothstep(0.0,1.0,d.swing)
		d.leaf.rotation.y = angle
		d.block.collision_layer = 0 if is_open and angle>1.2 else 1
		if d.zone!=place or transfer_delay>0 or prior_actor!=actor or d.block.collision_layer!=0 or not is_open:
			continue
		var now: Vector3 = d.frame.to_local(actor.global_position)
		var previous: Vector3 = d.frame.to_local(prior_position)
		if absf(now.x)<0.49 and now.y>=-0.12 and now.y<1.4 and now.z<=0.09 and previous.z>0.09:
			enter_door(d)
			break
	pass_loose_props()
	prior_position = actor.global_position
	prior_actor = actor

func enter_door(d: Dictionary) -> void:
	if actor.stunt_mode!="" or companion.stunt_mode!="" or train.seated or iron_ball.pushing or puzzles.is_pulling(actor) or puzzles.is_pulling(companion):
		_show_toast("先结束手边的动作，再穿过门",2)
		return
	var peer := other_door(d)
	var dest: int = peer.zone
	if place==0:
		original_title = title.text
		original_objective = objective.text
	maps[place].hide()
	place = dest
	maps[place].show()
	var frame: Node3D = peer.frame
	peer.swing = 1.0
	peer.leaf.rotation.y = deg_to_rad(88.0)
	peer.block.collision_layer = 0
	map_spawn = frame.to_global(Vector3(0,0.065,0.82))
	var turn: Basis = frame.global_basis * Basis(Vector3.UP,PI) * d.frame.global_basis.inverse()
	var carry_from := actor.global_position
	var heading := turn*Vector3(cos(actor.heading_yaw),0,-sin(actor.heading_yaw))
	var viewer := turn*Vector3(sin(camera_yaw),0,cos(camera_yaw))
	var arrival_velocity := turn*actor.velocity
	if prop_interaction.held!=null:
		var item: RigidBody3D = prop_interaction.held
		var carried := Transform3D(turn*item.global_basis,map_spawn+turn*(item.global_position-carry_from))
		prop_interaction._set_held_transform(carried)
		prop_interaction.last_good_transform = carried
		prop_interaction.arm_target = carried.origin
		item.reset_physics_interpolation()
	for person in [actor,companion]:
		var target := map_spawn if person==actor else frame.to_global(Vector3(0.62,0.065,1.03))
		person.global_position = target
		person.velocity = arrival_velocity if person==actor else Vector3.ZERO
		person.reset_physics_interpolation()
		var mind = person.get_node("WanderMind")
		mind.command_cancel()
		if mind.manual_hold:
			mind.manual_anchor = target
		mind.pause_left = 2.5
		if place==0:
			mind.patrol = old_patrol[person].duplicate()
		else:
			mind.patrol = [ORIGINS[place]+Vector3(-1.5,0,1),ORIGINS[place]+Vector3(1.6,0,0.4),ORIGINS[place]+Vector3(0.8,0,-1.3)]
	transfer_delay = 0.38
	environment.background_mode = Environment.BG_SKY if place==2 else room_background
	environment.sky = garden_sky if place==2 else room_sky
	camera_yaw = atan2(viewer.x,viewer.z)
	actor.heading_yaw = atan2(-heading.z,heading.x)
	actor.visual.rotation.y = actor.heading_yaw
	snap_camera()
	show_objective()
	_show_toast("回到玩具房" if place==0 else "来到"+PLACES[place],2.2)

func snap_camera() -> void:
	camera_focus = actor.global_position+Vector3.UP*0.30
	camera.position = camera_focus+Vector3(sin(camera_yaw)*0.7,0.56,cos(camera_yaw)*0.7)
	camera.look_at(camera_focus)
	camera.reset_physics_interpolation()

func _update_camera(delta: float) -> void:
	if place==0 or not overview:
		super._update_camera(delta)
	else:
		camera.position = ORIGINS[place]+Vector3(4.3,4.0,4.45)
		camera.look_at(ORIGINS[place]+Vector3(0,0.35,-0.50))
		camera.fov = 58

func _respawn() -> void:
	if place==0:
		super._respawn()
	else:
		if prop_interaction.held!=null:
			prop_interaction.drop()
		actor.reset_position()
		actor.global_position = map_spawn
		actor.velocity = Vector3.ZERO
		actor.reset_physics_interpolation()
		actor.can_control = true
		snap_camera()
		_show_toast("回到"+PLACES[place]+"门旁",2)

func _process(delta: float) -> void:
	super._process(delta)
	if action_hint==null or not ready_to_play or paused:
		return
	scenery.library.sync_quality(quality_surfaces.active_ultra)
	if place==1:
		if stages[0]==0:
			scenery.wind_key.rotation.y += delta*0.85
		elif stages[0]==3:
			scenery.clock_pivot.rotation.z = sin(elapsed*3.4)*0.19
			scenery.minute_hand.rotation.z -= delta*0.08
	elif place==2 and stages[1]==3:
		scenery.chimes.rotation.z = sin(elapsed*2.8)*0.07
	var key := "互动" if web_touch_mode else "E"
	var d := nearby_door()
	var words := ""
	if not d.is_empty():
		words = (key+" 关门  ·  向门内走可穿过") if opened[d.link] else (key+" 开门")
	elif at_station():
		words = key+" "+ACTIONS[place-1][stages[place-1]]
	action_hint.text = words
