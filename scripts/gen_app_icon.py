"""앱 아이콘(발바닥 + 노트)을 Android vector drawable로 만든다.

    python3 scripts/gen_app_icon.py

android/app/src/main/res/drawable 아래 전경·배경·테마(단색) 레이어를 다시 쓴다.
svg()는 미리보기용으로, 같은 도형을 SVG로 그린다.
"""
from pathlib import Path

def rrect(x, y, w, h, r):
    return (f"M{x+r},{y} H{x+w-r} A{r},{r} 0 0 1 {x+w},{y+r} V{y+h-r} "
            f"A{r},{r} 0 0 1 {x+w-r},{y+h} H{x+r} A{r},{r} 0 0 1 {x},{y+h-r} "
            f"V{y+r} A{r},{r} 0 0 1 {x+r},{y} Z")

def ellipse(cx, cy, rx, ry):
    return (f"M{cx-rx},{cy} A{rx},{ry} 0 1 0 {cx+rx},{cy} "
            f"A{rx},{ry} 0 1 0 {cx-rx},{cy} Z")

INK = "#0B4F3F"
PAGE = "#FFFFFF"
SPINE = "#D6EEE6"
LINE = "#DCEAE5"
PAW = "#F29AA3"
PAW_EDGE = "#D9707C"

# 108x108 캔버스, 안전 영역은 중심(54,54) 반지름 33 원.
PX, PY, PW, PH = 32, 27, 46, 54
PAD = ("M60,53.5 C66.5,53.5 71,59.5 71,63.8 C71,67.8 67.2,69.2 63.6,68.4 "
       "C61.8,68 58.2,68 56.4,68.4 C52.8,69.2 49,67.8 49,63.8 C49,59.5 53.5,53.5 60,53.5 Z")
TOES = [(48.6, 51.0, 3.3, 4.2, -25), (55.2, 45.8, 3.5, 4.6, -8),
        (64.8, 45.8, 3.5, 4.6, 8), (71.4, 51.0, 3.3, 4.2, 25)]

def paw(color, edge=None):
    extra = (edge,) if edge else ()
    shapes = [("path", PAD, color, *extra)]
    for cx, cy, rx, ry, rot in TOES:
        shapes.append(("group", rot, cx, cy, ellipse(cx, cy, rx, ry), color, *extra))
    return shapes

def foreground():
    shapes = []
    # 노트 그림자(배경 초록보다 진한 색)
    shapes.append(("path", rrect(PX + 2, PY + 3, PW, PH, 6), "#146B56"))
    shapes.append(("path", rrect(PX, PY, PW, PH, 6), PAGE))
    # 제본 쪽 띠
    shapes.append(("path", f"M{PX+6},{PY} H{PX+9} V{PY+PH} H{PX+6} A6,6 0 0 1 {PX},{PY+PH-6} V{PY+6} A6,6 0 0 1 {PX+6},{PY} Z", SPINE))
    # 줄
    for y in (35, 76):
        shapes.append(("path", rrect(PX + 13, y, PW - 18, 1.4, 0.7), LINE))
    # 발바닥: 테두리색을 조금 크게 깔고 위에 채운다. 종이 안쪽 가운데로 옮긴다.
    shapes.append(("xform", 0.9, 60, 57, 0, -1.5, paw(PAW_EDGE, 1.0) + paw(PAW)))
    # 제본 링
    for y in (39, 66):
        shapes.append(("path", rrect(PX - 5, y, 12, 4.4, 2.2), INK))
    return shapes

def monochrome():
    # 테마 아이콘(Android 13+)은 모양의 알파만 쓴다. 핵심인 발바닥만 크게 넣는다.
    return [("xform", 1.5, 60, 57, -6, -3, paw("#FFFFFF"))]

