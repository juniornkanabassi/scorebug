#!/usr/bin/env python3
"""Validate hand-measured reference rectangles and emit an enlarged, annotated PIL crop."""
import argparse
import json
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont, ImageStat


def parse_box(value):
    name, values = value.split("=", 1) if "=" in value else ("box", value)
    box = [int(v) for v in values.split(",")]
    if len(box) != 4 or min(box[2:]) <= 0:
        raise argparse.ArgumentTypeError("box wants x,y,width,height with positive size")
    return name, box


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("image")
    parser.add_argument("--box", required=True, type=parse_box, help="x,y,width,height")
    parser.add_argument("--element", action="append", type=parse_box, default=[], help="name=x,y,width,height")
    parser.add_argument("--out", required=True, help="annotated crop PNG")
    args = parser.parse_args()
    im = Image.open(args.image).convert("RGB")
    boxes = [args.box, *args.element]
    draw = ImageDraw.Draw(im)
    font = ImageFont.load_default()
    output = {"image": str(Path(args.image).resolve()), "size": list(im.size), "boxes": {}}
    for name, (x, y, w, h) in boxes:
        if x < 0 or y < 0 or x + w > im.width or y + h > im.height:
            parser.error(f"{name} rectangle is outside {im.width}x{im.height}")
        roi = im.crop((x, y, x + w, y + h))
        output["boxes"][name] = {"xywh": [x, y, w, h], "medianRGB": [round(v, 1) for v in ImageStat.Stat(roi).median]}
        colour = (255, 0, 255) if name == "box" else (0, 255, 255)
        draw.rectangle((x, y, x + w - 1, y + h - 1), outline=colour, width=1)
        draw.text((x + 2, max(0, y - 10)), name, fill=colour, font=font)
    # Nearest-neighbour keeps the one-pixel measurement borders inspectable.
    bounds = boxes[0][1]
    x, y, w, h = bounds
    crop = im.crop((x, y, x + w, y + h)).resize((w * 3, h * 3), Image.Resampling.NEAREST)
    Path(args.out).parent.mkdir(parents=True, exist_ok=True)
    crop.save(args.out)
    output["annotatedCrop"] = str(Path(args.out).resolve())
    print(json.dumps(output, indent=2))


if __name__ == "__main__":
    main()
