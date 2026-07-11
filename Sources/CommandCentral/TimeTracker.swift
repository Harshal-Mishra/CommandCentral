import CoreGraphics
import Foundation

struct StudySession: Codable, Identifiable {
    var id = UUID()
    var subject: String
    var date: Date      // session start
    var seconds: Int
    var detail: String? // e.g. the task this time was spent on
}

enum StatsRange: String, CaseIterable, Identifiable {
    case week = "7 Days"
    case month = "This Month"
    case all = "All Time"
    var id: String { rawValue }
}

/// Logs studied/worked time per subject and computes totals & streaks.
final class TimeTracker: ObservableObject {
    @Published private(set) var sessions: [StudySession] = []
    @Published private(set) var subjects: [String] = []
    @Published private(set) var dailyGoalMinutes = 120
    @Published private(set) var activeSubject: String?
    @Published private(set) var activeStart: Date?
    @Published private(set) var activeDetail: String?
    @Published private(set) var autoStopNotice: String?

    private var idleTimer: Timer?
    private let idleLimitSeconds = 300

    private var fileURL: URL { Storage.directory.appendingPathComponent("tracker.json") }

    private struct TrackerData: Codable {
        var sessions: [StudySession]
        var subjects: [String]
        var dailyGoalMinutes: Int
    }

    private static let defaultSubjects = ["Maths", "Physics", "Chemistry", "Coding", "Reading", "Other"]

    init() {
        if let data = try? Data(contentsOf: fileURL),
           let decoded = try? JSONDecoder().decode(TrackerData.self, from: data) {
            sessions = decoded.sessions
            subjects = decoded.subjects.isEmpty ? Self.defaultSubjects : decoded.subjects
            dailyGoalMinutes = decoded.dailyGoalMinutes
        } else {
            subjects = Self.defaultSubjects
        }
    }

    // MARK: - Logging

    func log(subject: String, seconds: Int, detail: String? = nil) {
        guard seconds >= 60 else { return }
        let canonical = addSubjectIfNeeded(subject)
        sessions.append(StudySession(subject: canonical,
                                     date: Date().addingTimeInterval(-Double(seconds)),
                                     seconds: seconds,
                                     detail: detail))
        save()
    }

    func deleteSession(_ id: UUID) {
        sessions.removeAll { $0.id == id }
        save()
    }

