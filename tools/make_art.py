"""
Renders the Amity Toolkit artwork with Pillow:

  Media/Icon.tga             64x64 in-game icon (TOC IconTexture)
  curseforge/logo.png        400x400 CurseForge project avatar
  curseforge/logo-1024.png   1024x1024 high-res avatar
  Media/MinimapIcon.tga      64x64 round minimap button icon
  curseforge/icon-256.png    256x256 preview of the in-game icon
  curseforge/banner.png      1600x400 header for the project description

Usage:  python tools/make_art.py
Everything is drawn at a higher resolution and downscaled for anti-aliasing.
"""

import math
import os

from PIL import Image, ImageChops, ImageDraw, ImageFilter, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FONTS = os.path.join(os.environ.get("WINDIR", r"C:\Windows"), "Fonts")

# Palette
NIGHT = (13, 14, 34)
NIGHT_2 = (22, 18, 52)
VIOLET = (92, 62, 196)
VIOLET_DEEP = (42, 26, 98)
GOLD_LIGHT = (255, 232, 160)
GOLD = (242, 193, 78)
GOLD_DARK = (176, 112, 30)
TEAL_LIGHT = (180, 255, 240)
TEAL = (63, 224, 197)
TEAL_DARK = (16, 120, 120)
OUTLINE = (20, 12, 44)


# --------------------------------------------------------------------------
# helpers
# --------------------------------------------------------------------------

def lerp(a, b, t):
    return tuple(int(round(a[i] + (b[i] - a[i]) * t)) for i in range(len(a)))


def vertical_gradient(size, stops):
    """stops: list of (t, rgb) sorted by t."""
    w, h = size
    col = Image.new("RGB", (1, h))
    px = col.load()
    for y in range(h):
        t = y / max(h - 1, 1)
        for i in range(len(stops) - 1):
            t0, c0 = stops[i]
            t1, c1 = stops[i + 1]
            if t0 <= t <= t1:
                px[0, y] = lerp(c0, c1, (t - t0) / max(t1 - t0, 1e-6))
                break
    return col.resize((w, h))


def radial_gradient(size, center, radius, inner, outer):
    w, h = size
    # distance field via a small image upscaled (fast enough, smooth)
    small = 256
    g = Image.new("L", (small, small))
    px = g.load()
    cx, cy = center[0] / w * small, center[1] / h * small
    r = radius / max(w, h) * small
    for y in range(small):
        for x in range(small):
            d = math.hypot(x - cx, (y - cy) * w / h) / r
            px[x, y] = int(max(0.0, min(1.0, d)) * 255)
    g = g.resize((w, h), Image.BICUBIC)
    a = Image.new("RGB", (w, h), inner)
    b = Image.new("RGB", (w, h), outer)
    return Image.composite(b, a, g)


def poly(size, points, scale):
    m = Image.new("L", size, 0)
    ImageDraw.Draw(m).polygon([(x * scale, y * scale) for x, y in points], fill=255)
    return m


def dilate(mask, px):
    px = max(3, int(px) | 1)
    return mask.filter(ImageFilter.MaxFilter(px))


def glow(mask, radius, color, strength=1.0):
    blurred = mask.filter(ImageFilter.GaussianBlur(radius))
    if strength != 1.0:
        blurred = blurred.point(lambda v: min(255, int(v * strength)))
    layer = Image.new("RGBA", mask.size, color + (0,))
    layer.putalpha(blurred)
    return layer


def fill(mask, rgb_image):
    layer = rgb_image.convert("RGBA")
    layer.putalpha(mask)
    return layer


def hexagon(cx, cy, r):
    return [(cx + r * math.cos(math.radians(a)), cy + r * math.sin(math.radians(a)))
            for a in range(-90, 270, 60)]


def star4(cx, cy, r, thin=0.22):
    pts = []
    for i in range(8):
        a = math.radians(-90 + i * 45)
        rr = r if i % 2 == 0 else r * thin
        pts.append((cx + rr * math.cos(a), cy + rr * math.sin(a)))
    return pts


# --------------------------------------------------------------------------
# the monogram: a gold "A" whose crossbar is a teal gem
# --------------------------------------------------------------------------

