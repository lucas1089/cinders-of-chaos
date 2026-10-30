# Android client (O313): study, plan and build

Status: phase 1 done, study and plan. Phase 2 done as far as this machine can check: the engine builds for android
arm64 with the NDK through CMake, and a Gradle project packs it into an APK. See "Phase 2 status" below. Phase 3 (written
2026-10-29, option B of section 3): the first-start download of the game data, the file-backed mount and the restart. See
"Phase 3 status". Step 8, the APK that updates itself (written 2026-10-30): see "Step 8 status". Nothing has run on a
device yet.
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
- Recommended, and built in phase 3 for the data: a small APK (engine, Lua, UI, no sprite pair) with the game data
  downloaded on first start through the signed manifest, and, still to build, the APK itself updated by a versioned download that is checked twice, then installed by
  Android's package installer (sideload). A store comes later and needs decisions from the owner.
- Honest estimate: 4 to 6 weeks of work for a client that starts, logs in and plays with a basic touch pad. Another
  6 to 10 weeks to make the Chaos windows usable on a phone. Details in "Estimate".

Phase 1 added no CI workflow, because the base had no Android build to run from Linux. Phase 2 adds the build and the
manual workflow `.github/workflows/android-client.yml`. See "Phase 2 status".

## Step 8 status: the APK updater

Date: 2026-10-30. Build plan step 8 is written and tested as far as this machine can: the publisher, the manifest key, the
screen logic, the Java download and the workflow. Nothing of it ran on a device, and the Java installer and the JNI call were
not built with the NDK and Gradle here.

### What was added

