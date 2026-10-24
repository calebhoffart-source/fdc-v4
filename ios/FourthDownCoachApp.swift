import SwiftUI

@main
struct FourthDownCoachApp: App {
    @StateObject private var store = CoachStore()
    @StateObject private var notices = CoachNotifications()
    var body: some Scene {
        WindowGroup {
            RootCoachView()
                .environmentObject(store)
                .environmentObject(notices)
                .preferredColorScheme(.dark)
        }
    }
}

enum CoachStyle {
    static let navy = Color(red: 0.035, green: 0.055, blue: 0.10)
    static let panel = Color(red: 0.08, green: 0.11, blue: 0.17)
    static let gold = Color(red: 1.0, green: 0.74, blue: 0.20)
    static let muted = Color(red: 0.57, green: 0.63, blue: 0.72)
    static let blue = Color(red: 0.23, green: 0.61, blue: 0.98)
}

struct CoachPanel<Content: View>: View {
    var title: String
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            Text(title.uppercased()).font(.caption.weight(.heavy)).tracking(1).foregroundStyle(CoachStyle.gold)
            content
        }
        .padding(17)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CoachStyle.panel, in: RoundedRectangle(cornerRadius: 18))
    }
}
struct MainButton: View {
    let title: String
    let icon: String
    var color = CoachStyle.gold
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.subheadline.bold())
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
        }.buttonStyle(.plain).foregroundStyle(.black)
            .background(color, in: RoundedRectangle(cornerRadius: 12))
    }
}
struct Heading: View {
    let title: String
    let subtitle: String
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.system(size: 30, weight: .black, design: .rounded)).foregroundStyle(.white)
            Text(subtitle).font(.subheadline).foregroundStyle(CoachStyle.muted)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct RootCoachView: View {
    @EnvironmentObject private var store: CoachStore
    @EnvironmentObject private var notifications: CoachNotifications
    @Environment(\.scenePhase) private var scenePhase
    @State private var selection = 0
    var body: some View {
        ZStack { CoachStyle.navy.ignoresSafeArea()
            if !store.state.onboardingFinished {
                WelcomeSetup()
            } else {
                TabView(selection: $selection) {
                    NavigationStack { HomeScreen(selection: $selection) }
                        .tabItem { Label("Home", systemImage: "house.fill") }.tag(0)
                    NavigationStack { TrainingScreen() }
                        .tabItem { Label("Train", systemImage: "figure.strengthtraining.functional") }.tag(1)
                    NavigationStack { CoachChatScreen() }
                        .tabItem { Label("Coach", systemImage: "bubble.left.and.bubble.right.fill") }.tag(2)
                    NavigationStack { ReportScreen() }
                        .tabItem { Label("Reports", systemImage: "chart.bar.fill") }.tag(3)
                    NavigationStack { MoreScreen() }
                        .tabItem { Label("More", systemImage: "line.3.horizontal") }.tag(4)
                }
                .tint(CoachStyle.gold)
                .toolbarBackground(CoachStyle.navy, for: .tabBar)
                .toolbarBackground(.visible, for: .tabBar)
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { store.auditMissedCommitments(); notifications.schedule(store) }
        }
    }
}

struct WelcomeSetup: View {
    @EnvironmentObject private var store: CoachStore
    @EnvironmentObject private var notices: CoachNotifications
    @State private var showCalibration = false
    var body: some View {
        ScrollView {
            VStack(spacing: 23) {
                Spacer(minLength: 25)
                Image(systemName: "shield.lefthalf.filled").font(.system(size: 66)).foregroundStyle(CoachStyle.gold)
                Text("FOURTH DOWN\nCOACH")
                    .font(.system(size: 38, weight: .black, design: .rounded)).multilineTextAlignment(.center)
                    .foregroundStyle(.white)
                Text("V4 • THE FREE NATIVE BUILD").font(.caption.bold()).tracking(2).foregroundStyle(CoachStyle.gold)
                CoachPanel(title: "First-time setup") {
                    Text("1. Calibrate 3 offensive reps, 3 defensive reps, and 3 controlled tackling-dummy movements using your camera.")
                    Text("2. Enable reminders and set an everyday commitment time.")
                    Text("3. Every morning, submit YESTERDAY'S Screen Time screenshot. One recreational minute = one accountability rep target. Safe workout limits apply.")
                }
                MainButton(title: store.certified ? "Recalibrate Camera" : "Calibrate All 3 Drills", icon: "camera.viewfinder") { showCalibration = true }
                MainButton(title: "Enable iPhone Notifications", icon: "bell.badge", color: CoachStyle.blue) { Task { await notices.ask(store) } }
                MainButton(title: "Enter Fourth Down Coach", icon: "arrow.right") {
                    store.state.onboardingFinished = true
                    notices.schedule(store)
                }
                Text("You can enter without the dummy and calibrate later. Training defaults to SEASON PAUSED; switch to offseason when appropriate. Nothing here can access or block other apps' Screen Time automatically.")
                    .font(.caption).foregroundStyle(CoachStyle.muted).multilineTextAlignment(.center)
            }.padding(21)
        }
        .sheet(isPresented: $showCalibration) { CalibrationWizard() }
    }
}

struct CalibrationWizard: View {
    @EnvironmentObject private var store: CoachStore
    @Environment(\.dismiss) private var dismiss
    @State private var index = 0
    @State private var showCamera = false
    private let kinds: [DrillKind] = [.offense, .defense, .tackle]
    var body: some View {
        NavigationStack {
            ZStack { CoachStyle.navy.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        Heading(title: "Camera calibration", subtitle: "Three samples of each motion pattern")
                        ForEach(Array(kinds.enumerated()), id: \.offset) { pair in
                            let i = pair.offset
                            let kind = pair.element
                            HStack(spacing: 12) {
                                Image(systemName: kind.icon).frame(width: 27).foregroundStyle(CoachStyle.gold)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(kind.rawValue).bold()
                                    Text(store.state.calibrations[kind.rawValue] != nil ? "Saved ✓" : "3 repetitions required").font(.caption).foregroundStyle(CoachStyle.muted)
                                }
                                Spacer()
                                if i == index { Image(systemName: "arrow.left").foregroundStyle(CoachStyle.gold) }
                            }.padding().background(CoachStyle.panel, in: RoundedRectangle(cornerRadius: 14))
                        }
                        CoachPanel(title: "Camera setup") {
                            Text("Place your phone securely, several steps away. Keep hips, knees, and ankles in frame. Calibrate with controlled motion in clear space.")
                            Text("AI tracks joint movements; calibration is NOT a trained tackling model or contact verification.").foregroundStyle(CoachStyle.muted)
                        }
                        if index < kinds.count {
                            MainButton(title: "Start \(kinds[index].rawValue) Calibration", icon: "camera.fill") { showCamera = true }
                        } else {
                            MainButton(title: "Calibration Complete", icon: "checkmark.seal.fill") { dismiss() }
                        }
                    }.padding(20)
                }
            }
            .navigationTitle("Calibration")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } } }
        }
        .sheet(isPresented: $showCamera) {
            if index < kinds.count {
                PoseCameraScreen(kind: kinds[index], calibrating: true) {
                    index = min(index + 1, kinds.count)
                }
            }
        }
    }
}

