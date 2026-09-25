"""Square art (direction B, hand-painted 2D): turns the AI-generated sources in
art_src/square/raw (and the sheets cut into art_src/square/cut by cut_sheet.py)
into final sprites at twice their display size, and registers them in game/data/art.json.

Display sizes and anchors live here; gameplay data only names the keys.
    python tools/art/build_square_art.py
"""
import json
import os
from PIL import Image

ROOT = os.path.join(os.path.dirname(__file__), '..', '..', 'game')
SQ = os.path.join(ROOT, 'assets', 'art', 'square')
SRC = os.path.join(os.path.dirname(__file__), '..', '..', 'art_src', 'square')
RES = 'res://assets/art/square/final/'
SCALE = 2  # final textures are twice the display size


def load(rel):
    im = Image.open(os.path.join(SRC, rel)).convert('RGBA')
    bb = im.getchannel('A').point(lambda v: 255 if v > 8 else 0).getbbox()
    return im.crop(bb) if bb else im


def put(im, name, h=None, w=None, scale=SCALE):
    """Saves `im` scaled to display height `h` (or width `w`); returns the display size."""
    if h is not None:
        w = round(im.width * h / im.height)
    else:
        h = round(im.height * w / im.width)
    out = im.resize((w * scale, h * scale), Image.LANCZOS)
    path = os.path.join(SQ, 'final', name + '.png')
    os.makedirs(os.path.dirname(path), exist_ok=True)
    out.save(path, optimize=True)
    return [w, h]


def sprite(name, size, ax, ay, **kw):
    d = {'path': RES + name + '.png', 'size': size, 'anchor': [round(size[0] * ax), round(size[1] * ay)]}
    d.update(kw)
    return d


def lights(size, pts):
    """Lights given as fractions of the sprite size, relative to the anchor."""
    return [[round(size[0] * x), round(size[1] * y), r, e] for x, y, r, e in pts]


S = {}

# --- ground: one painted plate for the whole square (1600 x 1100)
g = Image.open(os.path.join(SRC, 'raw', 'ground_plate.png')).convert('RGB')
g.resize((2048, 1408), Image.LANCZOS).save(os.path.join(SQ, 'final', 'ground.png'), optimize=True)
S['sq.ground'] = {'path': RES + 'ground.png', 'size': [1600, 1100], 'anchor': [0, 0]}

# --- buildings: anchor = the door on the ground line (door.x, rect bottom)
for key, src, h, ax, ay, pts in [
    ('sq.bld_shop', 'raw/bld_shop.png', 341, 0.62, 0.97, [(-0.42, -0.2, 110, 1.0), (-0.3, -0.62, 70, 0.7), (0.05, -0.68, 70, 0.7)]),
    ('sq.bld_home', 'raw/bld_home.png', 321, 0.50, 0.98, [(-0.3, -0.3, 80, 0.8), (0.28, -0.3, 80, 0.8), (0.05, -0.62, 60, 0.6)]),
    ('sq.bld_cardroom', 'raw/bld_cardroom.png', 355, 0.58, 0.99,
     [(-0.2, -0.43, 120, 1.2), (0.12, -0.43, 120, 1.2), (-0.13, -0.2, 90, 1.1), (0.12, -0.2, 90, 1.1), (-0.5, -0.4, 80, 0.8), (0, -0.02, 150, 0.9)]),
    ('sq.bld_hall', 'raw/bld_hall.png', 324, 0.56, 0.99, [(-0.35, -0.3, 80, 0.7), (0.35, -0.3, 80, 0.7)]),
]:
    size = put(load(src), key[3:], h=h)
    S[key] = sprite(key[3:], size, ax, ay, sort=True, lights=lights(size, pts))

