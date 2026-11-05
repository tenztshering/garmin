#!/usr/bin/env python3
"""Ray-trace a looping black-hole animation for the Gargantua watch face.

Physics (units G = c = M = 1, Schwarzschild):
  - every pixel is a light ray traced back from the camera; its path bends by the
    exact photon-orbit equation u'' = 3u^2 - u (u = 1/r);
  - wherever the bent path crosses the thin accretion disk it picks up light, so the
    far side of the disk shows up lensed over and under the shadow, plus the thin
    photon ring of light that looped around the hole;
  - Doppler + gravitational shift g (Luminet 1979) brightens/whitens the approaching
    side and reddens light near the horizon;
  - rays that escape sample a star field, so stars smear into arcs around the hole.

Animation: disk streaks drift inward (falling in), hot clumps spiral down and fade
to red as they cross into the shadow, and the star field slowly turns so starlight
bends around the hole. The loop is seamless (crossfade for the streaks, exact period
for the clumps). Each frame averages sub-frames for motion blur, because Monkey
Motion plays at most 10 fps.

Usage:  python3 tools/render.py [--preview]     (--preview: 1 frame only, fast)
Output: resources/animations/gargantua.mmm (+ .mm), build/preview.png, build/gargantua.gif
"""
import argparse
import os
import subprocess

import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "..", "build")

W = H = 390                 # FR165 screen
SS = 2                      # supersampling per axis
CX, CY = 195.0, 178.0       # hole centre on screen (a bit high: time sits below)
SCALE = 12.0                # px per M  -> shadow radius 3*sqrt(3)*12 = 62 px
INCL = np.radians(84.0)     # angle between disk normal and line of sight
R_IN, R_OUT = 3.6, 16.0     # disk edges (in M)
FPS, SECONDS = 10, 6
SUB = 4                     # motion-blur sub-frames per frame
NCROSS = 5                  # disk crossings per ray (primary, secondary, photon ring)
rng = np.random.default_rng(7)


# ---------------------------------------------------------------- photon orbits
def orbit_table():
    """u(phi) for a dense set of impact parameters b, integrated with RK4."""
    bc = 3 * np.sqrt(3)
    b = np.unique(np.concatenate([
        np.linspace(0.02, 32.0, 5000),
        bc + np.sinh(np.linspace(-6, 6, 3000)) * 0.004,   # very dense near the photon ring
    ]))
    dphi = 0.004
    steps = int(3.3 * np.pi / dphi)
    u = np.zeros_like(b)
    w = 1.0 / b
    U = np.zeros((steps + 1, b.size), np.float32)
    end = np.full(b.size, np.nan)       # phi where the ray escapes (u back to 0)
    cap = np.full(b.size, np.inf)       # phi where the ray hits the horizon
    alive = np.ones(b.size, bool)
    f = lambda u_: 3 * u_ * u_ - u_
    for k in range(1, steps + 1):
        k1u, k1w = w, f(u)
        k2u, k2w = w + 0.5 * dphi * k1w, f(u + 0.5 * dphi * k1u)
        k3u, k3w = w + 0.5 * dphi * k2w, f(u + 0.5 * dphi * k2u)
        k4u, k4w = w + dphi * k3w, f(u + dphi * k3u)
        un = u + dphi / 6 * (k1u + 2 * k2u + 2 * k3u + k4u)
        wn = w + dphi / 6 * (k1w + 2 * k2w + 2 * k3w + k4w)
        phi = k * dphi
        hit = alive & (un >= 0.5)
        cap[hit] = phi
        esc = alive & (un <= 0) & (k > 1)
        end[esc] = phi - dphi * un[esc] / (un[esc] - u[esc])   # linear root
        alive &= ~(hit | esc)
        u = np.where(alive, un, u)
        w = np.where(alive, wn, w)
        U[k] = np.where(alive, un, np.where(hit, 0.5, 0.0))
    return b, U, dphi, end, cap


