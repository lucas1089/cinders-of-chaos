-- The Shader row of the Outfit window (base patch 0045 in modules/game_outfit): pure logic, no client API, so
-- outfitshaderlist_test.lua runs it under plain Lua. The server's outfit window packet lists the shaders the
-- character owns as {shaders.xml id, shader name}; the window lists those, a "None" entry first, and sends the
-- picked name back in the set-outfit packet. The server checks ownership again (Game::playerChangeOutfit refuses
-- the whole change for a shader the character does not own), so a name the list does not hold is never sent.

OutfitShaderList = {}
local L = OutfitShaderList

L.MAX = 255        -- the packet's count is one byte
L.MAX_NAME = 64

-- the names players see: the store's names (server shop_config.lua, by shaders.xml id), the exclusives
-- (exclusives_config.lua) and the Chaos outfit shaders (cosmetics_config.lua outfitShaders). The test checks
-- every one against those files.
L.LABELS = {
  blue_loohs = { id = 1, label = "Frost Haze" },
  bloohs_green = { id = 2, label = "Venom Haze" },
  bloohs_red = { id = 3, label = "Ember Haze" },
  bloohs_white = { id = 4, label = "Pale Haze" },
  ["blue Dortmond"] = { id = 5, label = "Azure Waves" },
  red_dortmond = { id = 6, label = "Crimson Waves" },
  white_dortmond = { id = 7, label = "Ivory Waves" },
  green_dortmond = { id = 8, label = "Venom Waves" },
  pink_energizer = { id = 9, label = "Void Pulse" },
  blue_energizer = { id = 10, label = "Frost Pulse" },
  red_energizer = { id = 11, label = "Blood Pulse" },
  ["yellow _energizer"] = { id = 12, label = "Golden Pulse" },
  white_Energizer = { id = 13, label = "Spectral Pulse" },
  orange_energizer = { id = 14, label = "Infernal Pulse" },
  yellow_pixent = { id = 15, label = "Golden Sparks" },
  green_pixent = { id = 16, label = "Verdant Sparks" },
  blue_pixent = { id = 17, label = "Arcane Sparks" },
  ember_pixent = { id = 18, label = "Cinder Sparks" },
  chaos_ember_glow = { id = 19, label = "Ember Glow" },
  chaos_frost_rime = { id = 20, label = "Frost Rime" },
  chaos_void_flicker = { id = 21, label = "Void Flicker" },
  chaos_holy_radiance = { id = 22, label = "Holy Radiance" },
  chaos_blood_pulse = { id = 23, label = "Heartblood" },
  chaos_spectral_ghost = { id = 24, label = "Spectral Ghost" },
}

-- a readable name for a shader the table does not know: "blue_pixent" -> "Blue Pixent"
function L.label(name)
  if type(name) ~= "string" or name == "" then
    return "None"
  end
  local known = L.LABELS[name]
  if known then
    return known.label
  end
  local words = {}
  for w in name:gsub("^chaos_", ""):gmatch("[^%s_]+") do
    words[#words + 1] = w:sub(1, 1):upper() .. w:sub(2):lower()
  end
  return #words > 0 and table.concat(words, " ") or name
end

-- the server's list ({id, name} pairs, or {id = , name = }) as entries {id, name, label}, sorted by label;
-- anything malformed or repeated is left out
function L.entries(serverList)
  local out, seen = {}, {}
  if type(serverList) ~= "table" then
    return out
  end
  for _, s in ipairs(serverList) do
    if type(s) == "table" then
      local id = tonumber(s[1] or s.id)
      local name = s[2] or s.name
      if id and id >= 1 and id <= 65535 and id == math.floor(id) and type(name) == "string" and name ~= ""
          and #name <= L.MAX_NAME and not seen[name] then
        seen[name] = true
        out[#out + 1] = { id = id, name = name, label = L.label(name) }
        if #out >= L.MAX then
          break
        end
      end
    end
  end
  table.sort(out, function(a, b)
    if a.label ~= b.label then
      return a.label < b.label
    end
    return a.id < b.id
  end)
  return out
end

function L.find(entries, name)
  if type(name) ~= "string" or name == "" then
    return nil
  end
  for _, e in ipairs(entries or {}) do
    if e.name == name then
      return e
    end
  end
  return nil
end

-- the shader name the set-outfit packet carries: an owned one, or "" (none). A worn shader the list no longer
-- holds is dropped, else the server would refuse the whole outfit change.
function L.outgoing(entries, name)
  return L.find(entries, name) and name or ""
end

-- the text of the window's Shader row
function L.text(entries, name)
  local e = L.find(entries, name)
  return e and e.label or "None"
end

-- the rows of the selection list: "None" first, then the owned shaders; a search text filters by label or name
-- (plain text, case-insensitive); "None" stays while there is no search
function L.rows(entries, search)
  local rows = {}
  local q = type(search) == "string" and search:lower():gsub("^%s+", ""):gsub("%s+$", "") or ""
  if q == "" then
    rows[1] = { id = 0, name = "", label = "None" }
  end
  for _, e in ipairs(entries or {}) do
    if q == "" or e.label:lower():find(q, 1, true) or e.name:lower():find(q, 1, true) then
      rows[#rows + 1] = e
    end
  end
  return rows
end
