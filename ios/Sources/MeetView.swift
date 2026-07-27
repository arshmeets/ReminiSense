import SwiftUI
import UIKit

// MARK: - Result model

/// One pass of the Meet loop, rendered in-app.
struct MeetResult: Identifiable {
    enum Kind {
        case recognised
        case newFace
        case merged
        case guidance
        case failed
    }

    let id = UUID()
    let kind: Kind
    let name: String
    let subhead: String
    let headline: String
    let lines: [String]
    let topics: [String]
    let followups: [String]
    let transcript: String
    let placeholder: Bool
    let date = Date()

    var badge: String {
        switch kind {
        case .recognised: return "KNOWN"
        case .newFace: return "NEW FACE"
        case .merged: return "FACE LINKED"
        case .guidance: return "TRY AGAIN"
        case .failed: return "FAILED"
        }
    }

    var badgeTint: Color {
        switch kind {
        case .recognised, .merged: return .rcAccent
        case .newFace: return .rcAccent
        case .guidance, .failed: return .rcAlert
        }
    }
}

// MARK: - Engine

/// The one-tap loop: frame → speech → recognise → (auto-enrol on a miss) →
/// ingest → lens + ear + app.
///
/// It lives outside the view so auto-repeat survives a tab switch and so the
/// ordering guarantees stay in one place. The ordering matters: the camera runs
/// to completion BEFORE the microphone opens, which is what stops the two
/// contending for the audio route.
@MainActor
final class MeetEngine: ObservableObject {
    static let shared = MeetEngine()

    enum Phase: Equatable {
        case idle
        case framing
        case listening
        case thinking

        var isBusy: Bool { self != .idle }
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var statusLine = "Tap once. Recall does the rest."
    @Published private(set) var results: [MeetResult] = []
    @Published private(set) var lastCapture: UIImage?
    @Published private(set) var errorText: String?
    @Published private(set) var secondsLeft = 0
    @Published var autoRepeat = false {
        didSet { autoRepeat ? startAutoLoop() : stopAutoLoop() }
    }
    /// How long to listen for, in seconds.
    @Published var listenSeconds: Double = 8

    private let dictation = DictationManager.shared
    private var autoTask: Task<Void, Never>?
    /// The last transcript already folded into someone's record. Guards the
    /// "reuse whatever Listen captured this session" fallback from attaching
    /// the previous person's words to the next face.
    private var lastConsumedTranscript = ""

    private init() {}

    // MARK: Auto-repeat

    private func startAutoLoop() {
        autoTask?.cancel()
        autoTask = Task { @MainActor [weak self] in
            while let self, self.autoRepeat, !Task.isCancelled {
                await self.runOnce()
                guard self.autoRepeat else { break }
                // Breather between passes so the wearer can read the lens.
                for _ in 0..<40 {
                    guard self.autoRepeat, !Task.isCancelled else { break }
                    try? await Task.sleep(for: .milliseconds(100))
                }
            }
        }
    }

    private func stopAutoLoop() {
        autoTask?.cancel()
        autoTask = nil
    }

    // MARK: Dependencies

    private weak var glasses: GlassesManager?
    private weak var speech: SpeechManager?

    func bind(glasses: GlassesManager, speech: SpeechManager) {
        self.glasses = glasses
        self.speech = speech
    }

    // MARK: The loop

    func runOnce() async {
        guard !phase.isBusy, let glasses else { return }
        errorText = nil

        // 1 — one frame. Camera first, microphone afterwards: never both.
        phase = .framing
        statusLine = "Taking a frame…"
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()

        guard
            let image = await glasses.capturePhoto(),
            let jpeg = image.jpegData(compressionQuality: 0.7)
        else {
            phase = .idle
            statusLine = "Tap once. Recall does the rest."
            errorText = "Couldn't take a photo — check the camera source in Connect."
            await ReminiCards.shared.showGuidance(
                "No frame from the camera. Check the Connect tab."
            )
            return
        }
        lastCapture = image

        // Anything the Listen pipeline already captured this session, in case
        // they introduced themselves before the tap.
        let carried = dictation.transcript
            .trimmingCharacters(in: .whitespacesAndNewlines)

        // 2 — listen. The engine and its tap are already running; this only
        // opens a recognition task, so there is nothing for the camera to fight.
        phase = .listening
        let window = listenSeconds
        secondsLeft = Int(window)
        statusLine = "Listening — let them introduce themselves."
        let ticker = Task { @MainActor [weak self] in
            var left = Int(window)
            while left > 0, !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                left -= 1
                self?.secondsLeft = max(0, left)
            }
        }
        let fresh = await dictation.record(seconds: window)
        ticker.cancel()
        secondsLeft = 0

