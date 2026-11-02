"""Builds the oak leaf-cluster atlas (models/trees/oak_leaves.png, RGBA, 1024 x 1024, 2 x 2 clusters).

Each cluster is a sprig seen from the side: brown twigs with 20-30 lobed oak leaves. The leaf colour and veins are taken from
the photo leaves of ambientCG LeafSet009 (CC0), the outline is a drawn oak-leaf silhouette (rounded lobes). Leaves at the back
are darker (fake self-shadowing), so a card reads as a little volume, not a flat sticker.

    python3 tools/trees/make_leaf_atlas.py <LeafSet009 dir> <out png>
"""
import math
import random
import sys

from PIL import Image, ImageDraw, ImageFilter

SIZE = 1024
CELL = SIZE // 2
LEAF_L = 150            # leaf sprite length in pixels (inside a 512 cell)
TWIG = (78, 60, 44)
SEED = 4
LEAF_CENTRES = [(x, y) for x in (340, 1010, 1680) for y in (560, 1530)]   # the six photo leaves of LeafSet009 (2K)


def oak_mask(w, h, rng):
    """Lobed oak-leaf silhouette (white on black), tip up."""
    lobes = rng.choice([4, 5, 5, 6])
    pts_l, pts_r = [], []
    n = 90
    for i in range(n + 1):
        t = i / n                                    # 0 = stalk end, 1 = tip
        env = math.sin(math.pi * min(1.0, t * 1.08)) ** 0.8 * (0.55 + 0.45 * t)   # widest near the top third
        lobe = 0.62 + 0.38 * abs(math.cos(math.pi * lobes * t))
        half = 0.5 * w * env * lobe
        y = h * (1.0 - t)
        pts_l.append((w * 0.5 - half, y))
        pts_r.append((w * 0.5 + half, y))
    m = Image.new("L", (w, h + 8), 0)
    d = ImageDraw.Draw(m)
    d.polygon(pts_l + pts_r[::-1], fill=255)
    d.line([(w * 0.5, h), (w * 0.5, h + 8)], fill=255, width=3)          # the stalk
    return m.filter(ImageFilter.GaussianBlur(0.6))


def leaf_sprite(src, rng):
    w = int(LEAF_L * rng.uniform(0.5, 0.62))
    h = LEAF_L
    mask = oak_mask(w, h, rng)
    # a random crop of the photo leaves (the middle of a leaf: veins, no edge) as the colour
    cx, cy = rng.choice(LEAF_CENTRES)
    sx = cx - 110 + rng.randint(-40, 40)
    sy = cy - 160 + rng.randint(-60, 60)
    col = src.crop((sx, sy, sx + 220, sy + 320)).resize(mask.size).convert("RGB")
    col = col.rotate(rng.uniform(-10, 10), resample=Image.BILINEAR)
    # summer green: pull the yellow-green photo towards a fuller green
    r, g, b = col.split()
    r = r.point(lambda v: int(v * 0.62))
    g = g.point(lambda v: int(v * 0.86))
    b = b.point(lambda v: int(v * 0.55))
    col = Image.merge("RGB", (r, g, b))
    d = ImageDraw.Draw(col)
    d.line([(w * 0.5, h + 8), (w * 0.5, h * 0.2)], fill=(118, 140, 66), width=1)    # midrib
    leaf = Image.new("RGBA", mask.size)
    leaf.paste(col, (0, 0))
    leaf.putalpha(mask)
    return leaf


def shade(img, k):
    r, g, b, a = img.split()
    f = lambda v: int(min(255, v * k))
    return Image.merge("RGBA", (r.point(f), g.point(f), b.point(f), a))


def cluster(src, rng):
    cell = Image.new("RGBA", (CELL, CELL), (0, 0, 0, 0))
    d = ImageDraw.Draw(cell)
    # twig: from the bottom middle up and out, with 3-4 side shoots
    base = (CELL * 0.5 + rng.uniform(-20, 20), CELL - 4)
    tip = (CELL * 0.5 + rng.uniform(-60, 60), CELL * 0.18)
    stems = [(base, tip, 7)]
    for i in range(rng.randint(3, 4)):
        t = rng.uniform(0.25, 0.75)
        p = (base[0] + (tip[0] - base[0]) * t, base[1] + (tip[1] - base[1]) * t)
        side = -1 if i % 2 == 0 else 1
        q = (p[0] + side * rng.uniform(110, 190), p[1] - rng.uniform(40, 120))
        stems.append((p, q, 4))
    for a, b, wdt in stems:
        d.line([a, b], fill=TWIG + (255,), width=wdt)
    # leaves along the stems, back ones first (darker), then front ones
    spots = []
    for a, b, wdt in stems:
        k = 9 if wdt > 5 else 6
        for j in range(k):
            t = 0.2 + 0.8 * (j + rng.random() * 0.6) / k
            spots.append((a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t, math.atan2(b[1] - a[1], b[0] - a[0])))
    rng.shuffle(spots)
    n = len(spots)
    for i, (x, y, ang) in enumerate(spots):
        depth = i / max(1, n - 1)                  # 0 = back, 1 = front
        leaf = leaf_sprite(src, rng)
        s = rng.uniform(0.7, 1.05)
        leaf = leaf.resize((int(leaf.width * s), int(leaf.height * s)), Image.BILINEAR)
        rot = -math.degrees(ang) - 90 + rng.choice([-1, 1]) * rng.uniform(25, 75)
        leaf = leaf.rotate(rot, resample=Image.BICUBIC, expand=True)
        leaf = shade(leaf, 0.55 + 0.55 * depth * rng.uniform(0.85, 1.1))
        cell.alpha_composite(leaf, (int(x - leaf.width * 0.5), int(y - leaf.height * 0.5)))
    return cell


def main():
    src_dir, out = sys.argv[1], sys.argv[2]
    src = Image.open(f"{src_dir}/LeafSet009_2K-PNG_Color.png").convert("RGB")
    rng = random.Random(SEED)
    atlas = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    for i in range(4):
        atlas.alpha_composite(cluster(src, rng), ((i % 2) * CELL, (i // 2) * CELL))
    # bleed the colour into the transparent pixels so mipmaps do not get dark fringes
    rgb = atlas.convert("RGB")
    a = atlas.split()[3]
    bleed = rgb.filter(ImageFilter.GaussianBlur(6))
    filled = Image.composite(rgb, bleed, a.point(lambda v: 255 if v > 8 else 0))
    filled.putalpha(a)
    filled.save(out)


if __name__ == "__main__":
    main()
