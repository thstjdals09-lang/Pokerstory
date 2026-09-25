"""Visual slice 01 art: hand-authored vector sprites written as SVG.

Every asset is a plain SVG under game/assets/art/<group>/<name>.svg, drawn at 2x its on-screen size
(data/art.json gives the display size and the anchor). Replace any file with a PNG/SVG of the same
name (or point art.json at a new path) and nothing else changes.

Run:  python tools/art/make_slice_art.py
"""
import os

ROOT = os.path.join(os.path.dirname(__file__), '..', '..', 'game', 'assets', 'art')

INK = "#3b2a20"
CREAM = "#fff3d6"
WOOD, WOOD_D, WOOD_L = "#8a5a3c", "#6b4226", "#b98a5a"
PLASTER, PLASTER_D = "#f3e3c6", "#e0c9a3"
GLASS = "#cfe6f0"
GRASS, GRASS_D, GRASS_L = "#9cc47a", "#86b066", "#b2d48e"
STONE, STONE_D, STONE_L = "#dccfb6", "#c4b494", "#eadfca"
FELT, FELT_D, FELT_L = "#2f7a52", "#245f40", "#3b8c61"
RED, GOLD = "#c8553d", "#e0a526"


def svg(w, h, body, defs=""):
    return (f'<svg xmlns="http://www.w3.org/2000/svg" width="{w}" height="{h}" viewBox="0 0 {w} {h}">'
            f'<defs>{defs}</defs>{body}</svg>')


def r(x, y, w, h, fill, rx=0, stroke=INK, sw=3, extra=""):
    s = f' stroke="{stroke}" stroke-width="{sw}"' if stroke else ''
    return f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="{rx}" fill="{fill}"{s} {extra}/>'


def c(x, y, rad, fill, stroke=INK, sw=3, extra=""):
    s = f' stroke="{stroke}" stroke-width="{sw}"' if stroke else ''
    return f'<circle cx="{x}" cy="{y}" r="{rad}" fill="{fill}"{s} {extra}/>'


def e(x, y, rx, ry, fill, stroke=INK, sw=3, extra=""):
    s = f' stroke="{stroke}" stroke-width="{sw}"' if stroke else ''
    return f'<ellipse cx="{x}" cy="{y}" rx="{rx}" ry="{ry}" fill="{fill}"{s} {extra}/>'


def p(d, fill, stroke=INK, sw=3, extra=""):
    s = f' stroke="{stroke}" stroke-width="{sw}" stroke-linejoin="round" stroke-linecap="round"' if stroke else ''
    return f'<path d="{d}" fill="{fill}"{s} {extra}/>'


def lin(id, top, bottom, x2="0", y2="1"):
    return f'<linearGradient id="{id}" x1="0" y1="0" x2="{x2}" y2="{y2}"><stop offset="0" stop-color="{top}"/><stop offset="1" stop-color="{bottom}"/></linearGradient>'


def rad(id, inner, outer, o_in="1", o_out="0"):
    return (f'<radialGradient id="{id}"><stop offset="0" stop-color="{inner}" stop-opacity="{o_in}"/>'
            f'<stop offset="1" stop-color="{outer}" stop-opacity="{o_out}"/></radialGradient>')


def suit(kind, x, y, s, fill):
    """Small suit pip centred at x,y with size s (used sparingly)."""
    if kind == "heart":
        return p(f"M{x} {y+s*0.45} C{x-s*0.9} {y-s*0.1} {x-s*0.45} {y-s*0.75} {x} {y-s*0.3} C{x+s*0.45} {y-s*0.75} {x+s*0.9} {y-s*0.1} {x} {y+s*0.45} Z", fill, None)
    if kind == "diamond":
        return p(f"M{x} {y-s*0.55} L{x+s*0.4} {y} L{x} {y+s*0.55} L{x-s*0.4} {y} Z", fill, None)
    if kind == "club":
        return (c(x, y - s * 0.28, s * 0.24, fill, None) + c(x - s * 0.27, y + s * 0.05, s * 0.24, fill, None)
                + c(x + s * 0.27, y + s * 0.05, s * 0.24, fill, None) + p(f"M{x-s*0.08} {y} L{x-s*0.18} {y+s*0.5} L{x+s*0.18} {y+s*0.5} L{x+s*0.08} {y} Z", fill, None))
    # spade
    return (p(f"M{x} {y-s*0.55} C{x-s*0.85} {y+s*0.05} {x-s*0.45} {y+s*0.55} {x} {y+s*0.15} C{x+s*0.45} {y+s*0.55} {x+s*0.85} {y+s*0.05} {x} {y-s*0.55} Z", fill, None)
            + p(f"M{x-s*0.08} {y+s*0.1} L{x-s*0.18} {y+s*0.55} L{x+s*0.18} {y+s*0.55} L{x+s*0.08} {y+s*0.1} Z", fill, None))


def write(group, name, text):
    d = os.path.join(ROOT, group)
    os.makedirs(d, exist_ok=True)
    with open(os.path.join(d, name + '.svg'), 'w', encoding='utf-8') as f:
        f.write(text)


