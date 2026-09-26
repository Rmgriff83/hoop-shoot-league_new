/**
 * Golden-grid dump: runs the ORIGINAL TypeScript sim over a deterministic
 * launch grid and writes fixtures for the GDScript port to replay.
 * Run from the hoop_shoot folder:
 *   (cd ../../hoop_shoot_league && npx tsx ../godot/hoop_shoot/tools/dump_golden.mjs)
 * or with an explicit output path as argv[2].
 */
import { writeFileSync } from 'node:fs'
import { fileURLToPath } from 'node:url'
import { dirname, join } from 'node:path'
import { simulateShot } from '/Users/rossgriffus/Documents/projects/hoop_shoot_league/src/core/physics/shotSim.ts'

const rows = []
for (let angle = 25; angle <= 75; angle += 2.5) {
  for (let speed = 7; speed <= 11; speed += 0.25) {
    for (const vz of [-0.6, -0.3, 0, 0.3, 0.6]) {
      const out = simulateShot({ angleDeg: angle, speed, vz })
      rows.push({
        angle_deg: angle,
        speed,
        vz,
        type: out.type,
        points: out.points,
        made: out.made,
        rim_contacts: out.rimContacts,
        board_contacts: out.boardContacts,
        entry_angle_deg: out.entryAngleDeg,
      })
    }
  }
}

const here = dirname(fileURLToPath(import.meta.url))
const outPath = process.argv[2] ?? join(here, '..', 'tests', 'fixtures', 'golden_grid.json')
writeFileSync(outPath, JSON.stringify(rows))
console.log(`wrote ${rows.length} rows to ${outPath}`)
