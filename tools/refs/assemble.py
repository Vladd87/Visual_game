"""Copy the chosen reference photos into references/ and build the contact sheet.

Reads a TSV (selection.tsv) with columns:
  key  src_path  out_name  label
Images are re-encoded (JPEG q=92, EXIF/GPS stripped, size unchanged) so the
repo carries no photographer location metadata.

Usage: python3 -I assemble.py <selection.tsv> <references_dir>
"""
import csv
import os
import subprocess
import sys

from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))


def main():
    sel, out = sys.argv[1], sys.argv[2]
    os.makedirs(out, exist_ok=True)
    sheet_args = []
    with open(sel, newline="") as f:
        for row in csv.reader(f, delimiter="\t"):
            if not row or row[0].startswith("#"):
                continue
            key, src, name, label = row
            im = Image.open(src).convert("RGB")
            if max(im.size) < 1600:
                raise SystemExit(f"{key}: {im.size} is below the 1600 px floor")
            dst = os.path.join(out, name)
            im.save(dst, quality=92, optimize=True)
            print(f"{name}: {im.size[0]}x{im.size[1]}")
            sheet_args.append(f"{dst}={label}")
    subprocess.run(
        [sys.executable, "-I", os.path.join(HERE, "contact_sheet.py"),
         os.path.join(out, "contact_sheet.jpg"), "4", "560"] + sheet_args,
        check=True,
    )


if __name__ == "__main__":
    main()