def geometry():
    """Per-pixel disk crossings (r, azimuth, Doppler g) and escape direction."""
    b_t, U, dphi, end_t, cap_t = orbit_table()
    n = W * SS
    ys, xs = np.mgrid[0:n, 0:n].astype(np.float64)
    px = (xs + 0.5) / SS - CX
    py = CY - (ys + 0.5) / SS                  # y up
    b = np.hypot(px, py) / SCALE
    alpha = np.arctan2(py, px)
    ca, sa = np.cos(alpha), np.sin(alpha)

    # interpolate the orbit table in b
    j = np.clip(np.searchsorted(b_t, b) - 1, 0, b_t.size - 2)
    t = np.clip((b - b_t[j]) / (b_t[j + 1] - b_t[j]), 0, 1)
    end = np.where(t < 0.5, end_t[j], end_t[j + 1])
    cap = np.where(t < 0.5, cap_t[j], cap_t[j + 1])

    def u_at(phi):
        k = phi / dphi
        k0 = np.clip(k.astype(np.int64), 0, U.shape[0] - 2)
        f = np.clip(k - k0, 0, 1)
        a = U[k0, j] * (1 - t) + U[k0, j + 1] * t
        c = U[k0 + 1, j] * (1 - t) + U[k0 + 1, j + 1] * t
        return a * (1 - f) + c * f

    si, ci = np.sin(INCL), np.cos(INCL)
    phi0 = np.mod(np.arctan2(-ci, sa * si), np.pi)
    limit = np.where(np.isnan(end), np.minimum(cap, U.shape[0] * dphi), end)
    cross = []
    for m in range(NCROSS):
        phi = phi0 + m * np.pi
        ok = phi < limit
        u = np.where(ok, u_at(np.minimum(phi, 3.29 * np.pi)), 0)
        ok &= u > 1.0 / R_OUT * 0.9
        r = np.where(ok, 1.0 / np.maximum(u, 1e-6), 1e9)
        # position on the disk: d = cos(phi) z + sin(phi) e_alpha
        dx, dy, dz = np.sin(phi) * ca, np.sin(phi) * sa, np.cos(phi)
        psi = np.arctan2(dy * ci - dz * si, dx)          # e1 = x, e2 = N x e1
        rr = np.maximum(r, 3.05)
        om = rr ** -1.5
        g = np.sqrt(1 - 3 / rr) / (1 + 0.55 * om * b * si * ca)  # left side approaches (beaming tempered for looks)
        g *= np.clip((r - 2.0) / (R_IN - 2.0), 0, 1) ** 0.5     # fades to nothing at the horizon
        cross.append((ok, r.astype(np.float32), psi.astype(np.float32), g.astype(np.float32)))

    escaped = ~np.isnan(end)
    ph = np.nan_to_num(end)
    out = np.stack([np.sin(ph) * ca, np.sin(ph) * sa, np.cos(ph)], -1)
    return cross, escaped, out


# ---------------------------------------------------------------- textures
def star_map():
    h, w = 1024, 2048
    img = np.zeros((h, w, 3), np.float32)
    nstar = 3800
    z = rng.uniform(-1, 1, nstar)
    lon = rng.uniform(0, w, nstar)
    lat = (np.arcsin(z) / np.pi + 0.5) * h
    mag = rng.pareto(2.2, nstar) * 0.08 + 0.02
    tint = rng.choice([[1, .86, .7], [1, 1, 1], [.75, .85, 1]], nstar, p=[.35, .4, .25])
    for x, y, m, c in zip(lon, lat, mag, tint):
        xi, yi = int(x) % w, int(np.clip(y, 0, h - 1))
        img[yi, xi] += np.minimum(m, 1.2) * np.array(c)
    # tiny blur so stars survive resampling
    k = np.array([.25, .5, .25], np.float32)
    for ax in (0, 1):
        img = sum(np.roll(img, s, ax) * kk for s, kk in zip((-1, 0, 1), k))
    return img


