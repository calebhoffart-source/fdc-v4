import SwiftUI

struct CoachChatScreen: View {
    @EnvironmentObject private var store: CoachStore
    @EnvironmentObject private var notices: CoachNotifications
    @StateObject private var speech = CoachSpeech()
    @State private var input = ""
    @State private var sending = false
    @State private var showRequest = false
    @State private var pendingReschedule = false
    @FocusState private var typing: Bool
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "shield.fill").font(.title2).foregroundStyle(CoachStyle.gold)
                VStack(alignment: .leading) {
                    Text("COACH").font(.headline.bold()).foregroundStyle(.white)
                    Text("Offline rules • optional on-device model").font(.caption2).foregroundStyle(CoachStyle.muted)
                }
                Spacer()
                if store.state.voiceEnabled {
                    Button { speech.stopSpeaking() } label: { Image(systemName: "speaker.slash.fill") }.tint(CoachStyle.gold)
                }
            }.padding()
            ScrollViewReader { reader in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 11) {
                        ForEach(store.state.conversations) { line in
                            HStack {
                                if !line.fromCoach { Spacer(minLength: 55) }
                                Text(line.text)
                                    .font(.subheadline).fontWeight(line.fromCoach ? .bold : .regular)
                                    .padding(13)
                                    .background(line.fromCoach ? CoachStyle.panel : CoachStyle.blue.opacity(0.55), in: RoundedRectangle(cornerRadius: 15))
                                    .foregroundStyle(.white)
                                if line.fromCoach { Spacer(minLength: 55) }
                            }.id(line.id)
                        }
                    }.padding(15)
                }
                .onChange(of: store.state.conversations.count) { _, _ in
                    if let last = store.state.conversations.last { withAnimation { reader.scrollTo(last.id, anchor: .bottom) } }
                }
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack {
                    quick("Request more time")
                    quick("I need to reschedule")
                    quick("No dummy today")
                    quick("Travel mode")
                    quick("Coach stop training for the season")
                    quick("Coach start offseason training")
                }.padding(.horizontal, 12).padding(.vertical, 7)
            }
            HStack(spacing: 10) {
                TextField("Ask Coach or make a request…", text: $input, axis: .vertical)
                    .lineLimit(1...3).padding(10)
                    .background(CoachStyle.panel, in: RoundedRectangle(cornerRadius: 13))
                    .focused($typing)
                Button {
                    if speech.listening { speech.stop(); input = speech.recognized }
                    else { speech.start() }
                } label: { Image(systemName: speech.listening ? "waveform" : "mic.fill") }
                    .tint(CoachStyle.gold)
                Button { send() } label: { Image(systemName: "arrow.up.circle.fill").font(.title2) }
                    .tint(CoachStyle.gold).disabled(input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || sending)
            }.padding(12)
            if let issue = speech.issue { Text(issue).font(.caption).foregroundStyle(.orange).padding(.horizontal) }
        }
        .background(CoachStyle.navy).toolbar(.hidden, for: .navigationBar)
        .onDisappear { speech.stop(); speech.stopSpeaking() }
        .sheet(isPresented: $showRequest) { CoachTimeRequestScreen() }
    }
    private func quick(_ title: String) -> some View {
        Button(title) { input = title; send() }
            .font(.caption.bold()).buttonStyle(.bordered).tint(CoachStyle.gold)
    }
    private func send() {
        let prompt = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else { return }
        input = ""; typing = false
        store.userMessage(prompt)
        let normalized = prompt.lowercased()
        var response: String
        if pendingReschedule {
            pendingReschedule = false
            if normalized.contains("school") || normalized.contains("homework") || normalized.contains("practice") || normalized.contains("sleep") || normalized.contains("family") || normalized.contains("rest") || normalized.contains("injur") || normalized.contains("sick") || normalized.contains("exhausted") {
                store.excuseToday(prompt)
                response = "APPROVED. \(prompt.uppercased()). TAKE CARE OF THAT FIRST."
            } else {
                response = "I HEAR YOU. TRY A TWO-MINUTE STARTER AND SEE HOW YOU FEEL. IF YOU NEED REST, SCHOOL TIME, OR RECOVERY, TELL ME AND WE'LL ADJUST."
            }
        } else if normalized.contains("stop training") || normalized.contains("pause season") || normalized.contains("football season start") {
            store.setSeason(false); response = "SEASON PAUSE SET. WORKOUT REMINDERS OFF. YOUR RECORDS ARE KEPT."
        } else if normalized.contains("start offseason") || normalized.contains("resume offseason") {
            store.setSeason(true); response = "OFFSEASON ENABLED. WE'LL PICK UP WITH SAFE, CALIBRATED TRAINING."
        } else if normalized.contains("no dummy") {
            store.state.noDummy = true
            response = "NO-DUMMY MODE ON. FOCUS ON SAFE FOOTWORK AND STANCE."
        } else if normalized.contains("dummy available") {
            store.state.noDummy = false
            response = "DUMMY MODE AVAILABLE AGAIN. QUALITY FIRST."
        } else if normalized.contains("injur") || normalized.contains("sick") || normalized.contains("exhausted") || normalized.contains("need recovery") {
            store.recovery(prompt)
            response = "RECOVERY IS APPROVED. NO PUNISHMENT. LET AN ADULT OR A CLINICIAN KNOW IF YOU'RE HURT."
        } else if normalized.contains("finish recovery") || normalized.contains("end recovery") {
            store.resumeRecovery()
            response = "RECOVERY MODE CLEARED. RETURN GRADUALLY."
        } else if normalized.contains("reschedul") || normalized.contains("skip today") {
            pendingReschedule = true
            response = "WHAT'S STOPPING YOU TODAY? SCHOOL, FOOTBALL PRACTICE, INJURY, REST, FAMILY, OR SOMETHING ELSE? TELL ME SO I CAN RESPOND FAIRLY."
        } else if normalized.contains("more time") || normalized.contains("request time") {
            showRequest = true
            response = "REQUEST FORM OPEN. EARNED TIME USES YOUR BANK; TRAVEL BORROWING IS SEPARATE. IOS APP LIMITS ARE UNCHANGED."
        } else if normalized.contains("travel mode") {
            showRequest = true
            response = "TRAVEL REQUEST OPEN. USE THE TRAVEL LOAN ONLY WHEN YOU CANNOT ACCESS YOUR TRAINING SETUP."
        } else {
            response = CoachDialogue.ruleReply(prompt, state: store.state)
        }
        store.coach(response)
        notices.schedule(store)
        if store.state.voiceEnabled { speech.say(response) }
        sending = true
        Task {
            let enhanced = await CoachDialogue.onDeviceReply(prompt, state: store.state)
            // Local AI is optional and is only a different message. It never makes policy decisions.
            if let enhanced, !enhanced.isEmpty, !normalized.contains("season"), !normalized.contains("recovery") {
                store.coach(enhanced)
                if store.state.voiceEnabled { speech.say(enhanced) }
            }
            sending = false
        }
    }
}

