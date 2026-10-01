#!/usr/bin/env python3
"""Build the title-screen "shader puppet" assets for the two cast members.

For each hero this writes, into godot/assets/title_live2d/ (deliberately not under assets/runtime_web/:
tools/web/configure_runtime_web_imports.py pins every PNG import there to lossy WebP, which would
destroy the masks and the premultiplied alpha; these imports stay lossless):
  <id>_hero.png    premultiplied RGBA of the standing illustration (lossless import, mipmaps)
  <id>_mask_a.png  half-resolution RGBA: R/G/B hair chains A/B/C, A face-parallax profile
  <id>_mask_b.png  half-resolution RGBA: R cloth sway, B emissive crystals, A gold / silver trim (glint)
  chr001_lantern.png  the hanging lantern mace (chain and lantern) cut out as its own layer. The
                   shader swings it rigidly about the grip and draws it over the hero image, from
                   which it was removed. A displacement field cannot do this: the gap to the cape
                   is 3 px, far less than the swing.
  title_live2d_manifest.json  source hashes, sizes and the rig numbers the masks were cut for

The masks are painted from hand placed polygons (source pixel coordinates of the
authority art) intersected with colour rules, then softened. Nothing here changes the
artwork itself except: premultiplying alpha, and completing CHR002's sword point, which the
authority image clips at its right border.

Usage:  python tools/art/build_title_live2d.py [--debug DIR]
Needs numpy, Pillow and scipy.
"""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw
from scipy import ndimage as ndi

ROOT = Path(__file__).resolve().parents[2]
GODOT = ROOT / "godot"
OUT_DIR = GODOT / "assets/title_live2d"

SOURCES = {
    "chr001": ROOT / "data_source/art_source/card_8head_green_matte_r2/CHR001/chr001_8head_r7_chatgpt_fresh_exact_rgba.png",
    "chr002": GODOT / "assets/art/characters/CHR002/CHR002_PORTRAIT_R1.png",
}

# ----------------------------------------------------------------------------------------------
# hand placed regions (source pixels of the authority art)
# ----------------------------------------------------------------------------------------------
CHR001 = {
    # right ponytail incl. the strands that fall behind the pauldron
    "A": [(548, 24), (610, 24), (690, 55), (748, 104), (776, 160), (786, 215), (776, 262), (766, 302), (746, 342), (692, 324), (644, 314), (628, 352), (658, 408), (674, 470), (672, 548), (622, 552), (592, 490), (580, 420), (576, 330), (568, 262), (564, 190), (552, 100)],
    # long loose hair on the viewer's left
    "B": [(268, 440), (278, 380), (310, 330), (350, 302), (392, 270), (412, 215), (428, 150), (440, 95), (458, 88), (464, 140), (462, 210), (452, 270), (428, 292), (416, 340), (412, 420), (402, 500), (330, 520), (285, 490)],
    # bangs, hair cap and the lock beside the right cheek
    "C": [(470, 96), (590, 96), (606, 170), (626, 262), (638, 340), (642, 456), (606, 466), (588, 400), (574, 330), (568, 262), (560, 200), (520, 196), (478, 190)],
    # face (yaw / pitch parallax of the features)
    "F": [(468, 150), (506, 134), (532, 140), (554, 160), (566, 188), (562, 216), (546, 238), (520, 250), (494, 244), (474, 226), (460, 200), (458, 172)],
    # centre tabard with its white panels, and the translucent cape left of the left leg
    "T": [(398, 622), (548, 622), (548, 1060), (522, 1112), (470, 1142), (428, 1100), (418, 1030), (418, 840), (400, 700)],
    "CL": [(376, 646), (318, 866), (301, 999), (306, 1094), (352, 1096), (366, 1040), (364, 760), (380, 700)],
}

