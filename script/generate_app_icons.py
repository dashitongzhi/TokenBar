#!/usr/bin/env python3
from __future__ import annotations

from pathlib import Path

try:
    import cairosvg
except ImportError as exc:
    raise SystemExit("Missing cairosvg. Install it or use the committed PNG assets.") from exc


ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "script" / "assets" / "tokenbar-app-icon.svg"
APPICONSET = ROOT / "TokenBar" / "Assets.xcassets" / "AppIcon.appiconset"
DEFAULT_IMAGESET = ROOT / "TokenBar" / "Assets.xcassets" / "AppIconDefault.imageset"

MAC_ICON_SIZES = {
    "icon_16x16.png": 16,
    "icon_16x16@2x.png": 32,
    "icon_32x32.png": 32,
    "icon_32x32@2x.png": 64,
    "icon_128x128.png": 128,
    "icon_128x128@2x.png": 256,
    "icon_256x256.png": 256,
    "icon_256x256@2x.png": 512,
    "icon_512x512.png": 512,
    "icon_512x512@2x.png": 1024,
}


def render_png(target: Path, size: int) -> None:
    cairosvg.svg2png(
        url=str(SOURCE),
        write_to=str(target),
        output_width=size,
        output_height=size,
    )


def main() -> None:
    if not SOURCE.exists():
        raise SystemExit(f"Missing source SVG: {SOURCE}")

    for filename, size in MAC_ICON_SIZES.items():
        render_png(APPICONSET / filename, size)

    render_png(DEFAULT_IMAGESET / "AppIconDefault.png", 1024)
    print(f"Generated {len(MAC_ICON_SIZES) + 1} icon PNGs from {SOURCE.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
