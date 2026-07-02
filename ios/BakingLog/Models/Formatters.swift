import Foundation

/// Wire formats and shared display helpers. Wire formatters are pinned to
/// en_US_POSIX so device locale/12-hour settings can't corrupt API payloads;
/// display helpers use the user's locale.
enum Formatters {
    /// Wire format for bake_date ("yyyy-MM-dd"), interpreted in the device's timezone.
    static let isoDay: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    /// Wire format for occurs_at ("yyyy-MM-dd'T'HH:mm:ss") — local wall-clock time, no timezone.
    static let isoDateTime: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        return f
    }()

    private static let isoDateTimeNoSeconds: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd'T'HH:mm"
        return f
    }()

    static func parseDateTime(_ string: String) -> Date? {
        isoDateTime.date(from: string) ?? isoDateTimeNoSeconds.date(from: string)
    }

    static func displayDay(_ isoDayString: String) -> String {
        guard let date = isoDay.date(from: isoDayString) else { return isoDayString }
        return date.formatted(.dateTime.month(.defaultDigits).day().year(.twoDigits))
    }

    /// "90" or "137.5" — no trailing ".0"
    static func amountString(_ value: Double) -> String {
        value == value.rounded() ? String(Int(value)) : String(format: "%g", value)
    }

    static func displayAmount(value: Double?, unit: String?) -> String {
        guard let value else { return "" }
        let amount = amountString(value)
        guard let unit, !unit.isEmpty else { return amount }
        return "\(amount) \(unit)"
    }

    /// "9:30 PM"
    static func displayTime(_ date: Date?) -> String {
        guard let date else { return "" }
        return date.formatted(date: .omitted, time: .shortened)
    }

    /// Weekday label ("Monday") when the entry at `index` starts a new calendar
    /// day relative to the previous dated entry; nil for entries that continue
    /// the same day.
    static func dayLabel(in dates: [Date?], at index: Int) -> String? {
        guard index < dates.count, let date = dates[index] else { return nil }
        let day = Calendar.current.startOfDay(for: date)
        if let previous = dates[..<index].compactMap({ $0 }).last,
           Calendar.current.startOfDay(for: previous) == day {
            return nil
        }
        return date.formatted(.dateTime.weekday(.wide))
    }
}
