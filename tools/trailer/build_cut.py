#!/usr/bin/env python3
"""Build a trailer cut from tools/trailer/edit.json (docs/TRAILER.md -> The edit).

  python3 -I tools/trailer/build_cut.py appstore            the final App Store preview
  python3 -I tools/trailer/build_cut.py social --draft      a 960-high draft (Checkpoint B)
  python3 -I tools/trailer/build_cut.py appstore --check    ffprobe the built file against the spec
  python3 -I tools/trailer/build_cut.py --validate          check the edit data only (no ffmpeg)
  python3 -I tools/trailer/build_cut.py --barmap            print each cut's bar map

The edit is data: every entry lands on a bar.beat of the music (110 BPM, 4/4),
a hard cut. Footage comes from marketing/trailer/clips/<layout>/<shot>.mov
(60 fps, 2x the layout, captured by tools/trailer/capture.sh) with its SFX wav
and marks; text cards are PNG sequences the game rendered
(marketing/trailer/cards/<layout>/<id>/). ffmpeg only trims, scales, lays the
cards over, and mixes: the music at full length, the game's SFX under it and
lower still while a card is up, the last bar faded. Stdlib only.
"""
import json, os, subprocess, sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT = os.path.join(ROOT, "marketing", "trailer")
EDIT = os.path.join(ROOT, "tools", "trailer", "edit.json")
SHOTS = os.path.join(ROOT, "tools", "trailer", "shots")
FFMPEG = "/opt/homebrew/bin/ffmpeg"
FFPROBE = "/opt/homebrew/bin/ffprobe"
SRC_FPS = 60
BANNED = ["physics", "realistic", "roguelite", "roguelike", "ultimate", "experience", "immersive", "next-level", "revolutionary", "deckbuilder"]
MAX_CARDS = 6


def beat_time(edit, pos):
    """Seconds at "bar.beat" (both from 1; the beat may be fractional: "4.2.5" is bar 4, beat 2.5)."""
    bar, _, beat = str(pos).partition(".")
    beats = (int(bar) - 1) * 4 + (float(beat or 1) - 1.0)
    return beats * 60.0 / float(edit["bpm"])


def frame_at(edit, pos, fps):
    return int(round(beat_time(edit, pos) * fps))


def cut_plan(edit, name):
    """The cut as frame-exact segments and cards (output frames at the cut's fps)."""
    cut = edit["cuts"][name]
    fps = int(cut["fps"])
    end = frame_at(edit, "%d.1" % (int(cut["bars"]) + 1), fps)
    tl = cut["timeline"]
    segs = []
    for i, e in enumerate(tl):
        a = frame_at(edit, e["at"], fps)
        b = frame_at(edit, tl[i + 1]["at"], fps) if i + 1 < len(tl) else end
        segs.append({"clip": e.get("clip"), "file": e.get("file"), "a": a, "b": b, "from": e.get("from", "in"), "sfx": float(e.get("sfx", 1.0))})
    cards = []
    for c in cut.get("cards", []):
        a = frame_at(edit, c["at"], fps)
        b = frame_at(edit, c["until"], fps)
        cards.append({"id": c["id"], "text": c.get("text", ""), "a": a, "b": b})
    return {"fps": fps, "frames": end, "seconds": end / fps, "segs": segs, "cards": cards, "cut": cut}


