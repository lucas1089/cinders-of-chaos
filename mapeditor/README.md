# Our map editor (O382)

Our own build of the AGPL-3.0 map editor the owner chose in 2026-11, named **Cinders Map Editor** (O388).
Upstream repository, author and licence: `docs/CREDITS.md` (names stay there, `tools/ci/check_names.py`).
It is a Qt 6 / QML editor with its own QRhi renderer, built with CMake, vcpkg and Visual Studio 2022.

Set up like the client (`client/BASE.md`): the upstream tree is not committed.
This folder holds the pin, our patches and the tools.

| Path | What |
|---|---|
| `UPSTREAM` | The pinned upstream commit, one full sha. |
| `patches/NNNN-*.patch` | Our changes, applied in name order with `git apply` on the pinned commit. |
| `BASELINE_PATCHES` | Patches of the "before" build of the profile: the harness only. |
| `tools/check_patches.sh` | Checks every patch applies in order on a clean copy. |
| `tools/upstream.py` | Prints the upstream repository and the pin for the workflow. |
| `tools/run_profile.py` | Runs builds on a map and writes the timing table. |
| `.github/workflows/mapeditor-build.yml` | Build, tests, artifacts, release for the package, optional profile. |

Pin: `2b98cb3192a74e01bb6b88b05a8ba8185c9ebfa1` (upstream HEAD of 2026-10-28, cloned 2026-11-03).

## Build

In CI: Actions > "Map editor build" > Run workflow.
It also runs on a push to `main` that changes `mapeditor/**`. Never on pull requests.

The job, on `windows-2022`:

1. Checks out upstream at `UPSTREAM` and applies `patches/*.patch` in order.
2. Clones vcpkg at the upstream manifest's `builtin-baseline` (the tag of their `scripts/build-release.ps1`).
3. Restores the vcpkg binary cache (`actions/cache`).
   Key: `vcpkg.json` and `triplets/` of the pinned tree. The baseline is inside `vcpkg.json`.
4. `cmake --preset windows-vcpkg`, then builds `package_all` and the upstream CI test targets (Release).
5. Runs the upstream CI `ctest` subset.
6. Uploads two artifacts:
   - `mapeditor-windows-x64`: the release folder (editor exe, Qt runtime, `data/`, LICENSE, NOTICE, `BUILD_INFO.txt`).
   - `mapeditor-source`: the patched source zip plus `cinders-patches/` (this README, the pin, the patches, `APPLIED.txt`).

Time: the first run builds Qt with vcpkg, about 2 to 3 hours (job limit 6 hours).
The cache keeps Qt; later runs take about 20 to 30 minutes.
Seed the cache with one run without the profile first: both profile builds would otherwise build Qt in parallel.
The Qt binary cache is about 1 to 2 GB of the repository's 10 GB cache space.

Upstream repository for the checkout, in order: the input `upstream_repo`, the repository variable
`MAPEDITOR_UPSTREAM_REPO` (Settings > Secrets and variables > Actions > Variables), else the credits entry
of the map editor (AGPL licence, GitHub source).

Local build (Windows): check out upstream at the pin, `git apply` each patch in order, then run their
`build-release.bat`. Do not build Qt on the Linux dev box (disk).

Check the patches on Linux (no build):

```
bash mapeditor/tools/check_patches.sh PATH_TO_UPSTREAM_CLONE
```

## Add a patch

1. Clone upstream, check out the pin, apply the existing patches as commits (`git am mapeditor/patches/*.patch`).
2. Make one small change. Commit it with a header like the others: area, what, why, "result identical" or what changes.
3. `git format-patch -1 --zero-commit --no-signature` and save it as `patches/NNNN-short-name.patch` (next number).
4. Run `tools/check_patches.sh`. Add a row to the table below: expected gain, measured or not.
5. A harness-only patch (timing, no behaviour) also goes into `BASELINE_PATCHES`.

Keep upstream behaviour identical except speed. Behaviour changes need the owner's yes and their own row.
Owner yes so far: English texts, the name, the updater on our releases (O388, patches 0007-0009).

## Move the pin

1. Put the new upstream sha in `UPSTREAM`.
2. Run `tools/check_patches.sh` on a fresh clone. Rebase a patch that fails (`git am -3`, fix, `format-patch` again).
3. Drop patches upstream has taken. Check the test list of the build step against their release workflow.
4. Run the workflow with `profile: true` and compare.

