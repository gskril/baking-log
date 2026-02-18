import { Env, Webhook } from '../types';

export async function fireWebhooks(env: Env) {
  const webhooks = await env.DB.prepare(
    'SELECT * FROM webhooks WHERE active = 1'
  ).all<Webhook>();

  const deliveries = (webhooks.results ?? []).map(async (wh) => {
    const body = JSON.stringify({ event: 'bakes.updated', timestamp: new Date().toISOString() });

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
      // Silently fail
    }
  });

  await Promise.allSettled(deliveries);
}
