"""Synthesizes every sound and music track in Islander (no recordings, no licences).

Run from the repo root:  python3 last-light/tools/make_sounds.py
Needs numpy and ffmpeg (with libvorbis). Writes OGG files to last-light/game/sounds/.
"""
import os
import subprocess
import tempfile
import wave

import numpy as np

RATE = 22050
OUT = os.path.join(os.path.dirname(__file__), "..", "game", "sounds")
rng = np.random.default_rng(20261119)


def t(seconds):
    return np.arange(int(seconds * RATE)) / RATE


def noise(seconds):
    return rng.uniform(-1, 1, int(seconds * RATE))


def band(x, lo, hi):
    """Keeps frequencies between lo and hi (Hz) using the FFT."""
    spec = np.fft.rfft(x)
    freqs = np.fft.rfftfreq(len(x), 1 / RATE)
    spec[(freqs < lo) | (freqs > hi)] = 0
    return np.fft.irfft(spec, len(x))


def env(n, attack, decay_rate):
    """Quick attack, then exponential decay."""
    a = max(1, int(attack * RATE))
    e = np.exp(-np.arange(n) / RATE * decay_rate)
    e[:a] *= np.linspace(0, 1, a)
    return e


def sweep(f0, f1, seconds, shape=1.0):
    """A sine whose pitch glides from f0 to f1."""
    tt = t(seconds)
    f = f0 + (f1 - f0) * (tt / seconds) ** shape
    return np.sin(2 * np.pi * np.cumsum(f) / RATE)


def norm(x, peak=0.9):
    m = np.max(np.abs(x)) or 1
    return x / m * peak


