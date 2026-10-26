"""Export the approved SVG artwork. Requires Playwright and Pillow only for regeneration.

The exported PNGs are committed; Xcode does not need Python or a browser to build.
Run this script from any directory with: python3 ios/Design/export-approved-assets.py
"""
from pathlib import Path
import json
from PIL import Image
from playwright.sync_api import sync_playwright

design = Path(__file__).resolve().parent
approved = design / "approved"
assets = design.parent / "Earmark" / "Assets.xcassets"
manifest = json.loads((approved / "manifest.json").read_text())
with sync_playwright() as playwright:
    browser = playwright.chromium.launch()
    page = browser.new_page(device_scale_factor=1)
    for item in manifest:
        width = item.get("width", item.get("size", 256))
        height = item.get("height", item.get("size", 256))
        page.set_viewport_size({"width": width, "height": height})
        page.goto((approved / item["source"]).as_uri())
        page.wait_for_function("Array.from(document.images).every(image => image.complete)")
        name = item["name"]
        folder = assets / (name + (".appiconset" if name == "AppIcon" else ".imageset"))
        folder.mkdir(exist_ok=True)
        destination = folder / (name + ".png")
        page.locator("svg").first.screenshot(path=str(destination), omit_background=True)
        if name == "AppIcon":
            with Image.open(destination) as image:
                image.convert("RGB").save(destination)
        else:
            (folder / "Contents.json").write_text(json.dumps({
                "images": [{"filename": name + ".png", "idiom": "universal"}],
                "info": {"author": "xcode", "version": 1}
            }, indent=2))
    browser.close()

# The fixed strips use the same white-bordered round gem as the sticker sheet.
with Image.open(assets / "Gem_round_pink.imageset/Gem_round_pink.png") as image:
    image.save(assets / "RoundRhinestone.imageset/RoundRhinestone.png")
print(f"Exported {len(manifest)} native assets.")
