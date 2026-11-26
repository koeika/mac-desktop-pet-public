import Foundation

public struct VocabularyDisplayScheduleSnapshot: Codable, Equatable {
    public var dailyLimit: Int
    public var windowHours: Int
    public var questionPersists: Bool
    public var windowStartDate: Date?
    public var shownCountDate: String?
    public var shownCount: Int
    public var studyStartMinute: Int
    public var studyEndMinute: Int

    public init(
        dailyLimit: Int = 10,
        windowHours: Int = 6,
        questionPersists: Bool = true,
        windowStartDate: Date? = nil,
        shownCountDate: String? = nil,
        shownCount: Int = 0,
        studyStartMinute: Int = VocabularyDisplayScheduler.defaultStudyStartMinute,
        studyEndMinute: Int = VocabularyDisplayScheduler.defaultStudyEndMinute
    ) {
        self.dailyLimit = dailyLimit
        self.windowHours = windowHours
        self.questionPersists = questionPersists
        self.windowStartDate = windowStartDate
        self.shownCountDate = shownCountDate
        self.shownCount = shownCount
        self.studyStartMinute = studyStartMinute
        self.studyEndMinute = studyEndMinute
    }
}

public enum VocabularyDisplayScheduler {
    public static let defaultStudyStartMinute = 10 * 60
    public static let defaultStudyEndMinute = 18 * 60

    public static func normalized(_ snapshot: VocabularyDisplayScheduleSnapshot) -> VocabularyDisplayScheduleSnapshot {
        let window = normalizedStudyWindow(
            startMinute: snapshot.studyStartMinute,
            endMinute: snapshot.studyEndMinute
        )
        return VocabularyDisplayScheduleSnapshot(
            dailyLimit: normalizedDailyLimit(snapshot.dailyLimit),
            windowHours: normalizedWindowHours(snapshot.windowHours),
            questionPersists: snapshot.questionPersists,
            windowStartDate: nil,
            shownCountDate: snapshot.shownCountDate,
            shownCount: max(0, snapshot.shownCount),
            studyStartMinute: window.startMinute,
            studyEndMinute: window.endMinute
        )
    }

    public static func resetIfNeeded(
        _ snapshot: VocabularyDisplayScheduleSnapshot,
        now: Date,
        calendar: Calendar = .current
    ) -> VocabularyDisplayScheduleSnapshot {
        var updated = normalized(snapshot)
        let key = todayKey(for: now, calendar: calendar)
        if updated.shownCountDate != key {
            updated.shownCountDate = key
            updated.shownCount = 0
        }
        return updated
    }

    public static func canShowAutomaticVocabulary(
        _ snapshot: VocabularyDisplayScheduleSnapshot,
        now: Date,
        calendar: Calendar = .current,
        unlimited: Bool = false
    ) -> Bool {
        let updated = resetIfNeeded(snapshot, now: now, calendar: calendar)
        guard unlimited || updated.shownCount < updated.dailyLimit else { return false }
        return isInsideStudyWindow(updated, now: now, calendar: calendar)
    }

    public static func recordAutomaticVocabularyShown(
        _ snapshot: VocabularyDisplayScheduleSnapshot,
        now: Date,
        calendar: Calendar = .current,
        unlimited: Bool = false
    ) -> VocabularyDisplayScheduleSnapshot {
        var updated = resetIfNeeded(snapshot, now: now, calendar: calendar)
        let next = updated.shownCount < Int.max ? updated.shownCount + 1 : Int.max
        updated.shownCount = unlimited ? next : min(updated.dailyLimit, next)
        return updated
    }

    public static func windowEndDate(_ snapshot: VocabularyDisplayScheduleSnapshot) -> Date? {
        nil
    }

    public static func studyWindowDates(
        _ snapshot: VocabularyDisplayScheduleSnapshot,
        now: Date,
        calendar: Calendar = .current
    ) -> (start: Date, end: Date) {
        let updated = normalized(snapshot)
        let start = calendar.date(bySettingHour: updated.studyStartMinute / 60,
            minute: updated.studyStartMinute % 60, second: 0, of: now)!
        let end = calendar.date(bySettingHour: updated.studyEndMinute / 60,
            minute: updated.studyEndMinute % 60, second: 0, of: now)!
        return (start, end)
    }

    public static func isInsideStudyWindow(
        _ snapshot: VocabularyDisplayScheduleSnapshot,
        now: Date,
        calendar: Calendar = .current
    ) -> Bool {
        let window = studyWindowDates(snapshot, now: now, calendar: calendar)
        return now >= window.start && now < window.end
    }

    public static func secondsUntilStudyWindowEnd(
        _ snapshot: VocabularyDisplayScheduleSnapshot,
        now: Date,
        calendar: Calendar = .current
    ) -> TimeInterval {
        let window = studyWindowDates(snapshot, now: now, calendar: calendar)
        return max(0, window.end.timeIntervalSince(now))
    }

    public static func todayKey(for date: Date, calendar: Calendar = .current) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", components.year ?? 0, components.month ?? 0, components.day ?? 0)
    }

    public static func normalizedDailyLimit(_ value: Int) -> Int {
        max(value, 1)
    }

    public static func automaticInterval(_ snapshot: VocabularyDisplayScheduleSnapshot, now: Date,
                                         unlimited: Bool, minimumMinutes: Int, jitter: Double = 1,
                                         calendar: Calendar = .current) -> TimeInterval {
        let minimum = Double(max(1, minimumMinutes)) * 60
        guard !unlimited else { return minimum }
        let remaining = max(0, snapshot.dailyLimit - snapshot.shownCount)
        let evenlySpaced = secondsUntilStudyWindowEnd(snapshot, now: now, calendar: calendar) / (Double(remaining) + 1)
        return max(minimum, evenlySpaced * min(1.25, max(0.75, jitter)))
    }

    public static func normalizedWindowHours(_ value: Int) -> Int {
        min(max(value, 1), 12)
    }

    public static func normalizedStudyWindow(startMinute: Int, endMinute: Int) -> (startMinute: Int, endMinute: Int) {
        let start = normalizedMinuteOfDay(startMinute)
        let end = normalizedMinuteOfDay(endMinute)
        guard start < end else {
            return (defaultStudyStartMinute, defaultStudyEndMinute)
        }
        return (start, end)
    }

    public static func normalizedMinuteOfDay(_ value: Int) -> Int {
        min(max(value, 0), 23 * 60 + 59)
    }

    public static func minuteOfDay(for date: Date, calendar: Calendar = .current) -> Int {
        let components = calendar.dateComponents([.hour, .minute], from: date)
        return (components.hour ?? 0) * 60 + (components.minute ?? 0)
    }

    public static func timeText(for minute: Int) -> String {
        let normalized = normalizedMinuteOfDay(minute)
        return String(format: "%02d:%02d", normalized / 60, normalized % 60)
    }
}