def fade(x, seconds=0.01):
    n = min(len(x) // 2, int(seconds * RATE))
    x = x.copy()
    x[:n] *= np.linspace(0, 1, n)
    x[-n:] *= np.linspace(1, 0, n)
    return x


def loopable(x, seconds=0.25):
    """Crossfades the end into the start so the sound loops without a click."""
    n = int(seconds * RATE)
    head, body, tail = x[:n], x[n:-n], x[-n:]
    ramp = np.linspace(0, 1, n)
    return np.concatenate([body, tail * (1 - ramp) + head * ramp])


def save(name, x, quality=4):
    os.makedirs(OUT, exist_ok=True)
    pcm = (np.clip(x, -1, 1) * 32767).astype(np.int16)
    with tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as f:
        path = f.name
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(pcm.tobytes())
    out = os.path.join(OUT, name + ".ogg")
    subprocess.run(["ffmpeg", "-loglevel", "error", "-y", "-i", path, "-c:a", "libvorbis",
                    "-q:a", str(quality), out], check=True)
    os.remove(path)
    print(f"{name}.ogg  {len(x) / RATE:.1f}s  {os.path.getsize(out) // 1024} KB")


# ---------- Effects ----------

def chop():
    n = noise(0.3)
    knock = band(n, 300, 2200) * env(len(n), 0.002, 28)
    body = sweep(210, 120, 0.3) * env(len(n), 0.002, 18)
    return fade(norm(knock * 0.8 + body * 0.6))


def mine():
    tt = t(0.45)
    ring = sum(np.sin(2 * np.pi * f * tt) * a for f, a in [(1250, 1), (1910, .6), (2780, .4), (3400, .25)])
    click = band(noise(0.45), 1500, 7000) * env(len(tt), 0.001, 70)
    return fade(norm(ring * env(len(tt), 0.001, 14) * 0.6 + click))


def pick():
    n = band(noise(0.35), 1500, 6000)
    e = np.sin(np.linspace(0, np.pi, len(n))) ** 2
    return fade(norm(n * e * (0.6 + 0.4 * np.sin(np.linspace(0, 40, len(n))))))


def step():
    n = band(noise(0.13), 120, 1600)
    return fade(norm(n * env(len(n), 0.004, 35)))


def eat():
    parts = []
    for i in range(3):
        n = band(noise(0.09), 800, 5000) * env(int(0.09 * RATE), 0.001, 45)
        parts += [n, np.zeros(int(0.07 * RATE))]
    return fade(norm(np.concatenate(parts)))


def build():
    thud = sweep(140, 70, 0.35) * env(int(0.35 * RATE), 0.001, 16)
    knock = band(noise(0.35), 400, 3000) * env(int(0.35 * RATE), 0.001, 40)
    x = thud + knock * 0.7
    return fade(norm(np.concatenate([x, np.zeros(int(0.05 * RATE)), x * 0.7])))


def craft():
    k = band(noise(0.12), 600, 4000) * env(int(0.12 * RATE), 0.001, 50)
    tt = t(0.6)
    chime = (np.sin(2 * np.pi * 880 * tt) + 0.5 * np.sin(2 * np.pi * 1320 * tt)) * env(len(tt), 0.005, 6)
    return fade(norm(np.concatenate([k, np.zeros(1500), k, np.zeros(1500), chime * 0.5])))


def swing():
    n = noise(0.22)
    e = np.sin(np.linspace(0, np.pi, len(n))) ** 3
    return fade(norm(band(n, 400, 2500) * e) * 0.6)


def hit():
    thump = sweep(160, 60, 0.2) * env(int(0.2 * RATE), 0.001, 22)
    slap = band(noise(0.2), 500, 4000) * env(int(0.2 * RATE), 0.001, 55)
    return fade(norm(thump + slap * 0.8))


def hurt():
    tt = t(0.35)
    groan = np.sign(np.sin(2 * np.pi * np.cumsum(np.linspace(190, 120, len(tt))) / RATE)) * 0.3
    groan = band(groan, 80, 1200) * env(len(tt), 0.01, 9)
    h = hit()
    groan[: len(h)] += h * 0.5
    return fade(norm(groan))


def wolf_howl():
    secs = 2.6
    tt = t(secs)
    shape = np.interp(tt, [0, 0.5, 1.6, secs], [380, 640, 600, 430])
    vib = 1 + 0.012 * np.sin(2 * np.pi * 5.5 * tt)
    phase = 2 * np.pi * np.cumsum(shape * vib) / RATE
    voice = np.sin(phase) + 0.35 * np.sin(2 * phase) + 0.15 * np.sin(3 * phase)
    breath = band(noise(secs), 600, 3000) * 0.05
    e = np.interp(tt, [0, 0.35, 2.0, secs], [0, 1, 0.8, 0])
    return fade(norm((voice + breath) * e) * 0.8)


def wolf_bite():
    secs = 0.5
    tt = t(secs)
    growl = band(noise(secs), 80, 900) * (0.6 + 0.4 * np.sin(2 * np.pi * 30 * tt))
    snap = band(noise(secs), 1500, 7000) * env(len(tt), 0.001, 60)
    return fade(norm(growl * env(len(tt), 0.02, 6) + snap))


def wolf_yelp():
    return fade(norm(sweep(900, 450, 0.3, 0.6) * env(int(0.3 * RATE), 0.005, 9)) * 0.7)


def discover():
    out = []
    for f in [523.25, 659.25, 783.99, 1046.5]:
        tt = t(0.5)
        out.append((np.sin(2 * np.pi * f * tt) + 0.3 * np.sin(4 * np.pi * f * tt)) * env(len(tt), 0.005, 5))
    x = np.zeros(int(1.6 * RATE))
    for i, note in enumerate(out):
        s = int(i * 0.14 * RATE)
        x[s:s + len(note)] += note
    return fade(norm(x) * 0.7)


def shrine():
    tt = t(3.0)
    bell = sum(np.sin(2 * np.pi * f * tt) * a for f, a in [(392, 1), (784.6, .5), (1176, .25), (1571, .12)])
    return fade(norm(bell * env(len(tt), 0.003, 1.4)) * 0.7)


def ui():
    tt = t(0.06)
    return fade(norm(np.sin(2 * np.pi * 1400 * tt) * env(len(tt), 0.001, 70)) * 0.5)


# ---------- Loops ----------

def fire_loop():
    secs = 6.0
    rumble = band(noise(secs), 40, 400) * 0.35
    hiss = band(noise(secs), 2000, 8000) * 0.05
    pops = np.zeros(int(secs * RATE))
    for _ in range(110):
        at = rng.integers(0, len(pops) - 800)
        size = rng.uniform(0.2, 1.0)
        n = band(noise(0.03), 1000, 9000) * env(int(0.03 * RATE), 0.0005, 160) * size
        pops[at:at + len(n)] += n
    return loopable(norm(rumble + hiss + pops * 0.9) * 0.8)


def day_loop():
    secs = 12.0
    breeze = band(noise(secs), 80, 700) * (0.5 + 0.5 * np.sin(np.linspace(0, 2 * np.pi, int(secs * RATE)))) * 0.15
    birds = np.zeros(int(secs * RATE))
    for _ in range(26):
        at = rng.integers(0, len(birds) - 9000)
        f0 = rng.uniform(2200, 3600)
        for k in range(rng.integers(2, 5)):
            c = sweep(f0, f0 * rng.uniform(1.15, 1.5), 0.08) * env(int(0.08 * RATE), 0.005, 25)
            s = at + int(k * 0.11 * RATE)
            birds[s:s + len(c)] += c * rng.uniform(0.2, 0.5)
    return loopable(norm(breeze + birds) * 0.6)


def night_loop():
    secs = 12.0
    tt = t(secs)
    wind = band(noise(secs), 60, 500) * (0.55 + 0.45 * np.sin(2 * np.pi * tt / secs)) * 0.5
    crickets = np.zeros(len(tt))
    for voice in range(3):
        f = 4300 + voice * 380
        rate = 2.6 + voice * 0.7
        gate = (np.sin(2 * np.pi * rate * tt + voice) > 0.55).astype(float)
        trill = (np.sin(2 * np.pi * 45 * tt) > 0).astype(float)
        crickets += np.sin(2 * np.pi * f * tt) * gate * trill * 0.12
    return loopable(norm(wind + band(crickets, 3000, 6000)) * 0.6)


# ---------- Music ----------

NOTE = {"C": 0, "D": 2, "E": 4, "F": 5, "G": 7, "A": 9, "B": 11}


def hz(name, octave):
    return 440.0 * 2 ** ((NOTE[name[0]] + (1 if "#" in name else -1 if "b" in name else 0) - 9) / 12 + (octave - 4))


def pad(freqs, seconds):
    tt = t(seconds)
    x = np.zeros(len(tt))
    for f in freqs:
        for detune in (-0.4, 0.4):
            ff = f + detune
            x += np.sin(2 * np.pi * ff * tt) + 0.25 * np.sin(4 * np.pi * ff * tt)
    e = np.interp(tt, [0, seconds * 0.35, seconds * 0.7, seconds], [0, 1, 0.9, 0])
    return x * e


def pluck(f, seconds):
    tt = t(seconds)
    return (np.sin(2 * np.pi * f * tt) + 0.4 * np.sin(4 * np.pi * f * tt) + 0.15 * np.sin(6 * np.pi * f * tt)) \
        * env(len(tt), 0.004, 3.2)


def music(chords, scale, bar_seconds, bars, melody_density, seed):
    local = np.random.default_rng(seed)
    total = bar_seconds * bars
    x = np.zeros(int(total * RATE))
    overlap = 1.2
    for b in range(bars):
        root, quality, octave = chords[b % len(chords)]
        third = 3 if quality == "m" else 4
        r = hz(root, octave)
        freqs = [r / 2, r, r * 2 ** (third / 12), r * 2 ** (7 / 12)]
        p = pad(freqs, bar_seconds + overlap) * 0.09
        s = int(b * bar_seconds * RATE)
        end = min(len(x), s + len(p))
        x[s:end] += p[: end - s]
        # A few soft plucked notes from the scale over each chord.
        for beat in range(4):
            if local.random() < melody_density:
                name, octv = scale[local.integers(0, len(scale))]
                note = pluck(hz(name, octv), 2.0) * 0.12
                ps = s + int(beat * bar_seconds / 4 * RATE)
                pe = min(len(x), ps + len(note))
                x[ps:pe] += note[: pe - ps]
    # Wrap the tail that spills past the end back onto the start, so it loops.
    return norm(x) * 0.75


def music_day():
    chords = [("C", "", 3), ("A", "m", 2), ("F", "", 2), ("G", "", 2)]
    scale = [("C", 5), ("D", 5), ("E", 5), ("G", 5), ("A", 5), ("C", 6)]
    return music(chords, scale, 4.0, 12, 0.55, 7)


def music_night():
    chords = [("D", "m", 2), ("Bb", "", 2), ("G", "m", 2), ("A", "", 2)]
    scale = [("D", 4), ("F", 4), ("G", 4), ("A", 4), ("C", 5), ("D", 5)]
    return music(chords, scale, 6.0, 8, 0.3, 11)


if __name__ == "__main__":
    for fn in [chop, mine, pick, step, eat, build, craft, swing, hit, hurt, wolf_howl, wolf_bite,
               wolf_yelp, discover, shrine, ui]:
        save(fn.__name__, fn())
    save("fire_loop", fire_loop(), 3)
    save("day_loop", day_loop(), 3)
    save("night_loop", night_loop(), 3)
    save("music_day", music_day(), 3)
    save("music_night", music_night(), 3)
