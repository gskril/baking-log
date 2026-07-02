import { Hono } from 'hono';
import { Env, Photo } from '../types';

const app = new Hono<{ Bindings: Env }>();

// Allowed upload content types → file extension used for the R2 key. The
// extension is derived from the validated content type — never from the
// client-supplied filename, which could contain `/` or other junk.
const ALLOWED_PHOTO_TYPES: Record<string, string> = {
  'image/jpeg': 'jpg',
  'image/png': 'png',
  'image/heic': 'heic',
  'image/webp': 'webp',
  'image/gif': 'gif',
};

const MAX_PHOTO_BYTES = 10 * 1024 * 1024; // 10 MB

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

  const ext = ALLOWED_PHOTO_TYPES[file.type];
  if (!ext) {
    return c.json(
      { error: `photo content type must be one of ${Object.keys(ALLOWED_PHOTO_TYPES).join(', ')}` },
      400
    );
  }

  if (file.size > MAX_PHOTO_BYTES) {
    return c.json({ error: 'photo must be 10 MB or smaller' }, 413);
  }

  const id = crypto.randomUUID();
  const r2Key = `bakes/${bakeId}/${id}.${ext}`;
  const now = new Date().toISOString();

  await c.env.PHOTOS.put(r2Key, file.stream(), {
    httpMetadata: { contentType: file.type },
  });

  await c.env.DB.prepare(
    'INSERT INTO photos (id, bake_id, r2_key, caption, created_at) VALUES (?, ?, ?, ?, ?)'
  )
    .bind(id, bakeId, r2Key, caption, now)
    .run();

  const photo: Photo = {
    id,
    bake_id: bakeId,
    r2_key: r2Key,
    url: `/api/photos/${id}/image`,
    caption,
    created_at: now,
  };

  return c.json(photo, 201);
});

// Serve a photo image
app.get('/photos/:id/image', async (c) => {
  // Photo ids are UUIDs and images are never replaced under the same id, so
  // edge-caching the full response is safe. Cache hits skip D1 and R2 entirely.
  const cache = caches.default;
  const cacheKey = new Request(c.req.url);
  const cached = await cache.match(cacheKey);
  if (cached) {
    const etag = cached.headers.get('ETag');
    if (etag && c.req.header('If-None-Match') === etag) {
      return new Response(null, { status: 304, headers: cached.headers });
    }
    return cached;
  }

  const id = c.req.param('id');

  const photo = await c.env.DB.prepare('SELECT r2_key FROM photos WHERE id = ?')
    .bind(id)
    .first<Pick<Photo, 'r2_key'>>();

  if (!photo) return c.json({ error: 'Not found' }, 404);

  const object = await c.env.PHOTOS.get(photo.r2_key, {
    onlyIf: c.req.raw.headers,
  });
  if (!object) return c.json({ error: 'Image not found in storage' }, 404);

  const headers = new Headers();
  headers.set('Content-Type', object.httpMetadata?.contentType ?? 'image/jpeg');
  headers.set('Cache-Control', 'public, max-age=31536000, immutable');
  headers.set('ETag', object.httpEtag);

  // onlyIf failed (e.g. If-None-Match matched) — no body, tell the client
  // its cached copy is still good
  if (!('body' in object) || !object.body) {
    return new Response(null, { status: 304, headers });
  }

  const response = new Response(object.body, { headers });
  c.executionCtx.waitUntil(cache.put(cacheKey, response.clone()));
  return response;
});

// Delete a photo
app.delete('/photos/:id', async (c) => {
  const id = c.req.param('id');

  const photo = await c.env.DB.prepare('SELECT * FROM photos WHERE id = ?')
    .bind(id)
    .first<Photo>();

  if (!photo) return c.json({ error: 'Not found' }, 404);

  await Promise.all([
    c.env.PHOTOS.delete(photo.r2_key),
    c.env.DB.prepare('DELETE FROM photos WHERE id = ?').bind(id).run(),
  ]);

  c.executionCtx.waitUntil(
    caches.default.delete(new Request(new URL(`/api/photos/${id}/image`, c.req.url)))
  );

  return c.json({ ok: true });
});

export default app;
