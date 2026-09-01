class_name WorldBuilder
extends RefCounted
## Shared helpers every mini-game uses to set up its arena (sky,
## sun, ground) and spawn the shared player character, so a new
## game script only has to write its own rules, not re-build the
## world from scratch each time.

const PLAYER_SCENE := "res://scenes/Player.tscn"


static func build_sky_environment(parent: Node) -> WorldEnvironment:
	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color(0.3, 0.5, 0.85)
	sky_material.sky_horizon_color = Color(0.75, 0.82, 0.9)
	sky_material.ground_bottom_color = Color(0.3, 0.28, 0.25)
	sky_material.ground_horizon_color = Color(0.6, 0.6, 0.55)

	var sky := Sky.new()
	sky.sky_material = sky_material

	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.8
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.glow_enabled = true
	env.ssao_enabled = true
	env.fog_enabled = true
	env.fog_light_color = Color(0.75, 0.82, 0.9)
	env.fog_density = 0.0025

	# Light cinematic color grading -- costs almost nothing on weak
	# GPUs but reads as noticeably more "finished" than flat defaults.
	env.adjustment_enabled = true
	env.adjustment_brightness = 1.02
	env.adjustment_contrast = 1.08
	env.adjustment_saturation = 1.12

	var world_env := WorldEnvironment.new()
	world_env.environment = env
	parent.add_child(world_env)
	return world_env


static func build_sun(parent: Node) -> DirectionalLight3D:
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-50, -30, 0)
	light.light_energy = 1.2
	light.shadow_enabled = true
	parent.add_child(light)
	return light


static func build_ground(parent: Node, size: float = 80.0, color: Color = Color(0.25, 0.5, 0.28)) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = "Ground"
	parent.add_child(body)

	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(size, 1, size)
	collision.shape = shape
	collision.position.y = -0.5
	body.add_child(collision)

	var mesh_instance := MeshInstance3D.new()
	var mesh := PlaneMesh.new()
	mesh.size = Vector2(size, size)
	mesh.subdivide_width = 20
	mesh.subdivide_depth = 20

	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.9
	mesh.material = material

	mesh_instance.mesh = mesh
	body.add_child(mesh_instance)
	return body


## Encloses a size x size play area with four collidable walls, so an
## arena reads as an actual room instead of an open field.
static func build_walls(parent: Node, size: float = 80.0, height: float = 14.0, thickness: float = 2.0, color: Color = Color(0.82, 0.8, 0.76)) -> Node3D:
	var walls := Node3D.new()
	walls.name = "Walls"
	parent.add_child(walls)

	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.85

	var half := size / 2.0
	var configs := [
		{"pos": Vector3(0, height / 2.0, -half - thickness / 2.0), "size": Vector3(size + thickness * 2.0, height, thickness)},
		{"pos": Vector3(0, height / 2.0, half + thickness / 2.0), "size": Vector3(size + thickness * 2.0, height, thickness)},
		{"pos": Vector3(-half - thickness / 2.0, height / 2.0, 0), "size": Vector3(thickness, height, size)},
		{"pos": Vector3(half + thickness / 2.0, height / 2.0, 0), "size": Vector3(thickness, height, size)},
	]

	for config in configs:
		var body := StaticBody3D.new()
		walls.add_child(body)

		var collision := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = config["size"]
		collision.shape = shape
		body.add_child(collision)

		var mesh_instance := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = config["size"]
		mesh.material = material
		mesh_instance.mesh = mesh
		body.add_child(mesh_instance)

		body.position = config["pos"]

	return walls


static func spawn_player(parent: Node, spawn_position: Vector3) -> CharacterBody3D:
	var player_scene: PackedScene = load(PLAYER_SCENE)
	var player: CharacterBody3D = player_scene.instantiate()
	player.position = spawn_position
	parent.add_child(player)
	return player


## Applies the logged-in account's saved outfit colors (Auth.customization)
## to a freshly-spawned character -- called after every spawn site
## (Lobby solo/networked, the game's solo/networked) so a customized
## look follows the player everywhere, not just where they set it.
static func apply_customization(player: CharacterBody3D) -> void:
	for part in Auth.customization:
		player.set_outfit_color(part, Color(String(Auth.customization[part])))


static func find_animation_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node
	for child in node.get_children():
		var found := find_animation_player(child)
		if found:
			return found
	return null


static func find_mesh_instance(node: Node) -> MeshInstance3D:
	if node is MeshInstance3D:
		return node
	for child in node.get_children():
		var found := find_mesh_instance(child)
		if found:
			return found
	return null


static func find_child_by_name(node: Node, target_name: String) -> Node:
	if node.name == target_name:
		return node
	for child in node.get_children():
		var found := find_child_by_name(child, target_name)
		if found:
			return found
	return null


## Generates a matching collision shape for a named mesh (found
## anywhere under root) so imported scenery becomes solid to walk
## on/into, since a plain glTF import has no physics on its own.
static func add_collision_for(root: Node, mesh_node_name: String) -> void:
	var container := find_child_by_name(root, mesh_node_name)
	if container == null:
		return
	var mesh_instance := find_mesh_instance(container)
	if mesh_instance:
		mesh_instance.create_trimesh_collision()
