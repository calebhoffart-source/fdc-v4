import Foundation
import SwiftUI

// Data stays in the app's local UserDefaults. No account, backend, or upload.
enum DrillKind: String, CaseIterable, Codable, Identifiable {
    case offense = "Offensive Line"
    case defense = "Defensive Line"
    case tackle = "Controlled Tackle"
    case footwork = "No-Dummy Footwork"
    var id: String { rawValue }
    var icon: String {
        switch self { case .offense: return "figure.american.football"; case .defense: return "shield.fill"; case .tackle: return "figure.strengthtraining.functional"; case .footwork: return "figure.run" }
    }
    var requiresDummy: Bool { self == .offense || self == .defense || self == .tackle }
}

struct PoseProfile: Codable {
    var stanceAngle: Double
    var extensionAngle: Double
    var date: Date
    var examples: Int
}
struct ScreenReport: Codable, Identifiable {
    var id: String { day }
    var day: String // Calendar day of the reported usage, not submission day.
    var recreationalMinutes: Int
    var submittedAt: Date
    var reviewedOCR: Bool
}
struct CoachSession: Codable, Identifiable {
    var id = UUID()
    var date: Date
    var drill: DrillKind
    var countedReps: Int
    var creditMinutes: Int
    var source: String // camera, self-reported, etc.
}
struct GradeRecord: Codable, Identifiable {
    var id = UUID()
    var submittedAt = Date()
    var period: String
    var subject: String
    var percent: Int
    var reviewedOCR = false
}
struct ChatEntry: Codable, Identifiable {
    var id = UUID()
    var createdAt = Date()
    var fromCoach: Bool
    var text: String
}
struct FilmClip: Codable, Identifiable {
    var id = UUID()
    var date = Date()
    var drill: DrillKind
    var fileName: String
}
struct DailyCheckin: Codable, Identifiable {
    var id: String { day }
    var day: String
    var committed: Bool = false
    var started: Bool = false
    var finished: Bool = false
    var excused: Bool = false
    var reason: String = ""
}
struct FocusRecord: Codable, Identifiable {
    var id = UUID()
    var date = Date()
    var minutes: Int
    var completed: Bool
}

struct CoachState: Codable {
    var onboardingFinished = false
    var offSeason = false // School football season: workouts paused by default.
    var recovering = false
    var noDummy = false
    var notificationsEnabled = false
    var voiceEnabled = false
    var strictReminders = true
    var silentHourStart = 21
    var silentHourEnd = 7
    var workoutHour = 17
    var workoutMinute = 30
    var earnedMinutes = 0
    var travelDebt = 0
    var studyMinutesDue = 0
    var borrowedMinutes = 0
    var reports: [ScreenReport] = []
    var sessions: [CoachSession] = []
    var grades: [GradeRecord] = []
    var conversations: [ChatEntry] = [ChatEntry(fromCoach: true, text: "WELCOME TO FOURTH DOWN COACH. WE BUILD CONSISTENCY, NOT EXCUSES. SCHOOL, SLEEP, AND RECOVERY ALWAYS COME FIRST.")]
    var calibrations: [String: PoseProfile] = [:]
    var checkins: [DailyCheckin] = []
    var focus: [FocusRecord] = []
    var films: [FilmClip] = []
    var weeklyGradeCheck: Date? = nil
    var lastReportReminder: Date? = nil
    var coachTrust = 50
    var lastAccountabilityReviewDay = ""
    var voluntaryUpDownDay = ""
    var voluntaryUpDownCount = 0
    var lastBonusCreditDay: String? = nil
    var lastPauseChange = Date()
}

enum CoachDate {
    static func key(_ date: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar.current
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
    static func yesterday() -> String { key(Calendar.current.date(byAdding: .day, value: -1, to: Date()) ?? Date()) }
    static func sameDay(_ date: Date, as other: Date = Date()) -> Bool { Calendar.current.isDate(date, inSameDayAs: other) }
}

@MainActor
final class CoachStore: ObservableObject {
    @Published var state: CoachState { didSet { save() } }
    private static let storageKey = "FourthDownCoach.Free.V4.data"
    static let dailyCameraCap = 50
    static let dailyTackleCap = 8
    static let dailySelfReportCap = 15

