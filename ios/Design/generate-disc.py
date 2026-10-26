"""Reproduce the HTML conic disc once for the header and the centered app icon.
Run with Python, Pillow, and NumPy; generated PNGs are included in the app.
"""
from pathlib import Path
import json
import numpy as np
from PIL import Image, ImageDraw

root = Path(__file__).resolve().parents[1] / "Earmark/Assets.xcassets"
n = 1536
y, x = np.mgrid[0:n, 0:n].astype(float)
x -= n / 2; y -= n / 2
r = np.hypot(x, y) / n
angle = ((np.arctan2(x, -y) * 180 / np.pi - 25) % 360) / 360
stops = [0, .15, .27, .35, .45, .53, .68, .82, 1]
colors = ["d3d8d0", "fafff8", "b1bab3", "e6cbdc", "c1d8d8", "fafff4", "9aa69e", "d6ded4", "d3d8d0"]
rgb = np.array([[int(c[i:i+2], 16) for i in (0,2,4)] for c in colors])
a = np.zeros((n,n,4), dtype=np.uint8)
for c in range(3): a[:,:,c] = np.interp(angle, stops, rgb[:,c])
# HTML header: 62px disc, 3px pink border, 18px hub, 3px dotted
# trim. Use a 72px canvas so the complete 68px trim has breathing room.
unit = 1 / 72
a[:,:,3] = np.where(r <= 31 * unit, 255, 0)
im = Image.fromarray(a)
draw = ImageDraw.Draw(im)
def circle(radius, fill=None, outline=None, width=1):
    center = n/2; radius *= n
    draw.ellipse((center-radius,center-radius,center+radius,center+radius), fill=fill, outline=outline, width=width)
circle(33 * unit, outline="#8a8e89", width=round(n * 2 * unit))
circle(31 * unit, outline="#d7b1c4", width=round(n * 3 * unit))
circle(28 * unit, outline="#f6fff1", width=round(n * 2 * unit))
# The HTML's dotted pink-white rim, spaced evenly and fully inside the canvas.
for t in np.linspace(0, 2*np.pi, 34, endpoint=False):
    cx=n/2+np.sin(t)*n*32.5*unit; cy=n/2-np.cos(t)*n*32.5*unit; dot=n*1.5*unit
    draw.ellipse((cx-dot,cy-dot+2,cx+dot,cy+dot+2), fill="#975875")
    draw.ellipse((cx-dot,cy-dot,cx+dot,cy+dot), fill="#fff2f7")
# Broad concentric hub, matching the HTML radial center.
circle(9 * unit, fill="#c4cec2", outline="#9ba59a", width=round(n * unit))
circle(9 * unit * np.sqrt(2) * .42, fill="#8b978e")
circle(9 * unit * np.sqrt(2) * .35, fill="#e5ebe0")
circle(9 * unit * np.sqrt(2) * .20, fill="#778378")
im=im.resize((1024,1024), Image.Resampling.LANCZOS)
asset=root/"Disc.imageset"; asset.mkdir(exist_ok=True)
im.save(asset/"Disc.png")
(asset/"Contents.json").write_text(json.dumps({"images":[{"filename":"Disc.png","idiom":"universal"}],"info":{"author":"xcode","version":1}},indent=2))
icon=Image.new("RGB",(1024,1024),"#f3eee9")
icon.paste(im,(0,0),im)
icon.save(root/"AppIcon.appiconset/AppIcon.png")
