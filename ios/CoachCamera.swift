import SwiftUI
import AVFoundation
import Vision
import CoreImage
import AVKit

// Camera motion analysis: knee-angle cycle detector based on Vision human body joints.
// Distinct calibration profiles are saved for each drill. This DOES NOT confirm
// dummy contact, tackle safety, pad level, hand placement or correct football technique.
final class CoachPoseCamera: NSObject, ObservableObject, AVCaptureVideoDataOutputSampleBufferDelegate, AVCaptureFileOutputRecordingDelegate {
    @Published var status = "PLACE YOUR WHOLE BODY IN FRAME"
    @Published var count = 0
    @Published var bodyVisibility = 0.0
    @Published var isRecording = false
    @Published var error: String?
    @Published var samples: [(Double, Double)] = []
    @Published var lastFilmName: String?

    let session = AVCaptureSession()
    private let videoOutput = AVCaptureVideoDataOutput()
    private let movieOutput = AVCaptureMovieFileOutput()
    private let cameraQueue = DispatchQueue(label: "fdc.v4.camera.capture")
    private let framesQueue = DispatchQueue(label: "fdc.v4.camera.vision")
    private var lastFrame = Date.distantPast
    private var lastAccepted = Date.distantPast
    private var stanceMin = 180.0
    private var extensionMax = 0.0
    private var phase = 0
    private var stableStance = 0
    private var stableDrive = 0
    private let kind: DrillKind
    private let profile: PoseProfile?
    private var initialized = false

    init(kind: DrillKind, profile: PoseProfile?) {
        self.kind = kind
        self.profile = profile
        super.init()
    }

