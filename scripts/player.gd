extends CharacterBody3D
## Shared third-person character controller, reusable across every
## mini-game in the project (not just one game mode).
## Left stick = move, right stick = camera, R2 (analog) = sprint
## (proportional, like the FC26 sprint trigger), Cross/A = jump.
## WASD + Shift + Space work too, for testing without a controller.
##
## A game-mode script drives higher-level rules from the outside via
## freeze()/unfreeze() and play_animation(name) -- it never needs to
## know how movement or animation blending work internally.

const WALK_SPEED := 4.0
const SPRINT_SPEED := 9.0
const JUMP_VELOCITY := 5.5
const GRAVITY := 18.0
const GROUND_ACCEL := 10.0
const AIR_ACCEL := 3.0
const TURN_SPEED := 10.0
const STICK_DEADZONE := 0.15
const ANIM_BLEND := 0.2
const RUN_ANIM_THRESHOLD := 0.5

const ANIM_IDLE := "Idle"
const ANIM_WALK := "Walk"
const ANIM_RUN := "Run"
const ANIM_JUMP := "Jump"

const FOOTSTEP_SOUND := "res://assets/audio/footstep.wav"
const FOOTSTEP_INTERVAL_WALK := 0.48
const FOOTSTEP_INTERVAL_RUN := 0.26

## Which character model this instance wears. Swap this per-instance
## (or expose a picker later) to reuse the same controller for a
## different-looking character without touching any movement code.
@export var model_scene_path := "res://assets/characters/Casual_Male.gltf"

## Shown on the floating nameplate above the character's head, and
## meant to double as the identity used for social features (friend
## requests, etc.) once accounts exist.
@export var username := "Player":
	set(value):
		username = value
		if nameplate:
			nameplate.text = value

# Surface indices on this character pack's model (Skin, Shirt, Pants,
# Belt, Face, Hair, in that fixed order) that set_outfit_color() can
# retint for character customization.
const OUTFIT_SURFACES := {
	"skin": 0,
	"shirt": 1,
	"pants": 2,
	"belt": 3,
	"hair": 5,
}

var camera_yaw := 0.0
var camera_pitch := -20.0

var model: Node3D
var mesh_instance: MeshInstance3D
var anim_player: AnimationPlayer
var spring_arm: SpringArm3D
var camera: Camera3D
var footstep_player: AudioStreamPlayer3D
var nameplate: Label3D

var current_anim := ""
var footstep_timer := 0.0

const BASE_FOV := 65.0
const SPRINT_FOV := 74.0

var shake_time_left := 0.0
var shake_strength := 0.0

## True while the left stick / WASD is being pushed, regardless of
## how much residual velocity is left over from acceleration smoothing.
## Games that care about "is the player trying to move" (Red Light /
## Green Light, stealth, etc.) should check this instead of raw speed.
var is_input_active := false

## When true, movement/camera/animation-state input is ignored, but
## external code can still drive animations directly via play_animation().
## A game-mode script sets this for cutscenes, eliminations, victories, etc.
var frozen := false


func _ready() -> void:
	_build_body()


func _build_body() -> void:
	var collision := CollisionShape3D.new()
	var capsule_shape := CapsuleShape3D.new()
	capsule_shape.radius = 0.4
	capsule_shape.height = 1.8
	collision.shape = capsule_shape
	collision.position.y = 0.9
	add_child(collision)

	var model_scene: PackedScene = load(model_scene_path)
	model = model_scene.instantiate()
	add_child(model)
	anim_player = WorldBuilder.find_animation_player(model)
	mesh_instance = WorldBuilder.find_mesh_instance(model)
	_enable_looping(anim_player, [ANIM_IDLE, ANIM_WALK, ANIM_RUN])

	nameplate = Label3D.new()
	nameplate.text = username
	nameplate.position.y = 2.1
	nameplate.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	nameplate.no_depth_test = true
	nameplate.font_size = 56
	nameplate.outline_size = 10
	nameplate.modulate = Color(1, 1, 1)
	nameplate.outline_modulate = Color(0, 0, 0, 0.9)
	add_child(nameplate)

	spring_arm = SpringArm3D.new()
	spring_arm.position.y = 1.6
	spring_arm.spring_length = 6.0
	spring_arm.rotation_degrees.x = camera_pitch
	var probe_shape := SphereShape3D.new()
	probe_shape.radius = 0.3
	spring_arm.shape = probe_shape
	add_child(spring_arm)

	camera = Camera3D.new()
	# Only your own character's camera should ever be active. With no
	# multiplayer peer set (single-player), is_multiplayer_authority()
	# is true for every node, so this is unaffected outside netplay.
	camera.current = is_multiplayer_authority()
	camera.fov = BASE_FOV
	spring_arm.add_child(camera)

	footstep_player = AudioStreamPlayer3D.new()
	footstep_player.stream = load(FOOTSTEP_SOUND)
	footstep_player.unit_size = 6.0
	add_child(footstep_player)

	_build_network_sync()