## Profile

Actions > "Map editor build" > Run workflow with `profile: true`.
Inputs: `profile_runs` (3), `pan_seconds` (8), `profile_backend` (opengl-mesa or d3d11-warp), `assets_ref`.

What it does:

- Builds a second editor with only `BASELINE_PATCHES` (upstream plus the harness), the "before".
- Job `profile-data` (Linux): prepares the server folder like the Windows package
  (`tools/windows/prepare_server.sh`, the map master of `world/`), keeps `items.otb`, `items.xml` and the map.
- Job `profile` (Windows): joins `things/things-1098.tar.xz.part*` into `Tibia.dat` / `Tibia.spr`,
  writes `Tibia.otfi` (`tools/windows/editor_versions.py`), puts Mesa llvmpipe `opengl32.dll` next to both exes.
- `tools/run_profile.py` starts each build in turn, `profile_runs` times per scenario:
  `--load-profile --profile-map MAP --profile-client DIR --profile-version 1098 --profile-pan S --profile-exit`.
  Scenarios: `surface` (floor 7, light and animation on) and `zoomedout` (tile size 8, floor 5 with lower floors).
- The job summary gets the table: ready time (process start to the first complete frame), peak working set,
  frames and fps while panning, frame interval avg / p50 / p95 / p99 / worst, the load stages in ms
  (QML, OTBM, palette visibility, atlas, minimap and more), the map and atlas counts.
  Logs: artifact `mapeditor-profile-logs`.

The runner has no GPU: rendering is software. Compare the two builds of one run, not absolute FPS.

The pan mode is patch 0001. Run it by hand on a Windows PC with a GPU:

```
editor.exe --load-profile --profile-map C:\maps\world.otbm --profile-client C:\client --profile-version 1098 ^
  --profile-pan 8 --profile-tile-size 16 --profile-lighting 1 --profile-animations 1 --profile-exit 2> log.txt
python -I mapeditor\tools\run_profile.py --parse log.txt
```

Options of the pan mode: `--profile-pan SECONDS`, `--profile-pan-speed TILES_PER_S` (60), `--profile-tile-size N`,
`--profile-floor Z`, `--profile-lighting 0|1`, `--profile-animations 0|1`, `--profile-lower-floors 0|1`,
`--profile-timeout SECONDS` (60). The camera moves east, then south. Every presented frame is timed.
The FPS limit of the settings is lifted for the run; the workflow sets `QSG_NO_VSYNC=1`.

## Patches

Gains are judged from the code. "Not yet measured": the CI profile run will tell.

| Patch | What | Expected gain | Measured |
|---|---|---|---|
| 0001 profile-map-pan | Pan mode for timing runs (`--profile-pan` and view options), `--profile-timeout`. Harness only. | None (measuring) | n/a |
| 0002 light-grid-ignores-animation | The light grid cache key ignores data version bumps made only by item animation phases. Before, every water or torch phase change rebuilt the CPU light grid of all visible floors and uploaded the light texture. | Large with lighting preview on and animated items on screen: no light rebuild per phase | Not yet |
| 0003 overlays-ignore-animation | Grid, wall outline, pathing and floor change overlays keep their data across animation phases (same key as 0002). | Medium: one tile scan and upload less per phase change | Not yet |
| 0004 skip-idle-effect-buffer | No per-frame effect collection, allocation and dirty buffer while no placement effect runs. | Small, every frame | Not yet |
| 0005 skip-selection-lookups | Chunk instance collection skips three hash lookups per quad when nothing is selected. Chunks are collected again on every animation phase. | Medium with many animated chunks on screen | Not yet |
| 0006 palette-lazy-alias-lookup | Item search looks up brush aliases only for rows whose name and id miss. About 40k rows per keystroke. | Medium: faster search typing in the item palette | Not yet |
| 0007 english-ui | The Polish texts in English (O388, below). | None (texts) | n/a |
| 0008 cinders-map-editor-name | The name Cinders Map Editor, the exe names, our settings key, the AGPL notice in About (below). | None (name) | n/a |
| 0009 updater-our-releases | The self-updater reads our releases; the version counts up; `update-keep.txt` (below). | None (updates) | n/a |