        var transcript = fresh
        if transcript.isEmpty, !carried.isEmpty, carried != lastConsumedTranscript {
            transcript = carried
        }
        if !transcript.isEmpty { lastConsumedTranscript = transcript }

        // 3 — who is it?
        phase = .thinking
        statusLine = "Matching against your network…"
        do {
            let recognition = try await RecallAPI.recognize(jpeg: jpeg)
            if recognition.matched, !recognition.name.isEmpty {
                await handleMatch(recognition, transcript: transcript, jpeg: jpeg)
            } else {
                await handleMiss(transcript: transcript, jpeg: jpeg)
            }
        } catch {
            errorText = error.localizedDescription
            statusLine = "Backend didn't answer."
            results.append(
                MeetResult(
                    kind: .failed, name: "Couldn't reach the graph", subhead: "",
                    headline: error.localizedDescription, lines: [], topics: [],
                    followups: [], transcript: transcript, placeholder: false
                )
            )
            await ReminiCards.shared.showGuidance("Backend unreachable — check Connect.")
        }

        phase = .idle
        if errorText == nil { statusLine = "Tap once. Recall does the rest." }
    }

    // MARK: Branches

    private func handleMatch(
        _ recognition: Recognition, transcript: String, jpeg: Data
    ) async {
        statusLine = "Recalling \(recognition.name)…"
        FaceCache.store(jpeg, for: recognition.name)

        // Pin the conversation to the face we just matched so a first name in
        // the transcript can't spawn a duplicate node.
        var receipt: IngestReceipt?
        if !transcript.isEmpty {
            receipt = try? await RecallAPI.ingest(
                transcript: transcript, speaker: recognition.name
            )
        }

        let card = (try? await RecallAPI.recall(name: recognition.name))
            ?? RecallCard.empty(name: recognition.name)

        let subhead = [recognition.role, recognition.org.isEmpty ? card.org : recognition.org]
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
        var lines = card.lines
        if lines.isEmpty, !recognition.spoken.isEmpty { lines = [recognition.spoken] }
        if lines.isEmpty, let receipt, !receipt.topics.isEmpty {
            lines = ["You talked about \(receipt.topics.joined(separator: ", "))."]
        }
        let followups = card.followups.isEmpty ? (receipt?.followups ?? []) : card.followups
        if lines.isEmpty, let owed = followups.first {
            lines = ["You owe them: \(owed)."]
        }
        if lines.isEmpty { lines = ["You've met before — no notes yet."] }

        let headline = card.headline.isEmpty ? recognition.title : card.headline

        results.append(
            MeetResult(
                kind: .recognised,
                name: recognition.name,
                subhead: subhead,
                headline: headline,
                lines: lines,
                topics: card.topics.isEmpty ? (receipt?.topics ?? []) : card.topics,
                followups: followups,
                transcript: transcript,
                placeholder: false
            )
        )
        statusLine = "Matched in \(recognition.elapsedMs) ms"

        speech?.speak(
            recognition.spoken.isEmpty
                ? ([headline] + lines.prefix(1)).joined(separator: ". ")
                : recognition.spoken
        )
        await ReminiCards.shared.showRecall(
            headline: recognition.name,
            subhead: subhead,
            lines: lines + followups.map { "You owe them: \($0)" },
            name: recognition.name
        )
    }

