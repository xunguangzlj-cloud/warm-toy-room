extends RefCounted

var source: Node3D
var links: Array = []
var previous_quality: bool

func _init(game: Node3D) -> void:
	source = game.room
	previous_quality = game.quality_surfaces.active_ultra

func copy_visual(original: MeshInstance3D, target: MeshInstance3D) -> void:
	target.mesh = original.mesh
	target.material_override = original.material_override
	for i in original.mesh.get_surface_count():
		target.set_surface_override_material(i,original.get_surface_override_material(i))
	target.cast_shadow = original.cast_shadow
	if target.get_meta("living_rug",false):
		for i in target.mesh.get_surface_count():
			var fabric:=original.get_active_material(i)
			if fabric is BaseMaterial3D:
				var woven:=fabric.duplicate() as BaseMaterial3D
				woven.albedo_color=woven.albedo_color*Color("#cec2b6")
				target.set_surface_override_material(i,woven)
			elif fabric is ShaderMaterial and fabric.get_shader_parameter("tint") is Color:
				var woven:=fabric.duplicate() as ShaderMaterial
				woven.set_shader_parameter("tint",woven.get_shader_parameter("tint")*Color("#cec2b6"))
				target.set_surface_override_material(i,woven)

func sync_quality(ultra: bool) -> void:
	if previous_quality == ultra:
		return
	previous_quality = ultra
	for pair in links:
		copy_visual(pair[0],pair[1])

# 用原件在世界中的实际朝向排布。宽高为零时沿用原尺寸。
func furnish(parent: Node3D, path: String, anchor: Vector3, size: Vector3, contacts := false, align_top := false, uniform := false) -> Node3D:
	var original: Node3D = source.get_node(path)
	var geometry := original.find_children("*","MeshInstance3D",true,false)
	if original is MeshInstance3D:
		geometry.push_front(original)
	var found := false
	var bounds := AABB()
	var display := Node3D.new()
	parent.add_child(display)
	display.name = original.name
	for m in geometry:
		if m.mesh == null or not m.is_visible_in_tree():
			continue
		# 原导出的楼板与地毯也含散落玩具；这里只取各自的建筑和织物表面。
		if path=="Props/Floor" and not ("Oak" in str(m.name) or "Deep seams" in str(m.name)):
			continue
		if path=="Props/Rug" and not ("Antique woven rug" in str(m.name) or "Soft cotton ivory" in str(m.name)):
			continue
		var part: AABB = m.global_transform*m.get_aabb()
		bounds = bounds.merge(part) if found else part
		found = true
		var instance := MeshInstance3D.new()
		display.add_child(instance)
		instance.transform=m.global_transform
		if path=="Props/Rug":
			instance.set_meta("living_rug",true)
		copy_visual(m,instance)
		links.append([m,instance])
	if not found:
		return display
	var ratio := Vector3.ONE
	for axis in 3:
		if size[axis]>0.0 and bounds.size[axis]>0.001:
			ratio[axis] = size[axis]/bounds.size[axis]
	if uniform:
		ratio=Vector3.ONE*ratio.x
	var center := bounds.get_center()
	center.y = bounds.end.y if align_top else bounds.position.y
	display.scale = ratio
	display.position = anchor-center*ratio
	if contacts:
		# 对可踩踏物沿用原碰撞体，包括藤篮的中空内壁。
		for body in original.find_children("*","StaticBody3D",true,false):
			if body.collision_layer==0:
				continue
			var replica := StaticBody3D.new()
			display.add_child(replica)
			replica.transform=body.global_transform
			replica.collision_layer=body.collision_layer
			replica.collision_mask=body.collision_mask
			replica.physics_material_override=body.physics_material_override
			for cs in body.get_children():
				if cs is CollisionShape3D and not cs.disabled:
					var contact := CollisionShape3D.new()
					contact.shape=cs.shape
					replica.add_child(contact)
					contact.transform=cs.transform
	return display
