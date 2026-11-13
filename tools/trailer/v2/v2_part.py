"""Trailer v2: one part's deliverables from its clips (v2.py part N; docs/TRAILER.md -> v2).

A part file, tools/trailer/v2/parts/partNN.json:
  segments   [{clip, from, offset, frames}]  clips under marketing/trailer/v2/clips (the director's
                                               .mov/.wav/.marks.json); `from` is a mark, `offset` frames
                                               after it; the segments' frames add up to the part's
  card_in    the part frame the text card comes in (default: the hit that says "text card in")
  hit_marks  {"bar.beat": "mark" | "mark+n" | "mark-n"}  which mark of the clip each hit's moment is
  notes      what was approximated, for the report
Writes marketing/trailer/v2/parts/partNN/: partNN_clean.mov, partNN_text.mov (all-intra crf 10, exactly
`frames` long, the game's SFX only), partNN_sfx.wav, partNN_review.mp4 (text + its slice of music.wav),
partNN_sheet.png (one frame per beat, labelled), partNN_report.md (hits landed vs target, sources,
approximations). Stdlib only: the sheet's labels are a built-in 5x7 font.
"""
import json, os, struct, subprocess, sys, zlib

import v2

FPS = v2.FPS
MASTER = v2.MASTER
TILE = (216, 468)            # a sheet tile: the master at 0.2
FONT_SCALE = 2
GRID_COLS = 8


def seg_sources(seg):
    """A segment's files: a director clip ({clip}: v2/clips, with its marks) or a conformed phone
    recording ({conform: "part02/cage_make"}: v2/conform, no marks — `from` is a frame number)."""
    if seg.get("conform"):
        base = os.path.join(v2.OUT, "conform", seg["conform"])
        mov, wav = base + ".mov", base + ".wav"
        if not os.path.exists(mov):
            sys.exit("missing %s (v2.py conform <recording>)" % mov)
        n = v2.count_frames(mov)
        return mov, (wav if os.path.exists(wav) else None), {"marks": {"in": 0, "end": n - 30}, "flicks": [], "problems": [], "recording": os.path.basename(mov)}
    clip = seg["clip"]
    base = os.path.join(v2.OUT, "clips", clip)
    mov, wav, marks = base + ".mov", base + ".wav", base + ".marks.json"
    for p in (mov, wav, marks):
        if not os.path.exists(p):
            sys.exit("missing %s (tools/trailer/v2/capture.sh %s)" % (p, clip))
    return mov, wav, json.load(open(marks))


def mark_frame(marks, spec):
    """A clip frame from "in", "land+5", "tap-3" (frames), or a plain frame number."""
    spec = str(spec)
    if spec.lstrip("-").isdigit():
        return int(spec)
    name, off = spec, 0
    for sign in "+-":
        if sign in spec[1:]:
            i = spec.rindex(sign)
            name, off = spec[:i], int(spec[i:])
            break
    if name not in marks:
        return None
    return int(marks[name]) + off


def beat_frames(sb, bars, start_frame):
    """Every beat of `bars` as (bar, beat, frame from start_frame), rounded on the global timeline."""
    bpm = float(sb["timing"]["bpm"])
    out = []
    for bar in range(bars[0], bars[1] + 1):
        for beat in range(1, 5):
            t = ((bar - 1) * 4 + (beat - 1)) * 60.0 / bpm
            out.append((bar, beat, int(round(t * FPS)) - start_frame))
    return out


def zoom_filter(zoom, f0):
    """A segment's `zoom` {from, to, rect: [x, y, w, h], power}: a zip from the whole frame into `rect`
    (master px) between the clip frames `from` and `to` — the crop window shrinks on an ease-in
    (`power`, 2 = quadratic: slow off the mark, fast through the end) until the rect fills the frame's
    height, its centre sliding from the frame's centre to the rect's; the window stays inside the frame.
    Returns the filters to append after the master scale ("" when there is no zoom)."""
    if not zoom:
        return ""
    n0, n1 = int(zoom["from"]) - f0, int(zoom["to"]) - f0
    rx, ry, rw, rh = [float(v) for v in zoom["rect"]]
    mw, mh = MASTER
    big = float(zoom.get("factor", mh / rh))
    cx, cy = rx + rw / 2.0, ry + rh / 2.0
    # zoompan, one output frame per input (`crop` reads its w/h once, so it cannot shrink per frame);
    # `in` counts input frames from 1.
    e = "pow(clip((in-1-%d)/%d\\,0\\,1)\\,%g)" % (n0, max(1, n1 - n0), float(zoom.get("power", 2)))
    z = "1+%.6f*%s" % (big - 1.0, e)
    x = "clip(%.3f+%.3f*%s-iw/zoom/2\\,0\\,iw-iw/zoom)" % (mw / 2.0, cx - mw / 2.0, e)
    y = "clip(%.3f+%.3f*%s-ih/zoom/2\\,0\\,ih-ih/zoom)" % (mh / 2.0, cy - mh / 2.0, e)
    return ",zoompan=z='%s':x='%s':y='%s':d=1:s=%dx%d:fps=%d,setsar=1" % (z, x, y, mw, mh, FPS)


