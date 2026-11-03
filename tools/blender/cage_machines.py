"""The arcade hall's machine row (design "Arcade Cage Concept"): 9 upright video
cabinets, 3 pinball tables, a claw machine and a ticket wheel in the old
cabinet row's 14 slots. A port of the design's HALLFX block: same dimensions,
same colours, same canvas art, painted into one atlas.

The whole row is six meshes, so six draws (the design merges per material and
reaches about 60; the phone pays for draws, not triangles):

  HallMachines        static lit parts, the atlas; UV2 = the surface in metres
                      for the grain (machine_body.gdshader)
  HallMachinesGlow    unshaded atlas parts; backglasses + claw sign keep their
                      second frame in UV2 (machine_glow.gdshader flips them)
  HallMachineScreens  the attract loop, tinted by vertex colour (machine_screen.gdshader)
  HallMachineGlass    pinball + claw glass (ArcadeFx gives it a blended material)
  HallClaw            cable + head, moved by machine_claw.gdshader; UV2.x = 1
                      on what follows the head down, origin at the slot's foot
  HallWheel           the spinning face, machine_wheel.gdshader, origin at its hub

Machine-local frame as in the design: +z is the machine's front, y up; a slot
turns it -90 degrees about y so the fronts face the cage. Sim coordinates are
three.js coordinates, so the design's numbers carry over as they are.
"""
import math
import os
import struct
import zlib

import bpy
from mathutils import Matrix, Vector, geometry

ATLAS_W = 512
ORDER = "APACAPAAWAPAAA"   # along z, lowest first, as the design deals the slots

# Press Start 2P, 8 x 8, top row first: the characters the row spells out.
GLYPHS = {
    " ": "0000000000000000", "!": "3838383030003000", "8": "78C4E4789E867C00",
    "A": "386CC6C6FEC6C600", "B": "FCC6C6FCC6C6FC00", "C": "3C66C0C0C0663C00",
    "D": "F8CCC6C6C6CCF800", "E": "FEC0C0FCC0C0FE00", "F": "FEC0C0FCC0C0C000",
    "G": "3E60C0CEC6663E00", "H": "C6C6C6FEC6C6C600", "I": "7E18181818187E00",
    "K": "C6CCD8F0F8DCCE00", "L": "6060606060607E00", "N": "C6E6F6DECEC6C600",
    "O": "7CC6C6C6C6C67C00", "P": "FCC6C6C6FCC0C000", "R": "FCC6C6CEF8DCCE00",
    "S": "7CC6C07C06C67C00", "T": "7E18181818181800", "U": "C6C6C6C6C6C67C00",
    "W": "D6D6D6D6FEEE4400", "X": "C6C66C386CC6C600", "Y": "6666663C18181800",
    "Z": "FE0E1C3870E0FE00",
}

TINT = ["#F0B84A", "#E85AB8", "#4AA0F0", "#E8503A", "#5AE070", "#F0B84A", "#9A6AF0"]
BTN = ["#D0443A", "#FFE45C", "#3276B4", "#3E9C4F"]
INK, CHROME = "#141216", "#C9CED6"
PRIZES = ["#FF7AD9", "#FFE45C", "#7EE08A", "#38E1FF", "#FF6A3A", "#F1E8D0", "#B88AFF"]
UPRIGHTS = [
    {"body": "#1F2B5E", "a1": "#F0B84A", "a2": "#E8703A", "title": "BLASTRON", "mbg": "#0B0F2A", "mfg": "#F0B84A"},
    {"body": "#5E1F28", "a1": "#FFE45C", "a2": "#FF6A3A", "title": "TURBO 88", "mbg": "#1A0508", "mfg": "#FFE45C"},
    {"body": "#1F4A30", "a1": "#7EE08A", "a2": "#F0B84A", "title": "DIG DEEP", "mbg": "#06140A", "mfg": "#7EE08A"},
    {"body": "#26262C", "a1": "#38E1FF", "a2": "#FF3AA8", "title": "NEON RUN", "mbg": "#05050A", "mfg": "#38E1FF"},
    {"body": "#4A2560", "a1": "#FF7AD9", "a2": "#FFE45C", "title": "GALAXIA", "mbg": "#12061A", "mfg": "#FF7AD9"},
    {"body": "#6A4424", "a1": "#F1E8D0", "a2": "#E8703A", "title": "KUNG POW", "mbg": "#1A0E05", "mfg": "#F1E8D0"},
    {"body": "#E2DED4", "a1": "#E8703A", "a2": "#3276B4", "title": "ROBOZONE", "mbg": "#101828", "mfg": "#FFFFFF"},
    {"body": "#2A3A44", "a1": "#FFB23A", "a2": "#D0443A", "title": "STARWAY", "mbg": "#05080C", "mfg": "#FFB23A"},
    {"body": "#151515", "a1": "#D0443A", "a2": "#F1E8D0", "title": "FIGHT!", "mbg": "#140404", "mfg": "#FF5A4A"},
]
PINBALLS = [
    {"body": "#2A1A5A", "a1": "#F0B84A", "a2": "#FF7AD9", "t1": "SPACE", "t2": "WIZARD", "bg": "#0E0628", "pf": "#3A2A8A"},
    {"body": "#7A1A14", "a1": "#FFE45C", "a2": "#FF6A1A", "t1": "HOT", "t2": "ROD", "bg": "#1A0404", "pf": "#B8321E"},
    {"body": "#0F5A5A", "a1": "#FFE45C", "a2": "#F07A62", "t1": "SURF", "t2": "CITY", "bg": "#04201E", "pf": "#1FA6B8"},
]


