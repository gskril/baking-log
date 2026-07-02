import { Hono } from 'hono';
import { Env, BakeListItem, CreateBakeRequest, UpdateBakeRequest, Photo } from '../types';
import { getBakeWithDetails } from '../db/queries';
import { parseJsonBody, validateBakeRequest } from '../utils/validate';

const app = new Hono<{ Bindings: Env }>();

/** Store occurs_at uniformly with seconds ("YYYY-MM-DDTHH:MM:SS"). */
function withSeconds(occursAt: string | null | undefined): string | null {
  if (!occursAt) return null;
  return occursAt.length === 16 ? `${occursAt}:00` : occursAt;
}

/**
 * Statements that replace a bake's schedule and ingredients. Returned (not run)
 * so callers can bundle them with other writes into a single D1 batch.
 */
function replaceScheduleAndIngredientStatements(
  db: D1Database,
  bakeId: string,
  schedule: CreateBakeRequest['schedule'],
  ingredients: CreateBakeRequest['ingredients']
): D1PreparedStatement[] {
  const statements: D1PreparedStatement[] = [];

  if (schedule) {
    statements.push(db.prepare('DELETE FROM schedule_entries WHERE bake_id = ?').bind(bakeId));
    const stmt = db.prepare(
      'INSERT INTO schedule_entries (id, bake_id, occurs_at, action, note, sort_order) VALUES (?, ?, ?, ?, ?, ?)'
    );
    schedule.forEach((entry, i) => {
      statements.push(
        stmt.bind(crypto.randomUUID(), bakeId, withSeconds(entry.occurs_at), entry.action, entry.note ?? null, i)
      );
    });
  }

  if (ingredients) {
    statements.push(db.prepare('DELETE FROM ingredients WHERE bake_id = ?').bind(bakeId));
    const stmt = db.prepare(
      'INSERT INTO ingredients (id, bake_id, name, amount_value, unit, note, sort_order) VALUES (?, ?, ?, ?, ?, ?, ?)'
    );
    ingredients.forEach((ing, i) => {
      statements.push(
        stmt.bind(crypto.randomUUID(), bakeId, ing.name, ing.amount_value ?? null, ing.unit ?? null, ing.note ?? null, i)
      );
    });
  }

  return statements;
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
  const body = await parseJsonBody<CreateBakeRequest>(c.req.raw);
  if (!body) return c.json({ error: 'Invalid JSON body' }, 400);
  const invalid = validateBakeRequest(body, true);
  if (invalid) return c.json({ error: invalid }, 400);

  const id = crypto.randomUUID();
  const now = new Date().toISOString();

  await c.env.DB.batch([
    c.env.DB.prepare(
      'INSERT INTO bakes (id, title, bake_date, notes, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?)'
    ).bind(id, body.title ?? null, body.bake_date, body.notes ?? null, now, now),
    ...replaceScheduleAndIngredientStatements(c.env.DB, id, body.schedule, body.ingredients),
  ]);

  const result = await getBakeWithDetails(c.env.DB, id);
  return c.json(result, 201);
});

// Update a bake
app.put('/:id', async (c) => {
  const id = c.req.param('id');
  const body = await parseJsonBody<UpdateBakeRequest>(c.req.raw);
  if (!body) return c.json({ error: 'Invalid JSON body' }, 400);
  const invalid = validateBakeRequest(body, false);
  if (invalid) return c.json({ error: invalid }, 400);

  const existing = await c.env.DB.prepare('SELECT id FROM bakes WHERE id = ?')
    .bind(id)
    .first<{ id: string }>();

  if (!existing) return c.json({ error: 'Not found' }, 404);

  // A key present with an explicit null clears the field; an absent key
  // leaves it unchanged. (COALESCE can't tell those apart.)
  const sets: string[] = [];
  const values: (string | null)[] = [];
  if ('title' in body) {
    sets.push('title = ?');
    values.push(body.title ?? null);
  }
  if ('bake_date' in body) {
    // Validated above: present bake_date is always a YYYY-MM-DD string.
    sets.push('bake_date = ?');
    values.push(body.bake_date!);
  }
  if ('notes' in body) {
    sets.push('notes = ?');
    values.push(body.notes ?? null);
  }
  sets.push('updated_at = ?');
  values.push(new Date().toISOString());

  await c.env.DB.batch([
    c.env.DB.prepare(`UPDATE bakes SET ${sets.join(', ')} WHERE id = ?`).bind(...values, id),
    ...replaceScheduleAndIngredientStatements(c.env.DB, id, body.schedule, body.ingredients),
  ]);

  const result = await getBakeWithDetails(c.env.DB, id);
  return c.json(result);
});

// Delete a bake
app.delete('/:id', async (c) => {
  const id = c.req.param('id');

  const [bakeRes, photosRes] = await c.env.DB.batch([
    c.env.DB.prepare('SELECT id FROM bakes WHERE id = ?').bind(id),
    c.env.DB.prepare('SELECT id, r2_key FROM photos WHERE bake_id = ?').bind(id),
  ]);

  if (!bakeRes.results?.length) return c.json({ error: 'Not found' }, 404);

  const photos = (photosRes.results ?? []) as Pick<Photo, 'id' | 'r2_key'>[];

  // Delete associated photos from R2 (bulk) and purge their edge-cached copies
  if (photos.length) {
    await c.env.PHOTOS.delete(photos.map((p) => p.r2_key));
    c.executionCtx.waitUntil(
      Promise.all(
        photos.map((p) =>
          caches.default.delete(new Request(new URL(`/api/photos/${p.id}/image`, c.req.url)))
        )
      )
    );
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
