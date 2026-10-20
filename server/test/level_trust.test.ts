import { describe, expect, it } from "vitest";
import { acceptLevel } from "../src/level_trust";
import { LEVEL_TRUST } from "../src/ranked_data";

const H = 3_600_000;
const T0 = 1_800_000_000_000;

describe("acceptLevel", () => {
  it("never goes down", () => {
    expect(acceptLevel(7, 3, T0 - 100 * H, T0)).toBe(7);
    expect(acceptLevel(7, 7, T0 - 100 * H, T0)).toBe(7);
  });
  it("a brand-new account is believed only up to the grace", () => {
    expect(acceptLevel(1, 9, T0, T0)).toBe(1 + LEVEL_TRUST.grace_levels);
    expect(acceptLevel(1, 2, T0, T0)).toBe(2);
  });
  it("the cap grows by the hour and stops at max_level", () => {
    const per = LEVEL_TRUST.max_levels_per_hour;
    expect(acceptLevel(1, 99, T0 - 3 * H, T0)).toBe(1 + LEVEL_TRUST.grace_levels + 3 * per);
    expect(acceptLevel(1, 99, T0 - 3.5 * H, T0)).toBe(1 + LEVEL_TRUST.grace_levels + Math.floor(3.5 * per));
    expect(acceptLevel(1, 99, T0 - 10_000 * H, T0)).toBe(LEVEL_TRUST.max_level);
    expect(acceptLevel(1, 5, T0 - 10_000 * H, T0)).toBe(5); // under the cap: taken as reported
  });
  it("a bad value keeps the current level", () => {
    expect(acceptLevel(4, 0, T0 - 100 * H, T0)).toBe(4);
    expect(acceptLevel(4, 2.5, T0 - 100 * H, T0)).toBe(4);
    expect(acceptLevel(4, "9", T0 - 100 * H, T0)).toBe(4);
    expect(acceptLevel(4, LEVEL_TRUST.max_level + 1, T0 - 100 * H, T0)).toBe(4);
    expect(acceptLevel(4, undefined, T0 - 100 * H, T0)).toBe(4);
  });
});
