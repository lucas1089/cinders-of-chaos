-- The website's account API for the character select (website/README.md "Client API"; URL: Services.account in
-- init.lua, base patch 0050). JSON over HTTPS (plain HTTP only to 127.0.0.1 / localhost: a local test site).
--
-- The account name and password the client already holds for the game login (G.account / G.password, kept by the
-- stock client as before) go to the website once, in the login request; the website answers with a session token
-- (30 minutes) that the later requests carry. The token lives in this file's memory only: it is never written to the
-- settings, and it is dropped (and ended on the website) when the character select goes back to the login screen.

ChaosAccountApi = {}
local Api = ChaosAccountApi
local Core = CharSelectCore

local token, tokenExpires
local state            -- the last state answer (account + looks)
local busy = false
local pending = {}     -- callbacks waiting for a login in flight

function Api.url()
  return Core.apiUrl(Services and Services.account)
end

function Api.enabled()
  return Api.url() ~= nil and HTTP ~= nil and HTTP.post ~= nil
end

function Api.state()
  return state
end

-- one request; cb(body, err): body is the decoded answer (also of a refused request), err a transport error or nil
local function post(body, cb)
  local url = Api.url()
  if not url then
    cb(nil, 'no account API URL')
    return
  end
  local ok, err = pcall(HTTP.post, url, json.encode(body), function(data, httpErr)
    local decoded
    if type(data) == 'string' and data ~= '' then
      local okj, res = pcall(json.decode, data)
      if okj and type(res) == 'table' then decoded = res end
    end
    if decoded then
      cb(decoded, decoded.ok and nil or httpErr)
    else
      cb(nil, httpErr or 'no answer')
    end
  end)
  if not ok then cb(nil, tostring(err)) end
end

local function finishLogin(ok, text)
  busy = false
  local waiting = pending
  pending = {}
  for _, fn in ipairs(waiting) do fn(ok, text) end
end

-- a valid token, logging in with the game login's account and password when there is none; cb(ok, errorText)
function Api.ensureLogin(cb)
  if token and tokenExpires and os.time() < tokenExpires - 30 then
    cb(true)
    return
  end
  pending[#pending + 1] = cb
  if busy then return end
  local account, password = G and G.account, G and G.password
  if type(account) ~= 'string' or account == '' or type(password) ~= 'string' or password == '' then
    finishLogin(false, 'Log in again to use the website features.')
    return
  end
  busy = true
  post(Core.loginRequest(account, password, Core.nonce()), function(body, err)
    if body and body.ok and type(body.token) == 'string' then
      token = body.token
      tokenExpires = os.time() + math.max(60, tonumber(body.expiresIn) or 1500) -- the client's own clock
      state = { account = body.account, looks = body.looks }
      finishLogin(true)
    else
      token = nil
      finishLogin(false, Core.errorText(body, err))
    end
  end)
end

-- the account's state (looks, classes, slots, season); cb(state or nil, errorText)
function Api.refresh(cb)
  Api.ensureLogin(function(ok, text)
    if not ok then cb(nil, text) return end
    post({ action = 'state', token = token }, function(body, err)
      if body and body.ok then
        state = { account = body.account, looks = body.looks }
        cb(state)
      elseif body and body.error == 'token' then
        token = nil
        cb(nil, Core.errorText(body, err))
      else
        cb(nil, Core.errorText(body, err))
      end
    end)
  end)
end

-- creates a character; cb(ok, text, answer)
function Api.create(form, cb)
  Api.ensureLogin(function(ok, text)
    if not ok then cb(false, text) return end
    post(Core.createRequest(token, form, Core.nonce()), function(body, err)
      if body and body.ok then
        cb(true, body.message or 'Created.', body)
      else
        if body and body.error == 'token' then token = nil end
        cb(false, Core.errorText(body, err), body)
      end
    end)
  end)
end

-- back to the login screen: the token ends here and on the website
function Api.reset()
  if token then
    local t = token
    pcall(post, { action = 'logout', token = t }, function() end)
  end
  token, tokenExpires, state = nil, nil, nil
  busy, pending = false, {}
end
