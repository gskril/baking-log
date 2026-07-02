import SwiftUI

/// Drop-in replacement for a compact `DatePicker` on rows that get inserted
/// into a visible list.
///
/// The system compact picker re-measures itself when it attaches to a window:
/// on device, a newly inserted row renders abbreviated ("6/28/26") with a
/// leading gap and stays that way until the next layout pass (verified via
/// frame-by-frame screen recording; neither SwiftUI modifiers nor pre-warming
/// the control in `makeUIView` can reach that window). Overlaying an invisible
/// native picker as a tap target fails too — UIKit drops touches on views
/// with near-zero alpha. So both the capsule and the interaction are ours:
/// a SwiftUI button (deterministic from the first frame) that presents the
/// native combined date+time wheels in a popover.
///
/// Display priorities: the time matters most, the date is secondary, and the
/// year is noise — it only appears when it isn't the current year. The wheel
/// picker matches that: its date wheel has no year but scrolls across year
/// boundaries for the rare case.
struct CompactDateTimePicker: View {
    @Binding var date: Date
    @State private var showingPicker = false

    var body: some View {
        Button {
            showingPicker = true
        } label: {
            HStack(spacing: 6) {
                Text(date, format: .dateTime.hour().minute())
                Text(date, format: dateFormat)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(Color(.tertiarySystemFill), in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Date and time")
        .accessibilityValue(date.formatted(date: .abbreviated, time: .shortened))
        // No arrowEdge: let the popover pick the side with room (a forced edge
        // squeezes it into ~50pt when the row is near the screen edge).
        .popover(isPresented: $showingPicker) {
            DatePicker("Date and time", selection: $date, displayedComponents: [.date, .hourAndMinute])
                .datePickerStyle(.wheel)
                .labelsHidden()
                .padding(.horizontal)
                .presentationCompactAdaptation(.popover)
        }
    }

    /// "Jun 28" — the year appears only when it isn't the current one.
    private var dateFormat: Date.FormatStyle {
        var format = Date.FormatStyle.dateTime.month(.abbreviated).day()
        if !Calendar.current.isDate(date, equalTo: .now, toGranularity: .year) {
            format = format.year()
        }
        return format
    }
}
