# AI tools shortlist

A curated pick from the public list `SubmitGame/awesome-ai-game-dev-tools`. Read on 2026-10-14.
Written for the owner. Beta is two weeks out, so the bar is "helps before or soon after the beta".

How to read this:

- Stars and last push come from the list's own table. The list refreshes them daily from the GitHub API.
- Licences come from each repo's README or sidebar, read on 2026-10-14. Model weights often have their own licence.
  Where a weights licence was not on the repo page, the entry says so. Check the model card before shipping output.
- Nothing was installed or run. The machine was busy with a server load test. Every "works on CPU" or VRAM figure is
  the project's own claim.
- Actions: **adopt now**, **spike** (try for a day, then decide), **watch**, **skip**.

## What the list does not cover

The list is mostly local, open models and engines. It has no section for:

- pixel-art VFX, tilesets for 32x32 tile maps, or UI icon packs;
- localization;
- Discord or community tooling;
- bots that play an MMO for QA.

For these we keep what we have: the `gen_*` generators, the AI pixel-art service through the proxy, the area planner,
`check_locales.py` with in-house pt-BR, the Discord webhooks in docs/LAUNCH.md, and our own test bots.

Most of the list is 3D, world models, engine bridges for other engines, and talking-head video. None of that fits a
2D tile game. It is skipped as a group.

## 1. Pixel art, sprites and animation

### Pixel Snapper (`Hugo-Dz/spritefusion-pixel-snapper`)

- What: snaps messy AI pixel art onto a clean pixel grid. Makes pixel size even. Quantizes to N colours or to a fixed
  hex palette with `--palette`. Keeps dithering.
- Runs as: a Rust CLI with folder batch mode, a WASM build, and a web page. No GPU mentioned.
- Fit: the cleanup step after the AI pixel-art service. Useful for the 8 new monsters, the 4 deep dungeon bosses, and
  monster looks that still borrow donor art. Our `item_post.py` does a similar job for items. This could replace or
  feed it.
- Licence: MIT. No output restrictions.
- Maturity: 3.3k stars, last push 2026-07-16.
- Action: ~~adopt now~~ **watch** (measured 2026-10-14, below).
- Measured 2026-10-14: v1.0.0 (commit ae20461), built with cargo outside the repo. Inputs: 8 PixelLab item picks
  (`sets_v2`, variant A, 32x32), 6 frames of the rift variant `abyss_brute_v1` (64x64), and 4 of the items blown up
  x3.7 with blur and noise to stand in for a general image model.
  - Grid: auto-detect fails on our native-res art. It read 5 to 10 px "pixels" and shrank 32x32 items to 5x5 to 10x10
    and 64x64 monsters to 13x14. With `--pixel-size 1` it still trims and drops rows (sword 31x31, shield 25x22).
  - Palette: with `--pixel-size 1` its colours match the raw art as well as ours. `--palette` works. It keeps alpha
    as is, so it adds no 0/255 cut, speck drop, dark rim, margin or centring. `item_post.py` does all of those.
  - Off-grid input (x3.7): auto read too coarse (22 to 28 px wide). With `--pixel-size 4`, then `item_post.py`, it is a
    little crisper than `item_post.py` alone, but jagged. Not a clear win.
  - Speed: under 1 ms per sprite. Ours: 3 to 15 ms. Both negligible.
  - Verdict: no pipeline step. PixelLab already returns clean 1 px grids. Revisit only if we switch to a general image
    model (Qwen-Image) whose output is off-grid. Then run it with a known `--pixel-size` before `item_post.py`.

### Aseprite (`aseprite/aseprite`)

- What: the standard pixel-art and animation editor. Timeline, onion skin, sprite sheet export, a CLI and Lua
  scripting.
- Fit: hand touch-ups of 4-direction outfit frames. The generators and the AI service give a base. A human still
  fixes a bad frame or a wrong facing. The CLI can export sheets in a fixed layout for `client/tools/sprites/`.
- Licence: its own EULA, not open source. Source builds also fall under the EULA. A paid licence is the normal route.
  The price was not on the page I read. Output you draw is yours.
- Maturity: 40.1k stars, last push 2026-10-13.
- Action: **adopt now** if the owner or an artist will hand-edit frames. Otherwise use Pixelorama.

