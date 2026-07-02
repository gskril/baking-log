# Baking Log

Personal bread baking log — iOS app (SwiftUI) + Cloudflare Worker backend.

## Architecture

```
worker/          Cloudflare Worker (Hono + D1 + R2)
ios/             iOS app (SwiftUI, XcodeGen)
```

### Backend (worker/)

- **Framework**: Hono on Cloudflare Workers
- **Database**: D1 (SQLite) — schema via migrations in `migrations/*.sql`
- **Storage**: R2 bucket for photos
- **Auth**: Optional `API_KEY` env var → Bearer token middleware
- **Webhooks**: Manual push only — `POST /api/webhooks/push` triggers delivery with optional HMAC-SHA256 signing. CRUD operations do NOT auto-fire webhooks.

Key routes: `src/routes/bakes.ts` (CRUD), `src/routes/photos.ts` (upload/serve/delete), `src/routes/webhooks.ts` (management + push)

Scripts: `bun run dev`, `bun run deploy`, `bun run db:migrate`, `bun run db:migrate:remote`

### iOS (ios/)

- **Min target**: iOS 17.0, Swift 6.0
- **Build system**: XcodeGen (`project.yml` → `xcodegen generate`)
- **Pattern**: MVVM with `@MainActor` ViewModels + actor-isolated `APIClient`
- **App Group**: `group.com.bakinglog.shared` — UserDefaults suite storing the API URL/key settings

Key files:
- `BakingLog/Services/APIClient.swift` — actor singleton, all API calls. `photoURL(for:)` is `nonisolated` so SwiftUI views can call it synchronously. Uses a custom URLSession with a 15s request timeout so requests fail fast instead of hanging.
- `BakingLog/Services/NetworkMonitor.swift` — `@MainActor` singleton wrapping NWPathMonitor, status only. Drives the offline banner (`Views/OfflineBanner.swift`) shown at the top of the TabView and edit sheet.
- `BakingLog/Models/Bake.swift` — `Bake`, `ScheduleEntry`, `Photo` (all use CodingKeys for snake_case ↔ camelCase)
- `BakingLog/App/AppGroup.swift` — shared UserDefaults helper
- `BakingLog/App/ContentView.swift` — TabView with Bakes and Calculator tabs
- `BakingLog/Views/CalculatorView.swift` — Baker's percentage calculator with ingredient roles, hydration, scaling, presets
- `BakingLog/Views/SettingsView.swift` — API URL and key stored in App Group UserDefaults

## Important patterns

- **URL construction**: `APIClient` uses string concatenation (`"\(baseURLString)\(path)"`) — NOT `appendingPathComponent` which percent-encodes query params.
- **Swift 6 Sendable**: `UIImage` never crosses actor boundaries. The ViewModel converts to `Data` via `jpegData()` before passing to `APIClient.uploadPhoto(bakeId:imageData:)`.
- **D1 cascade deletes**: Don't rely on `ON DELETE CASCADE` — the delete handler in `bakes.ts` explicitly deletes `schedule_entries` and `photos` rows.
- **Entitlements**: The app target has an entitlements file for App Group capability. The App Group must be registered in the Apple Developer portal for device builds.
- **No offline mode**: there is no offline queueing (removed in PR #11). On save failure the edit sheet stays open and surfaces the error so input is never lost. `save()` marks a created bake as existing before uploading photos, so retrying after a partial failure updates instead of creating a duplicate. Connectivity status is display-only via `NetworkMonitor` + the offline banner.
- **Manual webhook push**: Webhooks are NOT fired automatically on CRUD. The user taps the paperplane icon in the bake list toolbar to trigger `POST /api/webhooks/push`, which fires webhooks for bakes updated in the last 24h (or a custom `since` timestamp).
- **Baker's calculator**: Ingredients are tagged as flour/liquid/other. Baker's percentages are relative to total flour weight. Hydration = total liquid / total flour. Scaling can target total dough weight or flour weight.
- **Custom date/time capsule**: Schedule rows use `Views/CompactDateTimePicker.swift` (time-first capsule → combined wheel popover), NOT a compact `DatePicker`. The system compact picker re-measures at window attach, so rows inserted into a visible list paint an abbreviated date with a leading gap on device (simulator never reproduces it) — don't reintroduce it in inserted rows. Full failure history is in the `0f8827a` commit message.
- **Keyboard reveal**: Newly inserted rows scroll into view above the keyboard via `Views/KeyboardReveal.swift` — two open-loop passes at `KeyboardReveal.passDelays` (device animations outrun the simulator's, so a single early pass lands short). The UI tests `Thread.sleep` past the final pass; keep them ahead of `passDelays` if the delays change.
- **iOS UI tests**: `BakingLogUITests` drives the real `BakeEditView` through a network-free host (`Views/UITestHost.swift`, `#if DEBUG`) that replaces `ContentView` when the app is launched with the `-uiTestHost` argument. Run with `xcodebuild -project BakingLog.xcodeproj -scheme BakingLog -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test`. To visually inspect flows in the simulator, launch via `xcrun simctl launch <sim> com.bakinglog.app -uiTestHost` and screenshot/record with `simctl io`. Tests assume a 12-hour US-locale simulator.

## Development

- **Package manager**: Bun (no npm — always use `bun` for install/run/add)

```bash
# Worker
cd worker && bun install && bun run db:migrate && bun run dev

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