CHR002 = {
    # side ponytail with its two ribbons: swings from the clip beside the head
    "A": [(420, 150), (335, 168), (250, 200), (170, 240), (110, 300), (62, 380), (30, 470), (20, 560), (34, 640), (120, 668), (150, 640), (130, 590), (122, 540), (140, 490), (175, 440), (215, 415), (262, 392), (300, 350), (340, 310), (385, 285), (410, 250), (424, 210)],
    "C": [(432, 100), (520, 82), (600, 100), (655, 160), (665, 230), (645, 300), (612, 320), (585, 290), (560, 262), (530, 238), (470, 235), (446, 215), (436, 160)],
    "F": [(470, 262), (500, 240), (545, 242), (570, 262), (590, 292), (588, 325), (560, 345), (520, 345), (490, 318)],
}


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1 << 20), b""):
            digest.update(chunk)
    return digest.hexdigest()


def smoothstep(a, b, x):
    t = np.clip((x - a) / (b - a), 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)


def rgb_to_hsv(rgb):
    r, g, b = rgb[..., 0], rgb[..., 1], rgb[..., 2]
    mx = rgb.max(axis=-1)
    mn = rgb.min(axis=-1)
    d = mx - mn
    nz = d > 1e-6
    safe = np.where(nz, d, 1.0)
    rc, gc, bc = (mx - r) / safe, (mx - g) / safe, (mx - b) / safe
    h = np.where(mx == r, bc - gc, np.where(mx == g, 2.0 + rc - bc, 4.0 + gc - rc))
    h = np.where(nz, (h / 6.0) % 1.0, 0.0) * 360.0
    s = np.where(mx > 1e-6, d / np.where(mx > 1e-6, mx, 1.0), 0.0)
    return h, s, mx


def poly_mask(shape, polys):
    height, width = shape
    img = Image.new("L", (width, height), 0)
    draw = ImageDraw.Draw(img)
    for poly in polys:
        draw.polygon([(float(x), float(y)) for x, y in poly], fill=255)
    return np.asarray(img, dtype=np.float32) / 255.0


def soften(mask, close_px=5, dilate_px=2, sigma=2.4):
    solid = ndi.binary_closing(mask > 0.4, structure=np.ones((close_px, close_px)))
    solid = ndi.binary_dilation(solid, iterations=dilate_px)
    return np.clip(ndi.gaussian_filter(solid.astype(np.float32), sigma), 0.0, 1.0)


# The lantern mace hangs from the grip on a chain. It is cut out of the hero image as its own layer
# (everything connected to LANTERN_SEED below LANTERN_TOP) and the shader rotates it about the grip.
# Rows LANTERN_TOP..LANTERN_BASE_CUT exist in both layers and are cross-faded, so the cut through
# the ring and the first links cannot show.
LANTERN_SEED = (220, 1000)      # x, y: a pixel of the lantern glass
LANTERN_TOP = 722
LANTERN_BASE_CUT = 740
LANTERN_MARGIN = 12
LANTERN_PIVOT = (240.0, 725.0)


