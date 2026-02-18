# Baking Log Worker API Integration Guide

This guide is for developers and coding agents integrating with the Baking Log Worker API to read, publish, and sync baking data.

## Base URL

- Production: `https://baking-log.gregskril.workers.dev`
- Local dev (default Wrangler): `http://127.0.0.1:8787`

## Authentication

Auth is optional and controlled by Worker env var `API_KEY`.

- If `API_KEY` is not set: API is open.
- If `API_KEY` is set: every `/api/*` route requires:
  - `Authorization: Bearer <API_KEY>`

Unauthorized response:

```json
{ "error": "Unauthorized" }
```

## Data Model (Wire Format)

All API fields are `snake_case`.

### Bake

```json
{
  "id": "uuid",
  "title": "Country Sourdough",
  "bake_date": "2026-02-17",
  "ingredients_text": "Optional free text",
  "notes": "Crumb opened up nicely",
  "created_at": "2026-02-17T20:11:14.000Z",
  "updated_at": "2026-02-17T20:11:14.000Z"
}
```

### Ingredient

```json
{
  "id": "uuid",
  "bake_id": "uuid",
  "name": "Bread flour",
  "amount": "500g",
  "note": null,
  "sort_order": 0,
  "created_at": "2026-02-17T20:11:14.000Z"
}
```

### Schedule Entry

```json
{
  "id": "uuid",
  "bake_id": "uuid",
  "time": "09:00",
  "action": "Mix",
  "note": null,
  "sort_order": 0,
  "created_at": "2026-02-17T20:11:14.000Z"
}
```

### Photo

```json
{
  "id": "uuid",
  "bake_id": "uuid",
  "r2_key": "bakes/<bakeId>/<photoId>.jpg",
  "url": "/api/photos/<photoId>/image",
  "caption": "Fresh from oven",
  "created_at": "2026-02-17T20:11:14.000Z"
}
```

`photo.url` is relative. Build an absolute URL as:

`<worker_base_url><photo.url>`

Example:

`https://baking-log.gregskril.workers.dev/api/photos/<photoId>/image`

## Endpoint Reference

### Health

- `GET /health` -> `{ "ok": true }`

### Bakes

- `GET /api/bakes?limit=50&offset=0`
  - Returns `{ "bakes": [...] }`
  - Each item includes `ingredient_count`.
- `GET /api/bakes/:id`
  - Returns a full bake object with `ingredients`, `schedule`, and `photos`.
- `POST /api/bakes`
  - Creates a bake.
  - Body:

```json
{
  "title": "Country Sourdough",
  "bake_date": "2026-02-17",
  "ingredients_text": "Optional summary",
  "notes": "Optional notes",
  "ingredients": [
    { "name": "Bread flour", "amount": "500g", "note": null }
  ],
  "schedule": [
    { "time": "09:00", "action": "Mix", "note": null }
  ]
}
```

- `PUT /api/bakes/:id`
  - Partial update.
  - Important behavior:
    - If `ingredients` is included, existing ingredients are replaced.
    - If `schedule` is included, existing schedule is replaced.
- `DELETE /api/bakes/:id`
  - Deletes bake, ingredient rows, schedule rows, photo rows, and photo objects in R2.

### Photos

- `POST /api/bakes/:bakeId/photos` (multipart/form-data)
  - Form fields:
    - `photo` (required file)
    - `caption` (optional text)
  - Returns created `Photo`.
- `GET /api/photos/:id/image`
  - Returns binary image.
  - Response headers include long-lived cache:
    - `Cache-Control: public, max-age=31536000, immutable`
- `DELETE /api/photos/:id`

### Export (Best for websites/static generation)

- `GET /api/export`
  - Returns:

```json
{
  "bakes": [
    {
      "id": "uuid",
      "title": "Country Sourdough",
      "bake_date": "2026-02-17",
      "ingredients_text": "...",
      "notes": "...",
      "created_at": "...",
      "updated_at": "...",
      "ingredients": [],
      "schedule": [],
      "photos": [
        {
          "id": "uuid",
          "bake_id": "uuid",
          "r2_key": "bakes/...",
          "url": "/api/photos/<photoId>/image",
          "caption": null,
          "created_at": "..."
        }
      ]
    }
  ],
  "exported_at": "2026-02-18T00:00:00.000Z"
}
```