struct HomeScreen: View {
    @EnvironmentObject private var store: CoachStore
    @Binding var selection: Int
    @EnvironmentObject private var notices: CoachNotifications
    @State private var showCommit = false
    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Heading(title: "THE LOCKER ROOM", subtitle: "Your daily accountability dashboard")
                HStack {
                    Image(systemName: "shield.fill").foregroundStyle(CoachStyle.gold)
                    Text(store.isSafeToTrain ? "OFFSEASON • TRAINING ON" : store.state.recovering ? "RECOVERY • TRAINING PAUSED" : "SCHOOL SEASON • TRAINING PAUSED")
                        .font(.caption.bold()).tracking(0.4)
                    Spacer()
                }.padding(14).frame(maxWidth: .infinity).background(CoachStyle.panel, in: RoundedRectangle(cornerRadius: 12))
                CoachPanel(title: "Yesterday's report → today's target") {
                    if let report = store.yesterdayReport {
                        Text("\(report.recreationalMinutes) MINUTES").font(.system(size: 35, weight: .black)).foregroundStyle(CoachStyle.gold)
                        Text("\(store.goalToday) accountability reps • 1 minute = 1 target")
                        ProgressView(value: Double(min(store.todayReps, store.goalToday)), total: Double(max(1, store.goalToday))).tint(CoachStyle.gold)
                        HStack { Text("\(store.todayReps) detected/logged today"); Spacer(); Text("Physical cap: \(CoachStore.dailyCameraCap)/day") }.font(.caption).foregroundStyle(CoachStyle.muted)
                    } else {
                        Text("No report for yesterday yet.").font(.headline)
                        Text("Open Reports and submit yesterday's iPhone Screen Time screenshot. Coach needs your confirmation before assigning a target.").foregroundStyle(CoachStyle.muted)
                        MainButton(title: "Submit Screen Time", icon: "camera") { selection = 3 }
                    }
                }
                HStack(spacing: 12) {
                    statCard("EARNED BANK", "\(store.state.earnedMinutes)m", "clock.fill")
                    statCard("COACH TRUST", "\(store.state.coachTrust)%", "checkmark.shield.fill")
                }
                CoachPanel(title: "Today's commitment") {
                    Text("Scheduled training: \(formattedTime)").font(.title3.bold())
                    Text("Check in when you start and finish. If you're sick, tired, or injured, use Recovery.").font(.caption).foregroundStyle(CoachStyle.muted)
                    if store.currentCheckin?.committed == true { Label("Commitment saved", systemImage: "checkmark.circle.fill").foregroundStyle(.green) }
                    else { MainButton(title: "Commit to Today's Plan", icon: "hand.raised.fill") { store.commitToday() } }
                    if store.state.offSeason && !store.state.recovering {
                        HStack {
                            Button("Start Check-in") { store.startCheckin(); selection = 1 }.buttonStyle(.bordered).tint(CoachStyle.gold)
                            Button("Finish Check-in") { store.finishCheckin(); notices.schedule(store) }.buttonStyle(.bordered).tint(CoachStyle.gold)
                        }
                    }
                }
                CoachPanel(title: "Coach says") {
                    Text(store.state.conversations.last(where: { $0.fromCoach })?.text ?? "SHOW UP. WORK SMART.")
                        .font(.subheadline.bold())
                    MainButton(title: "Talk to Coach", icon: "message.fill") { selection = 2 }
                }
                if store.state.offSeason && !store.state.recovering && store.currentCheckin?.finished != true {
                    CoachPanel(title: "Comeback challenge") {
                        Text("Missed a day? No stacked punishment reps. Restart with a small, manageable commitment.")
                            .font(.subheadline).foregroundStyle(CoachStyle.muted)
                        MainButton(title: "Start My Comeback", icon: "arrow.uturn.forward.circle.fill") {
                            store.comebackChallenge()
                            selection = 1
                        }
                    }
                }
                CoachPanel(title: "Career progress") {
                    HStack { Image(systemName: "trophy.fill").foregroundStyle(CoachStyle.gold); Text(store.level).font(.title3.bold()) }
                    Text("The goal is consistent technique, grades, and healthy recovery — not unlimited exercise.").font(.caption).foregroundStyle(CoachStyle.muted)
                }
            }.padding(16)
        }
        .background(CoachStyle.navy).toolbar(.hidden, for: .navigationBar)
    }
    private var formattedTime: String {
        let format = DateFormatter(); format.dateStyle = .none; format.timeStyle = .short
        let day = Calendar.current.startOfDay(for: Date())
        let d = Calendar.current.date(byAdding: .minute, value: store.state.workoutHour * 60 + store.state.workoutMinute, to: day) ?? Date()
        return format.string(from: d)
    }
    private func statCard(_ title: String, _ value: String, _ icon: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: icon).font(.caption2.bold()).foregroundStyle(CoachStyle.gold)
            Text(value).font(.system(size: 27, weight: .black)).foregroundStyle(.white)
        }.padding(16).frame(maxWidth: .infinity, alignment: .leading).background(CoachStyle.panel, in: RoundedRectangle(cornerRadius: 16))
    }
}