def split_lantern(img):
    """Return (hero without the lantern, lantern layer, (x0, y0, w, h)); straight alpha, float 0..1."""
    alpha = img[..., 3]
    support = alpha > 0.02
    below = support.copy()
    below[:LANTERN_TOP] = False
    labels, _count = ndi.label(below, structure=np.ones((3, 3), int))
    seed = labels[LANTERN_SEED[1], LANTERN_SEED[0]]
    if seed == 0:
        raise SystemExit("lantern seed pixel is transparent: the source art changed, re-measure LANTERN_SEED")
    comp = labels == seed
    other = support & ~comp
    # faint fringe pixels (0 < alpha <= 0.02) go with whichever side they touch
    d_comp = ndi.distance_transform_edt(~comp)
    d_other = ndi.distance_transform_edt(~other)
    fringe = (alpha > 0.0) & ~support
    owner = comp | (fringe & (d_comp < d_other) & (d_comp <= 3.0))
    owner[:LANTERN_TOP] = False
    removed = owner.copy()
    removed[:LANTERN_BASE_CUT] = False
    base = np.where(removed[..., None], 0.0, img).astype(np.float32)
    ys, xs = np.where(owner)
    height, width = alpha.shape
    x0 = max(int(xs.min()) - LANTERN_MARGIN, 0)
    y0 = max(int(ys.min()) - LANTERN_MARGIN, 0)
    x1 = min(int(xs.max()) + 1 + LANTERN_MARGIN, width)
    y1 = min(int(ys.max()) + 1 + LANTERN_MARGIN, height)
    layer = np.where(owner[..., None], img, 0.0).astype(np.float32)[y0:y1, x0:x1]
    # tightest gap to the art that stays behind (information for the log only)
    gap = float(d_comp[other & (np.arange(height)[:, None] >= LANTERN_BASE_CUT)].min())
    print(f"  lantern layer {x1 - x0}x{y1 - y0} at ({x0}, {y0}), {int(owner.sum())} px, closest static art {gap:.1f} px")
    return base, layer, (x0, y0, x1 - x0, y1 - y0)


def channel(poly, rule, alpha_ok, shape):
    inside = poly_mask(shape, [poly])
    out = soften(inside * rule)
    grown = ndi.gaussian_filter(inside, 3.0)
    return np.clip(out * grown, 0.0, 1.0) * alpha_ok


def half(mask):
    """Half resolution copy (box average), as float 0..1."""
    h, w = mask.shape
    h2, w2 = h // 2, w // 2
    return mask[: h2 * 2, : w2 * 2].reshape(h2, 2, w2, 2).mean(axis=(1, 3))


def to_u8(x):
    return np.clip(np.rint(x * 255.0), 0, 255).astype(np.uint8)


def complete_sword_point(img):
    """CHR002's blade runs off the right border of the authority image. Widen the canvas and
    close the point along the two edges that were converging (measured on the border)."""
    pad = 24
    h, w = img.shape[:2]
    wide = np.zeros((h, w + pad, 4), np.float32)
    wide[:, :w] = img
    alpha = img[..., 3]
    rows = np.where(alpha[:, w - 1] > 0.5)[0]
    if rows.size == 0:
        return wide
    top, bottom = int(rows.min()), int(rows.max())
    # edge slopes from the last 14 columns
    def edge(col, which):
        r = np.where(alpha[:, col] > 0.5)[0]
        return r.min() if which == "top" else r.max()
    cols = np.arange(w - 14, w - 1)
    top_slope = np.polyfit(cols, [edge(c, "top") for c in cols], 1)[0]
    bottom_slope = np.polyfit(cols, [edge(c, "bottom") for c in cols], 1)[0]
    # the two edges meet where top(x) == bottom(x)
    x_tip = (w - 1) + (bottom - top) / max(top_slope - bottom_slope, 1e-3)
    x_tip = min(x_tip, w - 1 + pad - 1)
    y_tip = bottom + bottom_slope * (x_tip - (w - 1))
    base = img[top:bottom + 1, w - 4:w - 1, :3].reshape(-1, 3)
    base_a = img[top:bottom + 1, w - 4:w - 1, 3].reshape(-1)
    colour = (base * base_a[:, None]).sum(axis=0) / max(base_a.sum(), 1e-3)
    # rasterise the missing triangle 4x supersampled
    ss = 4
    tri = Image.new("L", ((pad + 1) * ss, (bottom - top + 12) * ss), 0)
    ox, oy = w - 1, top - 4
    pts = [((0.0) * ss, (top - oy) * ss), ((x_tip - ox) * ss, (y_tip - oy) * ss), ((0.0) * ss, (bottom + 1 - oy) * ss)]
    ImageDraw.Draw(tri).polygon(pts, fill=255)
    cov = np.asarray(tri.resize((pad + 1, bottom - top + 12), Image.BOX), dtype=np.float32) / 255.0
    region = wide[oy:oy + cov.shape[0], ox:ox + cov.shape[1]]
    region[..., :3] = np.where(cov[..., None] > region[..., 3:4], colour, region[..., :3])
    region[..., 3] = np.maximum(region[..., 3], cov)
    return wide


