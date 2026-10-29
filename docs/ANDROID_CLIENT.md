# Android client (O313): study, plan and build

Status: phase 1 done, study and plan. Phase 2 done as far as this machine can check: the engine builds for android
arm64 with the NDK through CMake, and a Gradle project packs it into an APK. See "Phase 2 status" below. Nothing has run
on a device yet.
Date of the study: 2026-10-29. Owner approval to start: 2026-10-29.
The admin app in `android/` is a separate program and is not touched.

Owner wishes (ROADMAP O313): an arm64 APK of the game client, touch controls, the same overlay modules and
sprites, and an APK that updates itself.

## Short answer

- The base client has Android code, but no build path we can run in CI. It has a NativeActivity shell, an EGL window
  with touch input, Android branches in the engine, and a Visual Studio plus Ant project. There is no CMake target
  for Android. The libraries come as a 50 MB binary blob of unknown origin.
- Our C++ patches do not block Android. They add no desktop-only GL calls. Our shaders already compile as GLSL ES 1.00.
  Three places need Android work: the encrypted pack (RAM), the update overlay (RAM) and the restart.
- The real problems are the data size and the screen. The sprite pair is over 1 GiB and `chaos.pack` is about 0.9 GB.
  The engine decrypts the pack into one RAM buffer. 69 modules open windows taller than 360 logical pixels.
- Recommended: a small APK (engine, Lua, UI, no sprite pair) with the game data downloaded on first start through the
  signed manifest, and the APK itself updated by a versioned download that is checked twice, then installed by
  Android's package installer (sideload). A store comes later and needs decisions from the owner.
- Honest estimate: 4 to 6 weeks of work for a client that starts, logs in and plays with a basic touch pad. Another
  6 to 10 weeks to make the Chaos windows usable on a phone. Details in "Estimate".

Phase 1 added no CI workflow, because the base had no Android build to run from Linux. Phase 2 adds the build and the
manual workflow `.github/workflows/android-client.yml`. See "Phase 2 status".

## Phase 2 status

Date: 2026-10-29. Build plan steps 1, 3 and 4 are done. Step 2 is written but not run here. Step 9 is written.

### What was added

| Piece | Where | What it does |
|---|---|---|
| CMake target | client base patch `0163`, `client/BASE.md` | The base CMake files get an Android branch. With the NDK toolchain they build the shared library `libcinders.so` with OpenGL ES 2, the EGL window, the touch code and the app glue. Three compile fixes and one link fix are in the same patch. |
| JNI name | client base patch `0164` | The C function for the text dialog callback gets the name of the new Java class. |
| PhysFS init | client base patch `0165` | `PHYSFS_init(NULL)` on Android. PhysFS reads its argument as a `PHYSFS_AndroidInit` pointer there, and the base's text crashed the app at start. |
| Libraries | `client/android/vcpkg/vcpkg.json`, `client/android/triplets/arm64-android-chaos.cmake` | A pinned vcpkg manifest. The baseline is the one the base client already uses. The triplet is arm64, static, release only, API 26, 16 KB page size. |
| Gradle shell | `client/android/` | A minimal Gradle project with no wrapper. The Java activity `ChaosActivity` is adapted from the base shell. It has a new package, `com.cindersofchaos.client`, new strings, current immersive mode calls, a cutout setting and no other client names. minSdk 26, targetSdk 35, arm64-v8a only, NDK r27d. |
| Assets | `client/android/tools/make_assets.sh` | Packs `init.lua`, `data`, `modules`, `mods` and `layouts` of the assembled client into `data.zip`, without the sprite pair. The engine reads that file from the APK assets, as the base did. About 71 MB. |
| Icons | `client/android/tools/gen_icons.py` | The launcher icons from `docs/brand/cinders_logo_icon.png`. |
| Workflow | `.github/workflows/android-client.yml` | Manual only. Assembles the client, builds the libraries with vcpkg, builds the APK with Gradle and uploads it as an artifact with its SHA-256. |

How to build by hand, on Linux with the SDK, NDK r27d and Gradle 8.9 or newer:

1. `client/tools/assemble_client.sh BASE_CLIENT GAME_DIR`
2. `vcpkg install` with `--x-manifest-root=client/android/vcpkg`, `--overlay-triplets=client/android/triplets` and the
   triplet `arm64-android-chaos`, with `ANDROID_NDK_HOME` set. The vcpkg tool must be at the baseline commit.
