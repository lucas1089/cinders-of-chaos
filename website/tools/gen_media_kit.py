#!/usr/bin/env python3
"""Media kit for streamers and press (page?plugin=chaos&p=creators; website/README.md "Creator program").

Packs the art that is already in the repository (website/art/*.png and the site logo, all original and procedural,
see gen_site_art.py), the streamer kit (gen_streamer_kit.py: the committed overlays, panels, banners and Discord icon under
website/overlay/plugins/chaos/assets/streamer/, the partner guide and chat commands built from text) and a fact sheet in
pt-BR and en into one zip. The zip itself is NOT committed: it is built at
install time (website/install_site.sh) into <site>/press/cinders-of-chaos-media-kit.zip. What is committed is the
manifest website/overlay/plugins/chaos/creators/media_kit_manifest.json (file names, sizes, sha256), which the page
reads, and --check fails when the art or the fact sheet changed and the manifest did not.

  python3 -I website/tools/gen_media_kit.py                      write the manifest
  python3 -I website/tools/gen_media_kit.py --check              exit 1 when the manifest is out of date (CI)
  python3 -I website/tools/gen_media_kit.py --zip OUT.zip        also build the zip (install_site.sh)

Deterministic: files sorted, stored without compression (the PNGs are compressed already), fixed timestamps, no clock.
There are no gameplay screenshots in the repository, so the kit has none; the fact sheet says so.
"""
import hashlib
import io
import json
import os
import sys
import zipfile

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import gen_streamer_kit  # noqa: E402  (text files need no Pillow; the committed PNGs are read from disk)
REPO = os.path.normpath(os.path.join(HERE, "..", ".."))
ART = os.path.join(REPO, "website", "art")
LOGO = os.path.join(REPO, "website", "overlay", "layouts", "chaos", "assets", "img", "logo.png")
CAL = os.path.join(REPO, "website", "overlay", "plugins", "chaos", "calendar", "calendar_data.json")
MANIFEST = os.path.join(REPO, "website", "overlay", "plugins", "chaos", "creators", "media_kit_manifest.json")
ZIP_NAME = "cinders-of-chaos-media-kit.zip"
ROOT = "cinders-of-chaos-media-kit"
STAMP = (2026, 10, 29, 0, 0, 0)

FACTS = {
    "pt-BR": """CINDERS OF CHAOS: FICHA TÉCNICA

O que é
Um RPG online de fantasia sombria, grátis para jogar, com cliente próprio.

Em números
- 7 classes e 14 ascensões.
- Árvore passiva com mais de 600 nós.
- Itens com raridades e crafting, rifts, chefes do mundo, arena e battleground.
- Temporadas opcionais: seu personagem é permanente e o legado é cosmético.

Datas (horário do servidor, UTC-3)
{dates}
Datas marcadas como proposta ainda não são finais. Veja a página Calendário do site.

Jogo limpo
A loja nunca vende equipamento, orbs de sorte, itens aleatórios, níveis, classes ou vantagem de combate. A lista completa está na página "O que a loja nunca vende".

Código de criador
Quem apoia seu código dá a você uma parte das moedas das doações dele, em jogo, sem custo para o apoiador. Os números atuais estão na página Programa de Criadores.

O que tem neste kit
- logo.png, o logotipo com o lema.
- Banners: social, Discord, listas de servidores.
- Uma imagem das classes e uma dos recursos do jogo.
- streamer/: kit para streamers, com molduras e telas para o OBS, painéis da Twitch, banner social, ícone do Discord, guia do parceiro e comandos de chat.
- Esta ficha em pt-BR e en.
Não há capturas de tela de jogo neste kit. Peça à equipe quando houver uma versão estável.

Uso da arte
A arte é original do projeto. Pode usar para divulgar o jogo em vídeos, lives e posts. Não venda, não altere o logotipo e não use para outro jogo.
""",
    "en": """CINDERS OF CHAOS: FACT SHEET

What it is
A dark fantasy online RPG, free to play, with its own client.

In numbers
- 7 classes and 14 ascensions.
- A passive tree of more than 600 nodes.
- Items with rarities and crafting, rifts, world bosses, arena and battleground.
- Optional seasons: your character is permanent and the legacy is cosmetic.

Dates (server time, UTC-3)
{dates}
Dates marked as a proposal are not final. See the Calendar page of the site.

Fair play
The store never sells gear, luck orbs, random items, levels, classes or any combat advantage. The full list is on the page "What the store never sells".

Creator code
Whoever supports your code gives you a share of the coins of their donations, in game, at no cost to the supporter. The current numbers are on the Creator Program page.

What is in this kit
- logo.png, the logo with the tagline.
- Banners: social, Discord, server lists.
- One image of the classes and one of the game features.
- streamer/: the streamer kit, with OBS frames and scenes, Twitch panels, a social banner, the Discord icon, the partner guide and chat commands.
- This sheet in pt-BR and en.
There are no gameplay screenshots in this kit. Ask the team when a stable version exists.

Use of the art
The art is original to the project. You may use it to promote the game in videos, streams and posts. Do not sell it, do not alter the logo and do not use it for another game.
""",
}