All nine apply on the pin (`check_patches.sh`). None is compiled yet: the first CI run builds them.

## English and the name (O388)

Owner request 2026-11-03: "translate the whole map editor to English. Rename it to Cinders Map Editor."

Upstream is English except one area, which was Polish (not Portuguese). Found by a search of every string literal of
`editor/` and `libs/` (Polish letters, then every word missing from an English word list), patch 0007:

- the procedural brush bar (`ProceduralBrushBar.qml`): 31 texts, buttons, tooltips, the status line, the options;
- the procedural library dialog (`GenerationLibraryDialog.qml`): 35 texts, its status messages, the structure tab;
- the pattern errors of `proceduralgeneration.cpp` (7) and `mapview_generation.cpp` (3), the style suffix
  " · revised" of `generationlibrary.cpp`;
- the UI colorize presets (`uitheme.cpp`: Classic, Green, Red, Purple, Gold, Turquoise, Graphite);
- Tools > "Procedural brush…", the AI assistant example, the default custom generator profile name ("My cave");
- `docs/custom-map-generator.md`, shipped in the program folder's `docs/`, translated whole.

Everything else the user sees was English already: menus, dialogs, status bar, Lua script runner, weather preview,
path builder, palettes, tilesets and brush names (`data/`). Comments in Polish stay.

Patch 0008, the name:

| What | Before | Ours |
|---|---|---|
| Programs | upstream names | `CindersMapEditor.exe`, `CindersMapEditorUpdater.exe` (CMake `OUTPUT_NAME`; the release package script and its test follow) |
| Settings (QSettings) | the upstream organisation and application | `Cinders` / `CindersMapEditor`: `HKCU\Software\Cinders\CindersMapEditor`, its own app data folder |
| Titles | upstream name | "Cinders Map Editor": main window, start window, error dialog, in-game preview, updater |
| About | upstream name, link, sponsor | our name, version, the upstream link kept, "Based on ... by its authors, GNU AGPL-3.0", "Modified by Cinders of Chaos since 2026-11", where the source is |
| Windows version resource | icon only | product name, company, licence line, source line |
| Map stamp | "Saved with" + upstream name | "Saved with Cinders Map Editor" (the old stamp is replaced on save like the others) |

The release folder keeps LICENSE, NOTICE and the upstream README. The settings start empty once (new key); the
package presets them (`map-editor-settings.ps1`, key from `tools/windows/editor_release.py settings-key`: ours first,
then the upstream names).

## Self-updater (O388)

Owner 2026-11-03: keep the updater and its button, but update from our releases. Patch 0009:

- It reads `update-manifest.json` (upstream format: `schemaVersion` 1, `version`, `downloadUrl`, `sha256`, `size`,
  `releasePageUrl`, `notes`) of the release `mapeditor-latest` of `DME_RELEASE_REPOSITORY` (CMake, default
  `lucas1089/cinders-of-chaos`; the workflow passes `github.repository`). Unauthenticated GitHub API: the repository
  must stay public, 60 checks an hour per IP.
- The zip must be a `*-windows-x64.zip` under `github.com/<repo>/releases/download/`. Size and SHA-256 are checked
  before the install (as upstream), and again by the updater program.