    /// A miss is never a dead end. The same frame is enrolled immediately —
    /// under the name the conversation gave us if there was one, otherwise a
    /// placeholder the user renames later from Network.
    private func handleMiss(transcript: String, jpeg: Data) async {
        statusLine = "New face — adding them to your network…"

        var receipt: IngestReceipt?
        var name = ""
        if !transcript.isEmpty {
            receipt = try? await RecallAPI.ingest(transcript: transcript)
            name = receipt?.saved.trimmingCharacters(in: .whitespaces) ?? ""
        }

        let isPlaceholder = name.isEmpty
        if isPlaceholder { name = FaceCache.nextPlaceholderName() }

        do {
            let outcome = try await RecallAPI.enrollOutcome(
                name: name,
                photoJpeg: jpeg,
                relationship: isPlaceholder ? "just met" : "",
                // Only carry the raw line when ingest didn't already structure
                // it, so auto-enroll never clobbers better data.
                notes: receipt == nil ? String(transcript.prefix(300)) : ""
            )

            guard outcome.enrolled else {
                // "no face detected" is guidance, not a failure banner.
                statusLine = "No face in that frame."
                results.append(
                    MeetResult(
                        kind: .guidance,
                        name: "No face in that frame",
                        subhead: "",
                        headline: outcome.friendlyReason,
                        lines: transcript.isEmpty
                            ? []
                            : ["What they said was still saved to the graph."],
                        topics: receipt?.topics ?? [],
                        followups: receipt?.followups ?? [],
                        transcript: transcript,
                        placeholder: false
                    )
                )
                await ReminiCards.shared.showGuidance(outcome.friendlyReason)
                speech?.speak("Couldn't see a face. Get a little closer.")
                return
            }

            FaceCache.store(jpeg, for: outcome.name)
            if isPlaceholder { FaceCache.markPlaceholder(outcome.name) }

            var lines: [String] = []
            if let receipt, !receipt.topics.isEmpty {
                lines.append("Talked about \(receipt.topics.joined(separator: ", ")).")
            }
            if let org = receipt?.org, !org.isEmpty {
                lines.append("Works at \(org).")
            }
            if let owed = receipt?.followups.first {
                lines.append("You owe them: \(owed).")
            }
            if lines.isEmpty {
                lines.append(
                    isPlaceholder
                        ? "Saved as \(outcome.name) — rename them in Network."
                        : "Face saved. Recall will know them next time."
                )
            }

            let subhead = [receipt?.org ?? ""].filter { !$0.isEmpty }.joined()

            results.append(
                MeetResult(
                    kind: outcome.attachedToExisting ? .merged : .newFace,
                    name: outcome.name,
                    subhead: subhead,
                    headline: outcome.attachedToExisting
                        ? "Face linked to \(outcome.name)"
                        : "New face — added as \(outcome.name)",
                    lines: lines,
                    topics: receipt?.topics ?? [],
                    followups: receipt?.followups ?? [],
                    transcript: transcript,
                    placeholder: isPlaceholder
                )
            )
            statusLine = outcome.attachedToExisting
                ? "Face linked to \(outcome.name)."
                : "\(outcome.name) added."

            speech?.speak(
                isPlaceholder
                    ? "New face. Added to your network. Rename them later."
                    : "New face. \(outcome.name), added to your network."
            )
            await ReminiCards.shared.showNewFace(
                name: outcome.name,
                detail: lines.first ?? "",
                merged: outcome.attachedToExisting
            )
        } catch {
            errorText = error.localizedDescription
            results.append(
                MeetResult(
                    kind: .failed, name: "Couldn't add that face", subhead: "",
                    headline: error.localizedDescription, lines: [], topics: [],
                    followups: [], transcript: transcript, placeholder: false
                )
            )
            await ReminiCards.shared.showGuidance("Couldn't save that face — check Connect.")
        }
    }

    func clearResults() {
        results.removeAll()
        lastCapture = nil
        errorText = nil
    }
}

// MARK: - View

