# Baking Log

Personal bread baking log — iOS app (SwiftUI) + Cloudflare Worker backend.

## Architecture

```
worker/          Cloudflare Worker (Hono + D1 + R2)
ios/             iOS app + widget (SwiftUI, XcodeGen)
```

### Backend (worker/)

- **Framework**: Hono on Cloudflare Workers
- **Database**: D1 (SQLite) — schema in `src/db/schema.sql`
- **Storage**: R2 bucket for photos
- **Auth**: Optional `API_KEY` env var → Bearer token middleware
- **Webhooks**: Fire-and-forget delivery with optional HMAC-SHA256 signing

Key routes: `src/routes/bakes.ts` (CRUD), `src/routes/photos.ts` (upload/serve/delete), `src/routes/webhooks.ts`

Scripts: `npm run dev`, `npm run deploy`, `npm run db:init`, `npm run db:init:remote`

### iOS (ios/)

- **Min target**: iOS 17.0, Swift 6.0
- **Build system**: XcodeGen (`project.yml` → `xcodegen generate`)
- **Pattern**: MVVM with `@MainActor` ViewModels + actor-isolated `APIClient`
- **Widget**: BakingLogWidgetExtension shows latest bake
- **App Group**: `group.com.bakinglog.shared` for shared UserDefaults between app and widget

Key files:
- `BakingLog/Services/APIClient.swift` — actor singleton, all API calls. `photoURL(for:)` is `nonisolated` so SwiftUI views can call it synchronously.
- `BakingLog/Models/Bake.swift` — `Bake`, `ScheduleEntry`, `Photo` (all use CodingKeys for snake_case ↔ camelCase)
- `BakingLog/App/AppGroup.swift` — shared UserDefaults helper
- `BakingLog/Views/SettingsView.swift` — API URL and key stored in App Group UserDefaults

## Important patterns

- **URL construction**: `APIClient` uses string concatenation (`"\(baseURLString)\(path)"`) — NOT `appendingPathComponent` which percent-encodes query params.
- **Swift 6 Sendable**: `UIImage` never crosses actor boundaries. The ViewModel converts to `Data` via `jpegData()` before passing to `APIClient.uploadPhoto(bakeId:imageData:)`.
- **D1 cascade deletes**: Don't rely on `ON DELETE CASCADE` — the delete handler in `bakes.ts` explicitly deletes `schedule_entries` and `photos` rows.
- **Entitlements**: Both targets have entitlements files for App Group capability. The App Group must be registered in the Apple Developer portal for device builds.

## Development

```bash
# Worker
cd worker && npm install && npm run db:init && npm run dev

# iOS (requires XcodeGen)
cd ios && xcodegen generate && open BakingLog.xcodeproj
```

## Dependencies

| Package | Version | Notes |
|---------|---------|-------|
| hono | ^4.7.0 | Web framework |
| wrangler | ^4.0.0 | Cloudflare CLI (v4) |
| typescript | ^5.7.0 | |
| @cloudflare/workers-types | ^4.20250214.0 | |
