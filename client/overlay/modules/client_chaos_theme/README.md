# client_chaos_theme

Dark-fantasy UI theme (blackened iron, dried blood red, ember gold) for the OTClient 10.98 setup.
Autoloads early (`autoload-priority: 10`) and imports `styles.otui`, so any other module can use the `Chaos*` styles.

## Files

| Path (under `client/overlay/`) | What |
|---|---|
| `modules/client_chaos_theme/chaos_theme.otmod`, `chaos_theme.lua`, `styles.otui` | The theme module and all styles |
| `modules/client_chaos_topbar/` | Icon bar at the top of the game window (otmod, lua, otui) |
| `modules/client_background/` | Drop-in replacement of stock `client_background` (same API) showing `/images/chaos/background` + logo |
| `data/images/chaos/` | All generated art (PNG, 80 files) |
| `../tools/gen_theme_art.py` | Generator: `python3 -I client/tools/gen_theme_art.py [frames] [icons] [logo] [background]` (Pillow + numpy, deterministic, about 15 s) |

Copy `modules/*` into the client's `modules/` and `data/images/chaos` into its `data/images/chaos`.
`client_background` replaces the stock module of the same name, so remove or overwrite the stock folder.

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

## Top bar behaviour

Each icon is shown only if its module exists in `modules.*` and exposes a known function (`toggle`, `Stash.Toggle`, `Event.Toggle`,
`m_BattlepassFunctions.open`, ...) or a known window variable; calls are `pcall`-guarded. Logout always shows. The admin icon is hidden by default and shown only if
the local player exposes an admin accessor (`isAdmin`, `isGamemaster`, `getGroup`/`getGroupId`/`getAccess` >= 4) or a script calls `modules.client_chaos_topbar.ChaosTopBar.setAdmin(true)`.
Other modules can add icons with `ChaosTopBar.addEntry{ id=..., tip=..., modules={...}, fns={...} }` (the icon PNGs must exist).

## NOT tested (no OTClient runtime was available)

- None of the .otui/.lua was loaded in a real client. Lua parses with `luac -p`; OTUI was written from stock-client style files, not validated.
- Whether the engine draws `ChaosProgressBar` fill under or over the frame image (the frame has a translucent track, so either order is usable but the fill may look slightly dimmed).
- Fonts: only `verdana-11px-antialised` and `verdana-11px-rounded` are used. `ChaosTitle` could use a bigger stock font if your client has one.
- `image-border-left/right` on `ChaosSeparator`/`ChaosComboBox` and `image-border-top` on windows are standard OTClient properties but unverified on your fork.
- `modules.<name>` function names (`toggle` etc.) come from reading the overlay sources; several of those modules (bank, battlepass, notifications, game_admin, game_guide, game_highscore) have no
  confirmed toggle, so their icon may stay hidden. `game_admin` does not exist in the overlay yet.
- The top bar overlays the top 44 px of the game map (it is a centred, auto-width strip, not a full-width bar) and does not shift the map panel.
- The stock combo popup menu, tooltips and message boxes are not restyled.
- Art is hand-tuned by eye from contact sheets only; the 32x32 icons were not checked at 1:1 in a client.
- Everything is original procedural art (no third-party assets), so there is no licence issue with the PNGs.
