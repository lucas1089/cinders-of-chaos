# RmlUi spike

Question: what does it cost to move the client UI from OTUI to RmlUi (HTML and RCSS, MIT)? Spike of 2026-10-30.
One test window, no existing window converted. Plain facts first, estimates marked as estimates.

## What was built

| Part | Where |
| --- | --- |
| Engine glue | `client/overlay/src/framework/rml/rmlmanager.{h,cpp}` (copied over the base `src/` by `assemble_client.sh`) |
| Hooks in the base engine | `client/base-patches/0172-rmlui-spike.patch`, 5 files, 48 lines, all inside `#ifdef CHAOS_RMLUI` |
| Build | CMake option `CHAOS_RMLUI` (default OFF); vcpkg feature `rmlui` in the desktop manifest and in `client/android/vcpkg/vcpkg.json` (not installed unless asked for) |
| Lua | singleton `g_rml` |
| Test window | `client/overlay/modules/client_chaos_rmltest/` (`.rml`, `.rcss`, Lua, two TTF fonts, a Lua test) |

With the option OFF nothing of RmlUi is compiled, linked or installed. The Lua module then finds no `g_rml` and does nothing.

### Integration design

The engine runs two threads: the dispatcher thread (Lua, widgets, builds a `DrawQueue` per frame) and the render thread
(owns GL, draws the queue). RmlUi is single threaded and must sit on the dispatcher thread, next to Lua.

