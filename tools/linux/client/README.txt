Cinders of Chaos: Linux client
==============================

The game client for 64-bit Linux: Ubuntu 22.04 or newer, Debian 12 or newer, and most desktop distributions of the
same age (built on Ubuntu 22.04).

1. Extract the archive (tar -xzf CindersOfChaos-Client-Linux.tar.gz).
2. Run ./run-client.sh in the extracted folder (or double-click it in a file manager that runs scripts).
3. Log in. The client connects to the server address the release was built for (BUILD_INFO.txt, "server host").
   Another server: change host = "..." in init.lua (and the two http://...:8090/clientservices addresses).

What it needs from the system
  A desktop session (X11, or Wayland with XWayland) and OpenGL. Most desktops have everything. On a minimal install:
    sudo apt install libgl1 libglu1-mesa libx11-6 libasound2 libssl3 zlib1g libbz2-1.0
  (Ubuntu 24.04 calls the sound library libasound2t64.) Sound goes through ALSA or PulseAudio/PipeWire.
  Everything else (PhysicsFS, OpenAL, libzip and their libraries) is in lib/ next to the client.

Problems
  - "error while loading shared libraries: libGL.so.1" (or another one): install the packages above.
  - No GPU driver, or a virtual machine without 3D: LIBGL_ALWAYS_SOFTWARE=1 ./run-client.sh (slower).
  - No sound card: run-client.sh then turns sound off by itself (ALSOFT_DRIVERS=null).
  - Without a desktop (a server, tests): Xvfb :99 & then DISPLAY=:99 LIBGL_ALWAYS_SOFTWARE=1 ./run-client.sh
  - Settings, logs and crash reports are in ~/.local/share/ (the client's folder there).

Folders
  chaos-client   the client (start it through run-client.sh)
  lib/           its libraries
  data/          images, sounds, fonts; data/things/1098 holds the Cinders of Chaos Tibia.dat and Tibia.spr
  modules/ mods/ the game's interface
  BUILD_INFO.txt says which commits this client was built from and its client build number.
