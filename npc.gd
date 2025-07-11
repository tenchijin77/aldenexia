extends Area2D

signal hailed(faction, npc_name)

@export var npc_faction = "Villagers of Lumora"
@export var npc_name = "Villager Timot" # Updated to Timot

@onready var detection_zone = $DetectionZone # Assuming DetectionZone is a child Area2D
@onready var facing_ray_cast = $RayCast2D # Assuming RayCast2D is a child RayCast2D
@onready var animated_sprite = $AnimatedSprite2D # Make sure you have this node, as per previous discussions

# This will be replaced by the player's actual global position
var player_pos: Vector2 = Vector2.ZERO 
var player_node: CharacterBody2D = null # Explicitly type as CharacterBody2D

var player_in_range = false # Boolean to track if player is in detection zone

func _ready():
	# Connect to the detection zone signals
	if detection_zone:
		detection_zone.body_entered.connect(_on_detection_zone_body_entered)
		detection_zone.body_exited.connect(_on_detection_zone_body_exited)
		print("DetectionZone signals connected.")
	else:
		print("ERROR: DetectionZone node not found as child of NPC!")

	if facing_ray_cast:
		facing_ray_cast.add_exception(self) # Exclude self from raycast hits
		facing_ray_cast.enabled = false # Disable by default, enable for check
		print("FacingRayCast initialized.")
	else:
		print("ERROR: RayCast2D node not found as child of NPC!")
	
	# Ensure player node is found and connected for hailing logic
	var players = get_tree().get_nodes_in_group("player")
	if players.size() > 0:
		player_node = players[0] as CharacterBody2D # Cast to CharacterBody2D
		print("Connected to NPC: ", name) # Confirm NPC is ready and connected
	else:
		print("WARNING: Player not found in 'player' group. Cannot connect for facing check.")

func _input(event):
	# Only process if 'hail' action is pressed and player is in range
	if event.is_action_pressed("hail") and player_in_range:
		print("DEBUG: 'Hail' action pressed. Player in range:", player_in_range)

		if player_node:
			player_pos = player_node.global_position # Get player's current global position
			var npc_pos = global_position # NPC's root Area2D global position

			# Vector FROM NPC TO Player (used for NPC's own facing logic)
			var vector_npc_to_player = (player_pos - npc_pos).normalized()
			print("DEBUG: Vector FROM NPC TO Player (for NPC's logic):", vector_npc_to_player)

			# Vector FROM Player TO NPC (used for checking if player is facing the NPC)
			var vector_player_to_npc = (npc_pos - player_pos).normalized()
			print("DEBUG: Vector FROM Player TO NPC (for player facing check):", vector_player_to_npc)

			var player_facing = player_node.get_last_direction()
			
			print("DEBUG: Player Facing:", player_facing)

			# NPC flipping logic (to make NPC face the player)
			# Assumes NPC's default sprite faces right. If your NPC's sprite defaults to facing left, reverse true/false.
			if animated_sprite: # Ensure animated_sprite exists
				if vector_npc_to_player.x < 0: # Player is to NPC's left, NPC should face left
					animated_sprite.flip_h = true
				elif vector_npc_to_player.x > 0: # Player is to NPC's right, NPC should face right
					animated_sprite.flip_h = false

			# Player facing check: Is the player facing the NPC?
			# Player's facing vector should align with the vector from Player TO NPC.
			if player_facing.dot(vector_player_to_npc) > 0.5: # Using 0.5 for forgiveness
				print("DEBUG: Player is facing NPC (dot product > 0.5).")

				# Configure and perform the RayCast2D
				# This ensures the ray starts at the NPC's origin and points directly at the player
				# facing_ray_cast.target_position = to_local(player_pos) # Original dynamic calculation
				
				# --- TEMPORARY TEST: MANUALLY SET RAYCAST TARGET ---
				# Keep this for your current debugging phase. Once it works, uncomment the line above.
				facing_ray_cast.target_position = Vector2(-100, 0) # Ray points 100 pixels to the left in NPC's local space
				print("DEBUG: RayCast2D TEMPORARY target_position (local to NPC):", facing_ray_cast.target_position)
				# ----------------------------------------------------

				# Debug prints for ray global coordinates
				print("DEBUG: Player Global Position:", player_pos)
				print("DEBUG: NPC Global Position:", npc_pos)
				print("DEBUG: RayCast2D Local Target (from NPC origin):", facing_ray_cast.target_position)
				var ray_start_global = npc_pos 
				var ray_end_global = npc_pos + facing_ray_cast.target_position 
				print("DEBUG: Ray Global Start:", ray_start_global)
				print("DEBUG: Ray Global End:", ray_end_global)

				facing_ray_cast.enabled = true
				facing_ray_cast.force_raycast_update() # Important for immediate check

				if facing_ray_cast.is_colliding():
					var collider = facing_ray_cast.get_collider()
					print("DEBUG: Raycast collided with:", collider.name)
					# Use get_instance_id() for robust comparison, as nodes might be different instances
					if collider.get_instance_id() == player_node.get_instance_id():
						print("DEBUG: Hailing conditions met! Emitting hailed signal.")
						hailed.emit(npc_faction, npc_name)
					else:
						print("DEBUG: Raycast hit an obstacle instead of player:", collider.name)
				else:
					print("DEBUG: Raycast did not hit anything (or hit nothing on player mask).")
				
				facing_ray_cast.enabled = false # Disable raycast after check
			else:
				print("DEBUG: Player not facing NPC.")
		else:
			print("DEBUG: Player node not found for facing check.")
	# If 'hail' action is not pressed, ensure raycast is disabled (optional, depends on game flow)
	elif facing_ray_cast and facing_ray_cast.enabled:
		facing_ray_cast.enabled = false


func _on_detection_zone_body_entered(body: Node2D):
	# Ensure it's the player entering
	if body == player_node:
		player_in_range = true
		print("DEBUG: Player entered detection zone!")

func _on_detection_zone_body_exited(body: Node2D):
	# Ensure it's the player exiting
	if body == player_node:
		player_in_range = false
		print("DEBUG: Player exited detection zone.")