# --- props
PROPS = [
    # key, source, display (h or ('w', n)), anchor x, anchor y, extra
    ('sq.gate', 'raw/gate.png', 130, 0.5, 0.97, {'lights': [(0.3, -0.62, 70, 0.8)]}),
    ('sq.fountain', 'raw/fountain.png', 156, 0.5, 0.66, {}),
    ('sq.lamp', 'cut/sheet_street_0.png', 118, 0.5, 0.98, {'lights': [(0, -0.84, 140, 1.0)]}),
    ('sq.bench', 'cut/sheet_street_1.png', ('w', 84), 0.5, 0.92, {}),
    ('sq.board', 'cut/sheet_street_2.png', 122, 0.5, 0.97, {}),
    ('sq.signpost', 'cut/sheet_street_3.png', 90, 0.5, 0.97, {}),
    ('sq.tree', 'cut/sheet_plants_0.png', 160, 0.5, 0.96, {'sway': 0.03}),
    ('sq.tree_blossom', 'cut/sheet_plants_1.png', 160, 0.5, 0.96, {'sway': 0.03}),
    ('sq.bush', 'cut/sheet_plants_2.png', 58, 0.5, 0.92, {'sway': 0.025}),
    ('sq.planter', 'cut/sheet_plants_3.png', ('w', 130), 0.5, 0.9, {'sway': 0.012}),
    ('sq.booth', 'cut/sheet_misc_0.png', 140, 0.5, 0.95, {}),
    ('sq.crates', 'cut/sheet_misc_1.png', 62, 0.5, 0.95, {}),
    ('sq.pot', 'cut/sheet_misc_2.png', 54, 0.5, 0.95, {}),
    ('sq.aframe', 'cut/sheet_misc_3.png', 56, 0.5, 0.96, {}),
    # objects that appear with story progress
    ('sq.card_table', 'cut/sheet_story_0.png', ('w', 120), 0.5, 0.72, {}),
    ('sq.bunting', 'cut/sheet_story_1.png', ('w', 300), 0.5, 0.97, {'sway': 0.02}),
    ('sq.welcome', 'cut/sheet_story_2.png', ('w', 96), 0.5, 0.96, {}),
    ('sq.flag', 'cut/sheet_story_3.png', 120, 0.3, 0.98, {'sway': 0.06}),
]
for key, src, disp, ax, ay, extra in PROPS:
    im = load(src)
    size = put(im, key[3:], w=disp[1]) if isinstance(disp, tuple) else put(im, key[3:], h=disp)
    d = sprite(key[3:], size, ax, ay, sort=True)
    if 'lights' in extra:
        d['lights'] = lights(size, extra['lights'])
    if 'sway' in extra:
        d['sway'] = extra['sway']  # wind lean in radians (engine: ArtLib.sway)
    S[key] = d

# --- characters: five poses (front, front walking, side, side walking, back); side poses face right
FRAMES = ['', '@front1', '@side0', '@side1', '@back0']
CHARS = [('player', 84, False), ('lumi', 84, False), ('moa', 62, True), ('juno', 80, False), ('bibi', 70, False), ('miri', 92, False)]
for name, h, hover in CHARS:
    for i, suffix in enumerate(FRAMES):
        fname = 'char_%s%s' % (name, suffix.replace('@', '_'))
        size = put(load('cut/ch_%s_%d.png' % (name, i)), fname, h=h)
        d = sprite(fname, size, 0.5, 0.97)
        if hover:
            d['hover'] = True
        S['char.%s%s' % (name, suffix)] = d

# --- dialogue portraits: neutral, happy, troubled
PORTRAITS = {'player': 'cut/pt_player_%d.png', 'lumi': 'cut/pt_lumi_%d.png', 'moa': 'cut/pt_moa_%d.png', 'juno': 'cut/pt_juno_%d.png'}
for name, pattern in PORTRAITS.items():
    moods = {}
    for i, mood in enumerate(['neutral', 'happy', 'sad']):
        put(load(pattern % i), 'portrait_%s_%s' % (name, mood), h=128)
        moods[mood] = RES + 'portrait_%s_%s.png' % (name, mood)
    S['char.' + name]['portraits'] = moods
for row, name in enumerate(['bibi', 'miri']):
    moods = {}
    for i, mood in enumerate(['neutral', 'happy', 'sad']):
        put(load('cut/pt_bm_%d.png' % (row * 3 + i)), 'portrait_%s_%s' % (name, mood), h=128)
        moods[mood] = RES + 'portrait_%s_%s.png' % (name, mood)
    S['char.' + name]['portraits'] = moods

# --- UI pieces (textures for the parchment kit) at 1x: nine-slice borders draw texture pixels 1:1
UI = [('ui.panel', 0, 170), ('ui.tag', 1, 70), ('ui.tab', 2, 56), ('ui.slip', 3, 64), ('ui.pill', 4, 60),
      ('ui.chip', 5, 28), ('ui.sun', 6, 28), ('ui.moon', 7, 28), ('ui.suit_spade', 8, 24), ('ui.suit_diamond', 9, 24),
      ('ui.next', 10, 14), ('ui.suit_heart', 11, 24), ('ui.suit_club', 12, 24)]
for key, idx, h in UI:
    fname = key.replace('.', '_')
    size = put(load('cut/ui_%d.png' % idx), fname, h=h, scale=1)
    S[key] = sprite(fname, size, 0.5, 0.5)

p = os.path.join(ROOT, 'data', 'art.json')
A = json.load(open(p, encoding='utf-8'))
A['sprites'].update(S)
A['_comment_square'] = ('Square art (direction B, hand-painted 2D): sq.* and the char.* / ui.* entries come from '
                        'tools/art/build_square_art.py. Character poses: key (front), key@front1 (walking), '
                        'key@side0 / @side1 (facing right), key@back0. "portraits": neutral / happy / sad.')
json.dump(A, open(p, 'w', encoding='utf-8', newline='\n'), ensure_ascii=False, indent=1)
print(len(S), 'sprites')
