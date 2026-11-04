"""Render the my_wallet launcher icon set with Pillow.

Outputs (in the directory given as argv[1]):
  app_icon.png          1024px full icon (legacy / iOS / Play listing)
  app_icon_fg.png       1024px adaptive foreground (transparent, content in safe zone)
  app_icon_bg.png       1024px adaptive background (gradient)
"""
import math
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

S = 4  # supersampling factor
N = 1024 * S


def lerp(a, b, t):
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(len(a)))


def hex_rgb(h, a=255):
    h = h.lstrip('#')
    return (int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16), a)


def linear_gradient(size, c1, c2, angle_deg=135):
    w, h = size
    grad = Image.new('RGBA', size)
    px = grad.load()
    ang = math.radians(angle_deg)
    dx, dy = math.cos(ang), math.sin(ang)
    proj = [x * dx + y * dy for x, y in ((0, 0), (w, 0), (0, h), (w, h))]
    lo, hi = min(proj), max(proj)
    # draw per row with a small step for speed, then resize
    step = 8
    small = Image.new('RGBA', (w // step, h // step))
    sp = small.load()
    for y in range(h // step):
        for x in range(w // step):
            t = ((x * step) * dx + (y * step) * dy - lo) / (hi - lo)
            sp[x, y] = lerp(c1, c2, t)
    return small.resize(size, Image.BICUBIC)


def rounded_mask(size, radius):
    m = Image.new('L', size, 0)
    ImageDraw.Draw(m).rounded_rectangle((0, 0, size[0] - 1, size[1] - 1), radius, fill=255)
    return m


def card(w, h, c1, c2, chip=True, waves=True, stripe_alpha=40):
    body = linear_gradient((w, h), c1, c2, 120)
    d = ImageDraw.Draw(body)
    # subtle glossy diagonal band
    gloss = Image.new('RGBA', (w, h), (0, 0, 0, 0))
    gd = ImageDraw.Draw(gloss)
    gd.polygon([(int(w * 0.55), 0), (w, 0), (w, int(h * 0.15)), (int(w * 0.25), h), (0, h), (0, int(h * 0.9))],
               fill=(255, 255, 255, stripe_alpha))
    body = Image.alpha_composite(body, gloss)
    d = ImageDraw.Draw(body)
    if chip:
        cw, ch = int(w * 0.17), int(h * 0.2)
        cx, cy = int(w * 0.1), int(h * 0.36)
        d.rounded_rectangle((cx, cy, cx + cw, cy + ch), int(ch * 0.22), fill=hex_rgb('FDE68A'))
        lw = max(2, int(ch * 0.05))
        line = hex_rgb('B45309', 200)
        d.line((cx, cy + ch // 2, cx + cw, cy + ch // 2), fill=line, width=lw)
        d.line((cx + cw // 3, cy, cx + cw // 3, cy + ch), fill=line, width=lw)
        d.line((cx + 2 * cw // 3, cy, cx + 2 * cw // 3, cy + ch), fill=line, width=lw)
    if waves:
        ox, oy = int(w * 0.80), int(h * 0.46)
        lw = int(h * 0.04)
        for i, r in enumerate((0.08, 0.15, 0.22)):
            rr = int(h * r)
            d.arc((ox - rr, oy - rr, ox + rr, oy + rr), -50, 50, fill=(255, 255, 255, 235 - i * 30), width=lw)
    # number dots
    dy = int(h * 0.75)
    r = int(h * 0.025)
    for g in range(4):
        for k in range(4):
            x = int(w * 0.1) + g * int(w * 0.2) + k * int(r * 2.6)
            d.ellipse((x, dy - r, x + 2 * r, dy + r), fill=(255, 255, 255, 200))
    out = Image.new('RGBA', (w, h), (0, 0, 0, 0))
    out.paste(body, (0, 0), rounded_mask((w, h), int(h * 0.12)))
    return out


def shadow(img, blur, alpha=110, offset=(0, 0)):
    a = img.split()[3].point(lambda v: v * alpha // 255)
    sh = Image.new('RGBA', img.size, (0, 0, 0, 0))
    sh.putalpha(a)
    pad = blur * 3
    canvas = Image.new('RGBA', (img.width + pad * 2, img.height + pad * 2), (0, 0, 0, 0))
    canvas.paste(sh, (pad + offset[0], pad + offset[1]), sh)
    return canvas.filter(ImageFilter.GaussianBlur(blur)), pad


def place(base, img, center, angle=0, shadow_blur=0):
    rot = img.rotate(angle, resample=Image.BICUBIC, expand=True)
    if shadow_blur:
        sh, pad = shadow(rot, shadow_blur, offset=(0, shadow_blur // 2))
        base.alpha_composite(sh, (center[0] - sh.width // 2, center[1] - sh.height // 2))
    base.alpha_composite(rot, (center[0] - rot.width // 2, center[1] - rot.height // 2))


def shield_badge(size):
    img = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    d.ellipse((0, 0, size - 1, size - 1), fill=hex_rgb('10B981'))
    d.ellipse((int(size * 0.04),) * 2 + (int(size * 0.96),) * 2, outline=(255, 255, 255, 255), width=int(size * 0.05))
    # padlock
    bw, bh = int(size * 0.40), int(size * 0.30)
    bx, by = (size - bw) // 2, int(size * 0.47)
    lw = int(size * 0.07)
    sw = int(bw * 0.62)
    sx = (size - sw) // 2
    d.arc((sx, int(size * 0.24), sx + sw, int(size * 0.24) + int(sw * 1.1)), 180, 360, fill=(255, 255, 255, 255), width=lw)
    d.line((sx + lw // 2, int(size * 0.24) + int(sw * 0.55), sx + lw // 2, by + 2), fill=(255, 255, 255, 255), width=lw)
    d.line((sx + sw - lw // 2, int(size * 0.24) + int(sw * 0.55), sx + sw - lw // 2, by + 2), fill=(255, 255, 255, 255), width=lw)
    d.rounded_rectangle((bx, by, bx + bw, by + bh), int(bh * 0.2), fill=(255, 255, 255, 255))
    kr = int(size * 0.045)
    d.ellipse((size // 2 - kr, by + bh // 2 - kr, size // 2 + kr, by + bh // 2 + kr), fill=hex_rgb('10B981'))
    return img


def foreground(scale):
    """Card stack + lock badge, scaled to `scale` of the canvas."""
    fg = Image.new('RGBA', (N, N), (0, 0, 0, 0))
    cw = int(N * 0.62 * scale)
    ch = int(cw * 0.63)
    cx, cy = N // 2, N // 2
    back = card(cw, ch, hex_rgb('8B5CF6'), hex_rgb('6366F1'), chip=False, waves=False, stripe_alpha=25)
    front = card(cw, ch, hex_rgb('22D3EE'), hex_rgb('3B82F6'))
    place(fg, back, (cx - int(N * 0.03 * scale), cy - int(N * 0.10 * scale)), angle=14, shadow_blur=int(N * 0.012))
    place(fg, front, (cx + int(N * 0.01 * scale), cy + int(N * 0.05 * scale)), angle=-6, shadow_blur=int(N * 0.018))
    b = shield_badge(int(N * 0.26 * scale))
    place(fg, b, (cx + int(N * 0.25 * scale), cy + int(N * 0.25 * scale)), shadow_blur=int(N * 0.01))
    return fg


def main(out_dir):
    out = Path(out_dir)
    out.mkdir(parents=True, exist_ok=True)
    bg = linear_gradient((N, N), hex_rgb('0F172A'), hex_rgb('312E81'), 135)
    # soft glow behind the stack
    glow = Image.new('RGBA', (N, N), (0, 0, 0, 0))
    ImageDraw.Draw(glow).ellipse((N * 0.2, N * 0.2, N * 0.8, N * 0.8), fill=(99, 102, 241, 90))
    bg = Image.alpha_composite(bg, glow.filter(ImageFilter.GaussianBlur(N // 10)))

    full = bg.copy()
    full.alpha_composite(foreground(1.0))
    full.resize((1024, 1024), Image.LANCZOS).save(out / 'app_icon.png')

    # adaptive: content must stay inside the inner 66% safe zone
    foreground(0.82).resize((1024, 1024), Image.LANCZOS).save(out / 'app_icon_fg.png')
    bg.resize((1024, 1024), Image.LANCZOS).convert('RGB').save(out / 'app_icon_bg.png')

    # preview strip: full, circle mask, squircle mask
    prev = Image.new('RGBA', (3 * 300 + 40, 340), (240, 240, 240, 255))
    small = full.resize((280, 280), Image.LANCZOS)
    prev.alpha_composite(small, (10, 30))
    adapt = bg.copy()
    adapt.alpha_composite(foreground(0.82))
    adapt = adapt.resize((280, 280), Image.LANCZOS)
    circ = Image.new('L', (280, 280), 0)
    ImageDraw.Draw(circ).ellipse((0, 0, 279, 279), fill=255)
    prev.paste(adapt, (320, 30), circ)
    prev.paste(adapt, (630, 30), rounded_mask((280, 280), 70))
    prev.save(out / 'preview.png')


if __name__ == '__main__':
    main(sys.argv[1])