    func addManual(subject: String, minutes: Int, day: Date) {
        guard minutes > 0 else { return }
        let noon = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: day) ?? day
        sessions.append(StudySession(subject: addSubjectIfNeeded(subject),
                                     date: noon,
                                     seconds: minutes * 60,
                                     detail: "manual entry"))
        save()
    }

    var recentSessions: [StudySession] {
        Array(sessions.sorted { $0.date > $1.date }.prefix(12))
    }

    var isTracking: Bool { activeSubject != nil }

    var activeSeconds: Int {
        guard let activeStart else { return 0 }
        return Int(Date().timeIntervalSince(activeStart))
    }

    func startStopwatch(_ subject: String, detail: String? = nil) {
        stopStopwatch()
        activeSubject = addSubjectIfNeeded(subject)
        activeStart = Date()
        activeDetail = detail
        autoStopNotice = nil
        startIdleWatch()
    }

    func stopStopwatch() {
        if let subject = activeSubject, activeStart != nil {
            log(subject: subject, seconds: activeSeconds, detail: activeDetail)
        }
        clearActive()
    }

    private func clearActive() {
        activeSubject = nil
        activeStart = nil
        activeDetail = nil
        idleTimer?.invalidate()
        idleTimer = nil
    }

    // MARK: - Idle detection

    private func startIdleWatch() {
        idleTimer?.invalidate()
        idleTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            self?.checkIdle()
        }
    }

    /// If you walk away mid-session, stop the stopwatch and don't count
    /// the idle stretch — keeps the hours honest.
    private func checkIdle() {
        guard isTracking else { return }
        let types: [CGEventType] = [.mouseMoved, .keyDown, .leftMouseDown,
                                    .rightMouseDown, .scrollWheel]
        let idle = types.map {
            CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: $0)
        }.min() ?? 0
        guard Int(idle) >= idleLimitSeconds else { return }

        let counted = max(0, activeSeconds - Int(idle))
        let subject = activeSubject
        let detail = activeDetail
        clearActive()
        if let subject, counted >= 60 {
            log(subject: subject, seconds: counted, detail: detail)
            autoStopNotice = "Auto-stopped — you went idle. Saved \(formatHM(counted)) to \(subject)."
        } else {
            autoStopNotice = "Auto-stopped — you went idle before a full minute was tracked."
        }
    }

    // MARK: - Subjects & settings

    @discardableResult
    func addSubjectIfNeeded(_ name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return subjects.first ?? "Other" }
        if let existing = subjects.first(where: { $0.lowercased() == trimmed.lowercased() }) {
            return existing
        }
        let canonical = trimmed.prefix(1).uppercased() + trimmed.dropFirst()
        subjects.append(canonical)
        save()
        return canonical
    }

    func removeSubject(_ name: String) {
        subjects.removeAll { $0 == name }
        save()
    }

    func setGoal(_ minutes: Int) {
        dailyGoalMinutes = max(15, min(720, minutes))
        save()
    }

    // MARK: - Stats

    private var calendar: Calendar { Calendar.current }

    func seconds(on day: Date) -> Int {
        sessions.filter { calendar.isDate($0.date, inSameDayAs: day) }
            .reduce(0) { $0 + $1.seconds }
    }

    var todaySeconds: Int { seconds(on: Date()) }

    func seconds(in range: StatsRange) -> Int {
        sessionsIn(range).reduce(0) { $0 + $1.seconds }
    }

    func sessionsIn(_ range: StatsRange) -> [StudySession] {
        switch range {
        case .all:
            return sessions
        case .week:
            let start = calendar.startOfDay(for: calendar.date(byAdding: .day, value: -6, to: Date())!)
            return sessions.filter { $0.date >= start }
        case .month:
            let comps = calendar.dateComponents([.year, .month], from: Date())
            let start = calendar.date(from: comps)!
            return sessions.filter { $0.date >= start }
        }
    }

    func bySubject(_ range: StatsRange) -> [(subject: String, seconds: Int)] {
        var totals: [String: Int] = [:]
        for session in sessionsIn(range) {
            totals[session.subject, default: 0] += session.seconds
        }
        return totals.map { (subject: $0.key, seconds: $0.value) }
            .sorted { $0.seconds > $1.seconds }
    }

    func bySubjectToday() -> [(subject: String, seconds: Int)] {
        var totals: [String: Int] = [:]
        for session in sessions where calendar.isDate(session.date, inSameDayAs: Date()) {
            totals[session.subject, default: 0] += session.seconds
        }
        return totals.map { (subject: $0.key, seconds: $0.value) }
            .sorted { $0.seconds > $1.seconds }
    }

    struct DayTotal: Identifiable {
        let date: Date
        let minutes: Double
        var id: Date { date }
    }

    func dailyTotals(days: Int) -> [DayTotal] {
        (0..<days).reversed().map { offset in
            let day = calendar.date(byAdding: .day, value: -offset, to: Date())!
            return DayTotal(date: calendar.startOfDay(for: day),
                            minutes: Double(seconds(on: day)) / 60)
        }
    }

    private func metGoal(on day: Date) -> Bool {
        seconds(on: day) >= dailyGoalMinutes * 60
    }

    /// Consecutive days meeting the daily goal. Today only counts once met,
    /// but an unmet today doesn't break yesterday's streak.
    var currentStreak: Int {
        var streak = 0
        var day = Date()
        if !metGoal(on: day) {
            day = calendar.date(byAdding: .day, value: -1, to: day)!
        }
        while metGoal(on: day) {
            streak += 1
            day = calendar.date(byAdding: .day, value: -1, to: day)!
        }
        return streak
    }

    var bestStreak: Int {
        let goalDays = Set(sessions.map { calendar.startOfDay(for: $0.date) })
            .filter { metGoal(on: $0) }
            .sorted()
        var best = 0
        var run = 0
        var previous: Date?
        for day in goalDays {
            if let previous,
               let next = calendar.date(byAdding: .day, value: 1, to: previous),
               calendar.isDate(next, inSameDayAs: day) {
                run += 1
            } else {
                run = 1
            }
            best = max(best, run)
            previous = day
        }
        return best
    }

    var activeDaysThisMonth: Int {
        Set(sessionsIn(.month).map { calendar.startOfDay(for: $0.date) }).count
    }

    // MARK: - Persistence

    private func save() {
        let data = TrackerData(sessions: sessions,
                               subjects: subjects,
                               dailyGoalMinutes: dailyGoalMinutes)
        if let encoded = try? JSONEncoder().encode(data) {
            try? encoded.write(to: fileURL, options: .atomic)
        }
    }
}
