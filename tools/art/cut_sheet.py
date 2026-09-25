"""Cuts separate objects out of a transparent AI-generated sheet.

Objects are found as connected regions of the alpha channel (on a reduced grid, grown by `grow`
cells so wings, sparkles and tails stay with their body). Regions are ordered in rows (top to
bottom, then left to right) and saved trimmed, with a small margin.

    python tools/art/cut_sheet.py <sheet.png> <out_prefix> [--grow N] [--min-area PX] [--rows R]
    python tools/art/cut_sheet.py <sheet.png> <out_prefix> --grid COLSxROWS   (evenly spaced poses)
"""
import argparse
from PIL import Image, ImageFilter


def regions(alpha: Image.Image, cell: int, grow: int, min_area: int):
    small = alpha.resize((alpha.width // cell, alpha.height // cell), Image.BOX).point(lambda v: 255 if v > 24 else 0)
    if grow > 0:
        small = small.filter(ImageFilter.MaxFilter(grow * 2 + 1))
    w, h = small.size
    px = small.load()
    seen = [[False] * w for _ in range(h)]
    out = []
    for y in range(h):
        for x in range(w):
            if px[x, y] == 0 or seen[y][x]:
                continue
            stack = [(x, y)]
            seen[y][x] = True
            x0, y0, x1, y1, n = x, y, x, y, 0
            while stack:
                cx, cy = stack.pop()
                n += 1
                x0, y0, x1, y1 = min(x0, cx), min(y0, cy), max(x1, cx), max(y1, cy)
                for nx, ny in ((cx + 1, cy), (cx - 1, cy), (cx, cy + 1), (cx, cy - 1)):
                    if 0 <= nx < w and 0 <= ny < h and not seen[ny][nx] and px[nx, ny]:
                        seen[ny][nx] = True
                        stack.append((nx, ny))
            if n * cell * cell >= min_area:
                out.append((x0 * cell, y0 * cell, (x1 + 1) * cell, (y1 + 1) * cell))
    return out


def order(boxes, rows):
    boxes = sorted(boxes, key=lambda b: (b[1] + b[3]) / 2)
    if rows <= 1:
        return sorted(boxes, key=lambda b: b[0])
    per = -(-len(boxes) // rows)
    out = []
    for r in range(rows):
        out += sorted(boxes[r * per:(r + 1) * per], key=lambda b: b[0])
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('sheet')
    ap.add_argument('prefix')
    ap.add_argument('--grow', type=int, default=3)
    ap.add_argument('--cell', type=int, default=4)
    ap.add_argument('--min-area', type=int, default=4000)
    ap.add_argument('--rows', type=int, default=1)
    ap.add_argument('--margin', type=int, default=6)
    ap.add_argument('--grid', default='')
    a = ap.parse_args()
    im = Image.open(a.sheet).convert('RGBA')
    if a.grid:
        cols, rows = (int(v) for v in a.grid.lower().split('x'))
        cw, ch = im.width / cols, im.height / rows
        boxes = [(int(c * cw), int(r * ch), int((c + 1) * cw), int((r + 1) * ch)) for r in range(rows) for c in range(cols)]
        a.margin = 0
    else:
        boxes = order(regions(im.getchannel('A'), a.cell, a.grow, a.min_area), a.rows)
    for i, (x0, y0, x1, y1) in enumerate(boxes):
        crop = im.crop((max(0, x0 - a.margin), max(0, y0 - a.margin), min(im.width, x1 + a.margin), min(im.height, y1 + a.margin)))
        if a.grid:
            # Keep the main figure; drop slivers of the neighbouring pose at the cell edges.
            parts = regions(crop.getchannel('A'), a.cell, a.grow, 0)
            if parts:
                main_box = max(parts, key=lambda r: (r[2] - r[0]) * (r[3] - r[1]))
                keep = Image.new('L', crop.size, 0)
                keep.paste(255, main_box)
                crop.putalpha(Image.composite(crop.getchannel('A'), Image.new('L', crop.size, 0), keep))
        bb = crop.getchannel('A').point(lambda v: 255 if v > 8 else 0).getbbox()
        if bb:
            crop = crop.crop(bb)
        crop.save('%s_%d.png' % (a.prefix, i))
        print('%s_%d.png' % (a.prefix, i), crop.size)


if __name__ == '__main__':
    main()
