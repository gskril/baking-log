import { Hono } from 'hono';
import { Env, Photo } from '../types';

const app = new Hono<{ Bindings: Env }>();

// Upload a photo for a bake
app.post('/bakes/:bakeId/photos', async (c) => {
  const bakeId = c.req.param('bakeId');

  const bake = await c.env.DB.prepare('SELECT id FROM bakes WHERE id = ?')
    .bind(bakeId)
    .first();

  if (!bake) return c.json({ error: 'Bake not found' }, 404);

  const formData = await c.req.formData();
  const file = formData.get('photo') as File | null;
  const caption = formData.get('caption') as string | null;

  if (!file) return c.json({ error: 'No photo provided' }, 400);

  const id = crypto.randomUUID();
  const ext = file.name.split('.').pop() ?? 'jpg';
  const r2Key = `bakes/${bakeId}/${id}.${ext}`;

  await c.env.PHOTOS.put(r2Key, file.stream(), {
    httpMetadata: { contentType: file.type },
  });

  // Assign sort_order as max existing + 1
  const maxRow = await c.env.DB.prepare(
    'SELECT COALESCE(MAX(sort_order), -1) AS max_order FROM photos WHERE bake_id = ?'
  )
    .bind(bakeId)
    .first<{ max_order: number }>();
  const sortOrder = (maxRow?.max_order ?? -1) + 1;

  await c.env.DB.prepare(
    'INSERT INTO photos (id, bake_id, r2_key, caption, sort_order) VALUES (?, ?, ?, ?, ?)'
  )
    .bind(id, bakeId, r2Key, caption, sortOrder)
    .run();

  const photo: Photo = {
    id,
    bake_id: bakeId,
    r2_key: r2Key,
    url: `/api/photos/${id}/image`,
    caption,
    sort_order: sortOrder,
    created_at: new Date().toISOString(),
  };

  return c.json(photo, 201);
});

// Serve a photo image
app.get('/photos/:id/image', async (c) => {
  const id = c.req.param('id');

  const photo = await c.env.DB.prepare('SELECT * FROM photos WHERE id = ?')
    .bind(id)
    .first<Photo>();

  if (!photo) return c.json({ error: 'Not found' }, 404);

  const object = await c.env.PHOTOS.get(photo.r2_key);
  if (!object) return c.json({ error: 'Image not found in storage' }, 404);

  const headers = new Headers();
  headers.set('Content-Type', object.httpMetadata?.contentType ?? 'image/jpeg');
  headers.set('Cache-Control', 'public, max-age=31536000, immutable');

  return new Response(object.body, { headers });
});

// Reorder photos for a bake
app.put('/bakes/:bakeId/photos/reorder', async (c) => {
  const bakeId = c.req.param('bakeId');
  const body = await c.req.json<{ photo_ids: string[] }>();

  if (!Array.isArray(body.photo_ids) || body.photo_ids.length === 0) {
    return c.json({ error: 'photo_ids array required' }, 400);
  }

  const stmt = c.env.DB.prepare(
    'UPDATE photos SET sort_order = ? WHERE id = ? AND bake_id = ?'
  );
  const batch = body.photo_ids.map((photoId, i) =>
    stmt.bind(i, photoId, bakeId)
  );
  await c.env.DB.batch(batch);

  return c.json({ ok: true });
});

// Delete a photo
app.delete('/photos/:id', async (c) => {
  const id = c.req.param('id');

  const photo = await c.env.DB.prepare('SELECT * FROM photos WHERE id = ?')
    .bind(id)
    .first<Photo>();

  if (!photo) return c.json({ error: 'Not found' }, 404);

  await c.env.PHOTOS.delete(photo.r2_key);
  await c.env.DB.prepare('DELETE FROM photos WHERE id = ?').bind(id).run();

  return c.json({ ok: true });
});

export default app;