def premultiply(img):
    out = img.copy()
    out[..., :3] *= out[..., 3:4]
    return out


def build_chr001(img, dbg):
    height, width = img.shape[:2]
    shape = (height, width)
    rgb, alpha = img[..., :3], img[..., 3]
    hue, sat, val = rgb_to_hsv(rgb)
    solid = (alpha > 0.35).astype(np.float32)
    near_solid = (ndi.maximum_filter(solid, 5) > 0).astype(np.float32)
    teal = ((hue > 165) & (hue < 208)).astype(np.float32)
    hair_rule = teal * smoothstep(0.30, 0.45, sat) * (1.0 - smoothstep(0.62, 0.78, val)) * solid
    gold = ((hue > 28) & (hue < 62)).astype(np.float32) * smoothstep(0.30, 0.50, sat) * smoothstep(0.40, 0.60, val)
    skin = ((hue > 5) & (hue < 32)).astype(np.float32) * smoothstep(0.18, 0.35, sat) * smoothstep(0.55, 0.75, val)
    black = 1.0 - smoothstep(0.10, 0.22, val)

    hair_a = channel(CHR001["A"], hair_rule, near_solid, shape)
    hair_b = channel(CHR001["B"], hair_rule, near_solid, shape)
    hair_c = channel(CHR001["C"], hair_rule, near_solid, shape)
    face = ndi.gaussian_filter(poly_mask(shape, [CHR001["F"]]), 5.0)

    yy = np.arange(height, dtype=np.float32)[:, None] * np.ones((1, width), np.float32)
    cloth = poly_mask(shape, [CHR001["T"], CHR001["CL"]]) * solid * (1.0 - np.maximum(black, skin))
    cloth = ndi.gaussian_filter(cloth, 3.0) * smoothstep(640.0, 1120.0, yy)
    spare = np.zeros(shape, np.float32)
    cyan =((hue > 160) & (hue < 205)).astype(np.float32)
    emissive = ndi.gaussian_filter(cyan * smoothstep(0.42, 0.62, sat) * smoothstep(0.52, 0.80, val) * solid, 1.2)
    trim = ndi.gaussian_filter(gold * solid, 1.0)

    if dbg:
        dbg("chr001_hair", np.stack([hair_a, hair_b, hair_c], -1))
        dbg("chr001_parts", np.stack([cloth, spare, emissive], -1))
        dbg("chr001_trim_face", np.stack([trim, trim, face], -1))
    return (hair_a, hair_b, hair_c, face), (cloth, spare, emissive, trim)


