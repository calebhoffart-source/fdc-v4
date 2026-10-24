import SwiftUI
import AVKit

struct TrainingScreen: View {
    @EnvironmentObject private var store: CoachStore
    @EnvironmentObject private var notices: CoachNotifications
    @State private var kind: DrillKind = .offense
    @State private var showCamera = false
    @State private var showCalibration = false
    @State private var showRecovery = false
    @State private var recoveryReason = "Rest / football practice"
    @State private var showFocus = false
    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Heading(title: "TRAINING GROUND", subtitle: "Vision-assisted reps • your pace, quality first")
                if !store.isSafeToTrain {
                    CoachPanel(title: "Workout paused") {
                        Text(store.state.recovering ? "Recovery is active. No workout debt or rep penalties." : "School football season is paused by default. Turn on offseason training when your season is over.")
                        if store.state.recovering {
                            MainButton(title: "End Recovery Mode", icon: "heart.fill") { store.resumeRecovery(); notices.schedule(store) }
                        } else {
                            MainButton(title: "Start Offseason Training", icon: "play.circle.fill") { store.setSeason(true); notices.schedule(store) }
                        }
                    }
                }
                CoachPanel(title: "Choose your drill") {
                    Picker("Drill", selection: $kind) {
                        ForEach(DrillKind.allCases) { k in Text(k.rawValue).tag(k) }
                    }.pickerStyle(.menu).tint(CoachStyle.gold)
                    let profile = store.state.calibrations[kind.rawValue]
                    if kind != .footwork {
                        HStack {
                            Text(profile == nil ? "Calibration missing" : "Calibrated • \(profile!.examples) samples")
                            Spacer()
                            Image(systemName: profile == nil ? "exclamationmark.triangle.fill" : "checkmark.seal.fill")
                        }.font(.caption).foregroundStyle(profile == nil ? .orange : .green)
                    }
                    Text(drillDescription(kind)).font(.subheadline).foregroundStyle(CoachStyle.muted)
                    MainButton(title: "Open Live Rep Camera", icon: "camera.viewfinder") { showCamera = true }
                    .disabled(!store.isSafeToTrain || (kind.requiresDummy && (store.state.noDummy || store.state.calibrations[kind.rawValue] == nil)))
                    if kind.requiresDummy && store.state.calibrations[kind.rawValue] == nil {
                        MainButton(title: "Calibrate 3 Drill Types", icon: "viewfinder", color: CoachStyle.blue) { showCalibration = true }
                    }
                    if store.isSafeToTrain && store.todayManual < CoachStore.dailySelfReportCap {
                        Button("Log 1 unverified practice rep (honor system)") { _ = store.recordRep(kind, source: "manual") }
                            .font(.footnote).foregroundStyle(CoachStyle.muted)
                    }
                }
                CoachPanel(title: "Today") {
                    HStack {
                        VStack(alignment: .leading) { Text("\(store.todayReps)").font(.system(size: 36, weight: .black)).foregroundStyle(CoachStyle.gold); Text("Reps logged").font(.caption) }
                        Spacer()
                        VStack(alignment: .trailing) { Text("\(store.trainingRoomToday)").font(.system(size: 36, weight: .black)); Text("Before safety cap").font(.caption) }
                    }
                    ProgressView(value: Double(store.todayReps), total: Double(CoachStore.dailyCameraCap)).tint(CoachStyle.gold)
                    Text("Maximum \(CoachStore.dailyCameraCap) total training reps/day in this app, including no more than \(CoachStore.dailyTackleCap) controlled tackle reps. Rest, football practice, school and injuries override the target.")
                        .font(.caption).foregroundStyle(CoachStyle.muted)
                    if BonusSchedule.activeNow { Label("2X EARNED BANK CREDITS UNTIL 5 PM", systemImage: "bolt.fill").foregroundStyle(CoachStyle.gold) }
                }
                CoachPanel(title: "Training options") {
                    Toggle("No-dummy mode", isOn: Binding(get: { store.state.noDummy }, set: { store.state.noDummy = $0 }))
                    Button { showRecovery = true } label: { Label("Rest / injury / practice recovery", systemImage: "heart.text.square") }
                        .tint(CoachStyle.gold)
                    MainButton(title: "Phone-Free Focus Drive", icon: "moon.stars.fill", color: CoachStyle.blue) { showFocus = true }
                    HStack {
                        VStack(alignment: .leading) {
                            Text("Optional Up-Down Technique").font(.subheadline.bold())
                            Text("\(store.upDownsToday) / 20 today • No bank credit").font(.caption).foregroundStyle(CoachStyle.muted)
                        }
                        Spacer()
                        Button("+1") { store.logOptionalUpDown() }
                            .buttonStyle(.bordered).tint(CoachStyle.gold)
                            .disabled(!store.isSafeToTrain || store.upDownsToday >= 20)
                    }
                    Text("Never required as punishment for grades or screen time. Do only if healthy, rested, and cleared by your coach.")
                        .font(.caption).foregroundStyle(CoachStyle.muted)
                }
                CoachPanel(title: "Local film room") {
                    if store.state.films.isEmpty { Text("Record a clip during a camera session to review your movement.").foregroundStyle(CoachStyle.muted) }
                    ForEach(store.state.films.prefix(15)) { clip in
                        NavigationLink { FilmPlayerScreen(clip: clip) } label: {
                            HStack {
                                Image(systemName: "play.rectangle.fill")
                                VStack(alignment: .leading) { Text(clip.drill.rawValue); Text(clip.date, style: .date).font(.caption).foregroundStyle(CoachStyle.muted) }
                                Spacer(); Image(systemName: "chevron.right")
                            }
                        }.foregroundStyle(.white)
                    }
                    Text("Film stays on this iPhone. Reviewing footage does not constitute automatic appeal approval.")
                        .font(.caption2).foregroundStyle(CoachStyle.muted)
                }
            }.padding(16)
        }
        .background(CoachStyle.navy).toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $showCamera) {
            PoseCameraScreen(kind: kind, profile: store.state.calibrations[kind.rawValue])
                .environmentObject(store)
        }
        .sheet(isPresented: $showCalibration) { CalibrationWizard() }
        .sheet(isPresented: $showFocus) { NavigationStack { FocusDriveScreen() } }
        .alert("Recovery check-in", isPresented: $showRecovery) {
            TextField("Reason", text: $recoveryReason)
            Button("Enter Recovery Mode") { store.recovery(recoveryReason); notices.schedule(store) }
            Button("Cancel", role: .cancel) {}
        } message: { Text("Recovery cancels extra training obligations and workout reminders. You can return when ready.") }
    }
    private func drillDescription(_ drill: DrillKind) -> String {
        switch drill {
        case .offense: return "Calibrated stance → drive → reset pattern. The camera cannot verify pad level or blocking contact."
        case .defense: return "Calibrated defensive stance → extension → reset. Camera cannot classify an effective pass rush."
        case .tackle: return "Controlled padded-dummy movement only, with adult/coach supervision. No full-speed contact or injury-risk drills."
        case .footwork: return "No dummy needed: slow stance, step, extension, and reset in clear space. Pose detection uses generic knee-joint movement."
        }
    }
}