- **Render interface.** `CompileGeometry` copies the triangles into flat float arrays (no index buffer, GL ES 2 safe).
  `RenderGeometry` does not touch GL: it adds one `DrawQueueItemRml` to the frame's `g_drawQueue` (geometry by
  `shared_ptr`, translation, scissor rectangle, texture). On the render thread the item binds its own small shader
  (`a_Vertex`, `a_TexCoord`, `a_Color`; the fragment shader divides the alpha out of RmlUi's premultiplied colours so
  the painter's normal blend mode is untouched) and calls `glDrawArrays`. Scissor goes through `Painter::setClipRect`.
  Textures are engine `Texture` objects (GL upload happens lazily on the render thread, as for every engine texture).
  RmlUi's optional features (transforms, clip masks, layers, filters, shaders) are not implemented: no `transform`,
  no `box-shadow`, no `filter`, no `backdrop-filter`, no gradients (`decorator`) beyond what plain geometry gives.
- **System interface.** Time from `stdext::micros`, log lines to `g_logger` (`[RmlUi] ...`).
- **File interface.** Reads through `g_resources.readFileContents`, so documents, fonts and images come from PhysFS: the
  encrypted pack, the update folder and the Android `data.zip` work the same as for OTUI files.
- **Input.** `UIManager::inputEvent` first asks `g_rml.inputEvent`. A mouse press, release, wheel or move over a
  visible RmlUi element is consumed, anything else falls through to OTUI. Keys and text are consumed only while the
  focused RmlUi element is an `input`, `textarea` or `select`. A document body has `pointer-events: none`, so a
  full-screen document does not eat clicks meant for the game. Touch needs nothing extra: the engine already turns a
  tap into a left click (`MouseLeftButton`, `MouseTouch2/3`).
- **Z order.** RmlUi draws after the OTUI root of the foreground pane, so its documents are above every OTUI window.
  One layer only. Interleaving (an OTUI dialog above an RmlUi window) needs more work: either two Rml passes around the
  OTUI root or a rule that RmlUi documents are always on top.
- **Fonts.** RmlUi uses FreeType and TrueType. The client ships no TTF at run time: all its text is drawn with bitmap
  `.otfont` files made by `tools/make_ofl_fonts.sh` from five OFL families kept in `client/fonts-src/`. The test window
  ships two of them directly (Alegreya Sans Medium 265 KB, Alegreya SC Bold 379 KB, OFL texts beside them).
  Cinzel in `fonts-src` is a variable font; not tried.
- **Lua binding.** `g_rml.loadFont(path, fallback)`, `loadDocument(path)` returning an int id, `show`, `hide`, `close`,
  `isVisible`, `setText` (escapes), `setInnerRml`, `setClass`, `setProperty`, `setEventCallback(function(docId, elementId, eventType))`
  (click and change, id of the nearest element with an `id`), `setScale`, `escape`. Lua never holds an Rml pointer.

### Test window

`rmltest.rml` and `rmltest.rcss`: title bar, subtitle, a `flex: 1` list that scrolls (`overflow-y: auto`) with 30 rows
(zebra, hover colour), a footer with two buttons and a close button. Dark theme colours of `client_chaos_theme`.
Sizes: `width: 60%` with `min-width: 360dp` and `max-width: 640dp`, `height: 70%` with min and max. At 960x540 that is
576x378, at 1920x1080 640x756. All text comes from Lua through `tr()` (pt-BR entries added to `pt_br.lua`).
`ChaosRmlTest.open()` or Ctrl+Alt+F10 (only when `g_rml` exists).

## What compiled and what ran

Environment: Ubuntu 24.04 container, g++ 13.3, 4 cores, Mesa software GL (llvmpipe) under Xvfb, no GPU.

| Step | Result |
| --- | --- |
| RmlUi 6.0 core and FreeType font engine, Release, static | built in 30 s (196 ninja steps). `librmlui.a` 6.5 MB unstripped, 2.5 MB of code (`size`). The debugger library (0.46 MB) is not linked. |
| `base-patches/0172` on the assembled tree | applies after `0001` to `0167` (the tree of this worktree; `0168`-`0171` are not in it, the patch touches none of their files as far as known). |
| Whole client engine with `-DCHAOS_RMLUI=ON` | compiled (163 steps) and linked, 24.2 MB binary (stripped by the base's link flags). One workaround, see Risks "Linux link". |
| Client started under Xvfb, test window opened from Lua | works: log shows `[RmlUi] ready, version 6.0`, both fonts loaded from `/modules/...` through PhysFS, `RMLTEST open -> true`. |
| Drawing | window, border, background colours, rounded corners, TrueType text, 30 rows with zebra, scroll bar, buttons: drawn correctly over the login screen. Seen in screenshots at 960x540 and 1920x1080 (client window resized with `xdotool`). |
| Input | hover colour on a row and a button, click on Refresh reached Lua (`onEvent`, subtitle went from "refreshed 0 times" to "refreshed 1 times"), mouse wheel scrolled the list. Clicks outside the window reached the OTUI login screen (not exercised in detail). |
| Lua test `rmltest_test.lua` | passes under luajit and lua5.3 (fake `g_rml`, 13 checks). `check_names`, `check_credits`, `gen_credits --check`, `check_locales`, `check_modules` pass. |
| Option OFF | not built in this run. By construction nothing changes (every hook is inside `#ifdef CHAOS_RMLUI`, the CMake block is inside `if(CHAOS_RMLUI ...)`, the vcpkg entry is an optional feature). |

Not done: vcpkg install of the `rmlui` port (network not available for it here, so the port version at the manifest's
baseline `389e18e8...` is unchecked), Windows (MSVC), Android (NDK), any measurement of frame time or memory (software
GL says nothing about a GPU), the on-screen keyboard, touch, the `cp1252` conversion with real pt-BR text.

## Effort

All numbers below are estimates unless marked measured. The base for them (measured by counting files):
388 `.otui` files with 106 000 lines, 647 non-test Lua files with 338 000 lines, about 29 000 widget method calls in
Lua (`:setText(`, `:getChildById(` ...), 88 files that define a window, 106 overlay module folders and 63 base module
folders with UI. 138 of the `.otui` files and 147 000 Lua lines are ours (overlay); the rest are base modules.

**(a) Keep both systems.** Spike: done. To make it production quality: about 3 to 4 weeks for one developer.
- one z order that interleaves OTUI and RmlUi (a dialog above or below an RmlUi window), focus and key routing between
  the two, the UI cache (`m_cacheUI` repaints only on input: RmlUi animations and `:hover` need a repaint request),
  the UI zoom (`g_app` scale, the phone's 2x) mapped to `dp`, hot reload of `.rml`/`.rcss` for the module reloader,
  fonts shipped in the pack (and the 70 MB of base assets are not touched), cp1252 to UTF-8 (done in `g_rml.escape`,
  untested with real pt-BR text), tests;
- Android: soft keyboard and IME for `<input>`, touch scroll, tap-hover (see Risks), about 1 to 2 weeks of that.
- Running cost: two layout systems, two style systems (`client_chaos_theme` skins would need an RCSS twin), two sets of
  checks (`check_locales.py`, `check_text_fit.py`, `check_mobile_layout.py` read `.otui`, not `.rml`).

**(b) Port every window.** About 8 to 12 developer-months, with regressions. Reasoning: 88 window files and about 300
smaller templates (rows, slots, bars), at half a day to two days each including the Lua that drives them (the Lua is
rewritten from the widget API to the element API: `getChildById` to `GetElementById`, no `UIItem`, `UICreature`,
`UIMap`, `UIMinimap`, `UIProgressBar`, spell and item icons from sprite sheets). Those engine-drawn widgets have no
RmlUi equivalent and need custom elements that draw through the engine (one per widget type, 2 to 4 days each, the map
view is the hard one). Drag and drop of items between containers, slots and hotkeys is engine code today. The login
screen, the map overlay and the action bars are the most sensitive.

An alternative that costs nothing here: the base already has `UIFlexBox` (`src/framework/ui/uiflexbox.cpp`). Most of what
HTML flex gives for responsive layout exists in OTUI; `client_chaos_theme` and the `$mobile` rules already cover phone sizes.

## Risks

- **Android, GL ES.** The renderer uses only `glDrawArrays` with client arrays and the engine's own shader loader (which
  adds `precision`), so it should run on GL ES 2. Not compiled for the NDK, not run on a device.
- **Android, touch.** The engine turns a tap into a left click. RmlUi has no touch scrolling: a finger drag does not scroll
  an `overflow: auto` element (wheel and scroll bar only); kinetic scrolling would be our own code. After a tap the
  hovered element stays hovered unless we call `ProcessMouseLeave` on release.
- **Android, text input.** The engine sends text fields through a Java dialog (`uitextedit.cpp`, `ANDROID` branch).
  RmlUi's `<input>` needs `SystemInterface::ActivateKeyboard` wired to JNI and composed text fed to `ProcessTextInput`.
  Not started. Clipboard: also a stub on Android today.
- **Font rendering.** All current text is bitmap `.otfont` (crisp, pixel fonts, hinting off by design). RmlUi draws
  TrueType with FreeType into on-the-fly glyph atlases: anti-aliased, looks different, blurry under about 12 px, one atlas
  per size. The TTFs are not shipped today (only the OFL sources in `client/fonts-src/`), and a variable font such as
  Cinzel is not handled by the default font engine in a useful way. 640 KB for two fonts in the test window.
- **Encoding.** The engine's strings are cp1252, RmlUi wants UTF-8; `g_rml.escape` converts, and any new path that hands
  text to RmlUi must do the same. Key text from the engine (`keyText`) is passed through unconverted: accented letters
  typed into an `<input>` would be wrong. Not fixed.
- **Draw calls.** Each RmlUi geometry becomes one queue item and one draw call, with no batching (OTUI batches through
  `g_drawCache` and the atlas). The test window is a few dozen calls. A dense window (inventory grid, 500 rows) is not
  measured and probably needs batching in the render interface.
- **Not implemented in the render interface:** `transform`, clip masks, layers, filters, shaders, so no `box-shadow`,
  `filter`, `backdrop-filter`, `mask-image`, gradients beyond plain colour, and `overflow: hidden` with rounded corners
  clips to the rectangle only. Adding them is the larger half of RmlUi's render interface (about 1 to 2 weeks).
- **Linux link.** The engine sets `CMAKE_FIND_LIBRARY_SUFFIXES` to `.a` before `find_package`, so on Ubuntu RmlUi's
  FreeType lookup took `libfreetype.a`, which needs libpng, brotli and bzip2 that are not linked: undefined references.
  `-DFREETYPE_LIBRARY_RELEASE=/usr/lib/x86_64-linux-gnu/libfreetype.so` fixed it. With vcpkg's static FreeType the CMake
  config carries its dependencies, so it should not appear on Windows or Android; not tried.
- **vcpkg version.** The code is written against the RmlUi 6.0 render interface (`CompileGeometry`, `RenderGeometry`,
  `Span`). A vcpkg baseline older than that gives RmlUi 5.x and the file will not compile. Before the first CI run:
  check the port version at the baseline and add an `overrides` entry if needed.
- **Threads.** RmlUi runs on the dispatcher thread, as every Lua call does. The render thread only sees queue items. A
  call to `g_rml` from another thread is undefined. `g_rml.terminate()` runs in `Application::terminate`; document
  handles from Lua are ints, so a stale id returns false instead of crashing.
- **APK size (estimate).** RmlUi code about 2 MB stripped for arm64, FreeType about 0.5 MB, TTFs 0.3 MB per face (a
  five family set about 1.5 MB), so about 3 to 5 MB on a 71 MB `data.zip` (5 to 7 percent). Not measured.

## Licence notes

- RmlUi: MIT. FreeType (RmlUi's font engine): FreeType Licence (BSD style) or GPL-2. The two Alegreya fonts: SIL OFL 1.1.
  All three are in `docs/CREDITS.md`; the OFL texts ship with the module's fonts.
- RmlUi pulls no GPL code. Its bundled sample fonts (Lato, Noto Emoji) are not used and not shipped.

## Recommendation

**Do not port the UI to RmlUi.** Keep OTUI as the UI of the game.

Why: the spike proves that RmlUi can live in this engine (about 600 lines of glue, 48 lines of engine patch, off by
default, working on the desktop with the right look). It does not remove the cost that matters: the game's windows are
engine widgets (map, items, creatures, minimap, bars) plus 338 000 lines of Lua written against the widget API, and a
port is 8 to 12 developer-months for a visual gain, while Android still needs touch scrolling, IME and a font decision
that nobody has tested. OTUI already has flex layout and the phone rules.

If a reason appears (for example a designer who wants HTML and CSS for text-heavy pages such as patch notes, the wiki
cards or the credits), the cheap path is (a) for new screens only: keep `CHAOS_RMLUI` off in releases, finish the three
Android items first (touch scroll, soft keyboard, a GPU frame-time and APK-size measurement on a real phone), then enable
it for one module and look at the numbers. Until then the patch costs nothing: it can stay in `base-patches/` or be
dropped; no other file depends on it.
