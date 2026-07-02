import { Hono } from 'hono';
import { Env, BakeListItem, CreateBakeRequest, UpdateBakeRequest, Photo } from '../types';
import { getBakeWithDetails } from '../db/queries';
import { validateBakeRequest } from '../utils/validate';

const app = new Hono<{ Bindings: Env }>();

/** Store occurs_at uniformly with seconds ("YYYY-MM-DDTHH:MM:SS"). */
function withSeconds(occursAt: string | null | undefined): string | null {
  if (!occursAt) return null;
  return occursAt.length === 16 ? `${occursAt}:00` : occursAt;
}

async function replaceScheduleAndIngredients(
  db: D1Database,
  bakeId: string,
  schedule: CreateBakeRequest['schedule'],
  ingredients: CreateBakeRequest['ingredients']
) {
  if (schedule) {
    await db.prepare('DELETE FROM schedule_entries WHERE bake_id = ?').bind(bakeId).run();
    if (schedule.length) {
      const stmt = db.prepare(
        'INSERT INTO schedule_entries (id, bake_id, occurs_at, action, note, sort_order) VALUES (?, ?, ?, ?, ?, ?)'
      );
      await db.batch(
        schedule.map((entry, i) =>
          stmt.bind(crypto.randomUUID(), bakeId, withSeconds(entry.occurs_at), entry.action, entry.note ?? null, i)
        )
      );
    }
  }

  if (ingredients) {
    await db.prepare('DELETE FROM ingredients WHERE bake_id = ?').bind(bakeId).run();
    if (ingredients.length) {
      const stmt = db.prepare(
        'INSERT INTO ingredients (id, bake_id, name, amount_value, unit, note, sort_order) VALUES (?, ?, ?, ?, ?, ?, ?)'
      );
      await db.batch(
        ingredients.map((ing, i) =>
          stmt.bind(crypto.randomUUID(), bakeId, ing.name, ing.amount_value ?? null, ing.unit ?? null, ing.note ?? null, i)
        )
      );
    }
  }
}

// List all bakes
app.get('/', async (c) => {
  const limit = Math.min(Math.max(Number(c.req.query('limit')) || 50, 1), 200);
  const offset = Math.max(Number(c.req.query('offset')) || 0, 0);

  const bakes = await c.env.DB.prepare(
    `SELECT b.id, b.title, b.bake_date, b.notes,
            b.created_at, b.updated_at,
            (SELECT COUNT(*) FROM ingredients WHERE bake_id = b.id) AS ingredient_count
     FROM bakes b
     ORDER BY b.bake_date DESC, b.created_at DESC
     LIMIT ? OFFSET ?`
  )
    .bind(limit, offset)
    .all<BakeListItem>();

  return c.json({ bakes: bakes.results ?? [] });
});

// Get single bake with schedule, ingredients, and photos
app.get('/:id', async (c) => {
  const result = await getBakeWithDetails(c.env.DB, c.req.param('id'));
  if (!result) return c.json({ error: 'Not found' }, 404);
  return c.json(result);
});

// Create a new bake
app.post('/', async (c) => {
  const body = await c.req.json<CreateBakeRequest>();
  const invalid = validateBakeRequest(body, true);
  if (invalid) return c.json({ error: invalid }, 400);

  const id = crypto.randomUUID();
  const now = new Date().toISOString();

  await c.env.DB.prepare(
    'INSERT INTO bakes (id, title, bake_date, notes, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?)'
  )
    .bind(id, body.title ?? null, body.bake_date, body.notes ?? null, now, now)
    .run();

  await replaceScheduleAndIngredients(c.env.DB, id, body.schedule, body.ingredients);

  const result = await getBakeWithDetails(c.env.DB, id);
  return c.json(result, 201);
});

// Update a bake
app.put('/:id', async (c) => {
  const id = c.req.param('id');
  const body = await c.req.json<UpdateBakeRequest>();
  const invalid = validateBakeRequest(body, false);
  if (invalid) return c.json({ error: invalid }, 400);

  const existing = await c.env.DB.prepare('SELECT * FROM bakes WHERE id = ?')
    .bind(id)
    .first<{ id: string; title: string; bake_date: string; notes: string | null }>();

  if (!existing) return c.json({ error: 'Not found' }, 404);

  await c.env.DB.prepare(
    'UPDATE bakes SET title = ?, bake_date = ?, notes = ?, updated_at = ? WHERE id = ?'
  )
    .bind(
      body.title ?? existing.title,
      body.bake_date ?? existing.bake_date,
      body.notes ?? existing.notes,
      new Date().toISOString(),
      id
    )
    .run();

  await replaceScheduleAndIngredients(c.env.DB, id, body.schedule, body.ingredients);

  const result = await getBakeWithDetails(c.env.DB, id);
  return c.json(result);
});

// Delete a bake
app.delete('/:id', async (c) => {
  const id = c.req.param('id');

  const bake = await c.env.DB.prepare('SELECT * FROM bakes WHERE id = ?')
    .bind(id)
    .first();

  if (!bake) return c.json({ error: 'Not found' }, 404);

  // Delete associated photos from R2
  const photos = await c.env.DB.prepare('SELECT * FROM photos WHERE bake_id = ?')
    .bind(id)
    .all<Photo>();

  for (const photo of photos.results ?? []) {
    await c.env.PHOTOS.delete(photo.r2_key);
  }

  // Explicit deletes — don't rely on CASCADE since D1 may not enforce foreign keys
  await c.env.DB.batch([
    c.env.DB.prepare('DELETE FROM schedule_entries WHERE bake_id = ?').bind(id),
    c.env.DB.prepare('DELETE FROM ingredients WHERE bake_id = ?').bind(id),
    c.env.DB.prepare('DELETE FROM photos WHERE bake_id = ?').bind(id),
    c.env.DB.prepare('DELETE FROM bakes WHERE id = ?').bind(id),
  ]);

  return c.json({ ok: true });
});

export default app;