3. `client/android/tools/make_assets.sh GAME_DIR ASSETS_DIR`
4. In `client/android`: `gradle :app:assembleDebug -PchaosClientDir=GAME_DIR -PchaosDepsPrefix=VCPKG_INSTALLED/arm64-android-chaos -PchaosAssetsDir=ASSETS_DIR -PchaosClientBuild=N`

The workflow does exactly this. Secrets, names only: `CHAOS_CLIENT_KEY` and `CHAOS_RSA_PUBLIC` as for the Windows
package, and for a release signature `ANDROID_CLIENT_KEYSTORE_B64`, `ANDROID_CLIENT_KEYSTORE_PASS` and
`ANDROID_CLIENT_KEY_ALIAS`. Without the keystore secrets the APK is a debug build with the runner's debug key. The game
client has its own release key, not the key of the admin app.

### What was checked here

- Patches `0163` and `0164` apply after the 147 older patches on a fresh copy of the base. Zero rejects, and the result
  is the tree that was compiled. `client/tools/assemble_client.sh` runs to the end with them.
- With NDK r27d, android-26, arm64-v8a and Release, every engine source compiles with `-DANDROID` and the
  force-included `pch.h`. The libraries were stand-ins here: host headers for Boost 1.83, OpenSSL, LuaJIT, PhysFS,
  libzip, OpenAL, ogg and vorbis, plus empty archives. The link needed `--unresolved-symbols=ignore-all` for that
  reason. `llvm-nm` on the result lists no undefined symbol except libc, EGL, GLESv2, the NDK's own and the names of
  the stand-in libraries. The link error that this check found, `ResourceManager::encrypt`, is fixed in `0163`.
- The Gradle project builds a debug APK from that library with AGP 8.7.3 and Gradle 8.14.3, while the workflow pins 8.10.2: `aapt2 dump badging` shows
  package `com.cindersofchaos.client`, minSdk 26, targetSdk 35, native code `arm64-v8a` only. `zipalign -c -P 16`
  accepts it, `apksigner verify` accepts the debug signature, and `data.zip` is stored without compression.
- The workflow file parses as YAML and has only a `workflow_dispatch` trigger.
- `check_names.py`, `check_credits.py` and `gen_credits.py` pass. The new libraries are in `docs/CREDITS.md`.

### What is not checked

- Nothing on a device yet. The first CI build ran 2026-10-29 (`android-client.yml`, debug key): every vcpkg port
  built, `libcinders.so` linked against the real libraries, and the APK passed `apksigner`, `zipalign -P 16` and
  `aapt2`. Two fixes it needed: the triplet passes `ANDROID_ABI=arm64-v8a` (the NDK toolchain fell back to armv7
  and luajit did not assemble), and the workflow links `include/luajit` to `luajit-2.1`, because the engine
  includes `<luajit/lua.h>`.
- Everything at run time. The APK was never installed. LuaJIT on Android, the EGL window, the soft keyboard dialog,
  immersive mode, sound and the network stack are untested.
- A release signature.

### Still open

1. **File-backed data.** `chaos.pack` is not mounted on Android, so the APK starts from `data.zip` in the assets, which
   the engine reads into one RAM buffer, about 71 MB here. Fine for the Lua and UI files. The sprite pair has no path
   yet: a new patch must mount downloaded files from the app folder through PhysFS without a RAM copy, with the
   first-start download screen and the AES decision from the owner questions.
2. **No game data in the APK.** Without the pair the client stops at the missing-data error. The first-start download
   is step 5 of the plan.
3. **Restart.** Patch 0101 makes the restart an `exit`. The Java shell must start the activity again before the process
   ends. Not written.
4. **Touch layout.** The walk pad and the action bar of `client_mobile`, tap and long press, hotkey buttons, safe areas,
   the 69 windows over 360 logical pixels. Section 2 is unchanged.
5. **Window re-layout.** The engine resizes with the screen through `updateSize`. The Chaos windows have no mobile
   styles yet, except `game_event`. Phase 3.
