# character_sheet.gd
extends CanvasLayer

# UI Node references (UPDATED PATHS AS PROVIDED BY YOU)
@onready var name_label = $main_panel/scroll_container/scroll_wrapper/stat_block/name_label
@onready var class_label = $main_panel/scroll_container/scroll_wrapper/stat_block/class_label
@onready var health_label = $main_panel/scroll_container/scroll_wrapper/stat_block/health_label
@onready var mana_label = $main_panel/scroll_container/scroll_wrapper/stat_block/mana_label
@onready var strength_value = $main_panel/scroll_container/scroll_wrapper/stat_block/strength_label
@onready var dexterity_value = $main_panel/scroll_container/scroll_wrapper/stat_block/dexterity_label
@onready var constitution_value = $main_panel/scroll_container/scroll_wrapper/stat_block/constitution_label
@onready var intelligence_value = $main_panel/scroll_container/scroll_wrapper/stat_block/intelligence_label
@onready var wisdom_value = $main_panel/scroll_container/scroll_wrapper/stat_block/wisdom_label
@onready var charisma_value = $main_panel/scroll_container/scroll_wrapper/stat_block/charisma_label

# Resistance Block References
@onready var resist_block = $main_panel/scroll_container/scroll_wrapper/resist_block
@onready var acid_label = $main_panel/scroll_container/scroll_wrapper/resist_block/acid_label
@onready var cold_label = $main_panel/scroll_container/scroll_wrapper/resist_block/cold_label
@onready var fire_label = $main_panel/scroll_container/scroll_wrapper/resist_block/fire_label
@onready var magic_label = $main_panel/scroll_container/scroll_wrapper/resist_block/magic_label
@onready var psychic_label = $main_panel/scroll_container/scroll_wrapper/resist_block/psychic_label

# Equipment Block References
@onready var equipment_block = $main_panel/scroll_container/scroll_wrapper/equipment_block
@onready var ear1_label = $main_panel/scroll_container/scroll_wrapper/equipment_block/ear1_label
@onready var neck_label = $main_panel/scroll_container/scroll_wrapper/equipment_block/neck_label
@onready var face_label = $main_panel/scroll_container/scroll_wrapper/equipment_block/face_label
@onready var head_label = $main_panel/scroll_container/scroll_wrapper/equipment_block/head_label
@onready var ear2_label = $main_panel/scroll_container/scroll_wrapper/equipment_block/ear2_label
@onready var finger1_label = $main_panel/scroll_container/scroll_wrapper/equipment_block/finger1_label
@onready var wrist1_label = $main_panel/scroll_container/scroll_wrapper/equipment_block/wrist1_label
@onready var arms_label = $main_panel/scroll_container/scroll_wrapper/equipment_block/arms_label
@onready var hands_label = $main_panel/scroll_container/scroll_wrapper/equipment_block/hands_label
@onready var wrist2_label = $main_panel/scroll_container/scroll_wrapper/equipment_block/wrist2_label
@onready var finger2_label = $main_panel/scroll_container/scroll_wrapper/equipment_block/finger2_label
@onready var shoulders_label = $main_panel/scroll_container/scroll_wrapper/equipment_block/shoulders_label
@onready var chest_label = $main_panel/scroll_container/scroll_wrapper/equipment_block/chest_label
@onready var back_label = $main_panel/scroll_container/scroll_wrapper/equipment_block/back_label
@onready var waist_label = $main_panel/scroll_container/scroll_wrapper/equipment_block/waist_label
@onready var legs_label = $main_panel/scroll_container/scroll_wrapper/equipment_block/legs_label
@onready var feet_label = $main_panel/scroll_container/scroll_wrapper/equipment_block/feet_label
@onready var trinket1_label = $main_panel/scroll_container/scroll_wrapper/equipment_block/trinket1_label
@onready var trinket2_label = $main_panel/scroll_container/scroll_wrapper/equipment_block/trinket2_label
@onready var primary_label = $main_panel/scroll_container/scroll_wrapper/equipment_block/primary_label
@onready var secondary_label = $main_panel/scroll_container/scroll_wrapper/equipment_block/secondary_label
@onready var ranged_label = $main_panel/scroll_container/scroll_wrapper/equipment_block/ranged_label
@onready var ammo_label = $main_panel/scroll_container/scroll_wrapper/equipment_block/ammo_label


func _ready():
	print("DEBUG: Character sheet _ready().")


