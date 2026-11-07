#!/usr/bin/env python3
"""Builds the app's branding files from the original artwork.

Originals (any size, square) live in design/branding/ and are NOT bundled in
the app. This writes the 1024 px versions the app and flutter_launcher_icons
use to assets/branding/, and the Android notification icon (white silhouette)
to android/app/src/main/res/drawable-*/ic_notification.png.

Needs Pillow:  python3 -m pip install Pillow
Run from the repo root:  python3 tools/prepare_branding.py
Then:  dart run flutter_launcher_icons
"""
from pathlib import Path

from PIL import Image, ImageChops

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "design" / "branding"
OUT = ROOT / "assets" / "branding"
RES = ROOT / "android" / "app" / "src" / "main" / "res"

LOGO = SRC / "logo-woops.png"  # the ant, transparent
APP_ICON = SRC / "app-icon-woops.png"  # the ant on the hearts background
HEARTS = SRC / "app-icon-foreground-woops.png"  # the hearts background only
NOTIFICATION = SRC / "notification-icon.png"  # any colour: only its shape is used

SIZE = 1024
# Android status-bar icon sizes (24 dp) per screen density.
NOTIFICATION_SIZES = {"mdpi": 24, "hdpi": 36, "xhdpi": 48, "xxhdpi": 72, "xxxhdpi": 96}


def load(path: Path, size: int = SIZE) -> Image.Image:
    return Image.open(path).convert("RGBA").resize((size, size), Image.LANCZOS)


def flatten(img: Image.Image, colour=(255, 255, 255)) -> Image.Image:
    """Removes transparency (Apple rejects app icons with an alpha channel)."""
    base = Image.new("RGBA", img.size, colour + (255,))
    return Image.alpha_composite(base, img).convert("RGB")


def fade_cut_edges(img: Image.Image, share: float = 0.28) -> Image.Image:
    """Softly fades the artwork wherever it runs into the image border, so a
    figure cut off by the canvas looks like it's peeking in, not chopped."""
    w, h = img.size
    alpha = img.getchannel("A")
    touches = {
        "left": any(alpha.getpixel((0, y)) for y in range(h)),
        "right": any(alpha.getpixel((w - 1, y)) for y in range(h)),
        "top": any(alpha.getpixel((x, 0)) for x in range(w)),
        "bottom": any(alpha.getpixel((x, h - 1)) for x in range(w)),
    }
    if not any(touches.values()):
        return img
    span_x, span_y = int(w * share), int(h * share)
    mask = Image.new("L", img.size, 255)
    px = mask.load()
    for y in range(h):
        for x in range(w):
            f = 1.0
            if touches["left"] and x < span_x:
                f = min(f, x / span_x)
            if touches["right"] and x > w - 1 - span_x:
                f = min(f, (w - 1 - x) / span_x)
            if touches["top"] and y < span_y:
                f = min(f, y / span_y)
            if touches["bottom"] and y > h - 1 - span_y:
                f = min(f, (h - 1 - y) / span_y)
            # Ease out, so the fade starts gently.
            px[x, y] = int(255 * (f * f * (3 - 2 * f)))
    out = img.copy()
    out.putalpha(ImageChops.multiply(alpha, mask))
    return out


def silhouette(img: Image.Image) -> Image.Image:
    """White shape on transparent: what Android uses for small and themed icons."""
    white = Image.new("RGBA", img.size, (255, 255, 255, 0))
    white.putalpha(img.getchannel("A"))
    return white


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    logo = load(LOGO)
    # In the app the logo stands alone, so cut-off edges fade out; the icon
    # foreground keeps them (the icon's mask hides the canvas edges).
    fade_cut_edges(logo).save(OUT / "logo.png", optimize=True)
    logo.save(OUT / "app_icon_foreground.png", optimize=True)
    flatten(load(APP_ICON)).save(OUT / "app_icon.png", optimize=True)
    flatten(load(HEARTS)).save(OUT / "app_icon_background.png", optimize=True)
    silhouette(logo).save(OUT / "app_icon_monochrome.png", optimize=True)

    shape = silhouette(Image.open(NOTIFICATION).convert("RGBA"))
    for density, px in NOTIFICATION_SIZES.items():
        folder = RES / f"drawable-{density}"
        folder.mkdir(parents=True, exist_ok=True)
        shape.resize((px, px), Image.LANCZOS).save(folder / "ic_notification.png", optimize=True)
    print("Branding files written.")


if __name__ == "__main__":
    main()
