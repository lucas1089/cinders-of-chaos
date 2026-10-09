#!/usr/bin/env python3
"""Re-colour the purple ZnoteX layout ("Void") into the Cinders of Chaos client palette.

The Void layout is downloaded by website/install_site.sh at a pinned version; it is never committed here. This tool
reads its three theme stylesheets and writes re-coloured copies into our child layout (layouts/chaos, whose
theme.json names "void" as its parent), so ZnoteX's theme lookup (child -> parent) serves ours instead:

  * every violet / magenta colour literal (#hex, rgb(), rgba()) is mapped by hue, saturation and brightness:
      near-black violet backgrounds -> the client's iron blacks (#050405 .. #241f27)
      pale lavender text            -> the client's parchment text (#d6c9ae family)
      saturated violet accents      -> the client's crimson (#8a1010 .. #e03a1e)
    with a few exact replacements for the theme's named variables (gold #f6cf72 headings, crimson accents);
  * the brand webfonts of the original layout are dropped (not ours to ship) and replaced by serif stacks;
  * relative url(...) references that our layout does not ship point back to the parent layout;
  * our own stylesheet (layouts/chaos/assets/css/chaos.css) is appended to the last file, contract.css, so the
    parent's page shell picks it up without being copied or edited.

Colours: client/tools/gen_theme_art.py (IRON_*, BLOOD_*, GOLD_*) and the client's .otui text colours.
Usage: python3 -I website/tools/recolor_layout.py <layouts/void> <layouts/chaos>
Idempotent: always rebuilds the output from the parent's files.
"""
import colorsys
import os
import re
import sys

FILES = ("shadow-theme.css", "shadow-ui.css", "contract.css")

# client palette (client/tools/gen_theme_art.py)
IRON = ["#050405", "#0d0b0e", "#17141a", "#241f27", "#3a3339", "#574d52", "#7d7176"]
BLOOD = ["#2a0505", "#5a0a0a", "#8a1010", "#b8160f", "#e03a1e"]
GOLD = ["#6b4a14", "#a87420", "#d9a53a", "#f6cf72", "#fff0b8"]
TEXT = "#d6c9ae"     # client body text (.otui)
MUTED = "#8c8070"    # client muted text (.otui)
LINK = "#e8b84a"     # client highlighted text (.otui)

# exact replacements first (the layout's :root variables and its most visible literals)
EXACT = {
    "#07040f": IRON[0], "#0e0820": IRON[1], "#11072a": IRON[1], "#1a0a2e": IRON[2], "#2a1652": IRON[3],
    "#8b3fe0": BLOOD[3], "#b066ff": BLOOD[4], "#c44fff": GOLD[2], "#a855f7": BLOOD[4], "#6b2fc0": BLOOD[2],
    "#5a2da0": BLOOD[1], "#e8a030": GOLD[2], "#f5c050": GOLD[3], "#a8731c": GOLD[1],
    "#c9b3e6": TEXT, "#6d5a8c": MUTED, "#b794f4": LINK, "#ede0ff": "#f3ead6", "#e6d3ff": "#efe4cc",
    "#d9c5f5": "#e2d6bd",
}

FONT_STACK_DISPLAY = "'Cinzel','Trajan Pro','Palatino Linotype','Book Antiqua',Palatino,Georgia,serif"
FONT_STACK_TEXT = "'Palatino Linotype','Book Antiqua',Palatino,Georgia,serif"


def hexc(s):
    s = s.lstrip("#")
    if len(s) == 3:
        s = "".join(c * 2 for c in s)
    return tuple(int(s[i:i + 2], 16) for i in (0, 2, 4))


def tohex(rgb):
    return "#%02x%02x%02x" % tuple(max(0, min(255, int(round(c)))) for c in rgb)