    func start() {
        AVCaptureDevice.requestAccess(for: .video) { granted in
            if !granted { DispatchQueue.main.async { self.error = "Enable Camera in Settings → Fourth Down Coach." }; return }
            self.cameraQueue.async {
                if !self.initialized {
                    self.session.beginConfiguration()
                    self.session.sessionPreset = .high
                    guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
                          let input = try? AVCaptureDeviceInput(device: camera), self.session.canAddInput(input) else {
                        self.session.commitConfiguration()
                        DispatchQueue.main.async { self.error = "Unable to access the back camera." }
                        return
                    }
                    self.session.addInput(input)
                    self.videoOutput.alwaysDiscardsLateVideoFrames = true
                    self.videoOutput.setSampleBufferDelegate(self, queue: self.framesQueue)
                    if self.session.canAddOutput(self.videoOutput) { self.session.addOutput(self.videoOutput) }
                    if self.session.canAddOutput(self.movieOutput) { self.session.addOutput(self.movieOutput) }
                    self.session.commitConfiguration()
                    self.initialized = true
                }
                if !self.session.isRunning { self.session.startRunning() }
            }
        }
    }
    func stop() {
        cameraQueue.async {
            if self.movieOutput.isRecording { self.movieOutput.stopRecording() }
            if self.session.isRunning { self.session.stopRunning() }
        }
    }
    func startFilm() {
        cameraQueue.async {
            guard self.session.isRunning && !self.movieOutput.isRecording,
                  self.session.outputs.contains(where: { $0 === self.movieOutput }) else {
                DispatchQueue.main.async { self.error = "Film recording unavailable on this device." }
                return
            }
            let url = Self.filmFolder().appendingPathComponent(UUID().uuidString + ".mov")
            self.movieOutput.startRecording(to: url, recordingDelegate: self)
            DispatchQueue.main.async { self.isRecording = true }
        }
    }
    func stopFilm() {
        cameraQueue.async { if self.movieOutput.isRecording { self.movieOutput.stopRecording() } }
    }
    private static func filmFolder() -> URL {
        let root = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let folder = root.appendingPathComponent("Films", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }
    static func filmURL(_ name: String) -> URL { filmFolder().appendingPathComponent(name) }
    func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL, from connections: [AVCaptureConnection], error: Error?) {
        DispatchQueue.main.async {
            self.isRecording = false
            if let error { self.error = "Film could not be saved: \(error.localizedDescription)" }
            else { self.lastFilmName = outputFileURL.lastPathComponent; self.status = "FILM SAVED LOCALLY" }
        }
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        let now = Date()
        guard now.timeIntervalSince(lastFrame) > 0.16,
              let pixels = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        lastFrame = now
        let req = VNDetectHumanBodyPoseRequest()
        do {
            try VNImageRequestHandler(cvPixelBuffer: pixels, orientation: .right, options: [:]).perform([req])
            guard let observation = req.results?.first else {
                DispatchQueue.main.async { self.status = "NO PERSON DETECTED. STEP INTO FRAME."; self.bodyVisibility = 0 }
                return
            }
            let required: [VNHumanBodyPoseObservation.JointName] = [.leftHip, .leftKnee, .leftAnkle, .rightHip, .rightKnee, .rightAnkle]
            let quality = Double(required.filter { joint(observation, $0) != nil }.count) / Double(required.count)
            DispatchQueue.main.async { self.bodyVisibility = quality }
            guard quality >= 0.66 else {
                DispatchQueue.main.async { self.status = "SHOW HIPS, KNEES, AND ANKLES. MOVE BACK." }
                return
            }
            let values: [Double?] = [kneeAngle(observation, left: true), kneeAngle(observation, left: false)]
            let angles = values.compactMap { $0 }
            guard !angles.isEmpty else { return }
            let angle = angles.reduce(0, +) / Double(angles.count)
            let stanceThreshold = min(150.0, (profile?.stanceAngle ?? 145) + 5)
            let driveThreshold = max(158.0, (profile?.extensionAngle ?? 163) - 5)
            if angle <= stanceThreshold {
                stableStance += 1; stableDrive = 0
                stanceMin = min(stanceMin, angle)
                if stableStance >= 2 && phase == 0 { phase = 1 }
                if stableStance >= 2 && phase == 2 && now.timeIntervalSince(lastAccepted) >= 1.6 {
                    let minAngle = stanceMin
                    let maxAngle = extensionMax
                    phase = 1
                    lastAccepted = now
                    stanceMin = angle
                    extensionMax = 0
                    DispatchQueue.main.async {
                        self.count += 1
                        self.samples.append((minAngle, maxAngle))
                        self.status = "FULL STANCE → DRIVE → RESET CYCLE DETECTED"
                    }
                } else if phase == 1 {
                    DispatchQueue.main.async { self.status = "STANCE DETECTED. EXTEND, THEN RESET." }
                }
            } else if angle >= driveThreshold {
                stableDrive += 1; stableStance = 0
                extensionMax = max(extensionMax, angle)
                if stableDrive >= 2 && phase == 1 && extensionMax - stanceMin >= 12 {
                    phase = 2
                    DispatchQueue.main.async { self.status = "DRIVE DETECTED. RETURN TO STANCE." }
                }
            } else {
                stableStance = 0; stableDrive = 0
            }
        } catch {
            DispatchQueue.main.async { self.status = "VISION POSE DETECTION FAILED" }
        }
    }
    private func joint(_ pose: VNHumanBodyPoseObservation, _ name: VNHumanBodyPoseObservation.JointName) -> VNRecognizedPoint? {
        guard let p = try? pose.recognizedPoint(name), p.confidence >= 0.45 else { return nil }
        return p
    }
    private func kneeAngle(_ pose: VNHumanBodyPoseObservation, left: Bool) -> Double? {
        let hip: VNHumanBodyPoseObservation.JointName = left ? .leftHip : .rightHip
        let knee: VNHumanBodyPoseObservation.JointName = left ? .leftKnee : .rightKnee
        let ankle: VNHumanBodyPoseObservation.JointName = left ? .leftAnkle : .rightAnkle
        guard let a = joint(pose, hip), let b = joint(pose, knee), let c = joint(pose, ankle) else { return nil }
        let v1 = CGVector(dx: a.location.x-b.location.x, dy: a.location.y-b.location.y)
        let v2 = CGVector(dx: c.location.x-b.location.x, dy: c.location.y-b.location.y)
        let mag = hypot(v1.dx, v1.dy) * hypot(v2.dx, v2.dy)
        guard mag > 0.000001 else { return nil }
        let cosAngle = (v1.dx*v2.dx + v1.dy*v2.dy) / mag
        return acos(max(-1,min(1,cosAngle))) * 180 / .pi
    }
}

final class CameraSurface: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
    var preview: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
}
struct LiveCameraPreview: UIViewRepresentable {
    let session: AVCaptureSession
    func makeUIView(context: Context) -> CameraSurface {
        let view = CameraSurface()
        view.preview.session = session
        view.preview.videoGravity = .resizeAspectFill
        return view
    }
    func updateUIView(_ uiView: CameraSurface, context: Context) {}
}

