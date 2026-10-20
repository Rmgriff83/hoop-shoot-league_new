/**
 * Glicko-2, straight from Glickman's paper (glicko.net/glicko/glicko2.pdf),
 * one step at a time: scale to the internal mu/phi, v and delta from the
 * period's results, the volatility iteration, the new phi and mu, back to
 * the 1500 scale. Pure: the numbers come from ranked_data.ts.
 */
import { GLICKO } from "./ranked_data";

export interface Rating { mu: number; rd: number; vol: number }
export interface Result { mu: number; rd: number; score: number }

const SCALE = 173.7178;
const EPS = 1e-6;
const PI2 = Math.PI * Math.PI;

const g = (phi: number) => 1 / Math.sqrt(1 + (3 * phi * phi) / PI2);
const E = (mu: number, muj: number, phij: number) => 1 / (1 + Math.exp(-g(phij) * (mu - muj)));

/** One rating period for `player` with these results (score 1 win, 0 loss, 0.5 draw). */
export function rate(player: Rating, results: Result[]): Rating {
  const mu = (player.mu - GLICKO.mu0) / SCALE;
  const phi = player.rd / SCALE;
  const sigma = player.vol;
  if (results.length === 0) {
    // Step 6 only: the rating drifts by the volatility and nothing else.
    const phiStar = Math.sqrt(phi * phi + sigma * sigma);
    return { mu: player.mu, rd: Math.min(GLICKO.rd_max, phiStar * SCALE), vol: sigma };
  }
  // Steps 3 and 4: v, the estimated variance, and delta, the improvement.
  const opp = results.map((r) => ({ mu: (r.mu - GLICKO.mu0) / SCALE, phi: r.rd / SCALE, s: r.score }));
  let vInv = 0;
  let sum = 0;
  for (const o of opp) {
    const e = E(mu, o.mu, o.phi);
    const gj = g(o.phi);
    vInv += gj * gj * e * (1 - e);
    sum += gj * (o.s - e);
  }
  const v = 1 / vInv;
  const delta = v * sum;
  // Step 5: the new volatility by the Illinois algorithm.
  const a = Math.log(sigma * sigma);
  const tau = GLICKO.tau;
  const f = (x: number) => {
    const ex = Math.exp(x);
    const d2 = delta * delta;
    const p2 = phi * phi;
    return (ex * (d2 - p2 - v - ex)) / (2 * (p2 + v + ex) * (p2 + v + ex)) - (x - a) / (tau * tau);
  };
  let A = a;
  let B: number;
  if (delta * delta > phi * phi + v) {
    B = Math.log(delta * delta - phi * phi - v);
  } else {
    let k = 1;
    while (f(a - k * tau) < 0) k += 1;
    B = a - k * tau;
  }
  let fA = f(A);
  let fB = f(B);
  while (Math.abs(B - A) > EPS) {
    const C = A + ((A - B) * fA) / (fB - fA);
    const fC = f(C);
    if (fC * fB < 0) { A = B; fA = fB; } else { fA /= 2; }
    B = C;
    fB = fC;
  }
  const sigmaNew = Math.exp(A / 2);
  // Steps 6 and 7: the pre-period deviation, then the new deviation and rating.
  const phiStar = Math.sqrt(phi * phi + sigmaNew * sigmaNew);
  const phiNew = 1 / Math.sqrt(1 / (phiStar * phiStar) + 1 / v);
  const muNew = mu + phiNew * phiNew * sum;
  // Step 8: back to the 1500 scale.
  return { mu: muNew * SCALE + GLICKO.mu0, rd: Math.min(GLICKO.rd_max, phiNew * SCALE), vol: sigmaNew };
}

/** One match against one opponent: 1 for a win, 0 for a loss. */
export function rateOne(player: Rating, opp: { mu: number; rd: number }, score: number): Rating {
  return rate(player, [{ mu: opp.mu, rd: opp.rd, score }]);
}

/**
 * A deviation after `periods` idle rating periods (period_days each): step 6
 * of the paper repeated, on the internal scale (phi² + sigma²·t), never past rd_max.
 */
export function inflate(rd: number, vol: number, periods: number): number {
  const phi = rd / SCALE;
  const t = Math.max(0, periods);
  return Math.min(GLICKO.rd_max, Math.sqrt(phi * phi + vol * vol * t) * SCALE);
}

/** Idle rating periods between two instants. */
export function periodsBetween(fromMs: number, toMs: number): number {
  return Math.max(0, toMs - fromMs) / (GLICKO.period_days * 86_400_000);
}
