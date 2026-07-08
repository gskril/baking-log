import SwiftUI

/// Compact "Remind me" control that lives under the schedule section's Add Step
/// button: one-tap preset timers plus a row per active reminder. Scheduling
/// routes through the shared `ReminderManager`, which requests notification
/// permission lazily on the first tap.
struct ReminderTimerRow: View {
    /// Read fresh at tap time so a reminder captures the current title.
    let bakeTitle: () -> String?

    private let manager = ReminderManager.shared
    @Environment(\.openURL) private var openURL

    // Presets shown as one-tap capsules; the rest live behind the "More" menu.
    private static let quickPresets: [Int] = [30, 45, 60]
    private static let morePresets: [(label: String, minutes: Int)] = [
        ("15m", 15), ("90m", 90), ("2h", 120), ("3h", 180),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if manager.authorizationStatus == .denied {
                deniedRow
            } else {
                presetRow
            }

            ForEach(manager.activeReminders) { reminder in
                reminderRow(reminder)
            }
        }
        .task { await manager.refresh() }
    }

    // MARK: - Preset row

    private var presetRow: some View {
        HStack(spacing: 6) {
            Label("Remind me", systemImage: "timer")
                .font(.footnote)
                .foregroundStyle(.secondary)

            Spacer(minLength: 0)

            ForEach(Self.quickPresets, id: \.self) { minutes in
                presetCapsule("\(minutes)m", minutes: minutes)
                    .accessibilityIdentifier("reminderPreset\(minutes)")
            }

            Menu {
                ForEach(Self.morePresets, id: \.minutes) { preset in
                    Button(preset.label) { schedule(minutes: preset.minutes) }
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tint)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(Color(.tertiarySystemFill), in: Capsule())
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("More reminder options")
        }
        // .contain keeps the identifier on the container; a bare identifier on
        // the HStack propagates to every child and clobbers the per-preset ids.
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("reminderPresetRow")
    }

    private func presetCapsule(_ label: String, minutes: Int) -> some View {
        Button {
            schedule(minutes: minutes)
        } label: {
            Text(label)
                .font(.footnote.weight(.medium))
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .background(Color(.tertiarySystemFill), in: Capsule())
                .foregroundStyle(.tint)
        }
        // .borderless keeps the tap on the capsule instead of the whole Form row.
        .buttonStyle(.borderless)
    }

    // MARK: - Denied row

    private var deniedRow: some View {
        HStack(spacing: 6) {
            Label("Remind me", systemImage: "timer")
                .font(.footnote)
                .foregroundStyle(.secondary)

            Spacer(minLength: 0)

            Text("Notifications are off.")
                .font(.caption2)
                .foregroundStyle(.secondary)

            Button("Open Settings") {
                if let url = URL(string: UIApplication.openNotificationSettingsURLString) {
                    openURL(url)
                }
            }
            .font(.caption2)
            .buttonStyle(.borderless)
        }
    }

    // MARK: - Active reminder row

    private func reminderRow(_ reminder: ReminderManager.ScheduledReminder) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "bell")
                .font(.caption)
                .foregroundStyle(.tint)

            Text("Reminder at \(timeLabel(for: reminder.fireDate))")
                .font(.footnote)

            Spacer(minLength: 0)

            Button {
                manager.cancelReminder(id: reminder.id)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Cancel Reminder")
        }
    }

    // MARK: - Helpers

    private func schedule(minutes: Int) {
        let title = bakeTitle()
        Task {
            await manager.scheduleReminder(minutes: minutes, bakeTitle: title)
        }
    }

    /// Short time; only reminders that fire on a later day carry a date.
    private func timeLabel(for date: Date) -> String {
        if Calendar.current.isDateInToday(date) {
            return date.formatted(date: .omitted, time: .shortened)
        }
        return date.formatted(date: .abbreviated, time: .shortened)
    }
}
