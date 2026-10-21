-- The base client's Lua console (Ctrl+T) ran any Lua a player typed: a whole bot in one line (walk, attack, cast,
-- loot in a loop), the removed vBot by another door. Players' clients get this stand-in instead (assemble_client.sh
-- copies the overlay over the base module): the same module name and the functions other modules call
-- (corelib keybinds.lua bindHotkey, client_autoreloadmodule flushLines / show), all doing nothing. No toggle, so the
-- top bar's Developer > Console entry hides itself (chaos_topbar.lua findAction). Logs still go to the log file.
-- client/BASE.md "Lua console removed".

function init() end
function terminate() end
function show() end
function hide() end
function disable() end
function hideButton() end
function bindHotkey() end
function flushLines() end
function addLine() end
function clear() end
