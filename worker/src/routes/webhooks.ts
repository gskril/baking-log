import { Hono } from 'hono';
import { Env, Webhook } from '../types';
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
  const body = await c.req.json<{ url: string; secret?: string }>();
  const id = crypto.randomUUID();

  await c.env.DB.prepare(
    'INSERT INTO webhooks (id, url, secret) VALUES (?, ?, ?)'
  )
    .bind(id, body.url, body.secret ?? null)
    .run();

  const webhook = await c.env.DB.prepare('SELECT * FROM webhooks WHERE id = ?')
    .bind(id)
    .first<Webhook>();

  return c.json(webhook, 201);
});

// Manually push webhooks — pings all active webhooks
app.post('/push', async (c) => {
  c.executionCtx.waitUntil(fireWebhooks(c.env));
  return c.json({ ok: true });
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
