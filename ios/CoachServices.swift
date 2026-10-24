import Foundation
import Vision
import PhotosUI
import UserNotifications
import AVFoundation
import Speech
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Screenshot OCR happens locally and the user must confirm the number manually.
enum TextScanner {
    static func scan(_ imageData: Data) async -> [String] {
        await Task.detached(priority: .userInitiated) {
            let req = VNRecognizeTextRequest()
            req.recognitionLevel = .accurate
            req.usesLanguageCorrection = true
            do {
                try VNImageRequestHandler(data: imageData, options: [:]).perform([req])
                return (req.results ?? []).compactMap { $0.topCandidates(1).first?.string }
            } catch { return ["Unable to scan this image. Please enter the numbers yourself."] }
        }.value
    }
    static func likelyMinutes(_ lines: [String]) -> Int? {
        // Only give a suggestion; Screenshots may contain daily averages or other dates.
        for line in lines {
            let s = line.lowercased()
            let pattern = #"(\d{1,2})\s*h(?:r|ours?)?\s*(\d{1,2})\s*m"#
            if let r = s.range(of: pattern, options: .regularExpression) {
                let substring = String(s[r])
                let numbers = substring.split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }
                if numbers.count >= 2 { return numbers[0] * 60 + numbers[1] }
            }
            let minutesOnly = #"\b(\d{1,3})\s*m(?:in)?\b"#
            if let r = s.range(of: minutesOnly, options: .regularExpression),
               let n = Int(String(s[r]).split(whereSeparator: { !$0.isNumber }).first ?? "") { return n }
        }
        return nil
    }
}

@MainActor
final class CoachNotifications: ObservableObject {
    @Published var permissionLabel = "Not requested"
    private let center = UNUserNotificationCenter.current()

    func ask(_ store: CoachStore) async {
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            store.state.notificationsEnabled = granted
            permissionLabel = granted ? "Allowed" : "Denied in iOS Settings"
            if granted { schedule(store) }
        } catch { permissionLabel = error.localizedDescription }
    }

    // Repeat only on predictable schedules. No arbitrary background execution or unlimited spam.
    func schedule(_ store: CoachStore) {
        center.removeAllPendingNotificationRequests()
        guard store.state.notificationsEnabled else { return }
        let s = store.state
        let cal = Calendar.current
        func inQuiet(_ hour: Int) -> Bool {
            if s.silentHourStart > s.silentHourEnd { return hour >= s.silentHourStart || hour < s.silentHourEnd }
            return hour >= s.silentHourStart && hour < s.silentHourEnd
        }
        func notify(_ id: String, _ title: String, _ body: String, date: Date, repeats: Bool = false) {
            let hour = cal.component(.hour, from: date)
            guard !inQuiet(hour) && date > Date() else { return }
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            content.sound = .default
            let parts = cal.dateComponents(repeats ? [.hour, .minute] : [.year, .month, .day, .hour, .minute], from: date)
            let trigger = UNCalendarNotificationTrigger(dateMatching: parts, repeats: repeats)
            center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
        }
        // Respect the football-season pause and recovery: no Coach nags in these modes.
        guard s.offSeason && !s.recovering else { return }
        if let tomorrow = cal.date(byAdding: .day, value: 1, to: Date()),
           let morning = cal.date(bySettingHour: 7, minute: 15, second: 0, of: tomorrow) {
            notify("screen.audit", "📱 COACH: SCREEN TIME AUDIT", "UPLOAD YESTERDAY'S REPORT. KEEP IT ACCURATE.", date: morning, repeats: true)
        }
        let messages = [
            (10, "HOPE YOU AREN'T RACKING UP TOO MANY MINUTES. KEEP THE GOAL IN MIND."),
            (14, "PHONE BREAK CHECK. DON'T LET SCROLLING TAKE OVER THE DAY."),
            (18, "YOU'VE HAD TIME FOR YOUR PHONE. MAKE TIME FOR YOUR PLAN TOO.")
        ]
        for (hour, message) in messages where !inQuiet(hour) {
            if let tomorrow = cal.date(byAdding: .day, value: 1, to: Date()),
               let first = cal.date(bySettingHour: hour, minute: 0, second: 0, of: tomorrow) {
                notify("coach.nudge.\(hour)", "🏈 COACH CHECK-IN", message, date: first, repeats: true)
            }
        }
        // Concrete dates prevent cancelled/completed workout reminders from repeating indefinitely.
        for offset in 0..<5 {
            guard let day = cal.date(byAdding: .day, value: offset, to: Date()),
                  let scheduled = cal.date(bySettingHour: s.workoutHour, minute: s.workoutMinute, second: 0, of: day) else { continue }
            let dayKey = CoachDate.key(day)
            let done = s.checkins.first(where: { $0.day == dayKey })
            if done?.finished == true || done?.excused == true { continue }
            if let before = cal.date(byAdding: .minute, value: -10, to: scheduled) {
                notify("workout.before.\(offset)", "🏈 SESSION IN 10 MINUTES", "GET READY FOR YOUR COACH CHECKPOINT.", date: before)
            }
            let nagOffsets = s.strictReminders ? [0, 15, 30, 45, 60] : [0, 30]
            for n in nagOffsets {
                guard let date = cal.date(byAdding: .minute, value: n, to: scheduled) else { continue }
                let label = n == 0 ? "IT'S TRAINING TIME, ROOKIE." : "\(n) MINUTES SINCE THE COMMITMENT. START, RESCHEDULE, OR CHECK IN FOR RECOVERY."
                notify("workout.\(offset).\(n)", "🏈 FOURTH DOWN COACH", label, date: date)
            }
            if BonusSchedule.isBonusDay(day), let bonus = cal.date(bySettingHour: 16, minute: 0, second: 0, of: day) {
                notify("bonus.\(offset)", "⚡ 2X CREDIT WINDOW", "ONE VERIFIED REP CAN EARN TWO BANK CREDITS UNTIL 5 PM. DON'T OVERTRAIN.", date: bonus)
            }
        }
        if let next = cal.date(byAdding: .day, value: 7, to: Date()),
           let grade = cal.date(bySettingHour: 17, minute: 0, second: 0, of: next) {
            notify("grades.weekly", "📚 WEEKLY GRADE CHECK", "REVIEW CURRENT GRADES WITH COACH. SCHOOL COMES FIRST.", date: grade, repeats: true)
        }
    }
}

