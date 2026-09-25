# shape_body.py — gentle body sculpting for the Meshy female models (2026-09-25, user: "keep them busty and beautiful").
# Imported by smooth_character.py and run on the mesh BEFORE it is subdivided, in the T-pose rest shape, so the skin
# weights and UVs simply come along. Three soft pushes, each with a smooth falloff and measured from the model itself
# (so a gnome and an elf are shaped alike for their size):
#   bust  - each breast swells forward and a little up and out from a point just behind its surface
#   waist - the middle draws in toward the spine
#   hips  - the hips widen a little
# Characters face -Y in Blender (Mixamo), up is +Z. Arms (T-pose, at the shoulders) and long hair out at the sides are
# left alone: only vertices within the torso's width move.
from mathutils import Vector


def _smooth(t):   # 1 at the centre, 0 at the edge
    t = max(0.0, min(1.0, t))
    return (1.0 - t * t) ** 2


def shape(obj, bust=0.0, waist=0.0, hips=0.0, log=print):
    me = obj.data
    mw = obj.matrix_world
    inv = mw.inverted()
    pts = [mw @ v.co for v in me.vertices]
    zmin = min(p.z for p in pts)
    H = max(p.z for p in pts) - zmin
    rel = lambda p: (p.z - zmin) / H
    torso_x = 0.13 * H          # half-width of the torso region we touch
    moved = [Vector(p) for p in pts]

    # bust apexes: the most forward (lowest y) vertex on each side, in the chest band
    # (the average of the 20 most forward points on each side, then mirrored so both sides match: a single most-forward
    # vertex sat almost on the middle line on one model and filled in the cleavage)
    apex = {}
    found = {}
    for side in (1, -1):
        cand = sorted((p for p in pts if 0.64 <= rel(p) <= 0.80 and 0.035 * H < side * p.x < 0.085 * H), key=lambda p: p.y)[:20]
        if cand:
            found[side] = sum(cand, Vector()) / len(cand)
    if len(found) == 2:
        ax = (abs(found[1].x) + abs(found[-1].x)) / 2
        ay = (found[1].y + found[-1].y) / 2
        az = (found[1].z + found[-1].z) / 2
        apex = {1: Vector((ax, ay, az)), -1: Vector((-ax, ay, az))}
    R = 0.065 * H               # a breast's radius of influence
    if bust and len(apex) == 2:
        for side, a in apex.items():
            c = a + Vector((0.0, 0.75 * R, 0.0))          # a point inside the chest behind the apex
            for i, p in enumerate(pts):
                d = (p - a).length
                if d > 1.7 * R or abs(p.x) > torso_x:
                    continue
                front = max(0.0, min(1.0, (c.y - p.y) / (0.5 * R)))   # the back doesn't move
                cleavage = max(0.0, min(1.0, (abs(p.x) - 0.008 * H) / (0.02 * H)))   # the cleavage stays
                w = _smooth(d / (1.7 * R)) * front * cleavage
                push = (p - c) * (bust * w)
                push.z += bust * w * 0.18 * R                          # a little lift
                push.x += side * bust * w * 0.08 * R                   # and a touch apart
                moved[i] += push
        log("bust apex %.3f/%.3f at height %.2f, strength %.2f" % (apex[1].x, apex[-1].x, rel(apex[1]), bust))

    if waist or hips:
        # the torso's centre line (y) at each height, from the torso vertices
        def centre_y(zr):
            band = [p for p in pts if abs(rel(p) - zr) < 0.02 and abs(p.x) < torso_x]
            return sum(p.y for p in band) / len(band) if band else 0.0
        wz, hz = 0.62, 0.53
        wy, hy = centre_y(wz), centre_y(hz)
        for i, p in enumerate(pts):
            if abs(p.x) > 1.4 * torso_x:
                continue
            r = rel(p)
            if waist:
                w = _smooth(abs(r - wz) / 0.07)
                if w > 0:
                    moved[i].x -= p.x * waist * w
                    moved[i].y -= (p.y - wy) * waist * w * 0.6
            if hips:
                w = _smooth(abs(r - hz) / 0.06)
                if w > 0:
                    moved[i].x += p.x * hips * w
                    moved[i].y += (p.y - hy) * hips * w * 0.3
        log("waist %.2f, hips %.2f" % (waist, hips))

    for i, v in enumerate(me.vertices):
        v.co = inv @ moved[i]
    me.update()


