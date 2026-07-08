import AlarmKit
import Foundation
import Observation
import SwiftUI
import UserNotifications

/// Schedules baking timers. On iOS 26+ they are real AlarmKit alarms — a
/// full-screen system alert that breaks through Silent Mode and Focus. Earlier
/// systems fall back to a local notification. Permission is requested lazily
/// on the first `scheduleReminder`, never on `start()`.
@MainActor @Observable
final class ReminderManager: NSObject, UNUserNotificationCenterDelegate {
    static let shared = ReminderManager()

    enum AuthorizationStatus { case undetermined, granted, denied }

    struct ScheduledReminder: Identifiable, Equatable, Sendable {
        let id: String        // Alarm UUID / UNNotificationRequest identifier
        let fireDate: Date
    }

    private(set) var authorizationStatus: AuthorizationStatus = .undetermined
    private(set) var activeReminders: [ScheduledReminder] = []

    // Identifier prefix so the notification fallback only touches this
    // feature's requests.
    private static let identifierPrefix = "bake-reminder-"
    private static let fireDateKey = "fireDate"
    // AlarmKit doesn't expose an alarm's fire date, so remember it per id.
    private static let alarmFireDatesKey = "bakeReminderAlarmFireDates"

    private let center = UNUserNotificationCenter.current()

    private override init() {
        super.init()
    }

