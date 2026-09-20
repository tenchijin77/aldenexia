# kenji_npc.gd — Kenji, the cat by the town gate. Cats don't speak, so there is
# no dialogue or quest log: other NPCs mention him (see the guards' "hail"
# lines in Data/guard_flavor_text.json), hailing him gets an emote, and the
# "quest" is just EverQuest-style — drag a rat tail from your backpack and drop it ON him
# (or right-click him and drag it into the Give window, give_window.gd), press Give. He remembers partial hand-ins PER
# CHARACTER (a save-file key, so it survives logging out): give him 3 now and 7
# later and it completes at 10 total, then resets so it can be done again.
#
# Built on VendorNPC purely to reuse its plumbing (targeting, hail range,
# faction, health bar, right-click hit-testing); he never opens a shop —
# player3d.gd's _open_shop() hands VendorNPCs that define open_interaction()
# to it instead. Edit the @export texts below in the Inspector (or here).
extends VendorNPC
class_name KenjiNPC

const MODEL_BASE := "res://models/Kenji/Meshy_AI_kenji_3d_model_0919110711_image-to-3d-texture"
const REQUIRED_ITEM := "rat_tail"
const PROGRESS_KEY := "kenji_rat_tails_given"  # int in Global.player_data (the character's save file)
const BLESSING_ID := "kenjis_blessing"
# Small comfort buff, same modifier shapes campfire_warmth/well_fed use.
const BLESSING_MODIFIERS := {
	"hp_regen_bonus": 2.0,
	"mana_regen_bonus": 2.0,
	"stamina_regen_bonus": 2.0,
	"hit_chance": 3.0,
}
const INTERACT_RANGE := 6.0
const EMOTE_COLOR := "#ffd9a0"

@export_group("Quest")
@export var tails_required: int = 10
@export var xp_reward: int = 40
@export var blessing_duration: float = 900.0  # seconds

@export_group("Model")
@export var model_scale: float = 0.5

@export_group("Stats")
@export var max_health: int = 200

@export_group("Chat text (shown in the chat log; edit freely)")
## Shown when a player pets him (/pet). {name} = his name.
@export_multiline var pet_text: String = "You pet {name}. He begins to purr happily!"
## Picked at random when a player hails him (H / /hail).
@export var hail_emotes: PackedStringArray = [
	"Meoww! Kenji meows at you while pawing at a rat's tail. He seems very interested in it.",
]
## When the right number of rat tails is handed over.
@export_multiline var reward_text: String = "Kenji purrs loudly and rubs against your legs. A warm glow settles over you."
## After a partial hand-in (he keeps count). {given} = total so far, {need} = required, {left} = still owed, {taken} = just handed over.
@export_multiline var progress_text: String = "Kenji sniffs what you gave him and bats it into a little pile. He looks up at you, wanting more. ({given}/{need})"
## When you try to give rat tails but are carrying none.
@export_multiline var no_tails_text: String = "Kenji sniffs your empty hands, then looks up at you expectantly."
## When you give him something that isn't a rat tail.
@export_multiline var wrong_item_text: String = "Kenji sniffs the offering, then turns away, unimpressed."
## Name/description for the buff bar entry (the reward buff).
@export_multiline var blessing_description: String = "Kenji's blessing. +2 HP/Mana/Stamina regeneration and +3 to hit."

var _model: Node3D = null


func _ready() -> void:
	super._ready()
	add_to_group("pettable")  # /pet finds anything in this group
	call_deferred("_finish_model")


# VendorNPC gives every vendor a flat 100 HP; Kenji gets max_health instead
# (base_hp 50 + gear_hp, same formula the vendor/guard setups use).
func _setup_combat() -> void:
	super._setup_combat()
	combat_node.gear_hp = max_health - 50
	combat_node._stats_dirty = true
	combat_node.recalculate_derived_stats()
	combat_node.current_hp = combat_node.max_hp


# ── Visuals: static cat mesh, no animations ────────────────────────────────
func _build_character_model() -> void:
	_model = CatModel.build(self, MODEL_BASE, model_scale)


func _setup_animation() -> void:
	pass  # unrigged mesh — nothing to animate


func _load_shop_data() -> void:
	pass  # never a shop


func get_vendor_display_name() -> String:
	return npc_name


# Runs after the tree has settled: sit the model on the ground and float the
# nameplate just above his head, whatever model_scale is set to.
func _finish_model() -> void:
	if _model == null:
		return
	var height := CatModel.ground_and_measure(self, _model)
	if name_label:
		name_label.position.y = height + 0.3


# ── Interaction ────────────────────────────────────────────────────────────
func respond_to_hail() -> void:
	_face_local_player()
	if not hail_emotes.is_empty():
		_emote(hail_emotes[randi() % hail_emotes.size()])


func open_interaction(player: Node) -> void:
	if global_position.distance_to(player.global_position) > INTERACT_RANGE:
		GameLog.log_general("You are too far away from %s." % npc_name)
		return
	_face_local_player()
	var existing := get_tree().root.get_node_or_null("GiveWindow")
	if existing:
		existing.queue_free()
	var win := GiveWindow.new()
	win.name = "GiveWindow"
	get_tree().root.add_child(win)
	win.setup(self, player)