def rgb(c):
    return (int(c[1:3], 16), int(c[3:5], 16), int(c[5:7], 16))


def linear(c):
    def lin(v):
        v /= 255.0
        return v / 12.92 if v <= 0.04045 else ((v + 0.055) / 1.055) ** 2.4
    return tuple(lin(v) for v in rgb(c)) + (1.0,)


# ---- the atlas ---------------------------------------------------------------

class Tex:
    """One canvas from the design, row 0 on top. pack() gives it its place."""

    def __init__(self, w, h, fill="#000000"):
        self.w, self.h = w, h
        self.rows = [[rgb(fill)] * w for _ in range(h)]
        self.x = self.y = 0

    def px(self, c, x, y, w=1, h=1):
        v = rgb(c)
        for yy in range(max(0, y), min(self.h, y + h)):
            row = self.rows[yy]
            for xx in range(max(0, x), min(self.w, x + w)):
                row[xx] = v

    def text(self, s, cx, y, fg, shadow=None):
        """The design's txt(): 8 px type centred on cx, an optional hard shadow."""
        x0 = cx - len(s) * 4
        for dx, dy, c in ([(1, 1, shadow)] if shadow else []) + [(0, 0, fg)]:
            for i, ch in enumerate(s):
                g = GLYPHS[ch]
                for r in range(8):
                    bits = int(g[2 * r:2 * r + 2], 16)
                    for k in range(8):
                        if bits & (0x80 >> k):
                            self.px(c, x0 + i * 8 + k + dx, y + r + dy)

    def uv(self, u, v, atlas_h):
        """A three.js texture coordinate (v up, flipY canvas) -> Blender's atlas UV."""
        return ((self.x + u * self.w) / ATLAS_W, 1.0 - (self.y + (1.0 - v) * self.h) / atlas_h)


def pack(texs):
    """Shelves, tallest first, 1 px of repeated edge round each so nearest
    sampling on an exact edge never picks up a neighbour. Returns the height."""
    x, y, shelf = 1, 1, 0
    for t in sorted(texs, key=lambda t: (-t.h, -t.w)):
        if x + t.w + 1 > ATLAS_W:
            x, y, shelf = 1, y + shelf + 2, 0
        t.x, t.y = x, y
        x += t.w + 2
        shelf = max(shelf, t.h)
    h = 16
    while h < y + shelf + 1:
        h *= 2
    return h


def write_atlas(path, texs, h):
    img = [[(0, 0, 0)] * ATLAS_W for _ in range(h)]
    for t in texs:
        for yy in range(-1, t.h + 1):
            src = t.rows[min(t.h - 1, max(0, yy))]
            for xx in range(-1, t.w + 1):
                img[t.y + yy][t.x + xx] = src[min(t.w - 1, max(0, xx))]
    raw = b"".join(b"\0" + bytes(v for p in row for v in p) for row in img)

    def chunk(tag, data):
        return struct.pack(">I", len(data)) + tag + data + struct.pack(">I", zlib.crc32(tag + data) & 0xffffffff)

    with open(path, "wb") as f:
        f.write(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", ATLAS_W, h, 8, 2, 0, 0, 0))
                + chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b""))


# ---- three.js geometry, with its winding and UVs -------------------------------

def L(x, y, z, rx=0.0, ry=0.0, rz=0.0):
    """Translation x Rx x Ry x Rz: three's Euler XYZ, which Blender's is not."""
    return (Matrix.Translation((x, y, z)) @ Matrix.Rotation(rx, 4, "X")
            @ Matrix.Rotation(ry, 4, "Y") @ Matrix.Rotation(rz, 4, "Z"))


def plane(w, h):
    """PlaneGeometry: facing +z. Each corner is (x, y, z, u, v)."""
    a, b, c, d = (-w / 2, h / 2, 0, 0, 1), (-w / 2, -h / 2, 0, 0, 0), (w / 2, -h / 2, 0, 1, 0), (w / 2, h / 2, 0, 1, 1)
    return [(0, a, b, d), (0, b, c, d)]