def sample_stars(smap, d, t):
    rot = 2 * np.pi * 0.035 * t          # slow drift of the sky
    x = d[..., 0] * np.cos(rot) + d[..., 2] * np.sin(rot)
    z = -d[..., 0] * np.sin(rot) + d[..., 2] * np.cos(rot)
    lon = np.arctan2(x, z)
    lat = np.arcsin(np.clip(d[..., 1], -1, 1))
    h, w = smap.shape[:2]
    xi = ((lon / (2 * np.pi) + 0.5) * w).astype(int) % w
    yi = np.clip(((lat / np.pi + 0.5) * h).astype(int), 0, h - 1)
    return smap[yi, xi]


# radial streak pattern: many fine rings, each a sum of low azimuthal harmonics
NR = 2048
RAD = np.cumsum(rng.normal(0, 1, NR))
RAD = (RAD - RAD.min()) / np.ptp(RAD)
FINE = rng.uniform(0, 1, NR)
HARM = [(m, rng.uniform(0, 2 * np.pi, NR), rng.uniform(0.2, 1, NR)) for m in (1, 2, 3, 5, 8)]


def streaks(r, psi, t):
    """Disk brightness texture; features rotate and drift inward over time."""
    s = np.log(r) + 0.06 * t                        # inward drift
    idx = (s * 260).astype(np.int64) % NR
    om = 0.9 * (r / R_IN) ** -1.5                   # rad/s, differential rotation
    chi = psi - om * t
    v = 0.55 + 0.35 * RAD[idx] + 0.25 * FINE[idx]
    for m, ph, a in HARM:
        v = v + 0.10 * a[idx] * np.cos(m * chi + ph[idx])
    return np.clip(v, 0, None)


NSPOT = 7
SPOT = [(rng.uniform(0, 2 * np.pi), k / NSPOT, rng.uniform(0.8, 1.4)) for k in range(NSPOT)]


def spots(r, psi, t, T):
    """Hot clumps spiralling from the outer disk into the hole, exactly periodic."""
    out = np.zeros_like(r)
    for psi0, off, amp in SPOT:
        s = np.mod(t / T + off, 1.0)
        rs = 2.0 + (13.0 - 2.0) * (1 - s) ** 1.6     # speeds up as it falls
        # angle: integral of Omega ~ rs^-1.5 over the fall, stretched for looks
        ps = psi0 + 9.0 * s ** 2.2 + 2.2 * s
        fade = np.sin(np.pi * min(s * 1.25, 1.0)) ** 0.8 * np.clip((rs - 2.0) / 1.2, 0, 1)
        dpsi = np.angle(np.exp(1j * (psi - ps)))     # wrap to [-pi, pi]
        # trailing tail: longer behind the clump than ahead of it
        tail = np.where(dpsi < 0, 0.55, 0.12)
        out += amp * fade * np.exp(-((r - rs) / (0.35 + 0.04 * rs)) ** 2 - (dpsi / tail) ** 2)
    return out


def emissivity(r):
    inner = np.clip((r - R_IN) / 0.6, 0, 1)
    plunge = np.clip((r - 2.0) / (R_IN - 2.0), 0, 1) ** 3 * 0.12 * (r < R_IN)
    outer = np.clip((R_OUT - r) / 4.0, 0, 1)
    return ((R_IN / np.maximum(r, 2.01)) ** 2.0 * inner + plunge) * outer


def colour(temp):
    """temperature 0..~1.6 -> deep red, amber, cream, blue-white"""
    stops = np.array([0.0, 0.35, 0.7, 1.0, 1.35, 1.7])
    cols = np.array([[.25, .02, 0], [.85, .22, .03], [1, .55, .18],
                     [1, .86, .62], [1, .96, .9], [.78, .88, 1]])
    out = np.empty(temp.shape + (3,), np.float32)
    for c in range(3):
        out[..., c] = np.interp(temp, stops, cols[:, c])
    return out


