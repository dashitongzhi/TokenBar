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
ASSET_ROOT = ROOT / "TokenBar" / "Assets.xcassets"

VARIANT_IMAGESETS = {
    "AppIconDefault": {},
    "AppIconGlass": {
        "#092346": "#173D60",
        "#061226": "#0B223A",
        "#03101F": "#061A2C",
        "#123A5A": "#1D526D",
        "#071A2E": "#0A2740",
        "#0BA8FF": "#23B7FF",
    },
    "AppIconFrost": {
        "#092346": "#EAF8FF",
        "#061226": "#CFE8F7",
        "#03101F": "#B7D3E8",
        "#123A5A": "#0D3655",
        "#071A2E": "#08223A",
        "#103355": "#B7D3E8",
        "#4FF6FF": "#15A6D8",
        "#0BA8FF": "#087CC4",
        "#1DF293": "#16BA78",
    },
    "AppIconMidnight": {
        "#092346": "#071224",
        "#061226": "#020713",
        "#03101F": "#01040A",
        "#123A5A": "#0A263F",
        "#071A2E": "#041323",
        "#4FF6FF": "#2DEBFF",
        "#0BA8FF": "#078DFF",
        "#1DF293": "#16E58C",
    },
}

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


def variant_svg(source: str, replacements: dict[str, str]) -> str:
    svg = source
    for original, replacement in replacements.items():
        svg = svg.replace(original, replacement)
    return svg


def render_png(target: Path, size: int, svg_text: str) -> None:
    cairosvg.svg2png(
        bytestring=svg_text.encode("utf-8"),
        write_to=str(target),
        output_width=size,
        output_height=size,
    )


def main() -> None:
    if not SOURCE.exists():
        raise SystemExit(f"Missing source SVG: {SOURCE}")

    source_svg = SOURCE.read_text(encoding="utf-8")
    for filename, size in MAC_ICON_SIZES.items():
        render_png(APPICONSET / filename, size, source_svg)

    for asset_name, replacements in VARIANT_IMAGESETS.items():
        render_png(
            ASSET_ROOT / f"{asset_name}.imageset" / f"{asset_name}.png",
            1024,
            variant_svg(source_svg, replacements),
        )

    print(
        f"Generated {len(MAC_ICON_SIZES) + len(VARIANT_IMAGESETS)} icon PNGs "
        f"from {SOURCE.relative_to(ROOT)}"
    )


if __name__ == "__main__":
    main()
