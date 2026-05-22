import Foundation

public struct VocabularyDisplayScheduleSnapshot: Codable, Equatable {
    public var dailyLimit: Int
    public var windowHours: Int
    public var questionPersists: Bool
    public var windowStartDate: Date?
    public var shownCountDate: String?
    public var shownCount: Int

    public init(
        dailyLimit: Int = 10,
        windowHours: Int = 6,
        questionPersists: Bool = true,
        windowStartDate: Date? = nil,
        shownCountDate: String? = nil,
        shownCount: Int = 0
    ) {
        self.dailyLimit = dailyLimit
        self.windowHours = windowHours
        self.questionPersists = questionPersists
        self.windowStartDate = windowStartDate
        self.shownCountDate = shownCountDate
        self.shownCount = shownCount
    }
}

public enum VocabularyDisplayScheduler {
    public static func normalized(_ snapshot: VocabularyDisplayScheduleSnapshot) -> VocabularyDisplayScheduleSnapshot {
        VocabularyDisplayScheduleSnapshot(
            dailyLimit: normalizedDailyLimit(snapshot.dailyLimit),
            windowHours: normalizedWindowHours(snapshot.windowHours),
            questionPersists: snapshot.questionPersists,
            windowStartDate: snapshot.windowStartDate,
            shownCountDate: snapshot.shownCountDate,
            shownCount: max(0, snapshot.shownCount)
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
            updated.windowStartDate = nil
        }
        return updated
    }

    public static func canShowAutomaticVocabulary(
        _ snapshot: VocabularyDisplayScheduleSnapshot,
        now: Date,
        calendar: Calendar = .current
    ) -> Bool {
        let updated = resetIfNeeded(snapshot, now: now, calendar: calendar)
        guard updated.shownCount < updated.dailyLimit else { return false }
        guard let windowStart = updated.windowStartDate else { return true }
        return now < windowStart.addingTimeInterval(TimeInterval(updated.windowHours * 3600))
    }

    public static func recordAutomaticVocabularyShown(
        _ snapshot: VocabularyDisplayScheduleSnapshot,
        now: Date,
        calendar: Calendar = .current
    ) -> VocabularyDisplayScheduleSnapshot {
        var updated = resetIfNeeded(snapshot, now: now, calendar: calendar)
        if updated.windowStartDate == nil {
            updated.windowStartDate = now
        }
        updated.shownCount = min(updated.dailyLimit, updated.shownCount + 1)
        return updated
    }

    public static func windowEndDate(_ snapshot: VocabularyDisplayScheduleSnapshot) -> Date? {
        let updated = normalized(snapshot)
        return updated.windowStartDate?.addingTimeInterval(TimeInterval(updated.windowHours * 3600))
    }

    public static func todayKey(for date: Date, calendar: Calendar = .current) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", components.year ?? 0, components.month ?? 0, components.day ?? 0)
    }

    public static func normalizedDailyLimit(_ value: Int) -> Int {
        min(max(value, 1), 50)
    }

    public static func normalizedWindowHours(_ value: Int) -> Int {
        min(max(value, 1), 12)
    }
}
