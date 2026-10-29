#!/usr/bin/env python3
"""Streamer / partner kit: OBS overlays, Twitch panels, banners, Discord icon, partner guide, chat commands (page?plugin=chaos&p=creators;
website/README.md "Streamer kit").

Art is built from the repository's own art generator (gen_site_art.py: the client theme, the wordmark, the class badges, the same
fonts). Nothing here is third-party: no logo, name or picture from outside the repository. Needs Pillow and numpy (the pinned
versions of the other art checks). Deterministic: the same inputs and library versions give the same bytes.

COMMITTED, where the site serves it (website/overlay/plugins/chaos/assets/streamer/), checked by --check in CI:
  overlays/    webcam frame, bottom bar with a blank code slot (pt-BR, en), starting soon, be right back, ending (1920x1080, the
               frame and the bar are transparent)
  banners/     Twitch panels (320x100, 4 kinds, pt-BR, en), social banner (1500x500), offline screen (1920x1080), thumbnail template
  discord/     circle-safe server icon (512x512)
  slots.json   where the blank slots are, so a creator can put a text source there
  obs-overlay.html, obs-overlay.js   the optional OBS browser source page (hand written, static, no cookies, no requests)
BUILT at install, not committed (gen_media_kit.py puts them in the media kit zip): guide/ (the partner guide as markdown, from
creators/partner_guide.json and the numbers of server/data/scripts/chaos/creator_codes_config.lua) and chat/chat-commands.txt.
The creators page renders partner_guide.json itself. Text files need no Pillow (text_files()).

  python3 -I website/tools/gen_streamer_kit.py                  write the committed files
  python3 -I website/tools/gen_streamer_kit.py --check          exit 1 when a committed file is stale or missing (CI, fx venv)
  python3 -I website/tools/gen_streamer_kit.py --preview DIR    write every file, text ones too, to DIR (for looking at them)
"""
import datetime
import io
import json
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.normpath(os.path.join(HERE, "..", ".."))
CREATORS = os.path.join(REPO, "website", "overlay", "plugins", "chaos", "creators")
GUIDE = os.path.join(CREATORS, "partner_guide.json")
OUT = os.path.join(REPO, "website", "overlay", "plugins", "chaos", "assets", "streamer")
OBS_FILES = ("obs-overlay.html", "obs-overlay.js")
LOGO = os.path.join(REPO, "website", "overlay", "layouts", "chaos", "assets", "img", "logo.png")
CFG = os.path.join(REPO, "server", "data", "scripts", "chaos", "creator_codes_config.lua")
ROOT = "streamer"

SERVER = "Cinders of Chaos"
SLOT_TOKEN = "{CODE}"

TEXT = {
    "pt-BR": {
        "bar": "use o código", "starting": "Começando em breve", "brb": "Volto já", "ending": "Obrigado por assistir",
        "ending_sub": "Até a próxima live", "starting_sub": "A live começa em instantes", "brb_sub": "Pausa rápida, não saia daí",
        "slot": "Código de criador", "offline": "Estamos offline", "offline_sub": "Siga o canal para saber quando voltamos",
        "tag": "RPG online de fantasia sombria, grátis para jogar",
        "panels": [("about", "Sobre o jogo", "RPG de fantasia sombria"), ("code", "Código de criador", "Apoie o canal de graça"),
                   ("discord", "Discord", "Entre na comunidade"), ("rules", "Regras", "Leia antes de jogar")],
        "thumb": "Título aqui",
    },
    "en": {
        "bar": "use code", "starting": "Starting soon", "brb": "Be right back", "ending": "Thanks for watching",
        "ending_sub": "See you next stream", "starting_sub": "The stream begins in a moment", "brb_sub": "A short break, stay close",
        "slot": "Creator code", "offline": "We are offline", "offline_sub": "Follow the channel to know when we are back",
        "tag": "Dark fantasy online RPG, free to play",
        "panels": [("about", "About the game", "Dark fantasy RPG"), ("code", "Creator code", "Support the channel for free"),
                   ("discord", "Discord", "Join the community"), ("rules", "Rules", "Read before you play")],
        "thumb": "Title here",
    },
}
PANEL_NAMES = {"pt-BR": {"about": "sobre", "code": "codigo", "discord": "discord", "rules": "regras"},
               "en": {"about": "about", "code": "code", "discord": "discord", "rules": "rules"}}