- Version: upstream version + `DME_BUILD_NUMBER` (the run number): `1.1.43.57`. Newer run, newer version.
- The updater unpacks the zip and copies its files over the program folder; it removes nothing. Files listed in
  `update-keep.txt` of the program folder are never overwritten. The package lists `data/1098/creatures.xml` and
  `data/1098/items.xml` there (the game's lists). Folders the package adds (`client`, `cinders`, `inbox`, `source`)
  are not in the zip, so they stay.

The release job writes the manifest into each `mapeditor-<short>` release and copies it to the rolling release
`mapeditor-latest`, unless that names a newer version (a re-run of an old run). The pruning of old releases never
removes the one `mapeditor-latest` names.

## Findings without a patch yet

Read from the code at the pin. Each needs a profile number before a patch.

- **Atlas size limit.** The atlas is one texture, 128 sprites wide (4096 px).
  At the usual 16384 px limit that is 65,536 sprites (256 MiB).
  If our map uses more unique sprites, the atlas texture fails and the map draws nothing.
  The profile prints `map_sprite_counts unique_sprites`: check it first. Fix if needed: wider atlas or atlas pages.
- **Palette thumbnails in memory.** At client load every item thumbnail is composed and kept (no LRU).
  With about 40k item types that is 160 MiB or more. A lazy thumbnail cache would cut it, but changes upstream tests.
- **Palette visibility scan.** Every item is composed with QPainter at client load (upstream measured 1.7 s for 19k).
  For our 40k types expect 3 to 4 s. A direct pixel check is faster but may differ on semi-transparent pixels.
- **Animation invalidates whole chunks.** An animation phase change drops the cached quads of every chunk holding that
  item; the worker rebuilds them and the scene cache redraws. With animated water on most of the map this is the main
  cost while animations are on. A real fix keeps phases in the instance data (bigger change).
- **Lower floors are drawn fully.** Floors under solid ground are still drawn (fill cost on floors 0-6 and below
  ground). Occlusion by opaque ground needs per-chunk coverage data; not started.
- **Atlas growth.** Growth keeps 1024 free slots; each growth copies and uploads the whole atlas. Fine at load, small
  stalls when many new items are placed. Not changed: a larger headroom can pass the texture limit.
- **Already good upstream:** lighting work stops when the preview is off; atlas updates upload only new rows;
  the SPR is decoded lazily (memory mapped during bulk work); save writes through a 64 KiB buffer; the minimap
  is one 8-bit image per floor.

## Release (O387)

Job `release` of the same workflow, after a green build from `main` (push or dispatch; never pull requests).
It runs only when the patched build and its `ctest` step passed: the artifacts exist only then.
It publishes the GitHub release `mapeditor-<short sha>` of this repository (prerelease, never "latest").
Artifacts expire after 30 days; releases do not.

| Asset | What |
|---|---|
| `mapeditor-<short>-windows-x64.zip` | The release folder in one top folder of the same name. |
| `mapeditor-<short>-source.zip` | The patched source with `cinders-patches/` (AGPL). |
| `BUILD_INFO.txt` | Program version, upstream sha and repository, variant, our patches, our commit, the run. |
| `SHA256SUMS.txt` | The three files above. |
| `update-manifest.json` | The self-updater's manifest of this build (O388). |

Release `mapeditor-latest` (rolling, prerelease): only `update-manifest.json` of the newest build. Do not delete it.

One tag per commit. A new build never changes a release a package is downloading.
A rebuild of the same commit replaces its own release. The newest 5 are kept.
The job has `contents: write`; the rest of the workflow stays read only.

## Package

`windows-package.yml` input `map_editor`: `ours` (default) or `upstream`.

- `ours`: the newest `mapeditor-<hex>` release of this repository (`tools/windows/editor_release.py latest-tag`).
  `editor_release.py verify --ours` checks both zips and `BUILD_INFO.txt` against `SHA256SUMS.txt`.
  It also wants the patched variant, a full upstream sha and our patch list.
- No such release, or three bad downloads: a `::warning::` and the upstream release. Packaging never blocks.
- `upstream`: the upstream rolling release, as in O381.

Both go through the same later steps: `data\1098` creatures and items are the game's,
the settings key is read from the exe, the source zip goes to `mapeditor\source`.
Updater: kept for our build with `CindersMapEditorUpdater.exe` (O388), with `mapeditor\update-keep.txt`; removed for
upstream and for an older build of ours (it would install upstream).
Settings key: ours (`Software\Cinders\CindersMapEditor`) when the program holds it, else the upstream key named after
the upstream repository (`upstream_repo` of `BUILD_INFO.txt`, else the credits).
`mapeditor\CHANGES.txt` says "our build of ...: upstream commit <sha> + our patches 0001..0006" and our commit.
The release notes and the package `BUILD_INFO.txt` name the build that shipped.
A fallback to upstream says "the UPSTREAM release" in the release notes.

AGPL-3.0: whoever gets our build must be able to get its exact source.
So the package ships the patched source zip of the same release next to the editor, with LICENSE and NOTICE.
Never ship one without the other.

The updater installs our releases only (O388). After an update, `BUILD_INFO.txt` names the new build and its source is
the `-source.zip` of that release; `mapeditor\source` and `CHANGES.txt` still describe the packaged one.
