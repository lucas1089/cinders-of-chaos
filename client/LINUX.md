# Running the client on Linux

Tested in a Ubuntu 24.04 cloud container (software OpenGL, virtual display): the client builds, logs in to the server
and enters the game.

## Build
```
sudo apt-get install -y cmake g++ libboost-all-dev libphysfs-dev libogg-dev libvorbis-dev zlib1g-dev libzip-dev \
  libbz2-dev libssl-dev libopenal-dev libglew-dev libluajit-5.1-dev libgl1-mesa-dev libglu1-mesa-dev libx11-dev
tools/assemble_client.sh <base-client-dir> <game-dir>       # patches (C++ and Lua) + overlay + spell icons
mkdir build && cd build
cmake <game-dir> -DCMAKE_BUILD_TYPE=Release -DLUAJIT=ON -DPHYSFS_LIBRARY=/usr/lib/x86_64-linux-gnu/libphysfs.so
make -j$(nproc)
```
`-DPHYSFS_LIBRARY=...so`: Ubuntu's static `libphysfs.a` has no archive index and the link fails without it.

## Run
Put `Tibia.dat`/`Tibia.spr` (10.98) in `<game-dir>/data/things/1098/`, copy or link the `AstraClient` binary into
`<game-dir>` and start it from there. Without a GPU: `LIBGL_ALWAYS_SOFTWARE=1 ./AstraClient`; headless:
`Xvfb :99 &` then `DISPLAY=:99 ...`.

## What the first run found (fixed)
- The client's own 0x9F player-info packet uses 2-byte spell ids and an extra byte; 10.98 servers send 1-byte ids
  (`base-patches/0008-protocol-1098-player-info.patch`). Without it the rest of the login packet was dropped.
- Several imported modules depended on modules or UI styles of the clients they came from (stash, bank, event...);
  a missing style or module stops the client at start. Fixed with guards and `client_chaos_theme/compat.otui`.
- The overlay used to replace `client_background`, which other base modules call; now only its images are replaced.

Still logged but harmless at login: a missing `getItemsPrice` in the base client's cyclopedia, and "invalid slot".