6. **Mobile defaults.** The heavy options should start off on Android. Not set.
7. **APK self-update.** Step 8. The `android` manifest key, the installer hand-over and the publish script flag.
8. **OpenAL Soft is LGPL.** It is linked statically into the engine library. Whoever has the APK cannot relink it. For
   a public release either link it dynamically, as a separate `.so` in the APK, or offer the object files. The owner
   should decide before any public download. The same question applies to the Windows package.
9. **Encrypted data on the phone.** The Android pack path is plain: `data.zip` can be unzipped from the APK by anyone.
   Same level as the Windows loose tree before client build 13. Owner question 2 still decides.
10. **Developer verification.** Owner question 1 is unchanged.

## 1. Feasibility of the base client

Reference: the base client tree (the folder `client/BASE.md` describes). All paths below are inside that tree.

### What exists

| Piece | File | Finding |
|---|---|---|
| Shell | `android/otclientv8/src/.../*.java`, `AndroidManifest.xml` | A Java `NativeActivity` subclass. It loads the engine library, keeps the screen on, hides the system bars, shows the soft keyboard, shows a text dialog for text fields and a fatal error dialog. `minSdkVersion` 9, `targetSdkVersion` 29, landscape only. Uses `WRITE_EXTERNAL_STORAGE`, `INTERNET`, `VIBRATE`, `WAKE_LOCK`. |
| Window | `src/framework/platform/androidwindow.cpp` and `.h` | EGL, OpenGL ES 2 (`EGL_CONTEXT_CLIENT_VERSION 2`, with an ES 1 fallback). Handles surface loss and resize. |
| Touch | same file, `handleInput` | One finger: press, release and tap are a left click. Hold 500 ms and release: a right click. Move more than 8 px: a left drag. Second and third fingers: `MouseTouch2` and `MouseTouch3`. No hover, no mouse wheel, no pinch. |
| Platform | `src/framework/platform/androidplatform.cpp` | Clipboard, keyboard, cursor stubs. |
| Entry | `src/main.cpp` bottom | `android_main` with `android_native_app_glue`. |
| Engine branches | about 20 files with `#ifdef ANDROID` | `resourcemanager.cpp` (write dir is `internalDataPath`, data is read from `data.zip` in the APK assets), `application.cpp` (`m_mobile = true`, restart is `exit()`), `http/tls.h` (reads the system CA folders), `uitextedit.cpp` (no blinking cursor, text goes through the Java dialog), `glutil.h` (GLES2 headers), `logger.cpp` (logcat). |
| Mobile UI | `init.lua`, `layouts/mobile/`, `modules/client_mobile/` | `g_app.isMobile()` forces the layout `mobile`. `client_mobile` adds zoom buttons and a walk keypad. The layout README says: minimum height for mobile is 360, windows must not be taller. |
| Build | `android/otclientv8.sln`, `.androidproj`, `otclientv8_lib.vcxproj` | Visual Studio with the Android workload, NDK r21d, Ant, API 25. The engine is a `DynamicLibrary` with a hand-written list of 155 source files. |
| Libraries | `android_libs.7z` (50.8 MB) | Prebuilt `.a` files for boost_system, vorbisfile, vorbis, ssl, crypto, png, physfs, openal, ogg, luajit and libzip, for arm and arm64. No versions, no build scripts, no licence files. |
| CI | `.github/workflows/` | Only vcpkg desktop, WebAssembly and content checks. Nothing builds Android. |

### What is missing

1. **No CMake target.** `src/framework/CMakeLists.txt` handles Windows, Linux, WebAssembly and an `OPENGLES` option.
   `androidwindow.cpp`, `androidplatform.cpp`, `src/android/dependencies.cpp` and `android_native_app_glue.cpp` are
   only in the Visual Studio project. The CMake file adds X11 and `unixcrashhandler.cpp` for everything that is not
   Windows or WebAssembly.
2. **The Visual Studio source list is stale.** It lists files by hand. Files that our patches add
   (for example `xbrz.cpp`, headers like `chaospack.h`) are in the patched `CMakeLists.txt` only. A CMake build is the
   way, not the old project.
3. **The macro.** The engine tests `ANDROID`, not `__ANDROID__`. The Visual Studio project defines `ANDROID`. A CMake
   build with the NDK toolchain must add `-DANDROID` itself.
