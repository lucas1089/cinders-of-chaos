-- ChaosHelperFollow: follow a friend or the party leader (pure Lua: no engine calls; tests: helper_follow_test.lua).
-- The old helper's "follow friend": g_game.follow(creature) asks the server to walk the character after another player. The
-- server drops that follow by itself when anything else takes the walk, so the helper checks now and then and asks again.
-- What it does here:
--   * the leader is a friend by name, or the party leader (the player with the yellow party shield);
--   * `distance` is how close the character gets: 1 walks next to the leader (a plain follow), more lets go of the follow
--     once the leader is that near and takes it up again when the leader is one tile farther than that (no flapping);
--   * a protection zone, the helper switch and a leader that is out of view or on another floor do nothing and ask nothing
--     (a follow the helper started is let go when the leader leaves the view: it never walks to a spot where the leader was);
--   * the follow is asked for at most every 250 ms and, after FAIL_MAX asks in a row that did not start a follow, not for
--     RETRY_MS, so a leader behind a wall costs a few packets and no more.
-- Following and attacking exclude each other in the engine, so a follow cancels the attack and the helper's fight systems
-- pause while it lasts (helper.lua pausedWhy): the character walks to its leader first and fights when it arrives.
ChaosHelperFollow = ChaosHelperFollow or {}
local F = ChaosHelperFollow

F.ASK_GAP_MS = 250
F.FAIL_MAX = 5
F.RETRY_MS = 5000
F.DISTANCE_MAX = 5

function F.newState()
  return { lastAsk = nil, fails = 0, holdUntil = 0, ours = false }
end

-- pick the leader out of the players in view. players: { { id, name, position, shield, isSelf } }, cfg: the follow section
-- { enabled, mode = 'name' | 'leader', name }. Returns the player or nil.
function F.leaderOf(cfg, players)
  if type(cfg) ~= 'table' then return nil end
  local want = nil
  if cfg.mode ~= 'leader' then
    want = ChaosHelperAlly.cleanName(cfg.name)
    if not want then return nil end
    want = want:lower()
  end
  for _, p in ipairs(players or {}) do
    if not p.isSelf then
      if want then
        if type(p.name) == 'string' and p.name:lower() == want then return p end
      elseif ChaosHelperAlly.isLeaderShield(p.shield) then
        return p
      end
    end
  end
  return nil
end

-- What to do now: returns 'follow', 'release' or nil, and a reason (for the status line and the tests).
-- st: F.newState(); in = {
--   helperOn, pz,
--   leader = the player from F.leaderOf (nil: not in view), from = the player's position,
--   following = the id of the creature the character follows now (nil: none),
--   now }
-- The state keeps what the helper asked for (st.ours: the follow is the helper's).
function F.decide(cfg, st, input)
  if type(cfg) ~= 'table' or cfg.enabled ~= true then
    if st.ours and input.following then
      st.ours = false
      return 'release', 'off'
    end
    st.ours = false
    return nil, 'off'
  end
  if not input.helperOn then return nil, 'helperoff' end
  if input.pz then return nil, 'pz' end
  local leader, from, now = input.leader, input.from, input.now
  if not leader or not leader.position or not from or leader.position.z ~= from.z
      or not ChaosHelperLogic.inReach(from, leader.position) then
    -- out of view or on another floor: let our own follow go, never chase the old spot
    if st.ours and input.following then
      st.ours = false
      return 'release', 'away'
    end
    st.ours = false
    return nil, 'away'
  end
  local distance = math.max(1, math.min(F.DISTANCE_MAX, math.floor(tonumber(cfg.distance) or 1)))
  local dist = ChaosHelperLogic.distance(from, leader.position)
  local followingLeader = input.following ~= nil and input.following == leader.id
  if followingLeader then
    st.fails = 0
    st.ours = true
    if distance > 1 and dist <= distance then
      st.ours = false
      return 'release', 'near'
    end
    return nil, 'following'
  end
  -- not following the leader (nothing, or somebody else the player chose by hand: that is left alone)
  if input.following ~= nil and not st.ours then return nil, 'other' end
  if distance > 1 and dist <= distance + 1 then return nil, 'near' end
  if dist <= 1 and distance <= 1 then return nil, 'adjacent' end
  if now < st.holdUntil then return nil, 'retry' end
  if st.lastAsk and now - st.lastAsk < F.ASK_GAP_MS then return nil, 'gap' end
  st.lastAsk = now
  st.fails = st.fails + 1
  if st.fails > F.FAIL_MAX then
    st.fails = 0
    st.holdUntil = now + F.RETRY_MS
    return nil, 'giveup'
  end
  st.ours = true
  return 'follow', 'ask'
end

return ChaosHelperFollow