def problems(edit):
    """Everything wrong with the edit data ([] when it is sound)."""
    out = []
    for name, cut in edit.get("cuts", {}).items():
        plan = cut_plan(edit, name)
        last = -1
        for s in plan["segs"]:
            if s["a"] <= last:
                out.append("%s: entries out of order at frame %d" % (name, s["a"]))
            if s["b"] <= s["a"]:
                out.append("%s: an empty segment at frame %d" % (name, s["a"]))
            last = s["a"]
            if s["clip"]:
                path = os.path.join(SHOTS, s["clip"] + ".json")
                if not os.path.exists(path):
                    out.append("%s: no shot file for clip '%s'" % (name, s["clip"]))
                elif cut["layout"] == "appstore":
                    shot = json.load(open(path))
                    if any(st.get("do") in ("camera", "hud") for st in shot.get("steps", [])):
                        out.append("%s: '%s' uses the rim camera (the App Store cut is the shooting view only)" % (name, s["clip"]))
            elif not s["file"]:
                out.append("%s: an entry with no clip and no file at frame %d" % (name, s["a"]))
        worded = [c for c in plan["cards"] if c["text"]]
        if len(worded) > MAX_CARDS:
            out.append("%s: %d text cards (at most %d plus the end card)" % (name, len(worded), MAX_CARDS))
        for c in worded:
            words = c["text"].replace("\n", " ").split()
            if not 2 <= len(words) <= 4:
                out.append("%s: card '%s' has %d words (2-4)" % (name, c["id"], len(words)))
            if c["text"] != c["text"].upper():
                out.append("%s: card '%s' is not all caps" % (name, c["id"]))
            low = c["text"].lower()
            for w in BANNED:
                if w in low:
                    out.append("%s: card '%s' uses the banned word '%s'" % (name, c["id"], w))
            if c["b"] <= c["a"]:
                out.append("%s: card '%s' ends before it starts" % (name, c["id"]))
        if cut["layout"] == "appstore":
            if not 15.0 <= plan["seconds"] <= 30.0:
                out.append("%s: %.2f s (an App Preview is 15-30 s)" % (name, plan["seconds"]))
            if int(cut["fps"]) > 30:
                out.append("%s: %d fps (an App Preview is at most 30)" % (name, int(cut["fps"])))
    return out


def barmap(edit, name):
    plan = cut_plan(edit, name)
    lines = ["%s: %d bars, %.2f s at %d fps (%d frames)" % (name, int(plan["cut"]["bars"]), plan["seconds"], plan["fps"], plan["frames"])]
    tl = plan["cut"]["timeline"]
    for e, s in zip(tl, plan["segs"]):
        card = next((c["text"].replace("\n", " ") for c, raw in zip(plan["cards"], plan["cut"].get("cards", [])) if c["a"] <= s["a"] < c["b"] and c["text"]), "")
        lines.append("  %-7s %6.2fs  %3d fr  %-16s %s" % (e["at"], s["a"] / plan["fps"], s["b"] - s["a"], s["clip"] or os.path.basename(s["file"] or "?"), ("[" + card + "]") if card else ""))
    return "\n".join(lines)


def marks_of(layout, clip):
    path = os.path.join(OUT, "clips", layout, clip + ".marks.json")
    return json.load(open(path))["marks"] if os.path.exists(path) else {}


def src_frame(marks, spec):
    """A source frame from "in", "poster", "in+0.5", "poster-0.3" (seconds), counted from the movie's first frame."""
    name, off = spec, 0.0
    for sign in "+-":
        if sign in spec[1:]:
            i = spec.rindex(sign)
            name, off = spec[:i], float(spec[i:])
            break
    return int(marks.get(name, 0)) + int(round(off * SRC_FPS))


