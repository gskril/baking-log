import { Hono } from 'hono';
import { Env, Webhook, Bake, BakeWithDetails, ScheduleEntry, Photo } from '../types';
import { fireWebhooks } from '../services/webhook';

const app = new Hono<{ Bindings: Env }>();

// List webhooks
app.get('/', async (c) => {
  const webhooks = await c.env.DB.prepare(
    'SELECT * FROM webhooks ORDER BY created_at DESC'
  ).all<Webhook>();

  return c.json({ webhooks: webhooks.results ?? [] });
});

// Create a webhook
app.post('/', async (c) => {
  const body = await c.req.json<{
    url: string;
    events?: string[];
    secret?: string;
  }>();

  const id = crypto.randomUUID();

  await c.env.DB.prepare(
    'INSERT INTO webhooks (id, url, events, secret) VALUES (?, ?, ?, ?)'
  )
    .bind(
      id,
      body.url,
      JSON.stringify(body.events ?? ['*']),
      body.secret ?? null
    )
    .run();

  const webhook = await c.env.DB.prepare('SELECT * FROM webhooks WHERE id = ?')
    .bind(id)
    .first<Webhook>();

  return c.json(webhook, 201);
});

// Manually push webhooks — fires events for recent bakes
app.post('/push', async (c) => {
  const body = await c.req.json<{ since?: string }>().catch(() => ({}));
  const since = body.since ?? new Date(Date.now() - 24 * 60 * 60 * 1000).toISOString();

  const bakeRows = await c.env.DB.prepare(
    'SELECT * FROM bakes WHERE updated_at >= ? ORDER BY updated_at DESC'
  )
    .bind(since)
    .all<Bake>();

  const bakes = bakeRows.results ?? [];

  // Build full details for each bake
  const detailed: BakeWithDetails[] = [];
  for (const bake of bakes) {
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

    detailed.push({
      ...bake,
      schedule: schedule.results ?? [],
      photos: (photos.results ?? []).map((p) => ({
        ...p,
        url: `/api/photos/${p.id}/image`,
      })),
    });
  }

  c.executionCtx.waitUntil(
    fireWebhooks(c.env, 'bake.updated', { bakes: detailed })
  );

  return c.json({ ok: true, pushed: bakes.length });
});

// Delete a webhook
app.delete('/:id', async (c) => {
  const id = c.req.param('id');

  const webhook = await c.env.DB.prepare('SELECT id FROM webhooks WHERE id = ?')
    .bind(id)
    .first();

  if (!webhook) return c.json({ error: 'Not found' }, 404);

  await c.env.DB.prepare('DELETE FROM webhooks WHERE id = ?').bind(id).run();

  return c.json({ ok: true });
});

export default app;