def box(w, h, d):
    """BoxGeometry: face groups +x -x +y -y +z -z, as buildPlane lays them."""
    out = []

    def side(group, ua, va, wa, udir, vdir, sw, sh, sd):
        def corner(ix, iy):
            p = [0.0, 0.0, 0.0]
            p[ua] = (ix * sw - sw / 2) * udir
            p[va] = (iy * sh - sh / 2) * vdir
            p[wa] = sd / 2
            return (p[0], p[1], p[2], float(ix), 1.0 - iy)
        a, b, c, e = corner(0, 0), corner(0, 1), corner(1, 1), corner(1, 0)
        out.append((group, a, b, e))
        out.append((group, b, c, e))

    side(0, 2, 1, 0, -1, -1, d, h, w)
    side(1, 2, 1, 0, 1, -1, d, h, -w)
    side(2, 0, 2, 1, 1, 1, w, d, h)
    side(3, 0, 2, 1, 1, -1, w, d, -h)
    side(4, 0, 1, 2, 1, -1, w, h, d)
    side(5, 0, 1, 2, -1, -1, w, h, -d)
    return out


def cylinder(r, h, n=8):
    """CylinderGeometry: wall + both caps. Untextured wherever the row uses it."""
    out = []
    ring = [(r * math.sin(2 * math.pi * i / n), r * math.cos(2 * math.pi * i / n)) for i in range(n)]
    for i in range(n):
        (x0, z0), (x1, z1) = ring[i], ring[(i + 1) % n]
        t0, t1 = (x0, h / 2, z0, 0, 0), (x1, h / 2, z1, 0, 0)
        b0, b1 = (x0, -h / 2, z0, 0, 0), (x1, -h / 2, z1, 0, 0)
        out.append((0, t0, b0, t1))
        out.append((0, b0, b1, t1))
        out.append((0, (0, h / 2, 0, 0, 0), t0, t1))
        out.append((0, (0, -h / 2, 0, 0, 0), b1, b0))
    return out


def cone(r, h, n=3):
    out = []
    ring = [(r * math.sin(2 * math.pi * i / n), r * math.cos(2 * math.pi * i / n)) for i in range(n)]
    for i in range(n):
        (x0, z0), (x1, z1) = ring[i], ring[(i + 1) % n]
        out.append((0, (0, h / 2, 0, 0, 0), (x0, -h / 2, z0, 0, 0), (x1, -h / 2, z1, 0, 0)))
        out.append((0, (0, -h / 2, 0, 0, 0), (x1, -h / 2, z1, 0, 0), (x0, -h / 2, z0, 0, 0)))
    return out


def sphere(r, ws=6, hs=4):
    def p(i, j):
        phi, th = 2 * math.pi * i / ws, math.pi * j / hs
        return (-r * math.cos(phi) * math.sin(th), r * math.cos(th), r * math.sin(phi) * math.sin(th), 0, 0)
    out = []
    for j in range(hs):
        for i in range(ws):
            a, b, c, d = p(i + 1, j), p(i, j), p(i, j + 1), p(i + 1, j + 1)
            if j > 0:
                out.append((0, a, b, d))
            if j < hs - 1:
                out.append((0, b, c, d))
    return out


def ring(r0, r1, n=24):
    out = []
    for i in range(n):
        a0, a1 = 2 * math.pi * i / n, 2 * math.pi * (i + 1) / n
        p0, p1 = (r1 * math.cos(a0), r1 * math.sin(a0), 0, 0, 0), (r1 * math.cos(a1), r1 * math.sin(a1), 0, 0, 0)
        q0, q1 = (r0 * math.cos(a0), r0 * math.sin(a0), 0, 0, 0), (r0 * math.cos(a1), r0 * math.sin(a1), 0, 0, 0)
        out.append((0, q0, p0, p1))
        out.append((0, q0, p1, q1))
    return out


def circle(r, n=24):
    out = []
    for i in range(n):
        a0, a1 = 2 * math.pi * i / n, 2 * math.pi * (i + 1) / n
        p0 = (r * math.cos(a0), r * math.sin(a0), 0, (math.cos(a0) + 1) / 2, (math.sin(a0) + 1) / 2)
        p1 = (r * math.cos(a1), r * math.sin(a1), 0, (math.cos(a1) + 1) / 2, (math.sin(a1) + 1) / 2)
        out.append((0, (0, 0, 0, 0.5, 0.5), p0, p1))
    return out