4. **Old tooling.** NDK r21d, API 25, `minSdk 9`, Ant, `android:hasCode` and the Java file all predate the current
   rules. Google Play wants a recent target API, 64-bit only and 16 KB page size support for new apps. A current NDK
   (r27 or newer) builds 16 KB aligned libraries. The binary blob cannot be trusted to do that.
5. **Unproven.** We found no sign that this path was built with the current engine tree (our fork adds 147 patches
   and about 220 touched C++ files). Treat the Android branches as untested code.

Verdict: the code is a good start (window, touch, text input, TLS roots, logging are done). The build is not. We
build a CMake path ourselves (steps 1 to 4 of the plan).

### Dependencies that need Android builds

All as static arm64 libraries built from source with the NDK, so `docs/CREDITS.md` can name the versions.

| Library | Used for | Note |
|---|---|---|
| LuaJIT | Lua engine (`-DLUAJIT=ON`) | Builds for arm64 with the NDK clang and a 64-bit host. Android allows the JIT. Fallback: plain Lua 5.3, which CI already runs. |
| OpenSSL 3 | TLS, Ed25519 signature checks in C++, AES-GCM for pack and blobs | Build with `no-shared`, `android-arm64`. |
| zlib | pack and blob inflate | The NDK ships a system zlib, usable. |
| libzip, bzip2 | update overlay ZIP | Small. |
| PhysFS | resource layer | Small, plain C. |
| OpenAL Soft | sound (base patch 0032 turns the sound framework on) | Needs the AAudio or OpenSL ES backend. |
| ogg, vorbis, vorbisfile | sound files | Small. |
| libpng | images | The NDK has none we link; build it. |
| Boost | headers: asio, system, lockfree, iostreams, uuid | Header use only. Check `boost::process`: the base already compiles it out for `ANDROID` (our patch 0101 keeps that). |
| EGL, GLESv2, log, android, OpenSLES or aaudio | system | From the NDK sysroot. |

Source for the builds: a vcpkg manifest with the `arm64-android` triplet is the first thing to try, as the Windows
jobs use vcpkg. Not verified here: whether every port builds for that triplet. Second choice: a small script per
library.

### Do our base patches build there

- **C++ patches.** 147 patches. They add no new desktop-only GL calls. The GL calls they add are `glTexImage2D`,
  `glTexSubImage2D`, `glBlendFunc` and `glBlendFuncSeparate`, all part of OpenGL ES 2.
- **Patches that already protect Android.** 0101 (restart: on Android `exit()`), 0102 (pack: returns false on
  Android), 0027 (xBRZ without `DllExport`).
- **Patches that do not know Android yet:**
  - 0102 `mountEncryptedPack` returns false on Android. The APK would start with no data. See section 3.
  - 0103 encrypted update overlay: one in-memory ZIP of the whole update. See section 3.
  - 0035 client guard: a build-time key and an OpenSSL hash. Works with CMake on Linux. The key is read from the
    environment at configure time, so the Android job passes the same secret.
  - 0064 (x11 display lost) and every patch that edits `x11window.cpp` or `win32window.cpp` is irrelevant on Android.
  - Patches that change window or input code for desktop (keyboard hotkeys, mouse wheel, cursor) need a check for
    the Android window: the Android window has no hover and no wheel.
  - `chaos_hardening.cmake` is MSVC and GCC/MinGW only. Android needs its own flags (`-fstack-protector-strong`,
    `-D_FORTIFY_SOURCE`, relro, PIE). Note the base CMake adds `-no-pie`, which an Android shared library must not
    get. A shared library is built for Android, so the executable flags do not apply.
- **Shaders.** `client/tools/check_shaders.py` compiles every Chaos fragment and vertex stage twice: desktop GLSL
  1.10 and GLSL ES 1.00 with `precision highp float;` in front, as `framework/graphics/shader.cpp` does for GLES. The
  run today: 27 stages, 0 problems. So the shaders are Android-ready as far as a compiler can tell. Two open points
  for a real device: `highp` in fragment shaders is optional in ES 2 (nearly all arm64 phones have it), and the
  heavy effects (map bloom, light view, UI shaders of `game_shaderfx`, xBRZ upscaling) must be measured.
- **Mobile defaults.** The Android build should start with the heavy options off: xBRZ, bloom, weather, ground
  stains, aura strips. They are Options entries, so this is a first-start default, not new code.

### Risks (technical)

