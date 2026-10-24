/** UTC day numbers (ms since the epoch / one day): the unit of "once a day" everywhere online. */
export const DAY_MS = 86_400_000;
export const dayOf = (ms: number): number => Math.floor(ms / DAY_MS);
export const dayStart = (day: number): number => day * DAY_MS;
