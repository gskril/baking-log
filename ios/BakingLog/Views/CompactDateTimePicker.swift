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
/// with near-zero alpha. So both the capsules and the interaction are ours:
/// SwiftUI buttons (deterministic from the first frame) that present the
/// native calendar / time-wheel pickers in a popover, like the system does.
///
/// A single `popover(item:)` serves both capsules — two sibling `.popover`
/// modifiers in one List row cross their anchors (tapping one presents the
/// other's content).
struct CompactDateTimePicker: View {
    @Binding var date: Date
    @State private var activePicker: PickerKind?

    private enum PickerKind: String, Identifiable {
        case date, time
        var id: String { rawValue }
    }

    var body: some View {
        HStack(spacing: 10) {
            Button {
                activePicker = .date
            } label: {
                capsule {
                    Text(date, format: .dateTime.month(.abbreviated).day().year())
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Date")
            .accessibilityValue(date.formatted(date: .abbreviated, time: .omitted))

            Button {
                activePicker = .time
            } label: {
                capsule {
                    Text(date, format: .dateTime.hour().minute())
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Time")
            .accessibilityValue(date.formatted(date: .omitted, time: .shortened))
        }
        // No arrowEdge: let the popover pick the side with room (a forced edge
        // squeezes it into ~50pt when the row is near the screen edge).
        .popover(item: $activePicker) { kind in
            switch kind {
            case .date:
                DatePicker("Date", selection: $date, displayedComponents: .date)
                    .datePickerStyle(.graphical)
                    .labelsHidden()
                    // Hard frame: in a popover the graphical calendar collapses
                    // to ~50pt tall under min-size constraints.
                    .frame(width: 320, height: 340)
                    .presentationCompactAdaptation(.popover)
            case .time:
                DatePicker("Time", selection: $date, displayedComponents: .hourAndMinute)
                    .datePickerStyle(.wheel)
                    .labelsHidden()
                    .padding(.horizontal)
                    .presentationCompactAdaptation(.popover)
            }
        }
    }

    private func capsule(@ViewBuilder content: () -> Text) -> some View {
        content()
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(Color(.tertiarySystemFill), in: Capsule())
    }
}
