-- Migration number: 0003 	 2026-07-01T00:00:00.000Z
-- Structured data model:
--   ingredients.amount TEXT ("90 grams")  →  amount_value REAL + unit TEXT ('g'|'tsp'|'tbsp'|'cup')
--   schedule_entries.time TEXT ("9:30 PM") →  occurs_at TEXT, local wall-clock ISO 8601
--                                             ("YYYY-MM-DDTHH:MM:SS", no timezone — a bake
--                                             schedule is in the baker's local time)
-- Old string columns are dropped here; values are backfilled from a pre-migration
-- export by scripts/generate-backfill.ts.

CREATE TABLE ingredients_new (
  id TEXT PRIMARY KEY,
  bake_id TEXT NOT NULL REFERENCES bakes(id),
  name TEXT NOT NULL,
  amount_value REAL,
  unit TEXT CHECK (unit IN ('g', 'tsp', 'tbsp', 'cup')),
  note TEXT,
  sort_order INTEGER NOT NULL DEFAULT 0,
  created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now'))
);

INSERT INTO ingredients_new (id, bake_id, name, note, sort_order, created_at)
SELECT id, bake_id, name, note, sort_order, created_at FROM ingredients;

DROP TABLE ingredients;
ALTER TABLE ingredients_new RENAME TO ingredients;
CREATE INDEX IF NOT EXISTS idx_ingredients_bake ON ingredients(bake_id);

CREATE TABLE schedule_entries_new (
  id TEXT PRIMARY KEY,
  bake_id TEXT NOT NULL REFERENCES bakes(id) ON DELETE CASCADE,
  occurs_at TEXT,
  action TEXT NOT NULL,
  note TEXT,
  sort_order INTEGER NOT NULL DEFAULT 0,
  created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now'))
);

INSERT INTO schedule_entries_new (id, bake_id, action, note, sort_order, created_at)
SELECT id, bake_id, action, note, sort_order, created_at FROM schedule_entries;

DROP TABLE schedule_entries;
ALTER TABLE schedule_entries_new RENAME TO schedule_entries;
CREATE INDEX IF NOT EXISTS idx_schedule_bake ON schedule_entries(bake_id);

-- Normalize legacy datetime('now') timestamps ("YYYY-MM-DD HH:MM:SS", UTC) to ISO 8601
UPDATE photos SET created_at = replace(created_at, ' ', 'T') || 'Z' WHERE created_at LIKE '% %';
UPDATE bakes SET created_at = replace(created_at, ' ', 'T') || 'Z' WHERE created_at LIKE '% %';
UPDATE bakes SET updated_at = replace(updated_at, ' ', 'T') || 'Z' WHERE updated_at LIKE '% %';
UPDATE webhooks SET created_at = replace(created_at, ' ', 'T') || 'Z' WHERE created_at LIKE '% %';
