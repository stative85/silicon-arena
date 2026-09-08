extends RefCounted
class_name ArenaLayout

## THE COMPACT INDUSTRIAL ARENA, AS A DETERMINISTIC BUILD FUNCTION.
##
## Built in code rather than a hand-authored .tscn so the world's topology is
## diffable, hashable and identical on every construction. The visual scene
## dresses this; it does not define it.
##
##                          vault_hall
##                     (5 slots, 3 required)
##                              |
##          north_catwalk -- vault_ring -- south_catwalk
##                |                             |
##   spawn_vanta -+- spawn_kestrel   spawn_ozonious -+- spawn_brine
##                |                             |
##            west_pipe ---- machine_floor ---- east_pipe
##                              |
##                       spawn_gemmatron
##
## FIVE KEYS, one near each spawn. THREE DISTINCT keys open the vault. Nobody
## needs their own: that single asymmetry between "keys you have" and "keys the
## vault needs" is the entire engine of the round.

const SPAWNS := {
	"VANTA": "spawn_vanta",
	"KESTREL": "spawn_kestrel",
	"GEMMATRON": "spawn_gemmatron",
	"OZONIOUS": "spawn_ozonious",
	"BRINE": "spawn_brine",
}

const START_ENERGY := 100


static func build(world, round_id: String) -> void:
	world.round_id = round_id

	world.add_location("vault_hall", "Vault Hall", ["vault_ring"])
	world.add_location("vault_ring", "Vault Ring",
		["vault_hall", "north_catwalk", "south_catwalk", "machine_floor"])
	world.add_location("north_catwalk", "North Catwalk",
		["vault_ring", "spawn_vanta", "spawn_kestrel", "west_pipe"])
	world.add_location("south_catwalk", "South Catwalk",
		["vault_ring", "spawn_ozonious", "spawn_brine", "east_pipe"])
	world.add_location("machine_floor", "Machine Floor",
		["vault_ring", "west_pipe", "east_pipe", "spawn_gemmatron"])
	world.add_location("west_pipe", "West Pipe Run",
		["north_catwalk", "machine_floor"])
	world.add_location("east_pipe", "East Pipe Run",
		["south_catwalk", "machine_floor"])

	world.add_location("spawn_vanta", "Chamber I", ["north_catwalk"])
	world.add_location("spawn_kestrel", "Chamber II", ["north_catwalk"])
	world.add_location("spawn_gemmatron", "Chamber III", ["machine_floor"])
	world.add_location("spawn_ozonious", "Chamber IV", ["south_catwalk"])
	world.add_location("spawn_brine", "Chamber V", ["south_catwalk"])

	## The only door onto the vault itself. It starts UNLOCKED; that it can be
	## locked at all is what makes LOCK a meaningful verb rather than scenery.
	world.add_door("door_vault", "vault_ring", "vault_hall", false)
	world.add_door("door_west", "north_catwalk", "west_pipe", false)
	world.add_door("door_east", "south_catwalk", "east_pipe", false)

	## Five keys, one per spawn chamber. Key ids are deliberately NOT tied to
	## agent names -- key_A sitting in VANTA's chamber is not "VANTA's key", and
	## nothing in the host says it is.
	world.add_object("key_A", "key", "spawn_vanta")
	world.add_object("key_B", "key", "spawn_kestrel")
	world.add_object("key_C", "key", "spawn_gemmatron")
	world.add_object("key_D", "key", "spawn_ozonious")
	world.add_object("key_E", "key", "spawn_brine")

	## Scarce scrap: 8 pieces for 5 agents, deliberately not divisible evenly.
	world.add_object("scrap_1", "scrap", "machine_floor")
	world.add_object("scrap_2", "scrap", "machine_floor")
	world.add_object("scrap_3", "scrap", "west_pipe")
	world.add_object("scrap_4", "scrap", "east_pipe")
	world.add_object("scrap_5", "scrap", "north_catwalk")
	world.add_object("scrap_6", "scrap", "south_catwalk")
	world.add_object("scrap_7", "scrap", "vault_ring")
	world.add_object("scrap_8", "scrap", "machine_floor")

	## Two terminals, both away from the vault, so recovering energy costs
	## distance from the objective.
	world.add_terminal("terminal_west", "west_pipe", 2, 12)
	world.add_terminal("terminal_east", "east_pipe", 2, 12)

	## Five slots, three required. More slots than required keys means a
	## committed key can be withdrawn without necessarily closing the vault --
	## and that the count can hover at 2/3 indefinitely.
	world.add_vault_slot("vault_slot_1")
	world.add_vault_slot("vault_slot_2")
	world.add_vault_slot("vault_slot_3")
	world.add_vault_slot("vault_slot_4")
	world.add_vault_slot("vault_slot_5")


static func spawn_of(display_name: String) -> String:
	return str(SPAWNS.get(display_name, "vault_ring"))
