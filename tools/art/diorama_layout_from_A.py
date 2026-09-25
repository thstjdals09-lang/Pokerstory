"""Back-projects ground contact points read off the A image onto the ground plane.

Camera model fitted to A: vertical FOV 20 deg, optical axis pitched 22 deg down (the fountain's
ground ring is an ellipse of ratio ~0.39; the same lamp is 1.42x taller in front than at the back).
Scale: the player (feet at y 555) is 98 px tall = 1.2 m (the diorama's chibi height).
World: X right, Z toward the camera, fountain at the origin.
"""
import math, json

W, H = 1344, 752
FOV = 20.0
PITCH = 22.0
f = (H / 2) / math.tan(math.radians(FOV / 2))
th = math.radians(PITCH)


def ray(u, v):
    x = (u - W / 2) / f
    y = -(v - H / 2) / f
    z = -1.0
    # pitch down by th around X
    y2 = y * math.cos(th) + z * math.sin(th)
    z2 = -y * math.sin(th) + z * math.cos(th)
    return x, y2, z2


def ground(u, v, h=1.0):
    x, y, z = ray(u, v)
    t = h / -y
    return (x * t, z * t)  # camera at (0, h, 0)


def project(X, Y, Z, h=1.0):
    # world point relative to camera at (0,h,0)
    y = Y - h
    # undo pitch
    yc = y * math.cos(th) - Z * math.sin(th)
    zc = y * math.sin(th) + Z * math.cos(th)
    return (W / 2 + X / -zc * f, H / 2 - yc / -zc * f)


def px_per_m(u, v):
    gx, gz = ground(u, v)
    _, v0 = project(gx, 0, gz)
    _, v1 = project(gx, 0.1, gz)
    return (v0 - v1) / 0.1


# scale so the player is 1.2 m tall at 98 px
k = 1.2 / (98.0 / px_per_m(665, 555))
fx, fz = ground(678, 405)


def G(u, v):
    x, z = ground(u, v)
    return [round((x - fx) * k, 2), round((z - fz) * k, 2)]


def height(u, v, pixels):
    return round(pixels / px_per_m(u, v) * k, 2)


def facade(p0, p1, door, wall_px, depth_ratio):
    a = G(*p0)
    b = G(*p1)
    cx, cz = (a[0] + b[0]) / 2, (a[1] + b[1]) / 2
    w = math.hypot(b[0] - a[0], b[1] - a[1])
    ang = math.atan2(-(b[1] - a[1]), b[0] - a[0])  # front edge direction -> Y rotation
    d = w * depth_ratio
    # building centre sits behind the front edge
    nx, nz = -math.sin(ang), -math.cos(ang)
    centre = [round(cx + nx * d / 2, 2), round(cz + nz * d / 2, 2)]
    dg = G(*door)
    along = (dg[0] - cx) * math.cos(ang) - (dg[1] - cz) * math.sin(ang)
    mid = ((p0[0] + p1[0]) / 2, (p0[1] + p1[1]) / 2)
    return {"at": centre, "w": round(w, 2), "d": round(d, 2), "rot_deg": round(math.degrees(ang), 1),
            "door": round(along, 2), "h": height(mid[0], mid[1], wall_px)}


out = {}
out["buildings"] = {
    # front ground line (left point, right point), door foot, wall height in px at the front
    "home_building": facade((598, 256), (795, 256), (672, 252), 140, 0.75),
    "shop_building": facade((190, 264), (505, 264), (440, 262), 225, 0.6),
    "card_room_building": facade((985, 302), (1420, 348), (1140, 326), 270, 0.55),
    "community_hall_building": facade((-160, 505), (245, 552), (140, 548), 215, 0.8),
}
out["fountain_r"] = round((G(783, 405)[0] - G(575, 405)[0]) / 2, 2)
out["plaza_r"] = round((G(960, 405)[0] - G(410, 405)[0]) / 2, 2)
props = {
    "lamp": [(458, 655), (312, 405), (925, 292), (1085, 525), (905, 752), (1140, 745)],
    "board": [(345, 592)],
    "bench": [(1045, 497)],
    "stall": [(1240, 562)],
    "gate": [(1035, 770)],
    "mailbox": [(737, 262)],
    "aframe": [(455, 245), (1060, 332)],
    "barrel": [(630, 222), (215, 240), (1200, 345)],
    "crates": [(235, 250)],
    "pot": [(235, 560), (100, 620), (990, 320)],
}
out["props"] = {k2: [G(*p) for p in v] for k2, v in props.items()}
# flower beds: centre and pixel width -> world width (depth ~ 0.55 w)
beds = [((565, 262), 150), ((795, 262), 130), ((400, 360), 150), ((930, 338), 130), ((372, 580), 140),
        ((500, 562), 80), ((852, 582), 130), ((1100, 408), 120)]
out["beds"] = []
for (u, v), wpx in beds:
    x0 = G(u - wpx / 2, v)
    x1 = G(u + wpx / 2, v)
    c = G(u, v)
    out["beds"].append([c[0], c[1], round(abs(x1[0] - x0[0]), 2)])
out["people"] = {"player": G(665, 555), "lumi": G(745, 515), "moa": G(528, 412), "juno": G(990, 440)}
# fences: two ends each
out["fences"] = [[G(480, 185), G(590, 185)], [G(800, 180), G(985, 190)], [G(150, 690), G(320, 690)], [G(1180, 640), G(1344, 610)]]
# trees framing: ground points
out["trees"] = [G(*p) for p in [(90, 200), (520, 120), (860, 110), (960, 140), (40, 720), (1320, 600), (300, 760)]]
# camera: the ground point at the image centre, and distance to it
cx, cz = ground(W / 2, H / 2)
dist = math.hypot(math.hypot(cx, cz), 1.0) * k
out["camera"] = {"fov": FOV, "pitch": PITCH, "centre": [round((cx - fx) * k, 2), round((cz - fz) * k, 2)], "dist": round(dist, 2)}
print(json.dumps(out, indent=1))
json.dump(out, open(r'C:\Users\a\AppData\Local\Temp\claude\c--xampp-htdocs-opensource-casino-v10-main\bfdde39e-fc8e-4bde-8717-4343c35bf4c7\scratchpad\a_layout.json', 'w'), indent=1)