struct MoreScreen: View {
    @EnvironmentObject private var store: CoachStore
    @EnvironmentObject private var notices: CoachNotifications
    @State private var loanAmount = 30
    @State private var spendAmount = 10
    @State private var showLoanConfirm = false
    @State private var showGrades = false
    @State private var showFocus = false
    @State private var showCalibration = false
    @State private var showSetup = false
    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Heading(title: "PLAYBOOK", subtitle: "Requests, grades, loans, and settings")
                CoachPanel(title: "Earned screen time • honor bank") {
                    Text("\(store.state.earnedMinutes) earned minutes").font(.system(size: 27, weight: .black)).foregroundStyle(CoachStyle.gold)
                    Text("\(store.state.travelDebt) travel debt minutes • \(store.state.borrowedMinutes) minutes borrowed overall")
                        .font(.caption).foregroundStyle(CoachStyle.muted)
                    Stepper("Mark \(spendAmount) minutes spent", value: $spendAmount, in: 5...60, step: 5)
                    MainButton(title: "Record Spent Earned Minutes", icon: "clock") { store.spendBank(spendAmount) }
                        .disabled(store.state.earnedMinutes < spendAmount)
                    Text("This ledger cannot measure usage, impose restrictions, or unlock installed apps. Use iOS Screen Time/App Limits separately.")
                        .font(.caption).foregroundStyle(CoachStyle.muted)
                }
                CoachPanel(title: "Travel screen-time loan") {
                    Text("For travel or no access to your training setup. Each 10 borrowed minutes adds 1 minute of repayment from future earnings.")
                        .font(.subheadline)
                    Stepper("Borrow \(loanAmount) minutes", value: $loanAmount, in: 10...120, step: 10)
                    MainButton(title: "Request Travel Loan", icon: "airplane") { showLoanConfirm = true }
                    Text("Honor-based only; no automatic location checks and no physical training in vehicles.")
                        .font(.caption).foregroundStyle(CoachStyle.muted)
                }
                CoachPanel(title: "School and focus") {
                    MainButton(title: "Grade Checks and Study", icon: "books.vertical.fill", color: CoachStyle.blue) { showGrades = true }
                    MainButton(title: "Phone-Free Focus / Lock-In", icon: "moon.fill") { showFocus = true }
                    Text("Study minutes owed: \(store.state.studyMinutesDue)").font(.subheadline)
                }
                CoachPanel(title: "Season, recovery and settings") {
                    Toggle("Offseason Training Enabled", isOn: Binding(get: { store.state.offSeason }, set: { store.setSeason($0); notices.schedule(store) })).tint(CoachStyle.gold)
                    Toggle("Recovery Mode", isOn: Binding(get: { store.state.recovering }, set: { $0 ? store.recovery("Rest day") : store.resumeRecovery(); notices.schedule(store) })).tint(CoachStyle.gold)
                    Toggle("No Dummy Available", isOn: Binding(get: { store.state.noDummy }, set: { store.state.noDummy = $0 })).tint(CoachStyle.gold)
                    Toggle("Coach speaks out loud", isOn: Binding(get: { store.state.voiceEnabled }, set: { store.state.voiceEnabled = $0 })).tint(CoachStyle.gold)
                    Toggle("Persistent workout reminders (max 5)", isOn: Binding(get: { store.state.strictReminders }, set: { store.state.strictReminders = $0; notices.schedule(store) })).tint(CoachStyle.gold)
                    HStack {
                        Text("Workout hour")
                        Spacer()
                        Picker("Hour", selection: Binding(get: { store.state.workoutHour }, set: { store.state.workoutHour = $0; notices.schedule(store) })) {
                            ForEach(7..<21, id: \.self) { Text(String(format: "%02d", $0)).tag($0) }
                        }.pickerStyle(.menu).tint(CoachStyle.gold)
                        Picker("Minute", selection: Binding(get: { store.state.workoutMinute }, set: { store.state.workoutMinute = $0; notices.schedule(store) })) {
                            ForEach([0,15,30,45], id: \.self) { Text(String(format: "%02d", $0)).tag($0) }
                        }.pickerStyle(.menu).tint(CoachStyle.gold)
                    }
                    MainButton(title: "Enable Notifications", icon: "bell.badge.fill") { Task { await notices.ask(store) } }
                    Text("Notifications: \(notices.permissionLabel) • default quiet hours 9 PM–7 AM.")
                        .font(.caption).foregroundStyle(CoachStyle.muted)
                    MainButton(title: "Recalibrate All 3 Drills", icon: "camera.viewfinder", color: CoachStyle.blue) { showCalibration = true }
                }
                CoachPanel(title: "Accountability without paid Apple APIs") {
                    Text("Free iPhone setup: Settings → Screen Time → App Limits. Optionally ask a parent to set a Screen Time passcode. Separately, Settings → Shortcuts → Automation → App can trigger a reminder when selected apps open.")
                        .font(.subheadline)
                    Text("App limits and Shortcuts do not synchronize with this app's earned bank. We cannot access usage automatically or prevent leaving Lock-In Mode.")
                        .font(.caption).foregroundStyle(CoachStyle.muted)
                }
            }.padding(16)
        }.background(CoachStyle.navy).toolbar(.hidden, for: .navigationBar)
        .alert("Travel Loan", isPresented: $showLoanConfirm) {
            Button("Borrow \(loanAmount) min") { store.borrowForTravel(loanAmount) }
            Button("Cancel", role: .cancel) {}
        } message: { Text("Are you traveling or unable to access your training equipment? This logs \(Int(ceil(Double(loanAmount) / 10))) minutes of future-credit repayment; it won't unlock other apps.") }
        .sheet(isPresented: $showGrades) { NavigationStack { GradebookScreen() } }
        .sheet(isPresented: $showFocus) { NavigationStack { FocusDriveScreen() } }
        .sheet(isPresented: $showCalibration) { CalibrationWizard() }
    }
}


