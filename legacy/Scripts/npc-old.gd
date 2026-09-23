extends Area2D

signal hailed(faction, npc_name)

@export var npc_faction = "Villagers of Lumora"
@export var npc_name: String = "Villager Timot": set = _set_npc_name

@onready var detection_zone = $DetectionZone
@onready var facing_ray_cast = $RayCast2D
@onready var animated_sprite = $AnimatedSprite2D
@onready var name_label = $NameLabel

var player_pos: Vector2 = Vector2.ZERO
var player_node: CharacterBody2D = null
var player_in_range = false

func _ready():
	if name_label:
		_set_npc_name(npc_name)
		_update_label_position()
	else:
		print("ERROR: NameLabel node not found as child of NPC: ", name)

	if detection_zone:
		detection_zone.body_entered.connect(_on_detection_zone_body_entered)
		detection_zone.body_exited.connect(_on_detection_zone_body_exited)
		print("DetectionZone signals connected for NPC: ", name)
	else:
		print("ERROR: DetectionZone node not found as child of NPC: ", name)

	if facing_ray_cast:
		facing_ray_cast.add_exception(self)
		facing_ray_cast.enabled = false
		print("FacingRayCast initialized for NPC: ", name)
	else:
		print("ERROR: RayCast2D node not found as child of NPC: ", name)

	var players = get_tree().get_nodes_in_group("player")
	if players.size() > 0:
		player_node = players[0] as CharacterBody2D
		print("Connected to player node for NPC: ", name)
	else:
		print("WARNING: Player not found in 'player' group for NPC: ", name)

func _set_npc_name(value: String):
	npc_name = value
	if name_label:
		name_label.text = npc_name
		_update_label_position()

func _update_label_position():
	if name_label and animated_sprite and animated_sprite.sprite_frames and animated_sprite.sprite_frames.has_animation("Idle"):
		var texture_height = animated_sprite.sprite_frames.get_frame_texture("Idle", 0).get_size().y
		name_label.position = Vector2(-name_label.size.x / 2, -texture_height - 20)
	else:
		print("ERROR: Cannot update label position due to missing sprite or animation for NPC: ", name)

func _input(event):
	# Only react to "hail" action if chat is not active and player is in range
	if Global.is_chat_active:
		return

	if event.is_action_pressed("hail") and player_in_range:
		if not player_node:
			return

		player_pos = player_node.global_position
		var npc_pos = global_position
		var vector_npc_to_player = (player_pos - npc_pos).normalized()
		var vector_player_to_npc = (npc_pos - player_pos).normalized()
		var player_facing = player_node.get_last_direction()

		if animated_sprite:
			animated_sprite.flip_h = vector_npc_to_player.x < 0

		if player_facing.dot(vector_player_to_npc) > 0.5:
			facing_ray_cast.target_position = to_local(player_pos)
			facing_ray_cast.enabled = true
			facing_ray_cast.force_raycast_update()

			if facing_ray_cast.is_colliding():
				var collider = facing_ray_cast.get_collider()
				if collider and collider.get_instance_id() == player_node.get_instance_id():
					hailed.emit(npc_faction, npc_name)

			facing_ray_cast.enabled = false

func _on_detection_zone_body_entered(body: Node):
	if body.is_in_group("player"):
		player_in_range = true
		print("NPC: Player entered detection zone for ", npc_name)

func _on_detection_zone_body_exited(body: Node):
	if body.is_in_group("player"):
		player_in_range = false
		print("NPC: Player exited detection zone for ", npc_name)
