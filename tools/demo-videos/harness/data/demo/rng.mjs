// Seeded randomness. The dataset must come out identical for the same run day,
// so nothing here reads Math.random or the clock: every stream is a mulberry32
// seeded from a fixed string.

function hash(str) {
  let h = 2166136261;
  for (let i = 0; i < str.length; i++) {
    h ^= str.charCodeAt(i);
    h = Math.imul(h, 16777619);
  }
  return h >>> 0;
}

export class Rng {
  constructor(seed) {
    this.s = typeof seed === 'number' ? seed >>> 0 : hash(String(seed));
  }

  /** [0, 1) */
  next() {
    this.s = (this.s + 0x6d2b79f5) >>> 0;
    let t = this.s;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  }

  /** Integer in [lo, hi]. */
  int(lo, hi) { return lo + Math.floor(this.next() * (hi - lo + 1)); }

  /** Float in [lo, hi). */
  float(lo, hi) { return lo + this.next() * (hi - lo); }

  chance(p) { return this.next() < p; }

  pick(list) { return list[Math.floor(this.next() * list.length)]; }

  /** Picks from [[weight, value], …]. */
  weighted(pairs) {
    const total = pairs.reduce((s, [w]) => s + w, 0);
    let r = this.next() * total;
    for (const [w, v] of pairs) {
      r -= w;
      if (r < 0) return v;
    }
    return pairs[pairs.length - 1][1];
  }
}
