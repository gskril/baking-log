import WidgetKit
import SwiftUI

// MARK: - Timeline Provider

struct BakeEntry: TimelineEntry {
    let date: Date
    let bakeTitle: String
    let bakeDate: String
    let nextStep: String?
    let ingredientCount: Int
}

struct BakingLogProvider: TimelineProvider {
    func placeholder(in context: Context) -> BakeEntry {
        BakeEntry(
            date: .now,
            bakeTitle: "Sourdough Loaf",
            bakeDate: "2/13/26",
            nextStep: "Fold at 10pm",
            ingredientCount: 6
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (BakeEntry) -> Void) {
        completion(placeholder(in: context))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<BakeEntry>) -> Void) {
        Task {
            do {
                let bakes = try await APIClient.shared.listBakes(limit: 1)
                if let latest = bakes.first {
                    let ingredientCount = latest.ingredients?
                        .components(separatedBy: "\n")
                        .filter { !$0.isEmpty }.count ?? 0

                    let entry = BakeEntry(
                        date: .now,
                        bakeTitle: latest.title,
                        bakeDate: latest.displayDate,
                        nextStep: latest.schedule?.first?.action.isEmpty == false
                            ? "\(latest.schedule!.first!.time) — \(latest.schedule!.first!.action)"
                            : nil,
                        ingredientCount: ingredientCount
                    )

                    let nextUpdate = Calendar.current.date(byAdding: .minute, value: 30, to: .now)!
                    completion(Timeline(entries: [entry], policy: .after(nextUpdate)))
                } else {
                    let entry = BakeEntry(
                        date: .now,
                        bakeTitle: "No bakes yet",
                        bakeDate: "",
                        nextStep: nil,
                        ingredientCount: 0
                    )
                    let nextUpdate = Calendar.current.date(byAdding: .hour, value: 1, to: .now)!
                    completion(Timeline(entries: [entry], policy: .after(nextUpdate)))
                }
            } catch {
                let entry = BakeEntry(
                    date: .now,
                    bakeTitle: "Offline",
                    bakeDate: "",
                    nextStep: nil,
                    ingredientCount: 0
                )
                let nextUpdate = Calendar.current.date(byAdding: .minute, value: 15, to: .now)!
                completion(Timeline(entries: [entry], policy: .after(nextUpdate)))
            }
        }
    }
}

// MARK: - Widget Views

struct BakingLogWidgetEntryView: View {
    var entry: BakeEntry
    @Environment(\.widgetFamily) var family

    var body: some View {
        switch family {
        case .systemSmall:
            smallWidget
        case .systemMedium:
            mediumWidget
        default:
            smallWidget
        }
    }

    var smallWidget: some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: "oven")
                .font(.title3)
                .foregroundStyle(.orange)

            Spacer()

            Text(entry.bakeTitle)
                .font(.headline)
                .lineLimit(2)

            if !entry.bakeDate.isEmpty {
                Text(entry.bakeDate)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
    }

    var mediumWidget: some View {
        HStack {
            VStack(alignment: .leading, spacing: 6) {
                Image(systemName: "oven")
                    .font(.title3)
                    .foregroundStyle(.orange)

                Spacer()

                Text(entry.bakeTitle)
                    .font(.headline)

                if !entry.bakeDate.isEmpty {
                    Text(entry.bakeDate)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 8) {
                if entry.ingredientCount > 0 {
                    Label("\(entry.ingredientCount)", systemImage: "list.bullet")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if let nextStep = entry.nextStep {
                    Text(nextStep)
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .multilineTextAlignment(.trailing)
                }
            }
        }
        .padding()
    }
}

// MARK: - Widget Configuration

struct BakingLogWidget: Widget {
    let kind: String = "BakingLogWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: BakingLogProvider()) { entry in
            BakingLogWidgetEntryView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Latest Bake")
        .description("Shows your most recent bake at a glance.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

// MARK: - Preview

#Preview(as: .systemSmall) {
    BakingLogWidget()
} timeline: {
    BakeEntry(
        date: .now,
        bakeTitle: "Sourdough Loaf",
        bakeDate: "2/13/26",
        nextStep: "Fold at 10pm",
        ingredientCount: 6
    )
}

#Preview(as: .systemMedium) {
    BakingLogWidget()
} timeline: {
    BakeEntry(
        date: .now,
        bakeTitle: "Heart Focaccia",
        bakeDate: "2/13/26",
        nextStep: "3:25pm — Fold",
        ingredientCount: 4
    )
}
