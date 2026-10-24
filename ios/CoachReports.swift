import SwiftUI
import PhotosUI

struct ReportScreen: View {
    @EnvironmentObject private var store: CoachStore
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var selectedDate = Calendar.current.date(byAdding: .day, value: -1, to: Date()) ?? Date()
    @State private var scanned: [String] = []
    @State private var scanning = false
    @State private var hours = ""
    @State private var minutes = ""
    @State private var screenshotAttached = false
    @State private var confirmation = false
    @State private var reportMessage = ""
    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Heading(title: "SCREEN TIME AUDIT", subtitle: "Yesterday's use determines today's accountability goal")
                CoachPanel(title: "Upload your iPhone report") {
                    Text("Open Settings → Screen Time → See All App & Website Activity → Day. Select YESTERDAY. Screenshot your report.")
                        .font(.subheadline)
                    DatePicker("Usage date", selection: $selectedDate, in: ...Date(), displayedComponents: .date)
                        .datePickerStyle(.compact).tint(CoachStyle.gold)
                    PhotosPicker(selection: $selectedPhoto, matching: .images) {
                        Label(screenshotAttached ? "Screenshot selected ✓" : "Choose Screen Time Screenshot", systemImage: "photo")
                            .font(.headline).foregroundStyle(CoachStyle.gold)
                    }
                    if scanning { ProgressView("Reading screenshot on this iPhone…") }
                    if !scanned.isEmpty {
                        Text("OCR TEXT — VERIFY DATE AND RECREATIONAL USAGE").font(.caption.bold()).foregroundStyle(CoachStyle.gold)
                        Text(scanned.prefix(18).joined(separator: " • "))
                            .font(.caption).foregroundStyle(CoachStyle.muted).textSelection(.enabled)
                    }
                    Text("Enter recreational minutes, excluding school/homework usage. OCR may read Daily Average instead of yesterday. Check the number yourself.")
                        .font(.caption).foregroundStyle(CoachStyle.muted)
                    HStack {
                        TextField("Hours", text: $hours).keyboardType(.numberPad).textFieldStyle(.roundedBorder)
                        Text("h")
                        TextField("Minutes", text: $minutes).keyboardType(.numberPad).textFieldStyle(.roundedBorder)
                        Text("m")
                    }
                    Toggle("I checked the day and number on my screenshot", isOn: $confirmation).tint(CoachStyle.gold)
                        .font(.subheadline)
                    MainButton(title: "Submit Daily Audit", icon: "checkmark.seal.fill") { saveReport() }
                        .disabled(!confirmation || !screenshotAttached)
                    if !reportMessage.isEmpty { Text(reportMessage).font(.caption).foregroundStyle(CoachStyle.muted) }
                }
                CoachPanel(title: "Your screen time ledger") {
                    if store.state.reports.isEmpty { Text("Your reports will appear here.").foregroundStyle(CoachStyle.muted) }
                    ForEach(store.state.reports.prefix(14)) { record in
                        HStack {
                            Text(record.day).font(.subheadline)
                            Spacer()
                            Text("\(record.recreationalMinutes) min → \(record.recreationalMinutes) target reps")
                                .font(.caption.bold()).foregroundStyle(CoachStyle.gold)
                        }
                        Divider().overlay(.white.opacity(0.08))
                    }
                }
                CoachPanel(title: "Weekly Accountability Report") {
                    Text(store.weeklySummary).font(.headline)
                    Text("Coach Trust: \(store.weekTrustLabel). Trust rewards checking in and honesty; it is not a judgment of you as a person.")
                        .font(.caption).foregroundStyle(CoachStyle.muted)
                }
                CoachPanel(title: "Important limitation") {
                    Text("Apple doesn't let this free build read other apps' Screen Time directly. Screenshots must be selected and verified by you. A target does not authorize excessive physical exercise. The app can't stop you from opening TikTok, games, or other apps.")
                        .font(.caption).foregroundStyle(CoachStyle.muted)
                }
            }.padding(16)
        }
        .background(CoachStyle.navy).toolbar(.hidden, for: .navigationBar)
        .onChange(of: selectedPhoto) { _, item in
            guard let item else { return }
            scanning = true; screenshotAttached = false; confirmation = false
            Task {
                if let bytes = try? await item.loadTransferable(type: Data.self) {
                    scanned = await TextScanner.scan(bytes)
                    if let guess = TextScanner.likelyMinutes(scanned) {
                        hours = String(guess/60); minutes = String(guess%60)
                    }
                    screenshotAttached = true
                } else { reportMessage = "Unable to load image. Pick a screenshot from Photos." }
                scanning = false
            }
        }
    }
    private func saveReport() {
        let h = Int(hours) ?? -1
        let m = Int(minutes) ?? -1
        guard h >= 0 && h <= 24 && m >= 0 && m < 60 && h*60 + m <= 1440 else {
            reportMessage = "Enter valid hours and minutes."
            return
        }
        let day = CoachDate.key(selectedDate)
        store.addReport(day: day, minutes: h*60 + m, reviewedOCR: true)
        reportMessage = "\(day) saved. If this is yesterday's date, it now sets today's target."
        confirmation = false
        selectedPhoto = nil
        screenshotAttached = false
        scanned = []
    }
}