# ---------------------------------------------------------------- numbers of the creator code
def lua_number(text, key):
    m = re.search(r"^\s*%s\s*=\s*([0-9.]+)" % re.escape(key), text, re.M)
    if not m:
        raise SystemExit("gen_streamer_kit: %s not found in creator_codes_config.lua" % key)
    return int(float(m.group(1)))


def code_numbers():
    """The creator code numbers the guide quotes, read from the server config (the single source)."""
    with open(CFG, encoding="utf-8") as f:
        lua = f.read()
    m = re.search(r'^\s*launchBonusStart\s*=\s*"(\d{4})-(\d{2})-(\d{2}) (\d{2}):(\d{2})"', lua, re.M)
    if not m:
        raise SystemExit("gen_streamer_kit: launchBonusStart not found in creator_codes_config.lua")
    start = datetime.datetime(*[int(v) for v in m.groups()])
    days = lua_number(lua, "launchBonusDays")
    end = start + datetime.timedelta(days=days)
    return {
        "share": lua_number(lua, "sharePct"), "bonus": lua_number(lua, "launchBonusPct"), "support": lua_number(lua, "supportDays"),
        "hold": lua_number(lua, "holdDays"), "orderCap": lua_number(lua, "orderCap"), "monthlyCap": lua_number(lua, "monthlyCap"),
        "bonusDays": days,
        "discord_pt-BR": "o link está na página Programa de Criadores do site", "discord_en": "the link is on the Creator Program page of the site",
        "launch_pt-BR": start.strftime("%d/%m/%Y %H:%M"), "launch_en": start.strftime("%d %b %Y, %H:%M"),
        "end_pt-BR": end.strftime("%d/%m/%Y %H:%M"), "end_en": end.strftime("%d %b %Y, %H:%M"),
    }


def fill(text, lang, nums):
    def sub(m):
        k = m.group(1)
        key = k + "_" + lang if (k + "_" + lang) in nums else k
        if key not in nums:
            raise SystemExit("gen_streamer_kit: unknown token {%s} in partner_guide.json" % k)
        return str(nums[key])
    return re.sub(r"\{([A-Za-z]+)\}", sub, text)


# ---------------------------------------------------------------- the guide (markdown)
def guide_markdown(lang):
    """The partner guide of partner_guide.json as markdown in one language."""
    with open(GUIDE, encoding="utf-8") as f:
        data = json.load(f)
    nums = code_numbers()
    out = ["# " + data["title"][lang], "", fill(data["intro"][lang], lang, nums), ""]
    for sec in data["sections"]:
        out += ["## " + sec["title"][lang], ""]
        for blk in sec["blocks"]:
            kind, val = next(iter(blk.items()))
            if kind == "p":
                out += [fill(val[lang], lang, nums), ""]
            elif kind == "ul":
                out += ["- " + fill(x[lang], lang, nums) for x in val] + [""]
            elif kind == "ol":
                out += ["%d. %s" % (i + 1, fill(x[lang], lang, nums)) for i, x in enumerate(val)] + [""]
            elif kind == "check":
                out += ["- [ ] " + fill(x[lang], lang, nums) for x in val] + [""]
    return "\n".join(out).rstrip() + "\n"