def icosahedron(r):
    t = (1 + math.sqrt(5)) / 2
    v = [(-1, t, 0), (1, t, 0), (-1, -t, 0), (1, -t, 0), (0, -1, t), (0, 1, t), (0, -1, -t), (0, 1, -t),
         (t, 0, -1), (t, 0, 1), (-t, 0, -1), (-t, 0, 1)]
    k = r / math.sqrt(1 + t * t)
    v = [(a * k, b * k, c * k, 0, 0) for a, b, c in v]
    f = [0, 11, 5, 0, 5, 1, 0, 1, 7, 0, 7, 10, 0, 10, 11, 1, 5, 9, 5, 11, 4, 11, 10, 2, 10, 7, 6, 7, 1, 8,
         3, 9, 4, 3, 4, 2, 3, 2, 6, 3, 6, 8, 3, 8, 9, 4, 9, 5, 2, 4, 11, 6, 2, 10, 8, 6, 7, 9, 8, 1]
    return [(0, v[f[i]], v[f[i + 1]], v[f[i + 2]]) for i in range(0, len(f), 3)]


# The upright's side profile, (z, y); the design's ExtrudeGeometry, 4 cm deep.
SIDE_SHAPE = [(-.37, 0), (.31, 0), (.31, .86), (.42, .90), (.42, .98), (.22, 1.04), (.16, 1.52), (.31, 1.56), (.31, 1.84), (-.37, 1.84)]


def side_plate():
    """Caps are group 0 with the side art's UVs (u over 0.79 m from the back, v
    over 1.84 m), the rim group 1. After the design's rotateY(-90): x = -depth."""
    out = []
    pts = [Vector((z, y, 0)) for z, y in SIDE_SHAPE]
    uv = [((z + .37) / .79, y / 1.84) for z, y in SIDE_SHAPE]
    for tri in geometry.tessellate_polygon([pts]):
        # Near cap (x = -0.04, seen from -x) and far cap (x = 0, seen from +x).
        i0, i1, i2 = tri
        if (pts[i1] - pts[i0]).cross(pts[i2] - pts[i0]).z < 0:
            i1, i2 = i2, i1
        near = [(-.04, pts[i].y, pts[i].x, uv[i][0], uv[i][1]) for i in (i0, i1, i2)]
        far = [(0.0, pts[i].y, pts[i].x, uv[i][0], uv[i][1]) for i in (i0, i2, i1)]
        out.append((0, near[0], near[1], near[2]))
        out.append((0, far[0], far[1], far[2]))
    n = len(pts)
    for i in range(n):
        a, b = pts[i], pts[(i + 1) % n]
        a0, b0 = (0.0, a.y, a.x, 0, 0), (0.0, b.y, b.x, 0, 0)
        a1, b1 = (-.04, a.y, a.x, 0, 0), (-.04, b.y, b.x, 0, 0)
        out.append((1, a1, a0, b0))
        out.append((1, a1, b0, b1))
    return out


# ---- the row -------------------------------------------------------------------

class Mat:
    """Which of the six meshes a part lands on, and what it samples."""

    def __init__(self, sheet, tex=None, alt=None, tint=None):
        self.sheet, self.tex, self.alt, self.tint = sheet, tex, alt, tint


class Row:
    def __init__(self):
        self.texs = []
        self.swatches = {}
        self.sheets = {k: [] for k in ("lit", "glow", "screen", "glass", "claw", "wheel")}
        self.flash_i = 0   # the design's anim.bg order: every other machine flips out of step

    def tex(self, w, h, fill="#000000"):
        t = Tex(w, h, fill)
        self.texs.append(t)
        return t

    def swatch(self, c):
        if c not in self.swatches:
            self.swatches[c] = self.tex(2, 2, c)
        return self.swatches[c]

    def lam(self, c):
        return Mat("lit", self.swatch(c))

    def lamt(self, t):
        return Mat("lit", t)

    def bas(self, t, alt=None):
        return Mat("glow", t, alt)

    def bas_c(self, c):
        return Mat("glow", self.swatch(c))

    def put(self, faces, mat, M, flag=None):
        """Faces through M onto their mesh; mat is one Mat or a list by group."""
        for f in faces:
            m = mat[f[0]] if isinstance(mat, list) else mat
            ps = [M @ Vector(c[:3]) for c in f[1:]]
            flags = [flag(c) if flag else 0.0 for c in f[1:]]
            self.sheets[m.sheet].append((ps, [c[3:5] for c in f[1:]], m, flags))


def _slot(s):
    return Matrix.Translation((s[0], 0, s[1])) @ Matrix.Rotation(-math.pi / 2, 4, "Y")


def _coin_door(row, p, M):
    p(plane(.22, .28), row.coin, M)
    p(plane(.022, .045), row.coin_glow, M @ L(-.045, .03, .002))
    p(plane(.022, .045), row.coin_glow, M @ L(.045, .03, .002))


def _side_tex(row, sc):
    t = row.tex(32, 64, sc["body"])
    for y in range(64):
        for x in range(32):
            yy = 63 - y
            d = (x * 1.0 + yy * .55) % 34
            if yy < 44 and d < 4:
                t.px(sc["a1"], x, y)
            elif yy < 44 and 6 <= d < 8:
                t.px(sc["a2"], x, y)
            elif (x + y) % 2 == 0 and yy < 3:
                t.px(sc["a2"], x, y)
    t.px(sc["a1"], 0, 0, 32, 2)
    return t


