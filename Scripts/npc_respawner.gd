# npc_respawner.gd — Shared "an NPC died, bring it back after a while" behavior
# for every town NPC (guards, vendors, Kenji, Oni). Any NPC script calls
# register_home() once in _ready() and handle_death() from its own die().
# Dead NPCs are hidden, untargetable (removed from their groups so Tab-target/
# hail/heal lookups skip them), out of every monster's aggro table, and come
# back at their original spot with full health after `respawn_seconds`.
class_name NPCRespawner

const HOME_META := "respawn_home"
const GROUPS_META := "respawn_groups"
const DEAD_META := "npc_dead"


static func register_home(npc: Node3D) -> void:
	npc.set_meta(HOME_META, npc.global_transform)


static func is_dead(npc: Node) -> bool:
	return npc.has_meta(DEAD_META)


# Client-side mirror of a server-side death/respawn: the server hides the NPC and pulls it
# out of every group (see handle_death); a puppet only learns the replicated `visible`
# flag, so it applies the same untargetable/no-collision state locally.
static func mirror_hidden(npc: Node3D, hidden: bool) -> void:
	for c in npc.find_children("*", "CollisionShape3D", true, false):
		c.set_deferred("disabled", hidden)
	if hidden:
		var groups: Array = []
		for g in npc.get_groups():
			if not str(g).begins_with("_"):
				groups.append(g)
				npc.remove_from_group(g)
		npc.set_meta(GROUPS_META, groups)
	else:
		for g in npc.get_meta(GROUPS_META, []):
			npc.add_to_group(g)


static func handle_death(npc: Node3D, respawn_seconds: float) -> void:
	if not is_instance_valid(npc) or is_dead(npc):
		return
	var tree := npc.get_tree()
	npc.set_meta(DEAD_META, true)

	# Anything that was fighting it goes back to normal instead of chasing a
	# ghost (or, worse, turning on the player).
	for m in tree.get_nodes_in_group("monsters"):
		if "aggro_table" in m:
			m.aggro_table.erase(npc)
			if m.aggro_table.is_empty() and "current_state" in m \
					and (m.current_state == m.State.CHASE or m.current_state == m.State.ATTACK):
				m.change_state(m.State.IDLE)

	npc.visible = false
	npc.set_physics_process(false)
	npc.set_process(false)
	for c in npc.find_children("*", "CollisionShape3D", true, false):
		c.set_deferred("disabled", true)
	var groups: Array = []
	for g in npc.get_groups():
		if not str(g).begins_with("_"):
			groups.append(g)
			npc.remove_from_group(g)
	npc.set_meta(GROUPS_META, groups)

	await tree.create_timer(respawn_seconds).timeout
	if not is_instance_valid(npc):
		return

	npc.global_transform = npc.get_meta(HOME_META, npc.global_transform)
	if "velocity" in npc:
		npc.velocity = Vector3.ZERO
	for c in npc.find_children("*", "CollisionShape3D", true, false):
		c.set_deferred("disabled", false)
	for g in npc.get_meta(GROUPS_META, []):
		npc.add_to_group(g)
	npc.remove_meta(DEAD_META)
	if "combat_node" in npc and npc.combat_node is CombatNode:
		npc.combat_node.current_hp = npc.combat_node.max_hp
		npc.combat_node.active_effects.clear()
	npc.visible = true
	npc.set_physics_process(true)
	npc.set_process(true)
	if npc.has_method("on_respawned"):
		npc.on_respawned()