def build(edit, name, draft):
    plan = cut_plan(edit, name)
    cut = plan["cut"]
    layout, fps = cut["layout"], plan["fps"]
    w, h = cut["size"]
    if draft:
        w, h = int(round(w * 960 / h / 2)) * 2, 960
    inputs, vf, af = [], [], []
    def add_input(args):
        inputs.append(args)
        return len(inputs) - 1
    seen = {}
    vlabels, alabels = [], []
    for i, s in enumerate(plan["segs"]):
        n = s["b"] - s["a"]
        if s["clip"]:
            mov = os.path.join(OUT, "clips", layout, s["clip"] + ".mov")
            wav = os.path.join(OUT, "clips", layout, s["clip"] + ".wav")
            if not os.path.exists(mov):
                sys.exit("missing clip: %s (capture it with tools/trailer/capture.sh)" % mov)
            if s["clip"] not in seen:
                seen[s["clip"]] = (add_input(["-i", mov]), add_input(["-i", wav]))
            vi, ai = seen[s["clip"]]
            f0 = src_frame(marks_of(layout, s["clip"]), s["from"])
            step = SRC_FPS // fps
            vf.append("[%d:v]trim=start_frame=%d:end_frame=%d,setpts=PTS-STARTPTS,fps=%d,scale=%d:%d:flags=area,setsar=1[v%d]" % (vi, f0, f0 + n * step, fps, w, h, i))
            t0, t1 = f0 / SRC_FPS, (f0 + n * step) / SRC_FPS
            af.append("[%d:a]atrim=start=%.5f:end=%.5f,asetpts=PTS-STARTPTS,aresample=48000,volume=%.3f[a%d]" % (ai, t0, t1, s["sfx"], i))
        else:
            path = os.path.join(ROOT, s["file"])
            if os.path.exists(path):
                vi = add_input(["-i", path])
                vf.append("[%d:v]trim=duration=%.5f,setpts=PTS-STARTPTS,fps=%d,scale=%d:%d:force_original_aspect_ratio=increase:flags=lanczos,crop=%d:%d,setsar=1[v%d]" % (vi, n / fps, fps, w, h, w, h, i))
            else:   # a slot not filled yet (the filmed hand): black, so the draft still times out
                vi = add_input(["-f", "lavfi", "-i", "color=c=black:s=%dx%d:r=%d:d=%.5f" % (w, h, fps, n / fps)])
                vf.append("[%d:v]setsar=1[v%d]" % (vi, i))
            ai = add_input(["-f", "lavfi", "-i", "anullsrc=r=48000:cl=stereo:d=%.5f" % (n / fps)])
            af.append("[%d:a]atrim=duration=%.5f[a%d]" % (ai, n / fps, i))
        vlabels.append("[v%d]" % i)
        alabels.append("[a%d]" % i)
    vf.append("%sconcat=n=%d:v=1:a=0[vcat]" % ("".join(vlabels), len(vlabels)))
    af.append("%sconcat=n=%d:v=0:a=1[sfx0]" % ("".join(alabels), len(alabels)))
    # The cards the game rendered, laid over at their beats.
    cur = "[vcat]"
    duck = []
    for k, c in enumerate(plan["cards"]):
        seq = os.path.join(OUT, "cards", layout, c["id"], "f%04d.png")
        if not os.path.exists(seq % 0):
            sys.exit("missing card frames: %s (render them: tools/trailer/cards.sh %s)" % (os.path.dirname(seq), layout))
        ci = add_input(["-framerate", str(SRC_FPS), "-i", seq])
        t0, t1 = c["a"] / fps, c["b"] / fps
        vf.append("[%d:v]fps=%d,scale=%d:%d:flags=area,setpts=PTS+%.5f/TB[c%d]" % (ci, fps, w, h, t0, k))
        vf.append("%s[c%d]overlay=0:0:eof_action=pass:enable='between(t,%.5f,%.5f)'[vo%d]" % (cur, k, t0, t1, k))
        cur = "[vo%d]" % k
        if c["text"]:
            duck.append("between(t,%.3f,%.3f)" % (t0, t1))
    total = plan["seconds"]
    mi = add_input(["-stream_loop", "-1", "-i", os.path.join(ROOT, edit["music"])])
    fade = 4 * 60.0 / float(edit["bpm"]) * float(cut.get("fade_bars", 1.0))
    sfx_gain = float(cut.get("sfx_db", -5.0))
    duck_db = float(cut.get("duck_db", -6.0))
    duck_expr = ("volume='if(%s,%.4f,1)':eval=frame," % ("+".join(duck), 10 ** (duck_db / 20.0))) if duck else ""
    af.append("[sfx0]%svolume=%.2fdB[sfx]" % (duck_expr, sfx_gain))
    af.append("[%d:a]atrim=duration=%.5f,aresample=48000,volume=%.2fdB,afade=t=out:st=%.5f:d=%.5f[mus]" % (mi, total, float(cut.get("music_db", -3.0)), total - fade, fade))
    af.append("[mus][sfx]amix=inputs=2:normalize=0:duration=first,loudnorm=I=%.1f:TP=-1.5:LRA=11[aout]" % float(cut.get("lufs", -14.0)))
    tag = "draft" if draft else "final"
    os.makedirs(os.path.join(OUT, tag), exist_ok=True)
    dst = os.path.join(OUT, tag, "hoop_shoot_%s%s.mp4" % (name, "_draft" if draft else ""))
    cmd = [FFMPEG, "-y", "-loglevel", "error"]
    for a in inputs:
        cmd += a
    cmd += ["-filter_complex", ";".join(vf + af), "-map", cur, "-map", "[aout]", "-t", "%.5f" % total, "-r", str(fps),
            "-c:v", "libx264", "-pix_fmt", "yuv420p", "-movflags", "+faststart", "-c:a", "aac", "-b:a", "256k", "-ar", "48000", "-ac", "2"]
    if draft:
        cmd += ["-preset", "veryfast", "-crf", "20"]
    elif layout == "appstore":   # Apple: H.264 High 4.0, 10-12 Mbps
        cmd += ["-profile:v", "high", "-level:v", "4.0", "-preset", "slow", "-b:v", "11M", "-minrate", "10M", "-maxrate", "12M", "-bufsize", "12M", "-x264-params", "nal-hrd=cbr"]
    else:
        cmd += ["-profile:v", "high", "-level:v", "4.2", "-preset", "slow", "-crf", "15", "-maxrate", "30M", "-bufsize", "40M"]
    cmd.append(dst)
    subprocess.run(cmd, check=True)
    print("built %s (%.2f s, %dx%d @ %d fps)" % (dst, total, w, h, fps))
    return dst