def _upright(row, s, k):
    W, sc = _slot(s), UPRIGHTS[k % len(UPRIGHTS)]
    p = lambda g, m, l: row.put(g, m, W @ l)
    body, side, trim = row.lam(sc["body"]), row.lamt(_side_tex(row, sc)), row.lam(sc["a1"])
    p(side_plate(), [side, trim], L(-.33, 0, 0))
    p(side_plate(), [side, trim], L(.37, 0, 0))
    p(box(.66, 1.84, .5), body, L(0, .92, -.12))
    p(box(.66, .86, .04), body, L(0, .43, .29))
    p(box(.66, .12, .11), body, L(0, .91, .36))
    _coin_door(row, p, L(0, .44, .312))
    panel = row.tex(32, 16, "#1A1820")
    panel.px(sc["a1"], 0, 0, 32, 1)
    panel.px(sc["a1"], 0, 15, 32, 1)
    for i in range(0, 32, 2):
        panel.px(sc["a2"], i, 14)
    Lp = L(0, .985, .32, .29)
    p(box(.66, .05, .2), row.lamt(panel), Lp)
    p(cylinder(.008, .06, 5), row.lam(CHROME), Lp @ L(-.16, .055, .03))
    p(sphere(.022), row.lam(BTN[k % 4]), Lp @ L(-.16, .09, .03))
    for i, bx in enumerate((0, .08, .16)):
        p(cylinder(.02, .014, 8), row.lam(BTN[(i + k) % 4]), Lp @ L(bx, .03, .02))
    p(box(.66, .5, .03), row.lam(INK), L(0, 1.28, .175, -.124))
    p(plane(.5, .38), Mat("screen", tint=TINT[k % len(TINT)]), L(0, 1.28, .192, -.124))
    p(box(.66, .28, .15), row.lam(INK), L(0, 1.70, .235))
    marq = row.tex(72, 16, sc["mbg"])
    marq.px(sc["mfg"], 0, 0, 72, 1)
    marq.px(sc["mfg"], 0, 15, 72, 1)
    for i in range(2, 72, 6):
        marq.px(sc["mfg"], i, 2)
    marq.text(sc["title"], 36, 4, sc["mfg"], "#000000")
    p(plane(.64, .22), row.bas(marq), L(0, 1.70, .312))