### Pixelorama (`Orama-Interactive/Pixelorama`)

- What: a free pixel-art editor. Layers, frames, onion skin, tilemap layers, sprite sheet export, a CLI for bulk
  export. Windows, Linux, macOS and web.
- Fit: same job as Aseprite with no licence cost. The web build needs no install. Tilemap layers help to sketch
  ground transitions before they go into the theme generators.
- Licence: MIT.
- Maturity: 10.5k stars, last push 2026-10-13.
- Action: **adopt now** as the free option. Pick one of Aseprite or Pixelorama, not both.

### Qwen-Image-Edit 2511 (`QwenLM/Qwen-Image`)

- What: open image generation and editing. The 2511 edit model claims better character consistency and multi-image
  input.
- Fit: repaint one monster into its other three facings or into rank variants from a reference sheet. Output then
  goes through Pixel Snapper at 32x32 or 64x64.
- Licence: repo says Apache 2.0. A separate weights licence is not stated on the repo page. Check the model card.
- Needs: a GPU. A community tool claims 4 GB VRAM with offload. Not tested.
- Maturity: 8.4k stars, last push 2026-02-10. Qwen-Image 2.0 is announced as a hosted model only.
- Action: **spike** after the beta. Compare against the current AI pixel-art service on two monsters.

### ComfyUI (`Comfy-Org/ComfyUI`)

- What: the node GUI and backend most local image and video models run in.
- Fit: only as the host for Qwen-Image or Wan2.2 if we run models locally.
- Licence: GPL-3.0. That covers the tool, not the images it makes. Each model keeps its own licence.
- Maturity: 137.4k stars, last push 2026-10-14.
- Action: **watch**. Only needed if a local-model spike goes ahead.

### Sprite Fusion (web tilemap editor, spritefusion.com; checked 2026-10-14)
- A free web tilemap editor (no login) with auto-tile and smart fill, layers, and a paid desktop edition (USD 14.99
  one time). Exports engine packages, JSON, TMX and PNG; free exports capped at 4.5 MB. The same site hosts an AI pixel
  art generator and animator, and Pixel Snapper (tried above, not adopted). The home page says commercial use needs no
  permission; output ownership is not stated there (Terms not read).
- Fit for us: low. Our maps are OTBM edited with the map editor on windows-assets and generated by the area planner,
  both with our own item ids and sprites. Sprite Fusion has no OTBM export: a TMX import would need our sprites as a
  tileset and a tile id mapping. Its AI art overlaps the pixel art service we already use.
- Action: skip. Possible later use: a quick visual mock-up of a hunt layout before writing its area plan.

## 2. Upscaling and downscaling

### chaiNNer (`chaiNNer-org/chaiNNer`)

- What: a node GUI for image pipelines. Batch folders, upscaling models, many image ops. CPU fallback.
- Fit: marketing stills, website heroes, the wiki art from `gen_wiki_art.py`, and store banners at large sizes. Not
  for 32x32 sprites: AI upscalers blur pixel edges. Use nearest-neighbour scaling for sprites.
- Licence: GPL-3.0. Output is not affected.
- Maturity: 6.1k stars, last push 2026-10-11.
- Action: **watch**. Try it when beta marketing needs big images.

### Upscayl (`upscayl/upscayl`)

- What: a one-click desktop AI upscaler.
- Fit: same as chaiNNer, simpler, no pipelines.
- Licence: AGPL-3.0 per my knowledge of the project. Not re-checked today. Output is not affected.
- Maturity: 50.5k stars, last push 2026-10-05.
- Action: **skip** in favour of chaiNNer, unless the owner wants the simplest GUI.

### backgroundremover (`nadermx/backgroundremover`)

- What: cuts the subject out of an image or video. CLI, batch, CPU works.
- Fit: cut-outs of large key art for the website and the trailer. Not for sprites: our sprites already have alpha.
- Licence: code MIT, models Apache 2.0.
- Maturity: 8.1k stars, last push 2026-07-10.
- Action: **watch**.

## 3. Music and ambience

We ship no music today. The client has a sound framework from base patch 0032, used by the loot filter sounds.
Check whether it can loop a music track before any music work.