# An inventory item was dragged out of the backpack and released ON Kenji in the world (EverQuest-style; see
# player3d.gd's try_offer_item_to_npc_at()). Opens the Give window with that item already offered; the player
# still presses Give, like the trade window in EQ. Too far away -> open_interaction() says so and nothing opens.
func receive_item_drop(item: Dictionary, player: Node) -> void:
	open_interaction(player)
	var win := get_tree().root.get_node_or_null("GiveWindow")
	if win and win.has_method("offer_item"):
		win.offer_item(item)


# /pet — see player3d.gd's try_pet_nearby().
func receive_pet(_petter: Node) -> void:
	_face_local_player()
	_emote(pet_text.replace("{name}", npc_name))


# Called by the Give window. Returns true when the hand-in was accepted (the
# window then closes); false leaves it open so the player can adjust.
func try_give(item_id: String, player: Node) -> bool:
	if item_id != REQUIRED_ITEM:
		_emote(wrong_item_text)
		return false
	var given := get_given()
	var need := tails_required - given
	var have := count_item(REQUIRED_ITEM)
	if need > 0 and have <= 0:
		_emote(no_tails_text)
		return false

	# Hand over what you're carrying, but never more than he still needs.
	var taken := mini(have, maxi(need, 0))
	if taken > 0:
		consume_item(REQUIRED_ITEM, taken)
		var item_name: String = str(Inventory.get_item_definition(REQUIRED_ITEM).get("name", "Rat Tail"))
		GameLog.log_general("You give %s %d %s." % [npc_name, taken, item_name + ("s" if taken != 1 else "")])
	given += taken

	if given < tails_required:
		# Partial hand-in: remember it (per character, saved) and keep the window open.
		_set_given(given)
		_emote(progress_text.replace("{given}", str(given)).replace("{need}", str(tails_required)) \
				.replace("{left}", str(tails_required - given)).replace("{taken}", str(taken)))
		return false

	# Total reached — reset the counter (repeatable) and reward.
	_set_given(0)
	_emote(reward_text)
	if player.has_method("grant_xp"):
		player.grant_xp(xp_reward)
	if "combat_node" in player and player.combat_node is CombatNode:
		player.combat_node.apply_effect(BLESSING_ID, blessing_duration, BLESSING_MODIFIERS)
		GameLog.log_general("[color=#88ffaa]You gain [b]Kenji's Blessing[/b].[/color]")
	return true


# How many rat tails THIS character has handed over toward the current round.
func get_given() -> int:
	return int(Global.player_data.get(PROGRESS_KEY, 0))


func _set_given(count: int) -> void:
	Global.player_data[PROGRESS_KEY] = count
	Global.save_player_data_to_file()


# One line for the Give window.
func progress_summary() -> String:
	return "Rat tails you've given %s: %d / %d" % [npc_name, get_given(), tails_required]


func _emote(text: String) -> void:
	GameLog.log_general("[color=%s]%s[/color]" % [EMOTE_COLOR, text])


func _face_local_player() -> void:
	var player := TargetFrame.local_player()
	if not is_instance_valid(player):
		return
	var target: Vector3 = player.global_position
	target.y = global_position.y
	if target.distance_to(global_position) > 0.01:
		look_at(target, Vector3.UP)


# ── Death / respawn ────────────────────────────────────────────────────────
func die() -> void:
	NPCRespawner.handle_death(self, respawn_seconds)


# ── Inventory helpers (all bags + the basic slots) ─────────────────────────
# Every stack of `item_id` the player carries, as
# [{slot_type, slot_index, bag_slot, item_index, qty}].
static func find_stacks(item_id: String) -> Array:
	var out: Array = []
	for i in range(Inventory.basic_inventory.size()):
		var it = Inventory.basic_inventory[i]
		if it != null and it is Dictionary and it.get("item_id", "") == item_id:
			out.append({"slot_type": "basic", "slot_index": i, "bag_slot": -1, "item_index": -1,
					"qty": int(it.get("quantity", 1))})
	for key in Inventory.bag_contents:
		var items: Array = Inventory.bag_contents[key]
		for j in range(items.size()):
			var it = items[j]
			if it != null and it is Dictionary and it.get("item_id", "") == item_id:
				out.append({"slot_type": "bag", "slot_index": -1, "bag_slot": int(key), "item_index": j,
						"qty": int(it.get("quantity", 1))})
	return out


static func count_item(item_id: String) -> int:
	var total := 0
	for s in find_stacks(item_id):
		total += s["qty"]
	return total


# Removes `amount` units across however many stacks it takes. Bag stacks are
# processed highest-index-first so a fully-used stack disappearing doesn't
# shift the indexes of the ones still to be processed.
static func consume_item(item_id: String, amount: int) -> void:
	var stacks := find_stacks(item_id)
	stacks.sort_custom(func(a, b):
		if a["bag_slot"] != b["bag_slot"]:
			return a["bag_slot"] > b["bag_slot"]
		return a["item_index"] > b["item_index"])
	var left := amount
	for s in stacks:
		if left <= 0:
			break
		var take: int = mini(s["qty"], left)
		Inventory.consume_amount(s["slot_type"], s["slot_index"], s["bag_slot"], s["item_index"], take)
		left -= take
