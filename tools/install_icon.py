from PIL import Image
import os

RES = "android/app/src/main/res"
legacy = {"mdpi": 48, "hdpi": 72, "xhdpi": 96, "xxhdpi": 144, "xxxhdpi": 192}
adaptive = {"mdpi": 108, "hdpi": 162, "xhdpi": 216, "xxhdpi": 324, "xxxhdpi": 432}

icon = Image.open("assets/icon/icon.png").convert("RGBA")
fg = Image.open("assets/icon/foreground.png").convert("RGBA")

for d, px in legacy.items():
    out = f"{RES}/mipmap-{d}"
    os.makedirs(out, exist_ok=True)
    icon.resize((px, px), Image.LANCZOS).save(f"{out}/ic_launcher.png")
for d, px in adaptive.items():
    fg.resize((px, px), Image.LANCZOS).save(f"{RES}/mipmap-{d}/ic_launcher_foreground.png")

os.makedirs(f"{RES}/mipmap-anydpi-v26", exist_ok=True)
with open(f"{RES}/mipmap-anydpi-v26/ic_launcher.xml", "w") as f:
    f.write('''<?xml version="1.0" encoding="utf-8"?>
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@color/ic_launcher_background"/>
    <foreground android:drawable="@mipmap/ic_launcher_foreground"/>
</adaptive-icon>
''')
with open(f"{RES}/values/ic_launcher_background.xml", "w") as f:
    f.write('''<?xml version="1.0" encoding="utf-8"?>
<resources>
    <color name="ic_launcher_background">#2563EB</color>
</resources>
''')
print("icons installed")
