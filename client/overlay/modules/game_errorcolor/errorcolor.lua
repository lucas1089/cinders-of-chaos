-- Colours the server's error lines. The stock message module looks up MessageTypes[mode] on every message, so giving the
-- Failure mode its own coloured copy of the settings is enough; terminate puts the stock entry back.
local previous

function init()
  previous = ErrorColor.apply(MessageTypes, MessageModes.Failure, ErrorColor.COLOR)
end

function terminate()
  ErrorColor.restore(MessageTypes, MessageModes.Failure, previous)
  previous = nil
end
