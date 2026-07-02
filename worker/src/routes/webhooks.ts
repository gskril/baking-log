import { Hono } from 'hono';
import { Env } from '../types';
import { fireWebhooks } from '../services/webhook';
import { createWebhookSchema, parseBody } from '../utils/validate';

const app = new Hono<{ Bindings: Env }>();

// Never round-trip the HMAC secret — expose only whether one is set.
const WEBHOOK_COLUMNS = 'id, url, secret IS NOT NULL AS has_secret, created_at';

interface WebhookRow {
  id: string;
  url: string;
  has_secret: number;
  created_at: string;
}

function toResponse(row: WebhookRow) {
  return { ...row, has_secret: row.has_secret === 1 };
}

// List webhooks
app.get('/', async (c) => {
  const webhooks = await c.env.DB.prepare(
    `SELECT ${WEBHOOK_COLUMNS} FROM webhooks ORDER BY created_at DESC`
  ).all<WebhookRow>();

  return c.json({ webhooks: (webhooks.results ?? []).map(toResponse) });
});

// Create a webhook
app.post('/', async (c) => {
  const parsed = await parseBody(c.req.raw, createWebhookSchema);
  if (parsed.error !== undefined) return c.json({ error: parsed.error }, 400);
  const body = parsed.data;

  // A webhook pointing back at this API (e.g. /api/webhooks/push) would make
  // every push re-trigger itself. Needs the request context, so it lives
  // outside the schema.
  if (new URL(body.url).host === new URL(c.req.url).host) {
    return c.json({ error: 'url must not point at this API' }, 400);
  }

  const id = crypto.randomUUID();

  await c.env.DB.prepare(
    'INSERT INTO webhooks (id, url, secret) VALUES (?, ?, ?)'
  )
    .bind(id, body.url, body.secret ?? null)
    .run();

  const webhook = await c.env.DB.prepare(`SELECT ${WEBHOOK_COLUMNS} FROM webhooks WHERE id = ?`)
    .bind(id)
    .first<WebhookRow>();

  return c.json(webhook ? toResponse(webhook) : null, 201);
});

// Manually push webhooks
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