# ---------------------------------------------------------------- chat commands
def chat_commands():
    nums = code_numbers()
    return """CINDERS OF CHAOS: COMANDOS DE CHAT E TÍTULO / CHAT COMMANDS AND TITLE

Troque os campos entre chaves: {CODE} é o seu código de criador, {DISCORD} é o link do Discord do servidor, {SITE} é o endereço do site.
Replace the fields in braces: {CODE} is your creator code, {DISCORD} is the server Discord link, {SITE} is the site address.
Os comandos funcionam em qualquer bot de chat que aceite comandos de texto fixo.
They work in any chat bot that takes fixed text commands.

== PT-BR ==

Título da live (exemplos)
Cinders of Chaos | RPG de fantasia sombria grátis | use o código {CODE}
Cinders of Chaos | primeira vez no servidor | use o código {CODE}

!server
Cinders of Chaos é um RPG online de fantasia sombria, grátis para jogar, com cliente próprio. 7 classes, 14 ascensões e uma árvore passiva enorme. Baixe em {SITE}

!codigo
Quer apoiar o canal sem pagar nada a mais? Na hora de doar no site, use o código {CODE}. A doação é voluntária e o jogo é grátis.

!discord
Entre no Discord do servidor: {DISCORD}

!regras
As regras estão em {SITE}. Bugs não se mostram nem se usam: avise a equipe. Nada de venda de contas, itens ou moedas por dinheiro real.

== EN ==

Stream title (examples)
Cinders of Chaos | free dark fantasy RPG | use code {CODE}
Cinders of Chaos | first time on the server | use code {CODE}

!server
Cinders of Chaos is a dark fantasy online RPG, free to play, with its own client. 7 classes, 14 ascensions and a huge passive tree. Download it at {SITE}

!code
Want to support the channel at no extra cost? When you donate on the site, use the code {CODE}. Donating is voluntary and the game is free.

!discord
Join the server Discord: {DISCORD}

!rules
The rules are at {SITE}. Bugs are not shown or used: report them to the staff. No selling accounts, items or coins for real money.

== NÚMEROS / NUMBERS ==
Código de criador: %(share)d%% das moedas de cada doação por %(support)d dias, %(bonus)d%% nas doações dos primeiros %(bonusDays)d dias depois do lançamento (%(launch_pt-BR)s).
Creator code: %(share)d%% of the coins of each donation for %(support)d days, %(bonus)d%% for donations in the first %(bonusDays)d days after the launch (%(launch_en)s).
""" % nums


# ---------------------------------------------------------------- art
def load_art():
    try:
        import numpy  # noqa: F401
        from PIL import Image  # noqa: F401
    except ImportError:
        raise SystemExit("gen_streamer_kit: needs Pillow and numpy (pip install pillow==12.3.0 numpy==2.5.3)")
    sys.path.insert(0, HERE)
    import gen_site_art  # noqa: E402
    return gen_site_art


def png_bytes(img, colors=0):
    from PIL import Image
    if colors:
        if img.mode == "RGBA":
            img = img.quantize(colors, method=Image.Quantize.FASTOCTREE, dither=Image.Dither.FLOYDSTEINBERG)
        else:
            img = img.convert("RGB").quantize(colors, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.FLOYDSTEINBERG)
    buf = io.BytesIO()
    img.save(buf, "PNG", optimize=True)
    return buf.getvalue()


