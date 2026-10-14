"""Generates the Woops logo and app icons.

Requires Pillow (pip install pillow). Run from the project root:
    python3 tools/make_logo.py

Outputs:
  assets/branding/logo.png               in-app logo (transparent, 1024 px)
  assets/branding/app_icon.png           full app icon (blush background, 1024 px)
  assets/branding/app_icon_foreground.png Android adaptive-icon foreground (transparent)
"""

import math
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "assets" / "branding"
SCRIPT_FONT = ROOT / "assets" / "fonts" / "Pacifico-Regular.ttf"

SS = 4  # supersampling for smooth edges
SIZE = 1024

PINK = (255, 126, 179)
ROSE = (255, 79, 129)
CORAL = (255, 138, 122)
BLUSH_TOP = (255, 227, 238)
BLUSH_BOTTOM = (255, 242, 246)


def lerp(a, b, t):
    return tuple(round(a[i] + (b[i] - a[i]) * t) for i in range(len(a)))


def gradient(size, stops, angle_deg=135):
    """Diagonal multi-stop gradient."""
    w, h = size
    img = Image.new("RGB", size)
    px = img.load()
    a = math.radians(angle_deg)
    dx, dy = math.cos(a), math.sin(a)
    proj = [x * dx + y * dy for x, y in ((0, 0), (w, 0), (0, h), (w, h))]
    lo, hi = min(proj), max(proj)
    # Compute per-row in a fast-ish way.
    for y in range(h):
        for x in range(w):
            t = ((x * dx + y * dy) - lo) / (hi - lo)
            for i in range(len(stops) - 1):
                p0, c0 = stops[i]
                p1, c1 = stops[i + 1]
                if t <= p1:
                    px[x, y] = lerp(c0, c1, (t - p0) / (p1 - p0) if p1 > p0 else 0)
                    break
            else:
                px[x, y] = stops[-1][1]
    return img


def heart_points(cx, cy, scale, steps=720):
    """Classic parametric heart, centred on (cx, cy)."""
    pts = []
    for i in range(steps):
        t = 2 * math.pi * i / steps
        x = 16 * math.sin(t) ** 3
        y = 13 * math.cos(t) - 5 * math.cos(2 * t) - 2 * math.cos(3 * t) - math.cos(4 * t)
        pts.append((cx + x * scale, cy - y * scale))
    return pts


def heart_mask(size, cx, cy, scale):
    m = Image.new("L", size, 0)
    ImageDraw.Draw(m).polygon(heart_points(cx, cy, scale), fill=255)
    return m


def sparkle(draw, cx, cy, r, fill):
    """Four-pointed star."""
    k = r * 0.28
    pts = [(cx, cy - r), (cx + k, cy - k), (cx + r, cy), (cx + k, cy + k),
           (cx, cy + r), (cx - k, cy + k), (cx - r, cy), (cx - k, cy - k)]
    draw.polygon(pts, fill=fill)


