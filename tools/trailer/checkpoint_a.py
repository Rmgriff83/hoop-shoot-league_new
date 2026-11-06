#!/usr/bin/env python3
"""Checkpoint A's pack (docs/TRAILER.md -> Checkpoints): from the edit, the shot
files and the storyboard frames the game rendered, write
marketing/trailer/checkpoint_a/CHECKPOINT_A.md (the shot list on the bar map,
the copy options, the six themes and the frame each reads in) and the contact
sheets: one frame per shot in cut order, and each text card over its shot.

  tools/trailer/storyboard.sh appstore && tools/trailer/storyboard.sh social
  tools/trailer/cards.sh appstore && tools/trailer/cards.sh social
  python3 -I tools/trailer/checkpoint_a.py

Stdlib + ffmpeg (tiling and compositing only: every pixel of type is the game's).
"""
import json, os, subprocess, sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import build_cut as bc

A = os.path.join(bc.OUT, "checkpoint_a")
THEMES = ["shot feel", "nets", "league", "cards", "solo or online", "customization"]
THEME_WORDS = {
    "shot feel": "REAL SHOT FEEL: how you swipe decides the shot",
    "nets": "THE NETS (never named): the net's reaction is the payoff",
    "league": "THE LEAGUE: standings, a heat with the PiP, the title",
    "cards": "POWER-UP CARDS: the pick, Deep Freeze, Magnet",
    "solo or online": "SOLO OR ONLINE: the weekly board, a ranked face-off, SPOILS",
    "customization": "CUSTOMIZATION: the locker, a PEGGY legend pull, your kit in their window",
}
COLS = 6
THUMB_W = 240


def shot(name):
    path = os.path.join(bc.SHOTS, name + ".json")
    return json.load(open(path)) if os.path.exists(path) else {}


def flick_source(layout, name):
    """What the storyboard's flicks were: recordings, or stand-ins."""
    path = os.path.join(A, "frames", layout, name + ".marks.json")
    if not os.path.exists(path):
        return ""
    flicks = json.load(open(path)).get("flicks", [])
    if not flicks:
        return ""
    return "stand-in flick" if all(str(f).startswith("synth") for f in flicks) else "recorded flick"


