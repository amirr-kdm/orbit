// The timer's alarm: a few synthesized tones (no sound files), played at the volume chosen in Settings.

export const ALARM_TONES = [
  { id: "chime", name: "Chime" }, { id: "bell", name: "Bell" }, { id: "marimba", name: "Marimba" },
  { id: "digital", name: "Digital" }, { id: "gentle", name: "Gentle" }, { id: "alarm", name: "Alarm clock" },
] as const;
export type AlarmTone = typeof ALARM_TONES[number]["id"];
export const DEFAULT_TONE: AlarmTone = "alarm";
export const DEFAULT_VOLUME = 0.8;

interface Note { f: number; t: number; d: number; type?: OscillatorType; mix?: [number, number][] }
const SCORES: Record<AlarmTone, Note[]> = {
  chime: [{ f: 880, t: 0, d: 0.9 }, { f: 1100, t: 0.35, d: 0.9 }, { f: 1320, t: 0.7, d: 1.1 }],
  bell: [{ f: 660, t: 0, d: 2.2, mix: [[1, 1], [2.76, 0.4], [5.4, 0.2]] }, { f: 660, t: 1.1, d: 2.2, mix: [[1, 1], [2.76, 0.4], [5.4, 0.2]] }],
  marimba: [{ f: 523, t: 0, d: 0.5, type: "triangle" }, { f: 659, t: 0.18, d: 0.5, type: "triangle" }, { f: 784, t: 0.36, d: 0.5, type: "triangle" }, { f: 1047, t: 0.54, d: 0.8, type: "triangle" }],
  digital: [0, 1, 2, 3, 4].flatMap((r) => [0, 0.21, 0.42].map((t) => ({ f: 2600, t: r * 1.4 + t, d: 0.14, type: "square" as OscillatorType }))),
  gentle: [{ f: 392, t: 0, d: 1.6 }, { f: 523, t: 0.5, d: 1.8 }],
  // beep-beep-beep-beep … pause …, four times, like an alarm clock
  alarm: [0, 1, 2, 3].flatMap((r) => [0, 0.19, 0.38, 0.57].map((t) => ({ f: 1450, t: r * 1.3 + t, d: 0.11, type: "square" as OscillatorType }))),
};

/** Play a tone at `volume` (0…1). Returns quietly where audio is unavailable. */
export function playAlarm(tone: string | undefined, volume: number | undefined) {
  const vol = Math.min(1, Math.max(0, volume ?? DEFAULT_VOLUME));
  if (vol <= 0) return;
  try {
    const a = new AudioContext();
    if (a.state === "suspended") void a.resume();
    const score = SCORES[(tone as AlarmTone) in SCORES ? (tone as AlarmTone) : DEFAULT_TONE];
    // louder than the raw tone at full volume (+15 dB), with a limiter so it gets loud without cracking
    const limiter = a.createDynamicsCompressor();
    limiter.threshold.value = -6; limiter.knee.value = 0; limiter.ratio.value = 20; limiter.attack.value = 0.002; limiter.release.value = 0.1;
    limiter.connect(a.destination);
    const master = a.createGain(); master.gain.value = vol * vol * 3.2; master.connect(limiter);
    for (const n of score) {
      const t0 = a.currentTime + n.t;
      for (const [mul, amp] of n.mix ?? [[1, 1]]) {
        const o = a.createOscillator(), g = a.createGain();
        o.type = n.type ?? "sine"; o.frequency.value = n.f * mul; o.connect(g); g.connect(master);
        g.gain.setValueAtTime(0.0001, t0); g.gain.exponentialRampToValueAtTime(amp * 0.7, t0 + 0.02); g.gain.exponentialRampToValueAtTime(0.0008, t0 + n.d);
        o.start(t0); o.stop(t0 + n.d + 0.05);
      }
    }
  } catch { /* no audio */ }
}