# unit coordinates (0..1) inside the monogram box
A_SHAPE = [(0.50, 0.12), (0.83, 0.86), (0.67, 0.86), (0.50, 0.44), (0.33, 0.86), (0.17, 0.86)]
A_BAR = [(0.33, 0.625), (0.67, 0.625), (0.69, 0.675), (0.31, 0.675)]
A_FEET = [  # small flared feet
    [(0.12, 0.86), (0.38, 0.86), (0.38, 0.90), (0.12, 0.90)],
    [(0.62, 0.86), (0.88, 0.86), (0.88, 0.90), (0.62, 0.90)],
]
GEM = [(0.50, 0.535), (0.585, 0.65), (0.50, 0.765), (0.415, 0.65)]


def draw_monogram(canvas, box, outline_px):
    """Composite the monogram onto canvas (RGBA) inside box=(x, y, size)."""
    x0, y0, s = box
    size = canvas.size

    def at(points):
        return [(x0 + x * s, y0 + y * s) for x, y in points]

    letter = poly(size, at(A_SHAPE), 1)
    letter = ImageChops.lighter(letter, poly(size, at(A_BAR), 1))
    for foot in A_FEET:
        letter = ImageChops.lighter(letter, poly(size, at(foot), 1))
    gem = poly(size, at(GEM), 1)

    # soft teal aura behind everything
    canvas.alpha_composite(glow(ImageChops.lighter(letter, gem), s * 0.06, TEAL, 0.9))

    # dark outline
    outline = dilate(ImageChops.lighter(letter, gem), outline_px)
    canvas.alpha_composite(fill(outline, Image.new("RGB", size, OUTLINE)))

    # gold body with a vertical gradient and a light top bevel
    gold = vertical_gradient(size, [(0, GOLD_LIGHT), (y0 / size[1] + 0.45 * s / size[1], GOLD),
                                    (1, GOLD_DARK)])
    canvas.alpha_composite(fill(letter, gold))
    # bevel: the left half of each leg slightly brighter
    left_half = Image.new("L", size, 0)
    ImageDraw.Draw(left_half).rectangle([0, 0, x0 + 0.5 * s, size[1]], fill=60)
    shine = ImageChops.multiply(letter, left_half.point(lambda v: 255 if v else 0))
    canvas.alpha_composite(fill(shine.point(lambda v: v * 50 // 255), Image.new("RGB", size, (255, 255, 255))))

    # gem: outline, teal gradient, highlight facet
    canvas.alpha_composite(fill(dilate(gem, outline_px * 1.4), Image.new("RGB", size, OUTLINE)))
    canvas.alpha_composite(glow(gem, s * 0.035, TEAL_LIGHT, 1.6))
    teal = vertical_gradient(size, [(0, TEAL_LIGHT), ((y0 + 0.62 * s) / size[1], TEAL), (1, TEAL_DARK)])
    canvas.alpha_composite(fill(gem, teal))
    facet = poly(size, at([(0.50, 0.555), (0.555, 0.63), (0.50, 0.65), (0.445, 0.63)]), 1)
    canvas.alpha_composite(fill(facet.point(lambda v: v * 150 // 255), Image.new("RGB", size, (255, 255, 255))))


def sparkle(canvas, cx, cy, r, color=TEAL_LIGHT, alpha=230):
    m = poly(canvas.size, star4(cx, cy, r), 1)
    canvas.alpha_composite(glow(m, r * 0.6, color, 1.2))
    canvas.alpha_composite(fill(m.point(lambda v: v * alpha // 255), Image.new("RGB", canvas.size, (255, 255, 255))))


# --------------------------------------------------------------------------
# compositions
# --------------------------------------------------------------------------

def make_logo(final=1024, background=True):
    S = final * 2
    size = (S, S)
    img = Image.new("RGBA", size)
    if background:
        img.alpha_composite(radial_gradient(size, (S / 2, S * 0.42), S * 0.75, NIGHT_2, NIGHT).convert("RGBA"))

    # faint rune ring
    ring = Image.new("L", size, 0)
    d = ImageDraw.Draw(ring)
    d.ellipse([S * 0.06, S * 0.06, S * 0.94, S * 0.94], outline=40, width=int(S * 0.004))
    d.ellipse([S * 0.09, S * 0.09, S * 0.91, S * 0.91], outline=22, width=int(S * 0.002))
    img.alpha_composite(fill(ring, Image.new("RGB", size, TEAL)))

    # hexagon crest: gold rim + violet core
    cx, cy, r = S / 2, S / 2, S * 0.43
    outer = poly(size, hexagon(cx, cy, r), 1)
    rim_in = poly(size, hexagon(cx, cy, r * 0.93), 1)
    core = poly(size, hexagon(cx, cy, r * 0.90), 1)
    img.alpha_composite(glow(outer, S * 0.03, VIOLET, 0.8))
    img.alpha_composite(fill(dilate(outer, S * 0.012), Image.new("RGB", size, OUTLINE)))
    img.alpha_composite(fill(outer, vertical_gradient(size, [(0, GOLD_LIGHT), (0.5, GOLD), (1, GOLD_DARK)])))
    img.alpha_composite(fill(rim_in, Image.new("RGB", size, OUTLINE)))
    img.alpha_composite(fill(core, radial_gradient(size, (cx, cy * 0.8), r * 1.1, VIOLET, VIOLET_DEEP)))

    m = S * 0.66
    draw_monogram(img, (cx - m / 2, cy - m / 2 + S * 0.01, m), S * 0.016)

    sparkle(img, S * 0.27, S * 0.30, S * 0.035)
    sparkle(img, S * 0.75, S * 0.70, S * 0.025)
    sparkle(img, S * 0.71, S * 0.27, S * 0.018)
    return img.resize((final, final), Image.LANCZOS)


def make_icon(final=64):
    S = 512
    size = (S, S)
    img = Image.new("RGBA", size)
    img.alpha_composite(radial_gradient(size, (S / 2, S * 0.38), S * 0.8, VIOLET, VIOLET_DEEP).convert("RGBA"))
    draw_monogram(img, (S * 0.02, S * 0.03, S * 0.96), S * 0.03)
    sparkle(img, S * 0.22, S * 0.24, S * 0.06)
    # WoW-style bevel border
    d = ImageDraw.Draw(img)
    d.rectangle([0, 0, S - 1, S - 1], outline=OUTLINE + (255,), width=int(S * 0.035))
    d.rectangle([S * 0.035, S * 0.035, S * 0.965, S * 0.965], outline=GOLD_DARK + (200,), width=int(S * 0.012))
    return img.resize((final, final), Image.LANCZOS)


def make_minimap_icon(final=64):
    """Round icon; the minimap button's tracking border is drawn over it in game."""
    S = 512
    size = (S, S)
    img = Image.new("RGBA", size)
    disc = Image.new("L", size, 0)
    ImageDraw.Draw(disc).ellipse([0, 0, S - 1, S - 1], fill=255)
    img.alpha_composite(fill(disc, radial_gradient(size, (S / 2, S * 0.38), S * 0.6, VIOLET, VIOLET_DEEP)))
    draw_monogram(img, (S * 0.12, S * 0.10, S * 0.76), S * 0.03)
    return img.resize((final, final), Image.LANCZOS)


def font(name, px):
    return ImageFont.truetype(os.path.join(FONTS, name), px)


def text_mask(size, xy, text, fnt, tracking=0):
    m = Image.new("L", size, 0)
    d = ImageDraw.Draw(m)
    x, y = xy
    for ch in text:
        d.text((x, y), ch, font=fnt, fill=255)
        x += fnt.getlength(ch) + tracking
    return m


def text_width(text, fnt, tracking=0):
    return sum(fnt.getlength(c) for c in text) + tracking * (len(text) - 1)


def make_banner(final=(1600, 400)):
    k = 2
    W, H = final[0] * k, final[1] * k
    size = (W, H)
    img = Image.new("RGBA", size)
    img.alpha_composite(radial_gradient(size, (W * 0.2, H * 0.5), W * 0.7, NIGHT_2, NIGHT).convert("RGBA"))

    # diagonal violet light streak
    streak = Image.new("L", size, 0)
    ImageDraw.Draw(streak).polygon([(W * 0.35, 0), (W * 0.55, 0), (W * 0.40, H), (W * 0.20, H)], fill=40)
    img.alpha_composite(fill(streak.filter(ImageFilter.GaussianBlur(H * 0.15)), Image.new("RGB", size, VIOLET)))

    # emblem on the left
    logo = make_logo(final=int(H * 0.86), background=False)
    img.alpha_composite(logo, (int(H * 0.10), int(H * 0.07)))

    # wordmark
    tx = int(H * 1.08)
    word = font("georgiab.ttf", int(H * 0.36))
    wm = text_mask(size, (tx, int(H * 0.13)), "AMITY", word, tracking=int(H * 0.035))
    img.alpha_composite(glow(wm, H * 0.03, TEAL, 0.5))
    img.alpha_composite(fill(dilate(wm, H * 0.014), Image.new("RGB", size, OUTLINE)))
    img.alpha_composite(fill(wm, vertical_gradient(size, [(0, GOLD_LIGHT), (0.35, GOLD), (0.6, GOLD_DARK), (1, GOLD_DARK)])))

    # "TOOLKIT" in teal, bottom-aligned with the wordmark
    sub = font("segoeuib.ttf", int(H * 0.13))
    sx = tx + text_width("AMITY", word, int(H * 0.035)) + int(H * 0.06)
    sm = text_mask(size, (sx, int(H * 0.32)), "TOOLKIT", sub, tracking=int(H * 0.02))
    img.alpha_composite(glow(sm, H * 0.02, TEAL, 0.6))
    img.alpha_composite(fill(sm, vertical_gradient(size, [(0, TEAL_LIGHT), (1, TEAL)])))

    # tagline
    tag = font("segoeui.ttf", int(H * 0.085))
    chips = Image.new("RGBA", size, (0, 0, 0, 0))
    d = ImageDraw.Draw(chips)
    d.text((tx + int(H * 0.01), int(H * 0.58)), "Small quality-of-life tweaks for WoW Forever", font=tag,
           fill=(200, 196, 235, 255))

    # module chips
    chip_font = font("segoeuib.ttf", int(H * 0.06))
    x = tx + int(H * 0.01)
    y = int(H * 0.76)
    for label in ("Bar Text", "Auction iLvl", "LFG Role Filter", "Overpower Alert"):
        w = int(chip_font.getlength(label)) + int(H * 0.08)
        h = int(H * 0.11)
        d.rounded_rectangle([x, y, x + w, y + h], radius=h // 2, fill=(63, 224, 197, 34),
                            outline=TEAL + (200,), width=max(2, int(H * 0.005)))
        d.text((x + w / 2, y + h / 2), label, font=chip_font, fill=TEAL_LIGHT + (255,), anchor="mm")
        x += w + int(H * 0.035)
    img.alpha_composite(chips)

    sparkle(img, W * 0.93, H * 0.2, H * 0.04)
    sparkle(img, W * 0.97, H * 0.42, H * 0.022)
    return img.resize(final, Image.LANCZOS)


def main():
    out_cf = os.path.join(ROOT, "curseforge")
    out_media = os.path.join(ROOT, "Media")
    os.makedirs(out_cf, exist_ok=True)
    os.makedirs(out_media, exist_ok=True)

    logo = make_logo(1024)
    logo.convert("RGB").save(os.path.join(out_cf, "logo-1024.png"))
    logo.resize((400, 400), Image.LANCZOS).convert("RGB").save(os.path.join(out_cf, "logo.png"))

    icon = make_icon(64)
    icon.save(os.path.join(out_media, "Icon.tga"))  # 32-bit uncompressed TGA, power-of-two size
    make_minimap_icon(64).save(os.path.join(out_media, "MinimapIcon.tga"))
    make_icon(256).save(os.path.join(out_cf, "icon-256.png"))

    make_banner().convert("RGB").save(os.path.join(out_cf, "banner.png"))
    print("art written to", out_cf, "and", out_media)


if __name__ == "__main__":
    main()
