-- client_chaos_streamer: starts streamer mode (streamer.lua) and cinema mode (cinema.lua). Not sandboxed, so the
-- globals ChaosStreamer and ChaosCinema reach the settings module's dataset (base patch 0186) and the other modules.
ChaosStreamerModule = ChaosStreamerModule or {}

function ChaosStreamerModule.init()
  ChaosStreamer.init()
  ChaosCinema.init()
end

function ChaosStreamerModule.terminate()
  ChaosCinema.terminate()
  ChaosStreamer.terminate()
end
