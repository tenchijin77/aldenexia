# campfire.gd — logs a flavor message when the player warms up near the fire,
# and grants "Warmth of the Campfire" (+2 HP/Mana/Stamina regen for 15 minutes)
# after they've lingered nearby for 30 continuous seconds. Leaving early
# cancels the countdown — you have to actually sit through it.
#
# Also a cooking tradeskill station: right-clicking within COOK_RANGE opens
# the generic TradeskillWindow (player3d.gd's _try_open_campfire(), part of
# _try_open_shop_or_loot()'s dispatch chain). Range-based rather than a
# raycast (like the vendor shop check) since this node has no real collision
# body to hit — just its particle/light/audio children.
extends Node3D

const COOK_RANGE := 5.0
const STATION_ID := "campfire"
@export var display_name: String = "Campfire"  # future fire types (stove, forge) override this

const WARMTH_LINGER_SECONDS := 30.0
const BUFF_DURATION_SECONDS := 900.0  # 15 minutes
const BUFF_MODIFIERS := {
	"hp_regen_bonus": 2,
	"mana_regen_bonus": 2,
	"stamina_regen_bonus": 2,
}

@onready var warmth_area: Area3D = $WarmthArea
var _warmth_timer: Timer = Timer.new()

var _player_near: bool = false
var _warming_player: Node3D = null


func _ready() -> void:
	add_to_group("cooking_station")
	warmth_area.body_entered.connect(_on_body_entered)
	warmth_area.body_exited.connect(_on_body_exited)
	_warmth_timer.one_shot = true
	_warmth_timer.wait_time = WARMTH_LINGER_SECONDS
	_warmth_timer.timeout.connect(_on_warmth_timer_timeout)
	add_child(_warmth_timer)


func _on_body_entered(body: Node3D) -> void:
	# This node is a static, hand-placed part of the zone scene — identical
	# on every peer, not something spawned/owned by one player — so its
	# Area3D detects ANY replicated body walking through it, including a
	# remote player's puppet, on every single peer's own local physics.
	# Without this gate, a non-authoritative peer would (a) mutate a remote
	# player's combat_node directly, same relay problem as everywhere else
	# this session, and (b) show a spurious "You feel invigorated..." message
	# on the wrong player's screen entirely. Gating on the body's own
	# authority means only that player's own client ever reacts to their own
	# arrival — a player is always authoritative over themselves (unlike a
	# monster), so no RPC relay is needed once this check is in place.
	if not body.is_multiplayer_authority():
		return
	if _player_near or not body.is_in_group("player"):
		return
	_player_near = true
	_warming_player = body
	GameLog.log_general("The warmth of the fire renews your spirit as you take shelter nearby.")
	_warmth_timer.start()


func _on_body_exited(body: Node3D) -> void:
	if not body.is_multiplayer_authority():
		return
	if not body.is_in_group("player"):
		return
	_player_near = false
	_warming_player = null
	_warmth_timer.stop()


func _on_warmth_timer_timeout() -> void:
	if not is_instance_valid(_warming_player) or not ("combat_node" in _warming_player):
		return
	var combat_node = _warming_player.combat_node
	if not (combat_node is CombatNode):
		return
	combat_node.apply_effect("campfire_warmth", BUFF_DURATION_SECONDS, BUFF_MODIFIERS)
	GameLog.log_general("[color=#ffaa55]You feel invigorated by the campfire's warmth.[/color]")