    /// Safe to call from `App.init()` — the async work is kicked off in a Task.
    func start() {
        if #available(iOS 26.1, *) {
            authorizationStatus = Self.map(AlarmManager.shared.authorizationState)
            Task {
                await refresh()
                // Keeps the list live: fired/stopped alarms drop out here.
                for await alarms in AlarmManager.shared.alarmUpdates {
                    apply(alarms)
                }
            }
        } else {
            center.delegate = self
            Task {
                await syncNotificationAuthorizationStatus()
                await refresh()
            }
        }
    }

    @discardableResult
    func scheduleReminder(minutes: Int, bakeTitle: String?) async -> ScheduledReminder? {
        let trimmedTitle = bakeTitle?.trimmingCharacters(in: .whitespacesAndNewlines)
        if #available(iOS 26.1, *) {
            return await scheduleAlarm(minutes: minutes, title: trimmedTitle)
        }
        return await scheduleNotification(minutes: minutes, title: trimmedTitle)
    }

    func cancelReminder(id: String) {
        if #available(iOS 26.1, *) {
            if let uuid = UUID(uuidString: id) {
                try? AlarmManager.shared.cancel(id: uuid)
            }
            var dates = storedAlarmFireDates
            dates.removeValue(forKey: id)
            storedAlarmFireDates = dates
        } else {
            center.removePendingNotificationRequests(withIdentifiers: [id])
        }
        activeReminders.removeAll { $0.id == id }
    }

    func refresh() async {
        if #available(iOS 26.1, *) {
            apply((try? AlarmManager.shared.alarms) ?? [])
        } else {
            let pending = await center.pendingNotificationRequests()
            activeReminders = pending
                .filter { $0.identifier.hasPrefix(Self.identifierPrefix) }
                .compactMap { Self.reminder(from: $0) }
                .sorted { $0.fireDate < $1.fireDate }
        }
    }

    // MARK: - AlarmKit (iOS 26+)

    @available(iOS 26.1, *)
    private func scheduleAlarm(minutes: Int, title: String?) async -> ScheduledReminder? {
        guard await ensureAlarmAuthorized() else { return nil }

        let alarmTitle = (title?.isEmpty == false) ? title! : "Baking Timer"
        // The system supplies the stop button; the alert needs only a title.
        let alert = AlarmPresentation.Alert(title: "\(alarmTitle)")
        let attributes = AlarmAttributes<BakeAlarmMetadata>(
            presentation: AlarmPresentation(alert: alert),
            tintColor: .orange
        )

        let id = UUID()
        let fireDate = Date().addingTimeInterval(Double(minutes) * 60)
        do {
            _ = try await AlarmManager.shared.schedule(
                id: id,
                configuration: .timer(duration: Double(minutes) * 60, attributes: attributes)
            )
        } catch {
            return nil
        }

        var dates = storedAlarmFireDates
        dates[id.uuidString] = fireDate.timeIntervalSince1970
        storedAlarmFireDates = dates

        await refresh()
        return ScheduledReminder(id: id.uuidString, fireDate: fireDate)
    }

    @available(iOS 26.1, *)
    private func ensureAlarmAuthorized() async -> Bool {
        switch AlarmManager.shared.authorizationState {
        case .authorized:
            authorizationStatus = .granted
            return true
        case .denied:
            authorizationStatus = .denied
            return false
        case .notDetermined:
            let state = (try? await AlarmManager.shared.requestAuthorization()) ?? .denied
            authorizationStatus = Self.map(state)
            return state == .authorized
        @unknown default:
            authorizationStatus = .denied
            return false
        }
    }

    @available(iOS 26.1, *)
    private func apply(_ alarms: [Alarm]) {
        var dates = storedAlarmFireDates
        let liveIds = Set(alarms.map { $0.id.uuidString })
        dates = dates.filter { liveIds.contains($0.key) }

        var reminders: [ScheduledReminder] = []
        for alarm in alarms where alarm.state == .countdown {
            let key = alarm.id.uuidString
            let fireDate: Date
            if let stored = dates[key] {
                fireDate = Date(timeIntervalSince1970: stored)
            } else {
                // Stored date lost (e.g. reinstall) — approximate from the full
                // duration so the alarm stays visible and cancellable.
                fireDate = Date().addingTimeInterval(alarm.countdownDuration?.preAlert ?? 0)
                dates[key] = fireDate.timeIntervalSince1970
            }
            reminders.append(ScheduledReminder(id: key, fireDate: fireDate))
        }

        storedAlarmFireDates = dates
        activeReminders = reminders.sorted { $0.fireDate < $1.fireDate }
    }

    @available(iOS 26.1, *)
    private static func map(_ state: AlarmManager.AuthorizationState) -> AuthorizationStatus {
        switch state {
        case .notDetermined: return .undetermined
        case .authorized: return .granted
        default: return .denied
        }
    }

    private var storedAlarmFireDates: [String: Double] {
        get { UserDefaults.standard.dictionary(forKey: Self.alarmFireDatesKey) as? [String: Double] ?? [:] }
        set { UserDefaults.standard.set(newValue, forKey: Self.alarmFireDatesKey) }
    }

    // MARK: - Notification fallback (pre-iOS 26)

    private func scheduleNotification(minutes: Int, title: String?) async -> ScheduledReminder? {
        guard await ensureNotificationAuthorized() else { return nil }

        let content = UNMutableNotificationContent()
        content.title = (title?.isEmpty == false) ? title! : "Baking Log"
        content.body = "Baking timer is done."
        content.sound = .default

        let fireDate = Date().addingTimeInterval(Double(minutes) * 60)
        // Persist enough to rebuild the ScheduledReminder from pending requests.
        content.userInfo = [Self.fireDateKey: fireDate.timeIntervalSince1970]

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: Double(minutes) * 60, repeats: false)
        let id = Self.identifierPrefix + UUID().uuidString
        let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)

        do {
            try await center.add(request)
        } catch {
            return nil
        }

        let reminder = ScheduledReminder(id: id, fireDate: fireDate)
        await refresh()
        return reminder
    }

    private func syncNotificationAuthorizationStatus() async {
        let settings = await center.notificationSettings()
        authorizationStatus = Self.map(settings.authorizationStatus)
    }

    /// Requests permission when undetermined; returns whether we may schedule.
    private func ensureNotificationAuthorized() async -> Bool {
        await syncNotificationAuthorizationStatus()
        switch authorizationStatus {
        case .granted:
            return true
        case .denied:
            return false
        case .undetermined:
            let granted = (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
            authorizationStatus = granted ? .granted : .denied
            return granted
        }
    }

    private static func map(_ status: UNAuthorizationStatus) -> AuthorizationStatus {
        switch status {
        case .notDetermined:
            return .undetermined
        case .authorized, .provisional, .ephemeral:
            return .granted
        default:
            return .denied
        }
    }

    private static func reminder(from request: UNNotificationRequest) -> ScheduledReminder? {
        let info = request.content.userInfo
        guard let interval = info[fireDateKey] as? Double else { return nil }
        return ScheduledReminder(
            id: request.identifier,
            fireDate: Date(timeIntervalSince1970: interval)
        )
    }

    // MARK: - UNUserNotificationCenterDelegate (pre-iOS 26 fallback)

    // Delegate methods are nonisolated in Swift 6 — hop to the main actor to
    // touch state, and re-sync so the just-fired reminder drops from the list.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        await refresh()
        return [.banner, .sound, .list]
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        await refresh()
    }
}

/// AlarmKit requires a metadata type even when there's nothing to carry.
@available(iOS 26.1, *)
private struct BakeAlarmMetadata: AlarmMetadata {}
