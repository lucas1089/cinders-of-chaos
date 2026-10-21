-- Task names said to the base task NPC (Mermod) and the kills of its tasks (server/README.md "Task NPC names").
-- Beta report 2026-10-22: saying a task name did nothing and kills did not count. The base NPC only took a name after
-- "normal" or "daily" in a separate line and compared it letter for letter; its kill script compared the shown name,
-- case sensitive, and gave a party member the killer's task. tools/patch_task_npc.py makes both use this file.
-- Pure Lua (no engine call): tests/task_names_test.lua.
ChaosTaskNames = ChaosTaskNames or {}
local N = ChaosTaskNames

-- lower case; brackets, quotes and apostrophes out; hyphens and underscores read as spaces; one space between words;
-- no end punctuation; a leading or trailing word "task" dropped
function N.normalize(s)
	if type(s) ~= "string" then
		return ""
	end
	s = s:lower()
	s = s:gsub("[%[%]{}()\"`]", " "):gsub("'", ""):gsub("[%-_]", " ")
	s = s:gsub("%s+", " "):gsub("^ ", ""):gsub(" $", "")
	s = s:gsub("[%.!?,;:]+$", ""):gsub(" $", "")
	s = s:gsub("^task ", ""):gsub(" task$", "")
	return s
end

-- the last word without a plural "s" ("raging demons" and "raging demon" are one name)
local function stem(s)
	if #s > 3 then
		return (s:gsub("s$", ""))
	end
	return s
end

-- a said name and a listed name are the same task
function N.same(a, b)
	local na, nb = N.normalize(a), N.normalize(b)
	if na == "" or nb == "" then
		return false
	end
	return na == nb or stem(na) == stem(nb)
end

-- the index of the entry of list (a task table: {name = ...}) whose name is name, or nil
function N.find(list, name)
	for i, e in ipairs(list or {}) do
		if type(e) == "table" and N.same(name, e.name) then
			return i
		end
	end
	return nil
end

-- what a player said at the NPC: "normal <name>", "daily <name>" or a bare task name (normal list first). Returns
-- "normal" or "daily" and the index in that list, or nil when it names no task.
function N.route(msg, normal, daily)
	local m = N.normalize(msg)
	local rest = m:match("^normal (.+)$")
	if rest then
		local i = N.find(normal, rest)
		if i then
			return "normal", i
		end
		return nil
	end
	rest = m:match("^daily (.+)$")
	if rest then
		local i = N.find(daily, rest)
		if i then
			return "daily", i
		end
		return nil
	end
	local i = N.find(normal, m)
	if i then
		return "normal", i
	end
	i = N.find(daily, m)
	if i then
		return "daily", i
	end
	return nil
end

-- true when one of names is in list (any case, the same rules as N.same)
function N.inList(list, ...)
	for _, name in ipairs({...}) do
		if type(name) == "string" then
			for _, n in ipairs(list or {}) do
				if N.same(name, n) then
					return true
				end
			end
		end
	end
	return false
end

-- a kill counts for a task (task = {name, mons_list}) by the monster's shown name or its type name (a renamed or
-- prefixed monster is still its type)
function N.killCounts(task, shownName, typeName)
	if type(task) ~= "table" then
		return false
	end
	for _, n in ipairs({shownName, typeName}) do
		if type(n) == "string" and (N.same(n, task.name) or N.inList(task.mons_list, n)) then
			return true
		end
	end
	return false
end

return N
