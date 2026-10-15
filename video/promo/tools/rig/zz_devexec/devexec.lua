-- TEST ONLY (video/promo/README.md "Live rig"): rig.sh cx writes Lua to <client>/devexec/cmd.lua; this runs it
-- once per change and logs "DEVEXEC ok <result>" or "DEVEXEC ERROR <message>" to the client log.
DevExec = {}
local last = nil
local function tick()
  local ok, c = pcall(g_resources.readFileContents, '/devexec/cmd.lua')
  if ok and c and c ~= '' and c ~= last then
    last = c
    local fn, err = loadstring(c)
    if not fn then
      g_logger.info('DEVEXEC compile ' .. tostring(err))
    else
      local ok2, res = pcall(fn)
      g_logger.info('DEVEXEC ' .. (ok2 and 'ok ' or 'ERROR ') .. tostring(res))
    end
  end
  scheduleEvent(tick, 400)
end
function DevExec.init() scheduleEvent(tick, 1000) end
