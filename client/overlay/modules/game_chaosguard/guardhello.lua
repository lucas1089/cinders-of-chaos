-- The client guard's module hello (no client API; guardhello_test.lua). The C++ part of the guard (base patch 0035,
-- client/BASE.md "Client guard") answers the server's challenge; this hello tells the server, from Lua, that our
-- overlay runs: the build and how many of our modules (game_*, client_chaos_*) are loaded. The server
-- (server/data/scripts/chaos/clientguard.lua) expects it within 30 s of the login and at least 20 modules.
GuardHello = {}

function GuardHello.isOurs(name)
  return type(name) == 'string' and (name:find('^game_') ~= nil or name:find('^client_chaos') ~= nil)
end

-- modules: list of {name = string, loaded = bool}
function GuardHello.count(modules)
  local n = 0
  for _, m in ipairs(modules or {}) do
    if m.loaded and GuardHello.isOurs(m.name) then
      n = n + 1
    end
  end
  return n
end

function GuardHello.payload(build, modules)
  return { action = 'hello', data = { build = tonumber(build) or 0, modules = GuardHello.count(modules) } }
end