struct PoseCameraScreen: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: CoachStore
    @StateObject private var camera: CoachPoseCamera
    let kind: DrillKind
    let calibrating: Bool
    let onCalibrated: (() -> Void)?
    @State private var lastCredited = 0
    @State private var savedFilm: String?
    @StateObject private var coachVoice = CoachSpeech()

    init(kind: DrillKind, calibrating: Bool = false, profile: PoseProfile? = nil, onCalibrated: (() -> Void)? = nil) {
        self.kind = kind
        self.calibrating = calibrating
        self.onCalibrated = onCalibrated
        _camera = StateObject(wrappedValue: CoachPoseCamera(kind: kind, profile: profile))
    }
    var body: some View {
        ZStack {
            CoachStyle.navy.ignoresSafeArea()
            VStack(spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(calibrating ? "CALIBRATION" : "VISION CAMERA").font(.caption.bold()).foregroundStyle(CoachStyle.gold)
                        Text(kind.rawValue).font(.title2.bold()).foregroundStyle(.white)
                    }
                    Spacer()
                    Button("Done") { dismiss() }.buttonStyle(.borderedProminent).tint(CoachStyle.gold).foregroundStyle(.black)
                }.padding(.horizontal)
                ZStack(alignment: .bottom) {
                    LiveCameraPreview(session: camera.session)
                    Text(camera.status)
                        .font(.footnote.bold()).multilineTextAlignment(.center)
                        .padding(12).frame(maxWidth: .infinity)
                        .background(.black.opacity(0.8)).foregroundStyle(.white)
                }.clipShape(RoundedRectangle(cornerRadius: 17)).frame(maxHeight: .infinity).padding(.horizontal, 12)
                HStack {
                    VStack(alignment: .leading) {
                        Text(calibrating ? "CALIBRATION REPS" : "DETECTED REPS").font(.caption2).foregroundStyle(.white.opacity(0.6))
                        Text("\(calibrating ? min(camera.count, 3) : camera.count)" + (calibrating ? " / 3" : ""))
                            .font(.system(size: 38, weight: .black)).foregroundStyle(CoachStyle.gold)
                    }
                    Spacer()
                    VStack(alignment: .trailing) {
                        Text("JOINTS VISIBLE").font(.caption2).foregroundStyle(.white.opacity(0.6))
                        Text("\(Int(camera.bodyVisibility * 100))%").font(.title3.bold()).foregroundStyle(.white)
                    }
                }.padding(.horizontal, 20)
                if !calibrating {
                    HStack {
                        Button(camera.isRecording ? "Stop Film" : "Record Film") {
                            camera.isRecording ? camera.stopFilm() : camera.startFilm()
                        }.buttonStyle(.bordered).tint(CoachStyle.gold)
                        Spacer()
                        Text("Movement cycles: \(camera.count)")
                            .font(.caption).foregroundStyle(.white.opacity(0.8))
                    }.padding(.horizontal)
                }
                if let error = camera.error { Text(error).font(.caption).foregroundStyle(.red).padding(.horizontal) }
                Text("Motion detection uses visible joints and is experimental. It cannot verify dummy impact, safe tackling, or correct technique. Never train unsupervised on contact drills.")
                    .font(.caption2).foregroundStyle(.white.opacity(0.7)).padding(.horizontal)
            }.padding(.vertical, 10)
        }
        .onAppear { camera.start() }
        .onDisappear { camera.stop(); coachVoice.stopSpeaking() }
        .onChange(of: camera.count) { _, newCount in
            if calibrating {
                if newCount >= 3 && camera.samples.count >= 3 {
                    let first = Array(camera.samples.prefix(3))
                    let low = first.reduce(0.0) { $0 + $1.0 } / Double(first.count)
                    let high = first.reduce(0.0) { $0 + $1.1 } / Double(first.count)
                    store.saveCalibration(kind, min: low, max: high)
                    camera.stop()
                    onCalibrated?()
                    dismiss()
                }
            } else {
                guard newCount > lastCredited else { return }
                for _ in lastCredited..<newCount { _ = store.recordRep(kind, source: "camera") }
                lastCredited = newCount
                if store.state.voiceEnabled { coachVoice.say("GOOD DRIVE. RESET. NEXT REP.") }
            }
        }
        .onChange(of: camera.lastFilmName) { _, filename in
            if let filename { store.addFilm(kind, filename: filename) }
        }
    }
}

struct FilmPlayerScreen: View {
    @EnvironmentObject private var store: CoachStore
    let clip: FilmClip
    @State private var appealed = false
    var body: some View {
        VStack(spacing: 12) {
            VideoPlayer(player: AVPlayer(url: CoachPoseCamera.filmURL(clip.fileName)))
                .frame(maxHeight: .infinity)
                .background(.black)
            Text("Review the movement yourself. Camera pose detection cannot judge safe technique or prove contact.")
                .font(.caption).foregroundStyle(CoachStyle.muted).padding(.horizontal)
            MainButton(title: appealed ? "Manual Appeal Already Logged" : "Challenge a Missed Rep (Manual Review)", icon: "arrow.uturn.backward.circle.fill") {
                if store.recordRep(clip.drill, source: "manual") {
                    appealed = true
                    store.coach("FILM CHALLENGE SELF-REVIEWED. 1 MANUAL REP LOGGED, NOT AI VERIFIED.")
                }
            }.disabled(appealed || !store.isSafeToTrain || store.todayManual >= CoachStore.dailySelfReportCap)
                .padding(.horizontal)
        }
        .background(CoachStyle.navy)
        .navigationTitle(clip.drill.rawValue)
        .navigationBarTitleDisplayMode(.inline)
    }
}