def build(key):
    """`key` is a part number ("2") or one of a part's frames_list segments ("2a"): the segment is built
    on its own, as its slice of the part (its frames, its bar, the part's card already up where it is)."""
    sb = v2.story()
    n = int("".join(ch for ch in key if ch.isdigit()))
    sub = "".join(ch for ch in key if ch.isalpha())
    part = next(p for p in sb["parts"] if int(p["part"]) == n)
    part_id = "part%02d" % n
    pid = part_id + sub
    start, end = int(part["start_frame"]), int(part["end_frame"])
    bars = [int(part["bars"][0]), int(part["bars"][1])]
    if sub:
        entry = next((e for e in part.get("frames_list", []) if str(e.get("id")) == "%d%s" % (n, sub)), None)
        if entry is None:
            sys.exit("part %d has no segment '%s' in its frames_list" % (n, key))
        start, end = int(entry["start_frame"]), int(entry["end_frame"])
        # A slice may run past its bar (the beach, since 2026-11-13): the sheet shows every beat it covers.
        bpm = float(sb["timing"]["bpm"])
        last_bar = int(((end - 1) / FPS) * bpm / 60.0 / 4.0) + 1
        bars = [int(entry["bar"]), max(int(entry["bar"]), last_bar)]
    sub_offset = start - int(part["start_frame"])   # the slice's first frame, in part frames
    frames = end - start
    spec_path = os.path.join(v2.V2, "parts", pid + ".json")
    if not os.path.exists(spec_path):
        sys.exit("no part file %s" % spec_path)
    spec = json.load(open(spec_path))
    segs = spec["segments"]
    if sum(int(s["frames"]) for s in segs) != frames:
        sys.exit("%s: the segments add up to %d frames, the slice is %d" % (pid, sum(int(s["frames"]) for s in segs), frames))
    out_dir = os.path.join(v2.OUT, "parts", part_id)
    os.makedirs(out_dir, exist_ok=True)
    dst = lambda tail: os.path.join(out_dir, "%s_%s" % (pid, tail))
    # The text card: from its hit to the part's last frame (card_scene.gd render_v2 made the frames).
    card_in = spec.get("card_in")
    if card_in is None:
        card_in = 0
        for h in part.get("hits", []):
            if "text card in" in str(h.get("what", "")).lower():
                card_in = int(h["part_frame"])
    card_in -= sub_offset   # relative to this slice: negative = already up when it starts
    has_card = part.get("text") is not None and card_in < frames
    card_seq = os.path.join(v2.OUT, "cards", part_id, "f%04d.png")
    if has_card and not os.path.exists(card_seq % 0):
        sys.exit("missing card frames %s (tools/trailer/v2/cards.sh %d)" % (os.path.dirname(card_seq), n))
    # Inputs and the graph: each segment trimmed by frame, concatenated at the clip size, then the one downscale.
    inputs, vf, af = [], [], []
    def add_input(args):
        inputs.append(args)
        return len(inputs) - 1
    placed = []   # (segment, its part frame, its clip's first frame, marks, sources) for the report
    at = 0
    down = "scale=%d:%d:flags=area,setsar=1" % MASTER   # every source to the master once (a conformed recording already is)
    for i, s in enumerate(segs):
        mov, wav, mk = seg_sources(s)
        label = s.get("clip") or s.get("conform")
        f0 = mark_frame(mk["marks"], s.get("from", "in"))
        if f0 is None:
            sys.exit("%s: %s has no mark '%s'" % (pid, label, s.get("from")))
        f0 += int(s.get("offset", 0))
        nseg = int(s["frames"])
        have = int(mk["marks"].get("end", 0)) + 30
        if f0 < 0 or f0 + nseg > have:
            sys.exit("%s: '%s' from %s needs frames %d-%d of %d (lengthen the shot or move `from`)" % (pid, label, s.get("from"), f0, f0 + nseg, have))
        vi = add_input(["-i", mov])
        vf.append("[%d:v]trim=start_frame=%d:end_frame=%d,setpts=PTS-STARTPTS,%s%s[v%d]" % (vi, f0, f0 + nseg, down, zoom_filter(s.get("zoom"), f0), i))
        if wav:
            ai = add_input(["-i", wav])
            af.append("[%d:a]atrim=start=%.6f:end=%.6f,asetpts=PTS-STARTPTS,aresample=48000,aformat=channel_layouts=stereo[a%d]" % (ai, f0 / FPS, (f0 + nseg) / FPS, i))
        else:
            ai = add_input(["-f", "lavfi", "-i", "anullsrc=r=48000:cl=stereo:d=%.6f" % (nseg / FPS)])
            af.append("[%d:a]atrim=duration=%.6f[a%d]" % (ai, nseg / FPS, i))
        placed.append((s, at, f0, mk))
        at += nseg
    vf.append("%sconcat=n=%d:v=1:a=0,split[vclean][vraw2]" % ("".join("[v%d]" % i for i in range(len(segs))), len(segs)))
    af.append("%sconcat=n=%d:v=0:a=1,asplit=3[sfx1][sfx2][sfx3]" % ("".join("[a%d]" % i for i in range(len(segs))), len(segs)))
    if has_card:
        ci = add_input(["-framerate", str(FPS), "-i", card_seq])
        t0 = max(card_in, 0) / FPS
        if card_in < 0:   # the card came in before this slice: skip its first frames
            vf.append("[%d:v]trim=start_frame=%d,setpts=PTS-STARTPTS,%s[card]" % (ci, -card_in, down))
        else:
            vf.append("[%d:v]setpts=PTS+%.6f/TB,%s[card]" % (ci, t0, down))
        vf.append("[vraw2][card]overlay=0:0:eof_action=pass:enable='gte(t,%.6f)'[vtext]" % t0)
    else:
        vf.append("[vraw2]null[vtext]")
    cmd = [v2.FFMPEG, "-y", "-loglevel", "error"]
    for a in inputs:
        cmd += a
    cmd += ["-filter_complex", ";".join(vf + af)]
    audio = ["-c:a", "pcm_s16le", "-ar", "48000", "-ac", "2"]
    cmd += ["-map", "[vclean]", "-map", "[sfx1]", "-frames:v", str(frames)] + v2.MEZZ + audio + [dst("clean.mov")]
    cmd += ["-map", "[vtext]", "-map", "[sfx2]", "-frames:v", str(frames)] + v2.MEZZ + audio + [dst("text.mov")]
    cmd += ["-map", "[sfx3]"] + audio + [dst("sfx.wav")]
    v2.run(cmd)
    # The review: the text version with the part's slice of the music, the SFX under it.
    music = os.path.join(v2.OUT, "music.wav")
    if not os.path.exists(music):
        sys.exit("no music.wav (v2.py music)")
    a, b = start / FPS, end / FPS
    v2.run([v2.FFMPEG, "-y", "-loglevel", "error", "-i", dst("text.mov"), "-i", music, "-filter_complex",
            "[1:a]atrim=start=%.6f:end=%.6f,asetpts=PTS-STARTPTS,volume=-3dB[m];[0:a]volume=-5dB[s];[m][s]amix=inputs=2:normalize=0:duration=first[a]" % (a, b),
            "-map", "0:v", "-map", "[a]", "-c:v", "libx264", "-preset", "fast", "-crf", "18", "-pix_fmt", "yuv420p", "-c:a", "aac", "-b:a", "192k", "-movflags", "+faststart", dst("review.mp4")])
    # The sheet and the report.
    beats = [b for b in beat_frames(sb, bars, start) if 0 <= b[2] < frames]
    hits = {}
    for h in part.get("hits", []):
        f = int(h["part_frame"]) - sub_offset
        if 0 <= f < frames:
            hits["%d.%d" % (int(h["bar"]), int(h["beat"]))] = dict(h, part_frame=f)
    # The part file's own hits ({key, what, target, clip, clip_frame}: a moment inside a source, like a
    # recording's make), reported through the segment that carries that source frame.
    for h in spec.get("hits", []):
        hits[str(h["key"])] = {"what": h["what"], "part_frame": int(h["target"]), "clip": h.get("clip"), "clip_frame": h.get("clip_frame")}
    sheet(dst("text.mov"), beats, hits, dst("sheet.png"))
    slice_ = dict(part, title=part["title"] + (" — %s" % key if sub else ""), bars=bars, start_frame=start, end_frame=end)
    report = report_lines(slice_, pid, spec, placed, hits, frames, dst)
    open(dst("report.md"), "w").write("\n".join(report) + "\n")
    print("\n".join(report))
    return 0