def build_chr002(img, dbg):
    height, width = img.shape[:2]
    shape = (height, width)
    rgb, alpha = img[..., :3], img[..., 3]
    hue, sat, val = rgb_to_hsv(rgb)
    solid = (alpha > 0.35).astype(np.float32)
    near_solid = (ndi.maximum_filter(solid, 5) > 0).astype(np.float32)
    red = (((hue < 28) | (hue > 340))).astype(np.float32) * smoothstep(0.40, 0.55, sat) * smoothstep(0.40, 0.60, val) * solid
    yy = np.arange(height, dtype=np.float32)[:, None] * np.ones((1, width), np.float32)

    hair_a = channel(CHR002["A"], solid, near_solid, shape)
    hair_b = np.zeros(shape, np.float32)
    hair_c = channel(CHR002["C"], red, near_solid, shape)
    face = ndi.gaussian_filter(poly_mask(shape, [CHR002["F"]]), 5.0)

    # red gems on the armour (below the head) and the clip beside the head
    gem_zone = np.clip(smoothstep(330.0, 360.0, yy) + poly_mask(shape, [[(380, 70), (450, 70), (450, 215), (380, 215)]]), 0.0, 1.0)
    gems = ndi.gaussian_filter(((hue < 14) | (hue > 350)).astype(np.float32) * smoothstep(0.62, 0.78, sat) * smoothstep(0.55, 0.78, val) * solid * gem_zone * (1.0 - hair_c), 1.2)
    # silver trim: neutral light metal
    silver = (1.0 - smoothstep(0.10, 0.22, sat)) * smoothstep(0.50, 0.75, val) * solid * gem_zone
    silver = ndi.gaussian_filter(silver, 1.0)
    zero = np.zeros(shape, np.float32)
    if dbg:
        dbg("chr002_hair", np.stack([hair_a, hair_b, hair_c], -1))
        dbg("chr002_parts", np.stack([zero, zero, gems], -1))
        dbg("chr002_trim_face", np.stack([silver, silver, face], -1))
    return (hair_a, hair_b, hair_c, face), (zero, zero, gems, silver)


def write_rgba(path: Path, planes, scale_half: bool):
    stack = np.stack([half(p) if scale_half else p for p in planes], axis=-1)
    Image.fromarray(to_u8(stack), "RGBA").save(path, optimize=True)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--debug", type=Path, default=None, help="folder for mask overlay images")
    args = parser.parse_args()
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    manifest = {"schema": 1, "tool": "tools/art/build_title_live2d.py", "heroes": {}}

    for hero, source in SOURCES.items():
        img = np.asarray(Image.open(source).convert("RGBA"), dtype=np.float32) / 255.0
        if hero == "chr002":
            img = complete_sword_point(img)
        height, width = img.shape[:2]

        def dbg(name, rgbm, _img=img):
            if args.debug is None:
                return
            args.debug.mkdir(parents=True, exist_ok=True)
            base = _img[..., :3] * _img[..., 3:4] + np.array([0.12, 0.15, 0.19]) * (1 - _img[..., 3:4])
            out = np.clip(base * 0.55 + rgbm * 0.85, 0, 1)
            Image.fromarray(to_u8(out)).resize((width // 2, height // 2), Image.LANCZOS).save(args.debug / (name + ".png"))

        if hero == "chr001":
            a_planes, b_planes = build_chr001(img, dbg)
        else:
            a_planes, b_planes = build_chr002(img, dbg)

        lantern = None
        hero_img = img
        if hero == "chr001":
            hero_img, lantern_img, lantern_rect = split_lantern(img)
            lantern_path = OUT_DIR / "chr001_lantern.png"
            Image.fromarray(to_u8(premultiply(lantern_img)), "RGBA").save(lantern_path, optimize=True)
            lantern = {"file": lantern_path.name, "rect": list(lantern_rect), "pivot": list(LANTERN_PIVOT),
                       "seam": [LANTERN_TOP, LANTERN_BASE_CUT], "sha256": sha256(lantern_path)}
        hero_path = OUT_DIR / f"{hero}_hero.png"
        Image.fromarray(to_u8(premultiply(hero_img)), "RGBA").save(hero_path, optimize=True)
        write_rgba(OUT_DIR / f"{hero}_mask_a.png", a_planes, True)
        write_rgba(OUT_DIR / f"{hero}_mask_b.png", b_planes, True)
        manifest["heroes"][hero] = {
            "source": str(source.relative_to(ROOT)).replace("\\", "/"),
            "source_sha256": sha256(source),
            "size": [width, height],
            "mask_size": [width // 2, height // 2],
            "hero_sha256": sha256(hero_path),
        }
        if lantern is not None:
            manifest["heroes"][hero]["lantern"] = lantern
        print(f"{hero}: {width}x{height} -> {hero_path.name}")

    (OUT_DIR / "title_live2d_manifest.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()
