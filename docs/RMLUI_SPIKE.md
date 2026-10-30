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
  full-screen document does not eat clicks meant for the game. A tap is turned into a left click by the engine; a finger drag
  and the hover after a tap are handled in phase 2 (below).
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
| Option OFF | built in phase 2, see "Option OFF" below. |

Not done: vcpkg install of the `rmlui` port (network not available for it here, so the port version at the manifest's
baseline `389e18e8...` is unchecked), Windows (MSVC), Android (NDK), any measurement of frame time or memory (software
GL says nothing about a GPU), the on-screen keyboard, touch, the `cp1252` conversion with real pt-BR text.

## Phase 2: production ready layer (2026-10-30, base patch 0173)

Still behind `CHAOS_RMLUI` (off by default). Same test window, same recommendation: this makes the layer fit for one module
that wants HTML, it does not start a port.

| Item | What it does now |
| --- | --- |
| UI cache | The engine builds the UI picture again only on input (except a mouse move) and at a 16 ms interval. RmlUi asks for a repaint (`g_app.repaint()`) on every Lua call that changes a document, on every consumed input event, when the hovered element changes, and in `render()` when the frame it just drew differs from the last one. "Differs" is a hash of every draw call (geometry serial, translation, texture, clip), `chaosrml::FrameSignature`. So hover colours, animations, text changes, scrolling and a fling all repaint, and a still window asks for nothing. |
| UI scale | The engine draws the whole interface into a picture of window size / N and stretches it N times (`g_app.scale`, patch 0129). One interface pixel is already N screen pixels, so the RmlUi context takes the root widget size (viewport / N) and the dp ratio stays 1 for every N. Setting the dp ratio to N as well would draw every document N times too big. `g_rml.setScale(f)` is an extra factor on top (a text size option). The manager reads N as viewport width / root width, so a scale change (resize, `g_app.scale`) updates the dimensions, lays the documents out again and repaints; it is logged as `[RmlUi] interface scale ...`. `g_rml.getEngineScale()` and `getDpRatio()` read both. Text is rasterised at interface size and then stretched, as the OTUI bitmap fonts are (a vector font looks soft at 2x; a sharper text path would need the UI picture at window size, not done). |
| Z order and routing | RmlUi documents draw above every OTUI widget (one layer; an OTUI dialog above an RmlUi window is not possible). The rule is `chaosrml::consumes` (unit tested): move and wheel go to RmlUi when the pointer is over a visible RmlUi element (`pointer-events: auto`), a press the same, a release and the moves of a drag that started inside stay with RmlUi, keys and text only while an RmlUi `input`, `textarea` or `select` has the focus. Everything else reaches OTUI. A press that RmlUi does not take, while one of its fields has the focus, blurs the field. `UIManager::setHoverBlocked` (patch 0173) stops OTUI from hovering widgets under an RmlUi window. |
| Touch | Android sends Move, Press(touch), Moves, after 8 px a Press(left) at the start point, then Release(touch) and Release(left) (a tap or long press: Press and Release of left or right after the touch release). `chaosrml::TouchScroll` (pure, unit tested) turns the drag into whole-pixel scroll deltas (content follows the finger, remainders carried), with a fling after a fast release (decay 0.3 s, stops under 20 px/s). The manager applies them to the nearest overflow `auto` or `scroll` ancestor of the element under the finger that can still move, and passes the rest up. `ProcessMouseLeave` runs at the first left or right release after the finger lifted, so no element stays hovered. The touch press itself is not forwarded as a left button down (the left press that follows is). |
| Hot reload | `g_rml.clearCaches()` drops the style sheet and template caches. The test module calls it in `terminate()` and opens its window again in `init()` when it was open, so the module reloader (terminate, init) picks up edited `.rml` and `.rcss`. Fonts and images stay cached. Per-file watching is not done. |
| CI | `.github/workflows/rmlui-client.yml`, manual only: assembles the client, builds RmlUi 6.0 from its release tag (apt has no RmlUi), builds the client with `CHAOS_RMLUI=ON` and `OFF` and checks that the OFF binary has no `Rml::` symbols. It cannot run on push because the base client sources are not in the repository (same reason as `windows-client.yml`); the repository variable `CHAOS_BASE_CLIENT_REPO` must be set. The workflow has not run on GitHub; its steps are the ones run by hand here (the Ubuntu `libphysfs.a` needs `ranlib`). The vcpkg feature `rmlui` is still not installed by any job (port version at the manifest baseline unchecked). `rmlinputlogic_test.cpp` runs in the normal `native` job of `ci.yml`. |