def report_lines(part, pid, spec, placed, hits, frames, dst):
    lines = ["# %s — %s (bars %d–%d, frames %d–%d, %d frames)" % (pid, part["title"], part["bars"][0], part["bars"][1], part["start_frame"], part["end_frame"], frames), ""]
    # Lengths.
    for tail in ("clean.mov", "text.mov"):
        n = v2.count_frames(dst(tail))
        lines.append("- %s: %d frames%s" % (tail, n, "" if n == frames else "  **WRONG (wanted %d)**" % frames))
    wf = v2.wav_frames(dst("sfx.wav"))
    lines.append("- sfx.wav: %.2f frames%s" % (wf, "" if abs(wf - frames) < 1.0 else "  **WRONG**"))
    lines.append("- review.mp4, sheet.png: " + os.path.dirname(dst("x")))
    # Hits.
    lines += ["", "| hit | what | target | landed | delta |", "|---|---|---|---|---|"]
    hit_marks = spec.get("hit_marks", {})
    for key in sorted(hits, key=lambda k: tuple(int(x) for x in k.split("."))):
        h = hits[key]
        target = int(h["part_frame"])
        landed = None
        mspec = hit_marks.get(key)
        if h.get("clip_frame") is not None:   # a frame of a named source
            for s, at, f0, mk in placed:
                if (s.get("clip") or s.get("conform")) == h.get("clip") and f0 <= int(h["clip_frame"]) <= f0 + int(s["frames"]):
                    landed = at + (int(h["clip_frame"]) - f0)
                    break
            mspec = "%s@%s" % (h.get("clip"), h.get("clip_frame"))
        elif mspec:
            for s, at, f0, mk in placed:
                f = mark_frame(mk["marks"], mspec)
                if f is not None and f0 <= f <= f0 + int(s["frames"]):
                    landed = at + (f - f0)
                    break
        if landed is None:
            lines.append("| %s | %s | %d | — | (no mark%s) |" % (key, h["what"], target, ": " + mspec if mspec else ""))
        else:
            d = landed - target
            lines.append("| %s | %s | %d | %d | %+d%s |" % (key, h["what"], target, landed, d, "  **FLAG**" if abs(d) > 2 else ""))
    # Sources.
    lines += ["", "Sources:"]
    for s, at, f0, mk in placed:
        extra = []
        if mk.get("flicks"):
            extra.append("flicks " + ", ".join(mk["flicks"]))
        if mk.get("problems"):
            extra.append("PROBLEMS " + "; ".join(mk["problems"]))
        if mk.get("recording"):
            extra.append("Ross's recording, conformed")
        lines.append("- part frames %d–%d: %s from frame %d (%s%+d)%s" % (at, at + int(s["frames"]), (s.get("clip") or s.get("conform")) + ".mov", f0, s.get("from", "in"), int(s.get("offset", 0)), ("; " + "; ".join(extra)) if extra else ""))
    if spec.get("notes"):
        lines += ["", "Approximated / notes:"] + ["- " + n for n in spec["notes"]]
    return lines


