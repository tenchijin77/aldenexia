# vendor_npc.gd — Stationary general-goods vendor. Player3D's right-click
# handler (_try_open_shop_or_loot()) opens shop_window.tscn against whichever
# VendorNPC is nearest when a vendor's within SHOP_RANGE, in preference to the
# usual loot-corpse behavior. Builds its own visual dynamically from
# VENDOR_MODELS (keyed by vendor_model_key, same CHARACTER_MODELS/MOB_MODELS
# pattern as player3d.gd/monster3d.gd) instead of a static scene node, since
# different vendor instances now use different dedicated models — no combat,
# no navigation, just stands in place with a name label like guard_npc.gd.
extends CharacterBody3D
class_name VendorNPC

@export var npc_name: String = "Vendor"
@export var shop_id: String = "lumora_general_goods"  # key into Data/vendor_shop.json
@export var shop_data_path: String = "res://Data/vendor_shop.json"
# Key into VENDOR_MODELS — "male"/"female" so far. Anything else (including
# the default "default") falls back to DEFAULT_VENDOR_MODEL, the original
# shared player model every vendor used before 2026-09-16.
@export var vendor_model_key: String = "default"
## Seconds after dying before this NPC returns at its original spot.
@export var respawn_seconds: float = 120.0

const VENDOR_MODELS := {
	"male": {
		"scene":   "res://models/male vendor/Meshy_AI_Male_Vendor_Blacksmit_biped_Character_output.fbx",
		"library": "res://models/male vendor/male_vendor_animations.res",
		"texture_override": "res://models/male vendor/Meshy_AI_Male_Vendor_Blacksmit_biped_texture_0.png",
	},
	"female": {
		"scene":   "res://models/female vendor/Meshy_AI_Female_Vendor_Apothec_biped_Character_output.fbx",
		"library": "res://models/female vendor/female_vendor_animations.res",
		"texture_override": "res://models/female vendor/Meshy_AI_Female_Vendor_Apothec_biped_texture_0.png",
	},
}
const DEFAULT_VENDOR_MODEL := {
	"scene":   "res://models/player/character.fbx",
	"library": "res://models/player/player_animations.res",
}

@onready var name_label: Label3D = $NameLabel
var animation_player: AnimationPlayer = null
var combat_node: CombatNode

var _shop_data: Dictionary = {}


func _ready() -> void:
	add_to_group("npc_vendor")
	NPCRespawner.register_home(self)
	if name_label:
		name_label.text = npc_name
	_load_shop_data()
	_build_character_model()
	_setup_animation()
	_setup_combat()


# Where the solid ground is under a point: a ray from 1.5 m above it to 6.5 m below — high enough to find the top of a raised
# dock deck (vendors have no gravity, so one placed at a marker's y=0 on a deck would stand inside it), low enough never to
# hit the roof of the vendor lean-to they stand under (about 2.3 m).
func floor_y_at(pos: Vector3, default_y: float) -> float:
	if not is_inside_tree():
		return default_y
	var from := Vector3(pos.x, pos.y + 1.5, pos.z)
	var query := PhysicsRayQueryParameters3D.create(from, from + Vector3(0, -8.0, 0))
	query.exclude = [get_rid()]
	var hit := Global.ground_ray(get_world_3d().direct_space_state, query)
	if hit:
		return hit.position.y
	# Nothing within that window: on hilly terrain the NPC may have been placed well above or below the ground. Look from high
	# up instead (this can land on a roof, which is why it's only the fallback).
	var high := PhysicsRayQueryParameters3D.create(Vector3(pos.x, pos.y + 200.0, pos.z), Vector3(pos.x, pos.y - 200.0, pos.z))
	high.exclude = [get_rid()]
	hit = Global.ground_ray(get_world_3d().direct_space_state, high)
	return hit.position.y if hit else default_y


# Stand on whatever is under the spot the scene put this NPC at (waits one physics frame so the level's shapes exist), and make
# that spot the home he returns to after a respawn.
func snap_to_floor() -> void:
	await get_tree().physics_frame
	if not is_inside_tree():
		return
	global_position.y = floor_y_at(global_position, global_position.y)
	NPCRespawner.register_home(self)


# Had no combat_node at all before this — showed as 0/0 HP wherever
# something expects one (target frame, appraisal), same "no life" bug
# guard_npc.gd doesn't have since it already sets one up. Vendors don't
# fight, so this exists purely so they read as a real, alive NPC (100 HP
# flat, per the user's request) rather than for any actual combat use.
func _setup_combat() -> void:
	combat_node = CombatNode.new()
	add_child(combat_node)
	combat_node.level        = 1
	combat_node.strength     = 0
	combat_node.constitution = 0
	combat_node.dexterity    = 0
	combat_node.intelligence = 0
	combat_node.wisdom       = 0
	combat_node.charisma     = 0
	combat_node.luck         = 0
	combat_node.gear_hp = 50  # base_hp (50) + gear_hp (50) = 100 max_hp
	combat_node._stats_dirty = true
	combat_node.recalculate_derived_stats()
	combat_node.current_hp = combat_node.max_hp