| Risk | Why | Mitigation |
|---|---|---|
| RAM for `chaos.pack` | The engine decrypts it into one buffer of the full ZIP size (more than 1 GiB). A phone kills the app. | Do not use the pack on Android. Section 3. |
| RAM for the update overlay | Patch 0103 mounts all downloaded update files as one in-memory ZIP (limit below 4 GiB). A first install through the updater is the whole game. | A file-backed mount on Android. |
| Cold start time | Hashing 1 GB of data on a phone is slow. | Hash cache exists. Hash in slices. Measure. |
| Fill rate | The map draws many layers of effects and a light pass. | Mobile defaults, a render scale option, a frame limit. |
| Thermal and battery | Long sessions. | 30 fps cap option, `FLAG_KEEP_SCREEN_ON` only in game. |
| Text input | Text fields open a Java dialog. Chat and search boxes are everywhere in Chaos. | Keep the dialog first. Later an inline field with the soft keyboard. |
| Lifecycle | Android pauses and kills apps. The server connection drops when the app goes to the background. | Reconnect flow on resume, and a save of the client state. Server keeps the character for a grace time. |
| LuaJIT on Android | JIT memory rules differ by vendor. | Test on 3 devices. Fallback is plain Lua. |

## 2. Touch and screen

### What the Chaos modules do today

`grep -ri mobile client/overlay/modules` finds five modules with any mobile handling:

| Module | What it does on mobile |
|---|---|
| `game_event` | Full `$mobile` styles (10 places). Fits 540 logical pixels, asks `client_mobile` to hide the walk pad while it is open. The only fully ported window. |
| `game_shop` | One `$mobile` rule in `shop.otui`. The look preview column is skipped (`shop.lua`, `tryon.lua`). |
| `game_chatpanel` | Does nothing on mobile (returns early). The base console keeps working. |
| `game_chaosuiscale` | Does nothing on mobile. The phone client sets its own zoom. |
| `game_shaderfx` | The health and mana orbs sit in the window corner when there is no chat panel. |

The base modules `client_mobile` (zoom, walk pad), `game_interface`, `game_console`, `game_battle`,
`game_healthinfo`, `client_entergame`, `client_textedit` have mobile code. Whether the Chaos modules that replace
the look of them (`client_chaos_login`, `client_chaos_topbar`, `client_chaos_charselect`, `game_chaoshud`) kept those
branches is not checked yet. Phase 2 starts with that check on a device.

### What needs work

Count from the `.otui` files: 115 windows in 83 modules. Of those, 78 windows in 69 modules are taller than 360
logical pixels, and 37 windows are 560 or more. The tallest: `game_dungeons` 1219 x 720, `game_event` 1010 x 705,
`game_pact` 670, `game_crafting` 664, `game_passivetree` 650, `game_achievements` 620. The count is a rough scan of
the first lines of each window, not a measured layout.

Work in four groups:

1. **Must work before any test:** login, character list and character creation (`client_chaos_login`,
   `client_chaos_charselect`), the map, health and mana (`game_chaoshud`), the walk pad, tap to attack and use,
   long press for the context menu, the top bar, the inventory, spell bar buttons. Tap targets of 48 dp.
2. **Play loop windows:** battle list, skills, spellbook (`game_spellbook`), helper (`game_helper`, hotkeys must become
   buttons), loot windows, NPC trade, chat, party frames, quest and hunt trackers, death recap, level-up.
3. **Big windows to re-layout** (one `$mobile` style set per window, like `game_event`): the 37 windows of 560 px and
   more first, then the rest. Many are tabbed lists, so a fold or a scroll area is the usual fix.
4. **Desktop-only ideas to replace:** hover tooltips (`game_itemtooltip`: long press instead), keyboard hotkeys
   (`game_helperhud`, `game_helperrotation`, loadouts: an on-screen action bar), mouse wheel zoom, drag between
   windows (item moves: drag works, but needs a bigger hold area), right-click menus (long press works).

Screen facts to design for: landscape only, 1280 x 720 at 5.0 inches and up. Safe areas for notches. Logical pixels:
`g_app.scale(...)` and `scaleUp` or `scaleDown` set the zoom. A 20:9 phone has little vertical room, so a window
must fit in about 360 to 540 logical pixels.

A tool to add: `client/tools/check_mobile_layout.py`, which reads every window size and fails when a window is
over the limit and has no `$mobile` rule. CI can then keep the list from growing.