struct CoachTimeRequestScreen: View {
    @EnvironmentObject private var store: CoachStore
    @Environment(\.dismiss) private var dismiss
    @State private var amount = 10
    @State private var travel = false
    var body: some View {
        NavigationStack {
            ZStack { CoachStyle.navy.ignoresSafeArea()
                VStack(alignment: .leading, spacing: 20) {
                    Heading(title: "COACH REQUEST", subtitle: "A real request form that changes your local ledger")
                    Toggle("Travel loan instead of earned minutes", isOn: $travel).tint(CoachStyle.gold)
                    Stepper("Request \(amount) minutes", value: $amount, in: 5...60, step: 5)
                    Text(travel ? "Repayment: \(AccountabilityRules.travelLoanRepayment(borrowedMinutes: amount)) future earned minutes." : "Available earned balance: \(store.state.earnedMinutes) minutes.")
                        .font(.subheadline).foregroundStyle(CoachStyle.muted)
                    MainButton(title: travel ? "Log Travel Loan" : "Approve from Earned Bank", icon: "checkmark.circle.fill") {
                        if travel { store.borrowForTravel(amount) }
                        else { store.spendBank(amount) }
                        dismiss()
                    }.disabled(!travel && store.state.earnedMinutes < amount)
                    Text("This tracks voluntary requests. It cannot override Apple's actual Screen Time restrictions.")
                        .font(.caption).foregroundStyle(CoachStyle.muted)
                    Spacer()
                }.padding(20)
            }
            .navigationTitle("Request")
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } } }
        }
    }
}