def draw_logo(size_px, with_extras=True):
    """Transparent logo: glossy gradient heart + script W + sparkles."""
    S = size_px * SS
    canvas = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    cx, cy = S * 0.5, S * 0.52
    scale = S * 0.0265

    # Soft pink glow / shadow under the heart.
    shadow = heart_mask((S, S), cx, cy + S * 0.025, scale).filter(ImageFilter.GaussianBlur(S * 0.03))
    glow = Image.new("RGBA", (S, S), ROSE + (0,))
    glow.putalpha(shadow.point(lambda v: int(v * 0.55)))
    canvas.alpha_composite(glow)

    # Gradient heart (gradient rendered small and scaled up for speed).
    grad_small = gradient((256, 256), [(0, PINK), (0.55, ROSE), (1, CORAL)])
    grad = grad_small.resize((S, S), Image.BICUBIC).convert("RGBA")
    mask = heart_mask((S, S), cx, cy, scale)
    grad.putalpha(mask)
    canvas.alpha_composite(grad)

    # Glossy highlight on the upper-left lobe.
    hl = Image.new("L", (S, S), 0)
    ImageDraw.Draw(hl).ellipse((cx - S * 0.30, cy - S * 0.33, cx - S * 0.05, cy - S * 0.15), fill=150)
    hl = hl.filter(ImageFilter.GaussianBlur(S * 0.03))
    hl = Image.composite(hl, Image.new("L", (S, S), 0), mask)
    white = Image.new("RGBA", (S, S), (255, 255, 255, 0))
    white.putalpha(hl)
    canvas.alpha_composite(white)

    # Script "W" in white with a soft rose shadow.
    font = ImageFont.truetype(str(SCRIPT_FONT), int(S * 0.36))
    text = "W"
    bbox = ImageDraw.Draw(canvas).textbbox((0, 0), text, font=font)
    tw, th = bbox[2] - bbox[0], bbox[3] - bbox[1]
    tx, ty = cx - tw / 2 - bbox[0], cy - th / 2 - bbox[1] - S * 0.025
    tshadow = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    ImageDraw.Draw(tshadow).text((tx, ty + S * 0.012), text, font=font, fill=(160, 20, 70, 120))
    canvas.alpha_composite(tshadow.filter(ImageFilter.GaussianBlur(S * 0.008)))
    ImageDraw.Draw(canvas).text((tx, ty), text, font=font, fill=(255, 255, 255, 255))

    if with_extras:
        d = ImageDraw.Draw(canvas)
        # Little floating hearts and sparkles around the big heart.
        small = Image.new("RGBA", (S, S), (0, 0, 0, 0))
        for (hx, hy, hs, col) in [
            (0.83, 0.20, 0.0062, PINK + (255,)),
            (0.90, 0.33, 0.0036, CORAL + (230,)),
            (0.14, 0.24, 0.0040, ROSE + (210,)),
        ]:
            ImageDraw.Draw(small).polygon(heart_points(S * hx, S * hy, S * hs), fill=col)
        canvas.alpha_composite(small)
        sparkle(d, S * 0.20, S * 0.12, S * 0.035, (255, 182, 207, 255))
        sparkle(d, S * 0.76, S * 0.09, S * 0.022, (255, 210, 225, 255))
        sparkle(d, S * 0.88, S * 0.80, S * 0.028, (255, 160, 190, 255))
        sparkle(d, S * 0.63, S * 0.75, S * 0.020, (255, 255, 255, 220))  # glint on the heart

    return canvas.resize((size_px, size_px), Image.LANCZOS)


def blush_background(size_px, rounded=False):
    bg = gradient((256, 256), [(0, BLUSH_TOP), (1, BLUSH_BOTTOM)], angle_deg=90).resize(
        (size_px, size_px), Image.BICUBIC).convert("RGBA")
    if rounded:
        m = Image.new("L", (size_px, size_px), 0)
        ImageDraw.Draw(m).rounded_rectangle((0, 0, size_px, size_px), radius=size_px * 0.22, fill=255)
        bg.putalpha(m)
    return bg


def main():
    OUT.mkdir(parents=True, exist_ok=True)

    logo = draw_logo(SIZE)
    logo.save(OUT / "logo.png")

    # Full app icon (iOS/legacy Android): blush background, logo at ~86%.
    icon = blush_background(SIZE)
    inner = draw_logo(int(SIZE * 0.86))
    icon.alpha_composite(inner, ((SIZE - inner.width) // 2, (SIZE - inner.height) // 2))
    icon.convert("RGB").save(OUT / "app_icon.png")  # iOS icons must not be transparent

    # Android adaptive foreground: logo inside the 66% safe zone, no extras near edges.
    fg = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    inner = draw_logo(int(SIZE * 0.62), with_extras=False)
    fg.alpha_composite(inner, ((SIZE - inner.width) // 2, (SIZE - inner.height) // 2))
    fg.save(OUT / "app_icon_foreground.png")

    print("Wrote:", *(p.name for p in sorted(OUT.glob("*.png"))))


if __name__ == "__main__":
    main()