    init() {
        if let data = UserDefaults.standard.data(forKey: Self.storageKey),
           let restored = try? JSONDecoder().decode(CoachState.self, from: data) {
            state = restored
        } else { state = CoachState() }
        auditMissedCommitments()
    }
    private func save() {
        guard let json = try? JSONEncoder().encode(state) else { return }
        UserDefaults.standard.set(json, forKey: Self.storageKey)
    }
    var yesterdayReport: ScreenReport? { state.reports.first { $0.day == CoachDate.yesterday() } }
    var goalToday: Int { AccountabilityRules.nextDayRepTarget(recreationalMinutes: yesterdayReport?.recreationalMinutes ?? 0) }
    var todayReps: Int { state.sessions.filter { CoachDate.sameDay($0.date) }.reduce(0) { $0 + $1.countedReps } }
    var todayTackles: Int { state.sessions.filter { CoachDate.sameDay($0.date) && $0.drill == .tackle }.reduce(0) { $0 + $1.countedReps } }
    var todayManual: Int { state.sessions.filter { CoachDate.sameDay($0.date) && $0.source == "manual" }.reduce(0) { $0 + $1.countedReps } }
    var weeklyWorkouts: Int { state.sessions.filter { $0.date >= Date().addingTimeInterval(-7 * 86400) }.count }
    var currentCheckin: DailyCheckin? { state.checkins.first { $0.day == CoachDate.key() } }
    var isSafeToTrain: Bool { state.offSeason && !state.recovering }
    var certified: Bool { [DrillKind.offense, .defense, .tackle].allSatisfy { state.calibrations[$0.rawValue] != nil } }

    // Target remains 1 minute = 1 accountability rep; doing hundreds of physical reps is NOT required or prescribed.
    var trainingRoomToday: Int { max(0, Self.dailyCameraCap - todayReps) }
    var safelyAssignedToday: Int { AccountabilityRules.maxSafeTrainingAssignment(target: goalToday) }
    var upDownsToday: Int { state.voluntaryUpDownDay == CoachDate.key() ? state.voluntaryUpDownCount : 0 }
    func logOptionalUpDown() {
        guard isSafeToTrain && upDownsToday < 20 else { return }
        if state.voluntaryUpDownDay != CoachDate.key() { state.voluntaryUpDownDay = CoachDate.key(); state.voluntaryUpDownCount = 0 }
        state.voluntaryUpDownCount += 1
        if state.voluntaryUpDownCount == 20 { coach("YOU'VE REACHED THE OPTIONAL UP-DOWN LIMIT. NO MORE TODAY.") }
    }
    var weekTrustLabel: String { state.coachTrust >= 75 ? "Reliable" : state.coachTrust >= 40 ? "Building" : "Resetting" }
    var level: String {
        let total = state.sessions.reduce(0) { $0 + $1.countedReps }
        if total >= 1200 { return "All-American" }
        if total >= 700 { return "All-State" }
        if total >= 350 { return "Varsity" }
        if total >= 120 { return "Starter" }
        return "Rookie"
    }