@MainActor
final class CoachSpeech: ObservableObject {
    @Published var listening = false
    @Published var recognized = ""
    @Published var issue: String?
    private let speech = SFSpeechRecognizer(locale: Locale(identifier: "en_US"))
    private let engine = AVAudioEngine()
    private var bufferRequest: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private let voice = AVSpeechSynthesizer()

    func say(_ text: String) {
        let utterance = AVSpeechUtterance(string: text)
        utterance.rate = 0.53
        voice.speak(utterance)
    }
    func stopSpeaking() { voice.stopSpeaking(at: .immediate) }
    func start() {
        SFSpeechRecognizer.requestAuthorization { [weak self] permission in
            AVAudioApplication.requestRecordPermission { microphone in
                Task { @MainActor in
                    guard let self else { return }
                    guard permission == .authorized && microphone else {
                        self.issue = "Microphone and speech recognition permission are required for voice commands."
                        return
                    }
                    self.beginAudio()
                }
            }
        }
    }
    private func beginAudio() {
        stop()
        guard speech?.isAvailable == true else { issue = "Speech recognition is unavailable right now."; return }
        do {
            try AVAudioSession.sharedInstance().setCategory(.record, mode: .measurement, options: [.duckOthers])
            try AVAudioSession.sharedInstance().setActive(true)
            let req = SFSpeechAudioBufferRecognitionRequest()
            req.shouldReportPartialResults = true
            // Avoid sending voice audio to Apple servers when on-device recognition is unavailable.
            guard speech?.supportsOnDeviceRecognition == true else {
                issue = "On-device speech recognition isn't available. Type your command instead."
                return
            }
            req.requiresOnDeviceRecognition = true
            let input = engine.inputNode
            let format = input.outputFormat(forBus: 0)
            input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in req.append(buffer) }
            engine.prepare()
            try engine.start()
            bufferRequest = req
            listening = true
            task = speech?.recognitionTask(with: req) { [weak self] result, error in
                Task { @MainActor in
                    if let result { self?.recognized = result.bestTranscription.formattedString }
                    if error != nil { self?.stop() }
                }
            }
        } catch { issue = error.localizedDescription; stop() }
    }
    func stop() {
        if engine.isRunning { engine.stop(); engine.inputNode.removeTap(onBus: 0) }
        bufferRequest?.endAudio()
        task?.cancel()
        task = nil
        bufferRequest = nil
        listening = false
        try? AVAudioSession.sharedInstance().setActive(false)
    }
}

