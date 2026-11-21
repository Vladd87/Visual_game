"""Build a labelled grid image (contact sheet) from a list of images.

Usage:
  python3 -I contact_sheet.py <out.jpg> <cols> <cell_px> <image>[=<label>] ...

Each cell letterboxes the image into a square-ish cell (aspect 4:3) on a dark
background and prints the label underneath. Labels default to the file name.
"""
import os
import sys

from PIL import Image, ImageDraw, ImageFont


def load_font(size):
    for path in (
        "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",
        "/usr/share/fonts/truetype/liberation/LiberationSans-Regular.ttf",
    ):
        if os.path.exists(path):
            return ImageFont.truetype(path, size)
    return ImageFont.load_default()


def main():
    out, cols, cell = sys.argv[1], int(sys.argv[2]), int(sys.argv[3])
    items = []
    for arg in sys.argv[4:]:
        path, _, label = arg.partition("=")
        items.append((path, label or os.path.basename(path)))
    cw, ch = cell, int(cell * 3 / 4)
    label_h = max(14, cell // 18)
    font = load_font(label_h - 3)
    rows = (len(items) + cols - 1) // cols
    pad = 6
    sheet = Image.new(
        "RGB",
        (cols * (cw + pad) + pad, rows * (ch + label_h + pad) + pad),
        (18, 18, 20),
    )
    draw = ImageDraw.Draw(sheet)
    for n, (path, label) in enumerate(items):
        r, c = divmod(n, cols)
        x0 = pad + c * (cw + pad)
        y0 = pad + r * (ch + label_h + pad)
        try:
            im = Image.open(path).convert("RGB")
        except Exception as e:  # noqa: BLE001
            draw.text((x0 + 4, y0 + 4), f"unreadable: {e}"[:60], fill=(255, 80, 80), font=font)
            continue
        im.thumbnail((cw, ch), Image.LANCZOS)
        sheet.paste(im, (x0 + (cw - im.width) // 2, y0 + (ch - im.height) // 2))
        # Fit the label to the cell width so it never runs into a neighbour.
        text = label[:80]
        while text and draw.textlength(text, font=font) > cw - 4:
            text = text[:-1]
        if text != label[:80]:
            text = text[:-1] + "…"
        draw.text((x0 + 2, y0 + ch + 1), text, fill=(220, 220, 220), font=font)
    sheet.save(out, quality=90)
    print(f"{out}: {len(items)} images, {sheet.width}x{sheet.height}")


if __name__ == "__main__":
    main()