# ── Slider shapes (2026-09-25): each is a full-strength version of one change, stored as a blend shape the game mixes in
# by the player's slider (Scripts/appearance.gd). A slider at -1..+1 plays it backwards or forwards.
def _normals(obj):
    me = obj.data
    me.update()
    rot = obj.matrix_world.to_3x3()
    return [(rot @ v.normal).normalized() for v in me.vertices]


def _frame(obj):
    mw = obj.matrix_world
    pts = [mw @ v.co for v in obj.data.vertices]
    zmin = min(p.z for p in pts)
    H = max(p.z for p in pts) - zmin
    arm = next((o for o in obj.parent.children if o.type == 'ARMATURE'), None) if obj.parent else None
    return mw, pts, zmin, H


def _write(obj, pts, moved):
    inv = obj.matrix_world.inverted()
    for i, v in enumerate(obj.data.vertices):
        v.co = inv @ moved[i]
    obj.data.update()


def morph(obj, kind):
    """Deforms `obj` to the full-strength slider shape `kind`: weight, muscle (everyone), bust, waist, hips (women)."""
    if kind in ("bust", "waist", "hips"):
        shape(obj, bust=0.4 if kind == "bust" else 0.0, waist=0.12 if kind == "waist" else 0.0, hips=0.12 if kind == "hips" else 0.0,
              log=lambda s: None)
        return
    mw, pts, zmin, H = _frame(obj)
    normals = _normals(obj)
    xmax = max(abs(p.x) for p in pts)
    moved = [Vector(p) for p in pts]
    for i, p in enumerate(pts):
        r = (p.z - zmin) / H
        ax = abs(p.x) / H
        # not the head, the hands or the soles
        body = min(1.0, max(0.0, (0.84 - r) / 0.04)) * min(1.0, max(0.0, (xmax / H * 0.86 - ax) / 0.05)) * min(1.0, max(0.0, (r - 0.02) / 0.04))
        if body <= 0.0:
            continue
        n = normals[i]
        if kind == "weight":
            belly = _smooth(abs(r - 0.58) / 0.12) if ax < 0.12 else 0.0
            amount = 0.009 * H * (1.0 + 0.8 * belly) + 0.004 * H * _smooth(abs(r - 0.5) / 0.2)
            moved[i] += n * amount * body
            if belly and n.y < 0:                  # the belly rounds forward
                moved[i].y -= 0.006 * H * belly * body
        elif kind == "muscle":
            arms = _smooth(abs(r - 0.79) / 0.05) * _smooth(abs(ax - 0.24) / 0.16)     # shoulders and arms (T-pose)
            chest = _smooth(abs(r - 0.74) / 0.06) * (1.0 if ax < 0.14 else 0.0)
            amount = 0.04 * H * max(arms, chest * 0.7)   # (not the thighs: a tunic's hem ballooned)
            # not up into the neck, and little upward push on the shoulder tops: that shrugged the shoulders and
            # shortened the neck, and read as the whole character growing (test 36)
            neck = min(1.0, max(0.0, (0.76 - r) / 0.03)) if ax < 0.1 else 1.0
            push = n * amount * body * neck
            if push.z > 0.0:
                push.z *= 0.3
            moved[i] += push
            if r > 0.7 and ax < 0.14:
                moved[i].x *= 1.0 + 0.08 * _smooth(abs(r - 0.8) / 0.08)             # broader shoulders
    _write(obj, pts, moved)


FEMALE_SHAPES = ["bust", "waist", "hips", "weight", "muscle"]
MALE_SHAPES = ["weight", "muscle"]