def vd_shape(s, indent="    "):
    if s[0] == "xform":
        _, k, px, py, tx, ty, children = s
        inner = "".join(vd_shape(c, indent + "    ") for c in children)
        return (f'{indent}<group\n{indent}    android:pivotX="{px}"\n{indent}    android:pivotY="{py}"\n'
                f'{indent}    android:scaleX="{k}"\n{indent}    android:scaleY="{k}"\n'
                f'{indent}    android:translateX="{tx}"\n{indent}    android:translateY="{ty}">\n'
                f"{inner}{indent}</group>\n")
    if s[0] == "path":
        stroke = ""
        if len(s) > 3:
            stroke = f'\n{indent}    android:strokeColor="{s[2]}"\n{indent}    android:strokeWidth="{s[3]*2}"\n{indent}    android:strokeLineJoin="round"'
        return (f'{indent}<path\n{indent}    android:fillColor="{s[2]}"{stroke}\n'
                f'{indent}    android:pathData="{s[1]}" />\n')
    _, rot, cx, cy, d, color, *edge = s
    inner = vd_shape(("path", d, color, *edge), indent + "    ")
    return (f'{indent}<group android:rotation="{rot}" android:pivotX="{cx}" android:pivotY="{cy}">\n'
            f"{inner}{indent}</group>\n")

def svg_shape(s):
    if s[0] == "xform":
        _, k, px, py, tx, ty, children = s
        t = f"translate({tx},{ty}) translate({px},{py}) scale({k}) translate({-px},{-py})"
        return f'<g transform="{t}">' + "".join(svg_shape(c) for c in children) + "</g>"
    if s[0] == "path":
        stroke = f' stroke="{s[2]}" stroke-width="{s[3]*2}" stroke-linejoin="round"' if len(s) > 3 else ""
        return f'<path d="{s[1]}" fill="{s[2]}"{stroke}/>'
    _, rot, cx, cy, d, color, *edge = s
    return f'<g transform="rotate({rot} {cx} {cy})">' + svg_shape(("path", d, color, *edge)) + "</g>"

HEADER = ('<vector xmlns:android="http://schemas.android.com/apk/res/android"\n'
          '    android:width="108dp"\n    android:height="108dp"\n'
          '    android:viewportWidth="108"\n    android:viewportHeight="108">\n')

BG_TOP, BG_BOTTOM = "#2A9D7F", "#1A7A63"

def background_vd():
    return ('<vector xmlns:android="http://schemas.android.com/apk/res/android"\n'
            '    xmlns:aapt="http://schemas.android.com/aapt"\n'
            '    android:width="108dp"\n    android:height="108dp"\n'
            '    android:viewportWidth="108"\n    android:viewportHeight="108">\n'
            '    <path android:pathData="M0,0 H108 V108 H0 Z">\n'
            '        <aapt:attr name="android:fillColor">\n'
            '            <gradient\n'
            '                android:type="linear"\n'
            '                android:startX="0" android:startY="0"\n'
            '                android:endX="108" android:endY="108">\n'
            f'                <item android:offset="0" android:color="{BG_TOP}" />\n'
            f'                <item android:offset="1" android:color="{BG_BOTTOM}" />\n'
            '            </gradient>\n'
            '        </aapt:attr>\n'
            '    </path>\n'
            '</vector>\n')

def svg(shapes, clip, bg=True, size=108):
    clips = {
        "circle": '<circle cx="54" cy="54" r="54"/>',
        "squircle": '<rect x="0" y="0" width="108" height="108" rx="30"/>',
        "full": '<rect x="0" y="0" width="108" height="108"/>',
    }
    back = (f'<defs><linearGradient id="g" x1="0" y1="0" x2="1" y2="1">'
            f'<stop offset="0" stop-color="{BG_TOP}"/><stop offset="1" stop-color="{BG_BOTTOM}"/>'
            f'</linearGradient><clipPath id="c">{clips[clip]}</clipPath></defs>')
    body = ('<rect width="108" height="108" fill="url(#g)"/>' if bg else "") + "".join(svg_shape(s) for s in shapes)
    return (f'<svg xmlns="http://www.w3.org/2000/svg" width="{size}" height="{size}" viewBox="0 0 108 108">'
            f'{back}<g clip-path="url(#c)">{body}</g></svg>')

if __name__ == "__main__":
    out = Path(__file__).resolve().parent.parent / "android/app/src/main/res/drawable"
    open(f"{out}/ic_launcher_foreground.xml", "w").write(HEADER + "".join(vd_shape(s) for s in foreground()) + "</vector>\n")
    open(f"{out}/ic_launcher_monochrome.xml", "w").write(HEADER + "".join(vd_shape(s) for s in monochrome()) + "</vector>\n")
    open(f"{out}/ic_launcher_background.xml", "w").write(background_vd())