def remap(rgb):
    """Map one colour; returns the same tuple when it is not violet."""
    key = tohex(rgb)
    if key in EXACT:
        return hexc(EXACT[key])
    r, g, b = (c / 255.0 for c in rgb)
    h, s, v = colorsys.rgb_to_hsv(r, g, b)
    deg = h * 360
    if not (235 <= deg <= 340) or s < 0.12:
        return rgb
    if v < 0.24:
        # dark violet background -> warm iron black, same brightness
        nh, ns, nv = 330 / 360.0, min(s, 0.6) * 0.3, v * 0.95
    elif s < 0.5 and v > 0.55:
        # lavender text -> parchment
        nh, ns, nv = 40 / 360.0, s * 0.6, v * 0.97
    else:
        # violet accent -> crimson
        nh, ns, nv = 4 / 360.0, max(s, 0.78), min(1.0, v * 0.86)
    return tuple(c * 255 for c in colorsys.hsv_to_rgb(nh, ns, nv))


RE_HEX = re.compile(r"#([0-9a-fA-F]{6}|[0-9a-fA-F]{3})\b")
RE_RGB = re.compile(r"rgba?\(\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)\s*(,\s*[0-9.]+\s*)?\)")


def recolor(css):
    def hex_sub(m):
        return tohex(remap(hexc(m.group(0))))

    def rgb_sub(m):
        rgb = remap((int(m.group(1)), int(m.group(2)), int(m.group(3))))
        r, g, b = (max(0, min(255, int(round(c)))) for c in rgb)
        if m.group(4):
            return "rgba(%d,%d,%d%s)" % (r, g, b, m.group(4).replace(" ", ""))
        return "rgb(%d,%d,%d)" % (r, g, b)

    # do not touch colours inside url(...) (data URIs, file names)
    parts = re.split(r"(url\([^)]*\))", css)
    for i in range(0, len(parts), 2):
        parts[i] = RE_RGB.sub(rgb_sub, RE_HEX.sub(hex_sub, parts[i]))
    return "".join(parts)


def fonts(css):
    css = re.sub(r"@font-face\s*\{[^}]*\}\s*", "", css)
    css = re.sub(r"'EasonProCaps'|\"EasonProCaps\"|'EasonPro'|\"EasonPro\"", FONT_STACK_DISPLAY, css)
    css = re.sub(r"'CronosPro'|\"CronosPro\"", FONT_STACK_TEXT, css)
    css = css.replace("hue-rotate(18deg)", "hue-rotate(0deg)")
    return css


def urls(css, child_css_dir, parent_name):
    def sub(m):
        raw = m.group(1).strip().strip("'\"")
        if raw.startswith(("data:", "http:", "https:", "/", "#")):
            return m.group(0)
        if os.path.exists(os.path.normpath(os.path.join(child_css_dir, raw))):
            return m.group(0)
        if raw.startswith("../"):
            return "url('../../../%s/assets/%s')" % (parent_name, raw[3:])
        return "url('../../../%s/assets/css/%s')" % (parent_name, raw)
    return re.sub(r"url\(([^)]*)\)", sub, css)


def main(argv):
    if len(argv) != 3:
        print(__doc__)
        return 2
    parent, child = argv[1].rstrip("/"), argv[2].rstrip("/")
    parent_name = os.path.basename(parent)
    src_dir = os.path.join(parent, "assets", "css")
    out_dir = os.path.join(child, "assets", "css")
    ours = os.path.join(out_dir, "chaos.css")
    if not os.path.isdir(src_dir):
        print("no stylesheets in %s" % src_dir, file=sys.stderr)
        return 1
    os.makedirs(out_dir, exist_ok=True)
    for name in FILES:
        src = os.path.join(src_dir, name)
        if not os.path.isfile(src):
            print("skip %s (not in the parent layout)" % name)
            continue
        with open(src, encoding="utf-8") as f:
            css = f.read()
        css = urls(fonts(recolor(css)), out_dir, parent_name)
        head = "/* Generated by website/tools/recolor_layout.py from layouts/%s/assets/css/%s. Do not edit: */\n" \
               "/* re-run the installer. Our own rules are in chaos.css. */\n" % (parent_name, name)
        if name == FILES[-1] and os.path.isfile(ours):
            with open(ours, encoding="utf-8") as f:
                css += "\n\n/* ---- chaos.css ---- */\n" + f.read()
        with open(os.path.join(out_dir, name), "w", encoding="utf-8") as f:
            f.write(head + css)
        print("recoloured %s" % name)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
