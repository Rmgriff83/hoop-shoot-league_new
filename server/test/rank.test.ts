import { describe, expect, it } from "vitest";
import ladder from "../../tests/fixtures/ranked_ladder.json";
import { applyResult, bandOf, compareRank, conservative, defaultRow, tierIndex, type RatingRow } from "../src/rank";
import { SHIELD, TIERS } from "../src/ranked_data";

const NOW = 1_800_000_000_000;
/** A row at a rating, already at the rank that rating earns. */
function rowAt(mu: number, rd: number, over: Partial<RatingRow> = {}): RatingRow {
  const cons = conservative(mu, rd);
  const band = bandOf(cons);
  return { ...defaultRow("p", NOW), mu, rd, cons, tier: band.tier, division: band.division, peak_tier: band.tier, peak_division: band.division, ...over };
}
const strong = { mu: 2400, rd: 40 };
const weak = { mu: 700, rd: 40 };

describe("the ladder", () => {
  it("maps every fixture row", () => {
    for (const c of ladder.cases) expect(bandOf(c.cons), `cons ${c.cons}`).toEqual({ tier: c.tier, division: c.division });
    for (const c of ladder.conservative) expect(conservative(c.mu, c.rd), `mu ${c.mu} rd ${c.rd}`).toBe(c.cons);
  });
  it("orders tiers and divisions", () => {
    expect(tierIndex("rookie")).toBe(0);
    expect(tierIndex("legend")).toBe(TIERS.length - 1);
    expect(compareRank({ tier: "pro", division: 3 }, { tier: "starter", division: 1 })).toBeGreaterThan(0);
    expect(compareRank({ tier: "pro", division: 1 }, { tier: "pro", division: 2 })).toBeGreaterThan(0);
    expect(compareRank({ tier: "pro", division: 2 }, { tier: "pro", division: 2 })).toBe(0);
  });
});

describe("applyResult", () => {
  it("raises a new player's cons on the first win", () => {
    const r = applyResult(defaultRow("p", NOW), { mu: 1500, rd: 350 }, "win", NOW);
    expect(r.after.cons).toBeGreaterThan(r.before.cons);
    expect(r.row).toMatchObject({ games: 1, wins: 1, losses: 0, win_streak: 1, loss_streak: 0 });
    expect(r.row.updated_at).toBe(NOW);
  });
  it("a promotion sets the shield and the peak", () => {
    // Rated STARTER II (cons 1060) but still shown as STARTER III: the next result lifts it.
    const row = rowAt(1140, 40, { tier: "starter", division: 3, peak_tier: "starter", peak_division: 3 });
    const r = applyResult(row, strong, "win", NOW);
    expect(r.events).toEqual(["promoted"]);
    expect(r.row.shield_left).toBe(SHIELD);
    expect(compareRank({ tier: r.row.tier, division: r.row.division }, { tier: "starter", division: 3 })).toBeGreaterThan(0);
    expect({ tier: r.row.peak_tier, division: r.row.peak_division }).toEqual({ tier: r.row.tier, division: r.row.division });
  });
  it("three shielded matches, then the demotion on the fourth", () => {
    // Just promoted into PRO I (the shield is full) while rated PRO II (cons 1200): every loss asks for a demotion.
    let row = rowAt(1300, 50, { tier: "pro", division: 1, peak_tier: "pro", peak_division: 1, shield_left: SHIELD });
    const events: string[][] = [];
    for (let i = 0; i < 4; i++) {
      const r = applyResult(row, strong, "loss", NOW);
      events.push(r.events);
      row = r.row;
    }
    expect(events).toEqual([["shielded"], ["shielded"], ["shielded"], ["demoted"]]);
    expect(row.shield_left).toBe(0);
    expect(compareRank({ tier: row.tier, division: row.division }, { tier: "pro", division: 1 })).toBeLessThan(0);
    expect(row.loss_streak).toBe(4);
  });
  it("the peak tier is a floor: a STARTER who keeps losing stays STARTER III", () => {
    // Shown STARTER I with one shield left, rated under 1000 already (cons 940).
    let row = rowAt(1020, 40, { tier: "starter", division: 1, peak_tier: "starter", peak_division: 1, shield_left: 1 });
    const first = applyResult(row, strong, "loss", NOW);
    expect(first.events).toEqual(["shielded"]);
    const second = applyResult(first.row, strong, "loss", NOW);
    expect(second.events).toEqual(["floored"]);
    expect({ tier: second.row.tier, division: second.row.division }).toEqual({ tier: "starter", division: 3 });
    row = second.row;
    for (let i = 0; i < 20; i++) {
      const r = applyResult(row, strong, "loss", NOW);
      expect(r.events).toEqual([]); // the floor holds quietly
      row = r.row;
    }
    expect(row.cons).toBeLessThan(1000);
    expect({ tier: row.tier, division: row.division }).toEqual({ tier: "starter", division: 3 });
    expect(row.peak_tier).toBe("starter");
  });
  it("never lowers the peak and resets the other streak", () => {
    const row = rowAt(1700, 40, { peak_tier: "legend", peak_division: 1, tier: "legend", division: 1, win_streak: 3 });
    const r = applyResult(row, strong, "loss", NOW);
    expect(r.row.peak_tier).toBe("legend");
    expect(r.row.win_streak).toBe(0);
    expect(r.row.loss_streak).toBe(1);
    const w = applyResult(r.row, weak, "win", NOW);
    expect(w.row.loss_streak).toBe(0);
    expect(w.row.win_streak).toBe(1);
  });
});