## 3. Assets on a phone

### Sizes

| Item | Size |
|---|---|
| `Tibia.spr` of pair 37 | over 1 GiB, shipped as 46 or more shards of about 29 MB at most |
| `Tibia.dat` | about 5 MB |
| `chaos.pack` (everything, compressed and encrypted) | about 0.9 GB |
| Client tree without the pair after the slim step | 84.6 MB |
| Windows client download | about 1 GB (the pack is nearly all of it) |

Figures from `client/MANIFEST.md` ("Sharded sprites", "Slim client") and `launcher/README.md` ("Pack size"). The exact
size of the current pair should be read from the manifest when the work starts.

### Why the pack does not fit

`chaos.pack` is decrypted and inflated into one RAM buffer of the whole ZIP (`client/BASE.md` "Client packs": peak
memory is the ZIP size plus 4 MB). With the pair that is more than 1 GiB of RAM for data, on a phone with 4 to 8 GB
that Android also shares with other apps. It will be killed. So on Android:

- The APK does not hold the pair and does not use `chaos.pack`.
- Game data lives as files in the app's private folder (`getFilesDir`), the sprite shards among them. The engine
  already reads shards by PhysFS path and streams records, so shards on disk cost almost no RAM.
- Lua, UI and small art can stay in the APK as a ZIP in the assets (small, about 85 MB). The Android code path
  `PHYSFS_openRead("data.zip")` exists. It reads the whole `data.zip` into memory today. 85 MB is acceptable, but a
  PhysFS mount of the file is better (step 5).

### Options compared

| | A. Everything inside the APK | B. Small APK, data on first start (recommended) |
|---|---|---|
| APK size | 1.1 GB and more. Play Store base limit is 200 MB. A direct APK this size is slow to share and to update. | About 100 to 150 MB |
| First start | Instant after install | Download about 1.1 GB, shown with a progress bar |
| Data update | A new APK for every sprite change | Signed manifest, only changed shards (about 29 MB each) |
| Same trust as desktop | No, a separate path | Yes, the same Ed25519 manifest and key |
| Offline first start | Works | Needs a connection once |
| Disk during install | 2x the APK | About 1.1 GB plus staging for the largest files |

Recommendation: B. The APK carries the engine, the Lua and UI, and a minimal bootstrap. On first start it fetches
the signed manifest and downloads the game data (shards, dat, art) the way the desktop updater does.

### How, with the signed manifest

The desktop updater already does the hard parts: Ed25519 envelope, hashes per file, parallel ranged downloads, retry,
resume, staging, a journaled apply (`client/MANIFEST.md` "Signed updater"). Plan:

1. Reuse the in-game updater (Lua) for data. Its `files` section lists `data/`, `modules/`, `mods/`, `layouts/`
   files, which is exactly the content of the pair and the art. A first install is just an update from zero.
2. Add an Android profile to the manifest. The same blobs, plus a list for the phone: the shard set, but not the
   desktop-only art. A new key `android` next to `native` (old clients ignore unknown keys, as they ignore `native`).
   The phone only downloads files listed in its section. This is the idea of the O314 `native` section reused.
3. Make the overlay file-backed. Patch 0103 mounts the downloaded files as an in-memory ZIP. For Android a new patch
   (number 0163 or higher) mounts the folder `chaos_update/files` directly through PhysFS and decrypts per file when
   it is opened. On a phone the storage is app-private, so the encrypted blob step protects little. The simpler
   choice is to store the verified plain files in the app folder. Decision for the owner: keep AES blobs on the
   phone (more code) or not (less code, same level of protection as the Windows loose tree before build 13).
4. Show a first-start screen in the client: size, Wi-Fi advice, progress, pause. Check free space first: about 1.1 GB
   for the data and 0.5 GB for staging.
5. Shrink the pair for phones, later. Measure how many sprites the server content really uses (items, monsters,
   outfits, effects) against the library sprites the pair also holds. A "used set" shard list could cut the download.
   Not estimated here, because the share is not measured.

No sprite data goes into the repository. The pair md5s stay in `client/MANIFEST.md` as before.

## 4. Updates

Two things update: game data and the APK itself.

### Game data