def sheet(paths, dst, thumb_h):
    """Tile frames COLS across (ffmpeg): the storyboard, in cut order."""
    paths = [p for p in paths if os.path.exists(p)]
    if not paths:
        return False
    rows = (len(paths) + COLS - 1) // COLS
    cmd = [bc.FFMPEG, "-y", "-loglevel", "error"]
    for p in paths:
        cmd += ["-i", p]
    layout = "|".join("%d_%d" % ((i % COLS) * THUMB_W, (i // COLS) * thumb_h) for i in range(len(paths)))
    fc = "".join("[%d:v]scale=%d:%d[s%d];" % (i, THUMB_W, thumb_h, i) for i in range(len(paths)))
    fc += "".join("[s%d]" % i for i in range(len(paths))) + "xstack=inputs=%d:layout=%s:fill=black" % (len(paths), layout)
    if len(paths) == 1:
        fc = "[0:v]scale=%d:%d" % (THUMB_W, thumb_h)
    subprocess.run(cmd + ["-filter_complex", fc, "-frames:v", "1", dst], check=True)
    return True


def main():
    edit = json.load(open(bc.EDIT))
    os.makedirs(A, exist_ok=True)
    md = ["# Checkpoint A: the trailer's shot list, bar map, copy and storyboard", "",
          "Music: `%s`, 110 BPM, one bar = 2.18 s, 16 bars in the loop (34.9 s)." % edit["music"],
          "Every frame below was rendered by the game through the trailer director. A shot marked *stand-in flick* will be re-shot with a recorded flick once there is one for that court and outcome.", ""]
    used = {}
    for name, cut in edit["cuts"].items():
        plan = bc.cut_plan(edit, name)
        layout = cut["layout"]
        thumb_h = int(round(THUMB_W * cut["size"][1] / cut["size"][0] / 2)) * 2
        md += ["## %s cut: %d bars, %.2f s, %dx%d at %d fps" % (name.upper() if name != "appstore" else "APP STORE", int(cut["bars"]), plan["seconds"], cut["size"][0], cut["size"][1], plan["fps"]), "",
               "| # | Bar.beat | Time | Length | Shot | What it shows | Flicks | Card |", "|---|---|---|---|---|---|---|---|"]
        frames = []
        for i, (e, s) in enumerate(zip(cut["timeline"], plan["segs"])):
            clip = s["clip"]
            sh = shot(clip) if clip else {}
            card = next((c["text"].replace("\n", " ") for c in plan["cards"] if c["text"] and c["a"] <= s["a"] < c["b"]), "")
            note = sh.get("note", "The filmed hand flick (Ross films this; a black slot until then)." if not clip else "")
            md.append("| %d | %s | %.2f s | %.2f s | `%s` | %s | %s | %s |" % (i + 1, e["at"], s["a"] / plan["fps"], (s["b"] - s["a"]) / plan["fps"], clip or "hand_flick", note, flick_source(layout, clip) if clip else "", card))
            if clip:
                frames.append(os.path.join(A, "frames", layout, clip + ".png"))
                for th in sh.get("themes", []):
                    used.setdefault(th, {}).setdefault(clip, set()).add(name)
        ok = sheet(frames, os.path.join(A, "storyboard_%s.png" % layout), thumb_h)
        md += ["", "Storyboard, in cut order, %d across: `storyboard_%s.png`%s" % (COLS, layout, "" if ok else " (not rendered yet)"), ""]
        # Each card over the first shot of its window, as it will sit.
        comps = []
        for c in plan["cards"]:
            still = os.path.join(A, "cards", layout, c["id"] + ".png")
            under = next((os.path.join(A, "frames", layout, s["clip"] + ".png") for s in plan["segs"] if s["clip"] and s["a"] >= c["a"]), None)
            if c["id"] in ("credit", "free"):
                under = os.path.join(A, "frames", layout, "end_card.png")
            if not (os.path.exists(still) and under and os.path.exists(under)):
                continue
            dst = os.path.join(A, "cards", layout, "comp_%s.png" % c["id"])
            subprocess.run([bc.FFMPEG, "-y", "-loglevel", "error", "-i", under, "-i", still, "-filter_complex",
                            "[1:v]scale=iw/2:ih/2:flags=neighbor[c];[0:v][c]overlay=0:0", "-frames:v", "1", dst], check=True)
            comps.append(dst)
        if sheet(comps, os.path.join(A, "cards_%s.png" % layout), thumb_h):
            md += ["Text cards over their shots (option A of each): `cards_%s.png`" % layout, ""]
    md += ["## Copy options (pick one per card)", "", "| Card | A (in the storyboard) | B | C |", "|---|---|---|---|"]
    for cid, opts in edit.get("copy_options", {}).items():
        md.append("| %s | %s |" % (cid, " | ".join(o.replace("\n", " / ") for o in opts)))
    md += ["", "End card: the splash's neon logo, with `%s`. The social cut adds FREE ON THE APP STORE; the App Store cut has no price or store line." % edit.get("music_credit", ""), "",
           "## The six themes, and where each reads", "", "| Theme | Shots that carry it | Frame |", "|---|---|---|"]
    missing = []
    for th in THEMES:
        clips = used.get(th, {})
        if not clips:
            missing.append(th)
        md.append("| %s | %s | %s |" % (THEME_WORDS[th], ", ".join("`%s`" % c for c in clips) or "NONE", ", ".join("`frames/appstore/%s.png`" % c for c in clips)))
    md += ["", "Themes with no shot: %s" % (", ".join(missing) if missing else "none; all six land."), ""]
    open(os.path.join(A, "CHECKPOINT_A.md"), "w").write("\n".join(md))
    print("wrote %s (themes missing: %s)" % (os.path.join(A, "CHECKPOINT_A.md"), missing or "none"))
    return 0


if __name__ == "__main__":
    sys.exit(main())