def sha(data):
    return hashlib.sha256(data).hexdigest()


def read_bytes(path):
    with open(path, "rb") as f:
        return f.read()


def dates_text(lang):
    cal = json.loads(read_bytes(CAL).decode("utf-8"))
    lines = []
    for e in cal["events"]:
        if e["kind"] == "wipe":
            continue
        day = e["start"][:10].split("-")
        when = "%s/%s/%s" % (day[2], day[1], day[0]) if lang == "pt-BR" else "%s-%s-%s" % tuple(day)
        if e.get("hasTime"):
            when += " " + e["start"][11:16]
        title = e["title"][lang]
        mark = " (%s)" % ("proposta" if lang == "pt-BR" else "proposal") if e["status"] == "proposal" else ""
        lines.append("- %s: %s%s" % (when, title, mark))
    return "\n".join(lines) + "\n"


def files():
    """[(path in the zip, bytes)] sorted by path."""
    out = [(ROOT + "/logo.png", read_bytes(LOGO))]
    for name in sorted(os.listdir(ART)):
        if name.endswith(".png"):
            out.append((ROOT + "/art/" + name, read_bytes(os.path.join(ART, name))))
    for name, data in sorted(gen_streamer_kit.text_files().items()):
        out.append((ROOT + "/streamer/" + name, data))
    for name, path in sorted(gen_streamer_kit.walk(gen_streamer_kit.OUT).items()):
        out.append((ROOT + "/streamer/" + name, read_bytes(path)))
    for lang, name in (("pt-BR", "ficha-tecnica.pt-BR.txt"), ("en", "fact-sheet.en.txt")):
        out.append((ROOT + "/" + name, FACTS[lang].format(dates=dates_text(lang)).encode("utf-8")))
    out.sort(key=lambda x: x[0])
    return out


def build_zip(items):
    buf = io.BytesIO()
    with zipfile.ZipFile(buf, "w", zipfile.ZIP_STORED) as z:
        for name, data in items:
            info = zipfile.ZipInfo(name, STAMP)
            info.compress_type = zipfile.ZIP_STORED
            info.external_attr = 0o644 << 16
            z.writestr(info, data)
    return buf.getvalue()


def manifest(items, blob):
    return json.dumps({
        "generatedBy": "website/tools/gen_media_kit.py (do not edit by hand)",
        "zip": {"name": ZIP_NAME, "path": "press/" + ZIP_NAME, "bytes": len(blob), "sha256": sha(blob)},
        "files": [{"name": n[len(ROOT) + 1:], "bytes": len(d), "sha256": sha(d)} for n, d in items],
        "screenshots": 0,
    }, indent=1) + "\n"


def main(argv):
    items = files()
    blob = build_zip(items)
    text = manifest(items, blob)
    if "--zip" in argv:
        out = argv[argv.index("--zip") + 1]
        os.makedirs(os.path.dirname(os.path.abspath(out)), exist_ok=True)
        with open(out, "wb") as f:
            f.write(blob)
        print("media kit: wrote %s (%d bytes)" % (out, len(blob)))
    if "--check" in argv:
        have = open(MANIFEST, encoding="utf-8").read() if os.path.isfile(MANIFEST) else ""
        if have != text:
            print("media kit: the manifest is out of date; run python3 -I website/tools/gen_media_kit.py", file=sys.stderr)
            return 1
        print("media kit: manifest up to date (%d files, zip %d bytes)" % (len(items), len(blob)))
        return 0
    if "--zip" not in argv or "--write" in argv:
        os.makedirs(os.path.dirname(MANIFEST), exist_ok=True)
        with open(MANIFEST, "w", encoding="utf-8", newline="\n") as f:
            f.write(text)
        print("media kit: wrote %s" % os.path.relpath(MANIFEST, REPO))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