    func addReport(day: String, minutes: Int, reviewedOCR: Bool) {
        guard minutes >= 0 && minutes <= 1440 else { return }
        state.reports.removeAll { $0.day == day }
        state.reports.append(ScreenReport(day: day, recreationalMinutes: minutes, submittedAt: Date(), reviewedOCR: reviewedOCR))
        state.reports.sort { $0.day > $1.day }
        state.reports = Array(state.reports.prefix(120))
        adjustTrust(2)
        coach("REPORT RECEIVED. \(minutes) RECREATIONAL MINUTES RECORDED FOR \(day). THAT'S YOUR 1:1 ACCOUNTABILITY TARGET THE NEXT DAY. TRAINING STILL HAS A SAFETY LIMIT.")
    }
    @discardableResult
    func recordRep(_ drill: DrillKind, source: String) -> Bool {
        guard isSafeToTrain else { coach("TRAINING IS PAUSED. RECOVERY AND SCHOOL SEASON TAKE PRIORITY."); return false }
        guard todayReps < Self.dailyCameraCap else { coach("DAILY WORKOUT CAP REACHED. STOP FOR TODAY."); return false }
        guard drill != .tackle || todayTackles < Self.dailyTackleCap else { coach("CONTACT-DRILL LIMIT REACHED. NO MORE TACKLE REPS TODAY."); return false }
        guard source != "manual" || todayManual < Self.dailySelfReportCap else { coach("MANUAL REP LIMIT REACHED. USE CAMERA VERIFICATION NEXT TIME."); return false }
        let credit = BonusSchedule.activeNow ? 2 : 1
        state.sessions.append(CoachSession(date: Date(), drill: drill, countedReps: 1, creditMinutes: credit, source: source))
        var payout = credit
        if state.travelDebt > 0 { let paid = min(payout, state.travelDebt); state.travelDebt -= paid; payout -= paid }
        state.earnedMinutes += payout
        if todayReps % 10 == 0 { adjustTrust(1) }
        return true
    }
    func saveCalibration(_ kind: DrillKind, min: Double, max: Double) {
        state.calibrations[kind.rawValue] = PoseProfile(stanceAngle: min, extensionAngle: max, date: Date(), examples: 3)
        coach("\(kind.rawValue.uppercased()) CALIBRATION SAVED. THIS TRACKS A MOVEMENT PATTERN, NOT CONTACT OR SAFE TACKLING TECHNIQUE.")
    }
    func addFilm(_ kind: DrillKind, filename: String) { state.films.insert(FilmClip(drill: kind, fileName: filename), at: 0) }
    func borrowForTravel(_ amount: Int) {
        guard amount > 0 && amount <= 120 else { return }
        state.borrowedMinutes += amount
        state.travelDebt += AccountabilityRules.travelLoanRepayment(borrowedMinutes: amount)
        coach("TRAVEL LOAN: \(amount) MINUTES LOGGED. \(AccountabilityRules.travelLoanRepayment(borrowedMinutes: amount)) MINUTES WILL BE REPAID FROM FUTURE EARNINGS. NEVER EXERCISE IN A MOVING VEHICLE.")
    }
    func spendBank(_ amount: Int) {
        guard amount > 0 && amount <= state.earnedMinutes else { return }
        state.earnedMinutes -= amount
        coach("\(amount) EARNED MINUTES MARKED AS SPENT. THIS IS HONOR-SYSTEM TRACKING; IOS APPS ARE NOT ACTUALLY UNLOCKED.")
    }
    func addGrade(subject: String, percent: Int, period: String, ocr: Bool) {
        guard (0...100).contains(percent), !subject.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        state.grades.insert(GradeRecord(period: period, subject: subject, percent: percent, reviewedOCR: ocr), at: 0)
        if percent < 70 {
            state.studyMinutesDue += 20
            coach("\(subject.uppercased()) IS \(percent)%. SCHOOL FIRST. 20 MINUTES OF STUDY TIME ADDED, NOT PUNISHMENT REPS. ASK A TEACHER FOR HELP IF NEEDED.")
        } else { coach("\(subject.uppercased()) IS \(percent)%. GOOD. KEEP SCHOOL WORK CONSISTENT.") }
    }
    func recordStudy(_ minutes: Int) {
        guard minutes > 0 && minutes <= 180 else { return }
        state.studyMinutesDue = max(0, state.studyMinutesDue - minutes)
        coach("\(minutes) MINUTES OF STUDY TIME LOGGED. TAKE CARE OF YOUR GRADES.")
    }
    func coach(_ text: String) {
        state.conversations.append(ChatEntry(fromCoach: true, text: text))
        state.conversations = Array(state.conversations.suffix(100))
    }
    func userMessage(_ text: String) { state.conversations.append(ChatEntry(fromCoach: false, text: text)) }
    func adjustTrust(_ delta: Int) { state.coachTrust = min(100, max(0, state.coachTrust + delta)) }
    func commitToday() {
        ensureCheckin()
        if let i = state.checkins.firstIndex(where: { $0.day == CoachDate.key() }) { state.checkins[i].committed = true }
        coach("COMMITMENT ACCEPTED. I EXPECT YOU TO CHECK IN, BUT REST AND SCHOOL COME FIRST.")
    }
    func startCheckin() {
        ensureCheckin()
        if let i = state.checkins.firstIndex(where: { $0.day == CoachDate.key() }) { state.checkins[i].started = true }
        coach("CHECKPOINT ONE COMPLETE. GET SET UP SAFELY AND WORK ON QUALITY REPS.")
    }
    func finishCheckin() {
        ensureCheckin()
        if let i = state.checkins.firstIndex(where: { $0.day == CoachDate.key() }) {
            state.checkins[i].finished = true
            adjustTrust(3)
        }
        coach("CHECKPOINT TWO COMPLETE. YOU FOLLOWED THROUGH. RECOVER WELL.")
    }
    func excuseToday(_ reason: String) {
        ensureCheckin()
        if let i = state.checkins.firstIndex(where: { $0.day == CoachDate.key() }) {
            state.checkins[i].excused = true
            state.checkins[i].reason = reason
        }
        coach("RESCHEDULE APPROVED: \(reason). YOUR HEALTH AND SCHOOL COMMITMENTS COME FIRST. NO EXTRA REP DEBT.")
    }
    func auditMissedCommitments() {
        let today = CoachDate.key()
        guard state.lastAccountabilityReviewDay != today else { return }
        let cutoff = state.lastAccountabilityReviewDay
        let missed = state.checkins.filter {
            $0.day < today && $0.day > cutoff && $0.committed && !$0.finished && !$0.excused
        }.count
        state.lastAccountabilityReviewDay = today
        if missed > 0 && state.offSeason {
            adjustTrust(-min(12, missed * 3))
            coach("YOU MISSED \(missed) PRIOR COMMITMENT(S). NO REP PUNISHMENT. RESET WITH A COMEBACK CHALLENGE WHEN READY.")
        }
    }
    func comebackChallenge() {
        guard isSafeToTrain else {
            coach("YOUR COMEBACK IS RECOVERY OR SCHOOL RIGHT NOW. NO EXTRA WORKOUT NECESSARY.")
            return
        }
        commitToday()
        coach("COMEBACK CHALLENGE: START WITH TWO CONTROLLED MINUTES OF STANCE OR FOOTWORK, THEN DECIDE IF YOU'RE READY FOR MORE. NO PUNISHMENT REPS.")
    }
    func recovery(_ reason: String) {
        state.recovering = true
        ensureCheckin()
        if let i = state.checkins.firstIndex(where: { $0.day == CoachDate.key() }) {
            state.checkins[i].excused = true
            state.checkins[i].reason = reason
        }
        coach("RECOVERY MODE ACTIVE: \(reason). NO WORKOUT DEBT. COME BACK HEALTHY.")
    }
    func resumeRecovery() { state.recovering = false; coach("RECOVERY MODE OFF. RETURN GRADUALLY AND STOP IF YOU HAVE PAIN.") }
    func setSeason(_ active: Bool) {
        state.offSeason = active
        state.lastPauseChange = Date()
        coach(active ? "OFFSEASON TRAINING ON. TRAIN SMART." : "FOOTBALL SEASON PAUSE ACTIVE. NO EXTRA TRAINING REQUIREMENTS OR WORKOUT REMINDERS.")
    }
    func recordFocus(_ minutes: Int, completed: Bool) {
        state.focus.insert(FocusRecord(minutes: minutes, completed: completed), at: 0)
        if completed { adjustTrust(2); coach("FOCUS DRIVE COMPLETE. GOOD DISCIPLINE.") }
        else { coach("FOCUS SESSION STOPPED EARLY. RESET AND TRY AGAIN WHEN READY.") }
    }
    private func ensureCheckin() {
        if !state.checkins.contains(where: { $0.day == CoachDate.key() }) {
            state.checkins.append(DailyCheckin(day: CoachDate.key()))
        }
    }
    var weeklySummary: String {
        let weekAgo = Date().addingTimeInterval(-7*86400)
        let reps = state.sessions.filter { $0.date >= weekAgo }.reduce(0) { $0 + $1.countedReps }
        let completed = state.checkins.filter { $0.day >= CoachDate.key(weekAgo) && $0.finished }.count
        let reports = state.reports.filter { $0.submittedAt >= weekAgo }.count
        let focusMinutes = state.focus.filter { $0.date >= weekAgo && $0.completed }.reduce(0) { $0 + $1.minutes }
        return "\(reps) reps • \(completed) completed check-ins • \(reports) Screen Time reports • \(focusMinutes) focus minutes. Trust: \(state.coachTrust)/100."
    }
}

/// Deterministic rolling two days per week; users can see the 2X window in advance.
enum BonusSchedule {
    static func isBonusDay(_ date: Date) -> Bool {
        let cal = Calendar.current
        let week = cal.component(.weekOfYear, from: date)
        let year = cal.component(.yearForWeekOfYear, from: date)
        let day = cal.component(.weekday, from: date)
        let first = (week + year) % 7 + 1
        let second = (first + 3 - 1) % 7 + 1
        return day == first || day == second
    }
    static var activeNow: Bool { isBonusDay(Date()) && Calendar.current.component(.hour, from: Date()) == 16 }
}
