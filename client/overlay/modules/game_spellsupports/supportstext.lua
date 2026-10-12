-- Text helpers of the spell supports window that need no client API (tested by supportstext_test.lua).
--   SupportsText.shorten(text, fits)       the longest start of `text`, cut at a word and ended with "...", for
--                                          which fits(candidate) is true (text itself when it fits); second
--                                          result: true when it was shortened
--   SupportsText.wrap(text, width, indent) `text` broken into lines of at most `width` characters at spaces;
--                                          lines after the first start with `indent`

SupportsText = {}

local ELLIPSIS = '...'

function SupportsText.shorten(text, fits)
  text = tostring(text or '')
  if text == '' or fits(text) then return text, false end
  -- cut points: the end of every word (trailing spaces and punctuation that would sit before "..." dropped)
  local cuts = {}
  for pos in text:gmatch('%S+()') do
    if pos <= #text then cuts[#cuts + 1] = pos - 1 end
  end
  local function at(n)
    return (text:sub(1, n):gsub('[%s,;:%.%(]+$', '')) .. ELLIPSIS
  end
  -- binary search: the candidate grows with the cut, so "fits" turns from true to false once
  local lo, hi, best = 1, #cuts, nil
  while lo <= hi do
    local mid = math.floor((lo + hi) / 2)
    if fits(at(cuts[mid])) then
      best, lo = mid, mid + 1
    else
      hi = mid - 1
    end
  end
  if best then return at(cuts[best]), true end
  -- not even the first word fits: cut it by characters
  lo, hi = 1, math.min(#text, cuts[1] or #text)
  local chars
  while lo <= hi do
    local mid = math.floor((lo + hi) / 2)
    if fits(at(mid)) then
      chars, lo = mid, mid + 1
    else
      hi = mid - 1
    end
  end
  return chars and at(chars) or ELLIPSIS, true
end

function SupportsText.wrap(text, width, indent)
  text = tostring(text or '')
  indent = indent or ''
  width = math.max(tonumber(width) or 60, 4)
  local lines, line = {}, ''
  for word in text:gmatch('%S+') do
    local limit = #lines == 0 and width or width - #indent
    if line == '' then
      line = word
    elseif #line + 1 + #word <= limit then
      line = line .. ' ' .. word
    else
      lines[#lines + 1] = line
      line = word
    end
  end
  if line ~= '' or #lines == 0 then lines[#lines + 1] = line end
  return table.concat(lines, '\n' .. indent)
end

return SupportsText
