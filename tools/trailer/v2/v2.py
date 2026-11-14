#!/usr/bin/env python3
"""Trailer v2 ("Play for keeps"), one part at a time (docs/TRAILER.md -> v2).

  python3 -I tools/trailer/v2/v2.py music                 marketing/trailer/v2/music.wav from the storyboard's recipe, checked
  python3 -I tools/trailer/v2/v2.py conform <recording>   a phone recording -> 1080x2340, constant 60 fps, all-intra (+ .wav)
  python3 -I tools/trailer/v2/v2.py insets <conformed.mov> [--at S] [--ref clip.mov]
                                                           where the recording's HUD sits against the headless reference
  python3 -I tools/trailer/v2/v2.py part N                 build part N's deliverables from its clips and report the hits
  python3 -I tools/trailer/v2/v2.py overlays               every text card as its own transparent PNG (full frame + tight crop)

The plan is tools/trailer/v2/storyboard.json: 18 bars at 110 BPM, 60 fps,
2356 frames, every boundary round(t * 60) on the GLOBAL timeline (a bar is
130.9 frames), so a part's length is its end_frame - start_frame and never
computed here. The master is 1080 x 2340. Headless frames (1440 x 3120, the
720 x 1560 layout at 2x) are downscaled once with the area filter; phone
recordings are conformed to the master first. Stdlib only.
"""
import json, math, os, struct, subprocess, sys, zlib

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
V2 = os.path.join(ROOT, "tools", "trailer", "v2")
STORY = os.path.join(V2, "storyboard.json")
OUT = os.path.join(ROOT, "marketing", "trailer", "v2")
FFMPEG = "/opt/homebrew/bin/ffmpeg"
FFPROBE = "/opt/homebrew/bin/ffprobe"
FPS = 60
MASTER = (1080, 2340)
HEADLESS = (1440, 3120)          # 2x the 720 x 1560 layout (tools/trailer/capture.sh appstore)
DESIGN_SCALE = MASTER[0] / 720.0  # 1.5 master px per design px
# The iPhone 16's insets in design px (59 pt / 34 pt at 3x, scaled by 720 / 1179): what the headless renders use.
SAFE_TOP, SAFE_BOTTOM = 108, 62
# UiLayout.hud_map with those: the HUD's top row and the music row, in design px (ui_layout.gd).
HUD_TOP_ROW = max(32, SAFE_TOP + 6)
HUD_MUSIC_ROW = round(2556 * 720 / 1179) - max(32, SAFE_BOTTOM + 6) - 56
MEZZ = ["-c:v", "libx264", "-preset", "fast", "-crf", "10", "-g", "1", "-pix_fmt", "yuv420p"]


def story():
    return json.load(open(STORY))


def run(cmd, capture=False):
    r = subprocess.run(cmd, check=True, capture_output=capture, text=capture)
    return r.stdout if capture else None


def probe(path, entries, select=None):
    cmd = [FFPROBE, "-v", "error"]
    if select:
        cmd += ["-select_streams", select]
    cmd += ["-show_entries", entries, "-of", "json", path]
    return json.loads(run(cmd, capture=True))


def count_frames(path):
    out = run([FFPROBE, "-v", "error", "-count_frames", "-select_streams", "v:0", "-show_entries", "stream=nb_read_frames", "-of", "csv=p=0", path], capture=True)
    return int(out.strip().split(",")[0])


def wav_frames(path):
    """A wav's length in video frames (60 fps), from its sample count."""
    s = probe(path, "stream=duration_ts,sample_rate", "a:0")["streams"][0]
    return int(s["duration_ts"]) / float(s["sample_rate"]) * FPS


# ---- music -----------------------------------------------------------------------------


def music():
    """The storyboard's recipe (song bars 3-16, then bars 5-8 fading out over 4 bars, qsin),
    resampled to 48 kHz and trimmed to exactly total_frames frames."""
    sb = story()
    total = int(sb["timing"]["total_frames"])
    src = os.path.join(ROOT, sb["music"]["source"])
    dst = os.path.join(OUT, "music.wav")
    os.makedirs(OUT, exist_ok=True)
    recipe = sb["music"]["ffmpeg"]
    # The recipe's filter graph, verbatim, between -filter_complex " and ".
    graph = recipe.split('-filter_complex "', 1)[1].split('"', 1)[0]
    # The song is 34.907 s (the JSON says 34.909), so the concat runs ~39.270 s = 2356.2 frames:
    # the master is 2356 frames, so the stem is trimmed there, at 48 kHz (the mix's rate).
    graph = graph.replace("[out]", "[cat];[cat]aresample=48000,atrim=end=%.6f[out]" % (total / FPS))
    run([FFMPEG, "-y", "-loglevel", "error", "-i", src, "-filter_complex", graph, "-map", "[out]", "-c:a", "pcm_s24le", dst])
    n = wav_frames(dst)
    ok = abs(n - total) <= 0.5
    print("music.wav: %.2f frames = %.4f s (the storyboard: %d frames, %.3f s) -> %s" % (n, n / FPS, total, float(sb["timing"]["total_s"]), "OK" if ok else "WRONG LENGTH"))
    print("  " + dst)
    return 0 if ok else 1


