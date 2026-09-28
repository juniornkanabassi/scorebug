#!/usr/bin/env python3
"""PIL measurement helper for the comparison runner; boxes are xywh in reference pixels."""
import json
import math
import sys
from pathlib import Path
from PIL import Image, ImageChops, ImageDraw, ImageFont, ImageOps, ImageStat


def lab(rgb):
    r, g, b = [v / 255 for v in rgb]
    rgb = [v / 12.92 if v <= .04045 else ((v + .055) / 1.055) ** 2.4 for v in (r, g, b)]
    x = (rgb[0] * .4124 + rgb[1] * .3576 + rgb[2] * .1805) / .95047
    y = (rgb[0] * .2126 + rgb[1] * .7152 + rgb[2] * .0722)
    z = (rgb[0] * .0193 + rgb[1] * .1192 + rgb[2] * .9505) / 1.08883
    f = lambda v: v ** (1 / 3) if v > .008856 else 7.787 * v + 16 / 116
    fx, fy, fz = f(x), f(y), f(z)
    return (116 * fy - 16, 500 * (fx - fy), 200 * (fy - fz))


def plate_rgb(im, expected=None):
    if expected:
        target = tuple(int(expected[i:i + 2], 16) for i in (1, 3, 5))
        pixels = list(im.convert("RGB").getdata())
        plate = [p for p in pixels if sum((p[i] - target[i]) ** 2 for i in range(3)) <= 55 ** 2]
        if plate:
            return tuple(round(sum(p[i] for p in plate) / len(plate)) for i in range(3))
    # Four thin interior corner strips avoid centred glyphs and crests. Their mean also works for
    # gradients, where choosing one modal pixel would compare different stops in the two crops.
    w, h = im.size
    x, y = max(1, round(w * .08)), max(1, round(h * .08))
    patches = [im.crop((x, y, max(x + 1, round(w * .3)), max(y + 1, round(h * .17)))),
               im.crop((round(w * .7), y, max(round(w * .7) + 1, w - x), max(y + 1, round(h * .17)))),
               im.crop((x, round(h * .83), max(x + 1, round(w * .3)), max(round(h * .83) + 1, h - y))),
               im.crop((round(w * .7), round(h * .83), max(round(w * .7) + 1, w - x), max(round(h * .83) + 1, h - y)))]
    sample = Image.new("RGB", (sum(p.width for p in patches), max(p.height for p in patches)))
    offset = 0
    for patch in patches:
        sample.paste(patch, (offset, 0))
        offset += patch.width
    return tuple(round(v) for v in ImageStat.Stat(sample).mean)


def rect(box):
    x, y, w, h = box
    return (int(round(x)), int(round(y)), int(round(x + w)), int(round(y + h)))


def crop(im, box):
    return im.crop(rect(box))


def masked_rmse(a, b, ca, cb):
    # Pixels unlike either corner sample (text, crests, video bleed and anti-aliased edges) are
    # excluded; compare only the shared plate fill/gradient pixels.
    size = (min(320, max(1, a.width)), min(220, max(1, a.height)))
    a = a.convert("RGB").resize(size, Image.Resampling.BILINEAR)
    b = b.convert("RGB").resize(size, Image.Resampling.BILINEAR)
    da, db = list(a.getdata()), list(b.getdata())
    keep, sq = 0, 0
    for p, q in zip(da, db):
        if sum((p[i] - ca[i]) ** 2 for i in range(3)) <= 45 ** 2 and sum((q[i] - cb[i]) ** 2 for i in range(3)) <= 45 ** 2:
            sq += sum((p[i] - q[i]) ** 2 for i in range(3)) / 3
            keep += 1
    return math.sqrt(sq / keep) if keep else None