func _enable_looping(player: AnimationPlayer, anim_names: Array) -> void:
	if player == null:
		return
	for anim_name in anim_names:
		if player.has_animation(anim_name):
			player.get_animation(anim_name).loop_mode = Animation.LOOP_LINEAR


## Replicates position, facing, current animation, and movement-intent
## from whichever peer owns this character to every other peer. With
## no multiplayer peer active (single-player), this sits idle and
## changes nothing.
func _build_network_sync() -> void:
	var synchronizer := MultiplayerSynchronizer.new()
	var config := SceneReplicationConfig.new()
	config.add_property(NodePath(".:position"))
	config.add_property(NodePath(str(model.name) + ":rotation"))
	config.add_property(NodePath(".:current_anim"))
	config.add_property(NodePath(".:is_input_active"))
	synchronizer.replication_config = config
	add_child(synchronizer)


func _physics_process(delta: float) -> void:
	if frozen:
		return
	if not is_multiplayer_authority():
		# Someone else's character: just mirror their synced animation
		# state locally -- their own client owns movement/position.
		_apply_synced_animation()
		return
	_update_camera(delta)
	var move_state := _update_movement(delta)
	move_and_slide()
	_update_animation(move_state)
	_update_footsteps(move_state, delta)
	_update_sprint_fov(move_state, delta)
	_apply_synced_animation()


func _apply_synced_animation() -> void:
	if anim_player == null or current_anim.is_empty():
		return
	if anim_player.current_animation != current_anim and anim_player.has_animation(current_anim):
		anim_player.play(current_anim, ANIM_BLEND)


## Runs even while frozen, so an elimination/impact shake still plays
## out on top of a freeze() call.
func _process(delta: float) -> void:
	if shake_time_left <= 0.0:
		return
	shake_time_left -= delta
	if shake_time_left <= 0.0:
		camera.h_offset = 0.0
		camera.v_offset = 0.0
		return
	camera.h_offset = randf_range(-1.0, 1.0) * shake_strength
	camera.v_offset = randf_range(-1.0, 1.0) * shake_strength


## Briefly jitters the camera -- used by game-mode scripts for impacts,
## eliminations, explosions, or any other "hit" feedback.
func shake_camera(strength: float = 0.15, duration: float = 0.35) -> void:
	shake_strength = strength
	shake_time_left = duration


## Retints one outfit part ("skin", "shirt", "pants", "belt", "hair")
## for character customization. Face is deliberately left out -- it
## shares the head's UVs/detail, so recoloring it doesn't read as a
## skin tone change, just a discolored face.
func set_outfit_color(part: String, color: Color) -> void:
	if mesh_instance == null or not OUTFIT_SURFACES.has(part):
		return
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	mesh_instance.set_surface_override_material(OUTFIT_SURFACES[part], material)


## Stops the character from moving/turning and freezes the automatic
## Idle/Walk/Run/Jump animation state machine. Call play_animation()
## afterwards to show a specific pose (death, victory, a cutscene, etc.).
func freeze() -> void:
	frozen = true
	is_input_active = false


## Hands control back to the player and resumes automatic animation.
func unfreeze() -> void:
	frozen = false
	current_anim = ""


## Plays any animation this character has by name -- used by game-mode
## scripts for anything the built-in state machine doesn't cover
## (death, victory, emotes, interactions, future combat moves, etc.).
func play_animation(anim_name: String, blend: float = ANIM_BLEND) -> void:
	if anim_player and anim_player.has_animation(anim_name):
		anim_player.play(anim_name, blend)
		current_anim = anim_name


func _update_camera(delta: float) -> void:
	var look_x := Input.get_joy_axis(0, JOY_AXIS_RIGHT_X)
	var look_y := Input.get_joy_axis(0, JOY_AXIS_RIGHT_Y)
	if abs(look_x) < STICK_DEADZONE:
		look_x = 0.0
	if abs(look_y) < STICK_DEADZONE:
		look_y = 0.0

	camera_yaw -= look_x * 120.0 * delta
	camera_pitch = clamp(camera_pitch - look_y * 90.0 * delta, -60.0, 20.0)

	spring_arm.rotation_degrees.y = camera_yaw
	spring_arm.rotation_degrees.x = camera_pitch


