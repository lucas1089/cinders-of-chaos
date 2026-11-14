-- A fake widget engine for the tests of the trade window (tradeview_test.lua, tradewindow_test.lua; not loaded by the client).
-- It builds every widget from a REAL .otui (tradewindow.otui, npctalk.otui) (the ids under each style, nested ones too), so a lookup of an id the
-- file lacks raises in the test as it does in the client. Call TradeFake.install(path of the .otui) before loading the module code: it
-- defines g_ui, tr and the engine constants, and returns {styles, new, windowOf}.
TradeFake = {}
function TradeFake.install(otuiPath)
  -- ---------------------------------------------------------------- the .otui: styles, their children, ids
  local f = assert(io.open(otuiPath, 'r'))
  local text = f:read('*a')
  f:close()
  local styles = {}
  local stack = {}      -- {indent, node}
  for line in (text .. '\n'):gmatch('([^\n]*)\n') do
    if not line:match('^%s*//') and line:match('%S') then
      local indent = #line:match('^( *)')
      local name, base = line:match('^([%a][%w]*)%s*<%s*([%w]+)%s*$')
      if name then
        local node = { style = name, base = base, kids = {}, props = {} }
        styles[name] = node
        stack = { { indent = 0, node = node } }
      else
        while #stack > 1 and stack[#stack].indent >= indent do table.remove(stack) end
        local parent = stack[#stack].node
        local style = line:match('^%s+([%a][%w]*)%s*$')
        if style then
          local kid = { style = style, kids = {}, props = {} }
          parent.kids[#parent.kids + 1] = kid
          stack[#stack + 1] = { indent = indent, node = kid }
        else
          local k, v = line:match('^%s+([%w%-!&$@%.]+):%s*(.-)%s*$')
          if k and indent == stack[#stack].indent + 2 then parent.props[k] = v end
        end
      end
    end
  end

  -- ---------------------------------------------------------------- the fake engine
  local Widget = {}
  Widget.__index = function(t, k) return Widget[k] end
  local function new(style, parent)
    local w = setmetatable({ style = style, parent = parent, kids = {}, text = '', visible = true, enabled = true,
      checked = false, destroyed = false, margins = {}, scroll = { min = 0, max = 0, value = 0 } }, Widget)
    if parent then parent.kids[#parent.kids + 1] = w end
    return w
  end
  local function build(node, parent)
    local w = new(node.style, parent)
    w.id = node.props.id
    if node.props.visible == 'false' then w.visible = false end
    local own = styles[node.style]
    local function addKids(from)
      for _, kid in ipairs(from.kids) do build(kid, w) end
    end
    addKids(node)
    if own and own ~= node then addKids(own) end
    return w
  end
  function Widget:isDestroyed() return self.destroyed end
  function Widget:destroy()
    self.destroyed = true
    if self.parent then
      for i, k in ipairs(self.parent.kids) do if k == self then table.remove(self.parent.kids, i) break end end
    end
  end
  function Widget:destroyChildren() for i = #self.kids, 1, -1 do self.kids[i]:destroy() end self.kids = {} end
  function Widget:recursiveGetChildById(id)
    for _, k in ipairs(self.kids) do
      if k.id == id then return k end
      local r = k:recursiveGetChildById(id)
      if r then return r end
    end
  end
  function Widget:getChildById(id) for _, k in ipairs(self.kids) do if k.id == id then return k end end end
  function Widget:getChildCount() return #self.kids end
  function Widget:getChildren() return self.kids end
  function Widget:getChildByIndex(i) return self.kids[i] end
  function Widget:moveChildToIndex(child, index)
    for i, k in ipairs(self.kids) do if k == child then table.remove(self.kids, i) break end end
    table.insert(self.kids, math.max(1, math.min(#self.kids + 1, index)), child)
  end
  function Widget:setId(id) self.id = id end
  function Widget:setText(t)
    local old = self.text
    self.text = t
    if self.onTextChange and old ~= t then self.onTextChange(self, t, old) end
  end
  function Widget:getText() return self.text end
  function Widget:getTextSize() return { width = #self.text * 6, height = 12 } end
  function Widget:setWidth(w) self.width = w end
  function Widget:setHeight(h) self.height = h end
  function Widget:setMarginLeft(v) self.margins.left = v end
  function Widget:setMarginTop(v) self.margins.top = v end
  function Widget:addAnchor() end
  function Widget:setVisible(v) self.visible = v end
  function Widget:isVisible() return self.visible end
  function Widget:show() self.visible = true end
  function Widget:hide() self.visible = false end
  function Widget:setEnabled(v) self.enabled = v end
  function Widget:isEnabled() return self.enabled end
  function Widget:setChecked(v)
    if self.checked ~= v then
      self.checked = v
      if self.onCheckChange then self.onCheckChange(self, v) end
    end
  end
  function Widget:isChecked() return self.checked end
  function Widget:setOpacity(o) self.opacity = o end
  function Widget:setColor(c) self.color = c end
  function Widget:setTooltip(t) self.tooltip = t end
  function Widget:removeTooltip() self.tooltip = nil end
  function Widget:setItem(i) self.item = i end
  function Widget:setItemId(id) self.itemId = id end
  function Widget:setItemCount(c) self.count = c end
  function Widget:setShowCount(v) self.showCount = v end
  function Widget:isFocused() return self.focused == true end
  function Widget:focus() self.focused = true end
  function Widget:recursiveFocus() self.focused = true end
  function Widget:setMinimum(v) self.scroll.min = v if self.scroll.value < v then self.scroll.value = v end end
  function Widget:setMaximum(v) self.scroll.max = v if self.scroll.value > v then self.scroll.value = v end end
  function Widget:setValue(v)
    v = math.max(self.scroll.min, math.min(self.scroll.max, v))
    if v ~= self.scroll.value then
      self.scroll.value = v
      if self.onValueChange then self.onValueChange(self, v) end
    end
  end
  function Widget:getValue() return self.scroll.value end

  local KNOWN = {}
  g_ui = { importStyle = function() end, getRootWidget = function() return TradeFake.root end, createWidget = function(style, parent)
    local node = styles[style]
    assert(node or style:match('^Chaos') or style:match('^UI') or style == 'PopupMenu', 'unknown style ' .. style)
    if node then
      local w = new(style, parent)
      for _, kid in ipairs(node.kids) do build(kid, w) end
      return w
    end
    return new(style, parent)
  end }
  tr = function(k, ...)
    local args = { ... }
    if #args == 0 then return k end
    return (k:gsub('%%s', function() return table.remove(args, 1) end))
  end
  AnchorTop, AnchorLeft = 1, 2
  MouseLeftButton, MouseRightButton = 1, 2
  KeyboardFocusReason = 1
  GOLD_COINS = 3031


  local function windowOf(style)
    local node = assert(styles[style], style .. ' is not in tradewindow.otui')
    local w = new(style, nil)
    w.id = node.props.id
    for _, kid in ipairs(node.kids) do build(kid, w) end
    return w
  end
  return { styles = styles, new = new, build = build, windowOf = windowOf, Widget = Widget }
end
