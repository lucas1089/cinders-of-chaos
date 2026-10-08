# client_chaos_theme

Dark-fantasy UI theme (blackened iron, dried blood red, ember gold) for the OTClient 10.98 setup.
Autoloads before the game modules (`autoload-priority: 500`) and imports `styles.otui` and `compat.otui`, so any other module can use the `Chaos*` styles.
It also adds two widget helpers some modules expect and this engine lacks: `UIWidget:parseColoredText` (`[color=#rrggbb]...[/color]` markup) and `UIWidget:setExtendedTooltip` (shown as a plain multi-line tooltip).

## Files

| Path (under `client/overlay/`) | What |
|---|---|
| `modules/client_chaos_theme/chaos_theme.otmod`, `chaos_theme.lua`, `styles.otui` | The theme module and all styles |
| `modules/client_chaos_topbar/` | Menu bar at the top of the game window with drop-downs by category (otmod, lua, otui) |
| `data/images/chaos/` | All generated art (PNG, 80 files) |
| `../tools/gen_theme_art.py` | Generator: `python3 -I client/tools/gen_theme_art.py [frames] [icons] [logo] [background]` (Pillow + numpy, deterministic, about 15 s) |

`client/tools/assemble_client.sh` copies the overlay into the client; the login background and logo are plain images (`data/images/title.png`, `data/images/ui/logo.png`) used by the stock `client_background`.

## Styles (styles.otui)

`ChaosWindow` (+ `ChaosMainWindow`, `ChaosStaticWindow`, `ChaosStaticMainWindow`), `ChaosPanel`, `ChaosPanelDark`, `ChaosPanelHighlight`,
`ChaosTitlePlate`, `ChaosLabel`, `ChaosLabelDim`, `ChaosTitle`, `ChaosBloodLabel`, `ChaosButton` (normal/hover/pressed/disabled),
`ChaosTextEdit` (+ Password / Multiline), `ChaosTabButton` (normal/hover/checked), `ChaosProgressBar` (blood red; `ChaosHealthBar`, `ChaosManaBar` dark blue),
`ChaosScrollBar` (+ `ChaosScrollBarSlider`, vertical only), `ChaosCheckBox`, `ChaosComboBox`, `ChaosSeparator`, `ChaosItemSlot`.

Palette: OTUI has no variables, so the hex values are listed once in the header comment of `styles.otui` and mirrored in
`ChaosTheme.palette` (Lua). Every style uses only those values.

Window 9-slice: `image-border: 18`, `image-border-top: 34` (title band is part of the top border; the title text is drawn at `text-offset: 0 9`).

## Art (data/images/chaos)

`window`, `button_{normal,hover,pressed,disabled}`, `panel`, `panel_dark`, `panel_highlight`, `title_plate`, `textedit(_focus)`, `tab_{normal,hover,active}`,
`progress_frame`, `itemslot`, `scroll_*`, `checkbox` (16x32 sheet), `combobox`, `separator`, `topbar_bg`,
`background` (1920x1080), `logo` (760x300), `logo_small` (380x150),
`topbutton_<name>[_hover]` (64x64) and `small/topbutton_<name>[_hover]` (32x32) for: inventory, skills, battlelist, vip, spells, quests, market, bank, stash,
autoloot, daily, battlepass, passivetree, dungeons, events, infinitytower, minimap, options, notifications, help, logout, admin, ranking.

## Stock interface reskin

The base client's own chrome (windows, mini windows, panels, buttons, scroll bars, tabs, console, action bar,
inventory, minimap frame, login window) is recoloured to the same palette: `client/tools/gen_ui_reskin.py
<base-client-dir>` maps every grey pixel of those textures by brightness onto blackened iron, dried blood, bronze and
parchment, keeps saturated pixels (icons, bars, flags) and keeps size, alpha and layout, so no .otui changes. It writes
`overlay/data/images/<same path>` and lists the files in `overlay/data/images/RESKIN_FILES.txt` (rerun it after
updating the base client; files not in that list are our own art and are never overwritten). Base patch
`0013-chaos-text-colors.patch` turns the stock text colours to parchment tones to match.

## Menu bar (client_chaos_topbar)

Category buttons at the top of the game window: Character, Hunt, Chaos, Economy, Social, System and Admin (admins only). Each opens a
drop-down with the windows of that group (skills, spell list, passive tree, battle list, analyser, prey, auto loot, Infinity Tower, dungeons,
daily reward, event calendar, store, battle pass, market, bank, stash, VIP, quest log, options, hotkeys, logout, ...). It replaces the icon grid of
the stock `game_sidebuttons` window, which is closed on login. An entry is listed only when its module is loaded and exposes a known call
(`toggle`, `Stash.Toggle`, ...); calls are `pcall`-guarded, so a missing module never breaks the menu.
The admin category shows when the local player has GM access or a script calls `modules.client_chaos_topbar.ChaosTopBar.setAdmin(true)`.
Other modules can add entries with `ChaosTopBar.addEntry('chaos', { text = ..., icon = ..., modules = {...}, fns = {...} })`;
`ChaosTopBar.available()` lists what the menu shows and `ChaosTopBar.run(text)` runs an entry (useful for checks).

## Notes

- Loaded and checked in the Linux build of the client (see `client/LINUX.md`).
- Whether the engine draws `ChaosProgressBar` fill under or over the frame image (the frame has a translucent track, so either order is usable but the fill may look slightly dimmed).
- Fonts: only `verdana-11px-antialised` and `verdana-11px-rounded` are used. `ChaosTitle` could use a bigger stock font if your client has one.
- `image-border-left/right` on `ChaosSeparator`/`ChaosComboBox` and `image-border-top` on windows are standard OTClient properties but unverified on your fork.
- `modules.<name>` function names (`toggle` etc.) come from reading the overlay sources; several of those modules (bank, battlepass, notifications, game_admin, game_guide, game_highscore) have no
  confirmed toggle, so their icon may stay hidden. `game_admin` does not exist in the overlay yet.
- The top bar overlays the top 44 px of the game map (it is a centred, auto-width strip, not a full-width bar) and does not shift the map panel.
- The stock combo popup menu, tooltips and message boxes are not restyled.
- Art is hand-tuned by eye from contact sheets only; the 32x32 icons were not checked at 1:1 in a client.
- Everything is original procedural art (no third-party assets), so there is no licence issue with the PNGs.