def _backglass(row, th, on):
    t = row.tex(48, 40, th["bg"])
    for y in range(32):
        for x in range(48):
            band = math.floor((math.atan2(32 - y, x - 24) + math.pi) / (math.pi / 8))
            if band % 2 and (x + y) % 2 == 0:
                t.px(th["a2"], x, y)
    t.text(th["t1"], 24, 5, "#FFFFFF" if on else th["a1"], "#000000")
    t.text(th["t2"], 24, 17, th["a1"] if on else th["a2"], "#000000")
    for i in range(0, 48, 4):
        c = "#FFE45C" if ((i // 4) % 2 == 0) == on else "#4A3A1A"
        t.px(c, i, 0, 2, 1)
        t.px(c, i + 2, 31, 2, 1)
    t.px("#141216", 0, 32, 48, 8)
    for x in range(2, 46, 3):
        for y in range(34, 39, 2):
            t.px("#3A3640", x, y)
    return t


def _flash_mat(row, on, off):
    """The design swaps on/off on (step + i) % 2: UV holds the odd-step frame."""
    i = row.flash_i
    row.flash_i += 1
    return row.bas(on, off) if i % 2 == 0 else row.bas(off, on)


def _pinball(row, s, k):
    W, th = _slot(s), PINBALLS[k]
    p = lambda g, m, l: row.put(g, m, W @ l)
    chrome, ink, body, cap = row.lam(CHROME), row.lam(INK), row.lam(th["body"]), row.lam("#FFFFFF")
    st = row.tex(64, 16, th["body"])
    for x in range(64):
        for y in range(16):
            d = (x + y * 2) % 16
            if d < 3:
                st.px(th["a1"], x, y)
            elif d == 5 and y % 2:
                st.px(th["a2"], x, y)
    st.px(th["a1"], 0, 0, 64, 1)
    st.px("#000000", 0, 15, 64, 1)
    side = row.lamt(st)
    ft = row.tex(32, 56, th["pf"])
    for y in range(56):
        for x in range(32):
            if (x + y) % 2 == 0 and (y > 46 or x < 2 or x > 29):
                ft.px(th["bg"], x, y)
    ft.px(th["a1"], 0, 0, 32, 1)
    ft.px(th["a1"], 0, 0, 1, 56)
    ft.px(th["a1"], 31, 0, 1, 56)
    for x in (10, 16, 22):
        ft.px("#FFFFFF", x, 2, 1, 8)
    for r in range(3):
        for i, x in enumerate((7, 12, 19, 24)):
            ft.px(th["a2"] if i % 2 else th["a1"], x, 20 + r * 5, 2, 2)
    for i in range(6):
        ft.px("#FFFFFF", 4 + i, 38 + i)
        ft.px("#FFFFFF", 27 - i, 38 + i)
    ft.px(th["bg"], 13, 50, 6, 6)
    field = row.bas(ft)
    for lx, lz in ((-.3, -.36), (.3, -.36), (-.3, .64), (.3, .64)):
        hh = .86 if lz < 0 else .76
        p(box(.05, hh, .05), chrome, L(lx, hh / 2, lz))
    Lc = L(0, .94, .15, .09)
    p(box(.7, .26, 1.1), [side, side, field, ink, body, body], Lc)
    p(box(.02, .03, 1.1), chrome, Lc @ L(-.345, .145, 0))
    p(box(.02, .03, 1.1), chrome, Lc @ L(.345, .145, 0))
    for bx, bz, c in ((-.12, -.25, th["a1"]), (.12, -.25, th["a2"]), (0, -.08, th["a1"])):
        p(cylinder(.045, .05, 8), row.lam(c), Lc @ L(bx, .155, bz))
        p(cylinder(.028, .02, 8), cap, Lc @ L(bx, .19, bz))
    p(box(.12, .02, .025), cap, Lc @ L(-.08, .14, .38, 0, .5))
    p(box(.12, .02, .025), cap, Lc @ L(.08, .14, .38, 0, -.5))
    p(sphere(.02), chrome, Lc @ L(.1, .15, .1))
    p(plane(.68, 1.08), Mat("glass"), Lc @ L(0, .162, 0, -math.pi / 2))
    p(cylinder(.012, .09, 5), chrome, Lc @ L(.25, -.02, .59, math.pi / 2))
    p(cylinder(.02, .03, 6), row.lam(BTN[0]), L(-.365, .99, .52, 0, 0, math.pi / 2))
    p(cylinder(.02, .03, 6), row.lam(BTN[0]), L(.365, .99, .52, 0, 0, math.pi / 2))
    _coin_door(row, p, Lc @ L(0, -.02, .552) @ Matrix.Diagonal((.5, .5, 1, 1)))
    p(box(.3, .24, .14), body, L(0, 1.14, -.33))
    p(box(.7, .62, .16), [side, side, body, body, ink, body], L(0, 1.45, -.30))
    p(plane(.66, .58), _flash_mat(row, _backglass(row, th, True), _backglass(row, th, False)), L(0, 1.45, -.218))


def _claw_sign(row, on):
    t = row.tex(88, 16, "#140414")
    for i in range(0, 88, 4):
        c = "#FFE45C" if ((i // 4) % 2 == 0) == on else "#5A3A1A"
        t.px(c, i, 0, 2, 1)
        t.px(c, i + 2, 15, 2, 1)
    t.text("PRIZE GRAB", 44, 4, "#FF7AD9" if on else "#FFFFFF", "#000000")
    return t


def _claw(row, s):
    W = _slot(s)
    p = lambda g, m, l: row.put(g, m, W @ l)
    chrome, ink, body = row.lam(CHROME), row.lam(INK), row.lam("#C2306A")
    st = row.tex(32, 32, "#C2306A")
    for y in range(32):
        for x in range(32):
            if (x * 3 + y * 5) % 11 == 0:
                st.px("#FFE45C", x, y)
            elif (x * 7 + y) % 13 == 0:
                st.px("#38E1FF", x, y)
    st.px("#FFE45C", 0, 0, 32, 2)
    side = row.lamt(st)
    p(box(.74, .86, .72), [side, side, body, ink, body, body], L(0, .43, -.01))
    _coin_door(row, p, L(-.16, .44, .352))
    p(box(.2, .2, .03), ink, L(.18, .3, .352))
    p(plane(.17, .05), row.coin_glow, L(.18, .43, .353))
    p(box(.74, .05, .12), body, L(0, .885, .38))
    p(cylinder(.008, .06, 5), chrome, L(-.12, .94, .38))
    p(sphere(.024), row.lam(BTN[0]), L(-.12, .975, .38))
    p(cylinder(.035, .02, 8), row.lam(BTN[1]), L(.12, .92, .38))
    for cx, cz in ((-.355, -.355), (.355, -.355), (-.355, .335), (.355, .335)):
        p(box(.03, .9, .03), chrome, L(cx, 1.31, cz))
    glass = Mat("glass")
    p(plane(.7, .88), glass, L(0, 1.31, .345))
    p(plane(.7, .88), glass, L(-.36, 1.31, -.01, 0, math.pi / 2))
    p(plane(.7, .88), glass, L(.36, 1.31, -.01, 0, math.pi / 2))
    p(plane(.7, .88), row.lam("#2A1440"), L(0, 1.31, -.36))
    p(box(.7, .01, .7), row.lam("#1A0E24"), L(0, .865, -.01))
    p(box(.18, .012, .18), ink, L(.22, .872, .2))
    p(box(.74, .24, .72), body, L(0, 1.88, -.01))
    p(plane(.72, .18), _flash_mat(row, _claw_sign(row, True), _claw_sign(row, False)), L(0, 1.88, .352))
    # The prize pile: the design's seeded generator, draw for draw.
    sd = [3]

    def rr():
        sd[0] = (sd[0] * 16807) % 2147483647
        return sd[0] / 2147483647

    for i in range(20):
        layer = 0 if i < 13 else 1
        pos = (-.28 + rr() * .5, .93 + layer * .09 + rr() * .02, -.3 + rr() * .45)
        rx, ry = rr() * 3, rr() * 3
        sy = .8 + rr() * .4
        p(icosahedron(.062), row.lam(PRIZES[i % len(PRIZES)]), L(pos[0], pos[1], pos[2], rx, ry) @ Matrix.Diagonal((1, sy, 1, 1)))
    # Cable + head at rest: x = z = 0, the head's height zero. machine_claw.gdshader
    # adds the roam to all of it and the height to what carries UV2.x = 1.
    turn = Matrix.Rotation(-math.pi / 2, 4, "Y")
    gold, claw_chrome = Mat("claw", row.swatch("#F0B84A")), Mat("claw", row.swatch(CHROME))
    follows = lambda c: 1.0
    row.put(cylinder(.032, .05, 8), gold, turn, follows)
    for i in range(3):
        an = i / 3 * math.pi * 2
        row.put(box(.01, .085, .01), claw_chrome,
                turn @ L(math.cos(an) * .03, -.055, math.sin(an) * .03, math.sin(an) * .45, 0, -math.cos(an) * .45), follows)
    # The cable runs from just above the head (y + .02) to the gantry (1.76).
    cable = [(f[0],) + tuple((c[0], (1.76 if c[1] > 0 else .02), c[2], c[3], c[4]) for c in f[1:]) for f in box(.006, 1, .006)]
    row.put(cable, claw_chrome, turn, lambda c: 0.0 if c[1] > 1.0 else 1.0)


def _wheel(row, s):
    W = _slot(s)
    p = lambda g, m, l: row.put(g, m, W @ l)
    ink, body = row.lam(INK), row.lam("#8A1A1A")
    st = row.tex(32, 64, "#8A1A1A")
    for y in range(64):
        for x in range(32):
            if (x + y) % 10 < 2:
                st.px("#F0B84A", x, y)
    st.px("#FFE45C", 0, 0, 32, 2)
    side = row.lamt(st)
    p(box(.7, 2.0, .6), [side, side, body, ink, body, body], L(0, 1.0, -.07))
    p(ring(.27, .32, 24), row.bas_c("#F0B84A"), L(0, 1.38, .236))
    p(cone(.035, .08, 3), row.lam(BTN[0]), L(0, 1.68, .26, 0, 0, math.pi))
    head = row.tex(88, 16, "#140404")
    for i in range(0, 88, 4):
        head.px("#FFE45C", i, 0, 2, 1)
    head.text("SPIN N WIN", 44, 4, "#FFE45C", "#000000")
    p(plane(.66, .16), row.bas(head), L(0, 1.88, .232))
    p(box(.7, .05, .16), body, L(0, .95, .3))
    p(cylinder(.06, .04, 10), row.lam(BTN[0]), L(0, .99, .3))
    p(cylinder(.075, .02, 10), row.lam(CHROME), L(0, .975, .3))
    p(plane(.14, .03), row.coin_glow, L(.2, .82, .232))
    p(box(.07, .16, .004), row.lam("#F2A65E"), L(.2, .73, .236))
    _coin_door(row, p, L(-.15, .45, .232))
    face = row.tex(64, 64, INK)
    colours = ["#D0443A", "#FFE45C", "#3276B4", "#F1E8D0", "#3E9C4F", "#E8703A"]
    for y in range(64):
        for x in range(64):
            dx, dy = x - 31.5, y - 31.5
            r = math.hypot(dx, dy)
            if r > 31.5:
                continue
            an = (math.atan2(dy, dx) + math.pi) / (math.pi * 2) * 12
            i = math.floor(an)
            f = an - i
            c = colours[i % len(colours)]
            if f < .06 or r > 30:
                c = INK
            if r < 7:
                c = "#F0B84A"
            if r < 3:
                c = INK
            if abs(r - 27) < 1.2 and .4 < f < .6:
                c = "#FFFFFF"
            face.px(c, x, y)
    row.put(circle(.27, 24), Mat("wheel", face), Matrix.Rotation(-math.pi / 2, 4, "Y"))
    return (W @ L(0, 1.38, .238)).translation


def _object(name, sheet, atlas_h, material, s2b, link_obj, coll, parent, location=(0, 0, 0)):
    verts, faces, uvs, uv2s, colours = [], [], [], [], []
    for ps, cuvs, m, flags in sheet:
        faces.append((len(verts), len(verts) + 1, len(verts) + 2))
        n = (ps[1] - ps[0]).cross(ps[2] - ps[0])
        axis = max(range(3), key=lambda a: abs(n[a]))   # the plane this face lies closest to
        for i in range(3):
            verts.append(s2b(tuple(ps[i])))
            if m.tex is not None:
                u, v = cuvs[i]
                # A swatch samples its middle whatever the primitive's UVs say.
                if m.tex.w == 2 and m.tex.h == 2:
                    u, v = .5, .5
                uvs.append(m.tex.uv(u, v, atlas_h))
            else:
                uvs.append(tuple(cuvs[i]))
            if m.alt is not None:
                uv2s.append(m.alt.uv(cuvs[i][0], cuvs[i][1], atlas_h))
            elif m.sheet == "claw":
                uv2s.append((flags[i], 0.0))
            elif m.sheet == "lit":
                a, b = [c for c in range(3) if c != axis]
                uv2s.append((ps[i][a], ps[i][b]))
            else:
                uv2s.append(uvs[-1])
            colours.append(linear(m.tint) if m.tint else (1.0, 1.0, 1.0, 1.0))
    me = bpy.data.meshes.new(name)
    me.from_pydata(verts, [], faces)
    me.validate()
    uvl = me.uv_layers.new(name="UVMap")
    uv2 = me.uv_layers.new(name="UV2") if name in ("HallMachines", "HallMachinesGlow", "HallClaw") else None
    for poly in me.polygons:
        for loop in poly.loop_indices:
            vi = me.loops[loop].vertex_index
            uvl.data[loop].uv = uvs[vi]
            if uv2 is not None:
                uv2.data[loop].uv = uv2s[vi]
    if name == "HallMachineScreens":
        attr = me.color_attributes.new(name="Color", type="FLOAT_COLOR", domain="POINT")
        attr.data.foreach_set("color", [v for c in colours for v in c])
    me.materials.append(material)
    o = bpy.data.objects.new(name, me)
    link_obj(o, coll, parent, s2b(tuple(location)))
    return o


def build(coll, parent, slots, s2b, link_obj, mat_tex, tex_path):
    """Paint the atlas and add the six meshes. slots = (x, z) lowest z first."""
    row = Row()
    coin = row.tex(16, 20, "#6A6E76")
    coin.px("#9A9EA6", 0, 0, 16, 1)
    coin.px("#9A9EA6", 0, 0, 1, 20)
    coin.px("#3E4248", 15, 0, 1, 20)
    coin.px("#3E4248", 0, 19, 16, 1)
    coin.px("#2A2A2E", 3, 5, 3, 6)
    coin.px("#2A2A2E", 10, 5, 3, 6)
    coin.px("#D0443A", 4, 13, 2, 2)
    coin.px("#D0443A", 10, 13, 2, 2)
    coin.px("#C9CED6", 7, 16, 2, 2)
    row.coin = row.lamt(coin)
    row.coin_glow = row.bas_c("#FF8A2A")
    ua = pa = 0
    hub, foot = None, None
    for i, s in enumerate(slots):
        kind = ORDER[i]
        if kind == "A":
            _upright(row, s, ua)
            ua += 1
        elif kind == "P":
            _pinball(row, s, pa)
            pa += 1
        elif kind == "C":
            _claw(row, s)
            foot = (s[0], 0.0, s[1])
        else:
            hub = _wheel(row, s)
    atlas_h = pack(row.texs)
    path = tex_path("cage_machines.png")
    write_atlas(path, row.texs, atlas_h)
    material = mat_tex("Hall_Machines", path, matte=True)
    made = []
    for name, key, loc in (("HallMachines", "lit", (0, 0, 0)), ("HallMachinesGlow", "glow", (0, 0, 0)),
                           ("HallMachineScreens", "screen", (0, 0, 0)), ("HallMachineGlass", "glass", (0, 0, 0)),
                           ("HallClaw", "claw", foot), ("HallWheel", "wheel", hub)):
        made.append(_object(name, row.sheets[key], atlas_h, material, s2b, link_obj, coll, parent, loc))
    print("MACHINES atlas %dx%d, %d textures" % (ATLAS_W, atlas_h, len(row.texs)),
          {k: len(v) for k, v in row.sheets.items()})
    return made
