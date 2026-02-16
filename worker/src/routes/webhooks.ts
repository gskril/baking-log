import { Hono } from 'hono';
import { Env, Webhook } from '../types';

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