### Checked here (Linux, g++ 13, RmlUi 6.0 built from its tag, Mesa software GL, Xvfb)

- Engine with `CHAOS_RMLUI=ON`: compiles and links. With `OFF`: builds, see "Option OFF" below.
- `rmlinputlogic_test.cpp`: routing table, drag and sub-pixel carry, fling and its stop, leave after release, frame signature (`g++ -std=c++17 -Wall -Wextra -Werror`).
- Client run under Xvfb at 960x540: the window opens over the login screen; hover on a row and on a button; a click on Refresh reached Lua (count 0 to 1); six wheel clicks scrolled the list to row 25; the text field took `abc`; a click on an OTUI area blurred it (the following `zz` did not enter it); a key with no RmlUi field focused went to OTUI (space dismissed the start screen under the window).
- Touch: the Android event sequence fed through `g_rml.injectMouse` (Ctrl+Alt+F11 or `CHAOS_RMLTEST=touch`): `scrollTop 0 -> 95` for a 90 px drag (5 px of fling), `isPointerOver` false after the release, no row hovered in the screenshot.
- Scale: 1920x1080 at `g_app.scale(2)` (interface 960x540): the log shows `interface scale 2.0, dp ratio 1.0`, the window has the size it has at scale 1, times two on screen; hover, click and wheel work (pointer positions given in interface pixels, see the next point). At 960x540 the engine caps the scale at 1.5 and the layer followed it.
- X11 and the scale: `x11window.cpp` does not divide the pointer by the scale, so with xdotool the pointer must be given in interface pixels at scale 2. The same is true for OTUI; not changed here.
- The spike module never ran its `init`: its `.otmod` had no `@onLoad: init()`, so the hotkey was never bound (found now, fixed).

### Option OFF

Built with `-DCHAOS_RMLUI=OFF` after patch 0173 (162 ninja steps, `rmlmanager.cpp` is not one of them): it links, starts to the login screen under Xvfb, the log has no `RmlUi` or `RMLTEST` line and the test module does nothing. The binary has no `g_rml` string (the ON binary has two) and is 21.6 MB against 24.4 MB with the layer. The only code in the OFF tree that differs from the base are the `#ifdef CHAOS_RMLUI` blocks of patches 0172 and 0173.

### Not done

- Windows (MSVC) and Android (NDK) builds, a GPU, frame time and APK size, the soft keyboard and IME for `<input>`.
- Real touch on a phone: the touch logic is unit tested and driven with synthetic events, not with a finger.
- An OTUI dialog above an RmlUi window, per-file hot reload watching, the cp1252 conversion of typed text, batching of draw calls, the render interface features listed in Risks.
- The GitHub workflow run, the vcpkg `rmlui` feature.

## Phase 3: the Options window (2026-10-30, base patch 0175)

Owner 2026-10-30: "Faça pelo menos a janela de opções em rmlui". Module `client_chaos_rmloptions`, still behind
`CHAOS_RMLUI` (release builds keep it off).

- The classic window (`client_settings`) stays the source of truth. The RmlUi window reads the controls of its loaded
  pages (`loadedWindows`) and builds one RML page from them: check boxes, horizontal scroll bars (a range input),
  combo boxes (a select), buttons, labels, help icons (a "?" that opens the tooltip text under the panel). A FlatPanel
  is one panel; a label right before a slider or combo box shares its row.
- A change in RmlUi calls the classic widget's own click or setter (`onClick`, `setValue`, `setCurrentIndex`), so
  `setTempOption`, the auto apply, dependent controls and the saved settings run as before. After each change the window
  reads every control again (values, enabled state, labels such as "Ambient Light: 78 %").
- `openOptions` of `client_settings` is wrapped: the top menu button opens (or closes) the RmlUi window. The hotkey pages
  (General, Action Bar, Custom Hotkeys: key capture and lists) and the hotkey shortcuts open the classic window; the
  footer button "Classic window" opens it too. Closing calls the classic `closeOptions` (apply and save).
- Patch 0175 binds `g_rml.getValue`, `setValue`, `isChecked`, `setChecked`, `setDisabled` (form controls, in the overlay
  `rmlmanager.cpp`).
- Not mirrored: the HUD page's condition list (a `TextList`), tooltips on hover (RmlUi has none; the "?" opens the text).
- Test: `rmloptions_test.lua` (mock widgets, fake `g_rml` and `client_settings`: page build, sync, change, disabled,
  buttons, help, menu, the hook and its removal). Checked under Xvfb at 1280x720 and 960x540: Graphics, Effects and
  Interface pages drawn with the real values; a check box click, a help icon, a slider drag (the label followed to 78 %),
  the menu and Close worked.

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
