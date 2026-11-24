"""Build the Camiva app icon and notification icon from the white logo.

    python tool/build_brand_icons.py

Produces:
    assets/brand/app_icon.png          1024 square, gradient + logo (stores, iOS)
    assets/brand/icon_background.png   the gradient alone (Android adaptive)
    assets/brand/icon_foreground.png   logo on transparent (Android adaptive)
    android/.../drawable-*/ic_stat_camiva.png   white silhouette for the
                                                notification status bar

Then run `dart run flutter_launcher_icons` to install the launcher icons.

WHY GENERATED RATHER THAN DRAWN BY HAND
-------------------------------------------------------------------------------
Three sizes of the same mark have to agree, and Android's adaptive icon crops
the foreground to a circle or squircle depending on the launcher. Deriving them
all from one source with explicit padding is the only way the mark keeps the
same visual weight everywhere.

THE TWO PADDINGS ARE DIFFERENT ON PURPOSE
-------------------------------------------------------------------------------
* The square icon fills 78% of the canvas: it is never masked, so the mark can
  be big.
* The adaptive foreground is drawn at 76%, and flutter_launcher_icons insets it
  by a further 16% on each side. Android only ever shows the middle two thirds
  of an adaptive icon, and a round launcher mask cuts the corners off that, so
  the mark has to stay well inside — a wide logo hits the circle sideways long
  before a square one would.
"""

from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
LOGO = ROOT / "assets" / "brand" / "logo_white.png"
BRAND = ROOT / "assets" / "brand"
RES = ROOT / "android" / "app" / "src" / "main" / "res"

# Sampled from the supplied icon: a deep blue that lifts towards a lighter
# sky blue across the diagonal.
GRADIENT_FROM = (1, 48, 219)     # deep blue, top-left
GRADIENT_TO = (45, 184, 253)     # light blue, bottom-right

SQUARE = 1024
LOGO_FRACTION_SQUARE = 0.78
# flutter_launcher_icons wraps the foreground in a 16% inset of its own, so the
# visible width is roughly this fraction x 0.63. The mark is wide rather than
# square, so it runs out of room sideways first: at 0.90 the tail of the M was
# already being shaved off by round launcher masks. 0.76 keeps it inside the
# circle with a little air, and it still reads large.
LOGO_FRACTION_ADAPTIVE = 0.76

# Android notification icon densities, in pixels.
NOTIFICATION_SIZES = {
    "drawable-mdpi": 24,
    "drawable-hdpi": 36,
    "drawable-xhdpi": 48,
    "drawable-xxhdpi": 72,
    "drawable-xxxhdpi": 96,
}


def diagonal_gradient(size: int) -> Image.Image:
    """A smooth corner-to-corner gradient.

    Interpolating along (x + y) rather than a single axis is what makes the
    light fall across the diagonal, matching the supplied artwork.
    """
    image = Image.new("RGB", (size, size))
    pixels = image.load()
    span = (size - 1) * 2
    for y in range(size):
        for x in range(size):
            t = (x + y) / span
            pixels[x, y] = tuple(
                round(GRADIENT_FROM[i] + (GRADIENT_TO[i] - GRADIENT_FROM[i]) * t)
                for i in range(3)
            )
    return image


def fitted_logo(canvas: int, fraction: float) -> Image.Image:
    """The logo scaled to `fraction` of `canvas`, centred on transparency."""
    logo = Image.open(LOGO).convert("RGBA")

    # Trim transparent margins first, so the padding below is measured from the
    # mark itself rather than from whatever whitespace the export carried.
    bbox = logo.getbbox()
    if bbox:
        logo = logo.crop(bbox)

    target = int(canvas * fraction)
    scale = min(target / logo.width, target / logo.height)
    logo = logo.resize(
        (max(1, round(logo.width * scale)), max(1, round(logo.height * scale))),
        Image.LANCZOS,
    )

    layer = Image.new("RGBA", (canvas, canvas), (0, 0, 0, 0))
    layer.paste(
        logo,
        ((canvas - logo.width) // 2, (canvas - logo.height) // 2),
        logo,
    )
    return layer


def build_square_icon() -> Path:
    background = diagonal_gradient(SQUARE).convert("RGBA")
    background.alpha_composite(fitted_logo(SQUARE, LOGO_FRACTION_SQUARE))
    target = BRAND / "app_icon.png"
    background.save(target)
    return target


def build_adaptive_background() -> Path:
    """The gradient on its own, as the adaptive icon's back layer.

    A flat colour would have been simpler, but then the home-screen icon would
    not match the one on the store listing and on iOS. Android crops this layer
    to the viewport, and a corner-to-corner gradient survives that crop without
    losing its direction.
    """
    target = BRAND / "icon_background.png"
    diagonal_gradient(SQUARE).save(target)
    return target


def build_adaptive_foreground() -> Path:
    target = BRAND / "icon_foreground.png"
    fitted_logo(SQUARE, LOGO_FRACTION_ADAPTIVE).save(target)
    return target


def build_notification_icons() -> list[Path]:
    """A white silhouette on transparency.

    Android draws the status-bar icon using only the alpha channel, so colour is
    discarded — anything not fully transparent becomes solid white. Feeding it
    the coloured logo would produce a white blob; the mark has to carry its
    shape in its alpha.
    """
    written = []
    for folder, size in NOTIFICATION_SIZES.items():
        # A little tighter than the launcher icon: the status bar is small and
        # the system adds its own breathing room.
        icon = fitted_logo(size * 2, 0.86).resize((size, size), Image.LANCZOS)

        # Force every visible pixel to white, keeping the alpha shape.
        white = Image.new("RGBA", icon.size, (255, 255, 255, 0))
        white.putalpha(icon.getchannel("A"))

        directory = RES / folder
        directory.mkdir(parents=True, exist_ok=True)
        target = directory / "ic_stat_camiva.png"
        white.save(target)
        written.append(target)
    return written


def main() -> None:
    if not LOGO.exists():
        raise SystemExit(f"Missing source logo: {LOGO}")

    print(build_square_icon().relative_to(ROOT))
    print(build_adaptive_background().relative_to(ROOT))
    print(build_adaptive_foreground().relative_to(ROOT))
    for path in build_notification_icons():
        print(path.relative_to(ROOT))


if __name__ == "__main__":
    main()