struct FocusDriveScreen: View {
    @EnvironmentObject private var store: CoachStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var minutes = 15
    @State private var end: Date?
    @State private var leftApp = false
    @State private var recordDone = false
    @State private var startDate: Date?
    var body: some View {
        ZStack { CoachStyle.navy.ignoresSafeArea()
            VStack(spacing: 25) {
                Image(systemName: "iphone.gen3.radiowaves.left.and.right").font(.system(size: 48)).foregroundStyle(CoachStyle.gold)
                Heading(title: "LOCK-IN DRIVE", subtitle: "A voluntary phone-free challenge")
                if let end {
                    TimelineView(.periodic(from: .now, by: 1)) { timeline in
                        let seconds = max(0, Int(end.timeIntervalSince(timeline.date)))
                        Text(String(format: "%02d:%02d", seconds/60, seconds%60))
                            .font(.system(size: 62, weight: .black, design: .monospaced))
                            .foregroundStyle(CoachStyle.gold).monospacedDigit()
                    }
                    Text("Set your phone down. Switching away does not block other apps.")
                        .foregroundStyle(CoachStyle.muted).multilineTextAlignment(.center)
                    MainButton(title: "End Challenge Early", icon: "stop.circle.fill", color: .orange) {
                        finish(completed: false)
                    }
                } else {
                    Picker("Duration", selection: $minutes) {
                        ForEach([15,30,60], id: \.self) { Text("\($0) min").tag($0) }
                    }.pickerStyle(.segmented)
                    MainButton(title: "Start Focus Drive", icon: "play.circle.fill") {
                        startDate = Date(); end = Date().addingTimeInterval(TimeInterval(minutes * 60))
                    }
                }
                Text("Ending early is allowed. No extra punishment reps. This timer does not independently verify phone usage.")
                    .font(.caption).foregroundStyle(CoachStyle.muted).multilineTextAlignment(.center)
                Spacer()
            }.padding(20)
        }
        .navigationTitle("Focus Drive")
        .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { if end != nil { finish(completed: false) }; dismiss() } } }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .background && end != nil { leftApp = true }
            if newPhase == .active, let end, Date() >= end && !recordDone { finish(completed: !leftApp) }
            else if newPhase == .active && leftApp && end != nil && !recordDone { finish(completed: false) }
        }
        .task(id: end) {
            guard let finishAt = end else { return }
            while !Task.isCancelled && Date() < finishAt {
                try? await Task.sleep(for: .seconds(1))
            }
            if !Task.isCancelled && !recordDone && Date() >= finishAt { finish(completed: !leftApp) }
        }
    }
    private func finish(completed: Bool) {
        guard !recordDone else { return }
        recordDone = true
        store.recordFocus(minutes, completed: completed)
        end = nil
    }
}