def check(edit, name):
    """ffprobe the final against the cut's spec; a list of failures ([] when it passes)."""
    cut = edit["cuts"][name]
    path = os.path.join(OUT, "final", "hoop_shoot_%s.mp4" % name)
    if not os.path.exists(path):
        return ["not built: %s" % path]
    info = json.loads(subprocess.run([FFPROBE, "-v", "error", "-show_format", "-show_streams", "-of", "json", path], capture_output=True, text=True, check=True).stdout)
    v = next(s for s in info["streams"] if s["codec_type"] == "video")
    a = next(s for s in info["streams"] if s["codec_type"] == "audio")
    dur = float(info["format"]["duration"])
    num, den = v["avg_frame_rate"].split("/")
    fps = float(num) / float(den)
    vbr = float(v.get("bit_rate", 0)) / 1e6
    abr = float(a.get("bit_rate", 0)) / 1e3
    size = os.path.getsize(path) / 1e6
    report = {"file": path, "seconds": round(dur, 2), "size_mb": round(size, 1), "video": "%s %s L%.1f %dx%d %.2f fps %.1f Mbps %s" % (v["codec_name"], v.get("profile"), int(v.get("level", 0)) / 10.0, v["width"], v["height"], fps, vbr, v.get("field_order", "progressive")),
              "audio": "%s %d ch %s Hz %.0f kbps" % (a["codec_name"], a["channels"], a["sample_rate"], abr)}
    print(json.dumps(report, indent=1))
    bad = []
    if [v["width"], v["height"]] != list(cut["size"]):
        bad.append("size %dx%d, wanted %dx%d" % (v["width"], v["height"], cut["size"][0], cut["size"][1]))
    if abs(fps - int(cut["fps"])) > 0.01:
        bad.append("%.2f fps, wanted %d" % (fps, int(cut["fps"])))
    if v["codec_name"] != "h264" or a["codec_name"] != "aac" or a["channels"] != 2 or a["sample_rate"] != "48000":
        bad.append("codecs: want H.264 + AAC stereo 48 kHz")
    if v.get("field_order", "progressive") != "progressive":
        bad.append("not progressive")
    if cut["layout"] == "appstore":
        if not 15.0 <= dur <= 30.0:
            bad.append("%.2f s (15-30)" % dur)
        if not 10.0 <= vbr <= 12.0:
            bad.append("video %.1f Mbps (10-12)" % vbr)
        if v.get("profile") != "High" or int(v.get("level", 0)) > 40:
            bad.append("profile %s level %s (High, up to 4.0)" % (v.get("profile"), v.get("level")))
        if abs(abr - 256) > 24:
            bad.append("audio %.0f kbps (256)" % abr)
        if size > 500:
            bad.append("%.0f MB (500 at most)" % size)
    return bad


def main(argv):
    edit = json.load(open(EDIT))
    if "--validate" in argv:
        bad = problems(edit)
        print("\n".join(bad) if bad else "edit.json is sound")
        return 1 if bad else 0
    if "--barmap" in argv:
        for name in edit["cuts"]:
            print(barmap(edit, name))
        return 0
    names = [a for a in argv if not a.startswith("--")]
    if len(names) != 1 or names[0] not in edit["cuts"]:
        print(__doc__)
        return 1
    if "--check" in argv:
        bad = check(edit, names[0])
        print("\n".join("FAIL " + b for b in bad) if bad else "PASS: meets the spec")
        return 1 if bad else 0
    bad = problems(edit)
    if bad:
        print("\n".join(bad))
        return 1
    build(edit, names[0], "--draft" in argv)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
