# -*- coding: utf-8 -*-
"""Synthesises the seven notification tones into assets/sounds/notif_*.wav.

Run from the project root:  python tool/gen_sounds.py

Pure stdlib (wave + math) — no sample libraries, nothing downloaded. Each tone
is a short additive-synthesis blip: a couple of sine partials shaped by an
exponential decay envelope, which is what makes a synthesised tone read as a
"chime" rather than a beep. Attack and release are always ramped, because a
waveform that starts or stops at a non-zero sample produces an audible click.
"""
import io
import math
import os
import struct
import wave

RATE = 44100


def envelope(i, n, attack=0.008, decay=3.5):
    """Exponential decay with a short linear attack, in [0, 1]."""
    t = i / RATE
    total = n / RATE
    a = min(1.0, t / attack) if attack > 0 else 1.0
    d = math.exp(-decay * t / total)
    # Force the tail to zero so the file never ends mid-cycle.
    tail = min(1.0, (n - i) / (RATE * 0.01))
    return a * d * tail


def tone(partials, dur, decay=3.5, vib=0.0):
    """partials: list of (frequency_hz, amplitude)."""
    n = int(RATE * dur)
    out = []
    for i in range(n):
        t = i / RATE
        s = 0.0
        for (f, amp) in partials:
            freq = f * (1 + vib * math.sin(2 * math.pi * 5.5 * t))
            s += amp * math.sin(2 * math.pi * freq * t)
        out.append(s * envelope(i, n, decay=decay))
    return out


def seq(*segments):
    """Concatenates segments, which is how the multi-note tones are built."""
    out = []
    for s in segments:
        out.extend(s)
    return out


def silence(dur):
    return [0.0] * int(RATE * dur)


# Notes (equal temperament, A4 = 440).
def note(name):
    semis = {'C': 0, 'D': 2, 'E': 4, 'F': 5, 'G': 7, 'A': 9, 'B': 11}
    letter, octave = name[0], int(name[-1])
    n = semis[letter] + (1 if '#' in name else 0) + (octave - 4) * 12 - 9
    return 440.0 * (2 ** (n / 12))


def bell(f, dur, decay=3.5):
    """Fundamental + octave + a quiet fifth — a simple bell-ish spectrum."""
    return tone([(f, 0.62), (f * 2, 0.24), (f * 3, 0.08)], dur, decay=decay)


TONES = {
    # Two clean descending notes — the neutral default.
    'classic': lambda: seq(bell(note('E6'), 0.16), bell(note('B5'), 0.34)),
    # Low, gentle, slow decay.
    'soft': lambda: seq(tone([(note('A4'), 0.5), (note('E5'), 0.2)], 0.5, decay=2.6)),
    # High and glassy, three quick partials.
    'crystal': lambda: seq(bell(note('B6'), 0.12), bell(note('E7'), 0.12),
                           bell(note('G7'), 0.3, decay=4.5)),
    # Three even taps.
    'pulse': lambda: seq(bell(note('D6'), 0.09, decay=6), silence(0.045),
                         bell(note('D6'), 0.09, decay=6), silence(0.045),
                         bell(note('D6'), 0.2, decay=5)),
    # The brand tone: rising fourth, slight vibrato on the tail.
    'sigma': lambda: seq(bell(note('C6'), 0.13),
                         tone([(note('G6'), 0.55), (note('C7'), 0.18)], 0.42,
                              decay=3.2, vib=0.004)),
    # Wide interval, synthetic feel.
    'neo': lambda: seq(bell(note('F#6'), 0.1, decay=7),
                       bell(note('C#7'), 0.1, decay=7),
                       bell(note('F#5'), 0.34, decay=3)),
    # One short rounded pop.
    'bubble': lambda: seq(tone([(note('G5'), 0.6), (note('D6'), 0.22)], 0.17,
                               decay=7.5)),

    # ── In-chat feedback, NOT selectable notification tones ──
    # Much shorter and drier than the tones above: these fire on every single
    # send/receive, so any audible tail becomes maddening within a minute.
    'send': lambda: seq(tone([(note('A5'), 0.5), (note('E6'), 0.16)], 0.085,
                             decay=11)),
    'receive': lambda: seq(tone([(note('E5'), 0.5), (note('B5'), 0.18)], 0.11,
                                decay=9)),
}


def write_wav(path, samples):
    peak = max(1e-9, max(abs(s) for s in samples))
    # Normalise to -3 dBFS: loud enough to hear over a room, with headroom so
    # no sample clips after the int16 rounding.
    gain = 0.707 / peak
    frames = io.BytesIO()
    for s in samples:
        v = int(max(-32767, min(32767, s * gain * 32767)))
        frames.write(struct.pack('<h', v))
    with wave.open(path, 'wb') as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(frames.getvalue())


def main():
    # Two destinations, both required and NOT interchangeable:
    #   assets/sounds  — what the in-app preview player reads.
    #   res/raw        — what an Android notification channel can reference.
    # A channel's sound is a platform resource; it cannot point at a Flutter
    # asset, and it is frozen once the channel exists (see NotificationService,
    # which creates one channel per tone for exactly this reason).
    asset_dir = os.path.join('assets', 'sounds')
    raw_dir = os.path.join('android', 'app', 'src', 'main', 'res', 'raw')
    os.makedirs(asset_dir, exist_ok=True)
    os.makedirs(raw_dir, exist_ok=True)
    for name, build in TONES.items():
        samples = build()
        for d in (asset_dir, raw_dir):
            path = os.path.join(d, 'notif_%s.wav' % name)
            write_wav(path, samples)
            print('%-52s %6.1f KB' % (path, os.path.getsize(path) / 1024))


if __name__ == '__main__':
    main()