# ------------------------------------------------------------------------------------ tiles ----
def tiles():
    # grass: soft base with tufts and a few clover leaves
    body = r(0, 0, 256, 256, GRASS, stroke=None)
    import random
    rnd = random.Random(7)
    for _ in range(26):
        x, y = rnd.randint(8, 248), rnd.randint(8, 248)
        body += p(f"M{x} {y} l-4 -10 M{x} {y} l0 -12 M{x} {y} l5 -9", "none", GRASS_D, 2.5)
    for _ in range(10):
        x, y = rnd.randint(10, 246), rnd.randint(10, 246)
        body += e(x, y, rnd.randint(10, 22), rnd.randint(5, 9), GRASS_L, None, extra='opacity="0.55"')
    for _ in range(3):
        x, y = rnd.randint(20, 236), rnd.randint(20, 236)
        body += suit("club", x, y, 9, "#7fa85f")
    write('world', 'grass', svg(256, 256, body))
    # cobble: rounded stones on mortar
    body = r(0, 0, 256, 256, "#c9b99a", stroke=None)
    rnd = random.Random(3)
    y = 0
    row = 0
    while y < 256:
        x = -20 if row % 2 else 0
        while x < 256:
            w = rnd.randint(36, 52)
            col = rnd.choice([STONE, STONE_L, "#d6c8ac", "#e3d7bf"])
            body += r(x + 2, y + 2, w - 4, 28, col, rx=9, stroke="#b3a283", sw=2)
            x += w
        y += 32
        row += 1
    write('world', 'cobble', svg(256, 256, body))
    # plaza: larger fan stones, lighter
    body = r(0, 0, 256, 256, "#d8c9aa", stroke=None)
    rnd = random.Random(5)
    for yy in range(0, 256, 64):
        for xx in range(0, 256, 64):
            off = 32 if (yy // 64) % 2 else 0
            body += r((xx + off) % 256 + 3, yy + 3, 58, 58, rnd.choice(["#eadfc8", "#e4d6bb", "#efe5d2"]), rx=12, stroke="#c7b594", sw=2)
    write('world', 'plaza', svg(256, 256, body))
    # warm plank floor (card room: darker, home: honey)
    for name, base, line in (("floor_cardroom", "#8a5a44", "#6f4535"), ("floor_home", "#d9b889", "#bf9a6b")):
        body = r(0, 0, 256, 256, base, stroke=None)
        for i, yy in enumerate(range(0, 256, 32)):
            body += p(f"M0 {yy} L256 {yy}", "none", line, 2)
            xoff = 60 + (i * 90) % 170
            body += p(f"M{xoff} {yy} L{xoff} {yy+32}", "none", line, 2)
            body += c(xoff - 30, yy + 16, 1.6, line, None)
        write('world', name, svg(256, 256, body))


# ------------------------------------------------------------------------------- characters ----
def face(cx, cy, skin, hair=None, blush=True):
    s = c(cx, cy, 30, skin)
    s += e(cx - 11, cy + 3, 3.4, 4.6, INK, None) + e(cx + 11, cy + 3, 3.4, 4.6, INK, None)
    s += c(cx - 10, cy + 1.5, 1.2, "#ffffff", None) + c(cx + 12, cy + 1.5, 1.2, "#ffffff", None)
    if blush:
        s += e(cx - 18, cy + 12, 5, 3, "#f2a08a", None, extra='opacity="0.7"') + e(cx + 18, cy + 12, 5, 3, "#f2a08a", None, extra='opacity="0.7"')
    s += p(f"M{cx-4} {cy+14} Q{cx} {cy+18} {cx+4} {cy+14}", "none", INK, 2.5)
    return s


def characters():
    # player: traveller, mustard coat, teal scarf, satchel (56x72 display -> 112x144)
    defs = lin("coat", "#e3b04b", "#c8923a")
    b = ""
    b += r(38, 114, 14, 26, "#5a3a28", rx=6) + r(60, 114, 14, 26, "#5a3a28", rx=6)
    b += p("M30 72 Q56 62 82 72 L88 118 Q56 126 24 118 Z", "url(#coat)")
    b += p("M56 74 L56 118", "none", "#a8762c", 2.5) + c(52, 88, 2.4, INK, None) + c(52, 102, 2.4, INK, None)
    b += p("M84 76 L96 104 L90 108 L80 86", "#e3b04b")  # arm
    b += p("M28 76 L16 104 L22 108 L32 86", "#e3b04b")
    b += r(76, 92, 22, 18, "#8a5a3c", rx=4) + p("M80 78 L92 94", "none", "#6b4226", 3)  # satchel
    b += p("M34 66 Q56 78 78 66 L80 74 Q56 88 32 74 Z", "#3e8e8a") + p("M70 74 L78 96 L70 96 L64 78", "#3e8e8a")  # scarf
    b += face(56, 42, "#f6d7b8")
    b += p("M26 40 Q24 10 56 10 Q88 10 86 40 Q80 26 66 24 Q60 32 46 28 Q36 30 26 40 Z", "#6b4226")
    write('characters', 'player', svg(112, 144, b, defs))

    # Lumi: fox-kin host - fox ears, big tail, red vest with heart pin (56x72)
    defs = lin("fur", "#f09a5a", "#d9763a") + lin("vest", "#d9604a", "#b34a36")
    b = ""
    b += p("M84 98 C120 92 120 50 100 44 C108 70 96 86 80 90 Z", "url(#fur)")  # tail
    b += p("M100 44 C108 52 108 62 104 70 C100 60 96 54 100 44 Z", CREAM, None)
    b += r(40, 114, 13, 26, "#4a3226", rx=6) + r(60, 114, 13, 26, "#4a3226", rx=6)
    b += p("M32 74 Q56 64 80 74 L84 118 Q56 126 28 118 Z", "#fff3e0")
    b += p("M34 76 Q56 70 78 76 L80 110 Q56 116 32 110 Z", "url(#vest)")
    b += suit("heart", 66, 90, 10, GOLD)
    b += p("M80 78 L92 102 L86 106 L76 88", "#fff3e0") + p("M32 78 L20 102 L26 106 L36 88", "#fff3e0")
    b += p("M28 30 L22 2 L46 18 Z", "url(#fur)") + p("M31 24 L28 10 L40 19 Z", CREAM, None)
    b += p("M84 30 L90 2 L66 18 Z", "url(#fur)") + p("M81 24 L84 10 L72 19 Z", CREAM, None)
    b += face(56, 44, "#f8dcc2")
    b += p("M26 44 Q22 12 56 12 Q90 12 86 44 Q82 30 70 26 Q64 36 48 30 Q34 30 26 44 Z", "url(#fur)")
    write('characters', 'lumi', svg(112, 144, b, defs))

    # Moa: chip fairy - hovering, chip-disc dress, gold bun, glassy wings (44x56 -> 88x112)
    defs = lin("wing", "#e8f6ff", "#a9d8f0")
    b = ""
    b += e(20, 50, 18, 28, "url(#wing)", "#7fb3cf", 2.5, 'transform="rotate(-25 20 50)" opacity="0.9"')
    b += e(68, 50, 18, 28, "url(#wing)", "#7fb3cf", 2.5, 'transform="rotate(25 68 50)" opacity="0.9"')
    b += c(44, 76, 22, RED)
    for i in range(8):
        import math
        a = math.tau * i / 8
        b += p(f"M{44+math.cos(a)*16} {76+math.sin(a)*16} L{44+math.cos(a)*21} {76+math.sin(a)*21}", "none", CREAM, 4)
    b += c(44, 76, 10, "#f7d6a8", "#a8762c", 2)
    b += suit("club", 44, 76, 9, RED)
    b += p("M34 98 L32 108 M54 98 L56 108", "none", INK, 3)
    b += c(44, 38, 20, "#f8dcc2")
    b += e(37, 40, 2.6, 3.4, INK, None) + e(51, 40, 2.6, 3.4, INK, None)
    b += e(33, 47, 3.6, 2.2, "#f2a08a", None, extra='opacity="0.8"') + e(55, 47, 3.6, 2.2, "#f2a08a", None, extra='opacity="0.8"')
    b += p("M40 50 Q44 54 48 50", "none", INK, 2)
    b += p("M24 36 Q24 16 44 16 Q64 16 64 36 Q58 26 44 28 Q30 26 24 36 Z", "#f2c94c")
    b += c(44, 12, 8, "#f2c94c")
    write('characters', 'moa', svg(88, 112, b, defs))

    # Sera: tall shop mage - pointed violet hat with a tiny lantern charm, apron, lantern in hand (56x88)
    defs = lin("robe", "#9a7ac8", "#7458a6") + lin("hat", "#7b5cab", "#5a4185") + rad("lanternglow", "#ffe7a3", "#ffd27a", "0.95", "0")
    b = ""
    b += p("M28 90 Q56 80 84 90 L94 170 Q56 178 18 170 Z", "url(#robe)")
    b += p("M40 96 Q56 92 72 96 L76 160 Q56 164 36 160 Z", "#f5e6ff")
    b += p("M40 120 L72 120", "none", "#d8c5ec", 2.5)
    b += p("M82 96 L98 124 L92 128 L78 106", "url(#robe)") + p("M30 96 L16 124 L22 128 L34 106", "url(#robe)")
    b += p("M95 128 L95 136", "none", INK, 2.5) + r(88, 136, 14, 18, "#ffd27a", rx=4) + c(95, 145, 14, "url(#lanternglow)", None)
    b += p("M34 64 Q30 112 24 118 L40 110 Z", "#d9d0ee") + p("M78 64 Q82 112 88 118 L72 110 Z", "#d9d0ee")  # hair
    b += face(56, 66, "#f6dcc6")
    b += p("M16 60 Q56 46 96 60 Q84 66 56 64 Q28 66 16 60 Z", "url(#hat)")
    b += p("M30 58 Q48 34 58 4 Q66 34 82 58 Q56 50 30 58 Z", "url(#hat)")
    b += p("M58 4 Q70 6 72 16", "none", INK, 2.5) + c(72, 20, 4.5, "#ffd27a")
    b += suit("diamond", 56, 44, 10, GOLD)
    write('characters', 'sera', svg(112, 176, b, defs))


# ---------------------------------------------------------------------------------- buildings --
def window(x, y, w, h, frame=WOOD_D, lit=False, arch=False):
    glass = "#ffd98a" if lit else GLASS
    if arch:
        s = p(f"M{x} {y+h} L{x} {y+w/2} A{w/2} {w/2} 0 0 1 {x+w} {y+w/2} L{x+w} {y+h} Z", glass, frame, 4)
    else:
        s = r(x, y, w, h, glass, rx=4, stroke=frame, sw=4)
    s += p(f"M{x+w/2} {y+4} L{x+w/2} {y+h-2} M{x+2} {y+h*0.55} L{x+w-2} {y+h*0.55}", "none", frame, 3)
    return s


def door(cx, bottom, w=76, h=110, col="#8a5a3c", round_top=True):
    x = cx - w / 2
    y = bottom - h
    s = p(f"M{x} {bottom} L{x} {y+w/2} A{w/2} {w/2} 0 0 1 {x+w} {y+w/2} L{x+w} {bottom} Z", col, INK, 4) if round_top else r(x, y, w, h, col, rx=4, sw=4)
    for i in range(1, 3):
        s += p(f"M{x+i*w/3} {y+w/2-6} L{x+i*w/3} {bottom-4}", "none", "#6b4226", 2.5)
    s += c(cx + w * 0.3, bottom - h * 0.42, 4, GOLD, INK, 2)
    s += r(cx - w / 2 - 12, bottom - 2, w + 24, 12, "#a8876a", rx=4, stroke=INK, sw=2.5)
    return s


def buildings():
    # player cottage (340x300 display -> 680x600); door bottom-centre at (340, 596)
    defs = lin("roofg", "#7fa25c", "#5c7c41") + lin("wallp", PLASTER, PLASTER_D)
    b = e(340, 590, 330, 18, "#000000", None, extra='opacity="0.14"')
    b += r(60, 250, 560, 342, "url(#wallp)", rx=6, sw=5)
    for x in (60, 220, 460, 616):  # timber frame
        b += r(x, 250, 8, 342, WOOD, stroke=None)
    b += r(60, 420, 560, 8, WOOD, stroke=None)
    b += r(470, 60, 60, 140, "#b5655b", rx=4, sw=4) + r(462, 50, 76, 20, "#95504a", rx=4, sw=4)  # chimney
    b += p("M30 270 L340 70 L650 270 Z", "url(#roofg)", INK, 5)
    for i in range(1, 6):
        yy = 70 + i * 34
        span = (yy - 70) / 200 * 310
        b += p(f"M{340-span} {yy} L{340+span} {yy}", "none", "#55703b", 3)
    b += c(340, 190, 34, GLASS, WOOD_D, 5) + p("M340 158 L340 222 M308 190 L372 190", "none", WOOD_D, 3)
    b += window(110, 300, 92, 90) + window(478, 300, 92, 90)
    b += r(104, 392, 104, 26, "#8a5a3c", rx=4, sw=3)  # flower box, sparse: a new home
    b += c(130, 388, 8, "#f28b82", INK, 2) + c(156, 386, 6, "#86b066", INK, 2)
    b += door(340, 596, 96, 140)
    b += suit("heart", 340, 452, 16, "#c8553d")  # carved heart above the door
    b += p("M404 470 L420 470 L420 490", "none", INK, 3) + r(412, 490, 16, 22, "#e0c9a3", rx=4, sw=2.5)  # empty lantern hook
    write('buildings', 'home_player', svg(680, 600, b, defs))

    # Sera's shop (340x280 -> 680x560); striped awning, display window of little lamps
    defs = lin("roofr", "#c47266", "#9a524a") + lin("wallc", "#f5e1c0", "#e3c99f")
    b = e(340, 552, 330, 16, "#000", None, extra='opacity="0.14"')
    b += r(50, 220, 580, 336, "url(#wallc)", rx=6, sw=5)
    b += p("M20 240 L110 70 L570 70 L660 240 Z", "url(#roofr)", INK, 5)
    for i in range(1, 5):
        yy = 70 + i * 34
        b += p(f"M{110-i*22} {yy} L{570+i*22} {yy}", "none", "#86463f", 3)
    for i in range(8):  # awning stripes
        x = 70 + i * 68
        b += p(f"M{x} 300 L{x+68} 300 L{x+62} 350 Q{x+34} 362 {x+6} 350 Z", RED if i % 2 == 0 else CREAM, INK, 3)
    b += r(80, 370, 200, 120, "#ffe7b0", rx=6, stroke=WOOD_D, sw=5)  # display window
    for i, x in enumerate((110, 160, 210, 250)):
        b += p(f"M{x} 380 L{x} 410", "none", INK, 2) + c(x, 420, 12, "#ffd27a", INK, 2.5)
    b += door(340, 552, 90, 136, "#9a6a44")
    b += r(440, 380, 150, 90, GLASS, rx=4, stroke=WOOD_D, sw=5) + p("M515 384 L515 466", "none", WOOD_D, 3)
    b += p("M530 250 L530 275 M610 250 L610 275", "none", INK, 3) + r(510, 275, 120, 50, "#e7c796", rx=6, sw=4)  # hanging sign
    b += suit("diamond", 540, 300, 26, "#c8553d") + c(592, 300, 12, "#ffd27a", INK, 2.5)
    b += r(70, 500, 60, 50, "#b98a5a", rx=3, sw=3) + p("M70 525 L130 525 M100 500 L100 550", "none", WOOD_D, 2.5)  # crate
    b += e(580, 522, 26, 30, "#9a6a44", INK, 3) + p("M556 510 L604 510 M556 534 L604 534", "none", "#6b4226", 3)  # barrel
    write('buildings', 'shop_sera', svg(680, 560, b, defs))

    # card room (340x300 -> 680x600); navy slate roof, arched warm windows, club sign
    defs = lin("roofn", "#44628f", "#2b4466") + lin("wallw", "#e9d3b8", "#d6b995")
    b = e(340, 592, 330, 16, "#000", None, extra='opacity="0.16"')
    b += r(50, 250, 580, 346, "url(#wallw)", rx=6, sw=5)
    b += r(50, 470, 580, 126, "#a0735a", stroke=INK, sw=5)  # wood wainscot
    for x in range(90, 630, 60):
        b += p(f"M{x} 474 L{x} 592", "none", "#855a44", 3)
    b += p("M24 272 L150 70 L530 70 L656 272 Z", "url(#roofn)", INK, 5)
    for i in range(1, 6):
        yy = 70 + i * 34
        b += p(f"M{150-i*21} {yy} L{530+i*21} {yy}", "none", "#233a57", 3)
    b += window(90, 300, 100, 140, arch=True) + window(490, 300, 100, 140, arch=True)
    b += door(340, 596, 110, 160, "#6e4533")
    b += p("M280 380 L280 400 M400 380 L400 400", "none", INK, 3) + r(262, 330, 156, 58, "#3d2a25", rx=8, stroke=GOLD, sw=4)
    b += suit("club", 300, 360, 26, "#f3dfc1") + '<text x="355" y="370" font-family="serif" font-size="30" fill="#f3dfc1" text-anchor="middle">모임</text>'
    b += p("M226 470 L226 440", "none", INK, 3) + r(212, 440, 28, 36, "#ffd27a", rx=6, sw=3)  # door lanterns
    b += p("M454 470 L454 440", "none", INK, 3) + r(440, 440, 28, 36, "#ffd27a", rx=6, sw=3)
    write('buildings', 'card_room', svg(680, 600, b, defs))

    # village hall (320x280 -> 640x560)
    defs = lin("roofl", "#8a7aae", "#61547f") + lin("wallh", "#efe0c4", "#dcc6a2")
    b = e(320, 552, 310, 16, "#000", None, extra='opacity="0.14"')
    b += r(40, 230, 560, 326, "url(#wallh)", rx=6, sw=5)
    b += p("M16 250 L320 60 L624 250 Z", "url(#roofl)", INK, 5)
    b += c(320, 170, 36, CREAM, INK, 4) + p("M320 146 L320 170 L338 180", "none", INK, 4)
    for x in (90, 180, 400, 490):
        b += window(x, 300, 70, 110, arch=True)
    b += door(320, 552, 110, 150, "#7b5a8a")
    b += r(250, 250, 140, 40, "#f5e6c8", rx=6, sw=3) + '<text x="320" y="279" font-family="serif" font-size="26" fill="#3b2a20" text-anchor="middle">마을 회관</text>'
    write('buildings', 'hall', svg(640, 560, b, defs))

    # district gate (display 110x100 -> 220x200)
    b = r(30, 40, 22, 156, WOOD, rx=4) + r(168, 40, 22, 156, WOOD, rx=4)
    b += p("M10 52 Q110 0 210 52 L210 70 Q110 22 10 70 Z", "#6f8f4e", INK, 4)
    b += p("M100 60 L100 86", "none", INK, 3) + r(84, 86, 32, 36, "#ffd27a", rx=6, sw=3)
    write('buildings', 'gate', svg(220, 200, b))


# ------------------------------------------------------------------------------------- props ----
def props():
    # trees (100x120 -> 200x240), two kinds
    for name, canopy, dark, blossom in (("tree", "#6aa860", "#4f8a4b", None), ("tree_blossom", "#7db86a", "#5a9a50", "#f7c6cf")):
        b = e(100, 226, 56, 12, "#000", None, extra='opacity="0.16"')
        b += p("M88 230 L92 150 L108 150 L112 230 Z", "#7a5230")
        b += c(100, 110, 72, dark) + c(66, 96, 44, canopy, None) + c(128, 88, 48, canopy, None) + c(100, 64, 46, canopy, None)
        b += c(82, 70, 16, "#8cc47a", None, extra='opacity="0.7"')
        if blossom:
            for (x, y) in ((70, 100), (120, 70), (140, 118), (90, 130), (104, 52)):
                b += c(x, y, 7, blossom, None)
        write('props', name, svg(200, 240, b))
    # fountain (180x150 -> 360x300); suit medallions on the basin, water tiers
    defs = lin("water", "#9fd6ec", "#6db7d6")
    b = e(180, 250, 172, 44, "#000", None, extra='opacity="0.14"')
    b += e(180, 210, 166, 70, STONE_D) + e(180, 196, 150, 58, "url(#water)", "#8a9fa8", 3)
    for i, k in enumerate(("spade", "heart", "diamond", "club")):
        x = 70 + i * 73
        b += c(x, 262 - abs(1.5 - i) * 8, 13, STONE_L, INK, 2.5) + suit(k, x, 262 - abs(1.5 - i) * 8, 13, "#8a7a64")
    b += r(160, 90, 40, 110, STONE, rx=8, sw=3) + e(180, 96, 52, 18, STONE_L) + e(180, 90, 38, 12, "url(#water)", None)
    b += p("M180 80 Q176 50 180 30 Q184 50 180 80", "#cdeefb", None, extra='opacity="0.8"')
    b += p("M150 96 Q120 120 110 170 M210 96 Q240 120 250 170", "none", "#e8f7fd", 4, 'opacity="0.8"')
    write('props', 'fountain', svg(360, 300, b, defs))
    # lamp post (30x100 -> 60x200)
    b = e(30, 194, 18, 5, "#000", None, extra='opacity="0.18"') + r(26, 60, 8, 134, "#3b3a3f", rx=3, sw=2)
    b += r(18, 186, 24, 8, "#3b3a3f", rx=3, sw=2) + p("M14 34 L46 34 L42 64 L18 64 Z", "#ffe6a6", INK, 3) + p("M10 34 L30 18 L50 34 Z", "#3b3a3f", INK, 3)
    write('props', 'lamp_post', svg(60, 200, b))
    # bench (80x44 -> 160x88)
    b = e(80, 82, 70, 6, "#000", None, extra='opacity="0.16"') + r(8, 30, 144, 16, WOOD_L, rx=4) + r(8, 48, 144, 16, WOOD, rx=4)
    b += r(18, 64, 10, 20, WOOD_D, rx=2) + r(132, 64, 10, 20, WOOD_D, rx=2)
    write('props', 'bench', svg(160, 88, b))
    # flower bed (130x50 -> 260x100)
    b = r(6, 30, 248, 64, "#8a5a3c", rx=10) + r(14, 20, 232, 40, "#6f9a4f", rx=14, stroke=None)
    for i, col in enumerate(["#f28b82", "#fbbc04", "#ffffff", "#c58af9", "#f28b82", "#fbbc04", "#ffffff", "#c58af9", "#f28b82"]):
        x = 30 + i * 25
        b += c(x, 34 + (i % 2) * 12, 8, col, INK, 2) + c(x, 34 + (i % 2) * 12, 3, "#f2c94c", None)
    write('props', 'flower_bed', svg(260, 100, b))
    # job board (90x90 -> 180x180): notice board with pinned papers and a chip
    b = r(24, 70, 12, 104, WOOD_D, rx=3) + r(144, 70, 12, 104, WOOD_D, rx=3)
    b += r(8, 20, 164, 100, "#b98a5a", rx=6, sw=4) + p("M8 20 L90 4 L172 20", "#8a5a3c", INK, 4)
    b += r(22, 34, 44, 54, "#fff8ec", rx=2, sw=2, extra='transform="rotate(-4 44 61)"') + r(76, 36, 40, 44, "#ffe9a8", rx=2, sw=2)
    b += r(124, 34, 36, 50, "#e8f1ff", rx=2, sw=2, extra='transform="rotate(5 142 59)"') + c(96, 98, 10, RED, INK, 2)
    for x in (44, 96, 142):
        b += c(x, 38, 3, RED, None)
    write('props', 'job_board', svg(180, 180, b))
    # direction signpost (60x70 -> 120x140)
    b = r(54, 30, 12, 106, WOOD_D, rx=3)
    b += p("M16 24 L92 24 L106 38 L92 52 L16 52 Z", "#d9b27c", INK, 3) + p("M104 62 L28 62 L14 76 L28 90 L104 90 Z", "#c9a06a", INK, 3)
    write('props', 'signpost', svg(120, 140, b))
    # card room A-frame board (50x60 -> 100x120) with a single club
    b = p("M20 116 L38 16 L62 16 L80 116", "none", WOOD_D, 5) + r(22, 20, 56, 64, "#3d2a25", rx=4, stroke=WOOD, sw=4)
    b += suit("club", 50, 44, 18, "#f3dfc1") + p("M32 66 L68 66 M36 74 L64 74", "none", "#f3dfc1", 2.5)
    write('props', 'aframe', svg(100, 120, b))
    # festival booth (120x80 -> 240x160)
    b = r(20, 60, 200, 90, "#c9a37a", rx=4, sw=4)
    for i in range(6):
        b += p(f"M{20+i*33.3} 36 L{53.3+i*33.3} 36 L{50+i*33.3} 62 L{23+i*33.3} 62 Z", RED if i % 2 == 0 else CREAM, INK, 3)
    b += r(14, 26, 212, 12, WOOD_D, rx=3)
    write('props', 'booth', svg(240, 160, b))
    # crates stack and a flower pot for lived-in corners
    b = r(10, 50, 70, 60, "#b98a5a", rx=3) + p("M10 80 L80 80 M45 50 L45 110", "none", WOOD_D, 2.5) + r(30, 10, 60, 44, "#c9a06a", rx=3) + p("M30 32 L90 32", "none", WOOD_D, 2.5)
    write('props', 'crates', svg(100, 120, b))
    b = p("M20 60 L80 60 L72 110 L28 110 Z", "#c8553d") + c(50, 44, 22, "#6aa860") + c(36, 36, 14, "#86b066", None) + c(62, 34, 14, "#86b066", None)
    write('props', 'pot_plant', svg(100, 120, b))


# ------------------------------------------------------------------------------------ interiors ---
def interiors():
    # card room back wall (960x120 -> 1920x240): wainscot, rules board, frames, chip shelf, windows
    defs = lin("wallcr", "#6b4a3f", "#553a31")
    b = r(0, 0, 1920, 240, "url(#wallcr)", stroke=None) + r(0, 170, 1920, 70, "#4a3129", stroke=None) + p("M0 170 L1920 170", "none", "#2e1f1a", 4)
    b += window(140, 40, 120, 110, frame="#2e1f1a", lit=True, arch=True) + window(1660, 40, 120, 110, frame="#2e1f1a", lit=True, arch=True)
    b += r(760, 24, 400, 130, "#b98a5a", rx=8, stroke="#2e1f1a", sw=5)  # rules board
    b += '<text x="960" y="62" font-family="serif" font-size="30" fill="#3b2a20" text-anchor="middle">모임 규칙</text>'
    for i, t in enumerate(("다섯 장 받고, 한 번 바꾸기", "구경만 해도 괜찮아요", "끝나면 같이 차 한 잔")):
        b += f'<text x="960" y="{96+i*24}" font-family="serif" font-size="20" fill="#3b2a20" text-anchor="middle">· {t}</text>'
    for x, k in ((440, "heart"), (560, "spade"), (1300, "club"), (1420, "diamond")):  # small framed pictures, not casino decor
        b += r(x, 60, 80, 64, "#f3e2c0", rx=4, stroke=GOLD, sw=4) + suit(k, x + 40, 92, 22, "#8a5a3c")
    write('interiors', 'wall_cardroom', svg(1920, 240, b, defs))
    # poker table (260x200 -> 520x400): wood rim, felt, a few cards and chips
    defs = rad("feltg", FELT_L, FELT_D, "1", "1") + lin("rim", "#8a5a3c", "#5e3a26")
    b = e(260, 230, 250, 150, "#000", None, extra='opacity="0.25"')
    b += e(260, 200, 250, 160, "url(#rim)", INK, 5) + e(260, 196, 220, 136, "url(#feltg)", "#1f4f36", 3)
    b += e(260, 196, 170, 100, "none", "#6fb08a", 2.5, 'stroke-dasharray="10 8" opacity="0.6"')
    for i, k in enumerate(("spade", "heart", "diamond", "club")):
        import math
        a = math.tau * i / 4 + 0.6
        b += suit(k, 260 + math.cos(a) * 150, 196 + math.sin(a) * 88, 16, "#5fa37e")
    b += r(200, 170, 40, 56, CREAM, rx=5, sw=2.5, extra='transform="rotate(-10 220 198)"') + r(250, 168, 40, 56, "#2e4a74", rx=5, sw=2.5, extra='transform="rotate(8 270 196)"')
    for j, col in enumerate((RED, RED, "#2e4a74", GOLD)):
        b += e(330 + (j % 2) * 26, 220 - j * 6, 16, 8, col, INK, 2)
    write('interiors', 'poker_table', svg(520, 400, b, defs))
    # chair (40x46 -> 80x92)
    b = r(14, 8, 52, 44, "#8a5a3c", rx=8) + r(10, 46, 60, 22, "#b98a5a", rx=6) + r(14, 66, 8, 22, WOOD_D, rx=2) + r(58, 66, 8, 22, WOOD_D, rx=2)
    b += r(22, 16, 36, 24, "#c8553d", rx=6, stroke=None, extra='opacity="0.85"')
    write('interiors', 'chair', svg(80, 92, b))
    # chip shelf (120x80 -> 240x160)
    b = r(6, 6, 228, 148, "#5a3d2e", rx=6) + p("M6 56 L234 56 M6 106 L234 106", "none", "#3d2a25", 5)
    for row, y in enumerate((36, 86, 136)):
        for i in range(5):
            b += e(34 + i * 44, y, 16, 7, [RED, "#2e4a74", GOLD, CREAM, "#3e8e8a"][(i + row) % 5], INK, 2)
    write('interiors', 'chip_shelf', svg(240, 160, b))
    # oval rug for the card room (360x320 -> 720x640)
    b = e(360, 320, 350, 300, "#6e3f36", INK, 4) + e(360, 320, 310, 262, "none", "#c8a66a", 4) + e(360, 320, 280, 236, "#7a4a3f", None)
    write('interiors', 'rug_cardroom', svg(720, 640, b))
    # tea counter corner (130x80 -> 260x160)
    b = r(6, 40, 248, 110, "#8a5a3c", rx=6) + r(0, 30, 260, 20, "#b98a5a", rx=4)
    b += e(70, 22, 22, 16, CREAM, INK, 2.5) + p("M92 20 L106 12", "none", INK, 3) + e(150, 26, 12, 8, CREAM, INK, 2) + e(190, 26, 12, 8, CREAM, INK, 2)
    write('interiors', 'tea_counter', svg(260, 160, b))
    # coat rack with a scarf (40x100 -> 80x200)
    b = r(36, 30, 8, 164, WOOD_D, rx=3) + e(40, 194, 30, 6, WOOD_D) + p("M40 36 L16 56 M40 36 L64 56", "none", WOOD_D, 5)
    b += p("M18 56 Q14 110 24 130 L32 126 Q26 100 28 60 Z", "#3e8e8a")
    write('interiors', 'coat_rack', svg(80, 200, b))

    # home back wall (960x120 -> 1920x240): plaster, window, a shelf, a bare nail
    defs = lin("wallhm", "#e9d4b0", "#d9bf95")
    b = r(0, 0, 1920, 240, "url(#wallhm)", stroke=None) + r(0, 190, 1920, 50, "#b58d62", stroke=None) + p("M0 190 L1920 190", "none", "#8a6a48", 4)
    b += window(860, 20, 200, 150, frame="#8a6a48")
    b += p("M860 20 Q900 90 880 170 L860 170 Z M1060 20 Q1020 90 1040 170 L1060 170 Z", "#e6a88a", INK, 3)  # curtains
    b += r(300, 120, 200, 14, "#8a5a3c", rx=3) + c(1400, 90, 4, "#6b4226", None)
    write('interiors', 'wall_home', svg(1920, 240, b, defs))
    # bed (170x130 -> 340x260)
    b = e(170, 250, 160, 10, "#000", None, extra='opacity="0.15"') + r(10, 10, 320, 60, WOOD, rx=12) + r(18, 40, 304, 200, "#f8efe0", rx=14)
    b += r(18, 110, 304, 130, "#9fb8d9", rx=14) + p("M18 140 L322 140", "none", "#7f9cc2", 3) + r(40, 56, 110, 50, "#ffffff", rx=16) + r(190, 56, 110, 50, "#ffffff", rx=16)
    write('interiors', 'bed', svg(340, 260, b))
    # table (170x90 -> 340x180)
    b = e(170, 172, 150, 8, "#000", None, extra='opacity="0.15"') + r(10, 20, 320, 110, "#b98a5a", rx=10) + r(24, 120, 16, 50, WOOD_D, rx=3) + r(300, 120, 16, 50, WOOD_D, rx=3)
    b += e(90, 70, 20, 12, CREAM, INK, 2.5)
    write('interiors', 'table_home', svg(340, 180, b))
    # storage chest (90x60 -> 180x120)
    b = r(8, 30, 164, 84, "#7d5a3c", rx=8) + r(8, 22, 164, 30, "#8f6a4a", rx=8) + r(80, 44, 20, 20, GOLD, rx=3, sw=2.5)
    write('interiors', 'chest', svg(180, 120, b))
    # cosy rug (200x130 -> 400x260)
    b = r(10, 10, 380, 240, "#c97b63", rx=26) + r(34, 34, 332, 192, "none", rx=18, stroke="#f3d4b8", sw=4)
    for i in range(3):
        b += suit("heart", 140 + i * 60, 130, 18, "#e3a58f")
    write('interiors', 'rug_home', svg(400, 260, b))
    # moving boxes (just arrived; 70x60 -> 140x120)
    b = r(10, 50, 80, 64, "#c9a06a", rx=3) + p("M10 70 L90 70", "none", "#9a7446", 3) + r(70, 20, 60, 50, "#d6b07a", rx=3) + p("M70 36 L130 36", "none", "#9a7446", 3)
    write('interiors', 'boxes', svg(140, 120, b))
    # blueprint scroll on a stand (50x40 -> 100x80)
    b = r(10, 26, 80, 40, "#dfe9f5", rx=4, stroke="#35507a", sw=3) + p("M20 36 L60 36 M20 46 L80 46 M20 56 L50 56", "none", "#35507a", 2.5)
    b += c(10, 46, 10, "#c9d8ea", "#35507a", 3) + c(90, 46, 10, "#c9d8ea", "#35507a", 3)
    write('interiors', 'blueprint', svg(100, 80, b))


# ---------------------------------------------------------------------------------- items / ui ---
def items_ui():
    # the first-play lamp (40x60 -> 80x120): shade with a small spade cut-out
    defs = lin("shade", "#ffe6a6", "#f4c56a")
    b = e(40, 114, 26, 6, "#000", None, extra='opacity="0.18"') + r(30, 104, 20, 10, "#6b4226", rx=3) + r(36, 60, 8, 46, "#6b4226", rx=2, sw=2)
    b += p("M14 62 L66 62 L54 20 L26 20 Z", "url(#shade)", INK, 3.5) + suit("spade", 40, 42, 12, "#c98a3a")
    write('items', 'lamp_small', svg(80, 120, b, defs))
    # UI: chip, sun, moon
    b = c(24, 24, 20, RED, INK, 3) + c(24, 24, 10, CREAM, None)
    import math
    for i in range(6):
        a = math.tau * i / 6
        b += p(f"M{24+math.cos(a)*14} {24+math.sin(a)*14} L{24+math.cos(a)*19} {24+math.sin(a)*19}", "none", CREAM, 4)
    write('ui', 'chip', svg(48, 48, b))
    b = c(24, 24, 11, "#f7c948", INK, 3)
    for i in range(8):
        a = math.tau * i / 8
        b += p(f"M{24+math.cos(a)*15} {24+math.sin(a)*15} L{24+math.cos(a)*21} {24+math.sin(a)*21}", "none", "#e0a526", 3.5)
    write('ui', 'sun', svg(48, 48, b))
    b = p("M30 6 A18 18 0 1 0 42 34 A14 14 0 1 1 30 6 Z", "#f3e2a8", INK, 3) + c(12, 14, 2, "#fff8d8", None) + c(40, 12, 1.6, "#fff8d8", None)
    write('ui', 'moon', svg(48, 48, b))


if __name__ == '__main__':
    tiles(); characters(); buildings(); props(); interiors(); items_ui()
    print('art written to', os.path.abspath(ROOT))
