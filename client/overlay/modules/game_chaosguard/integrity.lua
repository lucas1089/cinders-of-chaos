-- Module integrity and known-tool signals of the bot detection (O722; no client API, integrity_test.lua; server:
-- data/scripts/chaos/botdet.lua, botdet_core.lua, extended opcode 169; client/tools/gen_module_hashes.py makes the official list at
-- release with the same digest rule). Detection and reports only: the client sends what it finds, the server writes an event
-- and a staff member reads it. Nothing here closes the client, removes a module or stops anything.
--
-- The digest of a module: the files of the folders modules/<name> and mods/<name> that end in .lua .otui .otmod .otml .json, sorted
-- as text lines (byte order of the line), one line "<path relative to the module folder>:<sha256 of the file>\n" each, the SHA-256 of the whole
-- text is the module's digest. The key is the folder name, with "mods/" before it for the mods folder. A client folder the
-- official list does not know is an extra module (an internal bot is one), a different digest is a changed module.
Integrity = {}

Integrity.EXTS = { lua = true, otui = true, otmod = true, otml = true, json = true }
Integrity.MAX_PER_CHUNK = 60 -- entries of one message: the server reads at most 160, the opcode limit is 16 KB
Integrity.ROOTS = { '/modules', '/mods' }

-- the module a virtual path belongs to: key, path inside the module folder; nil for a file that does not count
function Integrity.split(path)
  if type(path) ~= 'string' then return nil end
  local root, name, rest = path:match('^/(%a+)/([^/]+)/(.+)$')
  if root ~= 'modules' and root ~= 'mods' then return nil end
  local ext = rest:match('%.([%w]+)$')
  if not ext or not Integrity.EXTS[ext:lower()] then return nil end
  local key = root == 'mods' and ('mods/' .. name) or name
  return key, rest
end

-- files: list of virtual paths; hashOf(path) -> hex sha256 or nil; sha(text) -> hex sha256
-- returns {key = digest}
function Integrity.digests(files, hashOf, sha)
  local byKey = {}
  for _, path in ipairs(files) do
    local key, rest = Integrity.split(path)
    if key then
      local h = hashOf(path)
      if type(h) == 'string' and h ~= '' then
        local list = byKey[key]
        if not list then list = {}; byKey[key] = list end
        list[#list + 1] = rest .. ':' .. h:lower() .. '\n'
      end
    end
  end
  local out = {}
  for key, list in pairs(byKey) do
    table.sort(list)
    out[key] = sha(table.concat(list))
  end
  return out
end

-- the messages to send: {{i = 1, n = N, b = build, m = {{key, digest}, ...}}, ...}, entries sorted by key
function Integrity.chunks(digests, build, perChunk)
  perChunk = perChunk or Integrity.MAX_PER_CHUNK
  local keys = {}
  for key in pairs(digests) do
    if #key <= 64 then keys[#keys + 1] = key end
  end
  table.sort(keys)
  local n = math.max(1, math.ceil(#keys / perChunk))
  local out = {}
  for i = 1, n do
    local m = {}
    for j = (i - 1) * perChunk + 1, math.min(#keys, i * perChunk) do
      m[#m + 1] = { keys[j], digests[keys[j]] }
    end
    out[i] = { i = i, n = n, b = tonumber(build) or 0, m = m }
  end
  return out
end

-- ---------------------------------------------------------------- known tools
-- The server sends {t = {{code, hash}, ...}}: the codes and the 16 hex digits of FNV-1a 64 of a lower-case process name or window title
-- word (client/tools/chaostoolscan_test.cpp has the vector). The scan itself is C++ (base patch 0207, Windows only,
-- g_game.chaosScanTools); it answers with the codes it found and never reports a process or window name.
function Integrity.toolSpec(list)
  local parts = {}
  if type(list) ~= 'table' then return '' end
  for _, e in ipairs(list) do
    if type(e) == 'table' and type(e[1]) == 'string' and type(e[2]) == 'string'
        and e[1]:match('^%w+$') and #e[1] >= 3 and #e[1] <= 16 and e[2]:match('^%x+$') and #e[2] == 16 and #parts < 200 then
      parts[#parts + 1] = e[1] .. ':' .. e[2]:lower()
    end
  end
  return table.concat(parts, ',')
end

-- the scan's answer ("code,code" or "") as a sorted list of at most 8 codes of 3 to 16 letters or digits
function Integrity.toolCodes(answer)
  local out, seen = {}, {}
  if type(answer) ~= 'string' then return out end
  for code in answer:gmatch('[^,]+') do
    if code:match('^%w+$') and #code >= 3 and #code <= 16 and not seen[code] and #out < 8 then
      seen[code] = true
      out[#out + 1] = code
    end
  end
  table.sort(out)
  return out
end

function Integrity.toolMessage(codes)
  return { action = 'tools', data = { c = codes } }
end

function Integrity.integrityMessage(chunk)
  return { action = 'integrity', data = chunk }
end