### ACE-Step 1.5 (`ace-step/ACE-Step`, v1.5 in `ace-step/ACE-Step-1.5`)

- What: open music generation. Instrumentals across genres. v1.5 claims under 4 GB VRAM. CPU is a listed backend.
- Fit: the login theme, town loops, dungeon and rift ambience, boss stingers. Dark ambient and orchestral loops are
  the realistic target.
- Licence: code Apache 2.0 for v1 and MIT for v1.5. The weights licence is not stated on either repo page. Check the
  model card first. The README asks users to check originality and disclose AI use. The training data is not
  documented, so there is some risk of output that sounds like existing music.
- Maturity: 4.9k stars for v1, last push 2026-02-15. v1.5 released 2026-01-28.
- Action: **spike**. This is the only music model in the list that looked commercially usable.

### YuE (`multimodal-art-projection/YuE`)

- What: full songs with vocals.
- Licence flag: weights are CC BY-NC 4.0 with an extra creator permission. Individual creators may monetize output.
  Companies must contact the authors for a commercial licence. Needs 24 GB VRAM.
- Maturity: 11.9k stars, last push 2026-10-06.
- Action: **skip**. Unclear for a game studio, and we need instrumentals.

### AudioCraft, MusicGen and AudioGen (`facebookresearch/audiocraft`)

- Licence flag: code MIT, weights **CC-BY-NC 4.0, non-commercial**. Not usable for game content.
- Action: **skip**.

## 4. Sound effects

The list has no sound-effects model we could verify as commercially clean.

- MMAudio (`hkchengrex/MMAudio`): text or video to audio, about 6 GB VRAM. Weights **CC-BY-NC 4.0**. **Skip.**
- ThinkSound (`QwenAudio/ThinkSound`): README says **commercial use is not permitted**. **Skip.**
- AudioX (`ZeyueT/AudioX`): **non-commercial only**, watermarked. **Skip.**
- FoleyCrafter (`open-mmlab/FoleyCrafter`): licence not checked. **Watch.**

Our path for sound effects stays the synthesiser in `client/tools/gen_lootfilter_sounds.py`. Extend it for hits,
spells and UI clicks. ACE-Step can cover ambience beds.

## 5. Voice and NPC dialogue

### Chatterbox (`resemble-ai/chatterbox`)

- What: open text to speech. The multilingual model covers 23+ languages. There is a dedicated Brazilian Portuguese
  finetune. A Nano model runs on CPU.
- Fit: trailer and promo narration in English and pt-BR. Optional short voiced lines for a few key NPCs or boss
  intros later.
- Licence: MIT. Every output carries Resemble's inaudible Perth watermark. That is fine for us and shows the audio
  is synthetic.
- Maturity: 26.9k stars, last push 2026-07-21.
- Action: **spike** for the trailer voice-over.

### Qwen3-TTS (`QwenLM/Qwen3-TTS`)

- What: text to speech in 10 languages, Portuguese included. VoiceDesign builds a voice from a text description.
- Fit: same jobs as Chatterbox. VoiceDesign gives an original narrator voice without cloning a real person.
- Licence: repo Apache 2.0. Weights licence not stated on the repo page. Check the model card.
- Maturity: 13.8k stars, last push 2026-03-17.
- Action: **spike** next to Chatterbox. Keep the better pt-BR result.

### Others

- KittenTTS: tiny CPU models with Portuguese. Models use the "Stellon Labs Community License". Commercial terms not
  stated. **Watch.**
- GPT-SoVITS, RVC, Applio: voice cloning tools. Cloning a real voice needs that person's written consent. **Skip.**
- LLM NPC frameworks like ai-town and the generative agents repos: not for a 10.98 server with keyword NPCs. **Skip.**

## 6. Marketing video and trailer

### Whisper (`openai/whisper`)

- What: speech recognition. MIT, 110.5k stars, last push 2026-08-31.
- Fit: captions for the promo video in English and pt-BR. The Remotion captions skill can use it through
  whisper.cpp.
- Action: **adopt now** for the promo video.

### Wan2.2 (`Wan-Video/Wan2.2`)

- What: open text and image to video. The TI2V-5B model does image to video at 720p and 24 fps.
- Fit: a few short cinematic shots from key art for the trailer intro. Real gameplay capture should carry the
  trailer. AI video will not keep pixel art crisp.