## Webhooks (Manual Push Model)

Webhooks are not auto-fired by CRUD operations.

Current flow:

1. Register webhook(s).
2. Trigger delivery manually using `POST /api/webhooks/push`.

### Webhook Management

- `GET /api/webhooks` -> `{ "webhooks": [...] }`
- `POST /api/webhooks`
  - Body:

```json
{
  "url": "https://your-site.com/api/baking-webhook",
  "events": ["*"],
  "secret": "optional-signing-secret"
}
```

- `DELETE /api/webhooks/:id`

### Push Endpoint

- `POST /api/webhooks/push`
  - Body (optional): `{ "since": "2026-02-17T00:00:00.000Z" }`
  - If omitted, defaults to past 24 hours.
  - Finds bakes where `updated_at >= since`.
  - Sends event `bake.updated` with payload `{ bakes: [...] }`.
  - Immediate response: `{ "ok": true, "pushed": <count> }`

### Signature Verification

If webhook `secret` is set, Worker includes:

- `X-Webhook-Signature: sha256=<hex>`

Digest is HMAC-SHA256 of raw request body.

Node.js verification example:

```ts
import crypto from "node:crypto";

export function verifyWebhook(rawBody: string, signatureHeader: string | null, secret: string): boolean {
  if (!signatureHeader?.startsWith("sha256=")) return false;
  const expected = crypto
    .createHmac("sha256", secret)
    .update(rawBody, "utf8")
    .digest("hex");
  const received = signatureHeader.slice("sha256=".length);
  return crypto.timingSafeEqual(Buffer.from(received, "hex"), Buffer.from(expected, "hex"));
}
```

## Integration Patterns for `gregskril.com/baking`

### Pattern A: Pull on Build (recommended for static sites)

1. Fetch `GET /api/export` during site build.
2. Store as content JSON.
3. Render bake pages/listing.
4. Convert relative photo URLs to absolute worker URLs.

Minimal fetch example:

```bash
curl -sS "https://baking-log.gregskril.workers.dev/api/export" \
  -H "Authorization: Bearer $BAKING_LOG_API_KEY" \
  -o baking-export.json
```

### Pattern B: Push + Rebuild

1. Create webhook pointing to your website API endpoint.
2. Call `POST /api/webhooks/push` after you add/edit bakes (or on a cron).
3. Webhook handler verifies signature, then triggers rebuild/revalidation.

### Pattern C: Client-Side Live Fetch

1. Frontend calls `GET /api/bakes` and `GET /api/bakes/:id`.
2. Good for dynamic views, less ideal for SEO/perf than static prebuild.

## Agent Instructions (Copy/Paste)

Use these rules when writing integrations against this API:

1. Treat `snake_case` fields as canonical.
2. Use `/api/export` when you need complete website content.
3. Assume photo URLs are relative; prepend Worker origin.
4. Do not assume CRUD triggers webhooks. Call `/api/webhooks/push` explicitly.
5. For `PUT /api/bakes/:id`, send full `ingredients`/`schedule` arrays when changing them (endpoint replaces these collections).
6. If auth is enabled, always send Bearer token.
7. Parse and store timestamps as ISO-8601 UTC strings.

## Example: Create Then Publish

```bash
# 1) Create bake
curl -sS -X POST "https://baking-log.gregskril.workers.dev/api/bakes" \
  -H "Authorization: Bearer $BAKING_LOG_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "title": "Saturday Country Loaf",
    "bake_date": "2026-02-18",
    "ingredients": [
      {"name":"Bread flour","amount":"450g"},
      {"name":"Whole wheat flour","amount":"50g"},
      {"name":"Water","amount":"375g"},
      {"name":"Salt","amount":"10g"},
      {"name":"Levain","amount":"100g"}
    ],
    "notes": "Strong oven spring."
  }'

# 2) Push webhook deliveries for recent changes
curl -sS -X POST "https://baking-log.gregskril.workers.dev/api/webhooks/push" \
  -H "Authorization: Bearer $BAKING_LOG_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{"since":"2026-02-18T00:00:00.000Z"}'
```
