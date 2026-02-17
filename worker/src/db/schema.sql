CREATE TABLE IF NOT EXISTS bakes (
  id TEXT PRIMARY KEY,
  title TEXT NOT NULL,
  bake_date TEXT NOT NULL,
  ingredients TEXT,
  notes TEXT,
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  updated_at TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE TABLE IF NOT EXISTS schedule_entries (
  id TEXT PRIMARY KEY,
  bake_id TEXT NOT NULL REFERENCES bakes(id) ON DELETE CASCADE,
  time TEXT NOT NULL,
  action TEXT NOT NULL,
  note TEXT,
  sort_order INTEGER NOT NULL DEFAULT 0,
  created_at TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE TABLE IF NOT EXISTS photos (
  id TEXT PRIMARY KEY,
  bake_id TEXT NOT NULL REFERENCES bakes(id) ON DELETE CASCADE,
  r2_key TEXT NOT NULL,
  caption TEXT,
  created_at TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE TABLE IF NOT EXISTS webhooks (
  id TEXT PRIMARY KEY,
  url TEXT NOT NULL,
  events TEXT NOT NULL DEFAULT '["*"]',
  secret TEXT,
  active INTEGER NOT NULL DEFAULT 1,
  created_at TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE TABLE IF NOT EXISTS ingredients (
  id TEXT PRIMARY KEY,
  bake_id TEXT NOT NULL REFERENCES bakes(id),
  name TEXT NOT NULL,
  amount TEXT NOT NULL,
  note TEXT,
  sort_order INTEGER NOT NULL DEFAULT 0,
  created_at TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_schedule_bake ON schedule_entries(bake_id);
CREATE INDEX IF NOT EXISTS idx_photos_bake ON photos(bake_id);
CREATE INDEX IF NOT EXISTS idx_ingredients_bake ON ingredients(bake_id);
CREATE INDEX IF NOT EXISTS idx_bakes_date ON bakes(bake_date DESC);