def shade(geo, smap, t, T, with_streak_time):
    cross, escaped, out_dir = geo
    n = W * SS
    img = np.zeros((n, n, 3), np.float32)
    trans = np.ones((n, n), np.float32)
    for ok, r, psi, g in cross:
        if not ok.any():
            continue
        tex = streaks(r, psi, with_streak_time) * 0.9 + spots(r, psi, t, T) * 2.2
        e = emissivity(r) * tex * g ** 2.2 * ok
        temp = np.clip(g * (R_IN / np.maximum(r, 2.01)) ** 0.45 * 1.15 + 0.15 * tex - 0.1, 0, 1.7)
        img += (trans * e)[..., None] * colour(temp)
        opac = np.clip(e * 1.6, 0, 0.92) * ok
        trans *= 1 - opac
    sky = sample_stars(smap, out_dir, t) * (escaped * trans)[..., None]
    return img * 2.6 + sky * 1.6


def tonemap(x):
    x = 1 - np.exp(-x * 1.6)
    return np.clip(x, 0, 1) ** (1 / 1.15)


def frame(geo, smap, i, nframes):
    T = nframes / FPS
    acc = 0
    for s in range(SUB):
        t = (i + s / SUB) / FPS
        # crossfade the streak texture between t and t - T -> seamless loop
        wgt = t / T
        a = shade(geo, smap, t, T, t)
        b = shade(geo, smap, t, T, t - T)
        acc = acc + a * (1 - wgt) + b * wgt
    img = tonemap(acc / SUB)
    img = img.reshape(W, SS, W, SS, 3).mean((1, 3))
    # round watch: everything outside the disc stays black
    yy, xx = np.mgrid[0:H, 0:W]
    img[(xx - 194.5) ** 2 + (yy - 194.5) ** 2 > 195 ** 2] = 0
    return Image.fromarray((img * 255 + 0.5).astype(np.uint8))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--preview", action="store_true")
    args = ap.parse_args()
    os.makedirs(os.path.join(OUT, "frames"), exist_ok=True)
    print("tracing photon orbits...")
    geo = geometry()
    smap = star_map()
    nframes = FPS * SECONDS
    if args.preview:
        frame(geo, smap, 0, nframes).save(os.path.join(OUT, "preview.png"))
        print("wrote build/preview.png")
        return
    for i in range(nframes):
        frame(geo, smap, i, nframes).save(os.path.join(OUT, "frames", f"f{i:03d}.png"))
        print(f"frame {i + 1}/{nframes}", end="\r", flush=True)
    print()
    # Monkey Motion only reads GIF reliably (mp4/avi -> "0 frames"); one palette per frame
    # keeps the gradients clean before it re-encodes to RGB565.
    gif = os.path.join(OUT, "gargantua.gif")
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-framerate", str(FPS),
                    "-i", os.path.join(OUT, "frames", "f%03d.png"), "-vf",
                    "split[a][b];[a]palettegen=max_colors=256:stats_mode=single[p];"
                    "[b][p]paletteuse=new=1:dither=sierra2_4a", gif], check=True)
    Image.open(os.path.join(OUT, "frames", "f000.png")).save(os.path.join(OUT, "preview.png"))
    sdk = open(os.path.expanduser(
        "~/Library/Application Support/Garmin/ConnectIQ/current-sdk.cfg")).read().strip()
    root = os.path.join(HERE, "..")
    mm = os.path.join(OUT, "mm")
    subprocess.run(["rm", "-rf", mm], check=True)
    subprocess.run(["bash", os.path.join(sdk, "bin", "monkeym"), "-v", gif,
                    "-m", os.path.join(root, "manifest.xml"), "-f", str(FPS),
                    "-o", os.path.join(mm, "gargantua.mmm")], check=True)
    dst = os.path.join(root, "resources", "animations")
    for f in os.listdir(os.path.join(mm, "gargantua.mmm")):
        os.replace(os.path.join(mm, "gargantua.mmm", f), os.path.join(dst, f))
    print("wrote resources/animations/gargantua.mmm")

if __name__ == "__main__":
    main()
