import {Config} from '@remotion/cli/config';

// Use a local Chromium when one is given (no browser download). Otherwise Remotion fetches its own.
if (process.env.REMOTION_CHROME) {
  Config.setBrowserExecutable(process.env.REMOTION_CHROME);
}
Config.setVideoImageFormat('png');
Config.setCodec('h264');
Config.setCrf(18);
Config.setPixelFormat('yuv420p');
