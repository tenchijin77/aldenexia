#!/usr/bin/env python3
# telemetry_report.py — summarises the dedicated server's telemetry log (user://logs/telemetry.jsonl, written by
# net.gd _telemetry(): kills, character saves with what changed, trust anomalies, logins/logouts).
#
#   python3 tools/telemetry_report.py                     fetch the log from the test server (ssh) and report
#   python3 tools/telemetry_report.py path/to/telemetry.jsonl
#   python3 tools/telemetry_report.py --since 2026-09-25  only events on/after that date
#
# Per class: hours played, XP / kills / deaths / coin per hour. Per character: time to each level. Most-killed monsters,
# what kills players, quests completed, items gained, and every trust anomaly (a save the server corrected).

import json
import os
import subprocess
import sys
import tempfile
from collections import Counter, defaultdict

SERVER = "rwilkinson@192.168.77.100"
REMOTE = ".local/share/godot/app_userdata/Aldenexia-Lightfall/logs/telemetry.jsonl"


def load(path, since):
    events = []
    with open(path) as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            try:
                e = json.loads(line)
            except json.JSONDecodeError:
                continue
            if since and str(e.get("t", "")) < since:
                continue
            events.append(e)
    return events


def fetch():
    tmp = os.path.join(tempfile.gettempdir(), "aldenexia_telemetry.jsonl")
    subprocess.run(["scp", "-q", "-o", "BatchMode=yes", f"{SERVER}:{REMOTE}", tmp], check=True)
    return tmp


def hours(seconds):
    return seconds / 3600.0


def main():
    args = sys.argv[1:]
    since = ""
    if "--since" in args:
        i = args.index("--since")
        since = args[i + 1]
        del args[i:i + 2]
    path = args[0] if args else fetch()
    events = load(path, since)
    saves = [e for e in events if e.get("event") == "save"]
    kills = [e for e in events if e.get("event") == "kill"]
    anomalies = [e for e in events if e.get("event") == "anomaly"]
    print(f"Telemetry: {len(events)} events ({len(saves)} saves, {len(kills)} kills, {len(anomalies)} anomalies)"
          f"{' since ' + since if since else ''}\n")

    by_class = defaultdict(lambda: {"seconds": 0, "xp": 0, "coin": 0, "deaths": 0, "kills": 0, "chars": set()})
    char_class = {}
    for s in saves:
        c = by_class[s.get("class", "?")]
        # A save covers the time since the previous one; long gaps are the player being logged out, not playing.
        c["seconds"] += min(int(s.get("seconds", 0)), 600)
        c["xp"] += int(s.get("xp", 0))
        c["coin"] += int(s.get("coin", 0))
        c["deaths"] += int(s.get("deaths", 0))
        c["chars"].add(s.get("character", "?"))
        char_class[s.get("character", "?")] = s.get("class", "?")
    for k in kills:
        by_class[k.get("class", "?") or char_class.get(k.get("character"), "?")]["kills"] += 1

    print("BY CLASS (per hour of play)")
    print(f"  {'class':<13}{'chars':>6}{'hours':>7}{'XP/h':>8}{'kills/h':>9}{'deaths/h':>10}{'coin/h':>9}")
    for cls, c in sorted(by_class.items(), key=lambda kv: -kv[1]["seconds"]):
        h = hours(c["seconds"])
        rate = (lambda v: v / h) if h > 0 else (lambda v: 0)
        print(f"  {cls:<13}{len(c['chars']):>6}{h:>7.1f}{rate(c['xp']):>8.0f}{rate(c['kills']):>9.1f}"
              f"{rate(c['deaths']):>10.2f}{rate(c['coin']):>8.0f}c")

    print("\nTIME TO EACH LEVEL (hours played when first reached)")
    played = defaultdict(int)
    reached = defaultdict(dict)
    for s in saves:
        ch = s.get("character", "?")
        played[ch] += min(int(s.get("seconds", 0)), 600)
        lvl = int(s.get("level", 1))
        if int(s.get("levels_gained", 0)) > 0 and lvl not in reached[ch]:
            reached[ch][lvl] = played[ch]
    for ch in sorted(reached):
        steps = ", ".join(f"L{lvl} {hours(sec):.1f}h" for lvl, sec in sorted(reached[ch].items()))
        print(f"  {ch:<14}({char_class.get(ch, '?')}): {steps}")

    print("\nMOST KILLED")
    for (mob, lvl), n in Counter((k.get("monster", "?"), k.get("monster_level", 0)) for k in kills).most_common(12):
        print(f"  {n:>5}  {mob} (L{lvl})")

    deaths_by = Counter(s.get("death_by", "") for s in saves if int(s.get("deaths", 0)) > 0 and s.get("death_by"))
    if deaths_by:
        print("\nWHAT KILLS PLAYERS")
        for who, n in deaths_by.most_common(10):
            print(f"  {n:>5}  {who}")

    quests = Counter(q for s in saves for q in s.get("quests_completed", []))
    if quests:
        print("\nQUESTS COMPLETED")
        for q, n in quests.most_common():
            print(f"  {n:>5}  {q}")

    gained = Counter()
    for s in saves:
        for item, n in s.get("items_gained", {}).items():
            gained[item] += int(n)
    if gained:
        print("\nITEMS GAINED (top 15)")
        for item, n in gained.most_common(15):
            print(f"  {n:>6}  {item}")

    if anomalies:
        print("\nTRUST ANOMALIES (saves the server corrected)")
        for a in anomalies[-40:]:
            print(f"  {a.get('t', '')}  {a.get('character', '?')}: {a.get('detail', '')}")


if __name__ == "__main__":
    main()
