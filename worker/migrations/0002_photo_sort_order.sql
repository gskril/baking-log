ALTER TABLE photos ADD COLUMN sort_order INTEGER NOT NULL DEFAULT 0;

-- Backfill existing photos: assign sort_order based on created_at within each bake
UPDATE photos SET sort_order = (
  SELECT COUNT(*) FROM photos AS p2
  WHERE p2.bake_id = photos.bake_id AND p2.created_at < photos.created_at
);