| Piece | Where | What it does |
|---|---|---|
| Manifest key `android_apk` | `client/tools/make_update_manifest.py`, `client/MANIFEST.md` "APK updater" | `{version_code, version_name, min_version_code, url, sha256, size, signer_sha256}` in the signed payload. `build --apk FILE --apk-info JSON` writes it and publishes the APK as a plain file `apk/<sha[:2]>/<sha>.apk` next to the manifest. A publish without `--apk` keeps the published entry while its file is intact, `--no-apk` drops it. A lower version code, or the same code with another file, is refused. `set-apk` changes only this entry of the published manifest and signs it again with the same version and files, so a new app needs no new Windows package. `verify` checks the file. Old clients ignore the key. |
| Publish script | `server/deploy/publish_client_update.sh`, `chaos-ctl.sh publish-apk` | `--apk android-31` downloads `CindersOfChaos-Android.apk` and `.json` from the release, alone it runs `set-apk`, with a client release it goes into that publish. `--apk-min-version-code N`, `--no-apk`. The web check asks the APK URL with a range request. |
| Admin app | `android/` Comandos > Site e update do client; `desktop/` same card | Field "Release do app Android", buttons "Publicar app Android" and "Tirar o app do update". |
| Screen logic | `client/overlay/modules/client_chaos_firststart/firststart_core.lua`, `firststart.lua` | `apkEntry` checks the entry like the publisher, `apkDecision` says none, offer or required. An offer shows "New app version" with Update app and Later. Required (running package below `min_version_code`, or below the server's `min_package` and the entry reaches it) has no Later and blocks play. The screen polls the shell. |
| Base patch `0169` | `client/base-patches/0169-android-apk-update.patch`, `client/BASE.md` | `g_resources.startApkUpdate(url, sha256, size, signerSha256)`, `apkUpdateStatus()`, `cancelApkUpdate()` over one JNI call to `ChaosActivity.apkUpdate`. |
| Java shell | `client/android/app/src/main/java/com/cindersofchaos/client/` `ApkFetcher`, `ApkUpdater`, `InstallResultReceiver` | `ApkFetcher`: download to the app cache with range resume, exact size and SHA-256. `ApkUpdater`: the "install unknown apps" permission prompt, then checks the file (same package name, higher version code, exactly one signing certificate whose SHA-256 is `signer_sha256`), then a `PackageInstaller` session. The receiver starts the system confirmation window and records the result. `REQUEST_INSTALL_PACKAGES` is in the manifest. |
| Workflow | `.github/workflows/android-client.yml` | Prints sha256 and the signer certificate sha256, writes `CindersOfChaos-Android.json`, and with `publish_release` on a release-signed build attaches APK, JSON and sha256 file to the prerelease `android-<client_build>` (never overwritten). |

### How it behaves

1. The first-start screen fetches the manifest as before. Before it compares the game data it asks `apkDecision` with the
   running package (`Services.update.package`, equal to the APK versionCode) and the entry.
2. Offer: the player may press Later and goes on to the game data check. Required: only Update app.
3. Update app: the shell asks Android for the "install unknown apps" permission when it is not granted and opens that
   setting. The player allows it and comes back and presses Update app again. The download resumes.
4. The shell checks size and SHA-256 while downloading, then package name, version code and the signer certificate of the
   file. Any mismatch deletes the file and shows a reason; nothing is installed.
5. The `PackageInstaller` session is committed. Android asks the player to confirm, except on Android 12 and newer when this
   app installed the running version. After the install Android ends the process. The player opens the app again.
6. A package equal to or above `version_code` sees nothing. A phone whose engine lacks patch `0169` does not offer the update.

### What was checked here

- `make_update_manifest_test.py` (entry, plain file, carry over, `set-apk`, refusals, signature, old clients' view) and
  `publish_client_update_test.py` (the real script: APK alone, from a release tag with a stub for curl, with game files,
  refusals, removal), `chaos_ctl_test.py` (`publish-apk`).
- `firststart_core_test.lua` (entry rules, decision table, url, status text, phases) under LuaJIT and Lua 5.3.
- `ApkFetcherTest` on a plain JVM against a local server: fresh, resume, no range support, dropped connection, wrong
  hash, too many bytes, wrong length, errors, cancel, no space.
- The Java classes compile against an Android 14 `android.jar` (only the generated `R` is missing).
- `0169` applies without fuzz on the lines patch `0168` leaves, and the JNI function passes a syntax check with the JDK
  `jni.h`.

### What is not checked

- Everything on a device: the permission settings page, `getPackageArchiveInfo` signing info on each Android version,
  the session commit, the confirmation window, the silent update path on Android 12 and newer, how the phone reacts to the
  process ending, Play Protect warnings.
- The NDK build of `0169` and the Gradle build of the new Java and manifest entries.
- The Lua screen itself (no harness for `firststart.lua`; the logic is in the core).
- A real release key: the secrets below do not exist yet.

### What the owner does

1. Create the release keystore once and keep an offline backup. A lost key means players must uninstall.
   `keytool -genkeypair -v -keystore chaos-client.jks -alias chaos -keyalg RSA -keysize 4096 -validity 10000`. In the
   repository settings add the secrets `ANDROID_CLIENT_KEYSTORE_B64` (`base64 -w0 chaos-client.jks`),
   `ANDROID_CLIENT_KEYSTORE_PASS` and `ANDROID_CLIENT_KEY_ALIAS`.
2. Actions > Android client, tick `publish_release`, set `client_build` above every APK given out so far. The summary shows the
   sha256 and the signer certificate sha256; the prerelease `android-<client_build>` holds the files.
3. On the VPS, once: admin app Painel > Atualizar servidor, so `/opt/chaos/repo` has the new script. Shell fallback:
   `sudo /opt/chaos/repo/server/deploy/chaos-ctl.sh update-apply`.
4. Admin app: Comandos > card "Site e update do client" > field "Release do app Android" (for example `android-31`) > button
   "Publicar app Android". Shell fallback: `sudo /opt/chaos/repo/server/deploy/chaos-ctl.sh publish-apk android-31`. Add
   `--min-version-code 31` to make the update mandatory. "Tirar o app do update" removes the entry.
5. Check: `make_update_manifest.py verify /var/www/chaos/updates/live --public KEY` prints "app update 1.31 (code 31)". The
   site must serve `apk/` with range requests; the publish web check warns when it does not.
6. Players on the direct APK allow "install unknown apps" for the game once.

## Phase 3 status

Date: 2026-10-29. Build plan step 5 (data without the pack) and the restart are written and unit tested. The APK
self-update (step 8), the release keystore and the touch layer are not.

### What was added

| Piece | Where | What it does |
|---|---|---|
| Manifest key `android` | `client/tools/make_update_manifest.py`, `client/MANIFEST.md` "Phone data" | The signed payload lists the files a phone needs: every path of the update except `layouts/mobile/` and the prefixes of `--android-exclude`. Written on every publish (`--no-android` leaves it out), checked by `verify`. Old clients and the launcher ignore it. |
| Base patch `0167` | `client/base-patches/0167-android-phone-data.patch`, `client/BASE.md` | `g_resources.unpackUpdateBlob` (verified blob to a plain file), `mountDataFolder` (PhysFS mount of the downloaded folder in front of `data.zip`, file-backed), `getFreeSpace`, the update key on Android, and the Android restart request. |
| Base patch `0168` | `client/base-patches/0168-android-loading-splash.patch`, `client/BASE.md`, `ChaosActivity.java` | Loading screen until the first frame: logo, "Loading...", a progress bar from the module load; the native splash calls of the Windows build as JNI calls of `ChaosActivity.splashProgress` and `splashHide`. |
| First-start screen | `client/overlay/modules/client_chaos_firststart/` | Fetches the signed manifest, compares, shows size, Wi-Fi advice and the free-space check (data plus 0.5 GB), downloads with pause, resume and retry, unpacks, restarts. Uses the desktop updater's code for the signature, paths and the download pool. |
| Restart | `ChaosActivity.restartApp`, `RestartActivity`, `AndroidManifest.xml` | After the engine has shut down, a helper activity in its own process ends the game process and starts the game again. |
| Workflow | `.github/workflows/android-client.yml` | New inputs `update_manifest` and `update_public_key` (same production defaults as `windows-package.yml`, written with `set_update_config.py`; optional `update_baseline`, the release number of the APK's own Lua, so an older live update only brings the game data), `client_build` default 30 (the live build, else the manifest's `min_package` turns the phone away), and the smoke test asserts the first-start screen in logcat. |

Decision taken (owner question 2, default to the simpler path): the verified files are **plain files in the app's private
folder**, no AES blobs on the phone. Same protection as the Windows loose tree before client build 13. The downloads are
the encrypted blobs of the site and are decrypted once, by the engine, when they are unpacked. To change it later, a
decrypting file layer would have to sit under PhysFS.

### How it behaves

1. The APK starts from `data.zip` (Lua, UI, art). `bootstrap.lua` mounts `chaos_update/android` when a finished download
   is there.
2. No `data/things/1098/Tibia.dat`: the screen blocks the login, fetches the manifest and compares the phone list with the
   phone. The Download button starts it. With an unreachable server the screen says so and keeps a Retry. With the game data
   in place a failure is silent (log only) and the player goes on.
3. The files land in `chaos_update/android/` one by one, each only after its hashes and GCM tag checked. A stop in the
   middle resumes from `chaos_update/android_index.txt` and the finished parts in `chaos_update/staging/`.
4. The client restarts and mounts the folder. A later start downloads only what changed (Lua, art, a sprite shard).
5. A new APK removes the old APK's Lua and art from the folder (they would hide the new `data.zip`) and keeps the game data.

### What was checked here

- `client/overlay/modules/client_chaos_firststart/firststart_core_test.lua` (219 checks) and `boot_test.lua` (42 checks) under
  LuaJIT and Lua 5.3; the older updater and clean start tests still pass with the Android cases added.
- The publisher: `make_update_manifest_test.py` (the `android` section, its checks, `--android-exclude`, `--no-android`,
  the old clients' view, the signature, the workflow inputs) and `publish_client_update_test.py` (the real script on a
  synthetic sharded package).
- Patch `0167` applies on a fresh base after `0001` to `0166`; `resourcemanager.cpp` and `application.cpp` pass a syntax check.

### What is not checked

- Everything on a device: the download over a mobile network, the PhysFS mount of the folder, the free-space call, how long
  the unpack of about 1 GB takes, the JNI restart and the helper activity (Android may refuse a background activity start on
  some versions; if so the player opens the app again, the data is in place), the Java code (no Android SDK here to compile it).
- The NDK build of patch `0167` (the Linux syntax check used host headers).
- The smoke test line on the emulator (written, not run).

### What the owner does on the VPS

The live manifest gets the `android` section with its next publish. It needs the new publisher on the VPS and a release
newer than the live update (a publish of the same version is refused).
1. Admin app: Painel > Atualizar servidor (runs `update-apply`), so `/opt/chaos/repo` has this change. Shell fallback:
   `sudo /opt/chaos/repo/server/deploy/chaos-ctl.sh update-apply`.
2. Build the next Windows package (Actions > Windows package), as for any client update.
3. Admin app: Comandos > card "Site e update do client" > field "Release do client" (for example `winpkg-N`) > button
   "Publicar update". Shell fallback: `sudo /opt/chaos/repo/server/deploy/chaos-ctl.sh publish-update winpkg-N`.
4. Check: `make_update_manifest.py verify /var/www/chaos/updates/live --public KEY` prints "N phone files" (the key is the
   public key of `Services.update.publicKey`). Then run Actions > Android client (the defaults point at the live manifest
   and key).

## Phase 2 status

Date: 2026-10-29. Build plan steps 1, 3 and 4 are done. Step 2 is written but not run here. Step 9 is written.

### What was added

| Piece | Where | What it does |
|---|---|---|
| CMake target | client base patch `0163`, `client/BASE.md` | The base CMake files get an Android branch. With the NDK toolchain they build the shared library `libcinders.so` with OpenGL ES 2, the EGL window, the touch code and the app glue. Three compile fixes and one link fix are in the same patch. |
| JNI name | client base patch `0164` | The C function for the text dialog callback gets the name of the new Java class. |
| PhysFS init | client base patch `0165` | `PHYSFS_init(NULL)` on Android. PhysFS reads its argument as a `PHYSFS_AndroidInit` pointer there, and the base's text crashed the app at start. |
| Mobile layout styles | client base patch `0166` | With the layout `mobile`, the base styles of `/data/styles` load first and the layout's five files on top. Before, only the five loaded and the start stopped. |
| No mobile layout | `client/android/tools/make_assets.sh` | `layouts/mobile` stays out of `data.zip`. Its console style has no `readOnly` widget, and `game_console` stopped the start on a Galaxy S23. Without the folder `init.lua` keeps the default layout. |
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

1. **File-backed data.** Done in phase 3 (patch `0167`) for the downloaded game data. `data.zip` in the assets is still
   read into one RAM buffer, about 71 MB here. Fine for the Lua and UI files; a PhysFS mount of the APK asset would be
   better and is not built.
2. **No game data in the APK.** Done in phase 3: the first-start screen downloads it. Not run on a device.
3. **Restart.** Done in phase 3 (Java `restartApp` and `RestartActivity`). Not run on a device.
4. **Touch layout.** The walk pad and the action bar of `client_mobile`, tap and long press, hotkey buttons, safe areas,
   the 69 windows over 360 logical pixels. Section 2 is unchanged.
5. **Window re-layout.** The engine resizes with the screen through `updateSize`. The Chaos windows have no mobile
   styles yet, except `game_event`. The guard `client/tools/check_mobile_layout.py` now keeps the list from growing: 39
   windows are over 960 x 540 logical pixels without a `$mobile` rule and sit in `client/tools/mobile_layout_baseline.txt`.
   Each fixed window removes its line. The re-layout itself needs a device. Phase 3.
6. **Mobile defaults.** Done, not run on a device. On the first start on Android `game_visualfx` switches off
   `spellLight`, `liquidShimmer`, `weather`, `ambientParticles`, `missileTrails`, `lightFlicker`, `deathFade` and
   `rarityOutlineMap` through the settings module, once (flag `chaosMobileDefaults`). `screenGrade`, `bloom` and
   `hoverOutline` are off everywhere already. Desktop defaults are unchanged. The player can turn any back on.
7. **APK self-update.** Done in step 8, see "Step 8 status": the `android_apk` entry, the publish script and admin app button,
   the Java download and `PackageInstaller` hand-over with the permission prompt, the screen, patch `0169`. Not run on a
   device. Still needed: the release keystore secrets.
8. **OpenAL Soft is LGPL.** It is linked statically into the engine library. Whoever has the APK cannot relink it. For
   a public release either link it dynamically, as a separate `.so` in the APK, or offer the object files. The owner
   should decide before any public download. The same question applies to the Windows package.
9. **Encrypted data on the phone.** Decided as the default in phase 3: plain files in the app folder, and `data.zip` can
   be unzipped from the APK by anyone. Same level as the Windows loose tree before client build 13. The owner can still
   ask for encrypted storage (question 2); it would be a decrypting file layer under PhysFS.
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
| `game_chaosuiscale` | Sets the phone zoom 1.5 s after start and on a size change: the highest whole step that leaves 960x540 interface pixels (1080 high: 2x). The base phone zoom of 3x left 780x360 and cut the login and the windows. The zoom buttons still change it. |
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

The tool exists: `client/tools/check_mobile_layout.py` (test `check_mobile_layout_test.py`, CI step next to the text fit
check). It reads the top-level windows of `client/overlay/modules/**/*.otui` and fails when a window with a fixed size is
taller than 540 or wider than 960 logical pixels and has no `$mobile` rule, except the windows in
`mobile_layout_baseline.txt`. Windows with `anchors.fill` or a size set only by an expression are skipped. A baseline
entry that now fits is reported as removable. It is a text scan, not a measured layout.

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
Built in phase 3 (see "Phase 3 status"); the points below say how.

### How, with the signed manifest

The desktop updater already does the hard parts: Ed25519 envelope, hashes per file, parallel ranged downloads, retry,
resume, staging, a journaled apply (`client/MANIFEST.md` "Signed updater"). Plan:

1. Reuse the in-game updater (Lua) for data. Its `files` section lists `data/`, `modules/`, `mods/`, `layouts/`
   files, which is exactly the content of the pair and the art. A first install is just an update from zero.
2. Add an Android profile to the manifest. The same blobs, plus a list for the phone: the shard set, but not the
   desktop-only art. A new key `android` next to `native` (old clients ignore unknown keys, as they ignore `native`).
   The phone only downloads files listed in its section. This is the idea of the O314 `native` section reused.
   Done: the list holds paths of `files` (not copies), minus `layouts/mobile/`; `--android-exclude` takes more prefixes.
3. Make the overlay file-backed. Patch 0103 mounts the downloaded files as an in-memory ZIP. For Android patch 0167
   mounts the plain folder `chaos_update/android` directly through PhysFS. On a phone the storage is app-private, so
   the encrypted blob step protects little: the verified files are stored plain in the app folder (default taken for
   owner question 2; same protection as the Windows loose tree before build 13).
4. Show a first-start screen in the client: size, Wi-Fi advice, progress, pause. Check free space first: about 1.1 GB
   for the data and 0.5 GB for staging. Done (`client_chaos_firststart`). The Wi-Fi advice is a text: the client does not
   ask Android whether the link is Wi-Fi.
5. Shrink the pair for phones, later. Measure how many sprites the server content really uses (items, monsters,
   outfits, effects) against the library sprites the pair also holds. A "used set" shard list could cut the download.
   Not estimated here, because the share is not measured.

No sprite data goes into the repository. The pair md5s stay in `client/MANIFEST.md` as before.

## 4. Updates

Two things update: game data and the APK itself.

### Game data

The signed manifest, as on desktop. Lua and module-only changes are the cheap case: the in-game updater applies
them and restarts. On Android a restart was `exit()` (patch 0101). Done in phase 3: patch 0167 asks the Java shell,
which starts a helper activity in its own process that ends the game process and starts the game again.

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

- The manifest payload gets a new key `android_apk` with `{version_code, version_name, min_version_code, url, sha256,
  size, signer_sha256}`. It sits next to `android`, `native` and `files`. Old clients ignore it. Built in step 8.
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
5. **Data without the pack.** Done for the downloaded data in phase 3 (patch 0167, `client_chaos_firststart`). Left:
   mounting the APK's Lua ZIP without reading it into memory. Size was 8 to 12 days. This is the biggest engine step.
6. **First boot on a device.** Login, map, walking, attack, chat. Mobile defaults for the heavy options. Size: 5 to
   8 days, mostly fixing what only a device shows.
7. **Touch layer.** Walk pad and action bar from `client_mobile`, long press, tooltip replacement, hotkey buttons for
   the spells and the helper, safe areas. Size: 8 to 12 days.
8. **APK updater.** Done 2026-10-30, see "Step 8 status": the `android_apk` manifest key, the Java download and installer
   step (patch `0169`), the publish script and admin app button, tests. Not run on a device. Size was 4 to 6 days.
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
2. Phone data: AES blobs on the phone, or plain verified files in the app folder? (Built as plain files, the simpler
   default; say if you want encryption.)
3. Minimum device: Android 8 (API 26) and 3 GB RAM, or higher? This sets how much we cut.
4. Accept a first-start download of about 1.1 GB on mobile data, or Wi-Fi only with a warning?
5. Play Billing: if a store comes, the coin shop must change on that channel. Same answer for Apple later.
6. Which keystore holds the release key, and where is the offline backup?
