"""Combine test screenshots into one downscaled grid image for quick visual QA.
usage: python tools/contact_sheet.py out.png cols width shot1 shot2 ...   (names without .png, from _test_output/)"""
import sys
from PIL import Image, ImageDraw
out, cols, width = sys.argv[1], int(sys.argv[2]), int(sys.argv[3])
names = sys.argv[4:]
imgs = []
for n in names:
    try:
        imgs.append((n, Image.open(f"_test_output/{n}.png").convert("RGB")))
    except Exception as e:
        print("missing", n)
if not imgs:
    sys.exit(1)
w = width // cols
h = int(w * imgs[0][1].height / imgs[0][1].width)
rows = (len(imgs) + cols - 1) // cols
sheet = Image.new("RGB", (w * cols, (h + 16) * rows), (20, 20, 24))
d = ImageDraw.Draw(sheet)
for i, (n, im) in enumerate(imgs):
    x, y = (i % cols) * w, (i // cols) * (h + 16)
    sheet.paste(im.resize((w, h), Image.LANCZOS), (x, y + 16))
    d.text((x + 4, y + 2), n, fill=(230, 230, 230))
sheet.save(out)
print("sheet", out, sheet.size)