def main(spec_path):
    s = json.loads(Path(spec_path).read_text())
    ref = Image.open(s["reference"]).convert("RGBA")
    raw = Image.open(s["capture"]).convert("RGBA").resize((s["canvas"][0], s["canvas"][1]), Image.Resampling.LANCZOS)
    alpha = raw.getchannel("A").point(lambda v: 255 if v > 8 else 0)
    source = alpha.getbbox()
    box = s.get("bugBox")
    has_box = bool(box and box[2] > 0 and box[3] > 0)
    expected_visible = s.get("expectedVisible", True)
    visible = bool(source)
    scale, dx, dy = 1.0, 0.0, 0.0
    aligned = Image.new("RGBA", s["canvas"], (0, 0, 0, 0))
    if has_box and source and expected_visible:
        anchor_name = s.get("anchor")
        reference_anchor = s.get("anchorBox") or (s.get("elements", {}).get(anchor_name) if anchor_name else None)
        capture_anchor = s.get("captureBoxes", {}).get(anchor_name) if anchor_name else None
        if not reference_anchor or not capture_anchor or capture_anchor[2] <= 0:
            raise ValueError(f"missing fixed-element anchor ({anchor_name})")
        ax, ay, aw, ah = reference_anchor
        sx, sy, sw, sh = capture_anchor
        scale = aw / sw
        dx, dy = ax - sx * scale, ay - sy * scale
        size = (max(1, round(raw.width * scale)), max(1, round(raw.height * scale)))
        scaled = raw.resize(size, Image.Resampling.LANCZOS)
        aligned.alpha_composite(scaled, (round(dx), round(dy)))

    target = rect(box) if has_box else (0, 0, ref.width, ref.height)
    ref_crop = ref.crop(target)
    ours_crop = aligned.crop(target)
    # The reference's video is retained as the underlay, so an identical broadcast frame stays visible
    # behind our transparent overlay. Video/crests/names are still excluded from plate metrics below.
    ours_panel = Image.alpha_composite(ref_crop, ours_crop)
    diff = ImageChops.difference(ref_crop.convert("RGB"), ours_panel.convert("RGB"))
    diff = ImageOps.autocontrast(diff.convert("L")).convert("RGB")
    diff = Image.blend(Image.new("RGB", diff.size, (20, 20, 20)), diff, .85)
    over = Image.blend(ref_crop.convert("RGB"), ours_panel.convert("RGB"), .5)
    font = ImageFont.load_default()
    pad, label_h = 8, 22
    w, h = ref_crop.size
    panel = Image.new("RGB", (w * 4 + pad * 5, h + label_h + pad * 2), (28, 28, 28))
    draw = ImageDraw.Draw(panel)
    labels = [("reference", ref_crop.convert("RGB")), ("ours / reference underlay", ours_panel.convert("RGB")), ("difference", diff), ("50% overlay", over)]
    for i, (label, image) in enumerate(labels):
        x = pad + i * (w + pad)
        draw.text((x, pad), label, fill="white", font=font)
        panel.paste(image, (x, label_h + pad))
    Path(s["preview"]).parent.mkdir(parents=True, exist_ok=True)
    panel.save(s["preview"])

    results = {}
    for name, ref_box in s.get("elements", {}).items():
        if not ref_box or len(ref_box) != 4 or ref_box[2] <= 0 or ref_box[3] <= 0:
            continue
        got = s.get("captureBoxes", {}).get(name)
        threshold = s.get("thresholds", {}).get(name, s.get("thresholds", {}).get("default", {}))
        item = {"referenceBox": ref_box, "thresholds": threshold}
        if got and visible and expected_visible:
            gx, gy, gw, gh = got
            got = [gx * scale + dx, gy * scale + dy, gw * scale, gh * scale]
            rx, ry, rw, rh = ref_box
            gx, gy, gw, gh = got
            edges = {"left": round(gx - rx, 2), "top": round(gy - ry, 2),
                     "right": round(gx + gw - rx - rw, 2), "bottom": round(gy + gh - ry - rh, 2)}
            item["edgeOffsets"] = edges
            item["sizeRatio"] = {"width": round(gw / rw, 4), "height": round(gh / rh, 4)}
            tx, ty, _, _ = box if has_box else (0, 0, ref.width, ref.height)
            a = crop(ref, ref_box).convert("RGB")
            b = crop(ours_panel, [ref_box[0] - tx, ref_box[1] - ty, ref_box[2], ref_box[3]]).convert("RGB")
            # Sample the central 70% of a plate, limiting text and diagonal boundaries.
            expected = s.get("expectedColours", {}).get(name)
            ma, mb = plate_rgb(a, expected), plate_rgb(b, expected)
            la, lb = lab(ma), lab(mb)
            de = math.sqrt(sum((la[i] - lb[i]) ** 2 for i in range(3)))
            rmse = masked_rmse(a, b, ma, mb)
            item["sampledPlateRGB"] = {"reference": list(ma), "ours": list(mb)}
            item["deltaE76"] = round(de, 2)
            item["maskedRMSE"] = round(rmse, 2) if rmse is not None else None
            geometry_ok = max(abs(x) for x in edges.values()) <= threshold.get("geometryPx", 2)
            color_ok = not threshold.get("scoreColor", True) or de <= threshold.get("deltaE", 6)
            rmse_ok = not threshold.get("scoreRMSE", True) or (rmse is not None and rmse <= threshold.get("maskedRMSE", 24))
            item["status"] = "PASS" if geometry_ok and color_ok and rmse_ok else "FAIL"
        else:
            item["status"] = "PASS" if not expected_visible and not visible else "FAIL"
            item["note"] = "Reference state is hidden" if not expected_visible and not visible else "Expected visible element has no measurable DOM box" if visible else "No visible capture pixels"
        results[name] = item

    output = {"id": s["id"], "visible": visible, "sourceBox": list(source) if source else None,
              "anchor": {"name": s.get("anchor"), "referenceBox": s.get("anchorBox") or s.get("elements", {}).get(s.get("anchor")), "captureBox": s.get("captureBoxes", {}).get(s.get("anchor"))},
              "targetBox": box, "scale": round(scale, 5), "offset": [round(dx, 2), round(dy, 2)],
              "sourceSize": [raw.width, raw.height], "referenceSize": list(ref.size), "elements": results,
              "preview": s["preview"]}
    print(json.dumps(output))


if __name__ == "__main__":
    try:
        main(sys.argv[1])
    except Exception as e:
        print(f"compare-image: {e}", file=sys.stderr)
        raise