# set_character_data - This is the primary function to populate the sheet's UI
func set_character_data(data: Dictionary):
	print("DEBUG: Character sheet: set_character_data called with data.")
	print("DEBUG: Data received by Character Sheet: ", data)

	if typeof(data) != TYPE_DICTIONARY:
		push_error("❌ Character Sheet: Invalid data type received. Expected Dictionary.")
		return

	# Populate basic info
	name_label.text = data.get("player_name", "N/A")
	class_label.text = data.get("player_class", "N/A")

	# Health and Mana (from derived or top-level)
	var derived = data.get("derived", {})
	health_label.text = "Health: %d/%d" % [data.get("current_health", derived.get("health", 0)), derived.get("health", 0)]
	mana_label.text = "Mana: %d/%d" % [data.get("current_mana", derived.get("mana", 0)), derived.get("mana", 0)]

	# Populate stats - NOW INCLUDING LABELS
	var stats = data.get("stats", {})
	strength_value.text = "Strength: %s" % str(stats.get("strength", 0))
	dexterity_value.text = "Dexterity: %s" % str(stats.get("dexterity", 0))
	constitution_value.text = "Constitution: %s" % str(stats.get("constitution", 0))
	intelligence_value.text = "Intelligence: %s" % str(stats.get("intelligence", 0))
	wisdom_value.text = "Wisdom: %s" % str(stats.get("wisdom", 0))
	charisma_value.text = "Charisma: %s" % str(stats.get("charisma", 0))

	# Populate Resistances
	var resistances = data.get("resistances", {})
	acid_label.text = "Acid: %d%%" % resistances.get("acid", 0)
	cold_label.text = "Cold: %d%%" % resistances.get("cold", 0)
	fire_label.text = "Fire: %d%%" % resistances.get("fire", 0)
	magic_label.text = "Magic: %d%%" % resistances.get("magic", 0)
	psychic_label.text = "Psychic: %d%%" % resistances.get("psychic", 0)

	# Populate Equipment
	var equipment = data.get("equipment", {})
	ear1_label.text = "Ear 1: %s" % equipment.get("ear1", "Empty")
	neck_label.text = "Neck: %s" % equipment.get("neck", "Empty")
	face_label.text = "Face: %s" % equipment.get("face", "Empty")
	head_label.text = "Head: %s" % equipment.get("head", "Empty")
	ear2_label.text = "Ear 2: %s" % equipment.get("ear2", "Empty")
	finger1_label.text = "Finger 1: %s" % equipment.get("finger1", "Empty")
	wrist1_label.text = "Wrist 1: %s" % equipment.get("wrist1", "Empty")
	arms_label.text = "Arms: %s" % equipment.get("arms", "Empty")
	hands_label.text = "Hands: %s" % equipment.get("hands", "Empty")
	wrist2_label.text = "Wrist 2: %s" % equipment.get("wrist2", "Empty")
	finger2_label.text = "Finger 2: %s" % equipment.get("finger2", "Empty")
	shoulders_label.text = "Shoulders: %s" % equipment.get("shoulders", "Empty")
	chest_label.text = "Chest: %s" % equipment.get("chest", "Empty")
	back_label.text = "Back: %s" % equipment.get("back", "Empty")
	waist_label.text = "Waist: %s" % equipment.get("waist", "Empty")
	legs_label.text = "Legs: %s" % equipment.get("legs", "Empty")
	feet_label.text = "Feet: %s" % equipment.get("feet", "Empty")
	trinket1_label.text = "Trinket 1: %s" % equipment.get("trinket1", "Empty")
	trinket2_label.text = "Trinket 2: %s" % equipment.get("trinket2", "Empty")
	primary_label.text = "Primary: %s" % equipment.get("primary", "Empty")
	secondary_label.text = "Secondary: %s" % equipment.get("secondary", "Empty")
	ranged_label.text = "Ranged: %s" % equipment.get("ranged", "Empty")
	ammo_label.text = "Ammo: %s" % equipment.get("ammo", "Empty")

	print("✅ Character sheet UI updated for:", name_label.text)


# _input - Handles input specifically for the character sheet
func _input(event: InputEvent):
	if Input.is_action_just_pressed("toggle_character_sheet"):
		print("DEBUG: Character sheet: 'toggle_character_sheet' action detected. Closing.")
		queue_free()
		get_viewport().set_input_as_handled()
		print("DEBUG: Character sheet closed and input handled.")
		return