# ---- the sheet ---------------------------------------------------------------------------

FONT = {
    "A": [" ### ", "#   #", "#   #", "#####", "#   #", "#   #", "#   #"],
    "B": ["#### ", "#   #", "#   #", "#### ", "#   #", "#   #", "#### "],
    "C": [" ####", "#    ", "#    ", "#    ", "#    ", "#    ", " ####"],
    "D": ["#### ", "#   #", "#   #", "#   #", "#   #", "#   #", "#### "],
    "E": ["#####", "#    ", "#    ", "#### ", "#    ", "#    ", "#####"],
    "F": ["#####", "#    ", "#    ", "#### ", "#    ", "#    ", "#    "],
    "G": [" ####", "#    ", "#    ", "# ###", "#   #", "#   #", " ####"],
    "H": ["#   #", "#   #", "#   #", "#####", "#   #", "#   #", "#   #"],
    "I": ["#####", "  #  ", "  #  ", "  #  ", "  #  ", "  #  ", "#####"],
    "J": ["    #", "    #", "    #", "    #", "#   #", "#   #", " ### "],
    "K": ["#   #", "#  # ", "# #  ", "##   ", "# #  ", "#  # ", "#   #"],
    "L": ["#    ", "#    ", "#    ", "#    ", "#    ", "#    ", "#####"],
    "M": ["#   #", "## ##", "# # #", "#   #", "#   #", "#   #", "#   #"],
    "N": ["#   #", "##  #", "# # #", "#  ##", "#   #", "#   #", "#   #"],
    "O": [" ### ", "#   #", "#   #", "#   #", "#   #", "#   #", " ### "],
    "P": ["#### ", "#   #", "#   #", "#### ", "#    ", "#    ", "#    "],
    "Q": [" ### ", "#   #", "#   #", "#   #", "# # #", "#  # ", " ## #"],
    "R": ["#### ", "#   #", "#   #", "#### ", "# #  ", "#  # ", "#   #"],
    "S": [" ####", "#    ", "#    ", " ### ", "    #", "    #", "#### "],
    "T": ["#####", "  #  ", "  #  ", "  #  ", "  #  ", "  #  ", "  #  "],
    "U": ["#   #", "#   #", "#   #", "#   #", "#   #", "#   #", " ### "],
    "V": ["#   #", "#   #", "#   #", "#   #", "#   #", " # # ", "  #  "],
    "W": ["#   #", "#   #", "#   #", "# # #", "# # #", "## ##", "#   #"],
    "X": ["#   #", "#   #", " # # ", "  #  ", " # # ", "#   #", "#   #"],
    "Y": ["#   #", "#   #", " # # ", "  #  ", "  #  ", "  #  ", "  #  "],
    "Z": ["#####", "    #", "   # ", "  #  ", " #   ", "#    ", "#####"],
    "0": [" ### ", "#   #", "#  ##", "# # #", "##  #", "#   #", " ### "],
    "1": ["  #  ", " ##  ", "  #  ", "  #  ", "  #  ", "  #  ", " ### "],
    "2": [" ### ", "#   #", "    #", "   # ", "  #  ", " #   ", "#####"],
    "3": ["#####", "   # ", "  #  ", "   # ", "    #", "#   #", " ### "],
    "4": ["   # ", "  ## ", " # # ", "#  # ", "#####", "   # ", "   # "],
    "5": ["#####", "#    ", "#### ", "    #", "    #", "#   #", " ### "],
    "6": ["  ## ", " #   ", "#    ", "#### ", "#   #", "#   #", " ### "],
    "7": ["#####", "    #", "   # ", "  #  ", " #   ", " #   ", " #   "],
    "8": [" ### ", "#   #", "#   #", " ### ", "#   #", "#   #", " ### "],
    "9": [" ### ", "#   #", "#   #", " ####", "    #", "   # ", " ##  "],
    " ": ["     "] * 7,
    ".": ["     ", "     ", "     ", "     ", "     ", "  ## ", "  ## "],
    ",": ["     ", "     ", "     ", "     ", "  ## ", "  ## ", " #   "],
    ":": ["     ", "  ## ", "  ## ", "     ", "  ## ", "  ## ", "     "],
    ";": ["     ", "  ## ", "  ## ", "     ", "  ## ", "  ## ", " #   "],
    "-": ["     ", "     ", "     ", "#####", "     ", "     ", "     "],
    "+": ["     ", "  #  ", "  #  ", "#####", "  #  ", "  #  ", "     "],
    "/": ["    #", "    #", "   # ", "  #  ", " #   ", "#    ", "#    "],
    "#": [" # # ", " # # ", "#####", " # # ", "#####", " # # ", " # # "],
    "(": ["  #  ", " #   ", "#    ", "#    ", "#    ", " #   ", "  #  "],
    ")": ["  #  ", "   # ", "    #", "    #", "    #", "   # ", "  #  "],
    "'": ["  #  ", "  #  ", "     ", "     ", "     ", "     ", "     "],
    "?": [" ### ", "#   #", "    #", "   # ", "  #  ", "     ", "  #  "],
    "!": ["  #  ", "  #  ", "  #  ", "  #  ", "  #  ", "     ", "  #  "],
    "&": [" ##  ", "#  # ", "#  # ", " ##  ", "# # #", "#  # ", " ## #"],
    "=": ["     ", "     ", "#####", "     ", "#####", "     ", "     "],
    "<": ["   # ", "  #  ", " #   ", "#    ", " #   ", "  #  ", "   # "],
    ">": [" #   ", "  #  ", "   # ", "    #", "   # ", "  #  ", " #   "],
    "%": ["##  #", "## # ", "   # ", "  #  ", " #   ", "# ## ", "#  ##"],
}
CHAR_W = 6 * FONT_SCALE
LINE_H = 9 * FONT_SCALE