The signed manifest, as on desktop. Lua and module-only changes are the cheap case: the in-game updater applies
them and restarts. On Android a restart is `exit()` today (patch 0101). The Java shell must start the activity
again. Small change in the shell: an `AlarmManager` or a `startActivity` before exit.

### The APK itself

The in-game updater never downloads native code, by design. A new `.so` needs a new APK. Loading downloaded
native code from app storage is blocked by current Android versions for apps that target them, and Google Play
forbids it. We do not want it either: the manifest key would then run native code on every phone. So the APK
changes only as an APK.

| | Direct download (sideload) | Google Play (or another store) |
|---|---|---|
| How it updates | The app checks the signed manifest for an `android_apk` entry (version code, URL, SHA-256, size). It downloads the APK, checks the SHA-256 and the Ed25519 signature, then hands it to Android's `PackageInstaller`. The player taps Install. | The store updates it. |
| Trust | Our Ed25519 key and Android's own APK signature (same keystore every time, as the admin app does). Two independent checks. | Google's. |
| Friction | The player must allow "install unknown apps" once for our app. Play Protect may warn. Updates need one tap. On Android 12 and newer a silent update is possible only when our app installed the previous version. | None. |
| Rules | Few. | Strict: recent target API, 64-bit, 16 KB pages, review, data safety form, and Play Billing for digital goods. |
| Fit to this game | Works now. | The Chaos shop sells coins for real money (`docs/PRICES.md`). Play requires its billing for in-app digital goods. Also the game uses art from many third-party packs and a Tibia-style protocol, which a store review may question. Owner decision needed. |

Recommendation: **direct download first**, with the app updating itself through `PackageInstaller`, and the update
check inside the same signed manifest. Plan for a store later, as a second channel with the same engine and a
different updater setting (updater off, store updates). Do not build the store path now.

Details of the direct path:

- The manifest payload gets a new key `android` with `{version_code, version_name, min_version_code, url, sha256,
  size, signer_sha256}`. It sits next to `native` and `files`. Old clients ignore it.
- The shell (Java) downloads to the app cache with resume, checks the size and SHA-256, and asks the engine's Ed25519
  code for the manifest check. Simplest: the engine verifies the manifest it already verifies, then passes the
  APK entry to the shell through a JNI call.
- Check `signer_sha256` against the signing certificate of the new APK before install (Android also refuses a
  different signer on update).
- Permissions: `REQUEST_INSTALL_PACKAGES`. `FOREGROUND_SERVICE` is not needed for a download in the foreground.
- The signing key: one keystore for every release, in a repository secret, like `ANDROID_KEYSTORE_B64` of the admin
  app (`.github/workflows/admin-app.yml`). A lost key means players must uninstall. Back it up offline.
- Version: `versionCode` = the client build number (`CHAOS_CLIENT_BUILD`), so the server's `clientGuardBuilds` and
  `min_package` keep one meaning.
- Server side: the website serves the APK and the manifest from the same place as the desktop packages
  (`publish_client_update.sh` gets an Android flag). The admin app should get a button for it, per the repository
  rule (tab, card, button) when the step exists.
- To verify with the owner before shipping: since September 2026 Google asks for developer verification for apps
  installed on certified Android devices, starting in Brazil, Indonesia, Singapore and Thailand. The owner and many
  players are in Brazil. This was announced in 2025. I could not read the current text from here. Read it before
  choosing the channel. If it applies, a direct APK needs a registered developer account too.

## Build plan

Each step lists the result and a rough size. One person, with a phone and a CI runner, no Windows needed.

1. **CMake target for Android.** Done in patch 0163, see Phase 2 status. Add an Android branch to the base `CMakeLists.txt` through a numbered base patch
   (0163 or the next free number): `SHARED` library, `-DANDROID`, `OPENGLES=2.0`, `androidwindow.cpp`,
   `androidplatform.cpp`, `src/android/dependencies.cpp` and the native app glue in, X11, `unixcrashhandler.cpp`,
   `-no-pie` and the `-Wl,-Map` flags out. Result: it configures with the NDK toolchain file. Size: 3 to 4 days.
2. **Dependencies.** Done: built in CI 2026-10-29. vcpkg `arm64-android` or scripts, static libraries, versions pinned, a cache in CI. Result:
   `libcinders.so` links. Size: 4 to 6 days. Then add each library to `docs/CREDITS.md` and run `gen_credits.py`.