/// The primary control. One big button that captures a frame AND ~8 seconds of
/// speech, recognises the face, auto-enrols on a miss, folds the conversation
/// into the graph, and pushes the answer to the lens, the ear and the app.
struct MeetView: View {
    @EnvironmentObject private var glasses: GlassesManager
    @EnvironmentObject private var speech: SpeechManager
    @ObservedObject private var engine = MeetEngine.shared
    @ObservedObject private var dictation = DictationManager.shared
    @ObservedObject private var cards = ReminiCards.shared

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    statusHeader
                    meetButton.padding(.top, 4)
                    Text(engine.statusLine)
                        .font(.rcCaption)
                        .foregroundStyle(Color.rcTextDim)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 16)

                    controls
                    livePanel

                    if !dictation.isUsable {
                        permissionPanel
                    }
                    if let error = engine.errorText ?? dictation.errorText {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .font(.rcCaption)
                            .foregroundStyle(Color.rcAlert)
                            .panel()
                    }

                    resultsList
                }
                .padding(20)
            }
            .recallScreen()
            .navigationTitle("Meet")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    WordmarkLockup(size: 17)
                }
            }
        }
        .onAppear {
            engine.bind(glasses: glasses, speech: speech)
            DictationManager.shared.prime()
        }
    }

    // MARK: Header

    private var statusHeader: some View {
        HStack(spacing: 10) {
            pill(
                text: cards.connected ? "lens: connected" : "lens: idle",
                on: cards.connected,
                icon: "eyeglasses"
            )
            pill(
                text: dictation.engineRunning ? "mic: live" : "mic: off",
                on: dictation.engineRunning && dictation.isUsable,
                icon: "mic.fill"
            )
            pill(
                text: glasses.isConnected ? "cam: glasses" : "cam: phone",
                on: glasses.isConnected,
                icon: "camera.fill"
            )
        }
        .frame(maxWidth: .infinity)
    }

    private func pill(text: String, on: Bool, icon: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon).font(.system(size: 9, weight: .bold))
            Text(text)
                .font(.system(size: 11, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .foregroundStyle(on ? Color.rcAccent : Color.rcTextDim)
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background((on ? Color.rcAccent : Color.rcTextDim).opacity(0.12))
        .clipShape(Capsule())
    }

    // MARK: The button

    private var meetButton: some View {
        Button {
            Task { await engine.runOnce() }
        } label: {
            ZStack {
                Circle()
                    .fill(Color.rcAccent.opacity(0.16))
                    .frame(width: 250, height: 250)
                    .scaleEffect(
                        engine.phase == .listening ? 1 + dictation.level * 0.3 : 0.85
                    )
                    .opacity(engine.phase == .listening ? 1 : 0)
                    .animation(.easeOut(duration: 0.15), value: dictation.level)

                Circle()
                    .fill(Color.rcAccent)
                    .shadow(color: Color.rcAccent.opacity(0.4), radius: 28, y: 10)
                    .frame(width: 210, height: 210)

                Circle()
                    .stroke(Color.white.opacity(0.25), lineWidth: 1.5)
                    .frame(width: 186, height: 186)

                VStack(spacing: 7) {
                    Image(systemName: buttonIcon)
                        .font(.system(size: 38, weight: .medium))
                    Text(buttonTitle)
                        .font(.rcDisplay(23, .bold))
                    if engine.phase == .listening, engine.secondsLeft > 0 {
                        Text("\(engine.secondsLeft)s")
                            .font(.system(size: 14, weight: .semibold))
                            .opacity(0.85)
                    }
                }
                .foregroundStyle(.white)
            }
            .frame(height: 250)
            .scaleEffect(engine.phase.isBusy ? 0.97 : 1)
            .animation(.spring(duration: 0.4), value: engine.phase)
        }
        .buttonStyle(.plain)
        .disabled(engine.phase.isBusy)
        .accessibilityLabel("Meet — capture a face and what they say, then recall or add them")
    }

    private var buttonIcon: String {
        switch engine.phase {
        case .idle: return "person.crop.circle.badge.questionmark"
        case .framing: return "camera.fill"
        case .listening: return "waveform"
        case .thinking: return "sparkles"
        }
    }

    private var buttonTitle: String {
        switch engine.phase {
        case .idle: return "Meet"
        case .framing: return "Framing"
        case .listening: return "Listening"
        case .thinking: return "Recalling"
        }
    }

    // MARK: Controls

    private var controls: some View {
        VStack(spacing: 12) {
            Toggle(isOn: $engine.autoRepeat) {
                Label("Keep going — repeat automatically", systemImage: "arrow.triangle.2.circlepath")
                    .font(.rcBodyMedium)
                    .foregroundStyle(Color.rcText)
            }
            .tint(.rcAccent)

            Divider().overlay(Color.rcLine)

            Toggle(isOn: $speech.speakAloud) {
                Label("Speak the recall in my ear", systemImage: "waveform")
                    .font(.rcBodyMedium)
                    .foregroundStyle(Color.rcText)
            }
            .tint(.rcAccent)

            Divider().overlay(Color.rcLine)

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    SectionLabel("Listen window")
                    Spacer()
                    Text("\(Int(engine.listenSeconds))s")
                        .font(.rcLabel)
                        .foregroundStyle(Color.rcTextDim)
                }
                Slider(value: $engine.listenSeconds, in: 4...20, step: 1)
                    .tint(.rcAccent)
            }
        }
        .panel()
    }

    // MARK: Live transcript

    private var livePanel: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                SectionLabel("Heard live", icon: "text.quote")
                Spacer()
                if engine.phase == .listening {
                    HStack(spacing: 5) {
                        Circle().fill(Color.rcAlert).frame(width: 7, height: 7)
                        Text("LIVE").font(.rcLabel).foregroundStyle(Color.rcAlert)
                    }
                }
            }
            Text(
                dictation.transcript.isEmpty
                    ? "Whatever they say lands here as they say it."
                    : dictation.transcript
            )
            .font(.system(size: 16))
            .foregroundStyle(
                dictation.transcript.isEmpty ? Color.rcTextDim : Color.rcText
            )
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, minHeight: 54, alignment: .topLeading)
            .animation(.easeOut(duration: 0.2), value: dictation.transcript)

            Text(dictation.diagnostic)
                .font(.system(size: 11))
                .foregroundStyle(Color.rcTextDim.opacity(0.8))

            if !cards.lensStatus.isEmpty {
                Text(cards.lensStatus)
                    .font(.system(size: 11))
                    .foregroundStyle(
                        cards.lastSendFailed ? Color.rcAlert : Color.rcTextDim.opacity(0.8)
                    )
            }
        }
        .panel()
    }

    private var permissionPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel("Microphone", icon: "exclamationmark.triangle.fill")
            Text(dictation.authSummary)
                .font(.rcCaption)
                .foregroundStyle(Color.rcAlert)
                .fixedSize(horizontal: false, vertical: true)
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            .buttonStyle(GhostButtonStyle(tint: .rcAccent))
        }
        .panel()
    }

    // MARK: Results

    private var resultsList: some View {
        VStack(alignment: .leading, spacing: 14) {
            if engine.results.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "person.crop.rectangle.badge.plus")
                        .font(.system(size: 26))
                        .foregroundStyle(Color.rcAccent)
                    Text("One tap does everything.")
                        .font(.rcBodyMedium)
                        .foregroundStyle(Color.rcText)
                    Text("Recall grabs a frame, listens while they introduce themselves, and either hands you their recall card — or adds them to your network on the spot. It never comes back empty.")
                        .font(.rcCaption)
                        .foregroundStyle(Color.rcTextDim)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
                .padding(.horizontal, 8)
            } else {
                HStack {
                    SectionLabel("This session", icon: "clock.arrow.circlepath")
                    Spacer()
                    Button("Clear") { engine.clearResults() }
                        .font(.rcLabel)
                        .tint(.rcTextDim)
                }
                ForEach(engine.results.reversed()) { result in
                    MeetResultCard(result: result)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
        }
        .animation(.spring(duration: 0.45), value: engine.results.count)
    }
}

