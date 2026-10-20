import { describe, expect, it } from "vitest";
import { inflate, rate, rateOne } from "../src/glicko";
import { GLICKO } from "../src/ranked_data";

describe("glicko-2", () => {
  it("reproduces the paper's worked example", () => {
    // Glickman's example: 1500/200/0.06 beats 1400/30, loses to 1550/100 and 1700/300, tau 0.5.
    expect(GLICKO.tau).toBe(0.5);
    const out = rate({ mu: 1500, rd: 200, vol: 0.06 }, [
      { mu: 1400, rd: 30, score: 1 },
      { mu: 1550, rd: 100, score: 0 },
      { mu: 1700, rd: 300, score: 0 },
    ]);
    expect(out.mu).toBeCloseTo(1464.06, 1); // 1464.05 exactly; the paper rounds its intermediates
    expect(out.rd).toBeCloseTo(151.52, 2);
    expect(out.vol).toBeCloseTo(0.05999, 4);
  });
  it("moves the winner up and the loser down", () => {
    const a = { mu: 1500, rd: 200, vol: 0.06 };
    const b = { mu: 1500, rd: 200, vol: 0.06 };
    const a2 = rateOne(a, b, 1);
    const b2 = rateOne(b, a, 0);
    expect(a2.mu).toBeGreaterThan(a.mu);
    expect(b2.mu).toBeLessThan(b.mu);
    expect(a2.mu - a.mu).toBeCloseTo(b.mu - b2.mu, 6); // mirror images
    expect(a2.rd).toBeLessThan(a.rd); // a result always tightens the deviation
  });
  it("inflates an idle deviation and caps it at rd_max", () => {
    expect(inflate(100, 0.06, 0)).toBe(100);
    expect(inflate(100, 0.06, 1)).toBeGreaterThan(100);
    expect(inflate(100, 0.06, 10)).toBeGreaterThan(inflate(100, 0.06, 1));
    expect(inflate(349.9, 0.06, 1e9)).toBe(GLICKO.rd_max);
    expect(inflate(100, 0.06, 1e12)).toBe(GLICKO.rd_max);
  });
  it("leaves a long-idle player's rating alone while the deviation rises", () => {
    const idle = rate({ mu: 1620, rd: 60, vol: 0.06 }, []);
    expect(idle.mu).toBe(1620);
    expect(idle.rd).toBeGreaterThan(60);
    expect(idle.rd).toBeCloseTo(inflate(60, 0.06, 1), 9); // one idle period, either way
    const wide = inflate(60, 0.06, 365);
    expect(wide).toBeGreaterThan(idle.rd);
    expect(wide).toBeLessThanOrEqual(GLICKO.rd_max);
  });
});