struct GradebookScreen: View {
    @EnvironmentObject private var store: CoachStore
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var lines: [String] = []
    @State private var subject = ""
    @State private var percent = ""
    @State private var period = "Current grading period"
    @State private var confirmed = false
    @State private var screenshotAttached = false
    @State private var message = ""
    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Heading(title: "GRADE CHECK", subtitle: "Current grades and study priorities")
                CoachPanel(title: "Review your gradebook") {
                    PhotosPicker(selection: $selectedPhoto, matching: .images) {
                        Label("Choose Gradebook Screenshot", systemImage: "doc.text.viewfinder").foregroundStyle(CoachStyle.gold)
                    }
                    if !lines.isEmpty { Text(lines.prefix(25).joined(separator: " • ")).font(.caption).foregroundStyle(CoachStyle.muted).textSelection(.enabled) }
                    TextField("Subject (e.g., Math)", text: $subject).textFieldStyle(.roundedBorder)
                    TextField("Grade 0–100", text: $percent).keyboardType(.numberPad).textFieldStyle(.roundedBorder)
                    TextField("Grading period", text: $period).textFieldStyle(.roundedBorder)
                    Toggle("I verified this grade", isOn: $confirmed).tint(CoachStyle.gold)
                    MainButton(title: "Save Grade", icon: "checkmark") {
                        if let grade = Int(percent), (0...100).contains(grade) && confirmed {
                            store.addGrade(subject: subject, percent: grade, period: period, ocr: screenshotAttached)
                            subject = ""; percent = ""; confirmed = false; message = "Grade saved."
                        } else { message = "Enter a subject, a grade 0–100 and confirm it." }
                    }
                    Text(message).font(.caption).foregroundStyle(CoachStyle.muted)
                    Text("Screenshots are scanned locally, not uploaded. The app can't automatically log into your school gradebook.")
                        .font(.caption).foregroundStyle(CoachStyle.muted)
                }
                CoachPanel(title: "Study debt — not exercise punishment") {
                    Text("\(store.state.studyMinutesDue) study minutes").font(.title2.bold()).foregroundStyle(CoachStyle.gold)
                    HStack {
                        Button("Log 10 min study") { store.recordStudy(10) }.buttonStyle(.bordered).tint(CoachStyle.gold)
                        Button("Log 20 min study") { store.recordStudy(20) }.buttonStyle(.bordered).tint(CoachStyle.gold)
                    }
                    Text("Below 70% adds a manageable study block. It never adds mandatory physical punishment or overrides medical advice.")
                        .font(.caption).foregroundStyle(CoachStyle.muted)
                }
                CoachPanel(title: "Grade history") {
                    ForEach(store.state.grades.prefix(20)) { grade in
                        HStack {
                            VStack(alignment: .leading) { Text(grade.subject).bold(); Text(grade.period).font(.caption).foregroundStyle(CoachStyle.muted) }
                            Spacer()
                            Text("\(grade.percent)%").font(.title3.bold()).foregroundStyle(grade.percent >= 70 ? .green : .orange)
                        }
                        Divider()
                    }
                }
            }.padding(16)
        }.background(CoachStyle.navy)
            .navigationTitle("Grades")
            .onChange(of: selectedPhoto) { _, image in
                guard let image else { return }
                Task {
                    if let data = try? await image.loadTransferable(type: Data.self) {
                        lines = await TextScanner.scan(data)
                        screenshotAttached = true
                    } else { message = "Couldn't load image." }
                }
            }
    }
}