// MARK: - Result card

struct MeetResultCard: View {
    let result: MeetResult

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(result.name)
                        .font(.rcDisplay(22))
                        .foregroundStyle(Color.rcText)
                    if !result.subhead.isEmpty {
                        Text(result.subhead)
                            .font(.rcCaption.weight(.medium))
                            .foregroundStyle(Color.rcAccent)
                    }
                }
                Spacer()
                Chip(text: result.badge, tint: result.badgeTint, filled: true)
            }

            if !result.headline.isEmpty {
                Text(result.headline)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Color.rcText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !result.lines.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    SectionLabel("Say next", icon: "arrow.turn.down.right")
                    ForEach(Array(result.lines.enumerated()), id: \.offset) { _, line in
                        HStack(alignment: .firstTextBaseline, spacing: 9) {
                            Circle()
                                .fill(Color.rcAccent)
                                .frame(width: 5, height: 5)
                                .offset(y: -2)
                            Text(line)
                                .font(.rcBody)
                                .foregroundStyle(Color.rcText)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }

            if !result.topics.isEmpty {
                FlowChips(items: result.topics)
            }

            if !result.followups.isEmpty {
                VStack(alignment: .leading, spacing: 7) {
                    SectionLabel("You owe them", icon: "checklist")
                    ForEach(Array(result.followups.enumerated()), id: \.offset) { _, item in
                        Text("• \(item)")
                            .font(.rcCaption)
                            .foregroundStyle(Color.rcTextDim)
                    }
                }
            }

            if result.placeholder {
                Label(
                    "Auto-named. Open Network → \(result.name) to give them their real name.",
                    systemImage: "pencil.and.outline"
                )
                .font(.system(size: 12.5))
                .foregroundStyle(Color.rcAccent)
                .fixedSize(horizontal: false, vertical: true)
            }

            if !result.transcript.isEmpty {
                DisclosureGroup {
                    Text(result.transcript)
                        .font(.system(size: 13))
                        .foregroundStyle(Color.rcTextDim)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 6)
                } label: {
                    Text("What I heard")
                        .font(.rcLabel)
                        .foregroundStyle(Color.rcTextDim)
                }
                .tint(.rcTextDim)
            }

            Text(result.date, style: .time)
                .font(.system(size: 12))
                .foregroundStyle(Color.rcTextDim)
        }
        .panel()
    }
}
