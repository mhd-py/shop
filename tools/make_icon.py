from PIL import Image, ImageDraw

BLUE = (37, 99, 235, 255)
WHITE = (255, 255, 255, 255)
S = 1024


def glyph(d, fg, ink):
    # Receipt with zigzag bottom, kept inside the central safe zone.
    d.rounded_rectangle((342, 262, 682, 712), radius=28, fill=fg)
    pts = [(342, 700)]
    x = 342
    while x < 682:
        pts += [(x + 17, 752), (x + 34, 700)]
        x += 34
    d.polygon(pts, fill=fg)
    for y, w in ((350, 220), (426, 180), (502, 200)):
        d.rounded_rectangle((382, y, 382 + w, y + 28), radius=14, fill=ink)
    d.rounded_rectangle((382, 590, 642, 630), radius=20, fill=ink)


full = Image.new("RGBA", (S, S), BLUE)
glyph(ImageDraw.Draw(full), WHITE, BLUE)
full.save("assets/icon/icon.png")

fg = Image.new("RGBA", (S, S), (0, 0, 0, 0))
glyph(ImageDraw.Draw(fg), WHITE, BLUE)
fg.save("assets/icon/foreground.png")
