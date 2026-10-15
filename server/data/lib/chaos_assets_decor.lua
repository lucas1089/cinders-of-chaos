-- Server ids of the catacomb kit decoration of the pair 27 trial (server/tools/install_assets_decor.py --lua,
-- from server/data/items/assets_decor.csv). Generated; do not edit by hand. Used by data/lib/chaos_assets_art.lua,
-- and only while its switch ChaosAssetsArt.PAIR27 is on.

return {
	first = 36986,
	last = 36994,
	-- key = {id, size w x h, blocks a tile, animated, name}
	items = {
		crypt_portal = {id = 36986, w = 3, h = 3, block = false, animated = true, name = "crypt portal"},
		crypt_portal_collapse = {id = 36987, w = 4, h = 4, block = false, animated = true, name = "collapsing crypt portal"},
		crypt_portal_husk = {id = 36988, w = 4, h = 4, block = false, animated = false, name = "burnt-out portal ring"},
		crypt_seal = {id = 36989, w = 3, h = 3, block = true, animated = false, name = "sealed crypt hatch"},
		crypt_seal_breaking = {id = 36990, w = 3, h = 3, block = true, animated = true, name = "breaking crypt seal"},
		crypt_seal_open = {id = 36991, w = 3, h = 3, block = false, animated = false, name = "open crypt hatch"},
		sarcophagus = {id = 36992, w = 2, h = 3, block = true, animated = false, name = "sealed sarcophagus"},
		sarcophagus_opening = {id = 36993, w = 2, h = 3, block = true, animated = true, name = "sarcophagus lid grinding open"},
		sarcophagus_open = {id = 36994, w = 2, h = 3, block = true, animated = false, name = "open sarcophagus"},
	}
}