# ---- conform ---------------------------------------------------------------------------


def frame_times(path, limit=900):
    out = run([FFPROBE, "-v", "error", "-select_streams", "v:0", "-show_entries", "frame=pts_time", "-of", "csv=p=0", "-read_intervals", "%%+#%d" % limit, path], capture=True)
    ts = [float(x.split(",")[0]) for x in out.split() if x.strip() and x.split(",")[0] not in ("N/A", "")]
    return ts


def conform(path, part=None):
    """A phone recording to the master: 1080 wide, the last pixels cropped or padded to 2340,
    iOS's variable frame rate made a constant 60, all-intra crf 10; its audio as a wav too."""
    sb = story()
    v = probe(path, "stream=width,height,r_frame_rate,avg_frame_rate,nb_frames,duration", "v:0")["streams"][0]
    w, h = int(v["width"]), int(v["height"])
    ts = frame_times(path)
    deltas = [b - a for a, b in zip(ts, ts[1:])]
    spread = (max(deltas) - min(deltas)) * 1000.0 if deltas else 0.0
    known = {(1179, 2556): "iPhone 16", (828, 1792): "iPhone XR", HEADLESS: "headless render"}
    who = known.get((w, h), "not in the storyboard's screen_sizes table")
    sw = MASTER[0]
    sh = int(round(h * sw / w / 2.0)) * 2
    flags = "lanczos" if w < sw else "area"
    fit = ("scale=%d:%d:flags=%s" % (sw, sh, flags))
    if sh >= MASTER[1]:
        fit += ",crop=%d:%d:0:%d" % (MASTER[0], MASTER[1], (sh - MASTER[1]) // 2)
        edge = "crop %d px" % (sh - MASTER[1])
    else:
        fit += ",pad=%d:%d:0:%d" % (MASTER[0], MASTER[1], (MASTER[1] - sh) // 2)
        edge = "pad %d px" % (MASTER[1] - sh)
    if part is None:
        parent = os.path.basename(os.path.dirname(os.path.abspath(path)))
        part = parent if parent.startswith("part") else "misc"
    dst_dir = os.path.join(OUT, "conform", part)
    os.makedirs(dst_dir, exist_ok=True)
    name = os.path.splitext(os.path.basename(path))[0]
    mov = os.path.join(dst_dir, name + ".mov")
    wav = os.path.join(dst_dir, name + ".wav")
    has_audio = bool(probe(path, "stream=index", "a")["streams"])
    cmd = [FFMPEG, "-y", "-loglevel", "error", "-i", path, "-vf", fit + ",fps=%d,setsar=1" % FPS, "-fps_mode", "cfr", "-r", str(FPS)] + MEZZ
    cmd += (["-c:a", "pcm_s16le", "-ar", "48000", "-ac", "2"] if has_audio else ["-an"]) + [mov]
    run(cmd)
    if has_audio:
        run([FFMPEG, "-y", "-loglevel", "error", "-i", path, "-vn", "-c:a", "pcm_s16le", "-ar", "48000", "-ac", "2", wav])
    n = count_frames(mov)
    o = probe(mov, "stream=width,height,r_frame_rate", "v:0")["streams"][0]
    print("conform %s" % path)
    print("  in : %dx%d (%s), %s fps avg, %d frames sampled, frame-gap spread %.2f ms%s" % (w, h, who, v.get("avg_frame_rate"), len(ts), spread, " (variable)" if spread > 1.0 else ""))
    print("  fit: %s (%s, %s)" % (fit.split(",fps")[0], "x%.3f" % (sw / w), edge))
    print("  out: %sx%s %s fps, %d frames (%.3f s)%s" % (o["width"], o["height"], o["r_frame_rate"], n, n / FPS, "" if has_audio else ", no audio"))
    print("  " + mov + (("\n  " + wav) if has_audio else ""))
    return 0


# ---- insets ----------------------------------------------------------------------------


def gray_frame(path, at_s, size):
    """One frame as 8-bit gray rows, scaled to `size`."""
    raw = subprocess.run([FFMPEG, "-v", "error", "-ss", "%.3f" % at_s, "-i", path, "-frames:v", "1", "-vf", "scale=%d:%d:flags=area" % size, "-f", "rawvideo", "-pix_fmt", "gray", "-"], check=True, capture_output=True).stdout
    w, h = size
    assert len(raw) == w * h, "frame read: %d bytes for %dx%d" % (len(raw), w, h)
    mv = memoryview(raw)
    return [sum(mv[r * w:(r + 1) * w]) / float(w) for r in range(h)]


def best_shift(rec, ref, rows, span=90):
    """The vertical offset (master px) that lays the recording's row profile over the reference's in `rows`."""
    a, b = rows
    best, best_s = None, 0
    for s in range(-span, span + 1):
        err = 0.0
        for r in range(a, b):
            rr = r + s
            if 0 <= rr < len(rec):
                err += abs(rec[rr] - ref[r])
            else:
                err += 255.0
        if best is None or err < best:
            best, best_s = err, s
    return best_s


def insets(path, at_s=None, ref=None):
    """Where a recording's HUD sits against the headless reference (hud_ref.mov at the iPhone 16's insets):
    a side-by-side with a 50/50 blend, and the safe-top/bottom the recording implies."""
    ref = ref or os.path.join(OUT, "clips", "hud_ref.mov")
    if not os.path.exists(ref):
        sys.exit("no reference clip %s (tools/trailer/v2/capture.sh hud_ref)" % ref)
    if at_s is None:
        dur = float(probe(path, "format=duration")["format"]["duration"])
        at_s = dur / 2.0
    rec = gray_frame(path, at_s, MASTER)
    rf = gray_frame(ref, 0.0, MASTER)
    top_row = int(round(HUD_TOP_ROW * DESIGN_SCALE))
    music_row = int(round(HUD_MUSIC_ROW * DESIGN_SCALE))
    s_top = best_shift(rec, rf, (top_row - 60, top_row + 300))
    s_bot = best_shift(rec, rf, (music_row - 200, music_row + 84 + 60))
    os.makedirs(os.path.join(OUT, "insets"), exist_ok=True)
    name = os.path.splitext(os.path.basename(path))[0]
    png = os.path.join(OUT, "insets", name + "_insets.png")
    run([FFMPEG, "-y", "-loglevel", "error", "-ss", "%.3f" % at_s, "-i", path, "-i", ref, "-filter_complex",
         "[0:v]trim=end_frame=1,scale=%d:%d:flags=area,setsar=1,split[r1][r2];[1:v]trim=end_frame=1,scale=%d:%d:flags=area,setsar=1,split[f1][f2];[r1][f1]blend=all_mode=average[m];[r2][m][f2]hstack=3,scale=iw/2:-2[o]" % (MASTER + MASTER),
         "-map", "[o]", "-frames:v", "1", png])
    print("insets %s (frame at %.2f s) vs %s" % (path, at_s, os.path.basename(ref)))
    print("  reference HUD: top row y=%d, music row y=%d (master px; design %d / %d at --qa-safe-top=%d --qa-safe-bottom=%d)" % (top_row, music_row, HUD_TOP_ROW, HUD_MUSIC_ROW, SAFE_TOP, SAFE_BOTTOM))
    print("  recording's HUD sits %+d px (top band) / %+d px (bottom band) from the reference" % (s_top, s_bot))
    sug_top = SAFE_TOP + s_top / DESIGN_SCALE
    sug_bot = SAFE_BOTTOM - s_bot / DESIGN_SCALE
    verdict = "the headless insets line up (within 2 px)" if abs(s_top) <= 2 and abs(s_bot) <= 2 else "render with --qa-safe-top=%.0f --qa-safe-bottom=%.0f instead" % (sug_top, sug_bot)
    print("  -> " + verdict)
    print("  recording | blend | reference: " + png)
    return 0


# ---- overlays: the text cards as transparent PNGs ----------------------------------------


def alpha_bbox(path, size):
    """The opaque box of an RGBA PNG: (x0, y0, x1, y1) inclusive, or None when fully clear."""
    w, h = size
    raw = subprocess.run([FFMPEG, "-v", "error", "-i", path, "-filter_complex", "alphaextract", "-f", "rawvideo", "-pix_fmt", "gray", "-"],
                         check=True, capture_output=True).stdout
    rows = [y for y in range(h) if any(raw[y * w:(y + 1) * w])]
    if not rows:
        return None
    cols = [x for x in range(w) if any(raw[y * w + x] for y in range(rows[0], rows[-1] + 1))]
    return cols[0], rows[0], cols[-1], rows[-1]


def overlays():
    """Each part's settled text card (cards/stills/partNN.png, rendered by the game at 2x with a
    clear background) as its own PNG for Ross to lay over his own edit: the full 1080 x 2340
    master frame with the card where the pipeline puts it (drop it on as a cutaway at 100 %),
    and a tight crop with a 24 px margin for placing by hand. Part 4's card moves at its cut,
    so it gets both placements; part 8 is the end card (badge slot empty until the file exists)."""
    sb = story()
    out = os.path.join(OUT, "overlays")
    os.makedirs(out, exist_ok=True)
    for old in os.listdir(out):
        if old.endswith(".png"):
            os.remove(os.path.join(out, old))
    margin = 24
    jobs = []
    for p in sb["parts"]:
        pid = "part%02d" % p["part"]
        still = os.path.join(OUT, "cards", "stills", pid + ".png")
        if not os.path.exists(still):
            print("%s: no still (run tools/trailer/v2/cards.sh %d)" % (pid, p["part"]))
            continue
        text = p.get("text") or "end card"
        slug = "".join(c if c.isalnum() else "_" for c in text.lower().replace(" · ", " ")).strip("_")
        while "__" in slug:
            slug = slug.replace("__", "_")
        jobs.append((pid, slug, still))
        for m in p.get("card_y") or []:
            # the moved placement: a settled frame of the sequence after the move (fades take 45 frames)
            card_in = min([h["part_frame"] for h in p.get("hits", []) if "text card in" in h.get("what", "")] or [0])
            i = int(m["part_frame"]) - card_in + 45
            frame = os.path.join(OUT, "cards", pid, "f%04d.png" % i)
            if os.path.exists(frame):
                jobs.append((pid, slug + "_moved_y%d" % int(m["y"]), frame))
            else:
                print("%s: no sequence frame %d for the card_y move" % (pid, i))
    for pid, slug, src in jobs:
        box = alpha_bbox(src, HEADLESS)
        if box is None:
            print("%s: the still is fully transparent, skipped" % pid)
            continue
        full = os.path.join(out, "%s_%s.png" % (pid, slug))
        run([FFMPEG, "-v", "error", "-y", "-i", src, "-vf", "scale=%d:%d:flags=lanczos" % MASTER, "-pix_fmt", "rgba", "-frames:v", "1", full])
        x0, y0, x1, y1 = box
        x0, y0 = max(0, x0 - margin), max(0, y0 - margin)
        x1, y1 = min(HEADLESS[0] - 1, x1 + margin), min(HEADLESS[1] - 1, y1 + margin)
        cw, ch = x1 - x0 + 1, y1 - y0 + 1
        crop = os.path.join(out, "%s_%s_crop.png" % (pid, slug))
        run([FFMPEG, "-v", "error", "-y", "-i", src, "-vf", "crop=%d:%d:%d:%d,scale=%d:-1:flags=lanczos" % (cw, ch, x0, y0, round(cw * MASTER[0] / HEADLESS[0])),
             "-pix_fmt", "rgba", "-frames:v", "1", crop])
        mx, my = round(x0 * MASTER[0] / HEADLESS[0]), round(y0 * MASTER[1] / HEADLESS[1])
        print("%-44s full %dx%d; crop %dx%d sits at master (%d, %d)  [%s]" % (os.path.basename(full), MASTER[0], MASTER[1],
              round(cw * MASTER[0] / HEADLESS[0]), round(ch * MASTER[1] / HEADLESS[1]), mx, my, os.path.basename(crop)))
    print("-> %s" % out)
    return 0


# ---- main ------------------------------------------------------------------------------


def main(argv):
    if not argv:
        print(__doc__)
        return 1
    cmd, rest = argv[0], argv[1:]
    if cmd == "music":
        return music()
    if cmd == "conform":
        part = None
        if "--part" in rest:
            i = rest.index("--part")
            part = rest[i + 1]
            rest = rest[:i] + rest[i + 2:]
        return max([conform(p, part) for p in rest] or [1])
    if cmd == "insets":
        at = None
        ref = None
        if "--at" in rest:
            i = rest.index("--at")
            at = float(rest[i + 1])
            rest = rest[:i] + rest[i + 2:]
        if "--ref" in rest:
            i = rest.index("--ref")
            ref = rest[i + 1]
            rest = rest[:i] + rest[i + 2:]
        return insets(rest[0], at, ref)
    if cmd == "part":
        try:
            import v2_part   # noqa: F401  (tools/trailer/v2/v2_part.py, part 1 onward)
        except ImportError:
            sys.exit("part building arrives with part 1")
        return v2_part.main(rest)
    if cmd == "overlays":
        return overlays()
    print(__doc__)
    return 1


if __name__ == "__main__":
    sys.path.insert(0, V2)
    sys.exit(main(sys.argv[1:]))