- Licence: code and weights Apache 2.0. The authors claim no rights over generated content.
- Needs: 24 GB VRAM for the 5B model, per the README.
- Maturity: 17.9k stars, last push 2026-09-21.
- Action: **spike**, only if a 24 GB GPU is at hand. Otherwise skip.

### Others

- LTX-Video: licence not checked. **Watch.**
- HunyuanVideo and the other Hunyuan models: the Tencent Hunyuan community licence has had territory limits in past
  releases. Not re-checked today. **Skip.**
- manimgx: animation engine for trailers. Remotion already covers this. **Skip.**

## 7. Testing and QA

### Playwright (`microsoft/playwright`)

- What: browser automation and testing. Apache 2.0, 97.7k stars, last push 2026-10-14.
- Fit: smoke tests for the website before beta: account creation, login, downloads page, wiki, store and donation
  pages. Our `website/tests/*_test.php` test PHP units, not a real browser.
- Action: **spike** this week, after the load test. Run it against a staging site, not production.

### Others

- Gymnasium, ML-Agents, Arcade Learning Environment, AgentBench: reinforcement learning environments. They do not
  speak our protocol. Our own bots stay the QA path. **Skip.**

## 8. Code assist

### Claude Code Game Studios (`Donchitos/Claude-Code-Game-Studios`)

- What: a Claude Code template with 49 agents and about 74 skills for a game team.
- Fit: we already work with Claude Code. Its engine parts target other engines and do not apply. Some skills are
  worth copying as ideas: `/release-checklist`, `/patch-notes`, `/changelog`, `/balance-check`, `/soak-test`,
  `/playtest-report`, `/bug-triage`, `/hotfix`.
- Licence: MIT.
- Maturity: 26.4k stars, last push 2026-10-08.
- Action: **spike**. Read the release and QA skills. Write our own versions for Lua, TFS and the beta. Do not
  install the whole template.

### Others

- Other coding agents and engine MCP bridges in the list: we have a working setup. **Skip.**
- The reverse-engineering tools in section 1 of the list: not needed, and risky to keep in our tooling. **Skip.**

## Top 5: do next

1. **Done 2026-10-14: no adoption** (see Pixel Snapper above). **Pixel Snapper on the monster art backlog.** After the load test, install the CLI. Run it on one folder of raw
   AI pixel-art output with `--palette` set to our palette. Compare with `item_post.py` output side by side. If it
   wins, add it as an optional step in the sprite import tools for the 8 new monsters and 4 dungeon bosses.
2. **ACE-Step 1.5 music spike.** First read the weights licence on its model card. Then make three loops: login
   theme, a town, a dungeon. Check whether base patch 0032 can loop a music track. Write down prompts and seeds so
   tracks can be remade.
3. **Trailer voice-over with Chatterbox or Qwen3-TTS.** Write a 30-second script in English and pt-BR. Make one take
   with each tool. Pick by pt-BR quality. Use an original or designed voice, never a clone. Add captions with Whisper
   in the Remotion project.
4. **One pixel editor for hand fixes.** Pixelorama if cost matters, Aseprite if an artist prefers it. Use it to fix
   bad frames and facings in 4-direction outfits before they enter the dat/spr pair.
5. **Done 2026-10-14.** **Playwright smoke test for the website.** Script five flows on staging: sign up, log in, create a character,
   open downloads, open the wiki. Run it before each beta deploy. Now `website/tests/e2e/run.sh` (website/README.md
   "Smoke test", docs/LAUNCH.md "Website").

## Not verified

- No tool was installed or run, except Pixel Snapper and Playwright on 2026-10-14. All other quality, VRAM and CPU
  claims are from the projects.
- Weights licences for ACE-Step 1.5, Qwen-Image and Qwen3-TTS were not on the repo pages. Model cards not read.
- Aseprite price and the exact EULA terms for source builds were not read.
- Upscayl's licence and the Hunyuan licence terms are from memory, not re-checked.
- FoleyCrafter and LTX-Video licences were not checked.
- The GitHub API was blocked in this session. Stars and dates come from the list's table only.
- Training data provenance is unknown for every music and voice model. Treat output as needing a human listen for
  likeness to existing works.