func _load_shop_data() -> void:
	var file := FileAccess.open(shop_data_path, FileAccess.READ)
	if not file:
		return
	var result = JSON.parse_string(file.get_as_text())
	file.close()
	if typeof(result) == TYPE_DICTIONARY:
		_shop_data = result.get(shop_id, {})


# Vendors have HP (see _setup_combat) so they can be killed like any NPC; they
# then respawn via the shared helper. Nothing currently attacks them.
func die() -> void:
	NPCRespawner.handle_death(self, respawn_seconds)


func get_vendor_display_name() -> String:
	return _shop_data.get("vendor_name", npc_name)


# player3d.gd's try_hail_nearby_npc() (H key / "/hail") calls this on
# whichever NPC in group "npc_guard"/"npc_vendor" is nearest — same method
# name guard_npc.gd uses, so that dispatcher doesn't need to know the NPC's
# type. Reuses greet_player()'s line rather than a separate flavor pool;
# hailing him is just a way to get his greeting without opening the shop.
func respond_to_hail() -> void:
	var player := TargetFrame.local_player()
	if not is_instance_valid(player):
		return
	face_hailer(player)
	greet_player(player.player_name)


# Turn to face whoever is talking to this NPC (upright: never tilts up or down).
func face_hailer(player: Node3D) -> void:
	var target := player.global_position
	target.y = global_position.y
	if target.distance_to(global_position) > 0.01:
		look_at(target, Vector3.UP)


# Called by player3d.gd's _open_shop() the moment the shop window opens.
func greet_player(player_name: String) -> void:
	var talker := TargetFrame.local_player()
	if is_instance_valid(talker):
		face_hailer(talker)
	var stock := get_shop_stock()
	if stock.is_empty():
		return
	var item_def: Dictionary = stock[randi() % stock.size()]["item_def"]
	var item_name: String = item_def.get("name", "item")
	GameLog.log_general("[color=#cccc88]%s says, \"Welcome, %s. I have a good %s you might be interested in.\"[/color]" % [
		get_vendor_display_name(), player_name, item_name
	])


# Returns [{item_id, item_def, price}] for everything this vendor stocks,
# skipping any item_id from the JSON that has no items.json definition.
func get_shop_stock() -> Array:
	var stock: Array = []
	var multiplier: float = _shop_data.get("buy_price_multiplier", 1.0)
	for item_id in _shop_data.get("stock", []):
		var item_def: Dictionary = Inventory.get_item_definition(item_id)
		if item_def.is_empty():
			continue
		var price := int(round(Global.item_value_in_copper(item_def) * multiplier))
		stock.append({"item_id": item_id, "item_def": item_def, "price": maxi(price, 1)})
	return stock


# What this vendor will pay the player for one unit of a given item def.
func get_sell_price(item_def: Dictionary) -> int:
	var multiplier: float = _shop_data.get("sell_price_multiplier", 0.5)
	return maxi(int(round(Global.item_value_in_copper(item_def) * multiplier)), 1)


# Builds the "Character" child from VENDOR_MODELS[vendor_model_key] (or
# DEFAULT_VENDOR_MODEL) — mirrors player3d.gd's _build_character_model() /
# monster3d.gd's _setup_humanoid_visual(). Same 180°-Y facing fix every
# Mixamo export in this project needs.
func _build_character_model() -> void:
	var model_info: Dictionary = VENDOR_MODELS.get(vendor_model_key, DEFAULT_VENDOR_MODEL)
	var character_scene := load(model_info["scene"])
	if not character_scene:
		return
	var character: Node3D = character_scene.instantiate()
	character.name = "Character"
	character.transform = Transform3D.IDENTITY.rotated(Vector3.UP, PI)
	add_child(character)
	animation_player = character.get_node_or_null("AnimationPlayer")

	if model_info.has("texture_override"):
		_apply_texture_override(character, model_info["texture_override"])


# Meshy-sourced FBX exports never carry their real texture through to Godot
# reliably (confirmed recurring bug across every model built this way), so
# apply it as a runtime material override instead of trusting the FBX's own
# material.
func _apply_texture_override(node: Node, texture_path: String) -> void:
	var tex := load(texture_path) as Texture2D
	if not tex:
		push_warning("⚠️ Vendor texture override not found: %s" % texture_path)
		return
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = tex
	_apply_material_recursive(node, mat)


func _apply_material_recursive(node: Node, mat: Material) -> void:
	if node is MeshInstance3D:
		var mi: MeshInstance3D = node
		if mi.mesh:
			for i in range(mi.mesh.get_surface_count()):
				mi.set_surface_override_material(i, mat)
	for child in node.get_children():
		_apply_material_recursive(child, mat)


func _setup_animation() -> void:
	if not animation_player:
		return
	var model_info: Dictionary = VENDOR_MODELS.get(vendor_model_key, DEFAULT_VENDOR_MODEL)
	var lib := load(model_info["library"]) as AnimationLibrary
	if not lib:
		return
	if animation_player.has_animation_library(""):
		animation_player.remove_animation_library("")
	animation_player.add_animation_library("", lib)
	if animation_player.has_animation("idle"):
		animation_player.play("idle")
