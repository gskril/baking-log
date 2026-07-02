// Generates the data backfill for migration 0003 from a pre-migration export.
//
// Usage: bun scripts/generate-backfill.ts <export.json> <out.sql>
//
// Amounts: "90 grams" / "90g" / ".5 cup" → amount_value + canonical unit.
// Times: bake_date is the schedule's start date; entries are walked in sort
// order and the date rolls forward a day whenever the wall-clock time moves
// backwards (e.g. 9:30 PM → 10:30 AM means the next morning).

interface ExportIngredient {
  id: string;
  amount: string;
}

interface ExportScheduleEntry {
  id: string;
  time: string;
}

interface ExportBake {
  id: string;
  bake_date: string;
  ingredients?: ExportIngredient[];
  schedule?: ExportScheduleEntry[];
}

// One-time data fixes agreed with Greg (2026-07-01): some schedule notes
// carried day-offset info ("Next day", "2 days later") that the old
// time-of-day-only format couldn't represent. For these entries the entry's
// day is previous entry's day + daysAfterPrev, and the note is replaced
// (null = note removed; the day info now lives in occurs_at).
const CORRECTIONS: Record<string, { daysAfterPrev?: number; note?: string | null }> = {
  // Jun 26 loaf, Bake "Next day" after Jun 27 shape → Jun 28
  '73b2749d-d0d0-4f2e-8950-da6a26c322f1': { daysAfterPrev: 1, note: null },
  // Jun 15 loaf, Bake "2 days later" after Jun 15 coil fold → Jun 17
  '186e25d4-7c18-47ce-af85-858592e5eed1': { daysAfterPrev: 2, note: null },
  // May 25 loaf, Bake "2 days later" after midnight shape → May 27 (~1.8d in fridge)
  '1828d13e-f47b-48ae-a654-ed7b0446c905': { daysAfterPrev: 1, note: null },
  // Mar 5 loaf, Bake "2 days later" after Mar 6 back-in-fridge → Mar 8; keep observation
  '7628d3f5-abd8-4129-aa1d-cc3fb87899cb': {
    daysAfterPrev: 2,
    note: 'Spread out a bit when dumped from the proofing basket, which indicates mild over profing',
  },
  // Feb 26 loaf, Bake "2 days in the fridge" after Feb 27 shape → Mar 1
  'a9d4a0f6-ac23-4e30-be32-7a01c567f270': { daysAfterPrev: 2, note: null },
  // Jun 26 loaf, S&F note "pause until tomorrow" is redundant now that dates are stored
  'df948c3b-018e-4712-b43f-84ac3b8c504d': { note: 'Put in fridge' },
};

const UNIT_MAP: Record<string, string> = {
  g: 'g',
  gram: 'g',
  grams: 'g',
  tsp: 'tsp',
  teaspoon: 'tsp',
  teaspoons: 'tsp',
  tbsp: 'tbsp',
  tablespoon: 'tbsp',
  tablespoons: 'tbsp',
  cup: 'cup',
  cups: 'cup',
};

function parseAmount(raw: string): { value: number; unit: string | null } | null {
  const trimmed = raw.trim().toLowerCase();
  if (!trimmed) return null;
  // Leading number, then the first alphabetic token as the unit. Trailing
  // junk (from historical corruption like "0.5 teaspoons g") is ignored.
  const match = trimmed.match(/^(\d*\.?\d+)\s*([a-z]+)?/);
  if (!match) return null;
  const value = Number(match[1]);
  if (!Number.isFinite(value)) return null;
  const unit = match[2] ? (UNIT_MAP[match[2]] ?? null) : null;
  if (match[2] && !unit) return null; // unrecognized unit — skip, don't guess
  return { value, unit };
}

function parseTimeMinutes(time: string): number | null {
  const match = time.trim().match(/^(\d{1,2}):(\d{2}) (AM|PM)$/);
  if (!match) return null;
  const hour = (Number(match[1]) % 12) + (match[3] === 'PM' ? 12 : 0);
  return hour * 60 + Number(match[2]);
}

function occursAt(bakeDate: string, dayOffset: number, minutes: number): string {
  const [y, m, d] = bakeDate.split('-').map(Number);
  const date = new Date(Date.UTC(y, m - 1, d + dayOffset));
  const day = date.toISOString().slice(0, 10);
  const hh = String(Math.floor(minutes / 60)).padStart(2, '0');
  const mm = String(minutes % 60).padStart(2, '0');
  return `${day}T${hh}:${mm}:00`;
}

const [exportPath, outPath] = process.argv.slice(2);
if (!exportPath || !outPath) {
  console.error('Usage: bun scripts/generate-backfill.ts <export.json> <out.sql>');
  process.exit(1);
}

const data = (await Bun.file(exportPath).json()) as { bakes: ExportBake[] };
const lines: string[] = [];
const warnings: string[] = [];
let ingredientCount = 0;
let scheduleCount = 0;

for (const bake of data.bakes) {
  for (const ing of bake.ingredients ?? []) {
    const parsed = parseAmount(ing.amount);
    if (!parsed) {
      if (ing.amount.trim()) warnings.push(`ingredient ${ing.id}: unparseable amount "${ing.amount}"`);
      continue;
    }
    const unitSql = parsed.unit ? `'${parsed.unit}'` : 'NULL';
    lines.push(`UPDATE ingredients SET amount_value = ${parsed.value}, unit = ${unitSql} WHERE id = '${ing.id}';`);
    ingredientCount++;
  }

  let dayOffset = 0;
  let prevMinutes: number | null = null;
  for (const entry of bake.schedule ?? []) {
    const minutes = parseTimeMinutes(entry.time);
    if (minutes === null) {
      warnings.push(`schedule entry ${entry.id}: unparseable time "${entry.time}"`);
      prevMinutes = null;
      continue;
    }
    const correction = CORRECTIONS[entry.id];
    if (correction?.daysAfterPrev !== undefined) {
      dayOffset += correction.daysAfterPrev;
    } else if (prevMinutes !== null && minutes < prevMinutes) {
      dayOffset++;
    }
    prevMinutes = minutes;
    lines.push(`UPDATE schedule_entries SET occurs_at = '${occursAt(bake.bake_date, dayOffset, minutes)}' WHERE id = '${entry.id}';`);
    if (correction && 'note' in correction) {
      const noteSql = correction.note === null ? 'NULL' : `'${correction.note!.replace(/'/g, "''")}'`;
      lines.push(`UPDATE schedule_entries SET note = ${noteSql} WHERE id = '${entry.id}';`);
    }
    scheduleCount++;
  }
}

await Bun.write(outPath, lines.join('\n') + '\n');
console.log(`Wrote ${lines.length} updates (${ingredientCount} ingredients, ${scheduleCount} schedule entries) to ${outPath}`);
for (const w of warnings) console.warn(`WARNING: ${w}`);
