-- Registers the outfit shaders the server sends by name (data/XML/shaders.xml of Hellgrave Exodus,
-- ids 1-17) so monster modifiers, store shaders and outfit shaders draw. Same list and files as the
-- Exodus client's game_shaders module; the .frag files are in data/shaders.
-- The server names "blue Dortmond" (id 5) with a space, the Exodus client "blue_Dortmond": both are registered.

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
}

function init()
  for _, s in ipairs(SHADERS) do
    g_shaders.createOutfitShader(s[1], s[2], s[3])
  end
  g_shaders.createOutfitShader("blue Dortmond", "/shaders/expand_vertex", "/shaders/shine11")
end

function terminate()
end
