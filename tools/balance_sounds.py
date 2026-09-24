#!/usr/bin/env python3
"""balance_sounds.py - evens out the loudness of every sound effect and music track in Data/sounds.json.

Each entry names its files and a "target" loudness in LUFS (how loud that kind of sound should be: UI clicks quiet,
combat hits and spells in the middle, ambience low). This measures every file with ffmpeg (EBU R128 integrated
loudness; very short clips, too short for that, use their RMS level instead) and writes "volume_db": the gain that
brings the file to its target, capped so it never clips and never boosts by more than 18 dB. Scripts/sfx.gd plays
each sound at that volume. The audio files themselves are never changed.

Run it after adding or replacing sounds:   python3 tools/balance_sounds.py
"""
import json, os, re, subprocess, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DATA = os.path.join(ROOT, "Data", "sounds.json")


def measure(path):
    """(loudness, peak) in LUFS / dBFS; loudness falls back to RMS for clips too short for R128."""
    out = subprocess.run(["ffmpeg", "-hide_banner", "-nostats", "-i", path, "-af", "ebur128=peak=true,volumedetect",
                          "-f", "null", "-"], capture_output=True, text=True).stderr
    summary = out[out.rfind("Summary:"):]
    i = re.search(r"I:\s+(-?[\d.]+) LUFS", summary)
    peak = re.search(r"Peak:\s+(-?[\d.]+|-inf) dBFS", summary)
    mean = re.search(r"mean_volume: (-?[\d.]+) dB", out)
    loud = float(i.group(1)) if i else -70.0
    if loud <= -69.0 and mean:  # too short for an integrated reading
        loud = float(mean.group(1)) + 3.0  # RMS reads a little lower than LUFS for short hits
    pk = float(peak.group(1)) if peak and peak.group(1) != "-inf" else -60.0
    return loud, pk


def main():
    with open(DATA) as f:
        data = json.load(f)
    for sid, entry in data["sounds"].items():
        gains = []
        for rel in entry["files"]:
            path = os.path.join(ROOT, rel.replace("res://", ""))
            loud, pk = measure(path)
            gain = entry["target"] - loud
            gain = min(gain, 18.0, -1.0 - pk + 6.0)  # at most +18 dB, and not far past the file's own peak
            gains.append(round(gain, 1))
            print(f"{sid:22s} {rel.split('/')[-1]:28s} {loud:6.1f} LUFS  peak {pk:6.1f}  -> {gain:+5.1f} dB")
        entry["volume_db"] = round(sum(gains) / len(gains), 1)
        if len(gains) > 1:
            entry["file_db"] = gains  # each variant at its own level (Sfx uses these over volume_db)
        else:
            entry.pop("file_db", None)
    for path, entry in data.get("music", {}).items():
        loud, pk = measure(os.path.join(ROOT, path.replace("res://", "")))
        gain = min(entry["target"] - loud, 18.0, -1.0 - pk + 6.0)
        entry["volume_db"] = round(gain, 1)
        print(f"music {path.split('/')[-1]:32s} {loud:6.1f} LUFS  peak {pk:6.1f}  -> {gain:+5.1f} dB")
    with open(DATA, "w") as f:
        json.dump(data, f, indent=1, ensure_ascii=False)
        f.write("\n")


if __name__ == "__main__":
    sys.exit(main())
