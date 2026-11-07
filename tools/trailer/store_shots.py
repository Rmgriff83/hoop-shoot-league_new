#!/usr/bin/env python3
"""App Store screenshots from the trailer's 2x App Store clips (docs/TRAILER.md ->
Store screenshots): one movie frame per screenshot, downscaled once (area) to
1290 x 2796 (the 6.9" slot; the 720 x 1560 layout's own shape), in two sets:

  marketing/trailer/store/clean/      the frame alone
  marketing/trailer/store/captioned/  the frame with the trailer's text card

The captions are the cards tools/trailer/cards.sh rendered with the game's own
panel and type (option A copy). Run after capture_all.sh appstore and cards.sh
appstore; no Godot run of its own.

  python3 -I tools/trailer/store_shots.py
"""
import os, subprocess, sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import build_cut as bc

CLIPS = os.path.join(bc.OUT, "clips", "appstore")
CARDS = os.path.join(bc.OUT, "checkpoint_a", "cards", "appstore")
DST = os.path.join(bc.OUT, "store")
W, H = 1440, 3120            # the clips: 2x the 720 x 1560 layout
OUT_W, OUT_H = 1290, 2796    # Apple's 6.9" iPhone slot
CARD_Y = 2018                # where a card's panel sits in its 1440 x 3120 still

# name, card, frames ([clip, frame], or four of them for the 2 x 2 grid), and
# where the card's panel goes (2x px from the top; None = where the trailer has it).
SHOTS = [
    ("01_flick", "hook", [("flick_hard", 76)], 2300),
    ("02_courts", "courts", [("tour_cage", 78), ("tour_beach", 78), ("tour_park", 78), ("tour_city", 78)], 1450),
    ("03_league", "league", [("league_title", 223)], 2130),
    ("04_cards", "cards", [("card_pick", 108)], 2560),
    ("05_online", "online", [("ranked_faceoff", 150)], 2240),
    ("06_yours", "yours", [("locker_cycle", 114)], 2580),
]


def frame_inputs(frames):
    args = []
    for clip, n in frames:
        args += ["-i", os.path.join(CLIPS, clip + ".mov")]
    return args


def picture(frames):
    """The filter graph's [pic]: one frame, or four in a 2 x 2 grid with a black gutter."""
    if len(frames) == 1:
        clip, n = frames[0]
        return "[0:v]select=eq(n\\,%d),setpts=PTS-STARTPTS[pic];" % n
    g = 12  # gutter, 2x px
    cw, ch = (W - g) // 2, (H - g) // 2
    fc = ""
    for i, (clip, n) in enumerate(frames):
        fc += "[%d:v]select=eq(n\\,%d),setpts=PTS-STARTPTS,scale=%d:%d:flags=area[q%d];" % (i, n, cw, ch, i)
    fc += "[q0][q1][q2][q3]xstack=inputs=4:layout=0_0|%d_0|0_%d|%d_%d:fill=black,pad=%d:%d:0:0:black[pic];" % (cw + g, ch + g, cw + g, ch + g, W, H)
    return fc


def render(name, card, frames, card_y, captioned):
    out = os.path.join(_dst(), "captioned" if captioned else "clean", name + ".png")
    os.makedirs(os.path.dirname(out), exist_ok=True)
    cmd = [bc.FFMPEG, "-y", "-loglevel", "error"] + frame_inputs(frames)
    fc = picture(frames)
    if captioned:
        cmd += ["-i", os.path.join(CARDS, card + ".png")]
        dy = 0 if card_y is None else card_y - CARD_Y
        fc += "[pic][%d:v]overlay=0:%d[pic2];" % (len(frames), dy)
        last = "pic2"
    else:
        last = "pic"
    # Other slots' sizes differ in shape by < 0.3 %: fill, then trim the few px over.
    fc += "[%s]scale=%d:%d:force_original_aspect_ratio=increase:flags=area,crop=%d:%d,format=rgb24" % (last, OUT_W, OUT_H, OUT_W, OUT_H)
    subprocess.run(cmd + ["-filter_complex", fc, "-frames:v", "1", out], check=True)
    return out


def sheet(paths, dst):
    tw, th = 258, 559
    cmd = [bc.FFMPEG, "-y", "-loglevel", "error"]
    for p in paths:
        cmd += ["-i", p]
    fc = "".join("[%d:v]scale=%d:%d:flags=area[s%d];" % (i, tw, th, i) for i in range(len(paths)))
    fc += "".join("[s%d]" % i for i in range(len(paths)))
    fc += "xstack=inputs=%d:layout=%s:fill=black" % (len(paths), "|".join("%d_0" % (i * tw) for i in range(len(paths))))
    subprocess.run(cmd + ["-filter_complex", fc, "-frames:v", "1", dst], check=True)


def _dst():
    """store/ for the 6.9" default; store/<W>x<H>/ for any other size."""
    return DST if (OUT_W, OUT_H) == (1290, 2796) else os.path.join(DST, "%dx%d" % (OUT_W, OUT_H))


def main():
    """`--size=1320x2868` (6.9"), `--size=1284x2778` or `--size=1242x2688` (6.5") for the other slots."""
    global OUT_W, OUT_H
    for a in sys.argv[1:]:
        if a.startswith("--size="):
            OUT_W, OUT_H = (int(v) for v in a[len("--size="):].split("x"))
    missing = [c for _, _, fr, _ in SHOTS for c, _ in fr if not os.path.exists(os.path.join(CLIPS, c + ".mov"))]
    if missing:
        print("missing clips (run tools/trailer/capture_all.sh appstore): %s" % ", ".join(sorted(set(missing))))
        return 1
    for captioned in (False, True):
        made = [render(name, card, frames, y, captioned) for name, card, frames, y in SHOTS]
        sheet(made, os.path.join(_dst(), "sheet_%s.png" % ("captioned" if captioned else "clean")))
    print("wrote %d screenshots x 2 sets to %s (%d x %d)" % (len(SHOTS), _dst(), OUT_W, OUT_H))
    return 0


if __name__ == "__main__":
    sys.exit(main())
