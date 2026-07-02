import { Hono } from 'hono';
import { Env } from '../types';
import { fireWebhooks } from '../services/webhook';
import { parseJsonBody } from '../utils/validate';

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

/** Returns an error message, or null if the webhook URL is valid. */
function validateWebhookURL(url: unknown, requestURL: string): string | null {
  if (typeof url !== 'string') return 'url is required';

  let parsed: URL;
  try {
    parsed = new URL(url);
  } catch {
    return 'url must be a valid absolute URL';
  }

  if (parsed.protocol !== 'http:' && parsed.protocol !== 'https:') {
    return 'url must use http or https';
  }

  // A webhook pointing back at this API (e.g. /api/webhooks/push) would make
  // every push re-trigger itself.
  if (parsed.host === new URL(requestURL).host) {
    return 'url must not point at this API';
  }

  return null;
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
  const body = await parseJsonBody<{ url?: unknown; secret?: string }>(c.req.raw);
  if (!body) return c.json({ error: 'Invalid JSON body' }, 400);

  const invalid = validateWebhookURL(body.url, c.req.url);
  if (invalid) return c.json({ error: invalid }, 400);

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
