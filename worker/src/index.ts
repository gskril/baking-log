import { Hono } from 'hono';
import { cors } from 'hono/cors';
import { Env, Bake, BakeWithDetails, ScheduleEntry, Photo } from './types';
import bakes from './routes/bakes';
import photos from './routes/photos';
import webhooks from './routes/webhooks';

const app = new Hono<{ Bindings: Env }>();

// CORS for iOS app and website
app.use('*', cors());

// Optional API key auth middleware — skipped if API_KEY is not set
app.use('/api/*', async (c, next) => {
  const apiKey = c.env.API_KEY;
  if (apiKey) {
    const provided =
      c.req.header('Authorization')?.replace('Bearer ', '') ??
      c.req.query('key');
    if (provided !== apiKey) {
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
  const bakeRows = await c.env.DB.prepare(
    'SELECT * FROM bakes ORDER BY bake_date DESC'
  ).all<Bake>();

  const allBakes: BakeWithDetails[] = [];

  for (const bake of bakeRows.results ?? []) {
    const [schedule, photos] = await Promise.all([
      c.env.DB.prepare(
        'SELECT * FROM schedule_entries WHERE bake_id = ? ORDER BY sort_order ASC'
      )
        .bind(bake.id)
        .all<ScheduleEntry>(),
      c.env.DB.prepare(
        'SELECT * FROM photos WHERE bake_id = ? ORDER BY created_at ASC'
      )
        .bind(bake.id)
        .all<Photo>(),
    ]);

    allBakes.push({
      ...bake,
      schedule: schedule.results ?? [],
      photos: (photos.results ?? []).map((p) => ({
        ...p,
        url: `/api/photos/${p.id}/image`,
      })),
    });
  }

  return c.json({ bakes: allBakes, exported_at: new Date().toISOString() });
});

// Health check
app.get('/health', (c) => c.json({ ok: true }));

export default app;
