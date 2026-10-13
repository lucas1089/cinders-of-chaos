-- Registers the outfit shaders the server sends by name (data/XML/shaders.xml of the base server,
-- ids 1-17, 18 ember_pixent of the exclusives, 19-24 the chaos_* shaders of the cosmetics) so monster
-- modifiers, store shaders and outfit shaders draw. Same list and files as the base client's game_shaders module
-- (plus ember_pixent and the chaos_* ones); the .frag files are in data/shaders.
-- The server names "blue Dortmond" (id 5) with a space, the base client "blue_Dortmond": both are registered.

local SHADERS = {
  { "Enterprise", "/shaders/expand_vertex", "/shaders/shine15" },
  { "blue_loohs", "/shaders/expand_vertex", "/shaders/shine8" },
  { "bloohs_green", "/shaders/expand_vertex", "/shaders/bloohs_green" },
  { "bloohs_red", "/shaders/expand_vertex", "/shaders/bloohs_red" },
  { "bloohs_white", "/shaders/expand_vertex", "/shaders/bloohs_white" },
  { "blue_Dortmond", "/shaders/expand_vertex", "/shaders/shine11" },
  { "red_dortmond", "/shaders/expand_vertex", "/shaders/dortmond_red" },
  { "white_dortmond", "/shaders/expand_vertex", "/shaders/dortmond_white" },
  { "green_dortmond", "/shaders/expand_vertex", "/shaders/dortmond_green" },
  { "yellow_dortmond", "/shaders/expand_vertex", "/shaders/dortmond_yellow" },
  { "pink_energizer", "/shaders/expand_vertex", "/shaders/shine111" },
  { "blue_energizer", "/shaders/expand_vertex", "/shaders/energizer_blue" },
  { "red_energizer", "/shaders/expand_vertex", "/shaders/energizer_red" },
  { "yellow _energizer", "/shaders/expand_vertex", "/shaders/energizer_yellow" },
  { "white_Energizer", "/shaders/expand_vertex", "/shaders/energizer_white" },
  { "orange_energizer", "/shaders/expand_vertex", "/shaders/energizer_orange" },
  { "yellow_pixent", "/shaders/expand_vertex", "/shaders/shine122" },
  { "green_pixent", "/shaders/expand_vertex", "/shaders/pixent_green" },
  { "blue_pixent", "/shaders/expand_vertex", "/shaders/pixent_blue" },
  -- shader 18, never sold (server exclusives_config.lua, a boss drop; shaders.xml via server/tools/install_outfits.py)
  { "ember_pixent", "/shaders/expand_vertex", "/shaders/pixent_ember" },
  -- the Chaos outfit shaders, written for this server (server cosmetics_config.lua outfitShaders, shaders.xml ids
  -- 19-24 via server/tools/install_outfits.py; off on the server until the owner turns them on and prices them)
  { "chaos_ember_glow", "/shaders/chaos_outfit_vertex", "/shaders/chaos_outfit_ember_glow" },
  { "chaos_frost_rime", "/shaders/chaos_outfit_vertex", "/shaders/chaos_outfit_frost_rime" },
  { "chaos_void_flicker", "/shaders/chaos_outfit_vertex", "/shaders/chaos_outfit_void_flicker" },
  { "chaos_holy_radiance", "/shaders/chaos_outfit_vertex", "/shaders/chaos_outfit_holy_radiance" },
  { "chaos_blood_pulse", "/shaders/chaos_outfit_vertex", "/shaders/chaos_outfit_blood_pulse" },
  { "chaos_spectral_ghost", "/shaders/chaos_outfit_vertex", "/shaders/chaos_outfit_spectral_ghost" },
}

function init()
  -- one missing or broken shader file must not stop the client from starting
  local function create(name, vertex, fragment)
    local ok, err = pcall(g_shaders.createOutfitShader, name, vertex, fragment)
    if not ok then
      g_logger.warning('[chaosshaders] ' .. name .. ': ' .. tostring(err))
    end
  end
  for _, s in ipairs(SHADERS) do
    create(s[1], s[2], s[3])
  end
  create("blue Dortmond", "/shaders/expand_vertex", "/shaders/shine11")
end

function terminate()
end