def slot_box(img, gsa, box, label=None, lang=None):
    """A blank slot: dark inset with a gold edge (a text source of the stream goes on top), optional small label above."""
    from PIL import ImageDraw
    x0, y0, x1, y1 = box
    d = ImageDraw.Draw(img)
    d.rectangle([x0, y0, x1, y1], fill=gsa.BLACK + (225,), outline=gsa.GOLD_1 + (255,), width=2)
    d.rectangle([x0 + 4, y0 + 4, x1 - 4, y1 - 4], outline=gsa.BLOOD_1 + (255,), width=1)
    if label:
        gsa.plain_text(img, ((x0 + x1) // 2, y0 - 22), label, gsa.font(24, "heading"), fill=gsa.GOLD_3, anchor="mm")


def emblem(gsa, size):
    """The C of the logo on its badge plate (as the square icon)."""
    from PIL import Image
    icon = gsa.gta.render_icon(gsa.glyph_letter_c, True).crop((10, 10, gsa.gta.N - 10, gsa.gta.N - 10))
    return icon.resize((size, size), Image.LANCZOS)


def glyph_only(gsa, size):
    """The C alone (glow, shadow and gold body), without the badge plate and without the plate's rounded clip on the glow,
    scaled so the C itself spans `size` pixels on its longer side. Returns (image, glyph box in image pixels)."""
    from PIL import Image
    gta = gsa.gta
    keep_plate, keep_mask = gta.badge_plate, gta.rr_mask
    gta.badge_plate = lambda hover: Image.new("RGBA", (gta.N, gta.N), (0, 0, 0, 0))
    gta.rr_mask = lambda ins, rad: Image.new("L", (gta.N, gta.N), 255)
    try:
        icon = gta.render_icon(gsa.glyph_letter_c, False)
        g = gta.Glyph()
        gsa.glyph_letter_c(g)
        box = g.im.point(lambda v: 255 if v > 40 else 0).getbbox()
    finally:
        gta.badge_plate, gta.rr_mask = keep_plate, keep_mask
    pad = 28
    crop = (max(0, box[0] - pad), max(0, box[1] - pad), min(gta.N, box[2] + pad), min(gta.N, box[3] + pad))
    s = size / max(box[2] - box[0], box[3] - box[1])
    icon = icon.crop(crop)
    icon = icon.resize((max(1, round(icon.width * s)), max(1, round(icon.height * s))), Image.LANCZOS)
    return icon, tuple(round((v - o) * s) for v, o in zip(box, (crop[0], crop[1], crop[0], crop[1])))


def wordmark(gsa, width, tagline=True):
    """The site logo (wordmark and tagline, committed, 640 px wide) scaled to a width. gen_site_art.make_wordmark needs scipy and the
    reference picture of the client art; the committed logo is that same wordmark, so the kit builds with Pillow and numpy only."""
    from PIL import Image
    lg = Image.open(LOGO).convert("RGBA")
    if not tagline:
        lg = lg.crop((0, 0, lg.width, 225))     # above the divider
    box = lg.getchannel("A").point(lambda v: 255 if v > 24 else 0).getbbox()
    lg = lg.crop(box)
    return lg.resize((width, max(1, round(lg.height * width / lg.width))), Image.LANCZOS)


def scene(gsa, W, H, focus, dark, seed):
    from PIL import ImageDraw  # noqa: F401
    img = gsa.backdrop(W, H, focus_y=focus, dark=dark, seed=seed)
    return img


def make_screen(gsa, lang, kind, seed):
    """starting soon / be right back / ending: a full 1920x1080 scene, the wordmark, the headline, a blank slot."""
    from PIL import ImageDraw  # noqa: F401
    t = TEXT[lang]
    W, H = 1920, 1080
    img = scene(gsa, W, H, 0.3, 0.5, seed)
    gsa.panel(img, (40, 40, W - 40, H - 40), corner=64, fill_alpha=0, gold=True)
    lg = wordmark(gsa, 800)
    img.alpha_composite(lg, ((W - lg.width) // 2, 90))
    head = t[kind]
    gsa.gold_text(img, (W // 2, 640), head.upper() if kind != "ending" else head.upper(), gsa.fit(96, "display", head.upper(), 1500),
                  anchor="mm", glow=0.6, spacing=4)
    gsa.divider(img, W // 2, 722, 380)
    gsa.plain_text(img, (W // 2, 770), t[kind + "_sub"], gsa.font(40, "italic"), fill=gsa.TEXT, anchor="mm")
    slot = (W // 2 - 360, 850, W // 2 + 360, 970)
    slot_box(img, gsa, slot, t["slot"] if kind != "brb" else None)
    if kind == "brb":
        slot = (W // 2 - 360, 850, W // 2 + 360, 970)
    return img, slot


def make_bar(gsa, lang):
    """The bottom bar (transparent PNG): emblem, "Cinders of Chaos · use o código", and the blank code slot."""
    from PIL import Image, ImageDraw
    t = TEXT[lang]
    W, H = 1920, 1080
    img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    y0, y1 = H - 104, H - 12
    gsa.panel(img, (12, y0, W - 12, y1), corner=0, fill_alpha=238, gold=True)
    em = emblem(gsa, 84)
    img.alpha_composite(em, (30, y0 + 4))
    f = gsa.font(44, "display")
    d = ImageDraw.Draw(img)
    left = SERVER + " · " + t["bar"]
    gsa.gold_text(img, (130, (y0 + y1) // 2), left, f, anchor="lm", glow=0.0)
    x = 130 + int(d.textlength(left, font=f)) + 36
    slot = (x, y0 + 18, x + 460, y1 - 18)
    slot_box(img, gsa, slot)
    return img, slot


def make_cam(gsa):
    """The webcam frame: a gold and iron border around a transparent window, a small plate under it."""
    from PIL import Image
    W, H = 1920, 1080
    img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    cam = (1380, 640, 1380 + 480, 640 + 270)       # 16:9 window, lower right
    gsa.panel(img, (cam[0] - 14, cam[1] - 14, cam[2] + 14, cam[3] + 14), corner=36, fill_alpha=0, gold=True)
    plate = (cam[0] - 14, cam[3] + 18, cam[2] + 14, cam[3] + 82)
    gsa.panel(img, plate, corner=0, fill_alpha=238, gold=True)
    em = emblem(gsa, 52)
    img.alpha_composite(em, (plate[0] + 10, plate[1] + 6))
    slot = (plate[0] + 76, plate[1] + 12, plate[2] - 14, plate[3] - 12)
    slot_box(img, gsa, slot)
    return img, cam, slot


def make_panel(gsa, lang, key, title, sub):
    """A Twitch panel, 320x100: iron plate, gold trim, a class badge on the left, a title and a line."""
    from PIL import Image
    W, H = 320, 100
    img = Image.new("RGBA", (W, H), (0, 0, 0, 255))
    gsa.panel(img, (0, 0, W, H), corner=0, fill_alpha=255, gold=True)
    glyph = {"about": "warrior", "code": "mystic", "discord": "ranger", "rules": "templar"}[key]
    img.alpha_composite(gsa.badge(glyph, 64), (16, 18))
    gsa.gold_text(img, (96, 38), title.upper(), gsa.fit(24, "display", title.upper(), 196), anchor="lm", glow=0.0, spacing=0)
    gsa.plain_text(img, (96, 66), sub, gsa.fit(16, "text", sub, 208), fill=gsa.TEXT, anchor="lm")
    return img.convert("RGB")


def make_social(gsa, lang):
    """Channel / social banner, 1500x500: wordmark, a line and the seven class badges in the left 700 px, the rest is the scene
    (platforms crop the sides differently, so nothing important is far out)."""
    t = TEXT[lang]
    W, H = 1500, 500
    cx = 400
    img = scene(gsa, W, H, 0.3, 0.5, 63)
    gsa.panel(img, (14, 14, W - 14, H - 14), corner=36, fill_alpha=0, gold=True)
    lg = wordmark(gsa, 440, tagline=False)
    img.alpha_composite(lg, (cx - lg.width // 2, 26))
    y = 26 + lg.height + 8
    gsa.divider(img, cx, y, 280)
    gsa.plain_text(img, (cx, y + 30), t["tag"], gsa.fit(28, "italic", t["tag"], 640), fill=gsa.TEXT, anchor="mm")
    size, gap = 54, 12
    n = len(gsa.CLASSES)
    x = cx - (n * size + (n - 1) * gap) // 2
    for name, _ in gsa.CLASSES:
        img.alpha_composite(gsa.badge(name, size), (x, y + 60))
        x += size + gap
    return img.convert("RGB")


def make_offline(gsa, lang):
    t = TEXT[lang]
    W, H = 1920, 1080
    img = scene(gsa, W, H, 0.35, 0.45, 41)
    gsa.panel(img, (40, 40, W - 40, H - 40), corner=64, fill_alpha=0, gold=True)
    lg = wordmark(gsa, 800)
    img.alpha_composite(lg, ((W - lg.width) // 2, 110))
    gsa.gold_text(img, (W // 2, 700), t["offline"].upper(), gsa.fit(88, "display", t["offline"].upper(), 1500), anchor="mm", glow=0.5, spacing=4)
    gsa.divider(img, W // 2, 776, 380)
    gsa.plain_text(img, (W // 2, 830), t["offline_sub"], gsa.font(40, "italic"), fill=gsa.TEXT, anchor="mm")
    gsa.plain_text(img, (W // 2, 960), t["tag"], gsa.font(30, "heading"), fill=gsa.GOLD_3, anchor="mm")
    return img


def make_thumb(gsa):
    """YouTube thumbnail template, 1280x720: the title area is blank (dark plate, gold edge) for the creator's text."""
    W, H = 1280, 720
    img = scene(gsa, W, H, 0.3, 0.4, 52)
    lg = wordmark(gsa, 480)
    img.alpha_composite(lg, (40, 30))
    title = (60, 330, W - 60, 640)
    gsa.panel(img, title, corner=44, fill_alpha=150, gold=True)
    size, gap = 54, 12
    x = W - 60 - (len(gsa.CLASSES) * size + (len(gsa.CLASSES) - 1) * gap)
    for name, _ in gsa.CLASSES:
        img.alpha_composite(gsa.badge(name, size), (x, 664))
        x += size + gap
    return img, title


def make_circle_icon(gsa):
    """512x512 for Discord, which crops server icons to a circle: a full-bleed ember disc (no transparent or framed
    corners), a thin ring and the C well inside the circle (the C spans 60% of the width)."""
    import numpy as np
    from PIL import Image, ImageDraw, ImageFilter
    S = 512
    yy, xx = np.mgrid[0:S, 0:S].astype(np.float32)
    r = np.sqrt((xx - S / 2) ** 2 + (yy - S / 2) ** 2) / (S / 2)
    base = np.zeros((S, S, 3), np.float32)
    inner, outer = np.array((78, 24, 14), np.float32), np.array((10, 5, 5), np.float32)
    t = np.clip(r, 0, 1.2)[..., None]
    base[:] = inner * (1 - t) + outer * t
    haze = gsa.gta.fbm(S, S, 60, 4, 7)
    base *= (0.85 + 0.3 * haze)[..., None]
    img = Image.fromarray(np.clip(base, 0, 255).astype(np.uint8), "RGB").convert("RGBA")
    d = ImageDraw.Draw(img)
    # rings at 94% of the radius: inside the circle crop, with a margin
    for rad, col, wd in ((0.94, gsa.BLACK, 6), (0.91, gsa.GOLD_2, 3), (0.875, gsa.BLOOD_1, 2)):
        R = rad * S / 2
        d.ellipse([S / 2 - R, S / 2 - R, S / 2 + R, S / 2 + R], outline=col + (255,), width=wd)
    g, gb = glyph_only(gsa, int(S * 0.56))
    # centre the C itself (not its glow) on the circle
    pos = (S // 2 - (gb[0] + gb[2]) // 2, S // 2 - (gb[1] + gb[3]) // 2)
    img.alpha_composite(g, pos)
    return img.convert("RGB")


# ---------------------------------------------------------------- the kit
def read_bytes(path):
    with open(path, "rb") as f:
        return f.read()


def text_files():
    """{path under streamer/: bytes} of the files built from text (no Pillow): the guide and the chat commands."""
    return {
        "guide/guia-do-parceiro.pt-BR.md": guide_markdown("pt-BR").encode("utf-8"),
        "guide/partner-guide.en.md": guide_markdown("en").encode("utf-8"),
        "chat/chat-commands.txt": chat_commands().encode("utf-8"),
    }


def committed_text_files():
    """The hand-written OBS page files, as committed."""
    return {n: read_bytes(os.path.join(OUT, n)) for n in OBS_FILES}


def image_files():
    """{path under streamer/: bytes} of every generated image and slots.json."""
    out = {}
    slots = {}
    gsa = load_art()
    cam_img, cam, cam_slot = make_cam(gsa)
    out["overlays/webcam-frame.png"] = png_bytes(cam_img, 256)
    slots["overlays/webcam-frame.png"] = {"camera": list(cam), "nameSlot": list(cam_slot)}
    for lang in ("pt-BR", "en"):
        bar, bslot = make_bar(gsa, lang)
        out["overlays/bottom-bar.%s.png" % lang] = png_bytes(bar, 256)
        slots["overlays/bottom-bar.%s.png" % lang] = {"codeSlot": list(bslot)}
        for i, (kind, name) in enumerate((("starting", "starting-soon"), ("brb", "be-right-back"), ("ending", "ending"))):
            scr, sslot = make_screen(gsa, lang, kind, 30 + i)
            fname = "overlays/%s.%s.png" % (name, lang)
            out[fname] = png_bytes(scr, 160)
            slots[fname] = {"textSlot": list(sslot)}
        out["banners/offline.%s.png" % lang] = png_bytes(make_offline(gsa, lang), 160)
        out["banners/social-1500x500.%s.png" % lang] = png_bytes(make_social(gsa, lang), 160)
        for key, title, sub in TEXT[lang]["panels"]:
            out["banners/twitch-panel-%s.%s.png" % (PANEL_NAMES[lang][key], lang)] = png_bytes(make_panel(gsa, lang, key, title, sub), 128)
    thumb, tbox = make_thumb(gsa)
    out["banners/youtube-thumbnail-template-1280x720.png"] = png_bytes(thumb, 160)
    slots["banners/youtube-thumbnail-template-1280x720.png"] = {"titleArea": list(tbox)}
    out["discord/icon-circle-512.png"] = png_bytes(make_circle_icon(gsa), 128)
    out["slots.json"] = (json.dumps({"note": "Boxes are [x0, y0, x1, y1] in pixels of the picture. Put a text source of your stream there.",
                                     "slots": slots}, indent=1, sort_keys=True) + "\n").encode("utf-8")
    return out


def walk(base):
    found = {}
    for dp, _, names in os.walk(base):
        for n in names:
            full = os.path.join(dp, n)
            found[os.path.relpath(full, base).replace(os.sep, "/")] = full
    return found


def main(argv):
    if "--preview" in argv:
        dest = argv[argv.index("--preview") + 1]
        allf = dict(image_files())
        allf.update(text_files())
        allf.update(committed_text_files())
        for name, data in sorted(allf.items()):
            path = os.path.join(dest, name)
            os.makedirs(os.path.dirname(path), exist_ok=True)
            with open(path, "wb") as f:
                f.write(data)
            print("wrote", path, len(data))
        return 0
    imgs = image_files()
    if "--check" in argv:
        have = walk(OUT)
        bad = [n for n, d in imgs.items() if n not in have or read_bytes(have[n]) != d]
        extra = [n for n in have if n not in imgs and n not in OBS_FILES]
        missing_obs = [n for n in OBS_FILES if n not in have]
        for n in bad + extra + missing_obs:
            print("streamer kit: stale, extra or missing: " + n, file=sys.stderr)
        if bad or extra or missing_obs:
            print("streamer kit: run python3 -I website/tools/gen_streamer_kit.py (the fx venv in CI)", file=sys.stderr)
            return 1
        print("streamer kit: %d files up to date" % len(imgs))
        return 0
    if "--help" in argv or "-h" in argv:
        print(__doc__)
        return 0
    have = walk(OUT) if os.path.isdir(OUT) else {}
    for n in have:
        if n not in imgs and n not in OBS_FILES:
            os.remove(have[n])
    for name, data in sorted(imgs.items()):
        path = os.path.join(OUT, name)
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "wb") as f:
            f.write(data)
    print("streamer kit: wrote %d files to %s" % (len(imgs), os.path.relpath(OUT, REPO)))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