class Canvas:
    def __init__(self, w, h, bg=(24, 24, 28)):
        self.w, self.h = w, h
        self.px = bytearray(bytes(bg) * (w * h))

    def blit(self, x, y, w, h, rgb):
        for r in range(h):
            if 0 <= y + r < self.h:
                o = ((y + r) * self.w + x) * 3
                self.px[o:o + w * 3] = rgb[r * w * 3:(r + 1) * w * 3]

    def text(self, x, y, s, colour=(255, 255, 255)):
        for ch in s.upper():
            g = FONT.get(ch, FONT["?"])
            for r in range(7):
                for c in range(5):
                    if g[r][c] == "#":
                        self.rect(x + c * FONT_SCALE, y + r * FONT_SCALE, FONT_SCALE, FONT_SCALE, colour)
            x += CHAR_W

    def rect(self, x, y, w, h, colour):
        row = bytes(colour) * w
        for r in range(h):
            if 0 <= y + r < self.h:
                o = ((y + r) * self.w + x) * 3
                self.px[o:o + w * 3] = row

    def png(self, path):
        raw = b"".join(b"\x00" + bytes(self.px[r * self.w * 3:(r + 1) * self.w * 3]) for r in range(self.h))
        def chunk(tag, data):
            return struct.pack(">I", len(data)) + tag + data + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)
        with open(path, "wb") as f:
            f.write(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", self.w, self.h, 8, 2, 0, 0, 0)) + chunk(b"IDAT", zlib.compress(raw, 6)) + chunk(b"IEND", b""))


def frame_rgb(mov, frame, size):
    """One frame of a clip as rgb24 bytes at `size` (by frame number: exact on an all-intra clip)."""
    return subprocess.run([v2.FFMPEG, "-v", "error", "-i", mov, "-vf", "select=eq(n\\,%d),scale=%d:%d:flags=area" % (frame, size[0], size[1]), "-fps_mode", "passthrough", "-frames:v", "1", "-f", "rawvideo", "-pix_fmt", "rgb24", "-"], check=True, capture_output=True).stdout


def wrap(text, width):
    words, lines, cur = text.split(), [], ""
    for w in words:
        if cur and len(cur) + 1 + len(w) > width:
            lines.append(cur)
            cur = w
        else:
            cur = (cur + " " + w).strip()
    if cur:
        lines.append(cur)
    return lines


def sheet(mov, beats, hits, path):
    """One tile per beat of the text version, labelled bar.beat, the frame, and the hit that should be there."""
    gap, margin = 8, 12
    label_h = 4 * LINE_H + 6
    cell_w, cell_h = TILE[0] + gap, TILE[1] + label_h + gap
    cols = min(GRID_COLS, len(beats))
    rows = (len(beats) + cols - 1) // cols
    cv = Canvas(margin * 2 + cols * cell_w - gap, margin * 2 + rows * cell_h - gap)
    chars = TILE[0] // CHAR_W
    for i, (bar, beat, f) in enumerate(beats):
        x = margin + (i % cols) * cell_w
        y = margin + (i // cols) * cell_h
        rgb = frame_rgb(mov, f, TILE) if f >= 0 else b""
        if len(rgb) == TILE[0] * TILE[1] * 3:
            cv.blit(x, y, TILE[0], TILE[1], rgb)
        else:
            cv.rect(x, y, TILE[0], TILE[1], (60, 20, 20))
        ly = y + TILE[1] + 4
        key = "%d.%d" % (bar, beat)
        cv.text(x, ly, "%s  F%d" % (key, f), (255, 255, 255))
        h = hits.get(key)
        if h:
            for j, line in enumerate(wrap(str(h["what"]), chars)[:3]):
                cv.text(x, ly + (j + 1) * LINE_H, line, (255, 228, 92))
        else:
            cv.text(x, ly + LINE_H, "-", (120, 120, 120))
    cv.png(path)


def main(argv):
    if not argv:
        sys.exit("v2.py part N  (or a segment: 2a)")
    return build(argv[0])
