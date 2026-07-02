import { Hono } from 'hono';
import { cors } from 'hono/cors';
import { Env, Bake, BakeWithDetails, Ingredient, Photo, ScheduleEntry } from './types';
import bakes from './routes/bakes';
import photos from './routes/photos';
import webhooks from './routes/webhooks';
import { withPhotoURL } from './db/queries';

const app = new Hono<{ Bindings: Env }>();

/**
 * Constant-time string comparison. Digesting both values first sidesteps
 * timingSafeEqual's equal-length requirement without leaking length info.
 */
async function timingSafeEqual(a: string, b: string): Promise<boolean> {
  const encoder = new TextEncoder();
  const [digestA, digestB] = await Promise.all([
    crypto.subtle.digest('SHA-256', encoder.encode(a)),
    crypto.subtle.digest('SHA-256', encoder.encode(b)),
  ]);
  return crypto.subtle.timingSafeEqual(digestA, digestB);
}

// CORS for iOS app and website
app.use('*', cors());

// Optional API key auth middleware — skipped if API_KEY is not set
app.use('/api/*', async (c, next) => {
  if (c.req.path === '/api/export') return next();
  if (c.req.path.match(/^\/api\/photos\/[^/]+\/image$/)) return next();
  const apiKey = c.env.API_KEY;
  if (apiKey) {
    const authorization = c.req.header('Authorization');
    const prefix = 'Bearer ';
    if (
      !authorization?.startsWith(prefix) ||
      !(await timingSafeEqual(authorization.slice(prefix.length), apiKey))
    ) {
      return c.json({ error: 'Unauthorized' }, 401);
    }
  }
  await next();
});

// Mount routes
app.route('/api/bakes', bakes);
app.route('/api', photos);
app.route('/api/webhooks', webhooks);

// Full export endpoint — useful for pulling data into a personal website
app.get('/api/export', async (c) => {
  // Fetch everything in one D1 batch and group in memory — avoids one
  // round trip per bake
  const [bakeRes, scheduleRes, ingredientRes, photoRes] = await c.env.DB.batch([
    c.env.DB.prepare(
      'SELECT id, title, bake_date, notes, created_at, updated_at FROM bakes ORDER BY bake_date DESC'
    ),
    c.env.DB.prepare('SELECT * FROM schedule_entries ORDER BY occurs_at ASC, sort_order ASC'),
    c.env.DB.prepare('SELECT * FROM ingredients ORDER BY sort_order ASC'),
    c.env.DB.prepare('SELECT * FROM photos ORDER BY created_at ASC'),
  ]);

  const groupByBake = <T extends { bake_id: string }>(rows: T[]) => {
    const map = new Map<string, T[]>();
    for (const row of rows) {
      const list = map.get(row.bake_id);
      if (list) list.push(row);
      else map.set(row.bake_id, [row]);
    }
    return map;
  };

  const schedulesByBake = groupByBake((scheduleRes.results ?? []) as ScheduleEntry[]);
  const ingredientsByBake = groupByBake((ingredientRes.results ?? []) as Ingredient[]);
  const photosByBake = groupByBake((photoRes.results ?? []) as Photo[]);

  const allBakes: BakeWithDetails[] = ((bakeRes.results ?? []) as Bake[]).map((bake) => ({
    ...bake,
    ingredients: ingredientsByBake.get(bake.id) ?? [],
    schedule: schedulesByBake.get(bake.id) ?? [],
    photos: (photosByBake.get(bake.id) ?? []).map(withPhotoURL),
  }));

  return c.json({ bakes: allBakes, exported_at: new Date().toISOString() });
});

// Health check
app.get('/health', (c) => c.json({ ok: true }));

export default app;
