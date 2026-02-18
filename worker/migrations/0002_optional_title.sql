-- SQLite doesn't support ALTER COLUMN, but D1 allows NULL in NOT NULL columns
-- when inserted explicitly. Instead, recreate the table.
CREATE TABLE bakes_new (
  id TEXT PRIMARY KEY,
  title TEXT,
  bake_date TEXT NOT NULL,
  ingredients TEXT,
  notes TEXT,
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  updated_at TEXT NOT NULL DEFAULT (datetime('now'))
);

INSERT INTO bakes_new SELECT * FROM bakes;
DROP TABLE bakes;
ALTER TABLE bakes_new RENAME TO bakes;

CREATE INDEX IF NOT EXISTS idx_bakes_date ON bakes(bake_date DESC);
