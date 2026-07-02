import { Hono } from 'hono';
import { cors } from 'hono/cors';
import { Env, Bake, BakeWithDetails } from './types';
import bakes from './routes/bakes';
import photos from './routes/photos';
import webhooks from './routes/webhooks';
import { getBakeWithDetails } from './db/queries';

const app = new Hono<{ Bindings: Env }>();

// CORS for iOS app and website
app.use('*', cors());

// Optional API key auth middleware — skipped if API_KEY is not set
app.use('/api/*', async (c, next) => {
  if (c.req.path === '/api/export') return next();
  if (c.req.path.match(/^\/api\/photos\/[^/]+\/image$/)) return next();
  const apiKey = c.env.API_KEY;
  if (apiKey) {
    const provided = c.req.header('Authorization')?.replace('Bearer ', '');
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
    'SELECT id, title, bake_date, notes, created_at, updated_at FROM bakes ORDER BY bake_date DESC'
  ).all<Bake>();

  const allBakes: BakeWithDetails[] = [];

  for (const bake of bakeRows.results ?? []) {
    const details = await getBakeWithDetails(c.env.DB, bake.id);
    if (details) allBakes.push(details);
  }

  return c.json({ bakes: allBakes, exported_at: new Date().toISOString() });
});

// Health check
app.get('/health', (c) => c.json({ ok: true }));

export default app;