func _update_movement(delta: float) -> Dictionary:
	var move_x := Input.get_joy_axis(0, JOY_AXIS_LEFT_X)
	var move_y := Input.get_joy_axis(0, JOY_AXIS_LEFT_Y)

	# Keyboard fallback so movement can be tested without a controller plugged in.
	if Input.is_key_pressed(KEY_A):
		move_x -= 1.0
	if Input.is_key_pressed(KEY_D):
		move_x += 1.0
	if Input.is_key_pressed(KEY_W):
		move_y -= 1.0
	if Input.is_key_pressed(KEY_S):
		move_y += 1.0

	var input_vec := Vector2(move_x, move_y)
	if input_vec.length() < STICK_DEADZONE:
		input_vec = Vector2.ZERO
	else:
		input_vec = input_vec.normalized() * clamp(input_vec.length(), 0.0, 1.0)
	is_input_active = input_vec.length() > 0.0

	# R2 is an analog trigger (0.0 to 1.0), so sprint ramps in smoothly
	# instead of snapping, the same feel as the FC26 sprint trigger.
	var sprint_amount := Input.get_joy_axis(0, JOY_AXIS_TRIGGER_RIGHT)
	if Input.is_key_pressed(KEY_SHIFT):
		sprint_amount = 1.0
	var target_speed: float = lerp(WALK_SPEED, SPRINT_SPEED, clamp(sprint_amount, 0.0, 1.0))

	var cam_basis := spring_arm.global_transform.basis
	var forward := -cam_basis.z
	var right := cam_basis.x
	forward.y = 0.0
	forward = forward.normalized()
	right.y = 0.0
	right = right.normalized()

	var direction := (right * input_vec.x - forward * input_vec.y)
	if direction.length() > 0.01:
		direction = direction.normalized()

	var horizontal_velocity := Vector3(velocity.x, 0.0, velocity.z)
	var target_velocity := direction * target_speed
	var accel := GROUND_ACCEL if is_on_floor() else AIR_ACCEL
	horizontal_velocity = horizontal_velocity.lerp(target_velocity, clamp(accel * delta, 0.0, 1.0))

	velocity.x = horizontal_velocity.x
	velocity.z = horizontal_velocity.z

	if direction.length() > 0.01:
		var target_angle := atan2(direction.x, direction.z)
		model.rotation.y = lerp_angle(model.rotation.y, target_angle, TURN_SPEED * delta)

	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	elif Input.is_joy_button_pressed(0, JOY_BUTTON_A) or Input.is_key_pressed(KEY_SPACE):
		velocity.y = JUMP_VELOCITY

	return {
		"is_moving": direction.length() > 0.01,
		"sprint_amount": sprint_amount,
	}


func _update_animation(move_state: Dictionary) -> void:
	if anim_player == null:
		return

	var next_anim := ANIM_IDLE
	if not is_on_floor():
		next_anim = ANIM_JUMP
	elif move_state["is_moving"]:
		next_anim = ANIM_RUN if move_state["sprint_amount"] > RUN_ANIM_THRESHOLD else ANIM_WALK

	if next_anim != current_anim and anim_player.has_animation(next_anim):
		anim_player.play(next_anim, ANIM_BLEND)
		current_anim = next_anim


func _update_footsteps(move_state: Dictionary, delta: float) -> void:
	var is_walking_or_running: bool = is_on_floor() and move_state["is_moving"]
	if not is_walking_or_running:
		footstep_timer = 0.0
		return

	footstep_timer -= delta
	if footstep_timer <= 0.0:
		footstep_player.pitch_scale = randf_range(0.92, 1.08)
		footstep_player.play()
		var sprint_amount: float = move_state["sprint_amount"]
		footstep_timer = lerp(FOOTSTEP_INTERVAL_WALK, FOOTSTEP_INTERVAL_RUN, clamp(sprint_amount, 0.0, 1.0))


## Widens the FOV slightly while sprinting -- a cheap, common trick
## that sells a sense of speed without any extra rendering cost.
func _update_sprint_fov(move_state: Dictionary, delta: float) -> void:
	var sprint_amount: float = move_state["sprint_amount"]
	var target_fov: float = lerp(BASE_FOV, SPRINT_FOV, clamp(sprint_amount, 0.0, 1.0))
	camera.fov = lerp(camera.fov, target_fov, clamp(6.0 * delta, 0.0, 1.0))
