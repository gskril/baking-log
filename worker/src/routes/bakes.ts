import { Hono } from 'hono';
import { Env, Bake, BakeWithDetails, ScheduleEntry, Photo, CreateBakeRequest, UpdateBakeRequest } from '../types';

const app = new Hono<{ Bindings: Env }>();

// List all bakes
app.get('/', async (c) => {
  const limit = Number(c.req.query('limit') ?? 50);
  const offset = Number(c.req.query('offset') ?? 0);

  const bakes = await c.env.DB.prepare(
    'SELECT * FROM bakes ORDER BY bake_date DESC, created_at DESC LIMIT ? OFFSET ?'
  )
    .bind(limit, offset)
    .all<Bake>();

  return c.json({ bakes: bakes.results ?? [] });
});

// Get single bake with schedule and photos
app.get('/:id', async (c) => {
  const id = c.req.param('id');

  const bake = await c.env.DB.prepare('SELECT * FROM bakes WHERE id = ?')
    .bind(id)
    .first<Bake>();

  if (!bake) return c.json({ error: 'Not found' }, 404);

  const [schedule, photos] = await Promise.all([
    c.env.DB.prepare(
      'SELECT * FROM schedule_entries WHERE bake_id = ? ORDER BY sort_order ASC'
    )
      .bind(id)
      .all<ScheduleEntry>(),
    c.env.DB.prepare(
      'SELECT * FROM photos WHERE bake_id = ? ORDER BY created_at ASC'
    )
      .bind(id)
      .all<Photo>(),
  ]);

  const photosWithUrls = (photos.results ?? []).map((p) => ({
    ...p,
    url: `/api/photos/${p.id}/image`,
  }));

  const result: BakeWithDetails = {
    ...bake,
    schedule: schedule.results ?? [],
    photos: photosWithUrls,
  };

  return c.json(result);
});

// Create a new bake
app.post('/', async (c) => {
  const body = await c.req.json<CreateBakeRequest>();
  const id = crypto.randomUUID();
  const now = new Date().toISOString();

  await c.env.DB.prepare(
    'INSERT INTO bakes (id, title, bake_date, ingredients, notes, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?)'
  )
    .bind(id, body.title, body.bake_date, body.ingredients ?? null, body.notes ?? null, now, now)
    .run();

  if (body.schedule?.length) {
    const stmt = c.env.DB.prepare(
      'INSERT INTO schedule_entries (id, bake_id, time, action, note, sort_order) VALUES (?, ?, ?, ?, ?, ?)'
    );
    const batch = body.schedule.map((entry, i) =>
      stmt.bind(crypto.randomUUID(), id, entry.time, entry.action, entry.note ?? null, i)
    );
    await c.env.DB.batch(batch);
  }

  const bake = await c.env.DB.prepare('SELECT * FROM bakes WHERE id = ?')
    .bind(id)
    .first<Bake>();

  return c.json(bake, 201);
});

// Update a bake
app.put('/:id', async (c) => {
  const id = c.req.param('id');
  const body = await c.req.json<UpdateBakeRequest>();

  const existing = await c.env.DB.prepare('SELECT * FROM bakes WHERE id = ?')
    .bind(id)
    .first<Bake>();

  if (!existing) return c.json({ error: 'Not found' }, 404);

  const now = new Date().toISOString();

  await c.env.DB.prepare(
    'UPDATE bakes SET title = ?, bake_date = ?, ingredients = ?, notes = ?, updated_at = ? WHERE id = ?'
  )
    .bind(
      body.title ?? existing.title,
      body.bake_date ?? existing.bake_date,
      body.ingredients ?? existing.ingredients,
      body.notes ?? existing.notes,
      now,
      id
    )
    .run();

  if (body.schedule) {
    await c.env.DB.prepare('DELETE FROM schedule_entries WHERE bake_id = ?')
      .bind(id)
      .run();

    if (body.schedule.length) {
      const stmt = c.env.DB.prepare(
        'INSERT INTO schedule_entries (id, bake_id, time, action, note, sort_order) VALUES (?, ?, ?, ?, ?, ?)'
      );
      const batch = body.schedule.map((entry, i) =>
        stmt.bind(crypto.randomUUID(), id, entry.time, entry.action, entry.note ?? null, i)
      );
      await c.env.DB.batch(batch);
    }
  }

  const updated = await c.env.DB.prepare('SELECT * FROM bakes WHERE id = ?')
    .bind(id)
    .first<Bake>();

  return c.json(updated);
});

// Delete a bake
app.delete('/:id', async (c) => {
  const id = c.req.param('id');

  const bake = await c.env.DB.prepare('SELECT * FROM bakes WHERE id = ?')
    .bind(id)
    .first<Bake>();

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
    c.env.DB.prepare('DELETE FROM photos WHERE bake_id = ?').bind(id),
    c.env.DB.prepare('DELETE FROM bakes WHERE id = ?').bind(id),
  ]);

  return c.json({ ok: true });
});

export default app;
