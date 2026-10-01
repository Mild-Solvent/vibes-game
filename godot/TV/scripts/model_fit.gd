extends RefCounted
## Fits an imported model (.glb) into a box, so art can replace a grey-box shape without
## touching its collider: the model is scaled to the box and sits on the box's bottom face.


## Returns a node holding the model, centred on x/z with its bottom at -size.y / 2 (where a
## BoxMesh of `size` would sit). `yaw` turns the model first. Uniform scale keeps proportions;
## `stretch` scales each axis to fill the box exactly.
static func fit(path: String, size: Vector3, yaw := 0.0, stretch := false) -> Node3D:
	# holder (scaled, offset) -> model (turned), so the scale applies to the turned model's axes.
	var holder := Node3D.new()
	holder.name = "Model"
	var model: Node3D = load(path).instantiate()
	fix_materials(model)
	model.rotation.y = yaw
	holder.add_child(model)

	var bounds := _bounds(model, model.transform)
	if bounds.size.x <= 0.0 or bounds.size.y <= 0.0 or bounds.size.z <= 0.0:
		return holder
	var ratio := size / bounds.size
	var scale := ratio if stretch else Vector3.ONE * minf(ratio.x, minf(ratio.y, ratio.z))
	var centre := bounds.get_center()
	holder.scale = scale
	holder.position = Vector3(-centre.x * scale.x, -size.y / 2.0 - bounds.position.y * scale.y, -centre.z * scale.z)
	return holder


## Some Kenney packs (the ones without a colormap) import fully metallic, which turns them into
## washed-out, sky-coloured mirrors. Make them matte. Materials are shared, so this sticks.
static func fix_materials(node: Node) -> void:
	for mesh_instance in node.find_children("*", "MeshInstance3D", true, false):
		var mesh: Mesh = mesh_instance.mesh
		if mesh == null:
			continue
		for i in mesh.get_surface_count():
			var mat := mesh.surface_get_material(i) as StandardMaterial3D
			if mat and mat.metallic > 0.0:
				mat.metallic = 0.0
				mat.roughness = 1.0


## The bounding box of `node` and everything under it, in `node`'s own space.
static func bounds(node: Node3D) -> AABB:
	return _bounds(node, Transform3D.IDENTITY)


## The model's bounding box in its parent's space, before scaling.
static func _bounds(node: Node, xform: Transform3D) -> AABB:
	var result := AABB()
	var found := false
	if node is VisualInstance3D:
		result = xform * (node as VisualInstance3D).get_aabb()
		found = true
	for child in node.get_children():
		if not child is Node3D:
			continue
		var child_bounds := _bounds(child, xform * (child as Node3D).transform)
		if child_bounds.size == Vector3.ZERO:
			continue
		result = child_bounds if not found else result.merge(child_bounds)
		found = true
	return result
