# Baking Log

A minimal bread baking log — iOS app + Cloudflare Worker backend.

## Structure

```
worker/     Cloudflare Worker (Hono + D1 + R2)
ios/        iOS app (SwiftUI) + Widget extension
```

## Backend Setup

```bash
cd worker
npm install

# Create D1 database and R2 bucket
wrangler d1 create baking-log-db
wrangler r2 bucket create baking-log-photos

# Update wrangler.toml with the database_id from the d1 create output

# Initialize the database schema
npm run db:init:remote

# Deploy
npm run deploy
```

### API

| Method | Path | Description |
|--------|------|-------------|
| `GET` | `/api/bakes` | List bakes (supports `?limit=` and `?offset=`) |
| `GET` | `/api/bakes/:id` | Get bake with schedule + photos |
| `POST` | `/api/bakes` | Create a bake |
| `PUT` | `/api/bakes/:id` | Update a bake |
| `DELETE` | `/api/bakes/:id` | Delete a bake |
| `POST` | `/api/bakes/:id/photos` | Upload photo (multipart form: `photo` file + optional `caption`) |
| `GET` | `/api/photos/:id/image` | Serve photo image |
| `DELETE` | `/api/photos/:id` | Delete a photo |
| `GET` | `/api/webhooks` | List webhooks |
| `POST` | `/api/webhooks` | Create webhook (`{url, events?, secret?}`) |
| `DELETE` | `/api/webhooks/:id` | Delete webhook |
| `GET` | `/api/export` | Full data export (all bakes with schedule + photos) |
| `GET` | `/health` | Health check |

### Webhooks

Register a webhook to get notified when data changes:

```bash
curl -X POST https://your-worker.workers.dev/api/webhooks \
  -H "Content-Type: application/json" \
  -d '{"url": "https://your-site.com/webhook", "events": ["bake.created", "bake.updated"]}'
```

Events: `bake.created`, `bake.updated`, `bake.deleted`, `photo.uploaded`, `photo.deleted`

Payloads include an `X-Webhook-Signature` header (HMAC-SHA256) if you set a `secret`.

### Optional Auth

Set `API_KEY` in `wrangler.toml` or as a secret (`wrangler secret put API_KEY`) to require `Authorization: Bearer <key>` on all API requests.

## iOS Setup

Requires [XcodeGen](https://github.com/yonaskolb/XcodeGen):

```bash
brew install xcodegen
cd ios
xcodegen generate
open BakingLog.xcodeproj
```

In the app, go to Settings (gear icon) and set your worker URL.

### Widget

The widget shows your most recent bake. Add it from the iOS home screen widget picker after installing the app.