3. **Compile fixes.** Done for the engine in 0163. The 147 older patches compiled without change; the compiler found only the four
   problems that 0163 fixes, all in base code. Left from the original list: run time problems that only a device shows.
4. **Gradle shell.** Done, in `client/android/`. A new Gradle project (not the old Ant one) in a new folder such as `client/android/`, package
   `com.cindersofchaos.client`, `minSdk 26`, current `targetSdk`, arm64-v8a only, the Java activity adapted (system
   bars, keyboard, text dialog, fatal dialog, restart), icons from `docs/brand`. The name `client/android/` is chosen
   so it never mixes with the admin app in `android/`. Size: 3 to 4 days.
5. **Data without the pack.** Android patch for a file-backed overlay and for mounting the APK's Lua ZIP without
   reading it into memory. First-start download screen. Size: 8 to 12 days. This is the biggest engine step.
6. **First boot on a device.** Login, map, walking, attack, chat. Mobile defaults for the heavy options. Size: 5 to
   8 days, mostly fixing what only a device shows.
7. **Touch layer.** Walk pad and action bar from `client_mobile`, long press, tooltip replacement, hotkey buttons for
   the spells and the helper, safe areas. Size: 8 to 12 days.
8. **APK updater.** The `android` manifest key, the Java installer step, publish script flag, tests in Python for
   the manifest side. Size: 4 to 6 days.
9. **CI workflow.** Written, see Phase 2 status. `.github/workflows/android-client.yml`, manual only (`workflow_dispatch`), `ubuntu-latest`:
   - check out this repository and the assets branch, as `windows-package.yml` does (base client archive in parts);
   - `assemble_client.sh` into a game folder, then a trimmed folder for the APK (no pair, no `chaos.pack`);
   - set up Java 17, the Android SDK (the runner has it) and a pinned NDK, accept licences;
   - build the dependencies from the cache, or restore them;
   - build `libcinders.so` with CMake and the NDK toolchain, with `CHAOS_CLIENT_KEY` from the secret as in the Windows
     job;
   - Gradle `assembleDebug` for arm64, then `assembleRelease` signed with the keystore secret on request;
   - upload the APK to a prerelease like the other packages. No pair, no private data in artifacts.
   The workflow can only be written and checked once step 1 to 4 exist. Size: 2 to 3 days.
10. **Mobile layout pass.** The windows of section 2, with the `check_mobile_layout.py` guard. Size: 6 to 10 weeks,
    in slices of 5 to 8 windows, ordered by how often players open them.
11. **Test and release.** Three or more devices (a low, a mid and a high one), a soak test, battery and heat notes,
    the website download page. Size: 1 to 2 weeks.

### Estimate

| Phase | Steps | Size |
|---|---|---|
| Engine on Android, a client that starts | 1 to 6 | about 4 to 6 weeks |
| Playable touch controls | 7 | about 2 weeks |
| Self-updating APK | 8 | about 1 week |
| CI | 9 | about 3 days |
| Chaos windows on a phone | 10 | 6 to 10 weeks |
| Test and release | 11 | 1 to 2 weeks |

The numbers assume one developer and no surprises from LuaJIT, OpenAL or the GPU. Steps 1 to 3 hold the most
unknowns, because nobody has built this engine tree for Android in CI. Re-estimate after step 3.

### Checks to add with the work

- `tools/ci/check_names.py`: no name of another client in the Android files. The Java file from the base has such a
  name in its package and class. Rename them while adapting.
- `tools/ci/check_credits.py`: every new library in `docs/CREDITS.md`.
- `check_modules.py`: nothing new until Android-only modules exist.
- A Gradle lint or build job for the shell, like the admin app's pull request check.
- `check_mobile_layout.py` (new), see section 2.

## Open questions for the owner

1. Direct download first, store later: agreed? And does the Brazil developer verification rule apply to us?
2. Phone data: AES blobs on the phone, or plain verified files in the app folder?
3. Minimum device: Android 8 (API 26) and 3 GB RAM, or higher? This sets how much we cut.
4. Accept a first-start download of about 1.1 GB on mobile data, or Wi-Fi only with a warning?
5. Play Billing: if a store comes, the coin shop must change on that channel. Same answer for Apple later.
6. Which keystore holds the release key, and where is the offline backup?