/// The offline coach always responds. On Apple Intelligence-capable iOS 26+ devices,
/// Foundation Models may optionally generate DIALOGUE, never balance-changing decisions.
enum CoachDialogue {
    static func ruleReply(_ prompt: String, state: CoachState) -> String {
        let t = prompt.lowercased()
        if t.contains("hurt") || t.contains("injur") || t.contains("sick") || t.contains("pain") || t.contains("exhausted") {
            return "RECOVERY APPROVED. STOP TRAINING, REST, AND TELL A TRUSTED ADULT IF YOU'RE INJURED. NO PUNISHMENT REPS."
        }
        if t.contains("travel") || t.contains("road") || t.contains("airport") { return "TRAVEL MODE IS AVAILABLE. YOU CAN LOG A LIMITED HONOR-SYSTEM LOAN. NEVER TRAIN INSIDE A MOVING VEHICLE." }
        if t.contains("dummy") || t.contains("inside") { return "NO DUMMY? WE SWITCH TO STANCE AND FOOTWORK. IF IT'S DARK OR COLD, ONLY TRAIN INSIDE IF YOU HAVE CLEAR, SAFE SPACE." }
        if t.contains("school") || t.contains("homework") || t.contains("grade") || t.contains("study") { return "SCHOOL FIRST. FINISH YOUR WORK, THEN WE'LL ADJUST THE TRAINING TIME. ACADEMICS COUNT." }
        if t.contains("skip") || t.contains("excuse") || t.contains("can't") || t.contains("later") { return "TELL ME WHAT'S IN THE WAY. IF IT'S SCHOOL, PRACTICE, HEALTH, OR SLEEP, RESCHEDULE. OTHERWISE, START WITH TWO MINUTES OF FOOTWORK." }
        if t.contains("minutes") || t.contains("more time") { return "EARNED MINUTES ARE RECORDED IN YOUR BANK. I CAN'T CHANGE IOS SCREEN TIME LOCKS. DO THE WORK OR START A PHONE-FREE CHALLENGE." }
        if t.contains("replay") || t.contains("review") { return "CHECK THE FILM ROOM. THE CAMERA ESTIMATES POSE MOVEMENT ONLY; IT DOESN'T KNOW WHETHER YOU MADE A GOOD HIT." }
        if t.contains("double") || t.contains("2x") { return BonusSchedule.activeNow ? "2X WINDOW OPEN. QUALITY REPS ONLY, WITH THE DAILY LIMIT STILL IN PLACE." : "NO 2X WINDOW AT THE MOMENT. EARN YOUR REGULAR CREDITS." }
        if t.contains("report") || t.contains("screen time") { return "SUBMIT YESTERDAY'S SCREEN TIME SCREENSHOT AND CONFIRM RECREATIONAL MINUTES. ACCURATE REPORTS BUILD TRUST." }
        return "I HEAR YOU. CHECK YOUR DAILY COMMITMENT, KEEP THE REPORT HONEST, AND MAKE SMART PROGRESS. TELL ME IF YOU NEED TO RESCHEDULE OR RECOVER."
    }
    static func onDeviceReply(_ prompt: String, state: CoachState) async -> String? {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            let model = LanguageModelSession(instructions: """
            You are Fourth Down Coach, a demanding but respectful football coach for a teenage player. Respond in at most 65 words, firm, concise, all caps. Never shame, insult, or urge excessive exercise. Health, recovery, sleep, school, and parents come first. You may ONLY write dialogue. Never claim you verified reps, photos, grades, usage or unlocked apps. Never modify balances or grant permissions. For requests to skip due to illness or injury, approve rest.
            """)
            if let response = try? await model.respond(to: "Athlete: \(prompt). Offseason enabled: \(state.offSeason). Recovery: \(state.recovering).") {
                return response.content
            }
        }
        #endif
        return nil
    }
}
