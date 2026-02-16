import { Env, Webhook } from '../types';

export type WebhookEvent =
  | 'bake.created'
  | 'bake.updated'
  | 'bake.deleted'
  | 'photo.uploaded'
  | 'photo.deleted';

export async function fireWebhooks(
  env: Env,
  event: WebhookEvent,
  payload: unknown
) {
  const webhooks = await env.DB.prepare(
    'SELECT * FROM webhooks WHERE active = 1'
  )
    .all<Webhook>();

  const matching = (webhooks.results ?? []).filter((wh) => {
    const events: string[] = JSON.parse(wh.events);
    return events.includes('*') || events.includes(event);
  });

  const deliveries = matching.map(async (wh) => {
    const body = JSON.stringify({ event, payload, timestamp: new Date().toISOString() });

    const headers: Record<string, string> = {
      'Content-Type': 'application/json',
    };

    if (wh.secret) {
      const encoder = new TextEncoder();
      const key = await crypto.subtle.importKey(
        'raw',
        encoder.encode(wh.secret),
        { name: 'HMAC', hash: 'SHA-256' },
        false,
        ['sign']
      );
      const signature = await crypto.subtle.sign('HMAC', key, encoder.encode(body));
      const hex = [...new Uint8Array(signature)]
        .map((b) => b.toString(16).padStart(2, '0'))
        .join('');
      headers['X-Webhook-Signature'] = `sha256=${hex}`;
    }

    try {
      await fetch(wh.url, { method: 'POST', headers, body });
    } catch {
      // Silently fail — could add a delivery log table later
    }
  });

  // Fire and forget — don't block the response
  await Promise.allSettled(deliveries);
}
